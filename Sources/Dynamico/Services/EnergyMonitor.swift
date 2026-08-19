import Foundation
import AppKit
import Darwin

@MainActor
public final class EnergyMonitor: ObservableObject {
    public static let shared = EnergyMonitor()

    @Published public var topConsumers: [EnergyConsumerProcess] = []
    @Published public var isSampling: Bool = false

    private var lastSampleTime: Date?
    private let sampleInterval: TimeInterval = 5.0 // Refresh at most once every 5 seconds while open

    private init() {}

    /// Triggered strictly on notch panel expansion. Zero timer loops!
    public func sampleTopConsumers(forceRefresh: Bool = false) {
        if let lastSample = lastSampleTime, !forceRefresh {
            if Date().timeIntervalSince(lastSample) < sampleInterval {
                return
            }
        }

        self.isSampling = true
        self.lastSampleTime = Date()

        Task.detached(priority: .userInitiated) {
            let samples = await self.fetchTopEnergyProcesses()
            await MainActor.run {
                self.topConsumers = samples
                self.isSampling = false
            }
        }
    }

    private nonisolated func fetchTopEnergyProcesses() async -> [EnergyConsumerProcess] {
        // Step 1: Collect initial CPU tick snapshot
        let pids1 = getActivePIDs()
        var snapshot1: [pid_t: UInt64] = [:]
        for pid in pids1 {
            if let cpuTime = getCPUTime(for: pid) {
                snapshot1[pid] = cpuTime
            }
        }

        // 100ms sample window for CPU delta
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Step 2: Collect second CPU tick snapshot
        var processImpacts: [(pid_t, String, Double, NSImage?)] = []
        let myPID = ProcessInfo.processInfo.processIdentifier

        for (pid, time1) in snapshot1 {
            guard pid != myPID, pid > 0 else { continue }
            guard let time2 = getCPUTime(for: pid) else { continue }

            let timeDelta = time2 > time1 ? (time2 - time1) : 0
            // Convert nanoseconds delta over 100ms window to CPU percentage
            let cpuPercent = (Double(timeDelta) / 100_000_000.0) * 100.0

            if cpuPercent > 0.5 {
                // Resolve user application details
                if let app = NSRunningApplication(processIdentifier: pid),
                   let appName = app.localizedName,
                   !appName.isEmpty {
                    let icon = app.icon
                    processImpacts.append((pid, appName, cpuPercent, icon))
                }
            }
        }

        // Sort descending by CPU impact
        processImpacts.sort { $0.2 > $1.2 }

        // Deduplicate processes with same application name
        var uniqueApps: [String: EnergyConsumerProcess] = [:]
        for (pid, name, cpu, icon) in processImpacts {
            if let existing = uniqueApps[name] {
                let combinedCPU = existing.cpuPercentage + cpu
                uniqueApps[name] = EnergyConsumerProcess(id: existing.id, name: name, cpuPercentage: combinedCPU, icon: icon)
            } else {
                uniqueApps[name] = EnergyConsumerProcess(id: pid, name: name, cpuPercentage: cpu, icon: icon)
            }
        }

        let sortedResult = Array(uniqueApps.values)
            .sorted { $0.cpuPercentage > $1.cpuPercentage }

        return Array(sortedResult.prefix(4))
    }

    private nonisolated func getActivePIDs() -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 1024)
        let bytesReturned = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let count = Int(bytesReturned) / MemoryLayout<pid_t>.size
        guard count > 0 else { return [] }
        return Array(pids.prefix(count))
    }

    private nonisolated func getCPUTime(for pid: pid_t) -> UInt64? {
        var taskInfo = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
        guard size == MemoryLayout<proc_taskinfo>.size else { return nil }
        return taskInfo.pti_total_user + taskInfo.pti_total_system
    }
}
