import Foundation
import PerformanceDomain

public struct CPUCalculator: Sendable {
    private var previous: CPUTickValues?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func consume(_ metric: Metric<CPUTickValues>) -> Metric<Double> {
        guard let current = metric.value, let date = metric.sampledAt else {
            previous = nil
            return .unavailable(metric.quality, source: metric.source, reason: metric.reason ?? "未取得CPU计数")
        }
        defer { previous = current }
        guard let old = previous else { return .unavailable(.warmingUp, source: metric.source, reason: "正在建立CPU采样基线") }
        let a = [current.user, current.system, current.idle, current.nice]
        let b = [old.user, old.system, old.idle, old.nice]
        guard zip(a, b).allSatisfy({ $0 >= $1 }) else {
            return .unavailable(.warmingUp, source: metric.source, reason: "CPU计数已重置")
        }
        let d = zip(a, b).map { Double($0 - $1) }
        let total = d.reduce(0, +)
        guard total > 0 else { return .unavailable(.warmingUp, source: metric.source, reason: "尚无新的CPU计数") }
        return .measured((d[0] + d[1] + d[3]) / total * 100, at: date, source: metric.source)
    }
}

public struct ProcessCalculator: Sendable {
    private var previous: [ProcessIdentity: (cpu: UInt64, time: UInt64)] = [:]
    public init() {}
    public mutating func reset() { previous.removeAll() }
    public var trackedIdentityCount: Int { previous.count }
    public mutating func consume(_ sample: RawProcessSample) -> [ProcessSnapshot] {
        var next: [ProcessIdentity: (cpu: UInt64, time: UInt64)] = [:]
        let rows = sample.processes.map { p in
            var cpu: Metric<Double> = .unavailable(.unknown, source: "proc_pid_rusage", reason: "未取得可靠进程身份或CPU时间")
            if let identity = p.identity, let total = p.cpuNanoseconds {
                if let old = previous[identity], total >= old.cpu, sample.monotonicNanoseconds > old.time {
                    cpu = .measured(Double(total - old.cpu) / Double(sample.monotonicNanoseconds - old.time) * 100,
                                    at: sample.sampledAt, source: "proc_pid_rusage")
                } else {
                    cpu = .unavailable(.warmingUp, source: "proc_pid_rusage", reason: "正在建立进程CPU基线")
                }
                next[identity] = (total, sample.monotonicNanoseconds)
            }
            return ProcessSnapshot(pid: p.pid, identity: p.identity, name: p.name, cpuPercent: cpu,
                                   residentBytes: p.residentBytes, footprintBytes: p.footprintBytes)
        }
        previous = next
        return rows
    }
}

public enum ProcessSort: String, CaseIterable, Sendable { case cpu, resident, footprint, name }

public enum ProcessRanking {
    public static func rows(_ rows: [ProcessSnapshot], search: String, sort: ProcessSort, limit: Int = 20) -> [ProcessSnapshot] {
        let filtered = rows.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.pid).contains(search) }
        let sorted = filtered.sorted { a, b in
            if sort == .name {
                if a.name != b.name { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            } else {
                let av: Double?, bv: Double?
                switch sort {
                case .cpu: av = a.cpuPercent.value; bv = b.cpuPercent.value
                case .resident: av = a.residentBytes.value.map(Double.init); bv = b.residentBytes.value.map(Double.init)
                case .footprint: av = a.footprintBytes.value.map(Double.init); bv = b.footprintBytes.value.map(Double.init)
                case .name: av = nil; bv = nil
                }
                if av != bv {
                    guard let av else { return false }
                    guard let bv else { return true }
                    return av > bv
                }
            }
            return a.pid < b.pid
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}
