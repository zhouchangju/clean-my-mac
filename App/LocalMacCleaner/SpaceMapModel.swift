import Foundation
import CoreGraphics
import Observation
import CleanerDomain
import CleanerMacPlatform
import CleanerViz

/// 空间地图 v2 视图模型：层栈导航（下钻/后退/前进/面包屑跳级）+ 当前层按需查询。
/// 每次导航只查当前层 top-K 元数据（SQLiteScanStore.children）与该层去重权重
/// （mapWeights，硬链接别名计 0），绝不整树加载；无 Timer/轮询，
/// 刷新由导航令牌与扫描完成事件驱动。
@MainActor
@Observable
final class SpaceMapModel {
    /// 导航层：entryID 为 nil 表示扫描根目录。
    struct Level: Equatable {
        let entryID: UUID?
        let name: String
        var totalBytes: UInt64   // 该层聚合字节（去重计量，来自父级 aggregate / 根层扫描摘要）
    }
    /// 瓦片：普通瓦片对应一个条目；“其他”为聚合块（entryID 为 nil，不可下钻）。
    struct Tile: Identifiable, Equatable {
        enum ID: Hashable { case entry(UUID); case other }
        let id: ID
        let entryID: UUID?
        let name: String
        let bytes: UInt64          // 去重计量字节（mapWeights 语义）
        let isDirectory: Bool
        let partial: Bool          // 目录计量含未知部分
        let mtime: Date?
        let share: Double          // 占当前层真实字节比例（未压缩）
        let unitRect: CGRect       // 0…1 单位矩形，视图按实际几何缩放
    }
    enum Mode: String, CaseIterable { case treemap = "树图"; case list = "列表" }

    static let fetchLimit = 120    // 当前层元数据取回上限（列表模式复用同一批数据）
    static let tileTopN = 30       // 瓦片截断，与 CleanerViz cap 默认对齐
    static let tileMinRatio = 0.02

    private(set) var levels: [Level] = []
    private(set) var index = 0
    private(set) var tiles: [Tile] = []
    private(set) var rows: [Entry] = []          // 列表模式数据：当前层最大的前 fetchLimit 项
    private(set) var otherCount = 0              // 被并入“其他”的已取回小项数
    private(set) var levelTotalBytes: UInt64 = 0
    private(set) var truncated = false           // 当前层还有未取回的更多项
    private(set) var focused: Entry?             // 详情面板（文件或列表选中项）
    private(set) var loading = false
    private(set) var loadError: String?
    var mode: Mode = .treemap
    /// 导航/刷新令牌：用户导航或显式刷新时递增，驱动页面 task 重查当前层。
    private(set) var navigationToken = 0
    @ObservationIgnored private var entriesByID: [UUID: Entry] = [:]
    @ObservationIgnored private var weightsByID: [UUID: UInt64] = [:]
    @ObservationIgnored private var loadedRunID: UUID?
    @ObservationIgnored private var reloadGeneration = 0

    var current: Level? { levels.indices.contains(index) ? levels[index] : nil }
    var canBack: Bool { index > 0 }
    var canForward: Bool { index < levels.count - 1 }

    // MARK: 导航

    /// 下钻 = push：截断前进分支后压入新层。
    func enter(_ tile: Tile) {
        guard tile.isDirectory, let entryID = tile.entryID, entriesByID[entryID] != nil else { return }
        if index < levels.count - 1 { levels.removeSubrange((index + 1)...) }
        levels.append(Level(entryID: entryID, name: tile.name, totalBytes: tile.bytes))
        index = levels.count - 1
        focused = nil
        navigationToken += 1
    }
    /// 后退/前进 = 索引移动（保留栈，前进分支不丢失）。
    func back() { guard canBack else { return }; index -= 1; focused = nil; navigationToken += 1 }
    func forward() { guard canForward else { return }; index += 1; focused = nil; navigationToken += 1 }
    /// 面包屑跳级 = 截断到指定层。
    func jump(to target: Int) {
        guard levels.indices.contains(target) else { return }
        if target < levels.count - 1 { levels.removeSubrange((target + 1)...) }
        index = target; focused = nil; navigationToken += 1
    }
    /// 手动刷新 / 扫描完成回调共用入口。
    func requestRefresh() { navigationToken += 1 }
    /// 点击文件瓦片或列表行：显示详情面板。
    func focus(_ tile: Tile) {
        guard !tile.isDirectory, let entryID = tile.entryID else { return }
        focused = entriesByID[entryID]
    }
    func focusEntry(_ entry: Entry) { focused = entry }
    func entry(for id: UUID) -> Entry? { entriesByID[id] }
    /// 去重计量字节（硬链接别名为 0；文件原始属性看 Entry.allocatedBytes）。
    func weight(of id: UUID) -> UInt64? { weightsByID[id] }

    // MARK: 查询

