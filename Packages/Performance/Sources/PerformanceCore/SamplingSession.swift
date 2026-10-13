import Foundation
import PerformanceDomain

public enum SamplingDemand: Sendable { case overview, detail }

public struct PerformanceSnapshot: Sendable {
    public let system: SystemSnapshot?
    public let processes: [ProcessSnapshot]
    public let volume: VolumeSnapshot?
    public let processIssue: String?
    public let sequence: UInt64
    public init(system: SystemSnapshot? = nil, processes: [ProcessSnapshot] = [], volume: VolumeSnapshot? = nil, processIssue: String? = nil, sequence: UInt64 = 0) {
        self.system = system; self.processes = processes; self.volume = volume
        self.processIssue = processIssue; self.sequence = sequence
    }
}

public struct SamplingLease: Sendable {
    public let id: UUID
    public let snapshots: AsyncStream<PerformanceSnapshot>
}

/// A canceled OS read drains before a replacement worker starts. Visibility
/// generations discard its result without creating overlapping collections.
public actor SamplingSession {
    private struct Subscription {
        let consumerID: UUID
        let demand: SamplingDemand
        let continuation: AsyncStream<PerformanceSnapshot>.Continuation
        let stream: AsyncStream<PerformanceSnapshot>
    }
    private let sampler: any PerformanceSampler
    private let interval: Duration
    private let volumeInterval: Duration
    private let clock = ContinuousClock()
    private var subscriptions: [UUID: Subscription] = [:]
    private var consumerLeases: [UUID: UUID] = [:]
    private var worker: Task<Void, Never>?
    private var workerID: UUID?
    private var generation: UInt64 = 0
    private var stopped = false
    private var suspended = false
    private var cpu = CPUCalculator()
    private var processes = ProcessCalculator()
    private var current = PerformanceSnapshot()
    private var lastVolumeAt: ContinuousClock.Instant?

    public init(sampler: any PerformanceSampler, interval: Duration = .seconds(2), volumeInterval: Duration = .seconds(10)) {
        self.sampler = sampler; self.interval = max(.milliseconds(1), interval)
        self.volumeInterval = max(.milliseconds(1), volumeInterval)
    }

    public func acquire(consumerID: UUID, demand: SamplingDemand) -> SamplingLease {
        if let id = consumerLeases[consumerID], let existing = subscriptions[id] {
            switch existing.continuation.yield(current) {
            case .terminated: release(id)
            case .enqueued, .dropped: return SamplingLease(id: id, snapshots: existing.stream)
            @unknown default: release(id)
            }
        }
        let pair = AsyncStream<PerformanceSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        guard !stopped else {
            pair.continuation.finish()
            return SamplingLease(id: id, snapshots: pair.stream)
        }
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.release(id) }
        }
        subscriptions[id] = Subscription(consumerID: consumerID, demand: demand, continuation: pair.continuation, stream: pair.stream)
        consumerLeases[consumerID] = id
        pair.continuation.yield(current)
        ensureWorker()
        return SamplingLease(id: id, snapshots: pair.stream)
    }

    public func release(_ id: UUID) {
        guard let removed = subscriptions.removeValue(forKey: id) else { return }
        consumerLeases.removeValue(forKey: removed.consumerID)
        removed.continuation.finish()
        if subscriptions.isEmpty {
            invalidate()
        } else if !subscriptions.values.contains(where: { $0.demand == .detail }) {
            processes.reset()
            current = .init(system: current.system, volume: current.volume, sequence: current.sequence)
        }
    }

    public func snapshot() -> PerformanceSnapshot { current }
    public var subscriberCount: Int { subscriptions.count }

    public func suspend() { suspended = true; invalidate() }
    public func resume() { suspended = false; ensureWorker() }

    public func shutdown() async {
        stopped = true
        let all = Array(subscriptions.values)
        subscriptions.removeAll()
        consumerLeases.removeAll()
        for sub in all { sub.continuation.finish() }
        invalidate()
        let pending = worker
        await pending?.value
    }

    private func invalidate() {
        generation &+= 1
        cpu.reset(); processes.reset(); lastVolumeAt = nil
        worker?.cancel()
    }

    private func ensureWorker() {
        guard worker == nil, !stopped, !suspended, !subscriptions.isEmpty else { return }
        let id = UUID()
        workerID = id
        worker = Task { [weak self] in await self?.run(id) }
    }

    private func run(_ id: UUID) async {
        while !Task.isCancelled && !stopped && !suspended && !subscriptions.isEmpty {
            let round = generation
            let raw = await sampler.readSystem()
            guard round == generation, !Task.isCancelled else { break }
            let system = SystemSnapshot(cpuPercent: cpu.consume(raw.ticks), memoryUsedBytes: raw.memoryUsedBytes,
                                        memoryTotalBytes: raw.memoryTotalBytes, pressure: raw.pressure)
            var rows = current.processes
            var issue = current.processIssue
            if subscriptions.values.contains(where: { $0.demand == .detail }) {
                let rawProcesses = await sampler.readProcesses()
                guard round == generation, !Task.isCancelled else { break }
                if subscriptions.values.contains(where: { $0.demand == .detail }) {
                    rows = processes.consume(rawProcesses); issue = rawProcesses.issue
                } else { rows = []; issue = nil }
            } else { rows = []; issue = nil }
            var volume = current.volume
            if subscriptions.values.contains(where: { $0.demand == .overview }),
               lastVolumeAt == nil || lastVolumeAt!.duration(to: clock.now) >= volumeInterval {
                volume = await sampler.readStartupVolume()
                guard round == generation, !Task.isCancelled else { break }
                lastVolumeAt = clock.now
            }
            current = .init(system: system, processes: rows, volume: volume, processIssue: issue, sequence: current.sequence &+ 1)
            for sub in subscriptions.values { sub.continuation.yield(current) }
            do { try await clock.sleep(for: interval) } catch { break }
        }
        guard workerID == id else { return }
        worker = nil; workerID = nil
        ensureWorker()
    }
}
