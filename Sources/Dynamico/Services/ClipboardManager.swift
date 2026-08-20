import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
public final class ClipboardManager: ObservableObject {
    public static let shared = ClipboardManager()

    @Published public var items: [ClipboardItem] = []
    @Published public var lastCopiedItem: ClipboardItem? = nil

    private var lastChangeCount: Int = -1
    private let maxHistoryCount = 50
    private var pollTimer: Timer?

    private init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    public func startPolling() {
        guard pollTimer == nil else { return }
        // Polling loop to capture copies immediately even when notch is collapsed
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // Multi-type extraction pipeline

        // 1. Check for File URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first, firstURL.isFileURL {
            if let first = items.first, first.type == .fileURL && first.fileURL == firstURL {
                return
            }
            let newItem = ClipboardItem(
                type: .fileURL,
                content: firstURL.lastPathComponent,
                fileURL: firstURL
            )
            insertItem(newItem)
            return
        }

        // 2. Check for Image (.png, .tiff, UTType.image, NSImage)
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            let dimString = "\(Int(image.size.width)) × \(Int(image.size.height)) px"
            if let first = items.first, first.type == .image, first.imageData == pngData {
                return
            }
            let newItem = ClipboardItem(
                type: .image,
                content: "Image (\(dimString))",
                imageData: pngData
            )
            insertItem(newItem)
            return
        }

        // 3. Check for RTF
        if let rtfData = pasteboard.data(forType: .rtf) {
            let plainText: String
            if let attrString = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                plainText = attrString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                plainText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            if !plainText.isEmpty {
                if let first = items.first, first.type == .rtf && first.content == plainText {
                    return
                }
                let newItem = ClipboardItem(
                    type: .rtf,
                    content: plainText,
                    rtfData: rtfData
                )
                insertItem(newItem)
                return
            }
        }

        // 4. Plain Text / URL / HexColor
        if let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            let type: ClipboardItemType
            if isHexColor(string) {
                type = .hexColor
            } else if isURL(string) {
                type = .url
            } else {
                type = .text
            }

            if let first = items.first, first.content == string && first.type == type {
                return
            }

            let newItem = ClipboardItem(type: type, content: string)
            insertItem(newItem)
            return
        }
    }

    private func insertItem(_ newItem: ClipboardItem) {
        var updated = items
        // Remove duplicate items with identical content & type
        updated.removeAll(where: { $0.type == newItem.type && $0.content == newItem.content && $0.fileURL == newItem.fileURL })
        updated.insert(newItem, at: 0)

        if updated.count > maxHistoryCount {
            updated = Array(updated.prefix(maxHistoryCount))
        }

        self.items = updated
    }

    public func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .image:
            if let image = item.nsImage {
                pasteboard.writeObjects([image])
            }
        case .fileURL:
            if let url = item.fileURL as NSURL? {
                pasteboard.writeObjects([url])
            }
        case .rtf:
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            pasteboard.setString(item.content, forType: .string)
        case .text, .url, .hexColor:
            pasteboard.setString(item.content, forType: .string)
        }

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
