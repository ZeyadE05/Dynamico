import AppKit
import CoreAudio
import Combine

/// Event-driven monitor & controller for system volume and display brightness hardware keys.
/// Triggers fluid Dynamic Notch HUD overlays instantly without polling timers.
@MainActor
public final class SystemHUDMonitor: ObservableObject {
    public static let shared = SystemHUDMonitor()

    private var globalEventMonitor: Any?
    private var defaultOutputDeviceID: AudioObjectID = kAudioObjectUnknown

    // DisplayServices Private Framework C function pointers
    private typealias DisplayServicesGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias DisplayServicesGetLinearBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetLinearBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getBrightnessFn: DisplayServicesGetBrightnessFn?
    private var setBrightnessFn: DisplayServicesSetBrightnessFn?
    private var getLinearBrightnessFn: DisplayServicesGetLinearBrightnessFn?
    private var setLinearBrightnessFn: DisplayServicesSetLinearBrightnessFn?

    private init() {
        setupDisplayServices()
        setupVolumeListener()
        setupBrightnessListener()
        setupMediaKeyMonitor()
    }

    // MARK: - DisplayServices Private Framework Loader

    private func setupDisplayServices() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) else {
            return
        }
        if let getPtr = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightnessFn = unsafeBitCast(getPtr, to: DisplayServicesGetBrightnessFn.self)
        }
        if let setPtr = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightnessFn = unsafeBitCast(setPtr, to: DisplayServicesSetBrightnessFn.self)
        }
        if let getLinearPtr = dlsym(handle, "DisplayServicesGetLinearBrightness") {
            getLinearBrightnessFn = unsafeBitCast(getLinearPtr, to: DisplayServicesGetLinearBrightnessFn.self)
        }
        if let setLinearPtr = dlsym(handle, "DisplayServicesSetLinearBrightness") {
            setLinearBrightnessFn = unsafeBitCast(setLinearPtr, to: DisplayServicesSetLinearBrightnessFn.self)
        }
    }

    // MARK: - CoreAudio Volume Listener & Setter

    private func setupVolumeListener() {
        registerDefaultOutputDeviceListener()
        attachVolumeListenerToCurrentDefaultDevice()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.sound.soundchanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVolumeChanged()
            }
        }
    }

    private func registerDefaultOutputDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.attachVolumeListenerToCurrentDefaultDevice()
                self?.handleVolumeChanged()
            }
        }

        _ = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
    }

    private func attachVolumeListenerToCurrentDefaultDevice() {
        var defaultDeviceID = AudioObjectID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )

        guard status == noErr, defaultDeviceID != kAudioObjectUnknown else { return }
        self.defaultOutputDeviceID = defaultDeviceID

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementWildcard
        )

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.handleVolumeChanged()
            }
        }

        AudioObjectAddPropertyListenerBlock(defaultDeviceID, &volumeAddress, DispatchQueue.main, listener)
    }

    // MARK: - Distributed Notification Brightness Listener

    private func setupBrightnessListener() {
        let notificationCenter = DistributedNotificationCenter.default()
        let names = [
            "com.apple.BezelServices.BMDisplayBrightnessChanged",
            "com.apple.screenIsBrightnessLevelChangingNotification",
            "com.apple.screenBrightnessDidChange",
            "com.apple.ambientlight.brightnessNotification",
            "BrightnessChangedNotification"
        ]

        for name in names {
            notificationCenter.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleBrightnessChanged()
                }
            }
        }
    }

    private func handleBrightnessChanged() {
        let brightness = getCurrentDisplayBrightness()
        NotchTrackingController.shared.showHUD(type: .brightness, level: brightness)
    }

    private func handleVolumeChanged() {
        guard let volume = getSystemVolumeScalar() else { return }
        NotchTrackingController.shared.showHUD(type: .volume, level: Double(volume))
    }

    public func getSystemVolumeScalar() -> Float? {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return nil }
        var volume: Float = 0.0
        var propertySize = UInt32(MemoryLayout<Float>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &propertySize, &volume)
        if status == noErr { return volume }

        address.mElement = 1
        let statusCh1 = AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &propertySize, &volume)
        if statusCh1 == noErr { return volume }

        return nil
    }

    public func setSystemVolumeScalar(_ level: Float) {
        guard defaultOutputDeviceID != kAudioObjectUnknown else { return }
        var newVolume = min(max(level, 0.0), 1.0)
        let propertySize = UInt32(MemoryLayout<Float>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        _ = AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, propertySize, &newVolume)

        address.mElement = 1
        _ = AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, propertySize, &newVolume)

        address.mElement = 2
        _ = AudioObjectSetPropertyData(defaultOutputDeviceID, &address, 0, nil, propertySize, &newVolume)
    }

    // MARK: - Display Brightness Getter & Setter

    public func getCurrentDisplayBrightness() -> Double {
        if let getFn = getBrightnessFn {
            var brightness: Float = 0.5
            if getFn(CGMainDisplayID(), &brightness) == 0 {
                return Double(brightness)
            }
        }

        if let getLinearFn = getLinearBrightnessFn {
            var brightness: Float = 0.5
            if getLinearFn(CGMainDisplayID(), &brightness) == 0 {
                return Double(brightness)
            }
        }

        var brightness: Float = 0.5
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        if service != 0 {
            IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            IOObjectRelease(service)
            return Double(brightness)
        }
        return 0.5
    }

    public func setDisplayBrightness(_ level: Double) {
        let clamped = Float(min(max(level, 0.0), 1.0))
        if let setFn = setBrightnessFn {
            _ = setFn(CGMainDisplayID(), clamped)
            return
        }

        if let setLinearFn = setLinearBrightnessFn {
            _ = setLinearFn(CGMainDisplayID(), clamped)
            return
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        if service != 0 {
            IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
            IOObjectRelease(service)
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Global Media Key Hardware Event Tap (Active CGEventTap)

    private func setupMediaKeyMonitor() {
        requestAccessibilityPermissionIfNeeded()

        guard eventTap == nil else { return }

        let eventMask = (1 << NSEvent.EventType.systemDefined.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    let monitor = Unmanaged<SystemHUDMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
                return Unmanaged.passUnretained(event)
            }

            if type.rawValue == 14 { // sysDefined
                if let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
                    let data1 = nsEvent.data1
                    let keyCode = (data1 & 0xFFFF0000) >> 16
                    let keyFlags = data1 & 0x0000FFFF
                    let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA

                    if [0, 1, 2, 3, 7].contains(keyCode) {
                        if isKeyDown {
                            DispatchQueue.main.async {
                                SystemHUDMonitor.shared.handleMediaKey(keyCode: keyCode)
                            }
                        }
                        // Return nil to SWALLOW/CONSUME event, preventing default macOS HUD!
                        return nil
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: selfPtr
        ) {
            self.eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            installPassiveNSEventFallback()
        }
    }

    private func installPassiveNSEventFallback() {
        guard globalEventMonitor == nil else { return }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let data1 = event.data1
            let keyCode = (data1 & 0xFFFF0000) >> 16
            let keyFlags = data1 & 0x0000FFFF
            let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA

            guard isKeyDown else { return }

            Task { @MainActor [weak self] in
                self?.handleMediaKey(keyCode: keyCode)
            }
        }
    }

    public func requestAccessibilityPermissionIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        if !isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission & Restart Required"
                alert.informativeText = "Dynamico requires Accessibility permission to replace the system volume & brightness HUD.\n\nAfter granting permission in System Settings, please restart Dynamico for changes to take effect."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "OK")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func handleMediaKey(keyCode: Int) {
        // Key Codes:
        // 0 = Volume Up, 1 = Volume Down, 2 = Brightness Up, 3 = Brightness Down, 7 = Mute
        switch keyCode {
        case 2: // Brightness Up
            let current = getCurrentDisplayBrightness()
            let next = min(1.0, current + 0.0625)
            setDisplayBrightness(next)
            NotchTrackingController.shared.showHUD(type: .brightness, level: next)

        case 3: // Brightness Down
            let current = getCurrentDisplayBrightness()
            let next = max(0.0, current - 0.0625)
            setDisplayBrightness(next)
            NotchTrackingController.shared.showHUD(type: .brightness, level: next)

        case 0: // Volume Up
            let current = Double(getSystemVolumeScalar() ?? 0.5)
            let next = min(1.0, current + 0.0625)
            setSystemVolumeScalar(Float(next))
            NotchTrackingController.shared.showHUD(type: .volume, level: next)

        case 1: // Volume Down
            let current = Double(getSystemVolumeScalar() ?? 0.5)
            let next = max(0.0, current - 0.0625)
            setSystemVolumeScalar(Float(next))
            NotchTrackingController.shared.showHUD(type: .volume, level: next)

        case 7: // Mute
            let current = Double(getSystemVolumeScalar() ?? 0.5)
            let next = current > 0 ? 0.0 : 0.5
            setSystemVolumeScalar(Float(next))
            NotchTrackingController.shared.showHUD(type: .volume, level: next)

        default:
            break
        }
    }
}
