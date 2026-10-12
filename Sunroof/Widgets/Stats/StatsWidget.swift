import SwiftUI

/// What System Stats can show; each can be turned off in Settings › Widgets.
enum StatsMetric: String, CaseIterable {
    case cpu, memory, battery, disk, network

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .battery: "Battery"
        case .disk: "Free disk space"
        case .network: "Network"
        }
    }

    static func shown(hidden: [String]) -> [StatsMetric] { allCases.filter { !hidden.contains($0.rawValue) } }

    /// The Small size has room for two rings (CPU, memory, battery).
    static func rings(hidden: [String]) -> [StatsMetric] {
        Array(shown(hidden: hidden).filter { [.cpu, .memory, .battery].contains($0) }.prefix(2))
    }
}

struct StatsWidget: View {
    let model: StatsModel
    let size: WidgetSize
    @Environment(AppSettings.self) private var settings

    private var memory: Double { Double(model.memoryUsed) / Double(model.memoryTotal) }

    var body: some View {
        let shown = StatsMetric.shown(hidden: settings.hiddenStats)
        if size == .small {
            HStack(spacing: 14) {
                ForEach(StatsMetric.rings(hidden: settings.hiddenStats), id: \.self) { m in
                    switch m {
                    case .cpu: Ring(value: model.cpu, label: "CPU").tint(.green)
                    case .memory: Ring(value: memory, label: "MEM").tint(.blue)
                    default: Ring(value: model.battery?.level ?? 0, label: "BAT").tint(.yellow)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                if shown.contains(.cpu) {
                    Bar(label: "CPU", value: model.cpu, detail: percent(model.cpu)).tint(.green)
                }
                if shown.contains(.memory) {
                    Bar(label: "Memory", value: memory,
                        detail: "\(ByteCountFormatter.string(fromByteCount: Int64(model.memoryUsed), countStyle: .memory)) of \(ByteCountFormatter.string(fromByteCount: Int64(model.memoryTotal), countStyle: .memory))").tint(.blue)
                }
                if shown.contains(.battery) || shown.contains(.disk) {
                    HStack {
                        if shown.contains(.battery), let b = model.battery {
                            Label(percent(b.level), systemImage: b.charging ? "battery.100.bolt" : batterySymbol(b.level))
                        }
                        Spacer()
                        if shown.contains(.disk), let d = model.freeDisk {
                            Label("\(ByteCountFormatter.string(fromByteCount: d, countStyle: .file)) free", systemImage: "internaldrive")
                        }
                    }
                }
                if shown.contains(.network) {
                    HStack {
                        Label(StatsSampler.formatRate(model.down), systemImage: "arrow.down")
                        Spacer()
                        Label(StatsSampler.formatRate(model.up), systemImage: "arrow.up")
                    }
                }
                if shown.isEmpty {
                    Text("Choose what to show in Settings › Widgets").font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.caption.monospacedDigit())
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func batterySymbol(_ level: Double) -> String {
        switch level { case ..<0.15: "battery.0"; case ..<0.4: "battery.25"; case ..<0.65: "battery.50"; case ..<0.9: "battery.75"; default: "battery.100" }
    }

    private struct Ring: View {
        let value: Double
        let label: String
        var body: some View {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: max(0.01, min(value, 1)))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((value * 100).rounded()))").font(.callout.bold().monospacedDigit())
                    Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
            .animation(.easeOut(duration: 0.4), value: value)
        }
    }

    private struct Bar: View {
        let label: String
        let value: Double
        let detail: String
        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text(label).bold(); Spacer(); Text(detail).foregroundStyle(.secondary) }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(.tint).frame(width: g.size.width * max(0.02, min(value, 1)))
                    }
                }
                .frame(height: 5)
            }
            .animation(.easeOut(duration: 0.4), value: value)
        }
    }
}
