import Foundation
import IOKit
import IOKit.ps
import Observation

struct BatteryInfo {
    var percent: Int
    var charging: Bool
    var pluggedIn: Bool
    var minutesRemaining: Int?
    var cycleCount: Int?
    var health: Double?
    var condition: String?
}

/// System monitor: CPU, memory, disk, network and battery.
@MainActor
@Observable
final class SystemStats {
    static let shared = SystemStats()

    var cpu: Double = 0
    var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    var memoryUsed: Int64 = 0
    var memoryTotal: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    var memoryPressure: Double = 0
    var swapUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0
    var netDown: Double = 0
    var netUp: Double = 0
    var battery: BatteryInfo?
    var uptime: TimeInterval = 0
    var thermal: ProcessInfo.ThermalState = .nominal

    private var prevTicks: (used: UInt64, total: UInt64)?
    private var prevNet: (rx: UInt64, tx: UInt64, time: Date)?
    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in SystemStats.shared.refresh() }
        }
    }

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var diskUsedFraction: Double { diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0 }

    func refresh() {
        cpu = readCPU()
        cpuHistory.append(cpu)
        if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
        readMemory()
        readDisk()
        readNetwork()
        battery = readBattery()
        uptime = ProcessInfo.processInfo.systemUptime
        thermal = ProcessInfo.processInfo.thermalState
    }

    private func readCPU() -> Double {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return cpu }
        var used: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(count) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            used += user + sys + nice
            total += user + sys + nice + idle
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        defer { prevTicks = (used, total) }
        guard let prev = prevTicks, total > prev.total else { return 0 }
        return Double(used - prev.used) / Double(total - prev.total)
    }

    private func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Int64(vm_kernel_page_size)
        let active = Int64(stats.active_count) * page
        let wired = Int64(stats.wire_count) * page
        let compressed = Int64(stats.compressor_page_count) * page
        let purgeable = Int64(stats.purgeable_count) * page
        let speculative = Int64(stats.speculative_count) * page
        // Similar to Activity Monitor's "Memory Used".
        let appMemory = Int64(stats.internal_page_count) * page - purgeable
        memoryUsed = max(appMemory + wired + compressed, active + wired + compressed - speculative)
        memoryUsed = min(memoryUsed, memoryTotal)

        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            memoryPressure = [0, 0.2, 0.6, 0.9, 1.0][min(Int(level), 4)]
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = Int64(swap.xsu_used)
        }
    }

    private func readDisk() {
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }

    private func readNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var p = ifaddr
        while let ifa = p {
            let a = ifa.pointee
            if let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = a.ifa_data {
                let name = String(cString: a.ifa_name)
                if !name.hasPrefix("lo") && !name.hasPrefix("utun") && !name.hasPrefix("awdl") && !name.hasPrefix("llw") {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(d.ifi_ibytes)
                    tx += UInt64(d.ifi_obytes)
                }
            }
            p = a.ifa_next
        }
        let now = Date()
        if let prev = prevNet {
            let dt = now.timeIntervalSince(prev.time)
            if dt > 0 {
                netDown = rx >= prev.rx ? Double(rx - prev.rx) / dt : 0
                netUp = tx >= prev.tx ? Double(tx - prev.tx) / dt : 0
            }
        }
        prevNet = (rx, tx, now)
    }

    private func readBattery() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            var info = BatteryInfo(
                percent: max > 0 ? cur * 100 / max : cur,
                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                pluggedIn: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                minutesRemaining: (d[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil },
                condition: d["BatteryHealth"] as? String
            )
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                func prop(_ k: String) -> Int? {
                    IORegistryEntryCreateCFProperty(service, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
                }
                info.cycleCount = prop("CycleCount")
                if let design = prop("DesignCapacity"), design > 0, let raw = prop("AppleRawMaxCapacity") ?? prop("NominalChargeCapacity") {
                    info.health = min(1, Double(raw) / Double(design))
                }
                IOObjectRelease(service)
            }
            return info
        }
        return nil
    }

    var uptimeText: String {
        let d = Int(uptime) / 86400, h = Int(uptime) % 86400 / 3600, m = Int(uptime) % 3600 / 60
        return d > 0 ? "\(d) d \(h) h" : "\(h) h \(m) min"
    }

    var thermalText: String {
        switch thermal {
        case .nominal: String(localized: "Normal")
        case .fair: String(localized: "Warm")
        case .serious: String(localized: "Hot")
        case .critical: String(localized: "Critical")
        @unknown default: "—"
        }
    }

    static func speed(_ bps: Double) -> String {
        Fmt.bytes(Int64(bps)) + "/s"
    }
}
