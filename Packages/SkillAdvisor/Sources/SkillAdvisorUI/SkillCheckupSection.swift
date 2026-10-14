import SwiftUI
import SkillAdvisorCore

/// 体检中心区块（公共契约：App 侧 AICenterPage 直接调用）。
/// 组合两张卡片：磁盘体检（只读审计）+ 内存体检（协议状态机，受控单发动作）。
public struct SkillCheckupSection: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      StorageCheckupCard()
      MemoryCheckupCard()
      // 底部常驻边界声明
      Label {
        Text("以上动作由 Skill 安全协议执行；本应用不新增任何删除路径。")
          .font(.footnote).foregroundStyle(.secondary)
      } icon: {
        Image(systemName: "checkmark.shield").foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel("安全边界声明")
    }
  }
}

// MARK: - 磁盘体检卡片

@MainActor
@Observable
private final class StorageCheckupModel {
  var isRunning = false
  var result: StorageAuditReport?
  var skillState: String?

  private let runner: StorageAuditRunner

  init(runner: StorageAuditRunner = StorageAuditRunner()) { self.runner = runner }

  func run() {
    guard !isRunning else { return }
    isRunning = true
    // 运行在 Task.detached(.utility)，UI 只订阅结果；无定时器、无后台循环。
    Task.detached(priority: .utility) { [runner] in
      let report = await runner.runAudit()
      await MainActor.run { self.result = report; self.isRunning = false }
    }
  }
}

private struct StorageCheckupCard: View {
  @State private var model = StorageCheckupModel()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if let report = model.result { reportBody(report) }
      Button {
        model.run()
      } label: {
        if model.isRunning { ProgressView().controlSize(.small) }
        Text(model.isRunning ? "审计中…（du 扫描约需数十秒）" : "运行磁盘体检")
      }
      .disabled(model.isRunning)
    }
    .padding(14)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "internaldrive").foregroundStyle(.blue)
      Text("磁盘体检").font(.headline)
      Spacer()
      Text("mac-storage-guardian · 审计只读，不迁移任何文件")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func reportBody(_ report: StorageAuditReport) -> some View {
    if let error = report.runError {
      Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
    }
    if let raw = report.rawText {
      // 解码失败/纯文本兜底：滚动原文
      ScrollView {
        Text(raw).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 220)
      .padding(8).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    } else {
      volumesTable(report)
      categoryTable(report)
    }
    if !report.suggestions.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("建议（仅供参考，均不自动执行）").font(.subheadline.weight(.semibold))
        ForEach(Array(report.suggestions.enumerated()), id: \.offset) { _, line in
          Label(line, systemImage: "lightbulb").font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    if !report.permissionGaps.isEmpty {
      DisclosureGroup("权限盲区（\(report.permissionGaps.count) 处：审计不可见 ≠ 为空）") {
        ForEach(Array(report.permissionGaps.prefix(10).enumerated()), id: \.offset) { _, gap in
          VStack(alignment: .leading, spacing: 2) {
            Text(gap.path).font(.footnote.weight(.medium)).lineLimit(1).truncationMode(.middle)
            Text(gap.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .font(.footnote)
    }
  }

  private func volumesTable(_ report: StorageAuditReport) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("卷容量").font(.subheadline.weight(.semibold))
      ForEach(Array(report.volumes.enumerated()), id: \.offset) { _, volume in
        HStack {
          Image(systemName: volume.isInternal == false ? "externaldrive" : "internaldrive")
            .foregroundStyle(volume.isInternal == false ? .teal : .blue)
          Text(volume.path).font(.footnote).lineLimit(1).truncationMode(.middle)
          Spacer()
          if let error = volume.errorText {
            Text("读取失败：\(error)").font(.caption2).foregroundStyle(.orange)
          } else {
            Text("\(bytes(volume.usedBytes)) / \(bytes(volume.totalBytes))（\(String(format: "%.1f", volume.capacityPercent ?? 0))%）")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  /// 三色分类表：迁移候选 / 保留本机 / 待复查。
  private func categoryTable(_ report: StorageAuditReport) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("候选分类").font(.subheadline.weight(.semibold))
      categoryRows(title: "迁移候选（冷数据）", systemImage: "arrow.up.right.box", color: .orange,
                   entries: report.scopes.filter { $0.category == .migrate })
      categoryRows(title: "保留本机（活跃/运行状态）", systemImage: "macwindow", color: .blue,
                   entries: report.scopes.filter { $0.category == .keepLocal })
      categoryRows(title: "待复查（归属/一致性待人工核实）", systemImage: "questionmark.folder", color: .yellow,
                   entries: report.scopes.filter { $0.category == .review })
    }
  }

  @ViewBuilder
  private func categoryRows(title: String, systemImage: String, color: Color, entries: [StorageAuditReport.AuditEntry]) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Label("\(title)：\(entries.count) 项", systemImage: systemImage).font(.footnote).foregroundStyle(color)
      ForEach(entries, id: \.path) { entry in
        HStack {
          Text("· " + (entry.scope ?? entry.path)).font(.footnote).lineLimit(1).truncationMode(.middle)
          Spacer()
          if entry.sparseCandidate == true { Text("疑似稀疏").font(.caption2).foregroundStyle(.purple) }
          Text(bytes(entry.actualBytes)).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.leading, 16)
      }
    }
  }

  private func bytes(_ value: Int?) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value ?? 0), countStyle: .file)
  }
}

