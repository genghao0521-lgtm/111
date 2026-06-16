import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var showingSettings = false
    @State private var showingConversations = false
    @State private var showingFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ControlStrip()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                Divider()

                MessageListView()

                ComposerView(
                    showingFileImporter: $showingFileImporter,
                    photoItems: $photoItems
                )
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingConversations = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("会话列表")
                }

                ToolbarItem(placement: .principal) {
                    Text("对话")
                        .font(.headline.weight(.semibold))
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        store.createConversation()
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .accessibilityLabel("新建对话")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingConversations) {
                ConversationListView()
                    .environmentObject(store)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await store.addFiles(urls) }
                case .failure(let error):
                    store.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: photoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await store.addPhotoItems(newItems)
                    photoItems = []
                }
            }
            .alert("提示", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { store.errorMessage = nil }
                }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

private struct ControlStrip: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("推理强度", selection: settingsBinding(\.reasoningEffort)) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
            } label: {
                ChipLabel(icon: "brain.head.profile", title: "推理", value: store.settings.reasoningEffort.title)
            }

            Menu {
                ForEach([512, 1024, 2048, 4096, 8192], id: \.self) { length in
                    Button("\(length)") {
                        store.settings.maxOutputTokens = length
                        store.persist()
                    }
                }
            } label: {
                ChipLabel(icon: "list.bullet", title: "长度", value: lengthTitle)
            }

            Menu {
                ForEach([0.2, 0.5, 0.7, 1.0, 1.3], id: \.self) { value in
                    Button(String(format: "%.1f", value)) {
                        store.settings.temperature = value
                        store.persist()
                    }
                }
            } label: {
                ChipLabel(icon: "thermometer.medium", title: "温度", value: String(format: "%.1f", store.settings.temperature))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var lengthTitle: String {
        switch store.settings.maxOutputTokens {
        case 0..<1024: return "短"
        case 1024..<4096: return "中等"
        default: return "长"
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<ModelSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in
                store.settings[keyPath: keyPath] = value
                store.persist()
            }
        )
    }
}

private struct ChipLabel: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 2)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator).opacity(0.38), lineWidth: 1)
                )
        )
        .foregroundStyle(Color.primary)
    }
}

private struct MessageListView: View {
    @EnvironmentObject private var store: ChatStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if store.currentMessages.isEmpty {
                        EmptyConversationView()
                            .padding(.top, 48)
                    }

                    ForEach(store.currentMessages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    if store.isSending {
                        TypingIndicator()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .onChange(of: store.currentMessages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: store.isSending) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = store.currentMessages.last?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.snappy) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }
}

private struct EmptyConversationView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.blue)
            Text("开始一个新问题")
                .font(.headline)
            Text("输入消息，或先添加图片、视频、PDF、CSV 等附件。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }
}

private struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var webHeight: CGFloat = 120
    @State private var liked: Bool?

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 46)
                VStack(alignment: .leading, spacing: 12) {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.body)
                    }
                    AttachmentStack(attachments: message.attachments)
                    HStack {
                        Spacer()
                        Text(message.createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.blue.opacity(0.22), lineWidth: 1)
                        )
                )
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blue.gradient)
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 10) {
                    MathMarkdownWebView(markdown: message.text, height: $webHeight)
                        .frame(height: webHeight)

                    HStack(spacing: 18) {
                        Text(message.createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        Button {
                            liked = true
                        } label: {
                            Image(systemName: liked == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                        }
                        Button {
                            liked = false
                        } label: {
                            Image(systemName: liked == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(.separator).opacity(0.45), lineWidth: 1)
                        )
                )
            }
        }
    }
}

private struct AttachmentStack: View {
    let attachments: [ChatAttachment]

    var body: some View {
        if !attachments.isEmpty {
            VStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentRow(attachment: attachment)
                }
            }
        }
    }
}

private struct AttachmentRow: View {
    let attachment: ChatAttachment

