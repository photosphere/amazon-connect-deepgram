#!/usr/bin/env bash
#
# setup-lex-deepgram-secret.sh
#
# Create (or update) an AWS Secrets Manager secret that holds a Deepgram API key
# so that an Amazon Lex V2 bot can use Deepgram as its speech recognition model.
#
# It follows the official setup guide:
#   https://docs.aws.amazon.com/lexv2/latest/dg/customizing-speech-deepgram-setup.html
#
# What it does, idempotently:
#   1. Parses the supplied Lex ARN (bot or bot-alias) to derive region / account / bot id.
#   2. Ensures a customer-managed, symmetric KMS key exists (the default AWS-managed
#      key is NOT supported by Lex). One is auto-created via an alias unless you pass
#      your own --kms-key-id.
#   3. Stores the API key as the JSON value {"apiToken":"<key>"} in Secrets Manager.
#      - Creates the secret if it does not exist.
#      - Updates the value (and KMS key) if it already exists.
#   4. Attaches a resource policy that lets Lex (lex.amazonaws.com) read the secret,
#      scoped to your account and the bot's alias ARNs.
#
# Designed to run as-is in AWS CloudShell (bash, aws cli v2 and jq are preinstalled).
#
set -euo pipefail

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------
LEX_ARN=""
API_KEY=""
SECRET_NAME=""
KMS_KEY_ID=""              # user supplied CMK (id, arn or alias/<name>); empty = auto
REGION=""                  # overrides region parsed from the ARN
AUTO_KMS_ALIAS="alias/lex-deepgram-apitoken"
CREATED_KMS=0

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
err()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ">>> $*"; }

usage() {
  cat <<EOF
Usage: $0 --lex-arn <arn> --api-key <deepgram_api_key> [options]

Required:
  --lex-arn   <arn>   Lex V2 bot or bot-alias ARN, e.g.
                      arn:aws:lex:us-east-1:111122223333:bot/ABCDEFGHIJ
  --api-key   <key>   Your Deepgram API key.

Optional:
  --secret-name <name>  Secrets Manager secret name.
                        Default: lex-deepgram-apitoken-<botId>
  --kms-key-id  <id>    Existing customer-managed symmetric KMS key
                        (key id, key ARN, or alias/<name>). If omitted a key is
                        created/reused via the alias '${AUTO_KMS_ALIAS}'.
  --region      <reg>   AWS region (defaults to the region in the Lex ARN).
  -h, --help            Show this help.

Example:
  $0 --lex-arn arn:aws:lex:us-east-1:111122223333:bot/ABCDEFGHIJ \\
     --api-key 'dg_xxxxxxxxxxxxxxxxxxxxxxxxxxxx'
EOF
}

# ----------------------------------------------------------------------------
# Parse arguments
# ----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lex-arn)     LEX_ARN="${2:-}"; shift 2 ;;
    --api-key)     API_KEY="${2:-}"; shift 2 ;;
    --secret-name) SECRET_NAME="${2:-}"; shift 2 ;;
    --kms-key-id)  KMS_KEY_ID="${2:-}"; shift 2 ;;
    --region)      REGION="${2:-}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) err "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ -n "$LEX_ARN" ]] || { usage; err "--lex-arn is required"; }
[[ -n "$API_KEY" ]] || { usage; err "--api-key is required"; }
command -v aws >/dev/null || err "aws CLI not found"
command -v jq  >/dev/null || err "jq not found"

# ----------------------------------------------------------------------------
# Parse the Lex ARN: arn:partition:lex:region:account:resource
# resource is bot/<id>  OR  bot-alias/<botId>/<aliasId>
# ----------------------------------------------------------------------------
IFS=':' read -r _arn PARTITION SERVICE ARN_REGION ACCOUNT_ID RESOURCE <<<"$LEX_ARN"
[[ "$_arn" == "arn" && "$SERVICE" == "lex" ]] || err "Not a valid Lex ARN: $LEX_ARN"
[[ -n "$ACCOUNT_ID" && -n "$RESOURCE" ]]      || err "Could not parse account/resource from ARN: $LEX_ARN"

RES_TYPE="${RESOURCE%%/*}"          # bot | bot-alias
RES_PATH="${RESOURCE#*/}"           # <id>  or  <botId>/<aliasId>
case "$RES_TYPE" in
  bot)        BOT_ID="$RES_PATH" ;;
  bot-alias)  BOT_ID="${RES_PATH%%/*}" ;;
  *) err "ARN must be a bot or bot-alias ARN, got resource type: $RES_TYPE" ;;
esac
[[ -n "$BOT_ID" ]] || err "Could not derive bot id from ARN: $LEX_ARN"

REGION="${REGION:-$ARN_REGION}"
[[ -n "$REGION" ]] || err "Region missing in ARN; pass --region"

SECRET_NAME="${SECRET_NAME:-lex-deepgram-apitoken-${BOT_ID}}"

# ARN pattern Lex will use as aws:SourceArn (all aliases of this bot)
BOT_ALIAS_SOURCE_ARN="arn:${PARTITION}:lex:${REGION}:${ACCOUNT_ID}:bot-alias/${BOT_ID}/*"

info "Region        : $REGION"
info "Account       : $ACCOUNT_ID"
info "Bot id        : $BOT_ID"
info "Secret name   : $SECRET_NAME"
info "Lex SourceArn : $BOT_ALIAS_SOURCE_ARN"

