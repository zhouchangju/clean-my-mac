import Foundation
import CoreGraphics

/// squarified treemap 布局（Bruls/Huizing/van Wijk 2000 公开学术算法的清洁室实现）。
/// 沿短边成行；贪心接受使行内最差纵横比不恶化的下一项；锁定行后对剩余矩形递归。
/// 输出矩形面积与权重成比例，且并集恰好覆盖容器（浮点 epsilon 内）；纯函数、确定性。
public enum SquarifiedTreemap {
    /// 把 weights 布局进 rect，返回 id → 矩形（单位与 rect 相同）。
    /// 零/负/非有限权重被忽略；输入为空、全零或容器退化时返回空字典。
    /// 同一 id 出现多次时，后写入者覆盖先前的矩形。
    public static func layout<ID: Hashable>(weights: [(id: ID, weight: Double)], in rect: CGRect) -> [ID: CGRect] {
        // 过滤非法权重后按权重降序稳定排序（同权重按输入顺序），保证确定性
        let sorted = weights.enumerated()
            .filter { $0.element.weight.isFinite && $0.element.weight > 0 }
            .sorted { lhs, rhs in lhs.element.weight == rhs.element.weight ? lhs.offset < rhs.offset : lhs.element.weight > rhs.element.weight }
        guard !sorted.isEmpty, rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return [:] }
        var result: [ID: CGRect] = [:]; result.reserveCapacity(sorted.count)
        var remaining = rect
        var total = sorted.reduce(0.0) { $0 + $1.element.weight }
        var start = 0
        while start < sorted.count {
            let short = min(remaining.width, remaining.height)
            guard short.isFinite, short > 0, total > 0 else { break }
            // 贪心成行：逐项尝试，接受使最差纵横比不恶化的项
            var rowSum = 0.0, rowEnd = start, best = Double.infinity
            while rowEnd < sorted.count {
                let candidate = rowSum + sorted[rowEnd].element.weight
                var worst = 0.0
                for i in start...rowEnd {
                    let thickness = candidate / total * max(remaining.width, remaining.height)  // 条带厚度（沿长边）
                    let along = sorted[i].element.weight / candidate * short                    // 项沿短边的长度
                    worst = max(worst, max(thickness / along, along / thickness))
                }
                if worst <= best { best = worst; rowSum = candidate; rowEnd += 1 } else { break }
            }
            // 首项最差比有限，行内至少会接受一项
            place(sorted, start..<rowEnd, rowSum: rowSum, total: total, in: &remaining, into: &result)
            total -= rowSum
            start = rowEnd
        }
        return result
    }
    /// 放置一行：条带厚度沿长边切入，项沿短边依次堆叠；
    /// 行内位置用累计分数计算并把行尾项强制贴到剩余矩形边界，保证并集恰好覆盖。
    private static func place<ID: Hashable>(_ sorted: [(offset: Int, element: (id: ID, weight: Double))], _ range: Range<Int>, rowSum: Double, total: Double, in remaining: inout CGRect, into result: inout [ID: CGRect]) {
        let vertical = remaining.width >= remaining.height  // 短边=高 → 垂直堆叠的列
        let long = vertical ? remaining.width : remaining.height
        let short = vertical ? remaining.height : remaining.width
        let thickness = min(max(0, rowSum / total * long), long)
        var offset = vertical ? remaining.minY : remaining.minX
        let spanEnd = vertical ? remaining.maxY : remaining.maxX
        for i in range {
            let item = sorted[i].element
            let length = i == range.upperBound - 1 ? max(0, spanEnd - offset) : item.weight / rowSum * short
            if vertical { result[item.id] = CGRect(x: remaining.minX, y: offset, width: thickness, height: length) }
            else { result[item.id] = CGRect(x: offset, y: remaining.minY, width: length, height: thickness) }
            offset += length
        }
        if vertical { remaining = CGRect(x: remaining.minX + thickness, y: remaining.minY, width: max(0, remaining.width - thickness), height: remaining.height) }
        else { remaining = CGRect(x: remaining.minX, y: remaining.minY + thickness, width: remaining.width, height: max(0, remaining.height - thickness)) }
    }
}
