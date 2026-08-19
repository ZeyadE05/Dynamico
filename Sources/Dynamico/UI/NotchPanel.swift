import AppKit

public final class NotchPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        // Window level pinned above menu bar/status items
        self.level = NSWindow.Level(Int(NSWindow.Level.statusBar.rawValue) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = false
    }

    override public var canBecomeKey: Bool {
        return true
    }

    override public var canBecomeMain: Bool {
        return false
    }

    override public func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}
