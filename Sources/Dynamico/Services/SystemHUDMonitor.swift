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
    private typealias DisplayServicesGetLinearBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetLinearBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getLinearBrightnessFn: DisplayServicesGetLinearBrightnessFn?
    private var setLinearBrightnessFn: DisplayServicesSetLinearBrightnessFn?

    private init() {
        setupDisplayServices()
        setupVolumeListener()
        setupMediaKeyMonitor()
    }

    // MARK: - DisplayServices Private Framework Loader

    private func setupDisplayServices() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) else {
            return
        }
        if let getPtr = dlsym(handle, "DisplayServicesGetLinearBrightness") {
            getLinearBrightnessFn = unsafeBitCast(getPtr, to: DisplayServicesGetLinearBrightnessFn.self)
        }
        if let setPtr = dlsym(handle, "DisplayServicesSetLinearBrightness") {
            setLinearBrightnessFn = unsafeBitCast(setPtr, to: DisplayServicesSetLinearBrightnessFn.self)
        }
    }

    // MARK: - CoreAudio Volume Listener & Setter

    private func setupVolumeListener() {
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
        if let getFn = getLinearBrightnessFn {
            var brightness: Float = 0.5
            if getFn(CGMainDisplayID(), &brightness) == 0 {
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
        if let setFn = setLinearBrightnessFn {
            _ = setFn(CGMainDisplayID(), clamped)
            return
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        if service != 0 {
            IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
            IOObjectRelease(service)
        }
    }

    // MARK: - Global Media Key Hardware Event Tap (System-Defined Aux Keys)

    private func setupMediaKeyMonitor() {
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
