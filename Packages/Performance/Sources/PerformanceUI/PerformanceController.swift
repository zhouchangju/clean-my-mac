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
        didSet { preferences.set(intervalSeconds, forKey: "performance.refreshInterval") }
    }
    public var navigate: (@MainActor (UtilityRoute) -> Void)?
    private let preferences: UserDefaults
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
        let lease = await session.acquire(consumerID: consumerID, demand: demand)
        for await value in lease.snapshots {
            guard !Task.isCancelled else { break }
            if value.sequence >= snapshot.sequence { snapshot = value }
        }
        await session.release(lease.id)
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
