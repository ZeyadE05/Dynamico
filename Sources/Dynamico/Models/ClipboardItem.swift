import Foundation

public enum ClipboardItemType: String, Codable, Sendable {
    case text
    case url
    case hexColor
}

public struct ClipboardItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let type: ClipboardItemType
    public let content: String
    public let timestamp: Date

    public init(id: UUID = UUID(), type: ClipboardItemType, content: String, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
    }

    public var displayTitle: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 45 {
            return String(trimmed.prefix(45)) + "..."
        }
        return trimmed
    }
}