// MARK: - 内存体检卡片

@MainActor
@Observable
private final class MemoryCheckupModel {
  var isRunning = false
  var summary: MemoryRoundSummary?
  var actionInFlight = false

  private let machine: MemoryActionMachine

  init(machine: MemoryActionMachine = MemoryActionMachine(executor: MemoryCheckRunner())) { self.machine = machine }

  func run() {
    guard !isRunning else { return }
    isRunning = true
    // 用户手动触发的一次性体检；运行在 Task.detached(.utility)，UI 只订阅结果。
    Task.detached(priority: .utility) {
      let summary = await self.machine.handle(.beginInspection)
      await MainActor.run { self.summary = summary; self.isRunning = false }
    }
  }

  func terminate(candidateID: String) {
    guard !actionInFlight else { return }
    actionInFlight = true
    Task.detached(priority: .utility) {
      let summary = await self.machine.handle(.terminate(candidateID))
      await MainActor.run { self.summary = summary; self.actionInFlight = false }
    }
  }

  func approveCalibration() {
    guard !actionInFlight else { return }
    actionInFlight = true
    Task.detached(priority: .utility) {
      let summary = await self.machine.handle(.approveCalibration)
      await MainActor.run { self.summary = summary; self.actionInFlight = false }
    }
  }
}

