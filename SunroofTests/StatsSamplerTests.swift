import Foundation
import Testing
@testable import Sunroof

@Suite struct StatsSamplerTests {
    @Test func cpuUsageFromTickDeltas() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 160, system: 70, idle: 870, nice: 0) // +80 busy, +20 idle
        #expect(abs(StatsSampler.cpuUsage(prev: a, now: b) - 0.8) < 0.0001)
        #expect(StatsSampler.cpuUsage(prev: a, now: a) == 0)
    }

    @Test func rates() {
        #expect(StatsSampler.rate(bytes: 3_000, prevBytes: 1_000, interval: 2) == 1_000)
        #expect(StatsSampler.rate(bytes: 10, prevBytes: 1_000, interval: 1) == 0) // counter reset
    }

    @Test func formatting() {
        #expect(StatsSampler.formatRate(0) == "0 KB/s")
        #expect(StatsSampler.formatRate(1_536) == "1.5 KB/s")
        #expect(StatsSampler.formatRate(2_500_000) == "2.5 MB/s")
    }
}
