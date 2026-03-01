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

// MARK: - Network Time Range

enum NetworkTimeRange: String, CaseIterable {
    case oneMin = "1m"
    case fiveMin = "5m"
    case tenMin = "10m"

    var sampleCount: Int {
        switch self {
        case .oneMin:  return 30   // 1 min at 2s intervals
        case .fiveMin: return 150  // 5 min
        case .tenMin:  return 300  // 10 min
        }
    }
}

// MARK: - Main Dashboard

struct ContentView: View {
    @EnvironmentObject var stats: SystemStats
    @Environment(\.scaleFactor) private var scaleFactor
    @State private var showProcessList = false
    @State private var networkTimeRange: NetworkTimeRange = .fiveMin

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
                        infoRow
                        if showProcessList {
                            processListCard
                        }
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
                    .font(.system(size: 18 * scaleFactor, weight: .bold))
                    .foregroundColor(.white)
                Text("by Steve Jackson 2026")
                    .font(.system(size: 10 * scaleFactor))
                    .foregroundColor(.secondary)
                Text(stats.cpuName.isEmpty ? ProcessInfo.processInfo.hostName : stats.cpuName)
                    .font(.system(size: 10 * scaleFactor))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProcessInfo.processInfo.hostName)
                    .font(.system(size: 10 * scaleFactor, weight: .bold))
                    .foregroundColor(.white)
                Text(ProcessInfo.processInfo.operatingSystemVersionString)
                    .font(.system(size: 8 * scaleFactor))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Metrics Grid

    private var metricsGrid: some View {
        VStack(spacing: 10 * scaleFactor) {
            HStack(spacing: 12 * scaleFactor) {
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

            cpuCoreBarChart
        }
    }

    // MARK: CPU Core Bar Chart

    private var cpuCoreBarChart: some View {
        HStack(alignment: .bottom, spacing: 2 * scaleFactor) {
            ForEach(Array(stats.perCoreUsage.enumerated()), id: \.offset) { index, usage in
                VStack(spacing: 2 * scaleFactor) {
                    RoundedRectangle(cornerRadius: 2 * scaleFactor)
                        .fill(coreColor(usage))
                        .frame(height: max(2 * scaleFactor, 40 * scaleFactor * CGFloat(usage)))

                    Text("\(index)")
                        .font(.system(size: 8 * scaleFactor))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 50 * scaleFactor)
        .padding(10 * scaleFactor)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10 * scaleFactor)
        .animation(.easeInOut(duration: 0.5), value: stats.perCoreUsage)
    }

    private func coreColor(_ usage: Double) -> Color {
        switch usage {
        case 0..<0.5:  return .green
        case 0.5..<0.8: return .yellow
        default:        return .red
        }
    }

    // MARK: Network Card

    private func slicedHistory(_ data: [Double]) -> [Double] {
        let count = networkTimeRange.sampleCount
        if data.count <= count { return data }
        return Array(data.suffix(count))
    }

    private var networkCard: some View {
        VStack(spacing: 8 * scaleFactor) {
            // Time range picker
            HStack(spacing: 6 * scaleFactor) {
                Spacer()
                Text("Range")
                    .font(.system(size: 9 * scaleFactor))
                    .foregroundColor(.secondary)
                Picker("", selection: $networkTimeRange) {
                    ForEach(NetworkTimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140 * scaleFactor)
            }

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
                                .font(.system(size: 14 * scaleFactor, weight: .bold))
                                .foregroundColor(.cyan)
                            Text("Total: \(formatBytes(stats.netTotalIn))")
                                .font(.system(size: 10 * scaleFactor))
                                .foregroundColor(.secondary)
                        }
                    }
                    SparklineView(data: slicedHistory(stats.netDownHistory), color: .cyan)
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
                                .font(.system(size: 14 * scaleFactor, weight: .bold))
                                .foregroundColor(.orange)
                            Text("Total: \(formatBytes(stats.netTotalOut))")
                                .font(.system(size: 10 * scaleFactor))
                                .foregroundColor(.secondary)
                        }
                    }
                    SparklineView(data: slicedHistory(stats.netUpHistory), color: .orange)
                        .frame(height: 40 * scaleFactor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18 * scaleFactor)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18 * scaleFactor)
    }

    // MARK: Info Row (CPU Temp, Battery, Processes)

    private var infoRow: some View {
        HStack(spacing: 10 * scaleFactor) {
            InfoCard(icon: "thermometer.medium", title: "CPU Temp", iconColor: tempColor) {
                if let t = stats.cpuTemp {
                    Text(String(format: "%.1f °C", t))
                        .font(.system(size: 13 * scaleFactor, weight: .bold))
                        .foregroundColor(tempColor)
                } else {
                    Text("N/A")
                        .font(.system(size: 13 * scaleFactor, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }

            if stats.batteryLevel >= 0 {
                InfoCard(icon: batteryIcon, title: "Battery health") {
                    VStack(spacing: 2) {
                        Text(stats.batteryHealth > 0 ? "\(stats.batteryHealth)%" : "\(stats.batteryLevel)%")
                            .font(.system(size: 13 * scaleFactor, weight: .bold))
                            .foregroundColor(batteryColor)

                        if stats.batteryHealth > 0 {
                            Text("\(stats.batteryLevel)% charged")
                                .font(.system(size: 8 * scaleFactor))
                                .foregroundColor(.secondary)
                        }

                        if stats.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10 * scaleFactor))
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }

            InfoCard(icon: "cpu", title: "Processes running (Click to expand)") {
                Text("\(stats.processCount)")
                    .font(.system(size: 13 * scaleFactor, weight: .bold))
                    .foregroundColor(.white)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14 * scaleFactor)
                    .stroke(showProcessList ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .onTapGesture {
                withAnimation {
                    showProcessList.toggle()
                }
            }
        }
    }

    private var tempColor: Color {
        guard let t = stats.cpuTemp else { return .secondary }
        switch t {
        case ..<60:  return .green
        case ..<85:  return .yellow
        default:     return .red
        }
    }

    // MARK: Process List

    private var processListCard: some View {
        VStack(alignment: .leading, spacing: 12 * scaleFactor) {
            HStack {
                Image(systemName: "list.number")
                    .font(.system(size: 17 * scaleFactor))
                    .foregroundColor(.secondary)
                Text("Processes")
                    .font(.system(size: 12 * scaleFactor, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(stats.processCount) total")
                    .font(.system(size: 8 * scaleFactor))
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
            .font(.system(size: 7 * scaleFactor, weight: .bold))
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
        VStack(spacing: 8 * scaleFactor) {
            Text(title)
                .font(.system(size: 10 * scaleFactor, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                ArcShape(startDeg: 135, endDeg: 405)
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 8 * scaleFactor, lineCap: .round))

                ArcShape(startDeg: 135, endDeg: 135 + 270 * percent)
                    .stroke(color,
                            style: StrokeStyle(lineWidth: 8 * scaleFactor, lineCap: .round))
                    .animation(.easeInOut(duration: 0.7), value: percent)

                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 14 * scaleFactor, weight: .bold))
                        .foregroundColor(color)
                    Text(sublabel)
                        .font(.system(size: 7 * scaleFactor))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 70 * scaleFactor)
            .padding(.horizontal, 6 * scaleFactor)
        }
        .padding(12 * scaleFactor)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14 * scaleFactor)
    }
}

// MARK: - Info Card

struct InfoCard<Content: View>: View {
    let icon: String
    let title: String
    var iconColor: Color = .secondary
    @ViewBuilder let content: Content

    @Environment(\.scaleFactor) private var scaleFactor

    var body: some View {
        VStack(spacing: 6 * scaleFactor) {
            Image(systemName: icon)
                .font(.system(size: 16 * scaleFactor))
                .foregroundColor(iconColor)

            Text(title)
                .font(.system(size: 9 * scaleFactor))
                .foregroundColor(.secondary)

            content
        }
        .padding(12 * scaleFactor)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14 * scaleFactor)
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
        .font(.system(size: 8 * scaleFactor, design: .monospaced))
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
