import Foundation
import Observation
import AppKit
import PerformanceDomain
import PerformanceCore
import PerformanceMacPlatform

public enum UtilityRoute: String, CaseIterable, Sendable { case storage, performance, settings }

public struct StorageOverview: Sendable {
    public let title: String
    public let detail: String
    public let measuredAt: Date?
    public let incomplete: Bool
    public init(title: String = "尚未扫描", detail: String = "从主窗口选择范围并扫描", measuredAt: Date? = nil, incomplete: Bool = false) {
        self.title = title; self.detail = detail; self.measuredAt = measuredAt; self.incomplete = incomplete
    }
}

@MainActor @Observable
public final class PerformanceController {
    public private(set) var snapshot = PerformanceSnapshot()
    public var storage = StorageOverview()
    public var route: UtilityRoute = .storage
    public var menuEnabled: Bool {
        didSet { preferences.set(menuEnabled, forKey: "overview.menuEnabled") }
    }
    public var intervalSeconds: Double {
        didSet {
            guard [2.0, 5.0, 10.0].contains(intervalSeconds) else { intervalSeconds = oldValue; return }
            preferences.set(intervalSeconds, forKey: "performance.refreshInterval")
            let value = intervalSeconds
            Task { await session.setInterval(.seconds(value)) }
        }
    }
    public var navigate: (@MainActor (UtilityRoute) -> Void)?
    public var freshnessSeconds: TimeInterval { max(6, intervalSeconds * 3) }
    private let preferences: UserDefaults
    @ObservationIgnored private var rankingCache: (search: String, sort: ProcessSort, rows: [ProcessSnapshot])?
    @ObservationIgnored private(set) var rankingComputationCount = 0
    public let session: SamplingSession
    private var observers: [NSObjectProtocol] = []

    public init(sampler: any PerformanceSampler = MacPerformanceSampler(), preferences: UserDefaults = .standard) {
        self.preferences = preferences
        menuEnabled = preferences.object(forKey: "overview.menuEnabled") == nil ? true : preferences.bool(forKey: "overview.menuEnabled")
        let stored = preferences.double(forKey: "performance.refreshInterval")
        let interval = [2.0, 5.0, 10.0].contains(stored) ? stored : 2
        intervalSeconds = interval
        session = SamplingSession(sampler: sampler, interval: .seconds(interval))
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.session.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.session.resume() }
        })
    }

    public func observe(consumerID: UUID, demand: SamplingDemand) async {
        guard !Task.isCancelled else { return }
        let lease = await session.acquire(consumerID: consumerID, demand: demand, renewingExisting: true)
        for await value in lease.snapshots {
            guard !Task.isCancelled else { break }
            if value.sequence >= snapshot.sequence {
                rankingCache = nil
                snapshot = value
            }
        }
        await session.release(lease.id)
    }

    /// The one-second freshness clock only formats the visible rows. It must not
    /// repeatedly sort the complete process sample while its inputs are unchanged.
    public func rankedProcesses(search: String, sort: ProcessSort) -> [ProcessSnapshot] {
        if let cache = rankingCache, cache.search == search, cache.sort == sort { return cache.rows }
        let rows = ProcessRanking.rows(snapshot.processes, search: search, sort: sort)
        rankingCache = (search, sort, rows)
        rankingComputationCount += 1
        return rows
    }

    public func open(_ route: UtilityRoute) {
        self.route = route
        navigate?(route)
    }

    public func shutdown() async {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        await session.shutdown()
    }
}
