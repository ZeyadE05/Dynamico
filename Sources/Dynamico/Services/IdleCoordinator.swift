import AppKit
import Combine

/// Coordinator for zero-cost idle state throttling.
/// Suspends polling timers when the notch remains collapsed and idle for 60 seconds.
/// Wakes immediately on user interaction or system wake.
@MainActor
public final class IdleCoordinator: ObservableObject {
    public static let shared = IdleCoordinator()

    @Published public private(set) var isIdleSuspended: Bool = false

    private var idleTimer: Timer?
    private let idleThreshold: TimeInterval = 60.0 // 60 seconds idle threshold

    private init() {
        setupSystemSleepObservers()
        startIdleTimer()
    }

    private func setupSystemSleepObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.suspendForIdle()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.userDidInteract()
            }
        }
    }

    // MARK: - User Interaction Hook

    /// Call on any user interaction (mouse hover, click expand, drag gesture, media key press).
    public func userDidInteract() {
        if isIdleSuspended {
            resumeFromIdle()
        }
        startIdleTimer()
    }

    // MARK: - Idle Timer Management

    public func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateIdleState()
            }
        }
    }

    private func evaluateIdleState() {
        let isNotchCollapsed = NotchPanelController.shared.trackingController?.currentState == .collapsed
        let isMediaPlaying = MediaManager.shared.isPlaying

        if isNotchCollapsed && !isMediaPlaying {
            suspendForIdle()
        } else {
            // Re-arm timer if conditions for idle suspension are not yet met
            startIdleTimer()
        }
    }

    private func suspendForIdle() {
        guard !isIdleSuspended else { return }
        isIdleSuspended = true
        idleTimer?.invalidate()
        idleTimer = nil

        // Completely suspend polling loops in services
        ClipboardManager.shared.stopPolling()
        MediaManager.shared.updatePollingState(isNotchExpanded: false)
    }

    private func resumeFromIdle() {
        guard isIdleSuspended else { return }
        isIdleSuspended = false

        let isExpanded = NotchPanelController.shared.isExpanded
        ClipboardManager.shared.updatePollingState(isNotchExpanded: isExpanded)
        MediaManager.shared.updatePollingState(isNotchExpanded: isExpanded)

        // Perform single on-demand refresh
        ClipboardManager.shared.checkPasteboard()
        MediaManager.shared.refreshNowPlaying()
    }
}
