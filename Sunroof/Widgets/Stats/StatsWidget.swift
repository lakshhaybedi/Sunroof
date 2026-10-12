import SwiftUI

/// What System Stats can show; each can be turned off in Settings › Widgets.
enum StatsMetric: String, CaseIterable {
    case cpu, gpu, memory, temperature, battery, disk, network

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .temperature: "Temperatures"
        case .battery: "Battery"
        case .disk: "Free disk space"
        case .network: "Network"
        }
    }

    static func shown(hidden: [String]) -> [StatsMetric] { allCases.filter { !hidden.contains($0.rawValue) } }

    /// The Small size has room for two rings.
    static func rings(hidden: [String]) -> [StatsMetric] {
        let shown = shown(hidden: hidden)
        return Array([StatsMetric.cpu, .memory, .gpu, .battery].filter(shown.contains).prefix(2))
    }
}

struct StatsWidget: View {
    let model: StatsModel
    let size: WidgetSize
    @Environment(AppSettings.self) private var settings

    private var memory: Double { Double(model.memoryUsed) / Double(model.memoryTotal) }
    private var t: Temperatures { model.temperatures }

    var body: some View {
        let shown = StatsMetric.shown(hidden: settings.hiddenStats)
        let temps = shown.contains(.temperature)
        Group {
            if size == .small {
                HStack(spacing: 14) {
                    ForEach(StatsMetric.rings(hidden: settings.hiddenStats), id: \.self) { m in
                        switch m {
                        case .cpu: Ring(value: model.cpu, label: "CPU", temp: temps ? t.chip : nil).tint(.green)
                        case .gpu: Ring(value: model.gpu ?? 0, label: "GPU", temp: temps ? t.gpu : nil).tint(.purple)
                        case .memory: Ring(value: memory, label: "MEM", temp: nil).tint(.blue)
                        default: Ring(value: model.battery?.level ?? 0, label: "BAT", temp: temps ? t.battery : nil).tint(.yellow)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: size == .large ? 12 : 8) {
                    if size == .large {
                        Label("System", systemImage: "cpu").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    if shown.contains(.cpu) {
                        Bar(label: "CPU", value: model.cpu, detail: percent(model.cpu), temp: temps ? t.chip : nil).tint(.green)
                    }
                    if shown.contains(.gpu), let g = model.gpu {
                        Bar(label: "GPU", value: g, detail: percent(g), temp: temps ? t.gpu : nil).tint(.purple)
                    }
                    if shown.contains(.memory) {
                        Bar(label: "Memory", value: memory, detail: "\(gb(model.memoryUsed)) / \(gb(model.memoryTotal))", temp: nil).tint(.blue)
                    }
                    if size == .large, shown.contains(.temperature) { temperatureTiles }
                    if size == .large { Spacer(minLength: 0) }
                    chips(shown)
                    if shown.isEmpty {
                        Text("Choose what to show in Settings › Widgets").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .font(.caption.monospacedDigit())
    }

    /// Small facts in a wrapping row: SSD and battery temperature, battery, free disk, network.
    @ViewBuilder private func chips(_ shown: [StatsMetric]) -> some View {
        let items = chipItems(shown)
        if !items.isEmpty {
            let columns = [GridItem(.adaptive(minimum: size == .large ? 120 : 92), spacing: 6, alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(items, id: \.0) { item in
                    Label(item.1, systemImage: item.0).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08), in: .capsule)
                }
            }
        }
    }

    private func chipItems(_ shown: [StatsMetric]) -> [(String, String)] {
        var out: [(String, String)] = []
        let tempsInChips = shown.contains(.temperature) && size != .large // Large shows them as tiles
        if tempsInChips, let s = t.ssd { out.append(("internaldrive", "SSD " + Temperatures.format(s))) }
        if shown.contains(.battery), let b = model.battery {
            let temp = tempsInChips ? t.battery.map { " · " + Temperatures.format($0) } ?? "" : ""
            out.append((b.charging ? "battery.100.bolt" : batterySymbol(b.level), percent(b.level) + temp))
        }
        if shown.contains(.disk), let d = model.freeDisk {
            out.append(("externaldrive", Self.diskSize(d) + " free"))
        }
        if shown.contains(.network) {
            out.append(("arrow.down", StatsSampler.formatRate(model.down)))
            out.append(("arrow.up", StatsSampler.formatRate(model.up)))
        }
        return out
    }

    /// "621 GB", "1.2 TB": whole gigabytes keep the chip short.
    static func diskSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return gb >= 1000 ? String(format: "%.1f TB", gb / 1000) : String(format: "%.0f GB", gb)
    }

    /// Large: one tile per part that reports a temperature.
    @ViewBuilder private var temperatureTiles: some View {
        let parts: [(String, String, Double?)] = [("cpu", "Chip", t.chip), ("square.stack.3d.up", "GPU", t.gpu),
                                                  ("internaldrive", "SSD", t.ssd), ("battery.75", "Battery", t.battery)]
        let present = parts.compactMap { p in p.2.map { (p.0, p.1, $0) } }
        if !present.isEmpty {
            HStack(spacing: 6) {
                ForEach(present, id: \.1) { symbol, name, c in
                    VStack(spacing: 2) {
                        Text(Temperatures.format(c)).font(.title3.bold().monospacedDigit())
                            .foregroundStyle(c >= 90 ? Color.red : c >= 75 ? .orange : .primary)
                        Label(name, systemImage: symbol).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 10))
                }
            }
        }
    }

    private func gb(_ bytes: UInt64) -> String { String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func batterySymbol(_ level: Double) -> String {
        switch level { case ..<0.15: "battery.0"; case ..<0.4: "battery.25"; case ..<0.65: "battery.50"; case ..<0.9: "battery.75"; default: "battery.100" }
    }

    private struct Ring: View {
        let value: Double
        let label: String
        let temp: Double?
        var body: some View {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: max(0.01, min(value, 1)))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((value * 100).rounded()))").font(.callout.bold().monospacedDigit())
                    Text(temp.map { "\(label) \(Temperatures.format($0))" } ?? label)
                        .font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
        }
    }

    private struct Bar: View {
        let label: String
        let value: Double
        let detail: String
        let temp: Double?
        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(label).bold()
                    if let temp {
                        Label(Temperatures.format(temp), systemImage: "thermometer.medium")
                            .labelStyle(.titleAndIcon).foregroundStyle(temp >= 90 ? Color.red : temp >= 75 ? .orange : .secondary)
                    }
                    Spacer()
                    Text(detail).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(.tint).frame(width: g.size.width * max(0.02, min(value, 1)))
                    }
                }
                .frame(height: 5)
            }
        }
    }
}
