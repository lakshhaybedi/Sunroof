import Foundation
import IOKit

/// Temperatures in °C, averaged per part (nil when the Mac has no such sensor).
struct Temperatures: Equatable, Sendable {
    var chip: Double?    // CPU (on Apple Silicon: the whole SoC die)
    var gpu: Double?     // only on Macs that report a separate GPU sensor
    var ssd: Double?
    var battery: Double?

    /// Groups raw sensor readings by name. Readings outside 0…130 °C (unused sensors report about −9201) are dropped.
    static func summarize(_ readings: [(name: String, celsius: Double)]) -> Temperatures {
        var groups: [WritableKeyPath<Temperatures, Double?>: [Double]] = [:]
        for (raw, c) in readings where (0...130).contains(c) {
            let n = raw.lowercased()
            let key: WritableKeyPath<Temperatures, Double?>? =
                n.contains("gpu") ? \.gpu
                : n.contains("tdie") || n.contains("cpu") || n.contains("soc") || n.contains("acc") ? \.chip
                : n.contains("nand") || n.contains("ssd") ? \.ssd
                : n.contains("battery") ? \.battery
                : nil
            if let key { groups[key, default: []].append(c) }
        }
        var t = Temperatures()
        for (key, values) in groups { t[keyPath: key] = values.reduce(0, +) / Double(values.count) }
        return t
    }

    static func format(_ c: Double) -> String { "\(Int(c.rounded()))°" }
}

/// Reads the Mac's thermal sensors. macOS has no public API for this; like iStat Menus and Stats, it uses the
/// HID event system (read-only). If Apple changes it, the reader just returns no readings.
final class TemperatureReader: @unchecked Sendable { // used from one serial queue only
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    private let copyProperty: CopyProperty?, copyEvent: CopyEvent?, getFloat: GetFloat?
    private let client: AnyObject?  // must outlive `services`: they belong to this connection
    private let services: [AnyObject]
    private static let temperatureEvent: Int64 = 15 // kIOHIDEventTypeTemperature

    init() {
        let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func sym<T>(_ name: String) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: T.self) } }
        copyProperty = sym("IOHIDServiceClientCopyProperty")
        copyEvent = sym("IOHIDServiceClientCopyEvent")
        getFloat = sym("IOHIDEventGetFloatValue")
        guard let create: Create = sym("IOHIDEventSystemClientCreate"), let setMatching: SetMatching = sym("IOHIDEventSystemClientSetMatching"),
              let copyServices: CopyServices = sym("IOHIDEventSystemClientCopyServices"),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { client = nil; services = []; return }
        self.client = client
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary) // temperature sensors
        services = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
    }

    func read() -> Temperatures {
        guard let copyProperty, let copyEvent, let getFloat else { return Temperatures() }
        let readings: [(name: String, celsius: Double)] = services.compactMap { s in
            guard let name = copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String,
                  let e = copyEvent(s, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            return (name, getFloat(e, Int32(Self.temperatureEvent << 16)))
        }
        return Temperatures.summarize(readings)
    }
}
