import Testing
import Foundation
import Darwin
import PerformanceMacPlatform

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
