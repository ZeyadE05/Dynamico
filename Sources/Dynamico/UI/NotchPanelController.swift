import AppKit
import SwiftUI
import Combine

@MainActor
public final class NotchPanelController: NSObject, ObservableObject {
    public static let shared = NotchPanelController()

    @Published public var isExpanded: Bool = false
    @Published public var selectedTab: NotchTab = .spotify {
        didSet {
            if isExpanded {
                updatePanelFrame(animated: true)
            }
        }
    }
    @Published public var notchWidth: CGFloat = 180
    @Published public var notchHeight: CGFloat = 32

    public private(set) var panel: NotchPanel?
    private var hostingView: NSHostingView<NotchContentView>?
    private var mouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var trackingArea: NSTrackingArea?
    private var collapseTimer: Timer?

    override private init() {
        super.init()
        setupNotchDimensions()
        createPanel()
        setupMouseMonitoring()
    }

    private func setupNotchDimensions() {
        guard let screen = NSScreen.main else { return }

        // Detect notch on Apple Silicon MacBooks
        if #available(macOS 12.0, *) {
            if let topLeft = screen.auxiliaryTopLeftArea, let topRight = screen.auxiliaryTopRightArea {
                let notchW = topRight.origin.x - (topLeft.origin.x + topLeft.width)
                let notchH = topLeft.height
                if notchW > 30 && notchH > 10 {
                    self.notchWidth = notchW
                    self.notchHeight = max(notchH, 32)
                    return
                }
            }
            if screen.safeAreaInsets.top > 0 {
                self.notchHeight = max(screen.safeAreaInsets.top, 32)
                self.notchWidth = 185
                return
            }
        }
        
        // Fallback for non-notched displays
        self.notchWidth = 180
        self.notchHeight = 32
    }

    private func createPanel() {
        guard let screen = NSScreen.main else { return }

        let collapsedRect = calculatePanelFrame(isExpanded: false, screen: screen)
        let panel = NotchPanel(contentRect: collapsedRect)

        let contentView = NotchContentView(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        
        panel.contentView = hostingView
        panel.setFrame(collapsedRect, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView
    }

    public func calculatePanelFrame(isExpanded: Bool, screen: NSScreen = NSScreen.main!) -> NSRect {
        let screenFrame = screen.frame
        
        let contentH: CGFloat
        if isExpanded {
            switch selectedTab {
            case .spotify: contentH = 135
            case .clipboard: contentH = 155
            case .fileShelf: contentH = 150
            case .power: contentH = 175
            case .todoist: contentH = 180
            default: contentH = 150
            }
        } else {
            contentH = 0
        }

        let leftTabCount = SettingsManager.shared.activeLeftTabs.count
        let baseWidth: CGFloat
        if SettingsManager.shared.showTabLabels {
            baseWidth = max(CGFloat(leftTabCount * 125) + notchWidth + 140, 520)
        } else {
            baseWidth = max(CGFloat(leftTabCount * 42) + notchWidth + 120, 380)
        }
        let expandedWidth = min(max(baseWidth, SettingsManager.shared.customWidth), screenFrame.width - 40)
        let width: CGFloat = isExpanded ? expandedWidth : notchWidth
        let height: CGFloat = isExpanded ? (max(notchHeight, 32) + contentH) : max(notchHeight, 32)
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + screenFrame.height - height

        return NSRect(x: x, y: y, width: width, height: height)
    }

    public func toggleExpand() {
        setExpanded(!isExpanded)
    }

    public func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        self.isExpanded = expanded

        collapseTimer?.invalidate()
        collapseTimer = nil

        if expanded {
            // Check clipboard, spotify & energy state when expanding (passive refresh)
            ClipboardManager.shared.checkPasteboard()
            EnergyMonitor.shared.sampleTopConsumers()
            Task {
                await SpotifyAPIClient.shared.fetchCurrentPlayback()
                if TodoistAPIClient.shared.isAuthenticated {
                    await TodoistAPIClient.shared.fetchTasks()
                }
            }
        }

        updatePanelFrame(animated: true)
    }

    public func updatePanelFrame(animated: Bool) {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let targetFrame = calculatePanelFrame(isExpanded: isExpanded, screen: screen)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func setupMouseMonitoring() {
        // Monitor local & global mouse movements for hover triggers
        localMonitor()
        globalMonitor()
    }

    private func localMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseLocation(NSEvent.mouseLocation)
            return event
        }
    }

    private func globalMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseLocation(NSEvent.mouseLocation)
            }
        }
    }

    private func handleMouseLocation(_ location: NSPoint) {
        guard let screen = NSScreen.main, let panel = panel else { return }
        let screenFrame = screen.frame
        let notchTriggerZone = NSRect(
            x: (screenFrame.width - notchWidth) / 2 - 15,
            y: screenFrame.height - notchHeight - 15,
            width: notchWidth + 30,
            height: notchHeight + 30
        )

        let expandedFrameWithPadding = panel.frame.insetBy(dx: -10, dy: -10)

        if isExpanded {
            if !expandedFrameWithPadding.contains(location) {
                setExpanded(false)
            }
        } else {
            if notchTriggerZone.contains(location) {
                setExpanded(true)
            }
        }
    }

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let gMonitor = globalMouseMonitor {
            NSEvent.removeMonitor(gMonitor)
        }
    }
}
