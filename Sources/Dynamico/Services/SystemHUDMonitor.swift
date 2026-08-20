import AppKit
import CoreAudio
import Combine

/// Event-driven monitor for CoreAudio system volume and display brightness changes.
/// Triggers fluid Dynamic Notch HUD overlays without any polling timers.
@MainActor
public final class SystemHUDMonitor: ObservableObject {
    public static let shared = SystemHUDMonitor()

    private var audioDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultOutputDeviceID: AudioObjectID = kAudioObjectUnknown

    private init() {
        setupVolumeListener()
        setupBrightnessObservers()
    }

    // MARK: - CoreAudio Event-Driven Volume Listener

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
            mElement: kAudioObjectPropertyElementMain
        )

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.handleVolumeChanged()
            }
        }
        self.audioDeviceListenerBlock = listener

        AudioObjectAddPropertyListenerBlock(defaultDeviceID, &volumeAddress, DispatchQueue.main, listener)

        // DistributedNotificationCenter fallback observer
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
        if status == noErr {
            return volume
        }

        // Try channel 1 if main element fails
        address.mElement = 1
        let statusCh1 = AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &propertySize, &volume)
        if statusCh1 == noErr {
            return volume
        }

        return nil
    }

    // MARK: - Event-Driven Brightness Observer

    private func setupBrightnessObservers() {
        let brightnessNotifications = [
            "com.apple.brightnessChanged",
            "com.apple.screenIsBrightness",
            "com.apple.brightness.changed",
            "com.apple.ambientlight"
        ]

        for name in brightnessNotifications {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleBrightnessChanged(notification: notification)
                }
            }
        }
    }

    private func handleBrightnessChanged(notification: Notification) {
        var brightness: Double = 0.5

        if let userInfo = notification.userInfo {
            if let level = userInfo["brightness"] as? Double {
                brightness = level
            } else if let level = userInfo["DisplayBrightness"] as? Double {
                brightness = level
            }
        } else {
            brightness = getCurrentDisplayBrightness()
        }

        NotchTrackingController.shared.showHUD(type: .brightness, level: brightness)
    }

    public func getCurrentDisplayBrightness() -> Double {
        var brightness: Float = 0.5
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        if service != 0 {
            IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
            IOObjectRelease(service)
            return Double(brightness)
        }
        return 0.5
    }
}
