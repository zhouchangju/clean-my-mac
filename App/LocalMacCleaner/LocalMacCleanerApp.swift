import SwiftUI
import AppKit
import Darwin
import SQLite3
import CleanerDomain
import CleanerCore
import CleanerMacPlatform
import CleanerExecution

@main
struct LocalMacCleanerApp: App {
    private var uiTestColorScheme: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-lmcUITest") else { return nil }
        if args.contains("-lmcDark") { return .dark }
        if args.contains("-lmcLight") { return .light }
        return nil
    }
    @NSApplicationDelegateAdaptor(UtilityAppDelegate.self) var utilityDelegate
    var body: some Scene { launchScene() }
    private func launchScene() -> some Scene {
        // SceneBuilder has no buildEither; erase the availability-dependent scene
        // through its public limited-availability builder entry points.
        let scene: any Scene & _LimitedAvailabilitySceneMarker
        if #available(macOS 15, *) {
            scene = SceneBuilder.buildLimitedAvailability(mainWindow.defaultLaunchBehavior(.presented))
        } else {
            scene = SceneBuilder.buildLimitedAvailability(mainWindow)
        }
        return SceneBuilder.buildOptional(scene)
    }
    private var mainWindow: some Scene {
        Window("Local Mac Cleaner", id: "lmc-main") {
            UtilityRootView()
                .frame(minWidth: 1000, minHeight: 680)
                .preferredColorScheme(uiTestColorScheme)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("-lmcUITest") {
                        let small = ProcessInfo.processInfo.arguments.contains("-lmcSmallWindow")
                        NSApp.windows.first?.setContentSize(NSSize(width: small ? 1000 : 1180, height: small ? 680 : 780))
                    }
                }
        }
        .defaultSize(width: 1180, height: 780)
    }
}

enum CleanerPage: String, CaseIterable, Identifiable {
    case dashboard = "存储看板", map = "空间地图", browse = "文件浏览", candidates = "整理建议", large = "大文件", duplicates = "重复文件", history = "操作历史", aiCheckup = "AI 体检中心", settings = "设置"
    var id: String { rawValue }
    var icon: String {
        switch self { case .dashboard: "chart.pie"; case .map: "square.grid.2x2"; case .browse: "folder"; case .candidates: "lightbulb"; case .large: "doc"; case .duplicates: "doc.on.doc"; case .history: "clock"; case .aiCheckup: "sparkles"; case .settings: "gearshape" }
    }
}

@MainActor
@Observable
final class CleanerModel {
    var page: CleanerPage = .dashboard
    var scope: ScanScope?
    var run: ScanRun?
    var rows: [Entry] = []
    var mapWeights: [UUID: UInt64] = [:]
    var summary: ScanSummary?
    var dashboard: StorageDashboard?
    var volume: VolumeSnapshot?
    var preset: StorageScanPreset = .internalDisk
    var sort: StorageSort = .allocated
    var category: StorageCategory?
    var issuesOnly = false
    var scopeNotice: String?
    var maintenanceNotice: String?
    var preparingIndex = true
    var indexPreparationError: String?
    var migrationFixtureStatus: String?
    var restoredSnapshot = false
    private var ownStorageURL: URL?
    private var pendingIndexURL: URL?
    private var pendingIndexQuota = IndexResourcePolicy.defaultMaxBytes
    private var indexInitializationStarted = false
    var selection: Selection?
    var focusedID: UUID?
    var search = ""
    var offset = 0
    var parentID: UUID?
    var breadcrumbs: [(UUID?, String)] = [(nil, "扫描根目录")]
    var scanning = false
    var cancelling = false
    var lastScanProgressAt: ContinuousClock.Instant?
    var scanWaitThreshold: Duration {
        testRoot != nil && ProcessInfo.processInfo.arguments.contains("-lmcStalledScanFixture") ? .seconds(1) : .seconds(30)
    }
    var plan: CleanupPlan?
    var planMessage = ""
    var preflight: [PreflightResult] = []
    var action: CleanupAction = .trash
    var errorMessage: String?
    var freeBytes: Int64?
    var showPlan = false
    var ignored: [IgnoreEntry] = []
    var ignoreRevision: UInt64 = 0
    let pageSize = 100
    private var store: SQLiteScanStore?
    /// 供空间地图 v2 等子页面按需只读查询使用。
    var activeStore: SQLiteScanStore? { store }
    private var coordinator: ScanCoordinator?
    private var ignoreStore: IgnoreStore?
    private var scanGeneration = UUID()
    private var refreshTask: Task<Void, Never>?
    private var refreshRequested = false
    private var refreshUrgent = false
    private var lastRefreshAt: ContinuousClock.Instant?
    var refreshing = false
    var refreshActiveCount = 0
    var maxRefreshActiveCount = 0
    var discardedRefreshCount = 0
    private var planGeneration = UUID()
    var incompleteCoverage: Bool { run.map { $0.state != .completed } ?? false }
    var noSuccessfulMeasurement: Bool { !scanning && incompleteCoverage && ((summary?.entryCount ?? 0) == 0 || (run?.stopReason != nil && (summary?.knownAllocatedBytes ?? 0) == 0 && (summary?.knownLogicalBytes ?? 0) == 0)) }
    private var testRoot: URL?
    var focused: Entry? { rows.first { $0.id == focusedID } }
    var selectedCount: Int { selection?.ids.count ?? 0 }
    var hiddenSelectedCount: Int { selection?.ids.subtracting(Set(rows.map(\.id))).count ?? 0 }
    var storagePath: String = ""

