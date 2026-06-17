# Deepgram 支持德语 / 意大利语 ASR 的 Model ID

本文档整理 Deepgram 语音转写（ASR / speech-to-text）中**支持德语（German）与意大利语（Italian）** 的模型及其 `model` ID，用于在 Amazon Lex V2 的 Deepgram 配置（**Model ID** 字段）或直接调用 Deepgram `/v1/listen` 接口时选择。

> 数据来源：Deepgram 官方文档 [Models & Languages Overview](https://developers.deepgram.com/docs/models-languages-overview)（内容经整理改写以符合授权要求）。

---

## 语言代码

| 语言 | 单语代码（monolingual） | 多语代码（multilingual） |
|------|------------------------|--------------------------|
| 德语 German | `de` | `multi` |
| 意大利语 Italian | `it` | `multi` |

调用时通过 `language` 参数指定，例如 `language=de`、`language=it` 或 `language=multi`。

---

## 一、德语（de）可用的 Model ID

| Model ID | 类型 | 支持德语的方式 | 说明 |
|----------|------|----------------|------|
| `nova-3` / `nova-3-general` | 最新通用模型 | 多语 `multi`（含德语） | 德语通过多语模式 `language=multi` 支持，准确率最高，适合实时/批量、多说话人、嘈杂或远场音频 |
| `flux-general-multi` | 最新流式对话模型 | 多语 `de` | 面向语音 Agent，内置轮次检测；多语模型，支持德语 `de` |
| `nova-2` / `nova-2-general` | 通用模型 | 单语 `de` | 适合 nova-3 尚未单语支持的场景，支持德语单语识别 |
| `enhanced` / `enhanced-general` | 旧版（Legacy） | 单语 `de` | 比 Base 更低词错率、高精度时间戳、支持关键词增强 |
| `base` / `base-general` | 旧版（Legacy） | 单语 `de` | 适合大批量转写、高精度时间戳 |

---

## 二、意大利语（it）可用的 Model ID

| Model ID | 类型 | 支持意大利语的方式 | 说明 |
|----------|------|--------------------|------|
| `nova-3` / `nova-3-general` | 最新通用模型 | 多语 `multi`（含意大利语） | 意大利语通过多语模式 `language=multi` 支持，准确率最高 |
| `flux-general-multi` | 最新流式对话模型 | 多语 `it` | 面向语音 Agent，内置轮次检测；多语模型，支持意大利语 `it` |
| `nova-2` / `nova-2-general` | 通用模型 | 单语 `it` | 支持意大利语单语识别 |
| `enhanced` / `enhanced-general` | 旧版（Legacy） | 单语 `it` | 比 Base 更低词错率、高精度时间戳 |
| `base` / `base-general` | 旧版（Legacy） | 单语 `it` | 适合大批量转写 |

---

## 三、关键区别：单语 vs 多语

- **Nova-3 对德语/意大利语仅通过多语模式 `multi` 支持**，没有独立的 `de` / `it` 单语代码。
  - 即使用 `model=nova-3` 时，需设置 `language=multi`，模型会在多种语言间自动识别（code-switching）。
  - 若你期望**只识别单一语言**，使用单语模型（nova-2 / enhanced / base）配合 `language=de` 或 `language=it`。
- `flux-general-multi` 同为多语模型，但显式列出 `de` 与 `it` 语言提示（`language_hint`）。

---

## 四、推荐选择

| 场景 | 德语推荐 | 意大利语推荐 |
|------|----------|--------------|
| 追求最高准确率 / 多语混合 | `nova-3`（`language=multi`） | `nova-3`（`language=multi`） |
| 实时语音 Agent（需轮次检测） | `flux-general-multi` | `flux-general-multi` |
| 仅识别单一语言、稳定通用 | `nova-2`（`language=de`） | `nova-2`（`language=it`） |
| 大批量、成本敏感 | `base`（`language=de`） | `base`（`language=it`） |

---

## 五、在 Amazon Lex V2 中使用

在 Lex V2 控制台 bot 的语言区域（locale）配置 Deepgram 时：

1. **Speech model preference** 选择 **Deepgram**。
2. **Secret ARN**：填入存有 Deepgram API Key 的 Secrets Manager 密钥 ARN（参见本仓库 `README.md` 与脚本 `setup-lex-deepgram-secret.sh`）。
3. **Model ID**（可选）：填入上表中的 Model ID，例如：
   - 德语：`nova-2` 或 `nova-3`
   - 意大利语：`nova-2` 或 `nova-3`
   - 留空则使用 Deepgram 默认模型。

> **区域端点说明**：Lex V2 会根据 AWS 区域自动选择 Deepgram 端点——`eu-` 前缀的区域（如 `eu-west-1`、`eu-central-1`）使用 `api.eu.deepgram.com`，其余区域使用 `api.deepgram.com`。德语/意大利语业务通常部署在欧洲区域，会自动走 EU 端点。同一把 API Key 对两个端点均有效。

> **注意**：建议确认所选 Lex 语言区域（如 `de-DE`、`it-IT`）与所选 Deepgram 模型的语言支持一致。Nova-3 对德/意语依赖 `multi` 多语模式；若需严格单语识别，优先选择 `nova-2`。

---

## 六、直接调用 Deepgram API 示例

```bash
# 德语，使用 nova-2 单语
curl --request POST \
  --header 'Authorization: Token YOUR_DEEPGRAM_API_KEY' \
  --header 'Content-Type: audio/wav' \
  --data-binary @audio_de.wav \
  --url 'https://api.deepgram.com/v1/listen?model=nova-2&language=de'

# 意大利语，使用 nova-3 多语模式
curl --request POST \
  --header 'Authorization: Token YOUR_DEEPGRAM_API_KEY' \
  --header 'Content-Type: audio/wav' \
  --data-binary @audio_it.wav \
  --url 'https://api.deepgram.com/v1/listen?model=nova-3&language=multi'
```

---

## 参考来源

- Deepgram — Models & Languages Overview: https://developers.deepgram.com/docs/models-languages-overview
- Deepgram — Languages Support: https://developers.deepgram.com/docs/language
- Deepgram — Nova-3 Multilingual: https://developers.deepgram.com/docs/multilingual-code-switching
- AWS — Setting up Deepgram speech model preference (Lex V2): https://docs.aws.amazon.com/lexv2/latest/dg/customizing-speech-deepgram-setup.html

> 说明：以上模型与语言支持随 Deepgram 更新可能变化，部署前请以官方文档为准。内容已按授权要求改写。
