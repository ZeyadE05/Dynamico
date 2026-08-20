import Foundation
import AppKit
import Darwin

@MainActor
public final class EnergyMonitor: ObservableObject {
    public static let shared = EnergyMonitor()

    @Published public var topConsumers: [EnergyConsumerProcess] = []
    @Published public var aggregateCPULoad: Double = 0.0
    @Published public var memoryUsageFormatted: String = "-- GB"
    @Published public var memoryPercentage: Double = 0.0
    @Published public var isSampling: Bool = false

    private var lastSampleTime: Date?
    private let sampleInterval: TimeInterval = 5.0 // Refresh at most once every 5 seconds while open

    private init() {}

    /// Triggered strictly on notch panel expansion. Zero timer loops!
    /// Computes process impacts, aggregate CPU load, and system memory pressure in a single shared pass.
    public func sampleTopConsumers(forceRefresh: Bool = false) {
        if let lastSample = lastSampleTime, !forceRefresh {
            if Date().timeIntervalSince(lastSample) < sampleInterval {
                return
            }
        }

        self.isSampling = true
        self.lastSampleTime = Date()

        Task.detached(priority: .userInitiated) {
            let result = await self.fetchSystemMetricsAndProcesses()
            await MainActor.run {
                self.topConsumers = result.processes
                self.aggregateCPULoad = result.aggregateCPU
                self.memoryUsageFormatted = result.ramFormatted
                self.memoryPercentage = result.ramPercent
                self.isSampling = false
            }
        }
    }

    private nonisolated func fetchSystemMetricsAndProcesses() async -> (processes: [EnergyConsumerProcess], aggregateCPU: Double, ramFormatted: String, ramPercent: Double) {
        // Step 1: Collect initial CPU tick snapshot (Per-PID and System Host)
        let cpuTicks1 = getHostCPUTicks()
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
        let cpuTicks2 = getHostCPUTicks()
        var processImpacts: [(pid_t, String, Double, NSImage?)] = []
        let myPID = ProcessInfo.processInfo.processIdentifier

        for (pid, time1) in snapshot1 {
            guard pid != myPID, pid > 0 else { continue }
            guard let time2 = getCPUTime(for: pid) else { continue }

            let timeDelta = time2 > time1 ? (time2 - time1) : 0
            // Convert nanoseconds delta over 100ms window to CPU percentage
            let cpuPercent = (Double(timeDelta) / 100_000_000.0) * 100.0

            if cpuPercent > 0.5 {
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
        let top4Processes = Array(sortedResult.prefix(4))

        // Step 3: Compute Aggregate System CPU Load %
        let aggregateCPU = calculateHostCPULoad(ticks1: cpuTicks1, ticks2: cpuTicks2)

        // Step 4: Compute System Memory (RAM) Metrics
        let (ramFormatted, ramPercent) = getSystemRAMMetrics()

        return (top4Processes, aggregateCPU, ramFormatted, ramPercent)
    }

    // MARK: - Host System CPU & RAM Utilities

    private nonisolated func getHostCPUTicks() -> host_cpu_load_info? {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? cpuInfo : nil
    }

    private nonisolated func calculateHostCPULoad(ticks1: host_cpu_load_info?, ticks2: host_cpu_load_info?) -> Double {
        guard let t1 = ticks1, let t2 = ticks2 else { return 0.0 }
        let user = Double(t2.cpu_ticks.0 - t1.cpu_ticks.0)
        let system = Double(t2.cpu_ticks.1 - t1.cpu_ticks.1)
        let idle = Double(t2.cpu_ticks.2 - t1.cpu_ticks.2)
        let nice = Double(t2.cpu_ticks.3 - t1.cpu_ticks.3)

        let total = user + system + idle + nice
        guard total > 0 else { return 0.0 }

        let used = user + system + nice
        return (used / total) * 100.0
    }

    private nonisolated func getSystemRAMMetrics() -> (formatted: String, percentage: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return ("-- GB", 0.0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let usedBytes = active + wired + compressed
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        guard totalBytes > 0 else { return ("-- GB", 0.0) }

        let usedGB = Double(usedBytes) / 1_073_741_824.0
        let totalGB = Double(totalBytes) / 1_073_741_824.0
        let percent = (Double(usedBytes) / Double(totalBytes)) * 100.0

        let formatted = String(format: "%.1f / %.0f GB", usedGB, totalGB)
        return (formatted, percent)
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