    init() {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LocalMacCleaner", isDirectory: true)
            let directory: URL
            if ProcessInfo.processInfo.arguments.contains("-lmcUITest") {
                guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw CleanerError(.invalidInput, "测试临时根无法规范定位") }
                let temporaryRoot = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
                free(resolved)
                directory = temporaryRoot.appendingPathComponent("LMC-UI-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let fixture = directory.appendingPathComponent("fixture", isDirectory: true)
                try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                if !ProcessInfo.processInfo.arguments.contains("-lmcEmptyFixture") {
                    let files: [(String, Int)] = [
                        ("Downloads/保留的安装包.dmg", 2 * 1024 * 1024),
                        ("Documents/项目资料/很长的中文文件名_请先审阅再决定_重要资料.txt", 64 * 1024),
                        ("Pictures/旅行照片.heic", 512 * 1024),
                        ("Movies/家庭影像.mp4", 1024 * 1024),
                        ("Applications/Example.app/Contents/Resources/resource.dat", 1024 * 1024),
                        ("Developer/Project/.git/config", 64),
                        ("Developer/Project/源码.swift", 64 * 1024),
                        ("Library/Developer/Xcode/DerivedData/Fixture-ABC/Build/Intermediates.noindex/temp.o", 1024 * 1024),
                        (".npm/_cacache/tmp/过期缓存", 512 * 1024)
                    ]
                    for (path, size) in files {
                        let target = fixture.appendingPathComponent(path)
                        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        try Data(repeating: 0x41, count: size).write(to: target)
                        if path.hasPrefix(".npm") { try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-9 * 86400)], ofItemAtPath: target.path) }
                    }
                    let file = fixture.appendingPathComponent("Downloads/可审阅大文件_很长中文名称_保留原始资料.dat")
                    guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CleanerError(.invalidInput, "无法创建测试文件") }
                    let handle = try FileHandle(forWritingTo: file)
                    try handle.truncate(atOffset: 600 * 1024 * 1024)
                    try handle.close()
                }
                if ProcessInfo.processInfo.arguments.contains("-lmcDeniedFixture") {
                    let denied = fixture.appendingPathComponent("无法读取的目录", isDirectory: true)
                    try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    try Data("测试目录中的未知内容".utf8).write(to: denied.appendingPathComponent("隐藏资料.txt"))
                    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
                }
                testRoot = fixture
            } else { directory = base }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if ProcessInfo.processInfo.arguments.contains("-lmcUITest") && ProcessInfo.processInfo.arguments.contains("-lmcPendingFixture") {
                let pending = directory.appendingPathComponent("staging", isDirectory: true)
                try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try Data("待恢复测试记录，必须保留".utf8).write(to: pending.appendingPathComponent("pending-state"))
            }
            storagePath = directory.path; ownStorageURL = directory
            let quota: UInt64 = ProcessInfo.processInfo.arguments.contains("-lmcUITest") && ProcessInfo.processInfo.arguments.contains("-lmcQuotaFixture") ? 40 * 1024 : IndexResourcePolicy.defaultMaxBytes
            pendingIndexURL = directory.appendingPathComponent("index.sqlite")
            pendingIndexQuota = quota
            ignoreStore = try IgnoreStore(url: directory.appendingPathComponent("ignores.json"))
            ignored = ignoreStore?.entries ?? []
            ignoreRevision = ignoreStore?.revision ?? 0
            do { try setPreset(.internalDisk) }
            catch {
                scopeNotice = "内置存储无法预选：\(error)。已尝试我的文件，可自选可读目录。"
                do { try setPreset(.home) } catch { scopeNotice = "扫描范围不可用：\(error)" }
            }
        } catch {
            indexPreparationError = "本地索引准备失败：\(error)"
            errorMessage = indexPreparationError; preparingIndex = false
        }
    }

    func prepareIndex() {
        guard !indexInitializationStarted, let indexURL = pendingIndexURL, indexPreparationError == nil else { return }
        indexInitializationStarted = true
        let quota = pendingIndexQuota
        let legacyFixture = ProcessInfo.processInfo.arguments.contains("-lmcUITest") && ProcessInfo.processInfo.arguments.contains("-lmcMigrationFixture")
        let fixtureURL = testRoot
        Task {
            do {
                let prepared = try await Task.detached(priority: .utility) {
                    var oldRunID: UUID?
                    if legacyFixture, let fixtureURL {
                        oldRunID = try LegacyIndexFixture.write(indexURL, fixture: fixtureURL)
                        if ProcessInfo.processInfo.arguments.contains("-lmcReplacedScopeFixture") {
                            let previous = fixtureURL.deletingLastPathComponent().appendingPathComponent("previous-fixture", isDirectory: true)
                            try FileManager.default.moveItem(at: fixtureURL, to: previous)
                            try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                        }
                        try await Task.sleep(for: .seconds(8))
                    }
                    let actualStore = try SQLiteScanStore(url: indexURL, quotaBytes: quota)
                    var status: String?
                    if let oldRunID {
                        let summary = try await actualStore.summary(scanID: oldRunID)
                        status = "旧记录迁移完成：\(summary.entryCount) 项，已知分配 \(summary.knownAllocatedBytes) 字节"
                    }
                    return (actualStore, status)
                }.value
                store = prepared.0; migrationFixtureStatus = prepared.1
                try await restoreLastFinishedResults(using: prepared.0)
                preparingIndex = false
            } catch {
                let explanation = "本地索引准备失败，未开始扫描：\(error)"
                indexPreparationError = explanation; errorMessage = explanation; preparingIndex = false
            }
        }
    }

    private func restoreLastFinishedResults(using index: SQLiteScanStore) async throws {
        guard let saved = try await index.latestRetainedTerminalRun() else { return }
        let savedScope = saved.scope
        let matches: Bool
        do {
            matches = try await Task.detached(priority: .utility) {
                let current = try MacFileReader().scope(path: savedScope.rootPath)
                return current.rootIdentity.sameObject(as: savedScope.rootIdentity)
                    && current.rootIdentity.volumeID == savedScope.rootIdentity.volumeID
                    && current.rootIdentity.ownerUID == savedScope.rootIdentity.ownerUID
            }.value
        } catch {
            scopeNotice = "上次结果所属目录或卷暂时不可读取，未恢复；请重新选择可读范围。"
            return
        }
        guard matches else {
            scopeNotice = "上次结果所属目录或卷的身份已变化，未恢复；请重新扫描。"
            return
        }
        resetResults()
        scope = savedScope; run = saved; restoredSnapshot = true
        selection = Selection(scanID: saved.id)
        if savedScope.rootPath == "/System/Volumes/Data" { preset = .internalDisk }
        else if savedScope.rootPath == FileManager.default.homeDirectoryForCurrentUser.path { preset = .home }
        else if savedScope.rootPath == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path { preset = .downloads }
        else { preset = .custom }
        sampleSpace()
        requestRefresh(force: true)
    }

    func setPreset(_ value: StorageScanPreset) throws {
        guard !scanning else { return }
        let selected = if let testRoot { try MacFileReader().scope(path: testRoot.path) }
                       else { try StorageScopeProvider().scope(for: value) }
        scope = selected; preset = value
        resetResults()
        sampleSpace()
    }
    func quickScan(_ value: StorageScanPreset) {
        guard !preparingIndex, indexPreparationError == nil else { return }
        do { scopeNotice = nil; try setPreset(value); startScan() }
        catch { errorMessage = String(describing: error) }
    }
    private func resetResults() {
        invalidateRefresh()
        restoredSnapshot = false
        run = nil; rows = []; summary = nil; dashboard = nil; selection = nil; focusedID = nil
        parentID = nil; breadcrumbs = [(nil, "扫描根目录")]; offset = 0; search = ""; category = nil; issuesOnly = false
        invalidatePlan("扫描范围已改变，旧计划已失效")
    }
    func chooseScope() {
        guard !scanning else { return }
        if testRoot != nil { do { try setPreset(.custom) } catch { errorMessage = String(describing: error) }; return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "选择扫描目录。扫描和计划不会修改其中的文件。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            scope = try MacFileReader().scope(path: url.path); preset = .custom; scopeNotice = nil
            resetResults(); sampleSpace()
        } catch { errorMessage = String(describing: error) }
    }

    func startScan() {
        guard let scope, let store, !scanning, !preparingIndex, indexPreparationError == nil else { return }
        restoredSnapshot = false
        let generation = UUID(); scanGeneration = generation
        invalidateRefresh()
        scanning = true; cancelling = false; run = nil; rows = []; mapWeights = [:]; summary = nil; dashboard = nil; selection = nil; focusedID = nil; offset = 0
        lastScanProgressAt = .now
        parentID = nil; breadcrumbs = [(nil, "扫描根目录")]
        invalidatePlan("重新扫描后须重新选择和预览")
        let storageURL = ownStorageURL
        Task {
            do {
                let maintenanceSafety = await Task.detached { Self.maintenanceMayRun(at: storageURL) }.value
                if maintenanceSafety.allowed {
                    let retired = try await store.retireTerminalScans(protectedScanIDs: [])
                    maintenanceNotice = retired > 0 ? "已整理旧扫描索引；操作收据与待恢复数据不受此维护处理。" : nil
                } else { maintenanceNotice = maintenanceSafety.reason }
                if testRoot != nil && ProcessInfo.processInfo.arguments.contains("-lmcStalledScanFixture") {
                    try await Task.sleep(for: .seconds(30))
                }
                guard !cancelling, generation == scanGeneration else { scanning = false; cancelling = false; return }
                let coordinator = ScanCoordinator(store: store, rules: RuleEngine(ignores: ignored, homePath: testRoot?.path ?? FileManager.default.homeDirectoryForCurrentUser.path), reader: MacFileReader(), analysisMode: true)
                self.coordinator = coordinator
                let finished = try await coordinator.scan(scope: scope) { [weak self] progress in
                    await self?.receive(progress, generation: generation)
                }
                guard scanGeneration == generation else { return }
                run = finished; selection = Selection(scanID: finished.id)
                await refreshFinal()
                guard scanGeneration == generation else { return }
                scanning = false; cancelling = false
                sampleSpace()
            } catch {
                guard scanGeneration == generation else { return }
                scanning = false; cancelling = false; errorMessage = String(describing: error)
            }
        }
    }
    nonisolated private static func maintenanceMayRun(at url: URL?) -> (allowed: Bool, reason: String?) {
        guard let url else { return (false, "未能定位应用自身状态，保守保留旧索引。") }
        do {
            let reader = MacFileReader()
            let stateScope = try reader.scope(path: url.path)
            let cursor = try reader.directory(scope: stateScope, relativePath: "")
            var existing: Set<String> = []
            while let name = try cursor.next() { existing.insert(name) }
            for name in ["transactions", "receipts", "plans", "staging"] where existing.contains(name) {
                let identity = try reader.identity(scope: stateScope, relativePath: name)
                guard identity.kind == .directory else { return (false, "\(name) 状态路径不是可核实的目录，已保留全部旧索引。") }
                let child = try reader.directory(scope: stateScope, relativePath: name)
                guard try child.next() == nil else { return (false, "存在操作或恢复状态（\(name)），已保守保留全部旧索引。") }
            }
            return (true, nil)
        } catch { return (false, "状态目录不可安全核实，已保留旧索引：\(error)") }
    }

    private func receive(_ progress: ScanRun, generation: UUID) {
        guard scanGeneration == generation else { return }
        lastScanProgressAt = .now
        run = progress
        // Never await a store query on the scanner's progress callback.
        requestRefresh(immediate: progress.finishedAt != nil)
    }
    func cancel() {
        cancelling = true
        Task { await coordinator?.cancel() }
    }
    func requestRefresh(immediate: Bool = false, force: Bool = false) {
        guard run != nil else { return }
        if !force && (page == .settings || page == .history) { refreshRequested = false; return }
        refreshRequested = true
        refreshUrgent = refreshUrgent || immediate
        guard refreshTask == nil else { return }
        let generation = scanGeneration
        refreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.drainRefreshes(generation: generation)
        }
    }
    private func drainRefreshes(generation: UUID) async {
        while refreshRequested && !Task.isCancelled && scanGeneration == generation {
            if !refreshUrgent {
                let elapsed = lastRefreshAt.map { $0.duration(to: .now) } ?? .zero
                if elapsed < .seconds(1) {
                    do { try await Task.sleep(for: .seconds(1) - elapsed) }
                    catch { break }
                }
            }
            guard !Task.isCancelled, scanGeneration == generation else { break }
            refreshRequested = false; refreshUrgent = false
            await performRefresh(generation: generation)
            lastRefreshAt = .now
        }
        refreshTask = nil; refreshing = false
        if refreshRequested, run != nil { requestRefresh(immediate: refreshUrgent) }
    }
    private func refreshFinal() async {
        requestRefresh(immediate: true, force: true)
        while let task = refreshTask { await task.value }
    }
    private func performRefresh(generation: UUID) async {
        guard let store, let run else { return }
        let visiblePage = page, queryOffset = offset, queryParent = parentID, querySearch = search
        let querySort = sort, queryCategory = category, queryIssues = issuesOnly
        refreshActiveCount += 1; maxRefreshActiveCount = max(maxRefreshActiveCount, refreshActiveCount)
        defer { refreshActiveCount -= 1 }
        do {
            if ProcessInfo.processInfo.arguments.contains("-lmcUITest") && ProcessInfo.processInfo.arguments.contains("-lmcRefreshDelayFixture") {
                try await Task.sleep(for: .seconds(4))
            }
            let newRows: [Entry]
            if visiblePage == .browse {
                newRows = try await store.children(scanID: run.id, parentID: queryParent, offset: queryOffset, limit: pageSize, search: querySearch, sort: querySort, category: queryCategory)
            } else if visiblePage == .large || visiblePage == .candidates {
                newRows = try await store.catalog(scanID: run.id, offset: queryOffset, limit: pageSize, search: querySearch, sort: querySort, category: queryCategory, largeOnly: visiblePage == .large, candidatesOnly: visiblePage == .candidates && queryCategory == nil && !queryIssues, issuesOnly: queryIssues)
            } else { newRows = [] }
            let newWeights = visiblePage == .browse ? try await store.mapWeights(scanID: run.id, parentID: queryParent, ids: Set(newRows.map(\.id))) : [:]
            let newDashboard = try await store.dashboard(scanID: run.id)
            guard !Task.isCancelled, generation == scanGeneration, self.run?.id == run.id,
                  page == visiblePage, offset == queryOffset, parentID == queryParent, search == querySearch,
                  sort == querySort, category == queryCategory, issuesOnly == queryIssues else {
                discardedRefreshCount += 1
                return
            }
            rows = newRows; mapWeights = newWeights; dashboard = newDashboard; summary = newDashboard.summary
        } catch {
            if !Task.isCancelled, generation == scanGeneration, self.run?.id == run.id { errorMessage = String(describing: error) }
        }
    }
    private func invalidateRefresh() {
        refreshRequested = false; refreshUrgent = false
        refreshTask?.cancel()
        rows = []; mapWeights = [:]
    }
    func changePage() { rows = []; mapWeights = [:]; offset = 0; parentID = nil; breadcrumbs = [(nil, "扫描根目录")]; focusedID = nil; category = nil; issuesOnly = false; search = ""; requestRefresh() }
    func review(category: StorageCategory? = nil, large: Bool = false, issues: Bool = false) {
        page = large ? .large : .candidates
        rows = []; mapWeights = [:]
        self.category = category; issuesOnly = issues; offset = 0; parentID = nil; search = ""
        requestRefresh()
    }
    func jump(_ index: Int) {
        guard breadcrumbs.indices.contains(index) else { return }
        rows = []; mapWeights = [:]
        breadcrumbs = Array(breadcrumbs.prefix(index + 1)); parentID = breadcrumbs.last?.0; offset = 0; focusedID = nil
        requestRefresh()
    }
    func select(_ entry: Entry, _ selected: Bool) {
        guard !restoredSnapshot else { return }
        do { try selection?.set(entry, selected: selected); invalidatePlan("选择已改变，需重新预览") }
        catch { errorMessage = String(describing: error) }
    }
    func selectDisplayed() { for entry in rows where entry.selectable { select(entry, true) } }
    func clearSelection() { selection?.clear(); invalidatePlan("选择已清空") }
    func enter(_ entry: Entry) {
        guard entry.identity?.kind == .directory else { return }
        rows = []; mapWeights = [:]
        parentID = entry.id; breadcrumbs.append((entry.id, entry.relativePath)); offset = 0
        requestRefresh()
    }
    func up() {
        guard breadcrumbs.count > 1 else { return }
        rows = []; mapWeights = [:]
        breadcrumbs.removeLast(); parentID = breadcrumbs.last?.0; offset = 0
        requestRefresh()
    }
    func ignoreFocused() {
        guard let entry = focused, let scope, let ignoreStore else { return }
        do {
            let path = URL(fileURLWithPath: scope.rootPath).appendingPathComponent(entry.relativePath).path
            try ignoreStore.add(IgnoreEntry(scopeKind: entry.identity?.kind == .directory ? .subtree : .exactPath, matchValue: path))
            ignored = ignoreStore.entries; ignoreRevision = ignoreStore.revision
            selection?.clear(); invalidatePlan("忽略已改变，须重新扫描")
            run = nil; rows = []; summary = nil; dashboard = nil
        } catch { errorMessage = String(describing: error) }
    }
    func removeIgnore(_ id: UUID) {
        do {
            try ignoreStore?.remove(id)
            ignored = ignoreStore?.entries ?? []; ignoreRevision = ignoreStore?.revision ?? 0
            selection?.clear(); invalidatePlan("忽略已改变，须重新扫描"); run = nil; rows = []; summary = nil; dashboard = nil
        } catch { errorMessage = String(describing: error) }
    }
    func preview() {
        guard !restoredSnapshot else { planMessage = "上次结果仅供浏览，请重新扫描后选择文件。"; return }
        let generation = UUID(); planGeneration = generation
        showPlan = true; plan = nil; preflight = []
        guard let run, let selection, let store else { planMessage = "请完成扫描并明确选择文件"; return }
        let currentIgnoreRevision = ignoreRevision
        let currentAction = action
        Task {
            do {
                let entries = try await store.entries(scanID: run.id, ids: selection.ids)
                let (generated, results) = try await Task.detached {
                    let generated = try Planner.make(run: run, entries: entries, selection: selection, action: currentAction, ignoreRevision: currentIgnoreRevision)
                    let results = try MacPreflight().validate(plan: generated, run: run, selectionRevision: selection.revision, ignoreRevision: currentIgnoreRevision)
                    return (generated, results)
                }.value
                guard generation == planGeneration else { return }
                guard self.run?.id == run.id, self.selection?.revision == selection.revision,
                      ignoreRevision == currentIgnoreRevision, action == currentAction else { throw CleanerError(.planExpired, "选择、动作或扫描已改变") }
                preflight = results
                plan = generated; planMessage = "仅预览。M2 安全验收未满足，执行已禁用。"
            } catch { if generation == planGeneration { planMessage = String(describing: error) } }
        }
    }
    func invalidatePlan(_ message: String) { planGeneration = UUID(); plan = nil; preflight = []; planMessage = message }
    func reveal(_ entry: Entry) {
        guard let scope else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: scope.rootPath).appendingPathComponent(entry.relativePath)])
    }
    func exportPage() {
        guard let scope, !rows.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "存储分析-当前页.json"
        panel.message = "仅导出当前筛选这一页的 \(rows.count) 项；使用相对扫描根路径；文件名仍可能包含隐私，请本地保管。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Export.report(entries: rows, scope: scope).write(to: url, options: .atomic) }
        catch { errorMessage = String(describing: error) }
    }
    private func sampleSpace() {
        guard let scope else { return }
        do { volume = try StorageScopeProvider().volume(at: scope.rootPath) }
        catch { volume = nil; scopeNotice = "卷容量未能读取：\(error)" }
    }

}