    var body: some View {
        HStack(spacing: 10) {
            AttachmentThumbnail(attachment: attachment)
                .frame(width: 60, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.fileName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(attachment.displaySize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                )
        )
    }
}

private struct AttachmentThumbnail: View {
    let attachment: ChatAttachment

    var body: some View {
        Group {
            if let image = imageFromBase64 {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                    Image(systemName: iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var imageFromBase64: UIImage? {
        guard attachment.kind == .image,
              let base64 = attachment.dataBase64,
              let data = Data(base64Encoded: base64)
        else { return nil }
        return UIImage(data: data)
    }

    private var iconName: String {
        switch attachment.kind {
        case .image: return "photo"
        case .video: return "play.rectangle.fill"
        case .file:
            if attachment.mimeType.contains("pdf") { return "doc.richtext.fill" }
            if attachment.mimeType.contains("csv") { return "tablecells.fill" }
            return "doc.fill"
        }
    }

    private var iconColor: Color {
        switch attachment.kind {
        case .image: return .blue
        case .video: return .purple
        case .file: return attachment.mimeType.contains("pdf") ? .red : .green
        }
    }
}

private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("AI 正在思考")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct ComposerView: View {
    @EnvironmentObject private var store: ChatStore
    @Binding var showingFileImporter: Bool
    @Binding var photoItems: [PhotosPickerItem]

    var body: some View {
        VStack(spacing: 8) {
            if !store.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.pendingAttachments) { attachment in
                            PendingAttachmentChip(attachment: attachment) {
                                store.removePendingAttachment(attachment)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 8,
                    matching: .any(of: [.images, .videos])
                ) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 23, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择图片或视频")

                Button {
                    showingFileImporter = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 42, height: 48)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择文件")

                TextField("输入消息...", text: $store.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(.separator).opacity(0.45), lineWidth: 1)
                            )
                    )

                Button {
                    store.sendCurrentMessage()
                } label: {
                    Group {
                        if store.isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .background(canSend ? Color.blue : Color(.systemGray4))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("发送")
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !store.isSending && (!store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.pendingAttachments.isEmpty)
    }
}

private struct PendingAttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AttachmentThumbnail(attachment: attachment)
                .frame(width: 42, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(attachment.displaySize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 172)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                )
        )
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Base URL", text: settingsBinding(\.baseURL))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("API Key", text: settingsBinding(\.apiKey))
                        .textInputAutocapitalization(.never)
                    TextField("模型", text: settingsBinding(\.model))
                        .textInputAutocapitalization(.never)
                    Toggle("发送 reasoning_effort", isOn: settingsBinding(\.sendsReasoningEffort))
                }

                Section("模型参数") {
                    Picker("推理强度", selection: settingsBinding(\.reasoningEffort)) {
                        ForEach(ReasoningEffort.allCases) { effort in
                            Text(effort.title).tag(effort)
                        }
                    }
                    HStack {
                        Text("温度")
                        Slider(value: settingsBinding(\.temperature), in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", store.settings.temperature))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    Stepper("输出长度 \(store.settings.maxOutputTokens)", value: settingsBinding(\.maxOutputTokens), in: 128...32768, step: 128)
                }

                Section("系统提示词") {
                    TextEditor(text: settingsBinding(\.systemPrompt))
                        .frame(minHeight: 130)
                        .font(.body)
                }

                Section {
                    Button("重置演示对话") {
                        store.resetDemo()
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        store.persist()
                        dismiss()
                    }
                }
            }
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<ModelSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in
                store.settings[keyPath: keyPath] = value
                store.persist()
            }
        )
    }
}

struct ConversationListView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.conversations) { conversation in
                    Button {
                        store.selectConversation(conversation.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: conversation.id == store.selectedConversationID ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(conversation.messages.count) 条消息 · \(conversation.updatedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteConversation(conversation.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.createConversation()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
}