    /// 依据 model.run / model.activeStore 拉取当前层数据；run 为 nil 时清空回到引导态。
    /// 换 scanID（新扫描或恢复快照）时重置到根层；根层总量随扫描推进刷新。
    func reload(from model: CleanerModel) async {
        let generation = reloadGeneration + 1
        reloadGeneration = generation
        guard let run = model.run, let store = model.activeStore else {
            levels = []; index = 0; tiles = []; rows = []; entriesByID = [:]; weightsByID = [:]
            levelTotalBytes = 0; otherCount = 0; truncated = false; focused = nil; loadError = nil; loadedRunID = nil
            return
        }
        if levels.isEmpty || loadedRunID != run.id {
            levels = [Level(entryID: nil, name: "扫描根目录", totalBytes: await rootTotal(runID: run.id, model: model, store: store))]
            index = 0; loadedRunID = run.id; focused = nil
        }
        if index == 0, levels[0].entryID == nil { levels[0].totalBytes = await rootTotal(runID: run.id, model: model, store: store) }
        guard generation == reloadGeneration else { return }
        let levelEntryID = levels[index].entryID
        loading = true
        defer { loading = false }
        do {
            // 下钻时缓存的层总量可能已过时（扫描推进/完成后），用该层条目的 aggregate 刷新
            if let entryID = levelEntryID,
               let parentEntry = try await store.entries(scanID: run.id, ids: [entryID]).first,
               parentEntry.identity?.kind == .directory,
               let aggregate = parentEntry.allocatedBytes?.value, aggregate > levels[index].totalBytes {
                levels[index].totalBytes = aggregate
            }
            guard generation == reloadGeneration else { return }
            let level = levels[index]
            // 管线：children 取当前层元数据（按展示大小降序），mapWeights 按 ids 取去重权重
            let children = try await store.children(scanID: run.id, parentID: level.entryID, limit: Self.fetchLimit)
            guard generation == reloadGeneration else { return }
            let weights = try await store.mapWeights(scanID: run.id, parentID: level.entryID, ids: Set(children.map(\.id)))
            guard generation == reloadGeneration else { return }
            apply(children: children, weights: weights)
            loadError = nil
        } catch {
            guard generation == reloadGeneration else { return }
            loadError = String(describing: error)
            tiles = []; rows = []; entriesByID = [:]; weightsByID = [:]; otherCount = 0; truncated = false
        }
    }

    /// 根层总量：优先 CleanerModel 已刷新的扫描摘要，缺失时查 store（扫描早期/恢复态）。
    private func rootTotal(runID: UUID, model: CleanerModel, store: SQLiteScanStore) async -> UInt64 {
        if let known = model.summary?.knownAllocatedBytes, known > 0 { return known }
        return (try? await store.summary(scanID: runID))?.knownAllocatedBytes ?? 0
    }

    /// 组装展示数据：正权重条目逐项压缩 → cap 截断 → squarify 单位矩形；
    /// “其他”字节 = 层总量 − 入围项字节和（自动包含未取回项，总量不丢）。
    private func apply(children: [Entry], weights: [UUID: UInt64]) {
        rows = children
        entriesByID = Dictionary(children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        weightsByID = weights
        truncated = children.count >= Self.fetchLimit
        levelTotalBytes = current?.totalBytes ?? 0
        let positive: [(id: UUID, bytes: UInt64)] = children.compactMap { entry in
            let weight = weights[entry.id] ?? 0
            return weight > 0 ? (id: entry.id, bytes: weight) : nil
        }
        let capped = TreemapWeights.cap(items: positive.map { (id: $0.id, weight: TreemapWeights.compress(Double($0.bytes))) },
                                        topN: Self.tileTopN, minRatio: Self.tileMinRatio)
        let keptBytes = capped.kept.reduce(UInt64(0)) { $0 + (weights[$1.id] ?? 0) }
        let otherBytes = levelTotalBytes > keptBytes ? levelTotalBytes - keptBytes : 0
        // “其他”按聚合字节整体压缩（视作一个虚拟大项），避免大量小项的压缩和喧宾夺主
        var layoutItems: [(id: Tile.ID, weight: Double)] = capped.kept.map { (id: .entry($0.id), weight: $0.weight) }
        if otherBytes > 0 { layoutItems.append((id: .other, weight: TreemapWeights.compress(Double(otherBytes)))) }
        let rects = SquarifiedTreemap.layout(weights: layoutItems, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        var result: [Tile] = []
        for kept in capped.kept {
            guard let rect = rects[.entry(kept.id)], let entry = entriesByID[kept.id] else { continue }
            let bytes = weights[kept.id] ?? 0
            result.append(Tile(id: .entry(kept.id), entryID: kept.id, name: Self.displayName(entry), bytes: bytes,
                               isDirectory: entry.identity?.kind == .directory,
                               partial: entry.identity?.kind == .directory && entry.measureState != .measured,
                               mtime: Self.modified(entry),
                               share: levelTotalBytes > 0 ? Double(bytes) / Double(levelTotalBytes) : 0,
                               unitRect: rect))
        }
        if otherBytes > 0, let rect = rects[.other] {
            result.append(Tile(id: .other, entryID: nil, name: "其他", bytes: otherBytes, isDirectory: false, partial: false,
                               mtime: nil, share: levelTotalBytes > 0 ? Double(otherBytes) / Double(levelTotalBytes) : 0,
                               unitRect: rect))
        }
        tiles = result
        otherCount = positive.count - capped.kept.count
    }

    static func displayName(_ entry: Entry) -> String {
        let name = URL(fileURLWithPath: entry.relativePath).lastPathComponent
        return name.isEmpty ? entry.relativePath : name
    }
    static func modified(_ entry: Entry) -> Date? {
        guard let text = entry.identity?.mtimeNs, let nanoseconds = Double(text) else { return nil }
        return Date(timeIntervalSince1970: nanoseconds / 1_000_000_000)
    }
}
