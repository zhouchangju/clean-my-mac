import Foundation
import Testing
import PerformanceDomain
import PerformanceCore

private actor ControlledSampler: PerformanceSampler {
    var systemCalls = 0
    var processCalls = 0
    var volumeCalls = 0
    var active = 0
    var maximumActive = 0
    private var gate: CheckedContinuation<Void, Never>?
    var blocked = false

    func setBlocked(_ value: Bool) { blocked = value }
    func unblock() { blocked = false; gate?.resume(); gate = nil }
    func counts() -> (Int, Int, Int, Int) { (systemCalls, processCalls, volumeCalls, maximumActive) }

    func readSystem() async -> RawSystemSample {
        systemCalls += 1; active += 1; maximumActive = max(maximumActive, active)
        if blocked { await withCheckedContinuation { gate = $0 } }
        active -= 1
        let date = Date()
        return .init(ticks: .measured(.init(user: UInt64(systemCalls * 10), system: 0, idle: UInt64(systemCalls * 90), nice: 0), at: date, source: "fixture"),
                     memoryUsedBytes: .measured(100, at: date, source: "fixture"),
                     memoryTotalBytes: .measured(200, at: date, source: "fixture"),
                     pressure: .unavailable(.unknown, source: "fixture", reason: "unknown"))
    }
    func readProcesses() async -> RawProcessSample {
        processCalls += 1
        return .init(processes: [], monotonicNanoseconds: UInt64(processCalls), sampledAt: Date())
    }
    func readStartupVolume() async -> VolumeSnapshot {
        volumeCalls += 1
        return .init(volumeID: "fixture", availableBytes: .measured(50, at: Date(), source: "fixture"),
                     totalBytes: .measured(100, at: Date(), source: "fixture"))
    }
}

private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
    for _ in 0..<1000 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw WaitFailure.timedOut
}
private enum WaitFailure: Error { case timedOut }

@Test func duplicateConsumersAndTwoEntrancesShareOneWorker() async throws {
    let sampler = ControlledSampler()
    let session = SamplingSession(sampler: sampler, interval: .milliseconds(10))
    let consumer = UUID()
    let overview = await session.acquire(consumerID: consumer, demand: .overview)
    let repeated = await session.acquire(consumerID: consumer, demand: .overview)
    #expect(overview.id == repeated.id)
    let detail = await session.acquire(consumerID: UUID(), demand: .detail)
    try await waitUntil { await sampler.counts().1 >= 2 }
    #expect(await session.subscriberCount == 2)
    #expect(await sampler.counts().3 == 1)
    await session.release(detail.id)
    let afterRelease = await sampler.counts().1
    try await Task.sleep(for: .milliseconds(35))
    #expect(await sampler.counts().1 == afterRelease)
    await session.release(overview.id)
    try await Task.sleep(for: .milliseconds(10))
    let stopped = await sampler.counts().0
    try await Task.sleep(for: .milliseconds(35))
    #expect(await sampler.counts().0 == stopped)
    await session.shutdown()
}

@Test func canceledReadDrainsBeforeReacquireAndOldLeaseCannotReleaseNew() async throws {
    let sampler = ControlledSampler()
    await sampler.setBlocked(true)
    let session = SamplingSession(sampler: sampler, interval: .milliseconds(5))
    let consumer = UUID()
    let old = await session.acquire(consumerID: consumer, demand: .overview)
    try await waitUntil { await sampler.counts().0 == 1 }
    await session.release(old.id)
    let fresh = await session.acquire(consumerID: consumer, demand: .detail)
    await session.release(old.id)
    #expect(old.id != fresh.id)
    #expect(await session.subscriberCount == 1)
    #expect(await sampler.counts().0 == 1)
    await sampler.unblock()
    try await waitUntil { await sampler.counts().1 > 0 }
    #expect(await sampler.counts().3 == 1)
    #expect(await sampler.counts().2 == 0) // Discarded overview never reaches volume call.
    await session.release(fresh.id)
    await session.shutdown()
}

@Test func suspendDropsOldSampleAndResumeRebuildsCPU() async throws {
    let sampler = ControlledSampler()
    await sampler.setBlocked(true)
    let session = SamplingSession(sampler: sampler, interval: .seconds(10))
    let lease = await session.acquire(consumerID: UUID(), demand: .overview)
    try await waitUntil { await sampler.counts().0 == 1 }
    await session.suspend()
    await sampler.unblock()
    try await Task.sleep(for: .milliseconds(15))
    #expect(await session.snapshot().sequence == 0)
    await session.resume()
    try await waitUntil { await session.snapshot().sequence == 1 }
    #expect(await session.snapshot().system?.cpuPercent.quality == .warmingUp)
    await session.release(lease.id)
    await session.shutdown()
    let post = await session.acquire(consumerID: UUID(), demand: .detail)
    var iterator = post.snapshots.makeAsyncIterator()
    #expect(await iterator.next() == nil)
}

@Test func repeatedVisibilityDoesNotLeakSubscribers() async throws {
    let sampler = ControlledSampler()
    let session = SamplingSession(sampler: sampler)
    let consumer = UUID()
    for _ in 0..<50 {
        let lease = await session.acquire(consumerID: consumer, demand: .overview)
        await session.release(lease.id)
    }
    try await Task.sleep(for: .milliseconds(15))
    #expect(await session.subscriberCount == 0)
    #expect(await sampler.counts().3 <= 1)
    await session.shutdown()
}

@Test func renewedVisibilityCannotBeReleasedByAnOlderCanceledObserver() async {
    let session = SamplingSession(sampler: ControlledSampler())
    let consumer = UUID()
    let old = await session.acquire(consumerID: consumer, demand: .overview)
    let fresh = await session.acquire(consumerID: consumer, demand: .overview, renewingExisting: true)
    #expect(old.id != fresh.id)
    await session.release(old.id)
    #expect(await session.subscriberCount == 1)
    await session.release(fresh.id)
    await session.shutdown()
}

private actor AcquisitionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiting = false
    func wait() async { waiting = true; await withCheckedContinuation { continuation = $0 } }
    func isWaiting() -> Bool { waiting }
    func resume() { continuation?.resume(); continuation = nil }
}

@Test func canceledAcquisitionCannotReplaceAHealthyConsumer() async throws {
    let session = SamplingSession(sampler: ControlledSampler())
    let consumer = UUID()
    let healthy = await session.acquire(consumerID: consumer, demand: .overview)
    let gate = AcquisitionGate()
    let pending = Task {
        await gate.wait()
        return await session.acquire(consumerID: consumer, demand: .overview, renewingExisting: true)
    }
    try await waitUntil { await gate.isWaiting() }
    pending.cancel()
    await gate.resume()
    let canceled = await pending.value
    await session.release(canceled.id)
    #expect(await session.subscriberCount == 1)
    await session.release(healthy.id)
    await session.shutdown()
}
