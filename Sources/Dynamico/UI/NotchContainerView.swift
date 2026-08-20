import AppKit
import QuartzCore
import SwiftUI
import Combine

/// Layer-backed drawing container for the macOS Notch utility.
/// Handles GPU-accelerated CAShapeLayer bezier path morphing driven by CASpringAnimation,
/// system HUD banner animations, cached NSHostingView subview hierarchy reuse, synchronized shadow paths, and lightweight subview mounting.
public final class NotchContainerView: NSView {

    // MARK: - Properties

    public weak var controller: NotchPanelController?
    public weak var trackingController: NotchTrackingController?

    private let notchShapeLayer = CAShapeLayer()
    
    // Subview containers
    private let peekContainerView = NSView()
    private let expandedContainerView = NSView()
    
    // Peek & HUD elements
    private let peekIconView = NSImageView()
    private let peekLabel = NSTextField(labelWithString: "Dynamico")
    private let peekSubLabel = NSTextField(labelWithString: "Click to expand")

    // Expanded elements
    private let headerView = NSView()
    private let tabButtonsStack = NSStackView()
    private let rightButtonsStack = NSStackView()
    private var tabContentHostView: NSView?
    
    // Hosting View Cache for 60/120Hz Tab Switching
    private var hostingViewCache: [NotchTab: NSHostingView<AnyView>] = [:]
    private var currentHostingView: NSView?

    private var cancellables = Set<AnyCancellable>()

    // Calculated dynamic width for peek state
    private var calculatedPeekWidth: CGFloat = 240

    // Click gesture guard
    private var didExpandOnCurrentMouseDown: Bool = false
    private var expansionTimestamp: TimeInterval = 0

    // Spring animation constants
    private let springMass: CGFloat = 1.0
    private let springStiffness: CGFloat = 300.0
    private let springDamping: CGFloat = 27.0

