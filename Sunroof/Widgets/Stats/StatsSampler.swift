import Darwin
import Foundation
import IOKit.ps
import Observation

struct CPUTicks: Equatable {
    var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
}

/// Reads system statistics through public APIs only (no permissions).
enum StatsSampler {
    static func cpuUsage(prev: CPUTicks, now: CPUTicks) -> Double {
        let busy = Double((now.user + now.system + now.nice) &- (prev.user + prev.system + prev.nice))
        let idle = Double(now.idle &- prev.idle)
        return busy + idle > 0 ? busy / (busy + idle) : 0
    }

    /// Bytes per second; a counter that went backwards (interface reset) reads as 0.
    static func rate(bytes: UInt64, prevBytes: UInt64, interval: TimeInterval) -> Double {
        guard bytes >= prevBytes, interval > 0 else { return 0 }
        return Double(bytes - prevBytes) / interval
    }

    static func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        let kb = bytesPerSecond / 1024
        return kb < 0.05 ? "0 KB/s" : String(format: "%.1f KB/s", kb)
    }

    // MARK: - Live readings

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    /// (used, total) bytes: active + wired + compressed, like Activity Monitor's "Memory Used".
    static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let page = UInt64(getpagesize())
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (used, ProcessInfo.processInfo.physicalMemory)
    }

    /// (percent 0…1, charging), or nil on Macs without a battery.
    static func battery() -> (level: Double, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (Double(cur) / Double(max), d[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }

    static func freeDisk() -> Int64? {
        try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    /// Total bytes in/out across non-loopback interfaces.
    static func networkBytes() -> (rx: UInt64, tx: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = ptr.pointee
            guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = a.ifa_data,
                  (a.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(d.ifi_ibytes); tx += UInt64(d.ifi_obytes)
        }
        return (rx, tx)
    }
}

/// Live stats, sampled once a second only while the shelf is open.
@MainActor @Observable
final class StatsModel: WidgetModel {
    private(set) var cpu: Double = 0
    private(set) var memoryUsed: UInt64 = 0
    private(set) var memoryTotal: UInt64 = 1
    private(set) var battery: (level: Double, charging: Bool)?
    private(set) var freeDisk: Int64?
    private(set) var down: Double = 0
    private(set) var up: Double = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var lastNet: (rx: UInt64, tx: UInt64, at: TimeInterval)?

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks = nil
        lastNet = nil
    }

    private func sample() {
        if let t = StatsSampler.cpuTicks() {
            if let prev = lastTicks { cpu = StatsSampler.cpuUsage(prev: prev, now: t) }
            lastTicks = t
        }
        if let m = StatsSampler.memory() { memoryUsed = m.used; memoryTotal = max(m.total, 1) }
        battery = StatsSampler.battery()
        freeDisk = StatsSampler.freeDisk()
        let net = StatsSampler.networkBytes(), now = ProcessInfo.processInfo.systemUptime
        if let p = lastNet {
            down = StatsSampler.rate(bytes: net.rx, prevBytes: p.rx, interval: now - p.at)
            up = StatsSampler.rate(bytes: net.tx, prevBytes: p.tx, interval: now - p.at)
        }
        lastNet = (net.rx, net.tx, now)
    }
}
