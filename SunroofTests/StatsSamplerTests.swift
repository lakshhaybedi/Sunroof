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

    // Apple Silicon sensor names → chip / GPU / SSD / battery averages; junk readings (-9201 °C) are dropped.
    @Test func temperatureGroups() {
        let t = Temperatures.summarize([("PMU tdie1", 55.0), ("PMU tdie2", 51.0), ("PMU tdev1", -9201.1),
                                        ("NAND CH0 temp", 38.0), ("gas gauge battery", 32.0), ("gas gauge battery", 34.0),
                                        ("GPU MTR Temp Sensor1", 47.0), ("PMU tcal", 51.8)])
        #expect(t.chip == 53 && t.gpu == 47 && t.ssd == 38 && t.battery == 33)
        #expect(Temperatures.summarize([]).chip == nil)
    }

    @Test func temperatureFormat() {
        #expect(Temperatures.format(52.6) == "53°")
    }

    @MainActor @Test func diskSizeIsShort() {
        #expect(StatsWidget.diskSize(621_300_000_000) == "621 GB")
        #expect(StatsWidget.diskSize(1_240_000_000_000) == "1.2 TB")
    }
}
