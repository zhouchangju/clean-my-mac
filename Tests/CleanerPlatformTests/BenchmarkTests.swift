import Foundation
import Darwin
import Testing
import CleanerDomain
import CleanerCore
import CleanerMacPlatform
import CleanerTestSupport

/// Opt-in only; fixed 100 x 500 x 1KiB on this APFS host. Does not purge OS caches.
@Test(.enabled(if: ProcessInfo.processInfo.environment["LMC_BENCHMARK"] == "1")) func fixed50kBenchmark() async throws {
    let fixture = try Fixture(); defer { try? fixture.cleanup() }
    let attrs = try FileManager.default.attributesOfFileSystem(forPath: fixture.root.path)
    let freeBytes = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
    try #require(freeBytes >= 2 * 1024 * 1024 * 1024)
    let payload = Data(repeating: 65, count: 1024)
    for folder in 0..<100 {
        for file in 0..<500 { _ = try fixture.file("d\(folder)/f\(file)", contents: payload) }
    }
    var occupied: UInt64 = 0
    for folder in 0..<100 {
        for file in 0..<500 {
            var statValue = stat(); try #require(lstat(fixture.root.appendingPathComponent("d\(folder)/f\(file)").path, &statValue) == 0)
            occupied += UInt64(statValue.st_blocks) * 512
        }
    }
    try #require(occupied <= 512 * 1024 * 1024)
    let scope = try MacFileReader().scope(path: fixture.root.path)
    for trial in 1...3 {
        let state = try Fixture(); defer { try? state.cleanup() }
        let store = try SQLiteScanStore(url: state.root.appendingPathComponent("index.sqlite"))
        let start = ContinuousClock.now
        let run = try await ScanCoordinator(store: store, rules: RuleEngine()).scan(scope: scope)
        let elapsed = start.duration(to: .now)
        let summary = try await store.summary(scanID: run.id)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let record = "LMC_BENCH trial=\(trial) wall=\(elapsed) rssPeakBytes=\(usage.ru_maxrss) files=\(summary.entryCount) allocatedFixture=\(occupied) cache=uncontrolled-warm mainThreadBusy=UNVERIFIED"
        print(record)
        #expect(run.state == .completed)
        #expect(summary.entryCount == 50102) // root + 100 directories + 50000 leaves + fixture marker
        #expect(usage.ru_maxrss <= 500 * 1024 * 1024)
    }
}
