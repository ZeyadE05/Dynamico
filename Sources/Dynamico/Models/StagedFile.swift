import Foundation
import AppKit

public struct StagedFile: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let sizeFormatted: String
    public let addedAt: Date

    public init(id: UUID = UUID(), url: URL, addedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.name = url.lastPathComponent
        self.addedAt = addedAt
        
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            self.sizeFormatted = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        } else {
            self.sizeFormatted = "Unknown size"
        }
    }

    @MainActor
    public var fileIcon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
