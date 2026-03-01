import SwiftUI
import Darwin
import AppKit

// MARK: - Tab Selection

enum MonitorTab: String, CaseIterable {
    case cpu = "CPU"
    case memory = "Memory"
    case energy = "Energy"
    case disk = "Disk"
    case network = "Network"
}

// MARK: - Sort Column

enum SortColumn {
    case name, cpuUsage, memory, pid
}

// MARK: - Main View

struct ContentView: View {
    @EnvironmentObject var stats: SystemStats
    @State private var selectedTab: MonitorTab = .cpu
    @State private var searchText = ""
    @State private var sortColumn: SortColumn = .cpuUsage
    @State private var sortAscending = false
    @State private var selectedProcessID: pid_t? = nil
    @State private var showProcessInfo = false

    // Resizable column widths — default tab
    @State private var colCPUWidth: CGFloat = 70
    @State private var colMemWidth: CGFloat = 80
    @State private var colThreadsWidth: CGFloat = 60
    @State private var colPIDWidth: CGFloat = 60

    // Energy tab column widths
    @State private var colEnergyImpactWidth: CGFloat = 90
    @State private var colPower12hWidth: CGFloat = 80
    @State private var colAppNapWidth: CGFloat = 60
    @State private var colPreventSleepWidth: CGFloat = 80
    @State private var colEnergyUserWidth: CGFloat = 50

    // Memory tab column widths
    @State private var colMemTabMemWidth: CGFloat = 80
    @State private var colMemTabThreadsWidth: CGFloat = 60
    @State private var colMemTabPortsWidth: CGFloat = 50
    @State private var colMemTabPIDWidth: CGFloat = 55
    @State private var colMemTabUserWidth: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            Divider()

            // Info panel (under tabs) — hide for Energy/Memory tabs (shown at bottom instead)
            if selectedTab != .energy && selectedTab != .memory {
                infoPanel
                Divider()
            }

            // Action bar (End / Info buttons)
            if selectedProcessID != nil {
                actionBar
                Divider()
            }

            // Process table
            processTable

