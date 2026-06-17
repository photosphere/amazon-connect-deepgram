# Lex V2 Deepgram 密钥配置脚本

`setup-lex-deepgram-secret.sh` 用于在 **AWS CloudShell** 中一键完成 Amazon Lex V2 使用 Deepgram 作为语音识别模型所需的密钥配置：把 Deepgram API Key 安全地存入 **AWS Secrets Manager**，已存在则自动更新。

脚本严格遵循官方文档：
[Setting up Deepgram speech model preference](https://docs.aws.amazon.com/lexv2/latest/dg/customizing-speech-deepgram-setup.html)

---

## 功能说明

脚本以**幂等**方式执行以下步骤：

1. **解析 Lex ARN**：从你提供的 bot 或 bot-alias ARN 中自动提取 region、account ID、bot ID。
2. **准备客户托管 KMS 密钥**：官方要求必须使用**客户托管的对称 KMS 密钥**，默认的 AWS 托管密钥不被 Lex 支持。脚本会通过别名 `alias/lex-deepgram-apitoken` 自动创建或复用密钥（也可用 `--kms-key-id` 指定自己的密钥），并为其设置允许 Lex 解密的密钥策略。
3. **写入密钥**：按官方要求的格式存储，即单个键值对 `{"apiToken":"<你的密钥>"}`。
   - 密钥不存在 → 创建（`create-secret`）
   - 密钥已存在 → 更新密钥值与 KMS 密钥（`update-secret` + `put-secret-value`）
4. **附加资源策略**：为密钥附加资源策略，允许 `lex.amazonaws.com` 调用 `secretsmanager:GetSecretValue`，并通过 `aws:SourceAccount` 和 `aws:SourceArn`（限定为该 bot 的别名）收紧权限范围。

执行成功后会输出 **Secret ARN**，用于在 Lex 控制台配置。

---

## 前置条件

- 在 **AWS CloudShell** 中运行（已预装 `aws` CLI v2 与 `jq`）。
- 当前身份具备以下权限：
  - `secretsmanager:CreateSecret` / `UpdateSecret` / `PutSecretValue` / `DescribeSecret` / `PutResourcePolicy`
  - `kms:CreateKey` / `CreateAlias` / `ListAliases` / `PutKeyPolicy`
- 已从 [Deepgram 控制台](https://console.deepgram.com/) 获取 API Key。

---

## 使用方法

### 1. 上传并赋予执行权限

```bash
chmod +x setup-lex-deepgram-secret.sh
```

### 2. 运行脚本

```bash
./setup-lex-deepgram-secret.sh \
  --lex-arn arn:aws:lex:us-east-1:111122223333:bot/ABCDEFGHIJ \
  --api-key 'dg_xxxxxxxxxxxxxxxxxxxxxxxx'
```

### 参数说明

| 参数 | 必填 | 说明 |
|------|------|------|
| `--lex-arn` | 是 | Lex V2 的 bot 或 bot-alias ARN，例如 `arn:aws:lex:us-east-1:111122223333:bot/ABCDEFGHIJ` |
| `--api-key` | 是 | 你的 Deepgram API Key |
| `--secret-name` | 否 | Secrets Manager 密钥名称，默认 `lex-deepgram-apitoken-<botId>` |
| `--kms-key-id` | 否 | 自定义客户托管对称 KMS 密钥（key id / key ARN / `alias/<name>`）。不填则自动创建或复用 |
| `--region` | 否 | AWS 区域，默认取 Lex ARN 中的区域 |
| `-h`, `--help` | 否 | 显示帮助 |

### 3. 在 Lex 控制台完成关联

脚本输出 Secret ARN 后：

1. 打开 Lex V2 控制台，进入对应 bot 的语言区域（locale）。
2. **Speech model preference** 选择 **Deepgram**。
3. 在 **Secret ARN** 字段粘贴脚本输出的 ARN（可选填 Deepgram **Model ID**）。
4. 保存。

---

## 注意事项

- **KMS 计费**：新建的客户托管 KMS 密钥为计费资源（约每月 $1）。脚本通过别名复用，重复运行不会创建重复密钥。
- **权限范围**：脚本将资源策略收紧到 ARN 中指定的 bot（`bot-alias/<botId>/*`），比官方示例中的 `bot-alias/*/*` 更安全。如需放宽，可修改脚本中的 `BOT_ALIAS_SOURCE_ARN`。
- **自定义 KMS 密钥**：若使用 `--kms-key-id` 指定自有密钥，请自行确保其密钥策略允许 `lex.amazonaws.com` 通过 `secretsmanager.<region>.amazonaws.com` 调用 `kms:Decrypt`。

---

## 故障排查

| 现象 | 检查项 |
|------|--------|
| Lex 无法读取密钥 | 资源策略中的 account ID 与 bot-alias ARN 是否匹配 |
| 解密失败 | 是否使用客户托管对称 KMS 密钥（非默认 AWS 托管密钥），且密钥策略允许 Lex 解密 |
| 密钥内容错误 | 密钥值是否为 `{"apiToken":"..."}` 格式，键名是否为 `apiToken` |
| API 调用失败 | Deepgram API Key 是否有效、未过期 |

更多信息可查看 Amazon Lex V2 的 CloudWatch 日志。
