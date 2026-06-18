#!/usr/bin/env bash
#
# diagnose-lex-deepgram-secret.sh
#
# Diagnose the Lex V2 error:
#   "Invalid Bot Configuration: The secret could not be accessed.
#    Please check the resource policy on the secret ..."
#
# It checks, for a given bot-alias ARN and secret:
#   1. The secret's KMS key is a CUSTOMER-MANAGED CMK (not the default aws/secretsmanager).
#   2. The secret's resource policy allows lex.amazonaws.com:GetSecretValue
#      with the matching SourceAccount and a SourceArn covering the bot alias.
#   3. The CMK key policy allows lex.amazonaws.com:Decrypt via Secrets Manager.
#
# Run in AWS CloudShell. Read-only: it does not change anything.
#
set -euo pipefail

LEX_ALIAS_ARN=""
SECRET_ID=""
REGION=""

err()  { echo "ERROR: $*" >&2; exit 1; }
ok()   { echo "  [ OK ]  $*"; }
bad()  { echo "  [FAIL]  $*"; }
warn() { echo "  [WARN]  $*"; }
hdr()  { echo; echo "=== $* ==="; }

usage() {
  cat <<EOF
Usage: $0 --lex-arn <bot-alias-arn> --secret-id <name-or-arn> [--region <reg>]

  --lex-arn    Bot-alias ARN from the Connect GetUserInput step, e.g.
               arn:aws:lex:us-west-2:991727053196:bot-alias/E9LXXC9XGT/TSTALIASID
  --secret-id  The Secrets Manager secret name or ARN configured on the bot locale.
  --region     Optional; defaults to the region in the ARN.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lex-arn)   LEX_ALIAS_ARN="${2:-}"; shift 2 ;;
    --secret-id) SECRET_ID="${2:-}"; shift 2 ;;
    --region)    REGION="${2:-}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) err "Unknown argument: $1" ;;
  esac
done

[[ -n "$LEX_ALIAS_ARN" ]] || { usage; err "--lex-arn is required"; }
[[ -n "$SECRET_ID" ]]     || { usage; err "--secret-id is required"; }
command -v aws >/dev/null || err "aws CLI not found"
command -v jq  >/dev/null || err "jq not found"

IFS=':' read -r _arn PARTITION SERVICE ARN_REGION ACCOUNT_ID RESOURCE <<<"$LEX_ALIAS_ARN"
[[ "$SERVICE" == "lex" ]] || err "Not a Lex ARN: $LEX_ALIAS_ARN"
RES_PATH="${RESOURCE#*/}"           # E9LXXC9XGT/TSTALIASID
BOT_ID="${RES_PATH%%/*}"
REGION="${REGION:-$ARN_REGION}"

echo "Bot-alias ARN : $LEX_ALIAS_ARN"
echo "Account       : $ACCOUNT_ID"
echo "Region        : $REGION"
echo "Bot id        : $BOT_ID"
echo "Secret id     : $SECRET_ID"

# ----------------------------------------------------------------------------
# 1. Secret + KMS key
# ----------------------------------------------------------------------------
hdr "1. Secret & KMS encryption"
DESC=$(aws secretsmanager describe-secret --region "$REGION" --secret-id "$SECRET_ID" 2>/dev/null) \
  || err "Cannot describe secret '$SECRET_ID'. Wrong name/ARN or no permission."

SECRET_ARN=$(echo "$DESC" | jq -r '.ARN')
KMS_KEY=$(echo "$DESC" | jq -r '.KmsKeyId // ""')
echo "  Secret ARN : $SECRET_ARN"
echo "  KmsKeyId   : ${KMS_KEY:-<none / default aws/secretsmanager>}"

CMK_KEY_ID=""
if [[ -z "$KMS_KEY" || "$KMS_KEY" == "alias/aws/secretsmanager" ]]; then
  bad "Secret uses the DEFAULT AWS-managed key. Lex V2 does NOT support this."
  bad "      -> You must re-encrypt the secret with a customer-managed symmetric CMK."