# ----------------------------------------------------------------------------
# 1. Ensure a customer-managed symmetric KMS key
# ----------------------------------------------------------------------------
ensure_kms_key() {
  if [[ -n "$KMS_KEY_ID" ]]; then
    info "Using supplied KMS key: $KMS_KEY_ID"
    info "  NOTE: make sure its key policy lets lex.amazonaws.com call kms:Decrypt"
    info "        via service secretsmanager.${REGION}.amazonaws.com."
    return
  fi

  # Look for our managed alias first (idempotent reuse).
  local existing
  existing=$(aws kms list-aliases --region "$REGION" \
              --query "Aliases[?AliasName=='${AUTO_KMS_ALIAS}'].TargetKeyId | [0]" \
              --output text 2>/dev/null || echo "None")

  if [[ "$existing" != "None" && -n "$existing" ]]; then
    KMS_KEY_ID="$existing"
    info "Reusing KMS key behind ${AUTO_KMS_ALIAS}: $KMS_KEY_ID"
  else
    info "Creating customer-managed symmetric KMS key..."
    KMS_KEY_ID=$(aws kms create-key \
        --region "$REGION" \
        --description "Lex V2 Deepgram apiToken secret encryption" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --query 'KeyMetadata.KeyId' --output text)
    aws kms create-alias --region "$REGION" \
        --alias-name "$AUTO_KMS_ALIAS" --target-key-id "$KMS_KEY_ID"
    CREATED_KMS=1
    info "Created KMS key $KMS_KEY_ID (alias ${AUTO_KMS_ALIAS})"
  fi

  # Ensure the key policy lets Lex decrypt via Secrets Manager.
  local key_policy
  key_policy=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Id": "lex-deepgram-key-policy",
  "Statement": [
    {
      "Sid": "EnableRootAccountAdmin",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:${PARTITION}:iam::${ACCOUNT_ID}:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowLexDecryptViaSecretsManager",
      "Effect": "Allow",
      "Principal": { "Service": "lex.amazonaws.com" },
      "Action": [ "kms:Decrypt", "kms:DescribeKey" ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "secretsmanager.${REGION}.amazonaws.com",
          "aws:SourceAccount": "${ACCOUNT_ID}"
        }
      }
    }
  ]
}
JSON
)
  aws kms put-key-policy --region "$REGION" \
      --key-id "$KMS_KEY_ID" --policy-name default \
      --policy "$key_policy"
  info "KMS key policy updated to allow Lex decryption."
}

ensure_kms_key

# ----------------------------------------------------------------------------
# 2. Create or update the secret value: {"apiToken":"<key>"}
# ----------------------------------------------------------------------------
SECRET_STRING=$(jq -nc --arg t "$API_KEY" '{apiToken: $t}')

if aws secretsmanager describe-secret --region "$REGION" --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
  info "Secret '$SECRET_NAME' exists - updating value and KMS key..."
  aws secretsmanager update-secret --region "$REGION" \
      --secret-id "$SECRET_NAME" \
      --kms-key-id "$KMS_KEY_ID" >/dev/null
  aws secretsmanager put-secret-value --region "$REGION" \
      --secret-id "$SECRET_NAME" \
      --secret-string "$SECRET_STRING" >/dev/null
  info "Secret updated."
else
  info "Secret '$SECRET_NAME' not found - creating..."
  aws secretsmanager create-secret --region "$REGION" \
      --name "$SECRET_NAME" \
      --description "Deepgram API key for Amazon Lex V2 bot ${BOT_ID}" \
      --kms-key-id "$KMS_KEY_ID" \
      --secret-string "$SECRET_STRING" >/dev/null
  info "Secret created."
fi

SECRET_ARN=$(aws secretsmanager describe-secret --region "$REGION" \
              --secret-id "$SECRET_NAME" --query 'ARN' --output text)

# ----------------------------------------------------------------------------
# 3. Attach the resource policy that lets Lex read the secret
# ----------------------------------------------------------------------------
RESOURCE_POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LexTrust",
      "Effect": "Allow",
      "Principal": { "Service": "lex.amazonaws.com" },
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "*",
      "Condition": {
        "StringEquals": { "aws:SourceAccount": "${ACCOUNT_ID}" },
        "ArnLike": { "aws:SourceArn": "${BOT_ALIAS_SOURCE_ARN}" }
      }
    }
  ]
}
JSON
)

info "Attaching resource policy for Lex..."
aws secretsmanager put-resource-policy --region "$REGION" \
    --secret-id "$SECRET_ARN" \
    --resource-policy "$RESOURCE_POLICY" \
    --block-public-policy >/dev/null

# ----------------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------------
echo
echo "============================================================"
echo "Deepgram secret is ready."
echo "  Secret name : $SECRET_NAME"
echo "  Secret ARN  : $SECRET_ARN"
echo "  KMS key     : $KMS_KEY_ID"
[[ "$CREATED_KMS" -eq 1 ]] && echo "  (a new customer-managed KMS key was created and is billable)"
echo
echo "Next: in the Lex V2 console open your bot locale, set Speech model"
echo "preference to 'Deepgram', and paste the Secret ARN above into the"
echo "'Secret ARN' field. (Optionally set a Deepgram Model ID.)"
echo "============================================================"
