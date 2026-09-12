<p align="center">
    <picture>
          <img src="brand.png" />
    </picture>
</p>
<p align="center">
  本地优先、AI 原生的个人日记。用碎片记录生活 —— 文字、照片、语音 —— 交给设备本地的流水线来整理、总结并变得可检索。
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_CN.md">简体中文</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-Dart%20%E2%89%A5%203.6-02569B?style=flat-square" alt="Flutter">
</p>

> **fork 自 [memex-lab/memex](https://github.com/memex-lab/memex),并于 2026 年修改** 为完全本地、单用户的场景:去掉了偏云端和重量级多智能体的功能,保留在自托管 LLM 下运行良好的本地能力。基于 **GPL-3.0** 授权 —— 见 [LICENSE](LICENSE)。

## 这是什么?

一个不要求你正襟危坐写完整日记的应用。你用碎片记录生活 —— 一句话、一张照片、一段语音 —— 应用把每个碎片变成结构化的时间流卡片,记录心情,汇总成周期性总结,并让你日后能按关键词或语义找回任何内容。

**真正的本地优先。** 你的记录、卡片、总结和检索向量都存在设备上,没有任何服务器保存你的日记。你自带 LLM 提供方,请求直接从设备发往该提供方。本地跑 [Ollama](https://ollama.com/) 可完全离线,或接入 OpenAI / Claude / Gemini / Bedrock。

## 功能

- **快速捕捉** —— 文字、照片、语音在单次快速处理中变成带类型的时间流卡片。
- **语音卡片** —— 设备本地转写(sherpa-onnx 上的 SenseVoice),可播放并附逐字转写。
- **心情记录** —— 每条记录打心情分,随时间生成确定性的情绪曲线。
- **总结** —— 自动生成日 / 周 / 月 / 年的叙事式汇总。
- **检索与问答** —— 关键词 + 语义混合检索(bge-m3 向量,RRF 融合),来源卡片可点开。
- **记忆册导出** —— 把一段日期范围导出成封面 + 时间流 PDF(内置 CJK 字体),经系统分享面板交付。
- **目标卡与媒体卡** —— 记录目标进度,登记书影音。
- **备份** —— 手动导出、每日本地自动快照,以及可选的 iCloud Drive 文件夹每日备份(滚动两份),卸载重装也不丢。

## 技术栈

- **Flutter**(Dart ≥ 3.6),Material 3
- **MVVM + Provider**、密封 `Result` 类型、`Command` 模式
- **Drift**(SQLite)本地存储
- **fl_chart** 图表,**GoRouter** 导航
- 设备端 ML 用 **Google ML Kit**(OCR / 图像标注);本地语音转写用 **sherpa-onnx**

## 构建

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run
```

然后在应用内 **设置** 里配置你的 LLM 提供方。想完全离线,就在本机跑 Ollama 并把应用指向它的地址。

> iOS 构建使用占位的 bundle identifier 且未设开发团队。部署真机前请在 Xcode(`ios/Runner.xcodeproj`)里改成你自己的。

## 授权

[GPL-3.0](LICENSE)。本 fork 沿用上游项目的授权;所有修改同样以 GPL-3.0 授权。
