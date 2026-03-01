import Foundation
import Darwin
import IOKit
import IOKit.ps

struct ProcessEntry: Identifiable {
    let id: pid_t
    let name: String
    let cpuUsage: Double   // percentage (0–100)
    let memoryMB: Double   // resident memory in MB
}

class SystemStats: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var perCoreUsage: [Double] = []
    @Published var memUsed: UInt64 = 0
    @Published var memTotal: UInt64 = 0
    @Published var memWired: UInt64 = 0
    @Published var memApp: UInt64 = 0
    @Published var memCompressed: UInt64 = 0
    @Published var memCached: UInt64 = 0
    @Published var memSwapUsed: UInt64 = 0
    @Published var memPressureHistory: [Double] = []
    @Published var diskUsed: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var uptime: TimeInterval = 0
    @Published var batteryLevel: Int = -1      // current charge %
    @Published var batteryHealth: Int = -1     // ← NEW: long-term health %
    @Published var isCharging: Bool = false
    @Published var cpuName: String = ""
    @Published var netDownSpeed: Double = 0
    @Published var netUpSpeed: Double = 0
    @Published var netTotalIn: UInt64 = 0
    @Published var netTotalOut: UInt64 = 0
    @Published var netDownHistory: [Double] = []  // bytes/s, last 5 minutes
    @Published var netUpHistory: [Double] = []    // bytes/s, last 5 minutes
    @Published var cpuTemp: Double? = nil
    @Published var fanSpeeds: [Int] = []
    @Published var processes: [ProcessEntry] = []
    @Published var processCount: Int = 0
    @Published var energyImpactHistory: [Double] = []
    @Published var batteryLevelHistory: [Double] = []

    private var timer: Timer?
    private var prevCPUInfo: processor_info_array_t?
    private var prevCPUInfoCount: mach_msg_type_number_t = 0
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var prevNetTime: Date = Date()

    private let workQueue = DispatchQueue(label: "SystemStats.refresh", qos: .utility)
    private var refreshCount = 0

    init() {
        cpuName = readCPUName()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
        if let prev = prevCPUInfo {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: prev),
                          vm_size_t(MemoryLayout<integer_t>.size * Int(prevCPUInfoCount)))
        }
    }

    func refresh() {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.refreshCount += 1

            let (cpu, coreUsages) = self.readCPU()
            let memDetail = self.readMemory()
            let (dUsed, dTotal) = self.readDisk()
            let up = ProcessInfo.processInfo.systemUptime
            let (battery, charging) = self.readBattery()
            let health = self.readBatteryHealth()
            let (netIn, netOut, downSpd, upSpd) = self.readNetwork()
            let temp = SMCReader.shared.cpuTemperature()
            let fans = SMCReader.shared.fanSpeeds()

            // Only refresh process list every 3rd cycle (~6 seconds)
            let shouldRefreshProcs = self.refreshCount % 3 == 0
            let procs: [ProcessEntry]? = shouldRefreshProcs ? self.readProcesses() : nil

            DispatchQueue.main.async {
                let maxSamples = 300

                self.cpuUsage = cpu
                self.perCoreUsage = coreUsages
                self.memUsed = memDetail.used
                self.memTotal = memDetail.total
                self.memWired = memDetail.wired
                self.memApp = memDetail.app
                self.memCompressed = memDetail.compressed
                self.memCached = memDetail.cached
                self.memSwapUsed = memDetail.swapUsed

                // Track memory pressure history
                let pressure = memDetail.total > 0 ? Double(memDetail.used) / Double(memDetail.total) : 0
                self.memPressureHistory.append(pressure)
                if self.memPressureHistory.count > maxSamples {
                    self.memPressureHistory.removeFirst(self.memPressureHistory.count - maxSamples)
                }
                self.diskUsed = dUsed
                self.diskTotal = dTotal
                self.uptime = up
                self.batteryLevel = battery
                self.batteryHealth = health
                self.isCharging = charging
                self.netTotalIn = netIn
                self.netTotalOut = netOut
                self.netDownSpeed = downSpd
                self.netUpSpeed = upSpd
                // Append to history
                self.netDownHistory.append(downSpd)
                self.netUpHistory.append(upSpd)
                if self.netDownHistory.count > maxSamples {
                    self.netDownHistory.removeFirst(self.netDownHistory.count - maxSamples)
                }
                if self.netUpHistory.count > maxSamples {
                    self.netUpHistory.removeFirst(self.netUpHistory.count - maxSamples)
                }
                self.cpuTemp = temp
                self.fanSpeeds = fans
                if let procs {
                    self.processes = procs
                    self.processCount = procs.count
                }

                // Track energy impact history (total energy impact = sum of per-process CPU as proxy)
                let totalEnergyImpact = self.processes.reduce(0.0) { $0 + $1.cpuUsage }
                self.energyImpactHistory.append(totalEnergyImpact)
                if self.energyImpactHistory.count > maxSamples {
                    self.energyImpactHistory.removeFirst(self.energyImpactHistory.count - maxSamples)
                }

                // Track battery level history
                let battLevel = battery >= 0 ? Double(battery) : 100.0
                self.batteryLevelHistory.append(battLevel)
                if self.batteryLevelHistory.count > maxSamples {
                    self.batteryLevelHistory.removeFirst(self.batteryLevelHistory.count - maxSamples)
                }
            }
        }
    }

    // MARK: - NEW: Battery Health
    private func readBatteryHealth() -> Int {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)
                    .takeUnretainedValue() as? [String: Any] else { continue }
            
            if let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int,
               let designCapacity = desc[kIOPSDesignCapacityKey] as? Int,
               designCapacity > 0 {
                let health = Double(maxCapacity) / Double(designCapacity) * 100
                return Int(round(health))
            }
        }
        return -1
    }

    // MARK: - Battery
    private func readBattery() -> (Int, Bool) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)
                    .takeUnretainedValue() as? [String: Any] else { continue }
            let level = desc[kIOPSCurrentCapacityKey] as? Int ?? -1
            let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            return (level, charging)
        }
        return (-1, false)
    }

    // MARK: - CPU Usage
    private func readCPU() -> (Double, [Double]) {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(mach_host_self(),
                                          PROCESSOR_CPU_LOAD_INFO,
                                          &numCPUs,
                                          &cpuInfo,
                                          &numCPUInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return (0, []) }

        var totalUser: Int32 = 0, totalSystem: Int32 = 0
        var totalIdle: Int32 = 0, totalNice: Int32 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser   += info[offset + Int(CPU_STATE_USER)]
            totalSystem += info[offset + Int(CPU_STATE_SYSTEM)]
            totalIdle   += info[offset + Int(CPU_STATE_IDLE)]
            totalNice   += info[offset + Int(CPU_STATE_NICE)]
        }

        var usage: Double = 0
        var perCore: [Double] = []
        if let prev = prevCPUInfo {
            var prevUser: Int32 = 0, prevSystem: Int32 = 0
            var prevIdle: Int32 = 0, prevNice: Int32 = 0
            for i in 0..<Int(numCPUs) {
                let offset = Int(CPU_STATE_MAX) * i
                prevUser   += prev[offset + Int(CPU_STATE_USER)]
                prevSystem += prev[offset + Int(CPU_STATE_SYSTEM)]
                prevIdle   += prev[offset + Int(CPU_STATE_IDLE)]
                prevNice   += prev[offset + Int(CPU_STATE_NICE)]

                // Per-core usage
                let cUser   = info[offset + Int(CPU_STATE_USER)] - prev[offset + Int(CPU_STATE_USER)]
                let cSystem = info[offset + Int(CPU_STATE_SYSTEM)] - prev[offset + Int(CPU_STATE_SYSTEM)]
                let cIdle   = info[offset + Int(CPU_STATE_IDLE)] - prev[offset + Int(CPU_STATE_IDLE)]
                let cNice   = info[offset + Int(CPU_STATE_NICE)] - prev[offset + Int(CPU_STATE_NICE)]
                let cTotal  = cUser + cSystem + cIdle + cNice
                if cTotal > 0 {
                    perCore.append(Double(cUser + cSystem + cNice) / Double(cTotal))
                } else {
                    perCore.append(0)
                }
            }
            let dUser   = totalUser - prevUser
            let dSystem = totalSystem - prevSystem
            let dIdle   = totalIdle - prevIdle
            let dNice   = totalNice - prevNice
            let total   = dUser + dSystem + dIdle + dNice
            if total > 0 {
                usage = Double(dUser + dSystem + dNice) / Double(total)
            }

            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: prev),
                          vm_size_t(MemoryLayout<integer_t>.size * Int(prevCPUInfoCount)))
        }

        prevCPUInfo = cpuInfo
        prevCPUInfoCount = numCPUInfo
        return (usage, perCore)
    }

    // MARK: - Memory
    struct DetailedMemory {
        let used: UInt64
        let total: UInt64
        let wired: UInt64
        let app: UInt64
        let compressed: UInt64
        let cached: UInt64
        let swapUsed: UInt64
    }

    private func readMemory() -> DetailedMemory {
        let total = ProcessInfo.processInfo.physicalMemory
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return DetailedMemory(used: 0, total: total, wired: 0, app: 0, compressed: 0, cached: 0, swapUsed: 0)
        }
        let pageSize = UInt64(vm_kernel_page_size)
        let wired = UInt64(vmStats.wire_count) * pageSize
        let active = UInt64(vmStats.active_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let cached = UInt64(vmStats.external_page_count) * pageSize
        let used = active + wired
        let app = active

        // Read swap usage
        var swapUsed: UInt64 = 0
        var xswUsage = xsw_usage()
        var xswSize = MemoryLayout<xsw_usage>.size
        var swapMib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        if sysctl(&swapMib, 2, &xswUsage, &xswSize, nil, 0) == 0 {
            swapUsed = xswUsage.xsu_used
        }

        return DetailedMemory(used: used, total: total, wired: wired, app: app, compressed: compressed, cached: cached, swapUsed: swapUsed)
    }

    // MARK: - Disk
    private func readDisk() -> (UInt64, UInt64) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = attrs[.systemSize] as? UInt64 ?? 0
            let free  = attrs[.systemFreeSize] as? UInt64 ?? 0
            return (total - free, total)
        } catch {
            return (0, 0)
        }
    }

    // MARK: - Network
    private func readNetwork() -> (UInt64, UInt64, Double, Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0, 0, 0)
        }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("lo") {
                if let data = addr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn  += UInt64(networkData.ifi_ibytes)
                    totalOut += UInt64(networkData.ifi_obytes)
                }
            }
            ptr = addr.pointee.ifa_next
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(prevNetTime)
        var downSpeed: Double = 0
        var upSpeed: Double = 0
        if elapsed > 0 && prevNetIn > 0 {
            downSpeed = Double(totalIn - prevNetIn) / elapsed
            upSpeed   = Double(totalOut - prevNetOut) / elapsed
        }
        prevNetIn   = totalIn
        prevNetOut  = totalOut
        prevNetTime = now

        return (totalIn, totalOut, max(0, downSpeed), max(0, upSpeed))
    }

    // MARK: - CPU Name
    private func readCPUName() -> String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0)
        let result = String(cString: name)
        return result.isEmpty ? "Unknown" : result
    }

    // MARK: - Processes
    private func readProcesses() -> [ProcessEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size: size_t = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size > 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        var actualSize = size
        guard sysctl(&mib, UInt32(mib.count), &procList, &actualSize, nil, 0) == 0 else {
            return []
        }
        let actualCount = actualSize / MemoryLayout<kinfo_proc>.stride

        var entries: [ProcessEntry] = []
        entries.reserveCapacity(actualCount)

        for i in 0..<actualCount {
            let proc = procList[i]
            let pid = proc.kp_proc.p_pid
            if pid == 0 { continue }

            let name: String = {
                let comm = proc.kp_proc.p_comm
                return withUnsafeBytes(of: comm) { buf in
                    guard let ptr = buf.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                        return "?"
                    }
                    return String(cString: ptr)
                }
            }()

            // proc_pidinfo can fail for processes we don't own — use 0 for those
            var taskInfo = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, infoSize)

            let memMB: Double
            if ret == infoSize {
                memMB = Double(taskInfo.pti_resident_size) / (1024 * 1024)
            } else {
                memMB = 0
            }

            entries.append(ProcessEntry(
                id: pid,
                name: name,
                cpuUsage: 0,
                memoryMB: memMB
            ))
        }

        entries.sort { $0.memoryMB > $1.memoryMB }
        return entries
    }
}
