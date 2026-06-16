import Foundation
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

enum AttachmentFactory {
    private static let inlineImageLimit = 16_000_000
    private static let extractedTextLimit = 12_000

    static func make(from item: PhotosPickerItem) async throws -> ChatAttachment {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw AttachmentError.unreadable
        }

        let type = item.supportedContentTypes.first ?? .data
        let isVideo = type.conforms(to: .movie)
        let kind: AttachmentKind = isVideo ? .video : .image
        let ext = type.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg")
        let name = "\(isVideo ? "video" : "image")-\(Self.timestamp()).\(ext)"
        let mime = type.preferredMIMEType ?? (isVideo ? "video/quicktime" : "image/jpeg")
        let base64 = kind == .image && data.count <= inlineImageLimit ? data.base64EncodedString() : nil

        return ChatAttachment(
            fileName: name,
            mimeType: mime,
            kind: kind,
            byteCount: data.count,
            dataBase64: base64,
            extractedText: nil
        )
    }

    static func make(from url: URL) throws -> ChatAttachment {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        let kind: AttachmentKind
        if type.conforms(to: .image) {
            kind = .image
        } else if type.conforms(to: .movie) {
            kind = .video
        } else {
            kind = .file
        }

        let mime = type.preferredMIMEType ?? "application/octet-stream"
        let base64 = kind == .image && data.count <= inlineImageLimit ? data.base64EncodedString() : nil
        let extractedText = extractText(from: data, type: type)

        return ChatAttachment(
            fileName: url.lastPathComponent,
            mimeType: mime,
            kind: kind,
            byteCount: data.count,
            dataBase64: base64,
            extractedText: extractedText
        )
    }

    private static func extractText(from data: Data, type: UTType) -> String? {
        if type.conforms(to: .pdf), let document = PDFDocument(data: data) {
            var text = ""
            for index in 0..<document.pageCount {
                text += document.page(at: index)?.string ?? ""
                text += "\n"
                if text.count > extractedTextLimit { break }
            }
            return clipped(text)
        }

        if type.conforms(to: .text), let text = String(data: data, encoding: .utf8) {
            return clipped(text)
        }

        return nil
    }

    private static func clipped(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= extractedTextLimit {
            return trimmed
        }
        return String(trimmed.prefix(extractedTextLimit)) + "\n...[已截断]"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

enum AttachmentError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "无法读取所选附件。"
        }
    }
}
