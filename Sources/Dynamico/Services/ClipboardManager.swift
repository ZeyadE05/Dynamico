import Foundation
import AppKit
import Combine

@MainActor
public final class ClipboardManager: ObservableObject {
    public static let shared = ClipboardManager()

    @Published public var items: [ClipboardItem] = []
    @Published public var lastCopiedItem: ClipboardItem? = nil

    private var lastChangeCount: Int = -1
    private let maxHistoryCount = 15

    private init() {}

    /// Passive check triggered ONLY when notch expands or UI is shown. Zero timer loop!
    public func checkPasteboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return }

        // Determine item type
        let type: ClipboardItemType
        if isHexColor(string) {
            type = .hexColor
        } else if isURL(string) {
            type = .url
        } else {
            type = .text
        }

        // Avoid duplicate consecutive entry
        if let first = items.first, first.content == string {
            return
        }

        let newItem = ClipboardItem(type: type, content: string)
        
        // Insert at beginning, limit to 15
        var updated = items
        updated.removeAll(where: { $0.content == string })
        updated.insert(newItem, at: 0)

        if updated.count > maxHistoryCount {
            updated = Array(updated.prefix(maxHistoryCount))
        }

        self.items = updated
    }

    public func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
        
        // Update changeCount to avoid self-reimporting as new entry immediately
        self.lastChangeCount = pasteboard.changeCount
        self.lastCopiedItem = item

        // Haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    public func clearHistory() {
        items.removeAll()
    }

    private func isHexColor(_ string: String) -> Bool {
        let pattern = "^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
        return string.range(of: pattern, options: .regularExpression) != nil
    }

    private func isURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let host = url.host, !host.isEmpty else {
            return false
        }
        return url.scheme == "http" || url.scheme == "https"
    }
}
