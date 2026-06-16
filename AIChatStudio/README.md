# AI Chat Studio

AI Chat Studio 是一个完整 SwiftUI iPhone 工程，用于连接 OpenAI-compatible Chat Completions API 并进行多模态 AI 对话。

## 功能

- 新建、切换、删除对话
- OpenAI-compatible API Base URL、模型、API Key 配置
- 系统提示词、温度、输出长度、推理强度设置
- 图片、视频、PDF、CSV、文本等附件选择
- 图片会以内联 `image_url` 发送给支持视觉输入的模型
- PDF/CSV/文本文件会提取可读文本并随提示发送
- LaTeX 与 Markdown 表格通过内置 `WKWebView` + MathJax 渲染
- API Key 存入 iOS Keychain
- 未填写 API Key 时会走本地演示回复，方便直接运行看完整界面

## 运行

1. 用 Xcode 16 或更新版本打开 `AIChatStudio.xcodeproj`。
2. 选择 iPhone 模拟器或真机。
3. 如需真机运行，在 Signing & Capabilities 中设置你的 Team。
4. 运行后进入设置页，填写 API Key、Base URL 和模型。

默认 Base URL 是 `https://api.openai.com/v1`，默认模型是 `gpt-5.4-mini`。如果你的账号或兼容服务不支持这个模型，直接在设置里改成可用模型即可。

## API 说明

工程使用 `/chat/completions` 请求格式，包含 `messages`、`temperature`、`max_completion_tokens`，并可选发送 `reasoning_effort`。如果你的服务不支持推理参数，可以在设置里关闭“发送 reasoning_effort”。

OpenAI 官方 Chat Completions 参考：<https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create/>
