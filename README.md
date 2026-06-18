# Amazon Lex V2 + Deepgram 集成工具集

本仓库提供在 **AWS CloudShell** 中配置和排查 Amazon Lex V2 使用 Deepgram 语音识别（ASR）的脚本与文档。核心目标：把 Deepgram API Key 安全地存入 **AWS Secrets Manager**，让 Lex V2 / Amazon Connect 能正常调用 Deepgram。

脚本严格遵循官方文档：
[Setting up Deepgram speech model preference](https://docs.aws.amazon.com/lexv2/latest/dg/customizing-speech-deepgram-setup.html)

---

## 文件清单

| 文件 | 作用 |
|------|------|
| `setup-lex-deepgram-secret.sh` | 创建/更新存有 Deepgram API Key 的 Secrets Manager 密钥，并配置 KMS 与资源策略 |
| `diagnose-lex-deepgram-secret.sh` | 排查 “The secret could not be accessed” 等密钥访问报错 |
| `deepgram-models-de-it.md` | Deepgram 支持德语 / 意大利语 ASR 的 Model ID 说明 |
| `README.md` | 本文档 |

---

## 前置条件

- 在 **AWS CloudShell** 中运行（已预装 `aws` CLI v2 与 `jq`）。
- 当前身份具备以下权限：
  - Secrets Manager：`CreateSecret` / `UpdateSecret` / `PutSecretValue` / `DescribeSecret` / `GetResourcePolicy` / `PutResourcePolicy` / `ListSecrets`
  - KMS：`CreateKey` / `CreateAlias` / `ListAliases` / `DescribeKey` / `GetKeyPolicy` / `PutKeyPolicy`
- 已从 [Deepgram 控制台](https://console.deepgram.com/) 获取 API Key。

```bash
chmod +x setup-lex-deepgram-secret.sh diagnose-lex-deepgram-secret.sh
```

---

## 一、配置密钥：`setup-lex-deepgram-secret.sh`

### 功能（幂等执行）

1. **解析 Lex ARN**：从 bot 或 bot-alias ARN 中自动提取 region、account ID、bot ID。
2. **准备客户托管 KMS 密钥**：官方要求必须使用**客户托管的对称 KMS 密钥**，默认的 AWS 托管密钥（`aws/secretsmanager`）不被 Lex 支持。脚本通过别名 `alias/lex-deepgram-apitoken` 自动创建或复用密钥（也可用 `--kms-key-id` 指定自有密钥）。
3. **设置 KMS 密钥策略**：为脚本管理的密钥附加策略，允许 `lex.amazonaws.com` 通过 `secretsmanager.<region>.amazonaws.com` 调用 `kms:Decrypt`（官方文档未提及这一步，是常见漏配点）。
4. **写入密钥**：按官方要求存储为单个键值对 `{"apiToken":"<你的密钥>"}`。
   - 不存在 → 创建（`create-secret`）
   - 已存在 → 更新密钥值与 KMS 密钥（`update-secret` + `put-secret-value`）
5. **附加资源策略**：允许 `lex.amazonaws.com` 调用 `secretsmanager:GetSecretValue`，并通过 `aws:SourceAccount` 与 `aws:SourceArn`（收紧到该 bot 的别名 `bot-alias/<botId>/*`）限制范围。

执行成功后输出 **Secret ARN**，用于在 Lex 控制台填写。

### 用法

```bash
./setup-lex-deepgram-secret.sh \
  --lex-arn arn:aws:lex:us-west-2:991727053196:bot-alias/E9LXXC9XGT/TSTALIASID \
  --api-key 'dg_xxxxxxxxxxxxxxxxxxxxxxxx'
```

### 参数

| 参数 | 必填 | 说明 |
|------|------|------|
| `--lex-arn` | 是 | Lex V2 的 bot 或 bot-alias ARN |
| `--api-key` | 是 | Deepgram API Key |
| `--secret-name` | 否 | 密钥名称，默认 `lex-deepgram-apitoken-<botId>`。**修复已有配置时，必须填 bot 当前指向的密钥名** |
| `--kms-key-id` | 否 | 自有客户托管对称 KMS 密钥（key id / ARN / `alias/<name>`）。不填则自动创建或复用 |
| `--region` | 否 | AWS 区域，默认取 ARN 中的区域 |
| `-h`, `--help` | 否 | 显示帮助 |

> ⚠️ 若使用 `--kms-key-id` 指定自有密钥，脚本**不会**自动修改该密钥策略，仅给出提示——你需自行确保其密钥策略允许 Lex 解密。

### 在 Lex 控制台关联

1. 打开 Lex V2 控制台，进入对应 bot 的语言区域（locale）。
2. **Speech model preference** 选择 **Deepgram**。
3. **Secret ARN** 粘贴脚本输出的 ARN。
4. **Model ID**（可选）填入模型，例如德语/意大利语可用 `nova-2` 或 `nova-3`（详见 `deepgram-models-de-it.md`）。
5. 保存。

---

## 二、排查访问报错：`diagnose-lex-deepgram-secret.sh`

当 Lex / Connect 调用报错：

```
Invalid Bot Configuration: The secret could not be accessed.
Please check the resource policy on the secret and try your request again.
```

用此脚本（**只读，不修改任何资源**）检查三项根因：

1. 密钥是否使用**客户托管对称 CMK**（而非默认 AWS 托管密钥）。
2. 密钥**资源策略**是否允许 `lex.amazonaws.com:GetSecretValue`，且 `SourceAccount` / `SourceArn` 覆盖该 bot 别名。
3. **KMS 密钥策略**是否允许 `lex.amazonaws.com:Decrypt`。

### 用法

```bash
./diagnose-lex-deepgram-secret.sh \
  --lex-arn arn:aws:lex:us-west-2:991727053196:bot-alias/E9LXXC9XGT/TSTALIASID \
  --secret-id DemoDeepgramKey
```

| 参数 | 必填 | 说明 |
|------|------|------|
| `--lex-arn` | 是 | Connect `GetUserInput` 日志里的 bot-alias ARN |
| `--secret-id` | 是 | 密钥的**友好名**或**完整 ARN** |
| `--region` | 否 | AWS 区域，默认取 ARN 中的区域 |

> ⚠️ `--secret-id` 要传**友好名**（如 `DemoDeepgramKey`）或**完整 ARN**。
> 不要传 ARN 末尾的随机后缀片段（如 `DemoDeepgramKey-wi1vB3`），否则会报 “Wrong name/ARN”。

不确定密钥名时，先列出：

```bash
aws secretsmanager list-secrets --region us-west-2 \
  --query "SecretList[?contains(Name,'Deepgram')].[Name,ARN,KmsKeyId]" --output table
```

### 输出与修复

脚本对每项打印 `[OK]` / `[FAIL]` / `[WARN]`。出现 `[FAIL]` 时，直接对**同一密钥与 bot 别名**重跑配置脚本即可修复（会切换为正确配置的 CMK、设置密钥策略、附加资源策略）：

```bash
./setup-lex-deepgram-secret.sh \
  --lex-arn arn:aws:lex:us-west-2:991727053196:bot-alias/E9LXXC9XGT/TSTALIASID \
  --secret-name DemoDeepgramKey \
  --api-key '<your-deepgram-api-key>'
```

修复后密钥 ARN 不变，无需改动 bot 配置（前提是 `--secret-name` 与 bot 当前指向的密钥一致）。

---

## 三、德语 / 意大利语模型参考

详见 [`deepgram-models-de-it.md`](./deepgram-models-de-it.md)。要点：

- **Nova-3** 对德语/意大利语只通过多语模式 `language=multi` 支持，无独立单语代码。
- 需**严格单语识别**时，使用 `nova-2`（或 enhanced/base）配合 `language=de` / `language=it`。
- 实时语音 Agent（带轮次检测）可用 `flux-general-multi`。

---

## 常见问题（FAQ）

| 现象 | 检查项 |
|------|--------|
| `The secret could not be accessed` | 跑 `diagnose-lex-deepgram-secret.sh`；多为 KMS 用了默认托管密钥，或 KMS 密钥策略未授权 Lex 解密 |
| `Wrong name/ARN or no permission` | `--secret-id` 用友好名或完整 ARN，别用 `-xxxxxx` 后缀片段 |
| Lex 读不到密钥但策略看似正确 | 确认资源策略 `aws:SourceArn` 覆盖 `bot-alias/<botId>/*`，账号正确 |
| 解密失败 | 必须客户托管对称 KMS 密钥，且密钥策略允许 Lex 解密 |
| 密钥内容错误 | 值必须为 `{"apiToken":"..."}`，键名必须是 `apiToken` |
| 区域端点 | `eu-` 前缀区域走 `api.eu.deepgram.com`，其余走 `api.deepgram.com`；同一 Key 通用 |

---

## 安全与计费说明

- **KMS 计费**：新建客户托管 KMS 密钥为计费资源（约每月 $1）。脚本通过别名复用，重复运行不会创建重复密钥。
- **最小权限**：资源策略默认收紧到 ARN 中指定的 bot（`bot-alias/<botId>/*`），比官方示例的 `bot-alias/*/*` 更安全。如需放宽可修改脚本中的 `BOT_ALIAS_SOURCE_ARN`。

---

## 参考来源

- AWS — Setting up Deepgram speech model preference: https://docs.aws.amazon.com/lexv2/latest/dg/customizing-speech-deepgram-setup.html
- AWS — DeepgramSpeechModelConfig API: https://docs.aws.amazon.com/lexv2/latest/APIReference/API_DeepgramSpeechModelConfig.html
- Deepgram — Models & Languages Overview: https://developers.deepgram.com/docs/models-languages-overview
