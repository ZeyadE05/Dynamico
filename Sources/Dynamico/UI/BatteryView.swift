import SwiftUI

public struct BatteryView: View {
    @ObservedObject var batteryManager = BatteryManager.shared
    @ObservedObject var energyMonitor = EnergyMonitor.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            // Header: Battery Telemetry & State
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: batteryIconName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(batteryColor)

                    Text("\(batteryManager.batteryPercentage)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    Text("•")
                        .foregroundColor(.gray)

                    Text(batteryManager.timeRemainingFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                }

                Spacer()

                // Wattage Badge
                Text(batteryManager.wattageFormatted)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(wattageBackgroundColor)
                    .foregroundColor(wattageForegroundColor)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // System Load & Memory Pressure Metric Row
            HStack(spacing: 8) {
                metricCard(title: "CPU Load", value: String(format: "%.1f%%", energyMonitor.aggregateCPULoad), icon: "cpu", iconColor: Theme.cyanAccent)
                metricCard(title: "RAM Usage", value: energyMonitor.memoryUsageFormatted, icon: "memorychip", iconColor: Theme.purpleAccent)
                metricCard(title: "Battery Health", value: "\(batteryManager.healthPercentage)%", icon: "heart.fill", iconColor: .red)
                metricCard(title: "Cycles", value: "\(batteryManager.cycleCount)", icon: "arrow.triangle.2.circlepath", iconColor: .blue)
            }
            .padding(.horizontal, 16)

            // Top Energy Impact Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Top Energy Impact")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.85))

                    Spacer()

                    if energyMonitor.isSampling {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Button(action: {
                            energyMonitor.sampleTopConsumers(forceRefresh: true)
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.6))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if energyMonitor.topConsumers.isEmpty {
                    HStack {
                        Spacer()
                        Text("Sampling active processes...")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.4))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(energyMonitor.topConsumers) { process in
                            energyProcessRow(process)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            energyMonitor.sampleTopConsumers()
        }
    }

    private func metricCard(title: String, value: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8))
                    .foregroundColor(Color.white.opacity(0.4))
                Text(value)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func energyProcessRow(_ process: EnergyConsumerProcess) -> some View {
        HStack(spacing: 8) {
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Text(process.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.white.opacity(0.85))
                .lineLimit(1)

            Spacer()

            // Bar indicator
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 3)

                    Capsule()
                        .fill(process.cpuPercentage > 30 ? Color.orange : Color.green)
                        .frame(width: max(4, geo.size.width * min(1.0, CGFloat(process.cpuPercentage) / 100.0)), height: 3)
                }
            }
            .frame(width: 45, height: 3)

            Text(String(format: "%.1f%%", process.cpuPercentage))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.6))
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private var batteryIconName: String {
        if batteryManager.isCharging {
            return "battery.100.bolt"
        }
        let level = batteryManager.batteryPercentage
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }

    private var batteryColor: Color {
        if batteryManager.isCharging { return .green }
        if batteryManager.batteryPercentage <= 20 { return .red }
        return .green
    }

    private var wattageBackgroundColor: Color {
        if batteryManager.isCharging {
            return Color.green.opacity(0.15)
        } else if batteryManager.wattageValue < 0 {
            return Color.orange.opacity(0.15)
        } else {
            return Color.white.opacity(0.06)
        }
    }

    private var wattageForegroundColor: Color {
        if batteryManager.isCharging {
            return .green
        } else if batteryManager.wattageValue < 0 {
            return .orange
        } else {
            return Color.white.opacity(0.7)
        }
    }
}
