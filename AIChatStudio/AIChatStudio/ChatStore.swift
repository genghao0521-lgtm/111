import Foundation
import PhotosUI

@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationID: UUID?
    @Published var settings = ModelSettings()
    @Published var draft = ""
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isSending = false
    @Published var errorMessage: String?

    private let stateURL: URL

    var currentConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    var currentMessages: [ChatMessage] {
        currentConversation?.messages ?? []
    }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIChatStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateURL = directory.appendingPathComponent("state.json")

        load()
        if conversations.isEmpty {
            seedDemoConversation()
        }
    }

    func persist() {
        KeychainStore.saveAPIKey(settings.apiKey)

        var settingsForDisk = settings
        settingsForDisk.apiKey = ""
        let state = PersistedState(
            conversations: conversations,
            selectedConversationID: selectedConversationID,
            settings: settingsForDisk
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func createConversation() {
        var conversation = Conversation(title: "新对话")
        conversation.messages = []
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        draft = ""
        pendingAttachments = []
        persist()
    }

    func selectConversation(_ id: UUID) {
        selectedConversationID = id
        persist()
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationID == id {
            selectedConversationID = conversations.first?.id
        }
        if conversations.isEmpty {
            createConversation()
        } else {
            persist()
        }
    }

    func removePendingAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func addPhotoItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                let attachment = try await AttachmentFactory.make(from: item)
                pendingAttachments.append(attachment)
            } catch {
                errorMessage = "附件读取失败：\(error.localizedDescription)"
            }
        }
    }

    func addFiles(_ urls: [URL]) async {
        for url in urls {
            do {
                let attachment = try AttachmentFactory.make(from: url)
                pendingAttachments.append(attachment)
            } catch {
                errorMessage = "文件读取失败：\(error.localizedDescription)"
            }
        }
    }

    func sendCurrentMessage() {
        guard !isSending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }

        if selectedConversationID == nil || conversations.isEmpty {
            createConversation()
        }

        guard let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else { return }

        let userMessage = ChatMessage(role: .user, text: text, attachments: pendingAttachments)
        conversations[index].messages.append(userMessage)
        conversations[index].refreshTitle(from: text.isEmpty ? userMessage.attachments.first?.fileName ?? "附件分析" : text)
        conversations[index].updatedAt = Date()

        draft = ""
        pendingAttachments = []
        persist()

        let requestConversation = conversations[index]
        let requestSettings = settings
        let conversationID = conversations[index].id
        isSending = true

        Task {
            do {
                let reply = try await AIService(settings: requestSettings).send(conversation: requestConversation)
                appendAssistantReply(reply, to: conversationID)
            } catch {
                appendAssistantReply("请求失败：\(error.localizedDescription)", to: conversationID)
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    func resetDemo() {
        conversations = []
        selectedConversationID = nil
        seedDemoConversation()
        persist()
    }

    private func appendAssistantReply(_ text: String, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let message = ChatMessage(role: .assistant, text: text)
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL) else {
            settings.apiKey = KeychainStore.loadAPIKey()
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            conversations = state.conversations
            selectedConversationID = state.selectedConversationID ?? conversations.first?.id
            settings = state.settings
            settings.apiKey = KeychainStore.loadAPIKey()
        } catch {
            errorMessage = "读取本地数据失败：\(error.localizedDescription)"
            settings.apiKey = KeychainStore.loadAPIKey()
        }
    }

    private func seedDemoConversation() {
        let attachment = ChatAttachment(
            fileName: "experiment.png",
            mimeType: "image/png",
            kind: .image,
            byteCount: 1_200_000,
            dataBase64: nil,
            extractedText: nil
        )
        let user = ChatMessage(
            role: .user,
            text: "请分析这张图片中的实验数据，并估算该反应的表观活化能，给出计算过程和结论。",
            attachments: [attachment]
        )
        let assistant = ChatMessage(role: .assistant, text: """
好的，我来分析这张图片中的实验数据并估算表观活化能。

### 计算过程

根据阿伦尼乌斯方程：

\\[
k = Ae^{-E_a/(RT)}
\\]

两边取自然对数：

\\[
\\ln k = \\ln A - \\frac{E_a}{R}\\frac{1}{T}
\\]

因此，以 \\(\\ln k\\) 对 \\(1/T\\) 作图，斜率 \\(m = -E_a/R\\)。

### 实验数据

| T (K) | 1/T (K^-1) | k (s^-1) | ln k |
| --- | --- | --- | --- |
| 298 | 0.003356 | 0.127 | -2.066 |
| 308 | 0.003247 | 0.229 | -1.474 |
| 318 | 0.003145 | 0.406 | -0.901 |
| 328 | 0.003049 | 0.704 | -0.352 |

线性拟合得到斜率 \\(m = -5.41 \\times 10^3\\)，代入气体常数：

\\[
E_a = -mR = 5.41 \\times 10^3 \\times 8.314 = 44.97\\ \\mathrm{kJ\\ mol^{-1}}
\\]

### 结论

该反应的表观活化能约为 \\(44.97\\ \\mathrm{kJ\\ mol^{-1}}\\)。
""")

        var conversation = Conversation(title: "实验数据分析")
        conversation.messages = [user, assistant]
        conversations = [conversation]
        selectedConversationID = conversation.id
    }
}
