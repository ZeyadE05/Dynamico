import Foundation
import IOKit
import IOKit.ps
import Combine
import AppKit

public struct EnergyConsumerProcess: Identifiable, Equatable, Sendable {
    public let id: pid_t
    public let name: String
    public let cpuPercentage: Double
    public let icon: NSImage?

    public init(id: pid_t, name: String, cpuPercentage: Double, icon: NSImage?) {
        self.id = id
        self.name = name
        self.cpuPercentage = cpuPercentage
        self.icon = icon
    }
}

@MainActor
public final class BatteryManager: ObservableObject {
    public static let shared = BatteryManager()

    @Published public var batteryPercentage: Int = 100
    @Published public var isCharging: Bool = false
    @Published public var isPluggedIn: Bool = false
    @Published public var isFullyCharged: Bool = false
    @Published public var timeRemainingFormatted: String = "Calculating..."
    @Published public var wattageFormatted: String = "0.0 W"
    @Published public var wattageValue: Double = 0.0
    @Published public var cycleCount: Int = 0
    @Published public var healthPercentage: Int = 100
    @Published public var temperatureFormatted: String = "--°C"

    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    private init() {
        startMonitoring()
        updateBatteryState()
    }

    public func startMonitoring() {
        guard runLoopSource == nil else { return }

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let source = IOPSNotificationCreateRunLoopSource({ contextPointer in
            guard let contextPointer = contextPointer else { return }
            let manager = Unmanaged<BatteryManager>.fromOpaque(contextPointer).takeUnretainedValue()
            Task { @MainActor in
                manager.updateBatteryState()
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            self.runLoopSource = Unmanaged.passRetained(source)
        }
    }

    public func updateBatteryState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let currentCap = description[kIOPSCurrentCapacityKey] as? Int,
               let maxCap = description[kIOPSMaxCapacityKey] as? Int, maxCap > 0 {
                self.batteryPercentage = Int((Double(currentCap) / Double(maxCap)) * 100.0)
            }

            if let powerState = description[kIOPSPowerSourceStateKey] as? String {
                self.isPluggedIn = (powerState == kIOPSACPowerValue)
            }

            if let charging = description[kIOPSIsChargingKey] as? Bool {
                self.isCharging = charging
            }

            if let charged = description[kIOPSIsChargedKey] as? Bool {
                self.isFullyCharged = charged
            }

            // Calculate Time Remaining
            if isCharging {
                if let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int, timeToFull >= 0 {
                    let hours = timeToFull / 60
                    let mins = timeToFull % 60
                    self.timeRemainingFormatted = hours > 0 ? "\(hours)h \(mins)m to full" : "\(mins)m to full"
                } else {
                    self.timeRemainingFormatted = "Charging..."
                }
            } else if isPluggedIn {
                self.timeRemainingFormatted = "Power Adapter"
            } else {
                if let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int, timeToEmpty >= 0 {
                    let hours = timeToEmpty / 60
                    let mins = timeToEmpty % 60
                    self.timeRemainingFormatted = hours > 0 ? "\(hours)h \(mins)m left" : "\(mins)m left"
                } else {
                    self.timeRemainingFormatted = "Calculating..."
                }
            }
        }

        // Query IOKit AppleSmartBattery service for Cycle Count, Health %, Voltage & Amperage
        fetchSmartBatteryDetails()
    }

    private func fetchSmartBatteryDetails() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }

        var properties: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let dict = properties?.takeRetainedValue() as? [String: Any] {
            
            if let cycles = dict["CycleCount"] as? Int {
                self.cycleCount = cycles
            }

            let maxCap = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["MaxCapacity"] as? Int) ?? 0
            let designCap = (dict["DesignCapacity"] as? Int) ?? 0
            if designCap > 0 && maxCap > 0 {
                self.healthPercentage = min(100, Int((Double(maxCap) / Double(designCap)) * 100.0))
            }

            if let tempDeciC = dict["Temperature"] as? Int {
                let celsius = Double(tempDeciC) / 100.0
                self.temperatureFormatted = String(format: "%.1f°C", celsius)
            }

            // Power in Watts (Amps * Volts)
            var currentmA = 0
            if let rawAmps = dict["InstantAmperage"] as? Int {
                currentmA = rawAmps
            } else if let rawAmps = dict["Amperage"] as? Int {
                currentmA = rawAmps
            }

            var voltageMV = 0
            if let rawVolts = dict["Voltage"] as? Int {
                voltageMV = rawVolts
            }

            if voltageMV > 0 && currentmA != 0 {
                let watts = (Double(currentmA) * Double(voltageMV)) / 1_000_000.0
                self.wattageValue = watts
                if watts < 0 {
                    self.wattageFormatted = String(format: "%.1f W", watts)
                } else {
                    self.wattageFormatted = String(format: "+%.1f W", watts)
                }
            } else if isPluggedIn {
                self.wattageFormatted = "AC Power"
            } else {
                self.wattageFormatted = "-- W"
            }
        }
        IOObjectRelease(service)
    }

    deinit {
        if let source = runLoopSource?.takeRetainedValue() {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }
}
