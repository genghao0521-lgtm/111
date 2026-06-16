import Foundation

struct AIService {
    let settings: ModelSettings

    func send(conversation: Conversation) async throws -> String {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await demoReply(for: conversation)
        }

        let url = try endpointURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: payload(for: conversation))

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(statusCode) else {
            let serverMessage = decodeServerError(from: data) ?? "HTTP \(statusCode)"
            throw AIServiceError.server(serverMessage)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        if let text = decoded.choices?.first?.message.content, !text.isEmpty {
            return text
        }
        if let text = decoded.outputText, !text.isEmpty {
            return text
        }
        throw AIServiceError.emptyResponse
    }

    private func endpointURL() throws -> URL {
        var raw = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasSuffix("/") {
            raw.removeLast()
        }
        if !raw.hasSuffix("/chat/completions") {
            raw += "/chat/completions"
        }
        guard let url = URL(string: raw) else {
            throw AIServiceError.invalidURL
        }
        return url
    }

    private func payload(for conversation: Conversation) -> [String: Any] {
        var request: [String: Any] = [
            "model": settings.model,
            "messages": messages(for: conversation),
            "temperature": settings.clippedTemperature,
            "max_completion_tokens": settings.maxOutputTokens
        ]

        if settings.sendsReasoningEffort {
            request["reasoning_effort"] = settings.reasoningEffort.rawValue
        }

        return request
    }

    private func messages(for conversation: Conversation) -> [[String: Any]] {
        var result: [[String: Any]] = []
        let system = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            result.append(["role": "system", "content": system])
        }

        for message in conversation.messages.suffix(24) {
            switch message.role {
            case .assistant:
                result.append(["role": "assistant", "content": message.text])
            case .user:
                result.append(["role": "user", "content": contentParts(for: message)])
            }
        }
        return result
    }

    private func contentParts(for message: ChatMessage) -> [[String: Any]] {
        var text = message.text
        let notes = attachmentNotes(for: message.attachments)
        if !notes.isEmpty {
            text += "\n\n附件摘要：\n" + notes
        }

        var parts: [[String: Any]] = [
            ["type": "text", "text": text]
        ]

        for attachment in message.attachments where attachment.isImageForAPI {
            guard let base64 = attachment.dataBase64 else { continue }
            parts.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(attachment.mimeType);base64,\(base64)"
                ]
            ])
        }

        return parts
    }

    private func attachmentNotes(for attachments: [ChatAttachment]) -> String {
        attachments.map { attachment in
            var line = "- \(attachment.fileName), \(attachment.mimeType), \(attachment.displaySize)"
            if let extractedText = attachment.extractedText, !extractedText.isEmpty {
                line += "\n  提取文本：\n\(extractedText)"
            } else if attachment.kind == .video {
                line += "\n  说明：当前以视频文件元数据发送；如目标 API 支持视频理解，可在此处扩展上传管线。"
            }
            return line
        }
        .joined(separator: "\n")
    }

    private func decodeServerError(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return decoded.error.message
        }
        return String(data: data, encoding: .utf8)
    }

    private func demoReply(for conversation: Conversation) async throws -> String {
        try await Task.sleep(nanoseconds: 650_000_000)
        let latest = conversation.messages.last?.text ?? "这个问题"
        return """
这是本地演示回复。你还没有配置 API Key，所以我先用内置示例跑通完整对话流程。

你刚才的问题是：

> \(latest.isEmpty ? "请分析已上传附件。" : latest)

### LaTeX 渲染示例

\\[
\\ln k = \\ln A - \\frac{E_a}{R}\\frac{1}{T}
\\]

当斜率 \\(m = -5.41 \\times 10^3\\) 时：

\\[
E_a = -mR = 44.97\\ \\mathrm{kJ\\ mol^{-1}}
\\]

### Markdown 表格示例

| 参数 | 当前值 | 说明 |
| --- | --- | --- |
| 推理强度 | \(settings.reasoningEffort.title) | 控制 reasoning_effort |
| 输出长度 | \(settings.maxOutputTokens) | 使用 max_completion_tokens |
| 温度 | \(String(format: "%.1f", settings.temperature)) | 控制采样随机性 |

配置 API Key 后，这里会替换为真实模型回复。
"""
    }
}

enum AIServiceError: LocalizedError {
    case invalidURL
    case server(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "API Base URL 无效。"
        case .server(let message):
            return "API 请求失败：\(message)"
        case .emptyResponse:
            return "API 返回为空。"
        }
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorMessage
}

private struct APIErrorMessage: Decodable {
    let message: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]?
    let outputText: String?

    enum CodingKeys: String, CodingKey {
        case choices
        case outputText = "output_text"
    }
}

private struct Choice: Decodable {
    let message: AssistantMessage
}

private struct AssistantMessage: Decodable {
    let content: String?
}