    // Notch Dimensions Cache
    private var physicalNotchWidth: CGFloat = 185
    private var physicalNotchHeight: CGFloat = 32

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .string, .tiff, .png])
        setupLayerArchitecture()
        setupPeekView()
        setupExpandedView()
        setupCombineSubscriptions()
        detectNotchDimensions()
        updateShapeForCurrentState(animated: false)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .string, .tiff, .png])
        setupLayerArchitecture()
        setupPeekView()
        setupExpandedView()
        setupCombineSubscriptions()
        detectNotchDimensions()
        updateShapeForCurrentState(animated: false)
    }

    // MARK: - Combine Subscriptions

    private func setupCombineSubscriptions() {
        MediaManager.shared.$currentItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.trackingController?.currentState == .peek {
                    self?.updatePeekContent()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Dynamic Peek Width Calculation

    public func calculatePeekWidth() -> CGFloat {
        let iconW: CGFloat = 18
        let labelIntrinsicW = peekLabel.intrinsicContentSize.width
        let subLabelText = peekSubLabel.stringValue
        let subLabelIntrinsicW = subLabelText.isEmpty ? 0 : peekSubLabel.intrinsicContentSize.width
        let spacing: CGFloat = subLabelText.isEmpty ? 6 : 12
        let padding: CGFloat = 32

        let totalContentWidth = iconW + labelIntrinsicW + subLabelIntrinsicW + spacing + padding
        let minW = max(physicalNotchWidth + 60, 240)
        let maxW = bounds.width - 40

        return min(max(totalContentWidth, minW), maxW)
    }

    // MARK: - CoreAnimation Layer Architecture

    private func setupLayerArchitecture() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay

        guard let rootLayer = self.layer else { return }
        rootLayer.masksToBounds = false

        // Configure GPU-managed CAShapeLayer
        notchShapeLayer.fillColor = NSColor(red: 8/255, green: 8/255, blue: 10/255, alpha: 1.0).cgColor
        notchShapeLayer.strokeColor = NSColor.white.withAlphaComponent(0.06).cgColor
        notchShapeLayer.lineWidth = 1.0
        notchShapeLayer.shadowColor = NSColor.black.cgColor
        notchShapeLayer.shadowRadius = 18
        notchShapeLayer.shadowOffset = CGSize(width: 0, height: -6)
        notchShapeLayer.shadowOpacity = 0.70
        notchShapeLayer.shouldRasterize = false

        rootLayer.addSublayer(notchShapeLayer)

        // Add subview containers
        addSubview(peekContainerView)
        addSubview(expandedContainerView)

        peekContainerView.alphaValue = 0.0
        expandedContainerView.alphaValue = 0.0
        peekContainerView.isHidden = true
        expandedContainerView.isHidden = true
    }

    // MARK: - Hit Testing Override

    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard let tracking = trackingController else { return nil }
        let state = tracking.currentState

        switch state {
        case .collapsed:
            return nil

        case .peek, .hud:
            let rect = currentBoundsForState(state)
            let path = createNotchPath(rect: rect, cornerRadius: cornerRadiusForState(state))
            return path.contains(point) ? self : nil

        case .expanded:
            let expandedRect = currentBoundsForState(state)
            let path = createNotchPath(rect: expandedRect, cornerRadius: cornerRadiusForState(state))
            if path.contains(point) {
                return super.hitTest(point) ?? self
            }
            return nil
        }
    }

    // MARK: - Mouse Down Event Intercept

    override public func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let tracking = trackingController else {
            super.mouseDown(with: event)
            return
        }

        let state = tracking.currentState
        let peekRect = currentBoundsForState(.peek)
        let collapsedRect = physicalNotchHitBounds()

        if state == .peek || state == .collapsed || state.isHUD {
            if peekRect.contains(point) || collapsedRect.contains(point) {
                didExpandOnCurrentMouseDown = true
                expansionTimestamp = ProcessInfo.processInfo.systemUptime
                let targetTab = tracking.lastActiveTab
                controller?.selectedTab = targetTab
                tracking.setNotchState(.expanded(activeTab: targetTab), animated: true)
                return
            }
        } else if case .expanded = state {
            if let hitView = super.hitTest(point) {
                if hitView !== self && hitView !== expandedContainerView && hitView !== tabContentHostView && hitView !== headerView {
                    super.mouseDown(with: event)
                    return
                }
            }
            return
        }
        
        super.mouseDown(with: event)
    }

    override public func mouseUp(with event: NSEvent) {
        if didExpandOnCurrentMouseDown {
            didExpandOnCurrentMouseDown = false
            return
        }
        super.mouseUp(with: event)
    }

    // MARK: - NSDraggingDestination Support

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let notchHit = physicalNotchHitBounds().insetBy(dx: -20, dy: -20)
        let activeBounds = currentBoundsForState(trackingController?.currentState ?? .collapsed).insetBy(dx: -10, dy: -10)

        if notchHit.contains(point) || activeBounds.contains(point) {
            controller?.selectedTab = .fileShelf
            trackingController?.updateDragTargeted(true)
            return .copy
        }
        return .copy
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let activeBounds = currentBoundsForState(trackingController?.currentState ?? .collapsed).insetBy(dx: -10, dy: -10)
        let notchHit = physicalNotchHitBounds().insetBy(dx: -20, dy: -20)

        if activeBounds.contains(point) || notchHit.contains(point) {
            if trackingController?.isDragActive == false {
                controller?.selectedTab = .fileShelf
                trackingController?.updateDragTargeted(true)
            }
            return .copy
        } else {
            if trackingController?.isDragActive == true {
                trackingController?.updateDragTargeted(false)
            }
            return []
        }
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) {
        trackingController?.updateDragTargeted(false)
    }

    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            FileShelfManager.shared.stageFiles(from: urls)
            trackingController?.updateDragTargeted(false)
            return true
        }
        trackingController?.updateDragTargeted(false)
        return false
    }

    // MARK: - Notch Dimensions Detection

    public func detectNotchDimensions() {
        guard let screen = window?.screen ?? NSScreen.main else {
            physicalNotchWidth = 185
            physicalNotchHeight = 32
            return
        }

        if #available(macOS 12.0, *) {
            if let topLeft = screen.auxiliaryTopLeftArea, let topRight = screen.auxiliaryTopRightArea {
                let notchW = topRight.origin.x - (topLeft.origin.x + topLeft.width)
                let notchH = topLeft.height
                if notchW > 30 && notchH > 10 {
                    physicalNotchWidth = notchW
                    physicalNotchHeight = max(notchH, 32)
                    return
                }
            }
            if screen.safeAreaInsets.top > 0 {
                physicalNotchWidth = 185
                physicalNotchHeight = max(screen.safeAreaInsets.top, 32)
                return
            }
        }

        physicalNotchWidth = 185
        physicalNotchHeight = 32
    }

    // MARK: - Geometry & Path Generation

    public func currentBoundsForState(_ state: NotchState) -> CGRect {
        let totalW = bounds.width
        let height: CGFloat
        let width: CGFloat

        switch state {
        case .collapsed:
            width = physicalNotchWidth
            height = physicalNotchHeight
        case .peek:
            width = calculatedPeekWidth
            height = physicalNotchHeight + 34
        case .hud:
            width = max(calculatedPeekWidth, 230)
            height = physicalNotchHeight + 34
        case .expanded(let activeTab):
            let contentH: CGFloat
            switch activeTab {
            case .spotify: contentH = 135
            case .clipboard: contentH = 155
            case .fileShelf: contentH = 150
            case .power: contentH = 175
            case .todoist: contentH = 180
            default: contentH = 150
            }
            let baseW = max(physicalNotchWidth + 340, 560)
            width = min(max(baseW, SettingsManager.shared.customWidth), bounds.width - 20)
            height = max(physicalNotchHeight, 32) + contentH
        }

        let originX = (totalW - width) / 2
        let originY = bounds.height - height
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    public func physicalNotchHitBounds() -> CGRect {
        let totalW = bounds.width
        let originX = (totalW - physicalNotchWidth) / 2
        let originY = bounds.height - physicalNotchHeight
        return CGRect(x: originX, y: originY, width: physicalNotchWidth, height: physicalNotchHeight)
    }

    private func cornerRadiusForState(_ state: NotchState) -> CGFloat {
        switch state {
        case .collapsed: return 10
        case .peek, .hud: return 19
        case .expanded: return 26
        }
    }

    private func createNotchPath(rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width
        let h = rect.height
        let x = rect.origin.x
        let y = rect.origin.y

        let radius = min(cornerRadius, min(w / 2, h / 2))

        path.move(to: CGPoint(x: x, y: y + h))
        path.addLine(to: CGPoint(x: x + w, y: y + h))
        path.addLine(to: CGPoint(x: x + w, y: y + radius))
        path.addArc(tangent1End: CGPoint(x: x + w, y: y), tangent2End: CGPoint(x: x + w - radius, y: y), radius: radius)
        path.addLine(to: CGPoint(x: x + radius, y: y))
        path.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x, y: y + radius), radius: radius)
        path.closeSubpath()

        return path
    }

    // MARK: - State Morphing & CoreAnimation Springs

    public func stateDidChange(from oldState: NotchState, to newState: NotchState, animated: Bool) {
        updateShapeForCurrentState(animated: animated)
        updateSubviewsForState(newState, animated: animated)

        let isExpanded = newState.isExpanded
        ClipboardManager.shared.updatePollingState(isNotchExpanded: isExpanded)
        MediaManager.shared.updatePollingState(isNotchExpanded: isExpanded)
    }

    public func updateShapeForCurrentState(animated: Bool) {
        guard let trackingController = trackingController else { return }
        let state = trackingController.currentState
        let rect = currentBoundsForState(state)
        let radius = cornerRadiusForState(state)
        let newPath = createNotchPath(rect: rect, cornerRadius: radius)

        if animated {
            let springAnim = CASpringAnimation(keyPath: "path")
            springAnim.mass = springMass
            springAnim.stiffness = springStiffness
            springAnim.damping = springDamping
            springAnim.fromValue = notchShapeLayer.path
            springAnim.toValue = newPath
            springAnim.duration = springAnim.settlingDuration

            let shadowAnim = CASpringAnimation(keyPath: "shadowPath")
            shadowAnim.mass = springMass
            shadowAnim.stiffness = springStiffness
            shadowAnim.damping = springDamping
            shadowAnim.fromValue = notchShapeLayer.shadowPath
            shadowAnim.toValue = newPath
            shadowAnim.duration = springAnim.settlingDuration

            CATransaction.begin()
            notchShapeLayer.path = newPath
            notchShapeLayer.shadowPath = newPath
            notchShapeLayer.add(springAnim, forKey: "morphPath")
            notchShapeLayer.add(shadowAnim, forKey: "shadowPath")
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            notchShapeLayer.path = newPath
            notchShapeLayer.shadowPath = newPath
            CATransaction.commit()
        }

        trackingController.updateTrackingArea(for: self)
    }

    private func updateSubviewsForState(_ state: NotchState, animated: Bool) {
        let rect = currentBoundsForState(state)
        let duration: TimeInterval = animated ? 0.22 : 0.0

        switch state {
        case .collapsed:
            peekContainerView.isHidden = true
            expandedContainerView.isHidden = true
            expandedContainerView.frame = .zero
            setExpandedControlsEnabled(false)

        case .peek:
            peekContainerView.isHidden = false
            expandedContainerView.isHidden = true
            expandedContainerView.frame = .zero
            peekContainerView.frame = rect
            updatePeekContent()
            setExpandedControlsEnabled(false)

        case .hud(let type, let level):
            peekContainerView.isHidden = false
            expandedContainerView.isHidden = true
            expandedContainerView.frame = .zero
            peekContainerView.frame = rect
            updateHUDContent(type: type, level: level)
            setExpandedControlsEnabled(false)

        case .expanded:
            peekContainerView.isHidden = true
            expandedContainerView.isHidden = false
            expandedContainerView.frame = rect
            setExpandedControlsEnabled(true)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            switch state {
            case .collapsed:
                peekContainerView.animator().alphaValue = 0.0
                expandedContainerView.animator().alphaValue = 0.0
                unmountExpandedContentView()

            case .peek, .hud:
                peekContainerView.animator().alphaValue = 1.0
                expandedContainerView.animator().alphaValue = 0.0
                unmountExpandedContentView()

            case .expanded(let activeTab):
                peekContainerView.animator().alphaValue = 0.0
                expandedContainerView.animator().alphaValue = 1.0
                mountExpandedContentView(for: activeTab)
            }
        }
    }

    private func setExpandedControlsEnabled(_ enabled: Bool) {
        tabButtonsStack.arrangedSubviews.compactMap { $0 as? NSControl }.forEach { $0.isEnabled = enabled }
        rightButtonsStack.arrangedSubviews.compactMap { $0 as? NSControl }.forEach { $0.isEnabled = enabled }
    }

    // MARK: - Subview Configurations (Peek, HUD & Expanded)

    private func setupPeekView() {
        peekContainerView.wantsLayer = true
        
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        peekIconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Notch")?.withSymbolConfiguration(config)
        peekIconView.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        peekIconView.translatesAutoresizingMaskIntoConstraints = false

        peekLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        peekLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        peekLabel.lineBreakMode = .byTruncatingTail
        peekLabel.translatesAutoresizingMaskIntoConstraints = false

        peekSubLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        peekSubLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        peekSubLabel.lineBreakMode = .byTruncatingTail
        peekSubLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [peekIconView, peekLabel, peekSubLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        peekContainerView.addSubview(stack)

        NSLayoutConstraint.activate([
            peekIconView.widthAnchor.constraint(equalToConstant: 18),
            peekIconView.heightAnchor.constraint(equalToConstant: 18),
            stack.centerXAnchor.constraint(equalTo: peekContainerView.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: peekContainerView.bottomAnchor, constant: -7)
        ])
    }

    private func updatePeekContent() {
        let media = MediaManager.shared
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        if let item = media.currentItem, !item.title.isEmpty {
            peekIconView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Playing")?.withSymbolConfiguration(config)
            peekIconView.contentTintColor = item.appName == "Spotify" ? NSColor(red: 29/255, green: 185/255, blue: 84/255, alpha: 1.0) : NSColor(red: 250/255, green: 35/255, blue: 59/255, alpha: 1.0)
            peekLabel.stringValue = item.title
            peekSubLabel.stringValue = item.artist
        } else {
            peekIconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Dynamico")?.withSymbolConfiguration(config)
            peekIconView.contentTintColor = .white
            peekLabel.stringValue = "Dynamico"
            peekSubLabel.stringValue = "Click to expand"
        }

        let newPeekW = calculatePeekWidth()
        if abs(newPeekW - calculatedPeekWidth) > 1 {
            calculatedPeekWidth = newPeekW
            if trackingController?.currentState == .peek {
                updateShapeForCurrentState(animated: true)
            }
        }
    }

    private func updateHUDContent(type: NotchHUDType, level: Double) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let percentInt = Int(min(max(level, 0.0), 1.0) * 100.0)

        switch type {
        case .volume:
            let iconName = level <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
            peekIconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Volume")?.withSymbolConfiguration(config)
            peekIconView.contentTintColor = NSColor(red: 0, green: 210/255, blue: 255/255, alpha: 1.0)
            peekLabel.stringValue = "Volume"
            peekSubLabel.stringValue = "\(percentInt)%"

        case .brightness:
            peekIconView.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness")?.withSymbolConfiguration(config)
            peekIconView.contentTintColor = NSColor.systemYellow
            peekLabel.stringValue = "Brightness"
            peekSubLabel.stringValue = "\(percentInt)%"
        }
    }

    private func setupExpandedView() {
        expandedContainerView.wantsLayer = true

        headerView.translatesAutoresizingMaskIntoConstraints = false
        tabButtonsStack.orientation = .horizontal
        tabButtonsStack.spacing = 4
        tabButtonsStack.alignment = .centerY
        tabButtonsStack.translatesAutoresizingMaskIntoConstraints = false

        rightButtonsStack.orientation = .horizontal
        rightButtonsStack.spacing = 6
        rightButtonsStack.alignment = .centerY
        rightButtonsStack.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(tabButtonsStack)
        headerView.addSubview(rightButtonsStack)

        let contentHost = NSView()
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        expandedContainerView.addSubview(headerView)
        expandedContainerView.addSubview(contentHost)
        self.tabContentHostView = contentHost

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: expandedContainerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: expandedContainerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: expandedContainerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: max(physicalNotchHeight, 32)),

            tabButtonsStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 10),
            tabButtonsStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            rightButtonsStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            rightButtonsStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            contentHost.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentHost.leadingAnchor.constraint(equalTo: expandedContainerView.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: expandedContainerView.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: expandedContainerView.bottomAnchor)
        ])

        rebuildHeaderButtons()
    }

    public func rebuildHeaderButtons() {
        tabButtonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rightButtonsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let isExpanded = trackingController?.currentState.isExpanded == true

        for tab in SettingsManager.shared.activeLeftTabs {
            let btn = createTabButton(for: tab)
            btn.isEnabled = isExpanded
            tabButtonsStack.addArrangedSubview(btn)
        }

        let settingsBtn = NSButton(title: "Settings", target: self, action: #selector(openSettingsClicked))
        settingsBtn.bezelStyle = .inline
        settingsBtn.isBordered = false
        settingsBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        settingsBtn.contentTintColor = NSColor.white.withAlphaComponent(0.6)
        let settingsConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        settingsBtn.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?.withSymbolConfiguration(settingsConfig)
        settingsBtn.imagePosition = .imageLeading
        settingsBtn.isEnabled = isExpanded

        let collapseConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let collapseImg = NSImage(systemSymbolName: "chevron.up.circle.fill", accessibilityDescription: "Collapse")?.withSymbolConfiguration(collapseConfig)
        let collapseBtn = NSButton(image: collapseImg ?? NSImage(), target: self, action: #selector(collapseClicked))
        collapseBtn.isBordered = false
        collapseBtn.bezelStyle = .inline
        collapseBtn.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        collapseBtn.isEnabled = isExpanded

        rightButtonsStack.addArrangedSubview(settingsBtn)
        rightButtonsStack.addArrangedSubview(collapseBtn)
    }

    private func createTabButton(for tab: NotchTab) -> NSButton {
        let isSelected = controller?.selectedTab == tab
        let isExpanded = trackingController?.currentState.isExpanded == true
        let title = SettingsManager.shared.showTabLabels ? tab.title : ""
        let btn = NSButton(title: title, target: self, action: #selector(tabButtonClicked(_:)))
        btn.identifier = NSUserInterfaceItemIdentifier(tab.rawValue)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        if let img = NSImage(systemSymbolName: tab.rawValue, accessibilityDescription: tab.title)?.withSymbolConfiguration(config) {
            btn.image = img
            btn.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        btn.contentTintColor = isSelected ? .white : NSColor.white.withAlphaComponent(0.45)
        btn.isEnabled = isExpanded
        return btn
    }

    @objc private func tabButtonClicked(_ sender: NSButton) {
        guard trackingController?.currentState.isExpanded == true else { return }
        guard ProcessInfo.processInfo.systemUptime - expansionTimestamp > 0.25 else { return }
        guard let rawVal = sender.identifier?.rawValue, let tab = NotchTab(rawValue: rawVal) else { return }
        Theme.playHaptic(.alignment)
        trackingController?.selectTab(tab)
        rebuildHeaderButtons()
        updateShapeForCurrentState(animated: true)
    }

    @objc private func openSettingsClicked() {
        guard trackingController?.currentState.isExpanded == true else { return }
        guard ProcessInfo.processInfo.systemUptime - expansionTimestamp > 0.25 else { return }
        Theme.playHaptic(.alignment)
        SettingsWindowManager.shared.showSettingsWindow()
    }

    @objc private func collapseClicked() {
        guard trackingController?.currentState.isExpanded == true else { return }
        guard ProcessInfo.processInfo.systemUptime - expansionTimestamp > 0.25 else { return }
        Theme.playHaptic(.levelChange)
        trackingController?.setNotchState(.collapsed, animated: true)
    }

    // MARK: - Content Mounting / Unmounting (Hosting View Cache)

    private func mountExpandedContentView(for activeTab: NotchTab? = nil) {
        guard let hostView = tabContentHostView else { return }
        let selectedTab = activeTab ?? controller?.selectedTab ?? .spotify
        
        let oldHostingView = currentHostingView

        let hostingView: NSHostingView<AnyView>
        if let cached = hostingViewCache[selectedTab] {
            hostingView = cached
        } else {
            let content: AnyView
            switch selectedTab {
            case .spotify: content = AnyView(MediaPlayerView())
            case .clipboard: content = AnyView(ClipboardView())
            case .fileShelf: content = AnyView(FileShelfView())
            case .power: content = AnyView(BatteryView())
            case .todoist: content = AnyView(TodoistView())
            default: content = AnyView(MediaPlayerView())
            }

            let newHosting = NSHostingView(rootView: content)
            newHosting.autoresizingMask = [.width, .height]
            newHosting.wantsLayer = true
            hostingViewCache[selectedTab] = newHosting
            hostingView = newHosting
        }

        hostingView.frame = hostView.bounds
        hostingView.layer?.opacity = 0.0
        hostingView.layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1.0)
        
        hostView.addSubview(hostingView)
        currentHostingView = hostingView

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            hostingView.animator().layer?.opacity = 1.0
            hostingView.animator().layer?.transform = CATransform3DIdentity
            
            oldHostingView?.animator().layer?.opacity = 0.0
        } completionHandler: {
            if oldHostingView !== hostingView {
                oldHostingView?.removeFromSuperview()
            }
        }
    }

    private func unmountExpandedContentView() {
        currentHostingView?.removeFromSuperview()
        currentHostingView = nil
    }

    // MARK: - Tracking Area Override

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingController?.updateTrackingArea(for: self)
    }
}
