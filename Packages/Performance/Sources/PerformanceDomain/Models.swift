import Foundation

public enum MetricQuality: String, Codable, Sendable {
    case measured, warmingUp, permissionDenied, unsupported, unknown, failed
}

public struct Metric<Value: Codable & Sendable>: Codable, Sendable {
    public let value: Value?
    public let quality: MetricQuality
    public let sampledAt: Date?
    public let source: String
    public let reason: String?

    public static func measured(_ value: Value, at date: Date, source: String) -> Self {
        Self(value: value, quality: .measured, sampledAt: date, source: source, reason: nil)
    }

    public static func unavailable(_ quality: MetricQuality, source: String, reason: String) -> Self {
        precondition(quality != .measured)
        return Self(value: nil, quality: quality, sampledAt: nil, source: source, reason: reason)
    }

    private init(value: Value?, quality: MetricQuality, sampledAt: Date?, source: String, reason: String?) {
        self.value = value; self.quality = quality; self.sampledAt = sampledAt
        self.source = source; self.reason = reason
    }

    private enum CodingKeys: String, CodingKey { case value, quality, sampledAt, source, reason }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(Value.self, forKey: .value)
        quality = try c.decode(MetricQuality.self, forKey: .quality)
        sampledAt = try c.decodeIfPresent(Date.self, forKey: .sampledAt)
        source = try c.decode(String.self, forKey: .source)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        guard (quality == .measured && value != nil && sampledAt != nil)
                || (quality != .measured && value == nil) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid metric quality/value"))
        }
    }

    public func isStale(at now: Date, after interval: TimeInterval) -> Bool {
        guard let sampledAt, quality == .measured else { return false }
        let age = now.timeIntervalSince(sampledAt)
        return age < 0 || age > interval
    }
}

public enum MemoryPressure: String, Codable, Sendable { case normal, warning, critical }

public struct ProcessIdentity: Hashable, Codable, Sendable {
    public let pid: Int32
    public let startToken: UInt64
    public init(pid: Int32, startToken: UInt64) { self.pid = pid; self.startToken = startToken }
}

public struct ProcessSnapshot: Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let identity: ProcessIdentity?
    public let name: String
    public let cpuPercent: Metric<Double>
    public let residentBytes: Metric<UInt64>
    public let footprintBytes: Metric<UInt64>
    public init(pid: Int32, identity: ProcessIdentity?, name: String, cpuPercent: Metric<Double>, residentBytes: Metric<UInt64>, footprintBytes: Metric<UInt64>) {
        self.pid = pid; self.identity = identity; self.name = name
        self.cpuPercent = cpuPercent; self.residentBytes = residentBytes; self.footprintBytes = footprintBytes
    }
}

public struct SystemSnapshot: Sendable {
    public let cpuPercent: Metric<Double>
    public let memoryUsedBytes: Metric<UInt64>
    public let memoryTotalBytes: Metric<UInt64>
    public let pressure: Metric<MemoryPressure>
    public init(cpuPercent: Metric<Double>, memoryUsedBytes: Metric<UInt64>, memoryTotalBytes: Metric<UInt64>, pressure: Metric<MemoryPressure>) {
        self.cpuPercent = cpuPercent; self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes; self.pressure = pressure
    }
}

public struct VolumeSnapshot: Sendable {
    public let volumeID: String?
    public let availableBytes: Metric<UInt64>
    public let totalBytes: Metric<UInt64>
    public init(volumeID: String?, availableBytes: Metric<UInt64>, totalBytes: Metric<UInt64>) {
        self.volumeID = volumeID; self.availableBytes = availableBytes; self.totalBytes = totalBytes
    }
}

public struct RawSystemSample: Sendable {
    public let ticks: Metric<CPUTickValues>
    public let memoryUsedBytes: Metric<UInt64>
    public let memoryTotalBytes: Metric<UInt64>
    public let pressure: Metric<MemoryPressure>
    public init(ticks: Metric<CPUTickValues>, memoryUsedBytes: Metric<UInt64>, memoryTotalBytes: Metric<UInt64>, pressure: Metric<MemoryPressure>) {
        self.ticks = ticks; self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes; self.pressure = pressure
    }
}

public struct CPUTickValues: Codable, Sendable {
    public let user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public struct RawProcess: Sendable {
    public let pid: Int32
    public let identity: ProcessIdentity?
    public let name: String
    public let cpuNanoseconds: UInt64?
    public let residentBytes: Metric<UInt64>
    public let footprintBytes: Metric<UInt64>
    public init(pid: Int32, identity: ProcessIdentity?, name: String, cpuNanoseconds: UInt64?, residentBytes: Metric<UInt64>, footprintBytes: Metric<UInt64>) {
        self.pid = pid; self.identity = identity; self.name = name; self.cpuNanoseconds = cpuNanoseconds
        self.residentBytes = residentBytes; self.footprintBytes = footprintBytes
    }
}

public struct RawProcessSample: Sendable {
    public let processes: [RawProcess]
    public let monotonicNanoseconds: UInt64
    public let sampledAt: Date
    public let issue: String?
    public init(processes: [RawProcess], monotonicNanoseconds: UInt64, sampledAt: Date, issue: String? = nil) {
        self.processes = processes; self.monotonicNanoseconds = monotonicNanoseconds
        self.sampledAt = sampledAt; self.issue = issue
    }
}

public protocol PerformanceSampler: Sendable {
    func readSystem() async -> RawSystemSample
    func readProcesses() async -> RawProcessSample
    func readStartupVolume() async -> VolumeSnapshot
}