else
  # Resolve to a key id and verify it is CUSTOMER managed.
  KEY_META=$(aws kms describe-key --region "$REGION" --key-id "$KMS_KEY" 2>/dev/null || echo "")
  if [[ -z "$KEY_META" ]]; then
    warn "Could not describe KMS key $KMS_KEY (check permissions)."
  else
    MGR=$(echo "$KEY_META" | jq -r '.KeyMetadata.KeyManager')
    SPEC=$(echo "$KEY_META" | jq -r '.KeyMetadata.KeySpec // .KeyMetadata.CustomerMasterKeySpec')
    CMK_KEY_ID=$(echo "$KEY_META" | jq -r '.KeyMetadata.KeyId')
    if [[ "$MGR" == "CUSTOMER" ]]; then ok "KMS key is CUSTOMER managed."; else bad "KMS key is AWS managed ($MGR). Must be CUSTOMER managed."; fi
    if [[ "$SPEC" == "SYMMETRIC_DEFAULT" ]]; then ok "KMS key is symmetric."; else bad "KMS key spec is $SPEC. Must be SYMMETRIC_DEFAULT."; fi
  fi
fi

# ----------------------------------------------------------------------------
# 2. Secret resource policy
# ----------------------------------------------------------------------------
hdr "2. Secret resource policy"
RP=$(aws secretsmanager get-resource-policy --region "$REGION" --secret-id "$SECRET_ARN" \
       --query 'ResourcePolicy' --output text 2>/dev/null || echo "")

if [[ -z "$RP" || "$RP" == "None" ]]; then
  bad "No resource policy attached. Lex cannot access the secret."
else
  echo "$RP" | jq .
  echo
  echo "$RP" | grep -q "lex.amazonaws.com" \
    && ok "Principal lex.amazonaws.com present." \
    || bad "Principal lex.amazonaws.com NOT found."
  echo "$RP" | grep -q "GetSecretValue" \
    && ok "Action secretsmanager:GetSecretValue present." \
    || bad "Action secretsmanager:GetSecretValue NOT found."
  echo "$RP" | grep -q "$ACCOUNT_ID" \
    && ok "aws:SourceAccount $ACCOUNT_ID present." \
    || warn "aws:SourceAccount $ACCOUNT_ID not found (check the condition)."
  if echo "$RP" | grep -Eq "bot-alias/(${BOT_ID}|\*)/"; then
    ok "aws:SourceArn pattern covers bot-alias/${BOT_ID}/..."
  else
    bad "aws:SourceArn does NOT cover bot-alias/${BOT_ID}/*. This is likely the cause."
    echo "        Expected something like:"
    echo "        arn:${PARTITION}:lex:${REGION}:${ACCOUNT_ID}:bot-alias/${BOT_ID}/*"
  fi
fi

# ----------------------------------------------------------------------------
# 3. KMS key policy (only if a CMK is in use)
# ----------------------------------------------------------------------------
hdr "3. KMS key policy (Lex decrypt permission)"
if [[ -z "$CMK_KEY_ID" ]]; then
  warn "Skipped: no customer-managed CMK resolved (fix section 1 first)."
else
  KP=$(aws kms get-key-policy --region "$REGION" --key-id "$CMK_KEY_ID" \
         --policy-name default --query 'Policy' --output text 2>/dev/null || echo "")
  if [[ -z "$KP" ]]; then
    warn "Could not read key policy for $CMK_KEY_ID."
  else
    echo "$KP" | jq .
    echo
    if echo "$KP" | grep -q "lex.amazonaws.com" && echo "$KP" | grep -qi "Decrypt"; then
      ok "Key policy references lex.amazonaws.com with Decrypt."
    else
      bad "Key policy does NOT grant lex.amazonaws.com kms:Decrypt. Lex cannot decrypt the secret."
    fi
  fi
fi

hdr "Summary"
cat <<EOF
If any [FAIL] above relates to the KMS key (default key / no Lex decrypt) or the
resource policy (missing lex principal / wrong SourceArn), that is the cause of:
  "The secret could not be accessed."

Fix by re-running the setup script against THIS secret and bot alias:

  ./setup-lex-deepgram-secret.sh \\
     --lex-arn $LEX_ALIAS_ARN \\
     --secret-name $(basename "$SECRET_ARN" | sed 's/-[A-Za-z0-9]*$//') \\
     --api-key '<your-deepgram-api-key>'

(That switches the secret to a customer-managed CMK, sets the KMS key policy,
 and attaches the correct resource policy. Then make sure the bot locale's
 Deepgram 'Secret ARN' points to: $SECRET_ARN)
EOF
