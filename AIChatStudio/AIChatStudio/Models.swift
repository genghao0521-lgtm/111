import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

enum AttachmentKind: String, Codable {
    case image
    case video
    case file
}

enum ReasoningEffort: String, Codable, CaseIterable, Identifiable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "关闭"
        case .minimal: return "极低"
        case .low: return "低"
        case .medium: return "中等"
        case .high: return "高"
        case .xhigh: return "极高"
        }
    }
}

struct ModelSettings: Codable, Equatable {
    var baseURL = "https://api.openai.com/v1"
    var apiKey = ""
    var model = "gpt-5.4-mini"
    var systemPrompt = "你是一个严谨、清晰、擅长处理多模态文件的 AI 助手。回答时可以使用 Markdown、LaTeX 和表格。"
    var temperature = 0.7
    var maxOutputTokens = 2048
    var reasoningEffort = ReasoningEffort.medium
    var sendsReasoningEffort = true

    var clippedTemperature: Double {
        min(max(temperature, 0), 2)
    }
}

struct ChatAttachment: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileName: String
    var mimeType: String
    var kind: AttachmentKind
    var byteCount: Int
    var dataBase64: String?
    var extractedText: String?

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var isImageForAPI: Bool {
        kind == .image && dataBase64 != nil && mimeType.hasPrefix("image/")
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: MessageRole
    var text: String
    var attachments: [ChatAttachment] = []
    var createdAt = Date()
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []

    mutating func refreshTitle(from text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title == "新对话", !trimmed.isEmpty else { return }
        title = String(trimmed.prefix(18))
    }
}

struct PersistedState: Codable {
    var conversations: [Conversation]
    var selectedConversationID: UUID?
    var settings: ModelSettings
}
