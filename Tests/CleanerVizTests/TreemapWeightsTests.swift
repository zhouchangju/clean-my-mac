import Testing
import Foundation
@testable import CleanerViz

// MARK: compress

@Test func compressKnownValues() {
    #expect(TreemapWeights.compress(0) == 0)
    #expect(TreemapWeights.compress(-8) == 0)
    #expect(TreemapWeights.compress(.nan) == 0)
    #expect(TreemapWeights.compress(.infinity) == 0)
    #expect(TreemapWeights.compress(1) == 1)              // log2(2)^4 = 1
    #expect(TreemapWeights.compress(3) == 16)             // log2(4)^4 = 16
    #expect(TreemapWeights.compress(7) == 81)             // log2(8)^4 = 81
    #expect(abs(TreemapWeights.compress(3, exponent: 1) - 2) <= 1e-12)   // log2(4) = 2
    #expect(abs(TreemapWeights.compress(3, exponent: 2) - 4) <= 1e-12)
}

@Test func compressIsMonotonicAndBatchMatchesSingle() {
    let bytes: [Double] = [1, 10, 100, 1_000, 10_000, 1e6, 1e9, 1e12]
    let compressed = TreemapWeights.compress(weights: bytes)
    #expect(compressed == bytes.map { TreemapWeights.compress($0) })
    for i in 1..<compressed.count { #expect(compressed[i] >= compressed[i - 1]) }
    // 对数压缩显著收窄悬殊比：1e12:1 原始比 1e12 → 压缩后比约 40^4:1^4
    #expect(compressed[7] / compressed[0] < 1e7)
}

// MARK: cap

@Test func capKeepsTopNAndMergesRest() {
    var items: [(id: Int, weight: Double)] = []
    for i in 1...40 { items.append((id: i, weight: Double(100 - i))) }  // 99..60，全部 ≥ 首项 2%
    let capped = TreemapWeights.cap(items: items, topN: 30, minRatio: 0.02)
    #expect(capped.kept.count == 30)
    #expect(capped.kept.first?.id == 1 && capped.kept.first?.weight == 99)
    #expect(capped.otherCount == 10)
    let keptSum = capped.kept.reduce(0.0) { $0 + $1.weight }
    let total = items.reduce(0.0) { $0 + $1.weight }
    #expect(abs(keptSum + capped.otherWeight - total) <= 1e-9)
}

@Test func capDropsItemsBelowMinRatioOfFirst() {
    // 首项 100 → 阈值 2：1.9 即使排名靠前也被并入其他
    let items: [(id: String, weight: Double)] = [("big", 100), ("mid", 5), ("small", 1.9), ("tiny", 0.01)]
    let capped = TreemapWeights.cap(items: items, topN: 30, minRatio: 0.02)
    #expect(capped.kept.map(\.id) == ["big", "mid"])
    #expect(capped.otherCount == 2)
    #expect(abs(capped.kept.reduce(0.0) { $0 + $1.weight } + capped.otherWeight - 106.91) <= 1e-9)
}

@Test func capConservesTotalForVariousShapes() {
    let shapes: [[(id: Int, weight: Double)]] = [
        [],                                                     // 空
        [(1, 7)],                                               // 单项
        [(1, 5), (2, 5), (3, 5)],                               // 少于 topN
        (1...60).map { (id: $0, weight: Double($0)) },          // 超过 topN 且极端悬殊
        [(1, 1e9), (2, 1), (3, 1e-9)],                          // 悬殊 + 低于阈值
    ]
    for items in shapes {
        let capped = TreemapWeights.cap(items: items)
        let total = items.filter { $0.weight.isFinite && $0.weight > 0 }.reduce(0.0) { $0 + $1.weight }
        #expect(abs(capped.kept.reduce(0.0) { $0 + $1.weight } + capped.otherWeight - total) <= 1e-9 * max(1, total))
    }
}

@Test func capIgnoresNonPositiveWeightsEntirely() {
    let capped = TreemapWeights.cap(items: [("a", 10), ("z", 0), ("n", -3), ("nan", .nan)], topN: 30, minRatio: 0.02)
    #expect(capped.kept.map(\.id) == ["a"])
    #expect(capped.otherCount == 0 && capped.otherWeight == 0)
}

@Test func capEmptyReturnsEmpty() {
    let capped = TreemapWeights.cap(items: [(id: Int, weight: Double)](), topN: 30, minRatio: 0.02)
    #expect(capped.kept.isEmpty && capped.otherWeight == 0 && capped.otherCount == 0)
}

@Test func capZeroTopNMergesEverything() {
    // topN=0 语义：全部并入其他且不丢量
    let capped = TreemapWeights.cap(items: [("a", 4), ("b", 1)], topN: 0, minRatio: 0.02)
    #expect(capped.kept.isEmpty && capped.otherCount == 2 && abs(capped.otherWeight - 5) <= 1e-12)
}

@Test func capTieBreakKeepsInputOrder() {
    let capped = TreemapWeights.cap(items: [("x", 5), ("a", 5), ("m", 5)], topN: 2, minRatio: 0.02)
    #expect(capped.kept.map(\.id) == ["x", "a"] && capped.otherCount == 1)
}

@Test func capSortsDescendingRegardlessOfInputOrder() {
    let shuffled: [(id: Int, weight: Double)] = [(3, 10), (1, 50), (2, 30)]
    let capped = TreemapWeights.cap(items: shuffled, topN: 3, minRatio: 0.02)
    #expect(capped.kept.map(\.id) == [1, 2, 3] && capped.kept.map(\.weight) == [50, 30, 10])
}

// MARK: 端到端：compress → cap → layout 组合

@Test func pipelineProducesCompleteTiling() {
    // 真实形态的字节分布：悬殊目录 + 一批小项，压缩后仍有部分低于首项 2% 被 cap 合并
    let bytes: [UInt64] = [900_000_000_000, 320_000_000_000, 90_000_000_000, 4_000_000_000, 500_000_000, 60_000_000, 7_000_000, 900_000, 90_000, 5_000, 500, 50]
    var items: [(id: Int, weight: Double)] = bytes.enumerated().map { (id: $0.offset + 1, weight: TreemapWeights.compress(Double($0.element))) }
    items.append((id: 99, weight: TreemapWeights.compress(Double(bytes.reduce(0, +)) / 10)))  // 模拟"其他"聚合块
    let capped = TreemapWeights.cap(items: items, topN: 30, minRatio: 0.02)
    #expect(capped.kept.first?.id == 1)
    #expect(capped.otherCount >= 1, "最小几项压缩后仍低于首项 2%，应被合并")
    var layoutInput = capped.kept
    if capped.otherWeight > 0 { layoutInput.append((id: -1, weight: capped.otherWeight)) }
    let rects = SquarifiedTreemap.layout(weights: layoutInput, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    #expect(rects.count == layoutInput.count)
    let unionArea = rects.values.reduce(0.0) { $0 + $1.width * $1.height }
    #expect(abs(unionArea - 1) <= 1e-9)
}