private struct MemoryCheckupCard: View {
  @State private var model = MemoryCheckupModel()
  @State private var pendingCandidate: MemoryCandidate?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if let summary = model.summary { summaryBody(summary) }
      Button {
        model.run()
      } label: {
        if model.isRunning { ProgressView().controlSize(.small) }
        Text(model.isRunning ? "体检中…（约 15 秒）" : "运行内存体检")
      }
      .disabled(model.isRunning || model.actionInFlight)
    }
    .padding(14)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .confirmationDialog(terminateDialogTitle, isPresented: Binding(
      get: { pendingCandidate != nil }, set: { if !$0 { pendingCandidate = nil } })) {
      Button("确认终止（受控单发，SIGTERM，仅此进程）", role: .destructive) {
        if let candidate = pendingCandidate {
          pendingCandidate = nil
          model.terminate(candidateID: candidate.id)
        }
      }
      Button("取消", role: .cancel) { pendingCandidate = nil }
    } message: {
      terminateDialogMessage
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "memorychip").foregroundStyle(.purple)
      Text("内存体检").font(.headline)
      Spacer()
      Text("mac-memory-guardian · 45 秒预算 · fail-closed")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var terminateDialogTitle: String {
    if let c = pendingCandidate { return "确认终止绿色 Codex 候选 \(c.id)？" }
    return "确认终止？"
  }

  private var terminateDialogMessage: Text {
    guard let c = pendingCandidate else { return Text("确认终止？") }
    let rss = c.rssBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "未知"
    // 确认对话框引用协议事实：候选 ID、RSS、原因
    return Text("候选 ID：\(c.id)\nRSS：\(rss)\n原因：\(c.reasons.joined(separator: "、"))\n\n确认后将按协议重新体检取最新证据，再执行至多一次 terminate-codex（SIGTERM，仅该根进程）。该计划随即作废。")
  }

  @ViewBuilder
  private func summaryBody(_ summary: MemoryRoundSummary) -> some View {
    HStack(spacing: 8) {
      if let pressure = summary.inspection?.pressure {
        pressureBadge(pressure)
      }
      stateBadge(summary.state)
      if let remaining = summary.budgetRemainingSeconds {
        Text(String(format: "剩余预算 %.1fs", remaining)).font(.caption).foregroundStyle(.secondary)
      }
    }
    if summary.state == .calibrationPending {
      calibrationBanner(summary)
    }
    if summary.state == .approved {
      Label("已批准校准，本轮不做任何清理。后续清理需重新体检且校准状态为否。", systemImage: "checkmark.seal")
        .font(.callout).foregroundStyle(.blue)
    }
    if let note = summary.note {
      Text(note).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    if let inspection = summary.inspection {
      candidateList(summary, inspection: inspection)
    }
    if !summary.skipped.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        Text("已跳过").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(summary.skipped, id: \.self) { Text("· " + $0).font(.caption2).foregroundStyle(.secondary) }
      }
    }
    if let outcome = summary.terminateOutcome {
      Label("terminate-codex 终态：\(outcome.status)（recovery：\(outcome.recoveryStatus ?? "未知")）",
            systemImage: outcome.isCleanExit ? "checkmark.circle" : "exclamationmark.triangle")
        .font(.footnote).foregroundStyle(outcome.isCleanExit ? .green : .orange)
    }
  }

  private func pressureBadge(_ pressure: MemoryPressure) -> some View {
    HStack(spacing: 4) {
      Circle().fill(pressure.pressured ? Color.red : Color.green).frame(width: 8, height: 8)
      Text(pressure.pressured ? "内存压力（\(pressure.reasons.joined(separator: "、"))）" : "压力正常")
        .font(.footnote.weight(.semibold))
    }
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background((pressure.pressured ? Color.red : Color.green).opacity(0.12), in: Capsule())
  }

  private func stateBadge(_ state: MemoryActionState) -> some View {
    Text(stateLabel(state)).font(.caption)
      .padding(.horizontal, 8).padding(.vertical, 3)
      .background(Color.gray.opacity(0.14), in: Capsule())
  }

  private func stateLabel(_ state: MemoryActionState) -> String {
    switch state {
    case .idle: return "未体检"
    case .inspected: return "已体检"
    case .calibrationPending: return "校准模式（would do）"
    case .approved: return "已批准校准"
    case .acting: return "执行动作中"
    case .reporting: return "已报告"
    case .failed: return "已停止（fail-closed）"
    }
  }

  private func calibrationBanner(_ summary: MemoryRoundSummary) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("当前策略版本处于校准模式：以下全部为 would do，未执行任何清理。", systemImage: "eye")
        .font(.footnote).foregroundStyle(.orange)
      Button {
        model.approveCalibration()
      } label: {
        Text("批准校准（需确认；批准后本轮不做任何清理）")
      }
      .disabled(model.actionInFlight)
    }
  }

  private func candidateList(_ summary: MemoryRoundSummary, inspection: MemoryInspection) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("候选（\(inspection.candidates.count)）").font(.subheadline.weight(.semibold))
      ForEach(inspection.candidates) { candidate in
        candidateRow(candidate, summary: summary)
      }
      if inspection.candidates.isEmpty {
        Text("无候选").font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private func candidateRow(_ candidate: MemoryCandidate, summary: MemoryRoundSummary) -> some View {
    let disposition = summary.proposals.first { $0.id == candidate.id }?.disposition
    return HStack(spacing: 8) {
      tierDot(candidate.tier)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(candidate.appName ?? candidate.id).font(.footnote.weight(.medium)).lineLimit(1).truncationMode(.middle)
          Text(candidate.kind == .codex ? "Codex" : "应用").font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.gray.opacity(0.15), in: Capsule())
        }
        Text("\(candidate.id) · \(candidate.reasons.joined(separator: "、"))")
          .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
      }
      Spacer()
      Text(candidate.rssBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—")
        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
      actionControl(candidate, disposition: disposition, summary: summary)
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private func actionControl(_ candidate: MemoryCandidate, disposition: ProposalDisposition?, summary: MemoryRoundSummary) -> some View {
    switch disposition {
    case .actionable:
      Button("终止（受控）") { pendingCandidate = candidate }
        .controlSize(.small)
        .disabled(model.actionInFlight || summary.state != .inspected)
        .help("确认后按协议单发 terminate-codex；该计划随即作废")
    case .needsUser:
      Text("建议手动退出").font(.caption).foregroundStyle(.orange)
        .help("黄色候选无自动路径：请自行退出并先处理未保存内容")
    case .wouldDo:
      Text("would do").font(.caption).foregroundStyle(.orange)
    default:
      EmptyView()
    }
  }

  private func tierDot(_ tier: MemoryCandidate.Tier) -> some View {
    Circle().fill(tierColor(tier)).frame(width: 8, height: 8)
      .help("tier：\(tier.rawValue)")
  }

  private func tierColor(_ tier: MemoryCandidate.Tier) -> Color {
    switch tier {
    case .green: return .green
    case .yellow: return .yellow
    case .red: return .red
    case .unsupported, .unknown: return .gray
    }
  }
}
