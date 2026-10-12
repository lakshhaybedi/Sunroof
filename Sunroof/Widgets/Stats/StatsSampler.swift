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

extension StatsSampler {
    /// GPU time used by all apps (ns), summed from the graphics driver's per-client statistics.
    /// Unlike "Device Utilization %", this doesn't inflate when the GPU idles at a low clock.
    static func gpuTimeNs() -> UInt64? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var total: UInt64 = 0, found = false
        var acc = IOIteratorNext(it)
        while acc != 0 {
            var children: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(acc, kIOServicePlane, &children) == KERN_SUCCESS {
                var c = IOIteratorNext(children)
                while c != 0 {
                    if let usage = IORegistryEntryCreateCFProperty(c, "AppUsage" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? [[String: Any]] {
                        for u in usage { if let t = u["accumulatedGPUTime"] as? NSNumber { total &+= t.uint64Value; found = true } }
                    }
                    IOObjectRelease(c)
                    c = IOIteratorNext(children)
                }
                IOObjectRelease(children)
            }
            IOObjectRelease(acc)
            acc = IOIteratorNext(it)
        }
        return found ? total : nil
    }

    /// Share of wall time the GPU spent working (0…1).
    static func gpuBusy(prevNs: UInt64, nowNs: UInt64, interval: Double) -> Double {
        guard nowNs > prevNs, interval > 0 else { return 0 }
        return min(1, Double(nowNs - prevNs) / 1e9 / interval)
    }

    /// GPU busy share 0…1 at its current clock, as the driver reports it (fallback only).
    static func gpuUsage() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var best: Double?
        var s = IOIteratorNext(it)
        while s != 0 {
            if let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any], let u = stats["Device Utilization %"] as? NSNumber {
                best = max(best ?? 0, u.doubleValue / 100)
            }
            IOObjectRelease(s)
            s = IOIteratorNext(it)
        }
        return best
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
    private(set) var gpu: Double?
    private(set) var temperatures = Temperatures()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var lastNet: (rx: UInt64, tx: UInt64, at: TimeInterval)?
    @ObservationIgnored private var ticks = 0
    /// Sensors are read off the main thread (76 of them on an M5 Pro) so scrolling never waits on them.
    private static let sensorQueue = DispatchQueue(label: "sunroof.stats.sensors", qos: .utility)
    private nonisolated(unsafe) static var reader: TemperatureReader?
    private nonisolated(unsafe) static var lastGPU: (ns: UInt64, at: TimeInterval)? // used on sensorQueue only

    #if DEBUG
    /// Fixed readings for screenshots and previews.
    func usePreview(cpu: Double, memory: (used: UInt64, total: UInt64), battery: (Double, Bool), freeDisk: Int64, down: Double, up: Double,
                    gpu: Double? = nil, temperatures: Temperatures = Temperatures()) {
        (self.cpu, memoryUsed, memoryTotal, self.battery, self.freeDisk, self.down, self.up) =
            (cpu, memory.used, memory.total, battery, freeDisk, down, up)
        (self.gpu, self.temperatures) = (gpu, temperatures)
    }
    #endif

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
        ticks = 0 // next open reads temperatures and disk right away
        Self.sensorQueue.async { Self.lastGPU = nil } // don't average GPU over the time the shelf was closed
    }

    /// Every assignment redraws the widget (and makes macOS recomposite the blurred shelf), so values are rounded
    /// to what's displayed and only set when they change.
    private func sample() {
        func percent(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        if let t = StatsSampler.cpuTicks() {
            if let prev = lastTicks { set(\.cpu, percent(StatsSampler.cpuUsage(prev: prev, now: t))) }
            lastTicks = t
        }
        if let m = StatsSampler.memory() {
            set(\.memoryUsed, m.used / 100_000_000 * 100_000_000) // shown to 0.1 GB
            set(\.memoryTotal, max(m.total, 1))
        }
        let b = StatsSampler.battery().map { (level: percent($0.level), charging: $0.charging) }
        if b?.level != battery?.level || b?.charging != battery?.charging { battery = b }
        let net = StatsSampler.networkBytes(), now = ProcessInfo.processInfo.systemUptime
        if let p = lastNet {
            let d = StatsSampler.rate(bytes: net.rx, prevBytes: p.rx, interval: now - p.at)
            let u = StatsSampler.rate(bytes: net.tx, prevBytes: p.tx, interval: now - p.at)
            if StatsSampler.formatRate(d) != StatsSampler.formatRate(down) { down = d }
            if StatsSampler.formatRate(u) != StatsSampler.formatRate(up) { up = u }
        }
        lastNet = (net.rx, net.tx, now)
        if ticks % 3 == 0 { readSlowValues(disk: ticks % 60 == 0) } // temperatures and disk change slowly
        ticks += 1
    }

    private func set<T: Equatable>(_ key: ReferenceWritableKeyPath<StatsModel, T>, _ value: T) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    /// Off the main thread: the sensors, and free disk space (asking macOS what it could purge is slow).
    private func readSlowValues(disk: Bool) {
        Self.sensorQueue.async { [weak self] in
            if Self.reader == nil { Self.reader = TemperatureReader() }
            let raw = Self.reader?.read() ?? Temperatures()
            let t = Temperatures(chip: raw.chip?.rounded(), gpu: raw.gpu?.rounded(), ssd: raw.ssd?.rounded(), battery: raw.battery?.rounded())
            let d = disk ? StatsSampler.freeDisk() : nil
            var g: Double?
            let now = ProcessInfo.processInfo.systemUptime
            if let ns = StatsSampler.gpuTimeNs() {
                if let p = Self.lastGPU { g = (StatsSampler.gpuBusy(prevNs: p.ns, nowNs: ns, interval: now - p.at) * 100).rounded() / 100 }
                Self.lastGPU = (ns, now)
            } else {
                g = StatsSampler.gpuUsage().map { ($0 * 100).rounded() / 100 }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if t != self.temperatures { self.temperatures = t }
                    if let g, g != self.gpu { self.gpu = g }
                    if let d, d / 1_000_000_000 != (self.freeDisk ?? -1) / 1_000_000_000 { self.freeDisk = d }
                }
            }
        }
    }
}
