import SwiftUI
import CleanerDomain
import CleanerCore
import AIAdvisorUI
import SkillAdvisorUI

/// AI 体检中心页：AI Runtime 管理（AIAdvisorUI）+ Guardian Skill 体检（SkillAdvisorUI）。
/// 组合层保持稳定；面板实现在各自包内演进（T1/T2）。
struct AICenterPage: View {
    @Bindable var model: CleanerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AIRuntimeSection(contextProvider: buildAnalysisContext)
                SkillCheckupSection()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// 为 AI 分析构造脱敏上下文：优先使用既有 Export.report 的红线脱敏导出。
    private func buildAnalysisContext() async -> String? {
        await MainActor.run { () -> String? in
            guard let scope = model.scope, !model.rows.isEmpty else { return nil }
            do {
                let data = try Export.report(entries: model.rows, includeFullPaths: false, scope: scope)
                let summary = model.dashboard.map { dashboard -> String in
                    let categories = dashboard.categories
                        .map { "\($0.category.title)：已计量 \($0.allocatedBytes) 字节 / \($0.fileCount) 项" }
                        .joined(separator: "\n")
                    return "【分类汇总】\n\(categories)"
                } ?? ""
                let volumeLine = model.volume.map { volume -> String in
                    func gb(_ v: UInt64?) -> String { v.map { String(format: "%.1f GB", Double($0) / 1_073_741_824) } ?? "未知" }
                    return "【卷】\(volume.name) 容量 \(gb(volume.capacityBytes))，可用 \(gb(volume.availableBytes))"
                } ?? ""
                let report = String(decoding: data, as: UTF8.self)
                return "\(volumeLine)\n\(summary)\n【条目导出（已脱敏）】\n\(report)"
            } catch {
                return nil
            }
        }
    }
}