struct CleanerView: View {
    @Bindable var model: CleanerModel
    @FocusState private var searchFocused: Bool
    private let accent = Color.teal
    var body: some View {
        @Bindable var model = model
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Local Mac Cleaner", systemImage: "internaldrive.fill")
                    .font(.headline).padding(.horizontal, 16).padding(.top, 18)
                List(CleanerPage.allCases, selection: Binding(get: { model.page }, set: { model.page = $0; model.changePage() })) { page in
                    Label(page.rawValue, systemImage: page.icon).tag(page).accessibilityIdentifier("navigation.\(page.id)")
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label("完全本地处理", systemImage: "lock.shield")
                    Text("先分析，再审阅。\n扫描不修改你的文件。").font(.caption).foregroundStyle(.secondary)
                }.font(.caption).padding(16)
            }.frame(minWidth: 180, idealWidth: 195, maxWidth: 220, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
                Divider()
                Group {
                    switch model.page {
                    case .dashboard: dashboard
                    case .map: SpaceMapPage(model: model)
                    case .browse: browser
                    case .candidates: recommendations
                    case .large: browser
                    case .duplicates: DuplicatesPage(model: model)
                    case .settings: settings
                    case .history: history
                    case .aiCheckup: AICenterPage(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer.padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.background)
            }
        }
        .tint(accent)
        .task { model.prepareIndex() }
        .onChange(of: model.search) { model.offset = 0; model.requestRefresh() }
        .onChange(of: model.sort) { model.offset = 0; model.requestRefresh() }
        .onChange(of: model.category) { model.offset = 0; model.requestRefresh() }
        .sheet(isPresented: $model.showPlan) { planView }
        .alert("操作提示", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.page.rawValue).font(.title2.bold()).accessibilityIdentifier("storage.pageTitle")
                    Text(model.preset.title + " · 只读分析").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("自选目录", action: model.chooseScope).accessibilityIdentifier("scope.choose").disabled(model.scanning || model.preparingIndex)
                if model.scanning {
                    Button(model.cancelling ? "正在停止…" : "停止扫描", action: model.cancel).disabled(model.cancelling).accessibilityIdentifier("scan.cancel")
                } else {
                    Button(model.run == nil ? "开始扫描" : "重新扫描", action: model.startScan)
                        .buttonStyle(.borderedProminent).disabled(model.scope == nil || model.preparingIndex || model.indexPreparationError != nil).accessibilityIdentifier("scan.start")
                }
            }
            if model.preparingIndex {
                HStack { ProgressView().controlSize(.small); Text("正在准备本地索引，请稍候…").accessibilityIdentifier("index.preparing") }.font(.caption)
            }
            if let failure = model.indexPreparationError { Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).accessibilityIdentifier("index.failed") }
            if let status = model.migrationFixtureStatus { Text(status).font(.caption2).accessibilityIdentifier("test.indexMigrationStatus") }
            if model.restoredSnapshot, let saved = model.run {
                Text("上次扫描：" + (saved.finishedAt ?? saved.startedAt).formatted(date: .abbreviated, time: .shortened) + " · 仅供浏览，文件可能已变化；重新扫描后才能选择。")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("scan.restoredSnapshot")
            }
            Text(model.scope?.rootPath ?? "请选择可读范围")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(model.scope?.rootPath ?? "")
            if let notice = model.scopeNotice { Label(notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if let reason = model.run?.stopReason { Label("扫描提前停止：" + reason, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).accessibilityIdentifier("scan.stopReason") }
            if let notice = model.maintenanceNotice { Text(notice).font(.caption2).foregroundStyle(.secondary).lineLimit(2).accessibilityIdentifier("scan.maintenanceNotice") }
            if ProcessInfo.processInfo.arguments.contains("-lmcUITest") && ProcessInfo.processInfo.arguments.contains("-lmcRefreshDelayFixture") {
                Text("当前刷新 \(model.refreshActiveCount) · 并行刷新峰值 \(model.maxRefreshActiveCount) · 丢弃旧视图 \(model.discardedRefreshCount)")
                    .font(.caption2).accessibilityIdentifier("test.refreshObserver")
            }
            if model.scanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.cancelling ? "已请求停止；系统目录调用返回后结束，保留已扫描结果" : "已处理 \(model.run?.processedCount ?? 0) 项 · 总量未知")
                }.font(.caption)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let last = model.lastScanProgressAt, last.duration(to: .now) >= model.scanWaitThreshold {
                        Label(model.cancelling
                              ? "停止请求仍在等待文件系统响应。若系统显示权限提示，请自行处理；应用不会自动授权。"
                              : "较长时间未收到扫描进度，可能正在等待文件系统或系统权限响应。若系统显示权限提示，请自行处理；应用不会自动授权。",
                              systemImage: "clock.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.orange).accessibilityIdentifier("scan.waitingForSystem")
                    }
                }
            } else if let run = model.run {
                Text("\(scanLabel(run.state)) · \(run.processedCount) 项 · \(run.issueCount) 处未深入或读取缺口")
                    .font(.caption).foregroundStyle(run.state == .completed ? Color.secondary : Color.orange)
                    .accessibilityIdentifier("scan.status")
            }
        }
    }
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                volumeCard
                if model.run == nil && !model.scanning {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("从哪里开始？").font(.headline)
                        Text("内置存储已预选，一次点击即可了解主要占用。应用与代码仓库只计量；凭据、会话、云同步及权限受限位置不深入。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            quickButton(.internalDisk, icon: "internaldrive", identifier: "scope.internalDisk")
                            quickButton(.home, icon: "house", identifier: "scope.home")
                            quickButton(.downloads, icon: "arrow.down.circle", identifier: "scope.downloads")
                        }
                    }.cardStyle()
                } else {
                    HStack(spacing: 10) {
                        quickButton(.internalDisk, icon: "internaldrive", identifier: "scope.internalDisk")
                        quickButton(.home, icon: "house", identifier: "scope.home")
                        quickButton(.downloads, icon: "arrow.down.circle", identifier: "scope.downloads")
                    }
                    if let dashboard = model.dashboard {
                        HStack(alignment: .top, spacing: 14) {
                            categoryCard(dashboard)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("值得审阅").font(.headline)
                                ForEach(StorageInsights.make(dashboard: dashboard)) { insight in
                                    insightButton(title: insight.title, value: insight.actionTitle, description: insight.summary, icon: insight.kind == .coverage ? "exclamationmark.triangle" : "arrow.right.circle", id: "insight.\(insight.kind.rawValue)") {
                                        model.review(category: insight.category, large: insight.largeOnly, issues: insight.issuesOnly)
                                    }
                                }
                                if model.incompleteCoverage && !StorageInsights.make(dashboard: dashboard).contains(where: { $0.kind == .coverage }) {
                                    insightButton(title: "扫描覆盖不完整", value: "查看原因", description: model.run?.stopReason ?? "扫描已停止或取消，未读取范围仍然未知。", icon: "exclamationmark.triangle", id: "insight.coverage") { model.review(issues: true) }
                                }
                                if StorageInsights.make(dashboard: dashboard).isEmpty {
                                    Text(model.incompleteCoverage ? "已扫描部分尚未发现匹配项；继续查看已知占用，未覆盖范围仍未知。" : "此范围暂无规则匹配候选或大文件。可在空间地图审阅实际占用。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.cardStyle().frame(maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("扫描根目录 · 主要占用").font(.headline); Spacer(); Button("打开空间地图") { model.page = .map; model.changePage() }.accessibilityIdentifier("dashboard.openMap") }
                            ForEach(dashboard.topFolders.prefix(6)) { entry in
                                Button {
                                    model.page = .map; model.changePage(); model.enter(entry)
                                } label: {
                                    HStack { Image(systemName: "folder.fill").foregroundStyle(accent); Text(entry.relativePath.isEmpty ? "扫描根目录" : entry.relativePath).lineLimit(1); Spacer(); Text(measuredBytes(entry)).monospacedDigit(); Image(systemName: "chevron.right").font(.caption) }
                                }.buttonStyle(.plain).accessibilityIdentifier("dashboard.folder.\(entry.id)")
                                Divider()
                            }
                            if dashboard.topFolders.isEmpty { Text("已提交索引中尚无可展示目录；未读取范围仍未知，可在空间地图查看已知项目。").font(.caption).foregroundStyle(.secondary) }
                        }.cardStyle()
                    }
                }
            }.padding(20)
        }
    }
    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "internaldrive.fill").font(.system(size: 38)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.volume?.name ?? "内置存储").font(.headline)
                    Text("卷容量与可用空间 · 扫描只统计可读取范围").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.volume?.availableBytes.map(bytes) ?? "未知").font(.title2.bold()).monospacedDigit().accessibilityIdentifier("dashboard.freeBytes")
                    Text("卷可用空间").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let capacity = model.volume?.capacityBytes, let free = model.volume?.availableBytes, capacity > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(accent.opacity(0.16))
                        Capsule().fill(accent).frame(width: geometry.size.width * min(1, Double(capacity > free ? capacity - free : 0) / Double(capacity)))
                    }
                }.frame(height: 10)
                HStack { Text("卷已用 \(bytes(capacity > free ? capacity - free : 0))"); Spacer(); Text("总容量 \(bytes(capacity))") }.font(.caption).foregroundStyle(.secondary)
            } else { Text("卷空间样本未能获取，继续分析可读范围。").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.scanning && (model.summary?.entryCount ?? 0) == 0 ? "正在计量" : model.noSuccessfulMeasurement ? "未成功计量" : model.summary.map { bytes($0.knownAllocatedBytes) } ?? "尚未扫描").font(.title.bold()).monospacedDigit().accessibilityIdentifier("dashboard.knownBytes")
                    Text(model.noSuccessfulMeasurement ? "扫描提前停止，不能把未读取范围当成空目录" : "扫描已知分配大小 · 不是可释放量").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("dashboard.measureState")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(model.summary.map { "\($0.entryCount) 项" } ?? "点击下方快捷入口")
                    Text(model.summary.map { "\($0.unknownCount) 项计量未知" } ?? "首次启动不会自动扫描").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.cardStyle()
    }
    private func quickButton(_ preset: StorageScanPreset, icon: String, identifier: String) -> some View {
        Button { model.quickScan(preset) } label: {
            HStack { Image(systemName: icon); Text(preset == .internalDisk ? "扫描内置存储" : "扫描" + preset.title) }
                .frame(maxWidth: .infinity).padding(.vertical, 5)
        }.buttonStyle(.bordered).disabled(model.scanning || model.preparingIndex || model.indexPreparationError != nil).accessibilityIdentifier(identifier).help(preset.explanation)
    }
    private func categoryCard(_ dashboard: StorageDashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("空间分布").font(.headline)
            if model.noSuccessfulMeasurement {
                Label("分类尚未成功计量，不能据此判断整个范围为空。", systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("dashboard.categoriesUnknown")
            } else {
            Text("按普通叶子计量，目录不重复累加").font(.caption).foregroundStyle(.secondary)
            let maximum = dashboard.categories.map(\.allocatedBytes).max() ?? 0
            ForEach(dashboard.categories) { summary in
                Button { model.review(category: summary.category) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Label(summary.category.title, systemImage: summary.category.symbol); Spacer(); Text(bytes(summary.allocatedBytes)).monospacedDigit() }.font(.caption)
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 3).fill(categoryColor(summary.category).opacity(0.15))
                                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(categoryColor(summary.category)).frame(width: maximum > 0 ? geometry.size.width * Double(summary.allocatedBytes) / Double(maximum) : 0) }
                        }.frame(height: 7)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("dashboard.category.\(summary.category.rawValue)")
            }
            if dashboard.categories.isEmpty { Text("暂无已知分类占用").font(.caption).foregroundStyle(.secondary) }
            }
        }.cardStyle().frame(maxWidth: .infinity)
    }
    private func insightButton(title: String, value: String, description: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(title).font(.subheadline.bold()); Spacer(); Text(value).font(.subheadline.bold()) }
                    Text(description).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 7)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let dashboard = model.dashboard {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(StorageInsights.make(dashboard: dashboard)) { insight in
                            Button { model.review(category: insight.category, large: insight.largeOnly, issues: insight.issuesOnly) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(insight.title).font(.subheadline.bold())
                                    Text(insight.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                    Text(insight.actionTitle).font(.caption.bold()).foregroundStyle(accent)
                                }.frame(width: 230, alignment: .leading).cardStyle()
                            }.buttonStyle(.plain).accessibilityIdentifier("recommendation.insight.\(insight.kind.rawValue)")
                        }
                    }.padding(.horizontal, 20)
                }.frame(maxHeight: 125)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    recommendationChip("缓存候选", symbol: "archivebox", selected: model.category == nil && !model.issuesOnly) { model.review() }
                    recommendationChip("下载整理", symbol: "arrow.down.circle", selected: model.category == .downloads) { model.review(category: .downloads) }
                    recommendationChip("开发文件", symbol: "hammer", selected: model.category == .developer) { model.review(category: .developer) }
                    recommendationChip("文档影音", symbol: "photo", selected: model.category == .media) { model.review(category: .media) }
                    recommendationChip("覆盖缺口", symbol: "exclamationmark.triangle", selected: model.issuesOnly) { model.review(issues: true) }
                }.padding(.horizontal, 20)
            }.padding(.top, 16)
            Text(model.issuesOnly ? "未深入位置保留明确原因；缺口不意味着零占用。" : model.category == nil ? "仅规则识别的缓存候选；显示用途、重建影响与准入能力。不会自动勾选。" : "普通文件整理建议：先审阅占用和用途，文件大或旧不代表可以删除。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
            browser
        }
    }
    private func recommendationChip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.caption.bold()).padding(.horizontal, 5).padding(.vertical, 6) }
            .buttonStyle(.bordered).tint(selected ? accent : .secondary).accessibilityIdentifier("recommendation.\(title)")
    }
    private var browser: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                browserControls
                if model.page == .browse {
                    breadcrumbBar
                }
                entryTable
                HStack {
                    Button("上一页") { model.offset = max(0, model.offset - model.pageSize); model.requestRefresh() }.disabled(model.offset == 0)
                    Text("第 \(model.offset / model.pageSize + 1) 页 · \(model.rows.count) 项").font(.caption).foregroundStyle(.secondary)
                    Button("下一页") { model.offset += model.pageSize; model.requestRefresh() }.disabled(model.rows.count < model.pageSize)
                    Spacer()
                    Button("导出本页", action: model.exportPage).disabled(model.rows.isEmpty).accessibilityIdentifier("results.export")
                }
                if model.rows.isEmpty {
                    Text(model.run == nil ? "先扫描一个范围，再查看占用和审阅建议。" : model.scanning || model.refreshing ? "正在更新已提交结果…" : model.noSuccessfulMeasurement ? "扫描提前停止，尚未成功计量；请处理原因后重扫。" : model.issuesOnly ? "当前页没有缺口明细；扫描停止或未覆盖状态请查看上方提示。" : "当前筛选没有匹配项。")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("results.empty")
                }
            }
            if let entry = model.focused { detail(entry).frame(width: 250) }
        }.padding(20)
    }
    private var browserControls: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                .keyboardShortcut("f", modifiers: .command).accessibilityIdentifier("results.focusSearch").help("搜索（⌘F）")
            TextField("搜索相对路径", text: $model.search).textFieldStyle(.roundedBorder).focused($searchFocused).accessibilityIdentifier("results.search")
            Picker("排序", selection: $model.sort) {
                Text("分配大小").tag(StorageSort.allocated)
                Text("逻辑大小").tag(StorageSort.logical)
                Text("修改时间").tag(StorageSort.modified)
            }.labelsHidden().frame(width: 110).accessibilityIdentifier("results.sort")

        }
    }
    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button { model.up() } label: { Image(systemName: "arrow.left") }.disabled(model.breadcrumbs.count < 2).accessibilityIdentifier("map.back")
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                        Button(crumb.1.isEmpty ? "扫描根目录" : URL(fileURLWithPath: crumb.1).lastPathComponent) { model.jump(index) }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(index == model.breadcrumbs.count - 1 ? .primary : .secondary)
                            .accessibilityIdentifier("map.breadcrumb.\(index)")
                    }
                }
            }
        }
    }
    private var entryTable: some View {
        Table(model.rows, selection: Binding(get: { model.focusedID }, set: { model.focusedID = $0 })) {
            TableColumn("选择") { entry in
                Toggle("选择 \(entry.relativePath)", isOn: Binding(get: { model.selection?.ids.contains(entry.id) == true }, set: { model.select(entry, $0) }))
                    .labelsHidden().disabled(!entry.selectable || model.scanning || model.restoredSnapshot).accessibilityIdentifier("entry.select.\(entry.id)")
            }.width(35)
            TableColumn("名称") { entry in
                HStack(spacing: 6) {
                    Image(systemName: entry.identity?.kind == .directory ? "folder.fill" : entry.decision.disposition == .protect ? "lock.doc" : "doc").foregroundStyle(entry.identity?.kind == .directory ? accent : .secondary)
                    Text(URL(fileURLWithPath: entry.relativePath).lastPathComponent).lineLimit(1).help(entry.relativePath)
                }.accessibilityIdentifier("entry.name.\(entry.id)")
            }
            TableColumn("分配大小") { entry in Text(measuredBytes(entry)).font(.caption).monospacedDigit().accessibilityIdentifier("entry.allocated.\(entry.id)") }.width(110)
            TableColumn("逻辑大小") { entry in Text(measuredBytes(entry, logical: true)).font(.caption).monospacedDigit().accessibilityIdentifier("entry.logical.\(entry.id)") }.width(110)
            TableColumn("审阅能力") { entry in Text(sharedLabel(entry) ?? capability(entry)).font(.caption) }.width(96)
        }
        .accessibilityIdentifier("results.table")
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let entry = model.rows.first(where: { $0.id == id }) {
                Button("在 Finder 显示") { model.reveal(entry) }
                if entry.identity?.kind == .directory { Button("查看目录") { model.enter(entry) } }
            }
        } primaryAction: { ids in
            if let id = ids.first, let entry = model.rows.first(where: { $0.id == id }), entry.identity?.kind == .directory { model.enter(entry) }
        }
    }
    private func detail(_ entry: Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(URL(fileURLWithPath: entry.relativePath).lastPathComponent).font(.headline)
                Text(entry.relativePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Label(capability(entry), systemImage: entry.selectable ? "checkmark.circle" : "lock.shield").font(.subheadline)
                Divider()
                Text(entry.decision.reason).font(.callout)
                if sharedLabel(entry) != nil { Text("共享对象：已在另一路径计量；分配大小为文件原始属性，不重复计入地图。").font(.caption).foregroundStyle(.secondary) }
                LabeledContent("所属", value: entry.decision.owner).font(.caption)
                LabeledContent("分配", value: measuredBytes(entry)).font(.caption)
                LabeledContent("逻辑", value: measuredBytes(entry, logical: true)).font(.caption)
                if let timestamp = entry.identity?.mtimeNs, let nanoseconds = Double(timestamp) {
                    LabeledContent("修改时间", value: Date(timeIntervalSince1970: nanoseconds / 1_000_000_000).formatted(date: .numeric, time: .shortened)).font(.caption)
                }
                Text("重建影响：\(entry.decision.rebuildCost)").font(.caption)
                if entry.identity?.kind == .directory { Button("查看这个目录") { model.enter(entry) }.accessibilityIdentifier("detail.enter") }
                Button("在 Finder 显示") { model.reveal(entry) }.accessibilityIdentifier("entry.reveal.\(entry.id)")
                Button("忽略此项", action: model.ignoreFocused).disabled(model.scanning).accessibilityIdentifier("entry.ignore.\(entry.id)")
                DisclosureGroup("判断依据与限制") {
                    Text("规则：\(entry.decision.ruleIDs.joined(separator: "、"))\n原因码：\(entry.decision.reasonCodes.joined(separator: "、"))\n独占可回收量未知，受共享块与快照影响。清理安全验收未完成，执行未开放。")
                        .font(.caption2).textSelection(.enabled)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    private var footer: some View {
        VStack(spacing: 6) {
            Divider()
            HStack {
                Text("已选 \(model.selectedCount) 项\(model.hiddenSelectedCount > 0 ? " · 隐藏 \(model.hiddenSelectedCount) 项" : "")").font(.callout)
                Spacer()
                if model.page == .map || model.page == .large || model.page == .candidates {
                    Button("选择本页可操作项", action: model.selectDisplayed).disabled(model.scanning || model.restoredSnapshot || !model.rows.contains(where: \.selectable)).help("只选择当前显示的 \(model.rows.filter(\.selectable).count) 项")
                }
                Button("取消选择", action: model.clearSelection).disabled(model.selectedCount == 0)
                Button("预览计划", action: model.preview).disabled(model.selectedCount == 0 || model.scanning || model.restoredSnapshot).accessibilityIdentifier("plan.preview")
            }
            HStack { Text("先审阅后处理 · 当前仅预览，执行未开放").font(.caption).foregroundStyle(.secondary); Spacer() }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("忽略列表").font(.headline)
            Text("改变忽略后必须重新扫描；不会绕过保护策略。").font(.caption).foregroundStyle(.secondary)
            List(model.ignored) { item in HStack { Text(item.matchValue).textSelection(.enabled); Spacer(); Button("撤销忽略") { model.removeIgnore(item.id) } } }
            Text("扫描：受限顺序枚举 · 索引上限：1 GiB · 磁盘可用余量至少保留 1 GiB")
            Text("私有索引：\(model.storagePath)").font(.caption).textSelection(.enabled)
            Text("应用与代码仓库只计量、不可选择；凭据、会话、云同步及待恢复事务不深入。")
            Text("权限缺口需你自行在系统设置处理后重扫。历史裁剪与并发设置尚未开放。")
        }.padding(20)
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("尚无已执行操作", systemImage: "clock").font(.headline)
            Text("当前版本提供存储分析和计划预览。清理与收据恢复须在安全验收完成后开放。").foregroundStyle(.secondary)
            Spacer()
        }.padding(20)
    }
    private var planView: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 14) {
            Text("清理计划预览").font(.title2.bold())
            Picker("动作", selection: $model.action) {
                Text("移入废纸篓").tag(CleanupAction.trash)
                Text("永久删除缓存").tag(CleanupAction.purge)
            }.pickerStyle(.segmented).onChange(of: model.action) { model.preview() }
            Text(model.scope?.rootPath ?? "").font(.caption).lineLimit(2).textSelection(.enabled)
            Text(model.action == .trash ? "移入废纸篓通常不会增加可用空间。" : "永久删除无法撤销，仅限已准入缓存叶子文件。")
            Text(model.planMessage).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plan.status")
            if let plan = model.plan {
                Text("固定 \(plan.items.count) 项 · 有效至 \(plan.expiresAt.formatted())").font(.caption)
                List(plan.items) { item in
                    VStack(alignment: .leading) {
                        Text(item.sourceRelativePath)
                        if let result = model.preflight.first(where: { $0.itemID == item.id }) { Label(result.reason, systemImage: result.accepted ? "checkmark.shield" : "lock.shield").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                DisclosureGroup("计划校验信息") { Text("hash：\(plan.hash)\nM2安全验收未完成，执行禁用。").font(.caption2).textSelection(.enabled) }
            } else { Spacer() }
            HStack {
                Button("关闭") { model.showPlan = false }.accessibilityIdentifier("plan.close")
                Spacer()
                Button(model.action == .trash ? "确认移入废纸篓（未开放）" : "确认永久删除（未开放）") {}
                    .disabled(true).accessibilityIdentifier(model.action == .trash ? "plan.confirmTrash" : "plan.confirmPurge")
            }
        }.padding(24).frame(width: 650, height: 500)
            .task(id: model.plan?.id) {
                guard let plan = model.plan else { return }
                try? await Task.sleep(for: .seconds(max(0, plan.expiresAt.timeIntervalSinceNow)))
                guard !Task.isCancelled, model.plan?.id == plan.id else { return }
                model.invalidatePlan("计划已过期，需重新预览")
            }
    }
    private func sharedLabel(_ entry: Entry) -> String? {
        entry.identity?.kind == .regular && (entry.allocatedBytes?.value ?? 0) > 0 && model.mapWeights[entry.id] == 0 ? "共享 · 已另计" : nil
    }
    private func measuredBytes(_ entry: Entry, logical: Bool = false) -> String {
        guard let value = logical ? entry.logicalBytes : entry.allocatedBytes else { return "未知" }
        if entry.identity?.kind == .directory && entry.measureState != .measured {
            return value.value > 0 ? "已知 " + bytes(value.value) + "＋未知" : "未知"
        }
        return bytes(value.value)
    }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file) }
    private func scanLabel(_ state: ScanState) -> String {
        switch state { case .completed: "扫描完成"; case .partial: "部分结果（覆盖不完整）"; case .cancelled: "已取消（部分结果）"; case .failed: "扫描失败"; case .idle: "未扫描"; case .preparing: "准备扫描"; case .running: "扫描中" }
    }
    private func capability(_ entry: Entry) -> String {
        if entry.decision.disposition == .protect { return "保护 · 仅计量" }
        if entry.decision.disposition == .ignore { return "已忽略" }
        switch entry.decision.capability { case .previewOnly: return "仅预览"; case .trashEligible: return "可移入废纸篓"; case .purgeEligible: return "可永久清理缓存" }
    }
    private func categoryColor(_ category: StorageCategory) -> Color {
        switch category { case .cache: .orange; case .developer: .indigo; case .downloads: .teal; case .media: .pink; case .documents: .blue; case .applications: .purple; case .other: .gray }
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View { content.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1) } }
}
private extension View { func cardStyle() -> some View { modifier(CardStyle()) } }

