import Testing
import Foundation
import CoreGraphics
@testable import CleanerViz

/// 矩形近似断言（CGRect 无内置 accuracy 比较）。
private func expectRect(_ actual: CGRect, _ expected: CGRect, accuracy: Double = 1e-9, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(actual.minX - expected.minX) <= accuracy, "minX \(actual.minX) ≠ \(expected.minX)", sourceLocation: sourceLocation)
    #expect(abs(actual.minY - expected.minY) <= accuracy, "minY \(actual.minY) ≠ \(expected.minY)", sourceLocation: sourceLocation)
    #expect(abs(actual.width - expected.width) <= accuracy, "width \(actual.width) ≠ \(expected.width)", sourceLocation: sourceLocation)
    #expect(abs(actual.height - expected.height) <= accuracy, "height \(actual.height) ≠ \(expected.height)", sourceLocation: sourceLocation)
}

// MARK: 黄金用例（手算期望矩形）

@Test func goldenTwoItems() {
    // 100×100、权重 60/40：单项行 [60] 最差比 5/3，并入 40 恶化到 2.5 → 锁行，
    // 60 占左侧 60 宽整列，40 占剩余 40×100。
    let rects = SquarifiedTreemap.layout(weights: [(id: "a", weight: 60), (id: "b", weight: 40)], in: CGRect(x: 0, y: 0, width: 100, height: 100))
    expectRect(rects["a"] ?? .null, CGRect(x: 0, y: 0, width: 60, height: 100))
    expectRect(rects["b"] ?? .null, CGRect(x: 60, y: 0, width: 40, height: 100))
}

@Test func goldenThreeItems() {
    // 50/30/20 @100×100：[50] 比 2.0，[50,30] 恶化到 2.13 → 50 整列；
    // 剩余 50×100 中 30 单行（1.2 优于 2.5），20 收尾。
    let rects = SquarifiedTreemap.layout(weights: [(id: 1, weight: 50), (id: 2, weight: 30), (id: 3, weight: 20)], in: CGRect(x: 0, y: 0, width: 100, height: 100))
    expectRect(rects[1] ?? .null, CGRect(x: 0, y: 0, width: 50, height: 100))
    expectRect(rects[2] ?? .null, CGRect(x: 50, y: 0, width: 50, height: 60))
    expectRect(rects[3] ?? .null, CGRect(x: 50, y: 60, width: 50, height: 40))
}

@Test func goldenBrulsPaperExample() {
    // Bruls 论文示例：6×4 容器、权重 6,6,4,3,2,2,1（总和 24 == 面积）。
    // 行划分：[6,6] | [4,3] | [2] | [2] | [1]，矩形逐一手算如下。
    let input: [(id: Int, weight: Double)] = [(1, 6), (2, 6), (3, 4), (4, 3), (5, 2), (6, 2), (7, 1)]
    let rects = SquarifiedTreemap.layout(weights: input, in: CGRect(x: 0, y: 0, width: 6, height: 4))
    #expect(rects.count == 7)
    expectRect(rects[1] ?? .null, CGRect(x: 0, y: 0, width: 3, height: 2))
    expectRect(rects[2] ?? .null, CGRect(x: 0, y: 2, width: 3, height: 2))
    expectRect(rects[3] ?? .null, CGRect(x: 3, y: 0, width: 12.0 / 7.0, height: 7.0 / 3.0))
    expectRect(rects[4] ?? .null, CGRect(x: 3 + 12.0 / 7.0, y: 0, width: 9.0 / 7.0, height: 7.0 / 3.0))
    expectRect(rects[5] ?? .null, CGRect(x: 3, y: 7.0 / 3.0, width: 1.2, height: 5.0 / 3.0))
    expectRect(rects[6] ?? .null, CGRect(x: 4.2, y: 7.0 / 3.0, width: 1.2, height: 5.0 / 3.0))
    expectRect(rects[7] ?? .null, CGRect(x: 5.4, y: 7.0 / 3.0, width: 0.6, height: 5.0 / 3.0))
}

@Test func goldenEqualWeightsFormSquares() {
    // [10,10,10] @90×30：三个 30×30 正方形（最差比恒 1.0，单行锁定）。
    let rects = SquarifiedTreemap.layout(weights: [(id: "a", weight: 10), (id: "b", weight: 10), (id: "c", weight: 10)], in: CGRect(x: 0, y: 0, width: 90, height: 30))
    expectRect(rects["a"] ?? .null, CGRect(x: 0, y: 0, width: 30, height: 30))
    expectRect(rects["b"] ?? .null, CGRect(x: 30, y: 0, width: 30, height: 30))
    expectRect(rects["c"] ?? .null, CGRect(x: 60, y: 0, width: 30, height: 30))
}

