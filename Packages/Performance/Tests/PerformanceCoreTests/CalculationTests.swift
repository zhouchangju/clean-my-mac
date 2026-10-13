import Foundation
import Testing
import PerformanceDomain
import PerformanceCore

@Test func systemCPUUsesDeltasAndResets() {
    var calc = CPUCalculator()
    let date = Date()
    func sample(_ u: UInt64, _ s: UInt64, _ idle: UInt64) -> Metric<CPUTickValues> {
        .measured(.init(user: u, system: s, idle: idle, nice: 0), at: date, source: "fixture")
    }
    #expect(calc.consume(sample(100, 50, 850)).quality == .warmingUp)
    #expect(calc.consume(sample(120, 60, 920)).value == 30)
    #expect(calc.consume(sample(1, 1, 1)).quality == .warmingUp)
    calc.reset()
    #expect(calc.consume(sample(20, 20, 20)).value == nil)
    #expect(calc.consume(.unavailable(.permissionDenied, source: "fixture", reason: "denied")).quality == .permissionDenied)
}

private func row(_ pid: Int32, start: UInt64?, cpu: UInt64?, name: String = "worker") -> RawProcess {
    .init(pid: pid, identity: start.map { .init(pid: pid, startToken: $0) }, name: name, cpuNanoseconds: cpu,
          residentBytes: .measured(100, at: Date(), source: "fixture"),
          footprintBytes: .unavailable(.permissionDenied, source: "fixture", reason: "denied"))
}

@Test func processIdentityPreventsPIDReuseAndPrunesHistory() {
    var calc = ProcessCalculator()
    let date = Date()
    let first = calc.consume(.init(processes: [row(42, start: 1, cpu: 100)], monotonicNanoseconds: 1_000, sampledAt: date))
    #expect(first[0].cpuPercent.value == nil)
    let second = calc.consume(.init(processes: [row(42, start: 1, cpu: 600)], monotonicNanoseconds: 2_000, sampledAt: date))
    #expect(second[0].cpuPercent.value == 50)
    #expect(second[0].footprintBytes.value == nil)
    #expect(calc.consume(.init(processes: [row(42, start: 2, cpu: 5)], monotonicNanoseconds: 3_000, sampledAt: date))[0].cpuPercent.value == nil)
    #expect(calc.consume(.init(processes: [row(42, start: nil, cpu: 500)], monotonicNanoseconds: 4_000, sampledAt: date))[0].cpuPercent.quality == .unknown)
    #expect(calc.trackedIdentityCount == 0)
}

@Test func rankingFiltersBeforeTrimmingAndMissingValuesSortLast() {
    let date = Date()
    let rows = (1...25).map { n in
        ProcessSnapshot(pid: Int32(n), identity: nil, name: "worker\(n)",
                        cpuPercent: n == 25 ? .unavailable(.unknown, source: "fixture", reason: "missing") : .measured(Double(n), at: date, source: "fixture"),
                        residentBytes: .measured(0, at: date, source: "fixture"), footprintBytes: .unavailable(.unknown, source: "fixture", reason: "missing"))
    }
    #expect(ProcessRanking.rows(rows, search: "", sort: .cpu).first?.pid == 24)
    #expect(ProcessRanking.rows(rows, search: "worker1", sort: .cpu).count == 11)
    #expect(ProcessRanking.rows(rows, search: "worker25", sort: .cpu).first?.pid == 25)
    #expect(ProcessRanking.rows(rows, search: "", sort: .cpu, limit: 100).last?.pid == 25)
}

@Test func malformedMeasuredMetricIsRejectedAndStaleIsIndependent() throws {
    let json = Data(#"{"quality":"measured","source":"fixture"}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Metric<Double>.self, from: json) }
    let date = Date(timeIntervalSince1970: 100)
    let m = Metric<Double>.measured(0, at: date, source: "fixture")
    #expect(m.isStale(at: Date(timeIntervalSince1970: 107), after: 6))
    #expect(m.quality == .measured)
    #expect(m.value == 0)
    let decoded = try JSONDecoder().decode(Metric<Double>.self, from: JSONEncoder().encode(m))
    #expect(decoded.value == 0)
}
