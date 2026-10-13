import Testing
import Foundation
import Darwin
import PerformanceMacPlatform
import PerformanceCore

@Test func hostSystemAndStartupVolumeProvideRealReadOnlyMetrics() async {
    let sampler = MacPerformanceSampler()
    let system = await sampler.readSystem()
    #expect(system.ticks.value != nil)
    #expect(system.memoryTotalBytes.value == ProcessInfo.processInfo.physicalMemory)
    #expect(system.memoryUsedBytes.value != nil)
    #expect(system.pressure.value == nil) // No guessed mapping or fabricated pressure percentage.
    let volume = await sampler.readStartupVolume()
    #expect(volume.availableBytes.value != nil)
    #expect(volume.totalBytes.value != nil)
}

@Test func hostProcessSampleIncludesSelfWithReliableIdentity() async throws {
    let sample = await MacPerformanceSampler().readProcesses()
    let own = try #require(sample.processes.first { $0.pid == getpid() })
    #expect(own.identity?.startToken != nil)
    #expect(own.cpuNanoseconds != nil)
    #expect(own.footprintBytes.value != nil)
    #expect(sample.monotonicNanoseconds > 0)
}

@Test func hostCPUTimeUnitsMatchIndependentGetrusage() async throws {
    let sampler = MacPerformanceSampler()
    let first = await sampler.readProcesses()
    let before = try #require(first.processes.first { $0.pid == getpid() }?.cpuNanoseconds)
    var r1 = rusage()
    #expect(getrusage(RUSAGE_SELF, &r1) == 0)
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
    var result = 1.0
    while ContinuousClock.now < deadline { result = sin(result) + 1.1 }
    #expect(result.isFinite)
    let second = await sampler.readProcesses()
    let after = try #require(second.processes.first { $0.pid == getpid() }?.cpuNanoseconds)
    var r2 = rusage()
    #expect(getrusage(RUSAGE_SELF, &r2) == 0)
    func ns(_ r: rusage) -> Double {
        Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) * 1_000_000_000
            + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec) * 1_000
    }
    let independent = ns(r2) - ns(r1)
    #expect(independent > 10_000_000)
    let ratio = Double(after - before) / independent
    #expect(ratio > 0.8 && ratio < 1.2)
}

@Test func hostSystemCPUUsesActualTickDeltas() async throws {
    let sampler = MacPerformanceSampler()
    let first = await sampler.readSystem()
    var calculator = CPUCalculator()
    _ = calculator.consume(first.ticks)
    try await Task.sleep(for: .seconds(2))
    let second = await sampler.readSystem()
    let a = try #require(first.ticks.value)
    let b = try #require(second.ticks.value)
    let busy = Double(b.user - a.user) + Double(b.system - a.system) + Double(b.nice - a.nice)
    let idle = Double(b.idle - a.idle)
    let calculated = try #require(calculator.consume(second.ticks).value)
    print("CPU calibration ticks: \(a) -> \(b); calculated=\(calculated)")
    #expect(abs(calculated - busy / (busy + idle) * 100) < 0.001)
    #expect(calculated >= 0 && calculated <= 100)
}
