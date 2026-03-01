import SwiftUI

// MARK: - Scale Factor Environment Key

private struct ScaleFactorKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var scaleFactor: CGFloat {
        get { self[ScaleFactorKey.self] }
        set { self[ScaleFactorKey.self] = newValue }
    }
}

// MARK: - Main Dashboard

struct ContentView: View {
    @EnvironmentObject var stats: SystemStats
    @Environment(\.scaleFactor) private var scaleFactor

    private let referenceWidth: CGFloat = 760

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / referenceWidth

            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.12).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20 * scale) {
                        header
                        metricsGrid
                        networkCard
                        thermalCard
                        bottomRow
                        processListCard
                    }
                    .padding(24 * scale)
                }
            }
            .environment(\.scaleFactor, scale)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("System Monitor v1.3.2")
                    .font(.system(size: 30 * scaleFactor, weight: .bold))
                    .foregroundColor(.white)
                Text(stats.cpuName.isEmpty ? ProcessInfo.processInfo.hostName : stats.cpuName)
                    .font(.system(size: 11 * scaleFactor))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProcessInfo.processInfo.hostName)
                    .font(.system(size: 14 * scaleFactor, weight: .bold))
                    .foregroundColor(.white)
                Text(ProcessInfo.processInfo.operatingSystemVersionString)
                    .font(.system(size: 10 * scaleFactor))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Metrics Grid

    private var metricsGrid: some View {
        HStack(spacing: 16 * scaleFactor) {
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
            VStack(alignment: .leading, spacing: 8 * scaleFactor) {
                HStack(spacing: 14 * scaleFactor) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20 * scaleFactor))
                        .foregroundColor(.cyan)
                        .frame(width: 36 * scaleFactor)
                    VStack(alignment: .leading, spacing: 4 * scaleFactor) {
                        Text("Download")
                            .font(.system(size: 11 * scaleFactor))
                            .foregroundColor(.secondary)
                        Text(formatSpeed(stats.netDownSpeed))
                            .font(.system(size: 20 * scaleFactor, weight: .bold))
                            .foregroundColor(.cyan)
                        Text("Total: \(formatBytes(stats.netTotalIn))")
                            .font(.system(size: 10 * scaleFactor))
                            .foregroundColor(.secondary)
                    }
                }
                SparklineView(data: stats.netDownHistory, color: .cyan)
                    .frame(height: 40 * scaleFactor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 90 * scaleFactor)
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16 * scaleFactor)

            // Upload
            VStack(alignment: .leading, spacing: 8 * scaleFactor) {
                HStack(spacing: 14 * scaleFactor) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20 * scaleFactor))
                        .foregroundColor(.orange)
                        .frame(width: 36 * scaleFactor)
                    VStack(alignment: .leading, spacing: 4 * scaleFactor) {
                        Text("Upload")
                            .font(.system(size: 11 * scaleFactor))
                            .foregroundColor(.secondary)
                        Text(formatSpeed(stats.netUpSpeed))
                            .font(.system(size: 20 * scaleFactor, weight: .bold))
                            .foregroundColor(.orange)
                        Text("Total: \(formatBytes(stats.netTotalOut))")
                            .font(.system(size: 10 * scaleFactor))
                            .foregroundColor(.secondary)
                    }
                }
                SparklineView(data: stats.netUpHistory, color: .orange)
                    .frame(height: 40 * scaleFactor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18 * scaleFactor)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18 * scaleFactor)
    }

    // MARK: Thermal Card

    private var thermalCard: some View {
        HStack(spacing: 0) {
            // Temperature
            HStack(spacing: 14 * scaleFactor) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 20 * scaleFactor))
                    .foregroundColor(tempColor)
                    .frame(width: 36 * scaleFactor)
                VStack(alignment: .leading, spacing: 4 * scaleFactor) {
                    Text("CPU Temp")
                        .font(.system(size: 11 * scaleFactor))
                        .foregroundColor(.secondary)
                    if let t = stats.cpuTemp {
                        Text(String(format: "%.1f °C", t))
                            .font(.system(size: 20 * scaleFactor, weight: .bold))
                            .foregroundColor(tempColor)
                    } else {
                        Text("N/A")
                            .font(.system(size: 20 * scaleFactor, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 48 * scaleFactor)
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16 * scaleFactor)

            // Fans
            HStack(spacing: 14 * scaleFactor) {
                Image(systemName: "fan.fill")
                    .font(.system(size: 20 * scaleFactor))
                    .foregroundColor(.cyan)
                    .frame(width: 36 * scaleFactor)
                VStack(alignment: .leading, spacing: 4 * scaleFactor) {
                    Text("Fans")
                        .font(.system(size: 11 * scaleFactor))
                        .foregroundColor(.secondary)
                    if stats.fanSpeeds.isEmpty {
                        Text("N/A")
                            .font(.system(size: 20 * scaleFactor, weight: .bold))
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 12 * scaleFactor) {
                            ForEach(Array(stats.fanSpeeds.enumerated()), id: \.offset) { i, rpm in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fan \(i + 1)")
                                        .font(.system(size: 10 * scaleFactor))
                                        .foregroundColor(.secondary)
                                    Text("\(rpm) RPM")
                                        .font(.system(size: 13 * scaleFactor, weight: .bold))
                                        .foregroundColor(.cyan)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18 * scaleFactor)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18 * scaleFactor)
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
        HStack(spacing: 16 * scaleFactor) {
            InfoCard(icon: "clock.fill", title: "Uptime") {
                Text(uptimeString)
                    .font(.system(size: 20 * scaleFactor, weight: .bold))
                    .foregroundColor(.white)
            }

            if stats.batteryLevel >= 0 {
                InfoCard(icon: batteryIcon, title: "Battery") {
                    VStack(alignment: .leading, spacing: 2) {
                        // Main number = LONG-TERM HEALTH
                        Text(stats.batteryHealth > 0 ? "\(stats.batteryHealth)%" : "\(stats.batteryLevel)%")
                            .font(.system(size: 20 * scaleFactor, weight: .bold))
                            .foregroundColor(batteryColor)

                        Text("health")
                            .font(.system(size: 10 * scaleFactor))
                            .foregroundColor(.secondary)

                        // Optional: current charge level underneath
                        if stats.batteryHealth > 0 {
                            Text("\(stats.batteryLevel)% charged")
                                .font(.system(size: 11 * scaleFactor))
                                .foregroundColor(.secondary)
                        }

                        if stats.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 14 * scaleFactor))
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }

            InfoCard(icon: "cpu", title: "Processes") {
                Text("\(stats.processCount) running")
                    .font(.system(size: 20 * scaleFactor, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: Process List

    private var processListCard: some View {
        VStack(alignment: .leading, spacing: 12 * scaleFactor) {
            HStack {
                Image(systemName: "list.number")
                    .font(.system(size: 20 * scaleFactor))
                    .foregroundColor(.secondary)
                Text("Processes")
                    .font(.system(size: 15 * scaleFactor, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(stats.processCount) total")
                    .font(.system(size: 11 * scaleFactor))
                    .foregroundColor(.secondary)
            }

            // Column headers
            HStack(spacing: 0) {
                Text("PID")
                    .frame(width: 60 * scaleFactor, alignment: .leading)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Memory")
                    .frame(width: 80 * scaleFactor, alignment: .trailing)
            }
            .font(.system(size: 10 * scaleFactor, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4 * scaleFactor)

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
            .frame(height: 300 * scaleFactor)
        }
        .padding(18 * scaleFactor)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18 * scaleFactor)
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

    @Environment(\.scaleFactor) private var scaleFactor

    private var color: Color {
        switch percent {
        case 0..<0.5: return .green
        case 0.5..<0.8: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 14 * scaleFactor) {
            Text(title)
                .font(.system(size: 15 * scaleFactor, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                ArcShape(startDeg: 135, endDeg: 405)
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 14 * scaleFactor, lineCap: .round))

                ArcShape(startDeg: 135, endDeg: 135 + 270 * percent)
                    .stroke(color,
                            style: StrokeStyle(lineWidth: 14 * scaleFactor, lineCap: .round))
                    .animation(.easeInOut(duration: 0.7), value: percent)

                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 26 * scaleFactor, weight: .bold))
                        .foregroundColor(color)
                    Text(sublabel)
                        .font(.system(size: 10 * scaleFactor))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 130 * scaleFactor)
            .padding(.horizontal, 10 * scaleFactor)
        }
        .padding(18 * scaleFactor)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18 * scaleFactor)
    }
}

// MARK: - Info Card

struct InfoCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.scaleFactor) private var scaleFactor

    var body: some View {
        HStack(spacing: 14 * scaleFactor) {
            Image(systemName: icon)
                .font(.system(size: 20 * scaleFactor))
                .foregroundColor(.secondary)
                .frame(width: 36 * scaleFactor)

            VStack(alignment: .leading, spacing: 4 * scaleFactor) {
                Text(title)
                    .font(.system(size: 11 * scaleFactor))
                    .foregroundColor(.secondary)
                content
            }
            Spacer()
        }
        .padding(18 * scaleFactor)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18 * scaleFactor)
    }
}

// MARK: - Process Row

struct ProcessRow: View {
    let proc: ProcessEntry

    @Environment(\.scaleFactor) private var scaleFactor

    var body: some View {
        HStack(spacing: 0) {
            Text("\(proc.id)")
                .frame(width: 60 * scaleFactor, alignment: .leading)
                .foregroundColor(.secondary)
            Text(proc.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.white)
                .lineLimit(1)
            Text(formattedMem)
                .frame(width: 80 * scaleFactor, alignment: .trailing)
                .foregroundColor(memColor)
        }
        .font(.system(size: 11 * scaleFactor, design: .monospaced))
        .padding(.vertical, 4 * scaleFactor)
        .padding(.horizontal, 4 * scaleFactor)
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

// MARK: - Sparkline

struct SparklineView: View {
    let data: [Double]
    let color: Color

    @Environment(\.scaleFactor) private var scaleFactor

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }
            let maxVal = max(data.max() ?? 1, 1)
            let step = size.width / CGFloat(data.count - 1)

            var path = Path()
            for (i, value) in data.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - (CGFloat(value / maxVal) * size.height)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Fill
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .linearGradient(
                Gradient(colors: [color.opacity(0.3), color.opacity(0.0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            // Stroke
            context.stroke(path, with: .color(color), lineWidth: 1.5 * scaleFactor)
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
