import Foundation
import Testing
import PerformanceDomain
@testable import PerformanceUI

@Test @MainActor func settingsAreNamespacedAndPersistInTheirOwnPreferenceDomain() async throws {
    let name = "test-only.lmc.performance.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: name))
    defer { preferences.removePersistentDomain(forName: name) }
    preferences.set("sentinel", forKey: "cleaner.existing")
    let controller = PerformanceController(preferences: preferences)
    #expect(controller.menuEnabled)
    #expect(controller.intervalSeconds == 2)
    controller.menuEnabled = false
    controller.intervalSeconds = 5
    controller.intervalSeconds = -1
    #expect(controller.intervalSeconds == 5)
    await controller.shutdown()
    let restored = PerformanceController(preferences: preferences)
    #expect(!restored.menuEnabled)
    #expect(restored.intervalSeconds == 5)
    #expect(preferences.string(forKey: "cleaner.existing") == "sentinel")
    await restored.shutdown()
}

@Test func presentationDistinguishesZeroMissingStaleAndHistoricalValues() {
    let date = Date(timeIntervalSince1970: 100)
    let now = Date(timeIntervalSince1970: 107)
    let zero = Metric<Double>.measured(0, at: date, source: "fixture")
    #expect(MetricText.value(zero, now: now, threshold: 6) { String($0) } == "0.0 · 已过期")
    let missing = Metric<Double>.unavailable(.unknown, source: "fixture", reason: "unknown")
    #expect(MetricText.value(missing, now: now, threshold: 6) { String($0) } == "未取得")
    let failed = Metric<Double>.unavailable(.failed, source: "fixture", reason: "failure").preservingLastMeasurement(from: zero)
    #expect(MetricText.value(failed, now: now, threshold: 6) { String($0) } == "0.0 · 上次测量，已过期")
    #expect(failed.quality == .failed)
    #expect(failed.lastKnownAt == date)
}

@Test @MainActor func freshnessRepaintsReuseRankingButChangedInputsRecompute() async throws {
    let name = "test-only.ranking." + UUID().uuidString
    let preferences = try #require(UserDefaults(suiteName: name))
    defer { preferences.removePersistentDomain(forName: name) }
    let controller = PerformanceController(preferences: preferences)
    for _ in 0..<60 { _ = controller.rankedProcesses(search: "", sort: .cpu) }
    #expect(controller.rankingComputationCount == 1)
    _ = controller.rankedProcesses(search: "worker", sort: .cpu)
    #expect(controller.rankingComputationCount == 2)
    _ = controller.rankedProcesses(search: "worker", sort: .footprint)
    #expect(controller.rankingComputationCount == 3)
    await controller.shutdown()
}

@Test func freshnessUpdatesScheduleExpirationWithoutPeriodicPolling() {
    let sampled = Date(timeIntervalSince1970: 100)
    let now = Date(timeIntervalSince1970: 102)
    let metric = Metric<Double>.measured(1, at: sampled, source: "fixture")
    let dates = FreshnessUpdates.dates(metric, now: now, threshold: 6)
    #expect(dates == [Date(timeIntervalSince1970: 106.001)])
    #expect(FreshnessUpdates.dates(metric, now: Date(timeIntervalSince1970: 107), threshold: 6).isEmpty)
    let failed = Metric<Double>.unavailable(.failed, source: "fixture", reason: "failure").preservingLastMeasurement(from: metric)
    #expect(FreshnessUpdates.dates(failed, now: now, threshold: 6) == dates)
    let future = Metric<Double>.measured(1, at: Date(timeIntervalSince1970: 110), source: "fixture")
    #expect(FreshnessUpdates.dates(future, now: now, threshold: 6).count == 2)
    #expect(FreshnessUpdates.dates(Metric<Double>.unavailable(.unknown, source: "fixture", reason: "missing"), now: now, threshold: 6).isEmpty)
}