// MARK: 面积比例与覆盖守恒

@Test func areasProportionalUnionCoversExactly() {
    // 非原点容器 + 10 项悬殊权重：每项面积 == 容器面积 × 权重占比；
    // 两两交集面积≈0；总面积==容器面积（并集恰好覆盖）。
    let input: [(id: Int, weight: Double)] = [(1, 97), (2, 61), (3, 34), (4, 22), (5, 13), (6, 8), (7, 5), (8, 3), (9, 2), (10, 1)]
    let rect = CGRect(x: 5, y: -3, width: 320, height: 180)
    let rects = SquarifiedTreemap.layout(weights: input, in: rect)
    #expect(rects.count == input.count)
    let total = input.reduce(0.0) { $0 + $1.weight }
    var areaSum = 0.0
    for item in input {
        let r = rects[item.id] ?? .null
        areaSum += r.width * r.height
        let expected = rect.width * rect.height * item.weight / total
        #expect(abs(r.width * r.height - expected) <= 1e-6 * max(1, expected), "item \(item.id) 面积 \(r.width * r.height) ≠ \(expected)")
    }
    #expect(abs(areaSum - rect.width * rect.height) <= 1e-6, "并集面积 \(areaSum) ≠ \(rect.width * rect.height)")
    let ordered = input.compactMap { rects[$0.id] }
    for i in 0..<ordered.count {
        for j in (i + 1)..<ordered.count {
            #expect(ordered[i].intersection(ordered[j]).width * ordered[i].intersection(ordered[j]).height <= 1e-6, "瓦片 \(i)/\(j) 重叠")
        }
    }
}

@Test func extremeSkewStillLaysOutAllItems() {
    // 1e12 vs 1：两项都必须有矩形且覆盖守恒（压缩前的布局层不歧视小项）。
    let rects = SquarifiedTreemap.layout(weights: [(id: "huge", weight: 1e12), (id: "tiny", weight: 1)], in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
    #expect(rects.count == 2)
    let unionArea = rects.values.reduce(0.0) { $0 + $1.width * $1.height }
    #expect(abs(unionArea - 1_000_000) <= 1e-6)
}

// MARK: 退化输入与确定性

@Test func emptyInputReturnsNothing() {
    #expect(SquarifiedTreemap.layout(weights: [(id: Int, weight: Double)](), in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
}

@Test func nonPositiveOrNonFiniteWeightsAreIgnored() {
    let bad: [(id: String, weight: Double)] = [("a", 0), ("b", -5), ("c", .nan), ("d", .infinity)]
    #expect(SquarifiedTreemap.layout(weights: bad, in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
    // 混合输入只保留合法项
    let mixed = SquarifiedTreemap.layout(weights: [("a", 0), ("b", 8), ("c", -1), ("d", 2)], in: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(mixed.count == 2 && mixed["b"] != nil && mixed["d"] != nil)
}

@Test func degenerateContainerReturnsNothing() {
    // CGRect 初始化器会把负宽高规范化为正数，因此退化输入只剩零/NaN/空值形态
    for size in [CGRect(x: 0, y: 0, width: 0, height: 100), CGRect(x: 0, y: 0, width: 100, height: 0), CGRect(x: 0, y: 0, width: Double.nan, height: 100), CGRect.null, CGRect.zero] {
        #expect(SquarifiedTreemap.layout(weights: [(id: "a", weight: 1)], in: size).isEmpty)
    }
}

@Test func singleItemFillsContainerExactly() {
    let rect = CGRect(x: 2, y: 3, width: 77, height: 41)
    let rects = SquarifiedTreemap.layout(weights: [(id: 9, weight: 12345)], in: rect)
    expectRect(rects[9] ?? .null, rect)
}

@Test func deterministicAcrossRunsAndInputOrder() {
    let weights: [(id: Int, weight: Double)] = [(1, 42), (2, 17), (3, 9), (4, 4), (5, 2), (6, 1)]
    let rect = CGRect(x: 0, y: 0, width: 400, height: 240)
    let first = SquarifiedTreemap.layout(weights: weights, in: rect)
    let second = SquarifiedTreemap.layout(weights: weights, in: rect)
    #expect(first == second)
    // 乱序输入先内部排序，结果一致
    let shuffled = SquarifiedTreemap.layout(weights: weights.reversed(), in: rect)
    #expect(shuffled == first)
}

@Test func duplicateIDsLastWriteWins() {
    let rects = SquarifiedTreemap.layout(weights: [(id: "x", weight: 6), (id: "y", weight: 3), (id: "x", weight: 1)], in: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(rects.count == 2 && rects["y"] != nil)
}
