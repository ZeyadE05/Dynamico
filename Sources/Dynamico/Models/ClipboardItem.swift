import Foundation
import AppKit

public enum ClipboardItemType: String, Codable, Sendable {
    case text
    case url
    case hexColor
    case image
    case rtf
    case fileURL
}

public struct ClipboardItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let type: ClipboardItemType
    public let content: String
    public let imageData: Data?
    public let fileURL: URL?
    public let rtfData: Data?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        content: String,
        imageData: Data? = nil,
        fileURL: URL? = nil,
        rtfData: Data? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.imageData = imageData
        self.fileURL = fileURL
        self.rtfData = rtfData
        self.timestamp = timestamp
    }

    public var displayTitle: String {
        switch type {
        case .image:
            return content.isEmpty ? "Image" : content
        case .fileURL:
            if let fileURL = fileURL {
                return fileURL.lastPathComponent
            }
            return content
        case .rtf, .text, .url, .hexColor:
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 45 {
                return String(trimmed.prefix(45)) + "..."
            }
            return trimmed
        }
    }

    public var nsImage: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }
}
