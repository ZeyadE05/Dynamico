import AppKit

/// Fixed-canvas transparent panel manager for the macOS Notch utility.
/// Keeps the host NSPanel fixed at maximum expanded bounds with a transparent backing
/// to strictly prevent WindowServer surface buffer reallocations during morphing animations.
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

        // Window level pinned to statusBar so popups (popUpMenu level) and status items display above it
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true

        // Default to complete pass-through on creation.
        // NotchPanelController calls applyMousePassThrough(for:) once wiring is done.
        self.ignoresMouseEvents = true
    }

    override public var canBecomeKey: Bool { return false }
    override public var canBecomeMain: Bool { return false }

    override public func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    // MARK: - State-Driven Mouse Pass-Through

    public func applyMousePassThrough(for state: NotchState) {
        switch state {
        case .collapsed:
            ignoresMouseEvents = true
        case .peek, .expanded, .hud:
            ignoresMouseEvents = false
        }
    }
}
