import AppKit
import Combine

public enum NotchHUDType: Equatable {
    case volume
    case brightness
}

/// Associated-Value State Machine for Notch interaction.
public enum NotchState: Equatable {
    case collapsed
    case peek
    case expanded(activeTab: NotchTab)
    case hud(type: NotchHUDType, level: Double)

    public var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }

    public var isHUD: Bool {
        if case .hud = self { return true }
        return false
    }

    public var activeTab: NotchTab? {
        if case .expanded(let tab) = self { return tab }
        return nil
    }
}

/// Event-Driven Notch Controller (Zero Polling / Zero Timers).
/// Manages the collapsed -> peek -> expanded -> hud state lifecycle with tab persistence.
@MainActor
public final class NotchTrackingController: NSResponder, ObservableObject {
    public static let shared = NotchTrackingController()

    @Published public private(set) var currentState: NotchState = .collapsed
    @Published public private(set) var isDragActive: Bool = false

    public weak var containerView: NotchContainerView?
    public weak var panel: NotchPanel?

    private var trackingArea: NSTrackingArea?
    private var globalMouseMonitor: Any?

    private static let lastActiveTabKey = "last_active_notch_tab_session"

    public var lastActiveTab: NotchTab {
        get {
            if let saved = UserDefaults.standard.string(forKey: Self.lastActiveTabKey),
               let tab = NotchTab(rawValue: saved) {
                return tab
            }
            return .spotify
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.lastActiveTabKey)
        }
    }

    private var collapseWorkItem: DispatchWorkItem?
    private var hudDismissWorkItem: DispatchWorkItem?

    public override init() {
        super.init()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Native System HUD Trigger & Auto-Dismissal

    public func showHUD(type: NotchHUDType, level: Double) {
        IdleCoordinator.shared.userDidInteract()

        if currentState.isExpanded { return }

        hudDismissWorkItem?.cancel()
        setNotchState(.hud(type: type, level: level), animated: true)

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                if self?.currentState.isHUD == true {
                    self?.setNotchState(.collapsed, animated: true)
                }
            }
        }
        self.hudDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    // MARK: - Drag-and-Drop Pinning & Immediate Snapping

    public func updateDragTargeted(_ targeted: Bool) {
        IdleCoordinator.shared.userDidInteract()
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        if targeted {
            isDragActive = true
            if currentState != .expanded(activeTab: .fileShelf) {
                setNotchState(.expanded(activeTab: .fileShelf), animated: true)
            }
        } else {
            isDragActive = false
            if !isMouseInActiveBounds() {
                setNotchState(.collapsed, animated: true)
            }
        }
    }

    private func isMouseInActiveBounds() -> Bool {
        guard let container = containerView, let window = container.window else { return false }
        let mouseScreen = NSEvent.mouseLocation
        let activeBoundsView = container.currentBoundsForState(currentState).insetBy(dx: -4, dy: -4)
        let activeBoundsWindow = container.convert(activeBoundsView, to: nil)
        let activeBoundsScreen = window.convertToScreen(activeBoundsWindow)
        return activeBoundsScreen.contains(mouseScreen)
    }

    // MARK: - State Management

    public func setNotchState(_ newState: NotchState, animated: Bool = true) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        if currentState.isHUD && newState.isHUD {
            // Keep HUD updated smoothly
        } else if currentState == newState {
            return
        }

        let previousState = currentState
        currentState = newState

        panel?.applyMousePassThrough(for: newState)
        syncGlobalMonitor(for: newState)
        triggerHapticFeedback(for: newState, from: previousState)

        if case .expanded(let tab) = newState {
            lastActiveTab = tab
            containerView?.controller?.selectedTab = tab

            ClipboardManager.shared.checkPasteboard()
            EnergyMonitor.shared.sampleTopConsumers()
            Task {
                MediaManager.shared.refreshNowPlaying()
                if TodoistAPIClient.shared.isAuthenticated {
                    await TodoistAPIClient.shared.fetchTasks()
                }
            }
        }

        containerView?.stateDidChange(from: previousState, to: newState, animated: animated)
    }

    public func selectTab(_ tab: NotchTab) {
        IdleCoordinator.shared.userDidInteract()
        let isSameTab = (lastActiveTab == tab)
        lastActiveTab = tab
        if !isSameTab {
            performStrongHaptic(.levelChange)
        }
        if case .expanded = currentState {
            setNotchState(.expanded(activeTab: tab), animated: true)
        }
    }

    private func triggerHapticFeedback(for newState: NotchState, from oldState: NotchState) {
        switch (oldState, newState) {
        case (.collapsed, .peek):
            performStrongHaptic(.levelChange)
        case (_, .expanded):
            performBurstHaptic(.levelChange, count: 2)
        case (.expanded, .collapsed), (.peek, .collapsed), (.hud, .collapsed):
            performStrongHaptic(.levelChange)
        default:
            performStrongHaptic(.generic)
        }
    }

    private func performStrongHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    private func performBurstHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern, count: Int) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        for i in 0..<count {
            if i == 0 {
                performer.perform(pattern, performanceTime: .default)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * 14)) {
                    performer.perform(pattern, performanceTime: .default)
                }
            }
        }
    }

    public func toggleExpanded() {
        IdleCoordinator.shared.userDidInteract()
        if currentState.isExpanded {
            setNotchState(.collapsed, animated: true)
        } else {
            setNotchState(.expanded(activeTab: lastActiveTab), animated: true)
        }
    }

    // MARK: - Global Monitor (High-Performance Fast-Filtered Hover Detection)

    private func syncGlobalMonitor(for state: NotchState) {
        switch state {
        case .collapsed:
            installGlobalMonitor()
        case .peek, .expanded, .hud:
            removeGlobalMonitor()
        }
    }

    private func installGlobalMonitor() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            let mouseScreen = NSEvent.mouseLocation
            
            // Fast Top-Screen Boundary Rejection
            guard let mainScreen = NSScreen.main, mouseScreen.y >= (mainScreen.frame.maxY - 50) else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.currentState == .collapsed else { return }
                guard let container = self.containerView, let window = container.window else { return }

                let hitBoundsView   = container.physicalNotchHitBounds()
                let hitBoundsWindow = container.convert(hitBoundsView, to: nil)
                let hitBoundsScreen = window.convertToScreen(hitBoundsWindow)

                if hitBoundsScreen.contains(mouseScreen) {
                    IdleCoordinator.shared.userDidInteract()
                    self.collapseWorkItem?.cancel()
                    self.collapseWorkItem = nil
                    if event.type == .leftMouseDragged || NSEvent.pressedMouseButtons != 0 {
                        self.containerView?.controller?.selectedTab = .fileShelf
                        self.updateDragTargeted(true)
                    } else {
                        self.setNotchState(.peek, animated: true)
                    }
                }
            }
        }
    }

    private func removeGlobalMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    // MARK: - Initial Configuration

    public func configureForCurrentState() {
        panel?.applyMousePassThrough(for: currentState)
        syncGlobalMonitor(for: currentState)
        if let container = containerView {
            updateTrackingArea(for: container)
        }
    }

    // MARK: - Mouse Event Handling

    override public func mouseEntered(with event: NSEvent) {
        IdleCoordinator.shared.userDidInteract()
        guard let container = containerView else { return }
        let point = container.convert(event.locationInWindow, from: nil)

        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        if currentState == .collapsed {
            let physicalNotchRect = container.physicalNotchHitBounds()
            if physicalNotchRect.contains(point) {
                setNotchState(.peek, animated: true)
            }
        }
    }

    override public func mouseMoved(with event: NSEvent) {
        guard let container = containerView else { return }
        let point = container.convert(event.locationInWindow, from: nil)

        switch currentState {
        case .collapsed:
            let physicalNotchRect = container.physicalNotchHitBounds()
            if physicalNotchRect.contains(point) {
                IdleCoordinator.shared.userDidInteract()
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
                setNotchState(.peek, animated: true)
            }

        case .peek, .expanded, .hud:
            let activeBounds = container.currentBoundsForState(currentState).insetBy(dx: -6, dy: -6)
            if activeBounds.contains(point) || isDragActive {
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
            } else if currentState.isHUD {
                // Keep HUD until auto-dismiss timer handles it
            } else {
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
                setNotchState(.collapsed, animated: true)
            }
        }
    }

    override public func mouseExited(with event: NSEvent) {
        guard currentState == .peek || currentState.isExpanded else { return }
        guard !isDragActive else { return }
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        setNotchState(.collapsed, animated: true)
    }

    override public func mouseDown(with event: NSEvent) {
        IdleCoordinator.shared.userDidInteract()
        if currentState == .peek || currentState == .collapsed || currentState.isHUD {
            setNotchState(.expanded(activeTab: lastActiveTab), animated: true)
        }
    }

    // MARK: - NSTrackingArea Setup

    public func updateTrackingArea(for view: NSView) {
        if let existingArea = trackingArea {
            view.removeTrackingArea(existingArea)
            trackingArea = nil
        }

        guard currentState != .collapsed else { return }
        guard let container = containerView else { return }

        let activeRect = container.currentBoundsForState(currentState).insetBy(dx: -4, dy: -4)

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways
        ]

        let newTrackingArea = NSTrackingArea(
            rect: activeRect,
            options: options,
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(newTrackingArea)
        self.trackingArea = newTrackingArea
    }
}