            // Bottom panels for Energy and Memory tabs
            if selectedTab == .energy {
                Divider()
                energyBottomPanel
            } else if selectedTab == .memory {
                Divider()
                memoryBottomPanel
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showProcessInfo) {
            if let pid = selectedProcessID,
               let proc = stats.processes.first(where: { $0.id == pid }) {
                ProcessInfoView(process: proc)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // App title
            VStack(alignment: .leading, spacing: 1) {
                Text("System Monitor v2")
                    .font(.system(size: 13, weight: .bold))
                Text("Steve Jackson 2026")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 8)

            Spacer()

            // Tab buttons
            HStack(spacing: 0) {
                ForEach(MonitorTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            // Search field
            SearchField(text: $searchText, placeholder: "Search Processes")
                .frame(width: 160, height: 22)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Process Table

    private var sortedProcesses: [ProcessEntry] {
        var procs = stats.processes
        switch sortColumn {
        case .name:
            procs.sort { sortAscending ? $0.name < $1.name : $0.name > $1.name }
        case .cpuUsage:
            procs.sort { sortAscending ? $0.cpuUsage < $1.cpuUsage : $0.cpuUsage > $1.cpuUsage }
        case .memory:
            procs.sort { sortAscending ? $0.memoryMB < $1.memoryMB : $0.memoryMB > $1.memoryMB }
        case .pid:
            procs.sort { sortAscending ? $0.id < $1.id : $0.id > $1.id }
        }
        return procs
    }

    private func isMatch(_ proc: ProcessEntry) -> Bool {
        !searchText.isEmpty && proc.name.localizedCaseInsensitiveContains(searchText)
    }

    private func toggleSort(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = false
        }
    }

    private func sortIndicator(_ column: SortColumn) -> String {
        guard sortColumn == column else { return "" }
        return sortAscending ? " ▲" : " ▼"
    }

    private var processTable: some View {
        VStack(spacing: 0) {
            // Column headers
            switch selectedTab {
            case .energy:
                energyColumnHeaders
            case .memory:
                memoryColumnHeaders
            default:
                defaultColumnHeaders
            }

            Divider()

            // Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedProcesses.enumerated()), id: \.element.id) { index, proc in
                        let matched = isMatch(proc)
                        let isSelected = selectedProcessID == proc.id
                        switch selectedTab {
                        case .energy:
                            energyRow(proc: proc, index: index, matched: matched, isSelected: isSelected)
                        case .memory:
                            memoryRow(proc: proc, index: index, matched: matched, isSelected: isSelected)
                        default:
                            defaultRow(proc: proc, index: index, matched: matched, isSelected: isSelected)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Default Columns

    private var defaultColumnHeaders: some View {
        HStack(spacing: 0) {
            headerButton("Process Name", column: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            ColumnResizeHandle(width: $colCPUWidth)
            headerButton("% CPU", column: .cpuUsage, alignment: .trailing)
                .frame(width: colCPUWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colMemWidth)
            headerButton("Memory", column: .memory, alignment: .trailing)
                .frame(width: colMemWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colThreadsWidth)
            Text("Threads")
                .frame(width: colThreadsWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colPIDWidth)
            headerButton("PID", column: .pid, alignment: .trailing)
                .frame(width: colPIDWidth, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func defaultRow(proc: ProcessEntry, index: Int, matched: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 0) {
            processIcon(proc: proc, matched: matched, isSelected: isSelected)

            Text(String(format: "%.1f", proc.cpuUsage))
                .frame(width: colCPUWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : proc.cpuUsage > 50 ? .red : proc.cpuUsage > 10 ? .orange : .primary)

            Text(formatMemory(proc.memoryMB))
                .frame(width: colMemWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .primary)

            Text("—")
                .frame(width: colThreadsWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)

            Text("\(proc.id)")
                .frame(width: colPIDWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor :
            matched ? Color.yellow :
            index % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.3)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedProcessID == proc.id {
                selectedProcessID = nil
            } else {
                selectedProcessID = proc.id
            }
        }
    }

    // MARK: - Energy Columns

    private var energyColumnHeaders: some View {
        HStack(spacing: 0) {
            headerButton("App Name", column: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            ColumnResizeHandle(width: $colEnergyImpactWidth)
            headerButton("Energy Impact", column: .cpuUsage, alignment: .trailing)
                .frame(width: colEnergyImpactWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colPower12hWidth)
            Text("12 hr Power")
                .frame(width: colPower12hWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colAppNapWidth)
            Text("App Nap")
                .frame(width: colAppNapWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colPreventSleepWidth)
            Text("Preventing Sl…")
                .frame(width: colPreventSleepWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colEnergyUserWidth)
            Text("User")
                .frame(width: colEnergyUserWidth, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func energyRow(proc: ProcessEntry, index: Int, matched: Bool, isSelected: Bool) -> some View {
        let energyImpact = proc.cpuUsage * 2.0
        let preventingSleep = proc.cpuUsage > 5.0

        return HStack(spacing: 0) {
            processIcon(proc: proc, matched: matched, isSelected: isSelected)

            Text(String(format: "%.1f", energyImpact))
                .frame(width: colEnergyImpactWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : energyImpact > 50 ? .red : energyImpact > 10 ? .orange : .primary)

            Text(String(format: "%.2f", energyImpact * 0.8))
                .frame(width: colPower12hWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .primary)

            Text(proc.cpuUsage < 1.0 ? "Yes" : "No")
                .frame(width: colAppNapWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)

            Text(preventingSleep ? "Yes" : "No")
                .frame(width: colPreventSleepWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)

            Text(processUser(pid: proc.id))
                .frame(width: colEnergyUserWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor :
            matched ? Color.yellow :
            index % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.3)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedProcessID == proc.id {
                selectedProcessID = nil
            } else {
                selectedProcessID = proc.id
            }
        }
    }

    // Shared process icon + name column
    private func processIcon(proc: ProcessEntry, matched: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "app.dashed")
                .font(.system(size: 10))
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.white.opacity(0.2) : matched ? Color.black.opacity(0.1) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
            Text(proc.name)
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : matched ? .black : .primary)
                .fontWeight(matched ? .bold : .regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func processUser(pid: pid_t) -> String {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        if size > 0 {
            let uid = info.pbi_uid
            if let pw = getpwuid(uid) {
                return String(cString: pw.pointee.pw_name)
            }
        }
        return "—"
    }

    // MARK: - Memory Columns

    private var memoryColumnHeaders: some View {
        HStack(spacing: 0) {
            headerButton("Process Name", column: .name, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            ColumnResizeHandle(width: $colMemTabMemWidth)
            headerButton("Mem…", column: .memory, alignment: .trailing)
                .frame(width: colMemTabMemWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colMemTabThreadsWidth)
            Text("Threads")
                .frame(width: colMemTabThreadsWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colMemTabPortsWidth)
            Text("Ports")
                .frame(width: colMemTabPortsWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colMemTabPIDWidth)
            headerButton("PID", column: .pid, alignment: .trailing)
                .frame(width: colMemTabPIDWidth, alignment: .trailing)
            ColumnResizeHandle(width: $colMemTabUserWidth)
            Text("User")
                .frame(width: colMemTabUserWidth, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func memoryRow(proc: ProcessEntry, index: Int, matched: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 0) {
            processIcon(proc: proc, matched: matched, isSelected: isSelected)

            Text(formatMemory(proc.memoryMB))
                .frame(width: colMemTabMemWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .primary)

            Text("—")
                .frame(width: colMemTabThreadsWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)

            Text("—")
                .frame(width: colMemTabPortsWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)

            Text("\(proc.id)")
                .frame(width: colMemTabPIDWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)

            Text(processUser(pid: proc.id))
                .frame(width: colMemTabUserWidth + 1, alignment: .trailing)
                .foregroundColor(isSelected ? .white : matched ? .black : .secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor :
            matched ? Color.yellow :
            index % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.3)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedProcessID == proc.id {
                selectedProcessID = nil
            } else {
                selectedProcessID = proc.id
            }
        }
    }

    // MARK: - Memory Bottom Panel

    private var memoryBottomPanel: some View {
        HStack(spacing: 0) {
            // Left: Memory Pressure graph
            VStack(alignment: .leading, spacing: 4) {
                Text("MEMORY PRESSURE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                MemoryPressureGraph(
                    data: stats.memPressureHistory.isEmpty ? [0] : Array(stats.memPressureHistory.suffix(60))
                )
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .padding(12)
            .frame(maxWidth: .infinity)

            Divider()

            // Right: Detailed memory stats
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    memoryStatRow("Physical Memory:", value: formatBytes(stats.memTotal))
                    memoryStatRow("Memory Used:", value: formatBytes(stats.memUsed), color: .orange)
                    memoryStatRow("Cached Files:", value: formatBytes(stats.memCached))
                    memoryStatRow("Swap Used:", value: formatBytes(UInt64(stats.memSwapUsed)))
                }

                VStack(alignment: .leading, spacing: 3) {
                    memoryStatRow("App Memory:", value: formatBytes(stats.memApp))
                    memoryStatRow("Wired Memory:", value: formatBytes(stats.memWired))
                    memoryStatRow("Compressed:", value: formatBytes(stats.memCompressed))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 100)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func memoryStatRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private func headerButton(_ title: String, column: SortColumn, alignment: Alignment) -> some View {
        Button(action: { toggleSort(column) }) {
            Text(title + sortIndicator(column))
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            if let pid = selectedProcessID,
               let proc = stats.processes.first(where: { $0.id == pid }) {
                Text(proc.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("(PID: \(proc.id))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showProcessInfo = true }) {
                Text("Info")
                    .font(.system(size: 11))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)

            Button(action: { endSelectedProcess() }) {
                Text("End")
                    .font(.system(size: 11))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func endSelectedProcess() {
        guard let pid = selectedProcessID else { return }
        kill(pid, SIGTERM)
        selectedProcessID = nil
    }

    // MARK: - Info Panel

    private var infoPanel: some View {
        HStack(spacing: 0) {
            switch selectedTab {
            case .cpu:
                cpuBottomBar
            case .memory:
                memoryBottomBar
            case .energy:
                energyBottomBar
            case .disk:
                diskBottomBar
            case .network:
                networkBottomBar
            }
            Spacer()
        }
        .frame(height: 88)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    // CPU tab info panel
    private var cpuBottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                statLabel("System:", value: String(format: "%.2f%%", stats.cpuUsage * 100 * 0.3), color: .red)
                statLabel("User:", value: String(format: "%.2f%%", stats.cpuUsage * 100 * 0.7), color: .green)
                statLabel("Idle:", value: String(format: "%.2f%%", (1.0 - stats.cpuUsage) * 100), color: .primary)
            }
            .padding(.horizontal, 16)

            Divider().frame(height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("CPU LOAD")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                SparklineView(data: stats.perCoreUsage.isEmpty ? [0] : stats.perCoreUsage, color: .green)
                    .frame(width: 120, height: 40)
            }
            .padding(.horizontal, 16)

            Divider().frame(height: 60)

            HStack(spacing: 20) {
                statLabel("Processes:", value: "\(stats.processCount)", color: .primary)
            }
            .padding(.horizontal, 16)
        }
    }

    // Memory tab info panel
    private var memoryBottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                statLabel("Used:", value: formatBytes(stats.memUsed), color: .orange)
                statLabel("Total:", value: formatBytes(stats.memTotal), color: .primary)
                statLabel("Usage:", value: String(format: "%.1f%%", memFraction * 100), color: memFraction > 0.8 ? .red : memFraction > 0.5 ? .yellow : .green)
            }
            .padding(.horizontal, 16)

            Divider().frame(height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("MEMORY PRESSURE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlBackgroundColor))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(memFraction > 0.8 ? Color.red : memFraction > 0.5 ? Color.yellow : Color.green)
                            .frame(width: geo.size.width * CGFloat(memFraction))
                    }
                }
                .frame(width: 120, height: 20)
            }
            .padding(.horizontal, 16)

            Divider().frame(height: 60)

            HStack(spacing: 20) {
                statLabel("Processes:", value: "\(stats.processCount)", color: .primary)
            }
            .padding(.horizontal, 16)
        }
    }

    // Energy tab bottom panel (Activity Monitor style)
    private var energyBottomPanel: some View {
        HStack(spacing: 0) {
            // Left: Energy Impact graph
            VStack(alignment: .leading, spacing: 4) {
                Text("ENERGY IMPACT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                SparklineView(
                    data: stats.energyImpactHistory.isEmpty ? [0] : Array(stats.energyImpactHistory.suffix(60)),
                    color: .red
                )
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .padding(12)
            .frame(maxWidth: .infinity)

            Divider()

            // Right: Battery info + graph
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("BATTERY (Last 12 Hours)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        batteryInfoRow("Remaining charge:", value: stats.batteryLevel >= 0 ? "\(stats.batteryLevel)%" : "100%")
                        batteryInfoRow("Battery is Charged:", value: stats.batteryLevel >= 0 ? (stats.isCharging ? "Charging" : "No") : "AC Power")
                        if let temp = stats.cpuTemp {
                            batteryInfoRow("CPU Temp:", value: String(format: "%.1f °C", temp))
                        }
                    }

                    SparklineView(
                        data: stats.batteryLevelHistory.isEmpty ? [100] : Array(stats.batteryLevelHistory.suffix(60)),
                        color: .green
                    )
                    .frame(width: 100, height: 40)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 100)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func batteryInfoRow(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
        }
    }

    // Energy bottom bar kept for infoPanel switch (not used for Energy tab now)
    private var energyBottomBar: some View {
        EmptyView()
    }

    // Disk tab info panel
    private var diskBottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                statLabel("Used:", value: formatBytes(UInt64(max(0, stats.diskUsed))), color: .orange)
                statLabel("Free:", value: formatBytes(UInt64(max(0, stats.diskTotal - stats.diskUsed))), color: .green)
                statLabel("Total:", value: formatBytes(UInt64(max(0, stats.diskTotal))), color: .primary)
            }
            .padding(.horizontal, 16)

            Divider().frame(height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("DISK USAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlBackgroundColor))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(diskFraction > 0.9 ? Color.red : diskFraction > 0.7 ? Color.yellow : Color.blue)
                            .frame(width: geo.size.width * CGFloat(diskFraction))
                    }
                }
                .frame(width: 120, height: 20)
            }
            .padding(.horizontal, 16)

            Divider().frame(height: 60)

            HStack(spacing: 20) {
                statLabel("Usage:", value: String(format: "%.1f%%", diskFraction * 100), color: .primary)
            }
            .padding(.horizontal, 16)
        }
    }

    // Network tab info panel
    private var networkBottomBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                statLabel("Download:", value: formatSpeed(stats.netDownSpeed), color: .cyan)
                statLabel("Upload:", value: formatSpeed(stats.netUpSpeed), color: .orange)
            }
            .padding(.horizontal, 16)

            Divider().frame(height: 60)

            HStack(spacing: 20) {
                statLabel("Total In:", value: formatBytes(stats.netTotalIn), color: .primary)
                statLabel("Total Out:", value: formatBytes(stats.netTotalOut), color: .primary)
            }
            .padding(.horizontal, 16)

            Divider().frame(height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("NETWORK")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    SparklineView(data: stats.netDownHistory.isEmpty ? [0] : stats.netDownHistory.suffix(30).map { $0 }, color: .cyan)
                        .frame(width: 80, height: 36)
                    SparklineView(data: stats.netUpHistory.isEmpty ? [0] : stats.netUpHistory.suffix(30).map { $0 }, color: .orange)
                        .frame(width: 80, height: 36)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func statLabel(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
    }

    private var batteryColor: Color {
        switch stats.batteryLevel {
        case 0..<20:  return .red
        case 20..<40: return .orange
        default:      return .green
        }
    }

    // MARK: - Helpers

    private var memFraction: Double {
        guard stats.memTotal > 0 else { return 0 }
        return Double(stats.memUsed) / Double(stats.memTotal)
    }

    private var diskFraction: Double {
        guard stats.diskTotal > 0 else { return 0 }
        return Double(stats.diskUsed) / Double(stats.diskTotal)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1000 {
            return String(format: "%.2f TB", gb / 1024)
        } else if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.0f MB", Double(bytes) / 1_048_576)
        }
    }

    private func formatSpeed(_ bps: Double) -> String {
        switch bps {
        case ..<1_024:           return String(format: "%.0f B/s", bps)
        case ..<1_048_576:      return String(format: "%.1f KB/s", bps / 1_024)
        case ..<1_073_741_824:  return String(format: "%.1f MB/s", bps / 1_048_576)
        default:                return String(format: "%.2f GB/s", bps / 1_073_741_824)
        }
    }

    private func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        } else if mb >= 1 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }
}

// MARK: - Process Info View

struct ProcessInfoView: View {
    let process: ProcessEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "app.dashed")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.name)
                        .font(.system(size: 16, weight: .bold))
                    Text("Process ID: \(process.id)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                infoRow("Process Name", value: process.name)
                infoRow("PID", value: "\(process.id)")
                infoRow("CPU Usage", value: String(format: "%.1f%%", process.cpuUsage))
                infoRow("Memory", value: formatMemoryInfo(process.memoryMB))
                infoRow("Parent PID", value: parentPID())
                infoRow("User", value: processUser())
                infoRow("Architecture", value: processArchitecture())
                infoRow("Status", value: processStatus())
            }

            Spacer()

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 340, height: 320)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatMemoryInfo(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }

    private func parentPID() -> String {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(process.id, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        if size > 0 {
            return "\(info.pbi_ppid)"
        }
        return "N/A"
    }

    private func processUser() -> String {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(process.id, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        if size > 0 {
            let uid = info.pbi_uid
            if let pw = getpwuid(uid) {
                return String(cString: pw.pointee.pw_name)
            }
            return "\(uid)"
        }
        return "N/A"
    }

    private func processArchitecture() -> String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    private func processStatus() -> String {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(process.id, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        if size > 0 {
            let status = info.pbi_status
            switch status {
            case 1: return "Idle"
            case 2: return "Running"
            case 3: return "Sleeping"
            case 4: return "Stopped"
            case 5: return "Zombie"
            default: return "Running"
            }
        }
        return "Running"
    }
}

// MARK: - Sparkline

struct SparklineView: View {
    let data: [Double]
    let color: Color

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
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }
}

// MARK: - Memory Pressure Graph

struct MemoryPressureGraph: View {
    let data: [Double]

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }
            let step = size.width / CGFloat(data.count - 1)

            var path = Path()
            for (i, value) in data.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - (CGFloat(min(value, 1.0)) * size.height)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Fill with pressure-based gradient
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()

            let pressureColor = pressureColorForLatest
            context.fill(fillPath, with: .linearGradient(
                Gradient(colors: [pressureColor.opacity(0.4), pressureColor.opacity(0.05)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            context.stroke(path, with: .color(pressureColor), lineWidth: 1.5)
        }
    }

    private var pressureColorForLatest: Color {
        let latest = data.last ?? 0
        if latest > 0.8 { return .red }
        if latest > 0.5 { return .yellow }
        return .green
    }
}

// MARK: - Column Resize Handle

struct ColumnResizeHandle: View {
    @Binding var width: CGFloat
    var minWidth: CGFloat = 30

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 1, height: 14)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8, height: 14)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let newWidth = width - value.translation.width
                                width = max(minWidth, newWidth)
                            }
                    )
            )
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - NSSearchField Wrapper
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 11)
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }
    }
}