private enum LegacyIndexFixture {
    static func write(_ database: URL, fixture: URL) throws -> UUID {
        let reader = MacFileReader(), scope = try MacFileReader().scope(path: fixture.path)
        var run = ScanRun(scope: scope, ruleSetVersion: "seed-1")
        run.state = .completed; run.processedCount = 3; run.finishedAt = Date()
        if ProcessInfo.processInfo.arguments.contains("-lmcActiveSnapshotFixture") {
            run.state = .running; run.finishedAt = nil
        } else if ProcessInfo.processInfo.arguments.contains("-lmcPartialSnapshotFixture") {
            run.state = .partial; run.issueCount = 1
            run.stopReason = "自建测试范围存在权限缺口，结果不完整"
        }
        var paths = ["", "Downloads", "Downloads/保留的安装包.dmg"]
        if ProcessInfo.processInfo.arguments.contains("-lmcEligibleRestoreFixture") {
            paths.append("Downloads/可审阅大文件_很长中文名称_保留原始资料.dat")
            run.processedCount = 4
        }
        var entries: [Entry] = []
        for path in paths {
            let metadata = try reader.metadata(scope: scope, relativePath: path)
            let parent = path.isEmpty ? nil : path == "Downloads" ? entries.first?.id : entries.first { $0.relativePath == "Downloads" }?.id
            let entry = Entry(scanID: run.id, parentID: parent, relativePath: path, identity: metadata.identity,
                              logicalBytes: metadata.identity.kind == .directory ? nil : metadata.identity.size.value,
                              allocatedBytes: metadata.identity.kind == .directory ? nil : metadata.allocated,
                              measureState: .measured, decision: RuleEngine(homePath: fixture.path).decide(relativePath: path, identity: metadata.identity, absolutePath: fixture.appendingPathComponent(path).path))
            entries.append(entry)
        }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK, let connection else { throw CleanerError(.invalidInput, "旧索引测试目录无法创建") }
        defer { sqlite3_close(connection) }
        let schema = """
        CREATE TABLE scans(id TEXT PRIMARY KEY,json TEXT NOT NULL,summary TEXT);
        CREATE TABLE entries(id TEXT PRIMARY KEY,scan TEXT NOT NULL,parent TEXT,path TEXT NOT NULL,json TEXT NOT NULL,kind TEXT,logical INTEGER,allocated INTEGER,unknown INTEGER NOT NULL,candidate INTEGER NOT NULL,aggregate_logical INTEGER NOT NULL DEFAULT 0,aggregate_allocated INTEGER NOT NULL DEFAULT 0,aggregate_unknown INTEGER NOT NULL DEFAULT 0,category TEXT NOT NULL DEFAULT 'other',counted_logical INTEGER NOT NULL DEFAULT 0,counted_allocated INTEGER NOT NULL DEFAULT 0,unique_leaf INTEGER NOT NULL DEFAULT 0,modified INTEGER NOT NULL DEFAULT 0,preview_cache INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX entry_parent ON entries(scan,parent); CREATE INDEX entry_allocated ON entries(scan,allocated);
        CREATE TABLE measured(scan TEXT,device TEXT,inode TEXT,PRIMARY KEY(scan,device,inode));
        PRAGMA user_version=4;
        """
        guard sqlite3_exec(connection, schema, nil, nil, nil) == SQLITE_OK else { throw CleanerError(.invalidInput, "旧索引测试结构创建失败") }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        func execute(_ sql: String, _ values: [String?]) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else { throw CleanerError(.invalidInput, "旧索引测试语句失败") }
            defer { sqlite3_finalize(statement) }
            for (index, value) in values.enumerated() {
                if let value { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
                else { sqlite3_bind_null(statement, Int32(index + 1)) }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw CleanerError(.invalidInput, "旧索引测试写入失败") }
        }
        try execute("INSERT INTO scans(id,json) VALUES(?,?)", [run.id.uuidString, String(decoding: try Codec.encoder().encode(run), as: UTF8.self)])
        for entry in entries {
            guard let identity = entry.identity else { throw CleanerError(.invalidInput, "旧索引测试缺少真实身份") }
            let storedIdentity = FileIdentity(volumeID: identity.volumeID, device: identity.device.value, inode: identity.inode.value, kind: identity.kind, size: identity.size.value, mtimeNs: identity.mtimeNs, ctimeNs: identity.ctimeNs, linkCount: identity.linkCount.value, ownerUID: identity.ownerUID.value, parentChain: [])
            let stored = Entry(id: entry.id, scanID: run.id, parentID: entry.parentID, relativePath: entry.relativePath, identity: storedIdentity, logicalBytes: entry.logicalBytes?.value, allocatedBytes: entry.allocatedBytes?.value, measureState: .measured, decision: entry.decision)
            let leaf = identity.kind == .regular
            let logical = leaf ? entry.logicalBytes?.value ?? 0 : 0, allocated = leaf ? entry.allocatedBytes?.value ?? 0 : 0
            let category = StorageClassifier.category(relativePath: entry.relativePath, identity: identity, decision: entry.decision)
            try execute("INSERT INTO entries(id,scan,parent,path,json,kind,logical,allocated,unknown,candidate,category,counted_logical,counted_allocated,unique_leaf,modified,preview_cache) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [entry.id.uuidString, run.id.uuidString, entry.parentID?.uuidString, entry.relativePath, String(decoding: try Codec.encoder().encode(stored), as: UTF8.self), identity.kind.rawValue, entry.logicalBytes.map { String($0.value) }, entry.allocatedBytes.map { String($0.value) }, "0", "0", category.rawValue, String(logical), String(allocated), leaf ? "1" : "0", identity.mtimeNs, "0"])
            if leaf { try execute("INSERT INTO measured VALUES(?,?,?)", [run.id.uuidString, String(identity.device.value), String(identity.inode.value)]) }
            if let parent = entry.parentID {
                try execute("WITH RECURSIVE a(id,parent) AS (SELECT id,parent FROM entries WHERE id=? UNION ALL SELECT e.id,e.parent FROM entries e JOIN a ON e.id=a.parent) UPDATE entries SET aggregate_logical=aggregate_logical+?,aggregate_allocated=aggregate_allocated+? WHERE id IN (SELECT id FROM a)", [parent.uuidString, String(logical), String(allocated)])
            }
        }
        guard sqlite3_exec(connection, """
        CREATE TABLE scan_totals(scan TEXT PRIMARY KEY,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,unknown INTEGER NOT NULL,entry_count INTEGER NOT NULL,large_count INTEGER NOT NULL,preview_count INTEGER NOT NULL,preview_bytes INTEGER NOT NULL);
        CREATE TABLE category_totals(scan TEXT NOT NULL,category TEXT NOT NULL,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,file_count INTEGER NOT NULL,PRIMARY KEY(scan,category));
        INSERT INTO scan_totals SELECT scan,sum(counted_logical),sum(counted_allocated),sum(unknown),count(*),sum(CASE WHEN kind='regular' AND logical>=536870912 THEN 1 ELSE 0 END),0,0 FROM entries GROUP BY scan;
        INSERT INTO category_totals SELECT scan,category,sum(counted_logical),sum(counted_allocated),sum(unique_leaf) FROM entries GROUP BY scan,category;
        CREATE INDEX entry_issues ON entries(scan,unknown,path) WHERE unknown=1;
        CREATE INDEX entry_topfolders ON entries(scan,parent,kind,aggregate_allocated DESC,path) WHERE kind='directory';
        """, nil, nil, nil) == SQLITE_OK else { throw CleanerError(.invalidInput, "旧索引测试统计创建失败") }
        return run.id
    }
}
