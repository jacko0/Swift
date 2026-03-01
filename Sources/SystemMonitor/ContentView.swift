import SwiftUI

// MARK: - Main Dashboard

struct ContentView: View {
    @EnvironmentObject var stats: SystemStats

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.10, blue: 0.12).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    metricsGrid
                    networkCard
                    thermalCard
                    bottomRow
                    processListCard
                }
                .padding(24)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("System Monitor v1.3")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text(stats.cpuName.isEmpty ? ProcessInfo.processInfo.hostName : stats.cpuName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProcessInfo.processInfo.hostName)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(ProcessInfo.processInfo.operatingSystemVersionString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Metrics Grid

    private var metricsGrid: some View {
        HStack(spacing: 16) {
            GaugeCard(
                title: "CPU",
                percent: stats.cpuUsage,
                label: "\(Int(stats.cpuUsage * 100))%",
                sublabel: "\(ProcessInfo.processInfo.processorCount) cores"
            )
            GaugeCard(
                title: "Memory",
                percent: memFraction,
                label: "\(Int(memFraction * 100))%",
                sublabel: "\(formatBytes(stats.memUsed)) / \(formatBytes(stats.memTotal))"
            )
            GaugeCard(
                title: "Disk",
                percent: diskFraction,
                label: "\(Int(diskFraction * 100))%",
                sublabel: "\(formatBytes(UInt64(max(0, stats.diskUsed)))) / \(formatBytes(UInt64(max(0, stats.diskTotal))))"
            )
        }
    }

    // MARK: Network Card

    private var networkCard: some View {
        HStack(spacing: 0) {
            // Download
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(.cyan)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSpeed(stats.netDownSpeed))
                        .font(.title2.bold())
                        .foregroundColor(.cyan)
                    Text("Total: \(formatBytes(stats.netTotalIn))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 48)
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)

            // Upload
            HStack(spacing: 14) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatSpeed(stats.netUpSpeed))
                        .font(.title2.bold())
                        .foregroundColor(.orange)
                    Text("Total: \(formatBytes(stats.netTotalOut))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
    }

    // MARK: Thermal Card

    private var thermalCard: some View {
        HStack(spacing: 0) {
            // Temperature
            HStack(spacing: 14) {
                Image(systemName: "thermometer.medium")
                    .font(.title2)
                    .foregroundColor(tempColor)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU Temp")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let t = stats.cpuTemp {
                        Text(String(format: "%.1f °C", t))
                            .font(.title2.bold())
                            .foregroundColor(tempColor)
                    } else {
                        Text("N/A")
                            .font(.title2.bold())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 48)
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)

            // Fans
            HStack(spacing: 14) {
                Image(systemName: "fan.fill")
                    .font(.title2)
                    .foregroundColor(.cyan)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fans")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if stats.fanSpeeds.isEmpty {
                        Text("N/A")
                            .font(.title2.bold())
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 12) {
                            ForEach(Array(stats.fanSpeeds.enumerated()), id: \.offset) { i, rpm in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fan \(i + 1)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("\(rpm) RPM")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.cyan)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
    }

    private var tempColor: Color {
        guard let t = stats.cpuTemp else { return .secondary }
        switch t {
        case ..<60:  return .green
        case ..<85:  return .yellow
        default:     return .red
        }
    }

    // MARK: Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 16) {
            InfoCard(icon: "clock.fill", title: "Uptime") {
                Text(uptimeString)
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }

            if stats.batteryLevel >= 0 {
                InfoCard(icon: batteryIcon, title: "Battery") {
                    VStack(alignment: .leading, spacing: 2) {
                        // Main number = LONG-TERM HEALTH
                        Text(stats.batteryHealth > 0 ? "\(stats.batteryHealth)%" : "\(stats.batteryLevel)%")
                            .font(.title2.bold())
                            .foregroundColor(batteryColor)

                        Text("health")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Optional: current charge level underneath
                        if stats.batteryHealth > 0 {
                            Text("\(stats.batteryLevel)% charged")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if stats.isCharging {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }

            InfoCard(icon: "cpu", title: "Processes") {
                Text("\(stats.processCount) running")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: Process List

    private var processListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.number")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Processes")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(stats.processCount) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Column headers
            HStack(spacing: 0) {
                Text("PID")
                    .frame(width: 60, alignment: .leading)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Memory")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.caption2.bold())
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)

            Divider()
                .background(Color.white.opacity(0.1))

            // Process rows in a fixed-height scroll area
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(stats.processes) { proc in
                        ProcessRow(proc: proc)
                    }
                }
            }
            .frame(height: 300)
        }
        .padding(18)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
    }

    // MARK: Helpers

    private var memFraction: Double {
        guard stats.memTotal > 0 else { return 0 }
        return Double(stats.memUsed) / Double(stats.memTotal)
    }

    private var diskFraction: Double {
        guard stats.diskTotal > 0 else { return 0 }
        return Double(stats.diskUsed) / Double(stats.diskTotal)
    }

    private var uptimeString: String {
        let s = Int(stats.uptime)
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    private var batteryIcon: String {
        if stats.isCharging { return "battery.100.bolt" }
        switch stats.batteryLevel {
        case 0..<20:  return "battery.0"
        case 20..<50: return "battery.25"
        case 50..<75: return "battery.50"
        default:      return "battery.100"
        }
    }

    private var batteryColor: Color {
        switch stats.batteryLevel {
        case 0..<20:  return .red
        case 20..<40: return .orange
        default:      return .green
        }
    }

    private func formatSpeed(_ bps: Double) -> String {
        switch bps {
        case ..<1_024:           return String(format: "%.0f B/s",  bps)
        case ..<1_048_576:      return String(format: "%.1f KB/s", bps / 1_024)
        case ..<1_073_741_824:  return String(format: "%.1f MB/s", bps / 1_048_576)
        default:                return String(format: "%.2f GB/s", bps / 1_073_741_824)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1000
            ? String(format: "%.2f TB", gb / 1024)
            : String(format: "%.1f GB", gb)
    }
}

// MARK: - Gauge Card

struct GaugeCard: View {
    let title: String
    let percent: Double
    let label: String
    let sublabel: String

    private var color: Color {
        switch percent {
        case 0..<0.5: return .green
        case 0.5..<0.8: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                ArcShape(startDeg: 135, endDeg: 405)
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))

                ArcShape(startDeg: 135, endDeg: 135 + 270 * percent)
                    .stroke(color,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .animation(.easeInOut(duration: 0.7), value: percent)

                VStack(spacing: 2) {
                    Text(label)
                        .font(.title.bold())
                        .foregroundColor(color)
                    Text(sublabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 130)
            .padding(.horizontal, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
    }
}

// MARK: - Info Card

struct InfoCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                content
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
    }
}

// MARK: - Process Row

struct ProcessRow: View {
    let proc: ProcessEntry

    var body: some View {
        HStack(spacing: 0) {
            Text("\(proc.id)")
                .frame(width: 60, alignment: .leading)
                .foregroundColor(.secondary)
            Text(proc.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.white)
                .lineLimit(1)
            Text(formattedMem)
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(memColor)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private var formattedMem: String {
        let mb = proc.memoryMB
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        } else if mb >= 1 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }

    private var memColor: Color {
        switch proc.memoryMB {
        case 500...: return .red
        case 200...: return .orange
        case 50...:  return .yellow
        default:     return .secondary
        }
    }
}

// MARK: - Arc Shape

struct ArcShape: Shape {
    let startDeg: Double
    let endDeg: Double

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addArc(
                center:     CGPoint(x: rect.midX, y: rect.midY),
                radius:     min(rect.width, rect.height) / 2,
                startAngle: .degrees(startDeg),
                endAngle:   .degrees(endDeg),
                clockwise:  false
            )
        }
    }
}
