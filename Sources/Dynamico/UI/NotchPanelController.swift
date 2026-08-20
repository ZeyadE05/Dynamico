import AppKit
import Combine

/// Coordinator for the macOS Notch Utility.
/// Manages the fixed-canvas transparent host window, event-driven tracking controller,
/// GPU-accelerated layer container, and screen parameter reconfigurations.
@MainActor
public final class NotchPanelController: NSObject, ObservableObject {
    public static let shared = NotchPanelController()

    @Published public var isExpanded: Bool = false {
        didSet {
            guard let tracking = trackingController else { return }
            let targetState: NotchState = isExpanded ? .expanded(activeTab: tracking.lastActiveTab) : .collapsed
            if tracking.currentState != targetState {
                tracking.setNotchState(targetState, animated: true)
            }
        }
    }

    @Published public var selectedTab: NotchTab = .spotify {
        didSet {
            containerView?.rebuildHeaderButtons()
            containerView?.updateShapeForCurrentState(animated: true)
        }
    }

    @Published public var notchWidth: CGFloat = 185
    @Published public var notchHeight: CGFloat = 32

    public private(set) var panel: NotchPanel?
    public private(set) var trackingController: NotchTrackingController?
    public private(set) var containerView: NotchContainerView?

    override private init() {
        super.init()
        setupPanelArchitecture()
        setupScreenChangeObserver()
    }

    public func setupPanelArchitecture() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Fixed canvas window bounds pinned at screen top-center
        let canvasW: CGFloat = min(720, screenFrame.width - 20)
        let canvasH: CGFloat = 260
        let canvasX = screenFrame.origin.x + (screenFrame.width - canvasW) / 2
        let canvasY = screenFrame.origin.y + screenFrame.height - canvasH

        let canvasRect = NSRect(x: canvasX, y: canvasY, width: canvasW, height: canvasH)

        let panel = NotchPanel(contentRect: canvasRect)
        let tracking = NotchTrackingController()
        let container = NotchContainerView(frame: NSRect(x: 0, y: 0, width: canvasW, height: canvasH))

        container.controller = self
        container.trackingController = tracking
        container.autoresizingMask = [.width, .height]

        tracking.containerView = container
        tracking.panel = panel          // Wire back-reference so state transitions can flip ignoresMouseEvents
        panel.contentView = container
        panel.orderFrontRegardless()

        self.panel = panel
        self.trackingController = tracking
        self.containerView = container

        // Apply the correct ignoresMouseEvents, global mouse monitor, and tracking area
        // for the initial .collapsed state in one atomic call.
        tracking.configureForCurrentState()
    }

    private func setupScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDisplayReconfiguration()
            }
        }
    }

    public func handleDisplayReconfiguration() {
        guard let screen = NSScreen.main, let panel = panel else { return }
        let screenFrame = screen.frame

        let canvasW: CGFloat = min(720, screenFrame.width - 20)
        let canvasH: CGFloat = 260
        let canvasX = screenFrame.origin.x + (screenFrame.width - canvasW) / 2
        let canvasY = screenFrame.origin.y + screenFrame.height - canvasH

        let newCanvasRect = NSRect(x: canvasX, y: canvasY, width: canvasW, height: canvasH)
        panel.setFrame(newCanvasRect, display: true, animate: false)

        containerView?.detectNotchDimensions()
        containerView?.rebuildHeaderButtons()
        containerView?.updateShapeForCurrentState(animated: false)
    }

    public func toggleExpand() {
        guard let tracking = trackingController else { return }
        tracking.toggleExpanded()
        self.isExpanded = tracking.currentState.isExpanded
    }

    public func setExpanded(_ expanded: Bool) {
        guard let tracking = trackingController else { return }
        let newState: NotchState = expanded ? .expanded(activeTab: tracking.lastActiveTab) : .collapsed
        tracking.setNotchState(newState, animated: true)
        self.isExpanded = expanded
    }

    public func updatePanelFrame(animated: Bool) {
        // Zero WindowServer frame resizing during morphing; delegate shape update to NotchContainerView
        containerView?.detectNotchDimensions()
        containerView?.rebuildHeaderButtons()
        containerView?.updateShapeForCurrentState(animated: animated)
    }
}
