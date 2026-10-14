import Foundation

/// treemap 权重预处理纯函数：对数压缩与 top-N 截断。
/// 压缩用于抑制极端悬殊的字节权重（让小目录仍可见）；指数取折中值 4
///（过大会让面积脱离真实占比，过小则小项不可见，默认值可在调用处调整）。
public enum TreemapWeights {
    public static let defaultExponent = 4.0
    /// pow(log2(1 + bytes), exponent)；非正或非有限输入返回 0。
    public static func compress(_ bytes: Double, exponent: Double = defaultExponent) -> Double {
        guard bytes.isFinite, bytes > 0 else { return 0 }
        return pow(log2(1 + bytes), exponent)
    }
    /// 批量压缩（逐项独立压缩，不做总量再平衡）。
    public static func compress(weights: [Double], exponent: Double = defaultExponent) -> [Double] {
        weights.map { compress($0, exponent: exponent) }
    }

    /// top-N 截断结果：kept 为保留项（降序）；other 为其余全部项的权重和与项数。
    public struct Capped<ID: Hashable> {
        public let kept: [(id: ID, weight: Double)]
        public let otherWeight: Double
        public let otherCount: Int
    }
    /// 按权重降序取前 topN 项，再丢弃其中小于首项 minRatio 的项；
    /// 其余全部（topN 之外、被丢弃的小项）合并为"其他"。
    /// 总量守恒：Σkept + otherWeight == Σ(正值输入权重)；非正值输入不计入任何一侧。
    public static func cap<ID: Hashable>(items: [(id: ID, weight: Double)], topN: Int = 30, minRatio: Double = 0.02) -> Capped<ID> {
        let sorted = items.enumerated()
            .filter { $0.element.weight.isFinite && $0.element.weight > 0 }
            .sorted { lhs, rhs in lhs.element.weight == rhs.element.weight ? lhs.offset < rhs.offset : lhs.element.weight > rhs.element.weight }
        guard !sorted.isEmpty else { return Capped(kept: [], otherWeight: 0, otherCount: 0) }
        let total = sorted.reduce(0.0) { $0 + $1.element.weight }
        let threshold = sorted[0].element.weight * max(0, minRatio)
        let kept = sorted.prefix(max(0, topN)).filter { $0.element.weight >= threshold }
        let keptSum = kept.reduce(0.0) { $0 + $1.element.weight }
        return Capped(kept: kept.map { (id: $0.element.id, weight: $0.element.weight) },
                      otherWeight: max(0, total - keptSum),
                      otherCount: sorted.count - kept.count)
    }
}
