# Deepgram 粤语（香港）支持：ASR Model ID 与 TTS Voice

本文档整理 Deepgram 中**粤语（Cantonese，繁体、香港）** 的支持情况，涵盖：
- 语音转写（**ASR / speech-to-text**）可用的模型及其 `model` ID；
- 文本转语音（**TTS / Aura**）的粤语支持现状。

用于在 Amazon Lex V2 的 Deepgram 配置（**Model ID** 字段）或直接调用 Deepgram `/v1/listen`、`/v1/speak` 接口时选择。

> 数据来源：Deepgram 官方文档 [Models & Languages Overview](https://developers.deepgram.com/docs/models-languages-overview)（内容经整理改写以符合授权要求）。

> ⚠️ **关于文件名中的 “hk”**：这里的 `hk` 指**粤语（香港，`zh-HK`）这门语言**，并非区域端点。Deepgram **没有**「香港」专属端点，`apiTokenRegion` 也没有 `hk` 取值；粤语转写走全球端点 `api.deepgram.com` 即可（如需数据驻留，可结合 `eu` / `au` 区域端点，见本仓库 `README.md`）。

---

## 语言代码

| 语言 | 语言代码（language） | 类型 |
|------|----------------------|------|
| 粤语（繁体，香港）Chinese (Cantonese, Traditional) | `zh-HK` | 单语（monolingual） |

调用时通过 `language=zh-HK` 指定。

> 区分提示：粤语是 `zh-HK`，与普通话/国语不同——
> - 普通话（简体）：`zh`、`zh-CN`、`zh-Hans`
> - 普通话（繁体，台湾）：`zh-TW`、`zh-Hant`
> - **粤语（繁体，香港）：`zh-HK`**

---

## 一、粤语（zh-HK）可用的 Model ID

| Model ID | 类型 | 支持粤语的方式 | 说明 |
|----------|------|----------------|------|
| `nova-3` / `nova-3-general` | 最新通用模型 | 单语 `zh-HK` | 准确率最高，适合实时/批量、多说话人、嘈杂或远场音频；粤语作为独立单语代码支持 |
| `nova-2` / `nova-2-general` | 通用模型 | 单语 `zh-HK` | 通用稳定，nova-3 之外的备选；同样以单语代码 `zh-HK` 支持粤语 |

> 仅 `nova-3` 与 `nova-2`（及其 `-general` 写法）支持粤语 `zh-HK`。其余模型不支持，见下。

---

## 二、不支持粤语的模型（避免误选）

| Model ID | 是否支持粤语 | 说明 |
|----------|--------------|------|
| `flux-general-multi` | ❌ | 流式对话/语音 Agent 模型，仅多语 `en, es, fr, de, hi, ru, pt, ja, it, nl`，**不含粤语** |
| `nova-3` 的 `multi` 多语模式 | ❌ | `multi`（code-switching）仅覆盖上述 10 种语言，**不含粤语**；粤语必须用 `language=zh-HK` 单语模式 |
| `enhanced` / `enhanced-general` | ❌ | 旧版模型语言列表不含粤语 |
| `base` / `base-general` | ❌ | 旧版模型仅支持 `zh`、`zh-CN`、`zh-TW`（普通话），**不含粤语 `zh-HK`** |

---

## 三、关键区别

- **粤语只有单语代码 `zh-HK`，没有多语 `multi` 支持。** 与德语/意大利语不同（它们可走 `multi` 多语 code-switching），粤语**不能**用 `language=multi`，必须显式设 `language=zh-HK`。
- **Flux 不支持粤语。** 若需要带轮次检测（turn detection）的实时语音 Agent，目前 `flux-general-multi` 不覆盖粤语，需改用 `nova-3` / `nova-2`（`language=zh-HK`）配合自行的端点/轮次逻辑。
- **旧版 Base 的中文仅为普通话**（`zh`、`zh-CN`、`zh-TW`），不要误以为能识别粤语。

---

## 四、推荐选择

| 场景 | 粤语推荐 |
|------|----------|
| 追求最高准确率 | `nova-3`（`language=zh-HK`） |
| 通用稳定 / nova-3 不可用时的备选 | `nova-2`（`language=zh-HK`） |
| 实时语音 Agent（需轮次检测） | Flux 暂不支持粤语；用 `nova-3` 流式（`language=zh-HK`），轮次检测需自行处理 |
| 大批量、成本敏感 | `nova-2`（`language=zh-HK`）；Base/Enhanced 不支持粤语 |

---

## 五、文本转语音（TTS / Aura）粤语支持现状

> ⚠️ **结论：Deepgram 的 TTS（Aura / Aura-2）目前不支持粤语，也不支持任何中文。** 因此**没有**可用于粤语输出的 Deepgram `aura-*` voice。

Deepgram Aura TTS 当前支持的语言（[官方文档](https://developers.deepgram.com/docs/tts-models)）：

| 语言 | 代码 | 备注 |
|------|------|------|
| 英语 English | `en` | 美/英/澳/爱尔兰/菲律宾口音 |
| 西班牙语 Spanish | `es` | 墨西哥/西班牙/哥伦比亚/拉美口音 |
| 德语 German | `de` | |
| 法语 French | `fr` | |
| 荷兰语 Dutch | `nl` | |
| 意大利语 Italian | `it` | |
| 日语 Japanese | `ja` | |

- **不含粤语 / 中文**，故无 `aura-2-*-yue`、`aura-2-*-zh` 之类的 voice。
- Aura voice 命名格式为 `[modelname]-[voicename]-[language]`，例如 `aura-2-thalia-en`；语言后缀里目前没有任何中文/粤语代码。

### 粤语语音输出（TTS）的替代方案

若你的 Amazon Connect / Lex 流程需要**粤语语音播报**，由于 Deepgram TTS 暂不支持粤语，可考虑：

- **Amazon Polly**：提供粤语（香港）`zh-HK` 神经语音 **Hiujin**，可直接在 Connect 中作为语音输出。
- 即「Deepgram 负责粤语 STT（`zh-HK`，用 nova-3 / nova-2）」+「Polly 负责粤语 TTS（Hiujin）」的组合。
- Deepgram 的 ASR（粤语 `zh-HK`）与 TTS（不含粤语）相互独立；选用 Deepgram 做 STT 不代表 TTS 也能用 Deepgram 粤语。

> 说明：Deepgram 表示会持续新增 TTS 语言，部署前请以 [Voices and Languages](https://developers.deepgram.com/docs/tts-models) 官方页面为准。

---

## 六、在 Amazon Lex V2 中使用

在 Lex V2 控制台 bot 的语言区域（locale）配置 Deepgram 时：

1. **Speech model preference** 选择 **Deepgram**。
2. **Secret ARN**：填入存有 Deepgram API Key 的 Secrets Manager 密钥 ARN（参见本仓库 `README.md` 与脚本 `setup-lex-deepgram-secret.sh`）。
3. **Model ID**（可选）：填入上表中的 Model ID，例如粤语用 `nova-3` 或 `nova-2`；留空则使用 Deepgram 默认模型。

> **语言一致性**：请确认 Lex 语言区域与 Deepgram 的语言支持匹配。粤语在 Deepgram 中对应 `zh-HK`，且仅 `nova-3` / `nova-2` 支持。若 Lex 端没有对应的粤语 locale，需评估是否改用 Amazon Connect 第三方 STT 流程，并在转写参数中指定 `language=zh-HK`。

> **区域端点说明**：Deepgram 没有香港专属端点。粤语转写默认走全球端点 `api.deepgram.com`；如有数据驻留要求，可在 Amazon Connect 中通过密钥的 `apiTokenRegion` 选择 `eu` 或 `au` 区域端点（粤语 STT 在区域端点同样可用，注意 EU/AU 端点不提供 Whisper 模型）。Lex V2 则按 AWS 区域自动选端点，且忽略 `apiTokenRegion`。同一把 API Key 对各端点均有效。

---

## 七、直接调用 Deepgram API 示例

```bash
# 粤语，使用 nova-3 单语
curl --request POST \
  --header 'Authorization: Token YOUR_DEEPGRAM_API_KEY' \
  --header 'Content-Type: audio/wav' \
  --data-binary @audio_yue.wav \
  --url 'https://api.deepgram.com/v1/listen?model=nova-3&language=zh-HK'

# 粤语，使用 nova-2 单语
curl --request POST \
  --header 'Authorization: Token YOUR_DEEPGRAM_API_KEY' \
  --header 'Content-Type: audio/wav' \
  --data-binary @audio_yue.wav \
  --url 'https://api.deepgram.com/v1/listen?model=nova-2&language=zh-HK'
```

---

## 参考来源

- Deepgram — Models & Languages Overview: https://developers.deepgram.com/docs/models-languages-overview
- Deepgram — Voices and Languages (TTS / Aura): https://developers.deepgram.com/docs/tts-models
- Deepgram — Languages Support: https://developers.deepgram.com/docs/language
- Deepgram — Cantonese Speech-to-Text: https://deepgram.com/product/speech-to-text/cantonese
- Deepgram — Nova-3 Expands Speech-to-Text Support Across Asia-Pacific: https://deepgram.com/learn/deepgram-nova-3-expands-speech-to-text-support-across-asia-pacific
- AWS — Setting up Deepgram speech model preference (Lex V2): https://docs.aws.amazon.com/lexv2/latest/dg/customizing-speech-deepgram-setup.html

> 说明：以上模型与语言支持随 Deepgram 更新可能变化，部署前请以官方文档为准。内容已按授权要求改写。
