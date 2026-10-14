import SwiftUI
import AppKit
import AIAdvisorCore

/// AI Runtime 中心区块：runtime 检测列表 + 默认设置 + AI 空间分析面板。
/// 公共契约（App 侧 AICenterPage 依赖）：`AIRuntimeSection(contextProvider:)`。
public struct AIRuntimeSection: View {
    @State private var model: AIRuntimeModel

    public init(contextProvider: (@Sendable () async -> String?)? = nil) {
        _model = State(initialValue: AIRuntimeModel(contextProvider: contextProvider))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            runtimeCard
            analysisCard
            Text("AI 输出仅为分析建议，本应用不会据此执行任何删除或修改。")
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        .task { await model.bootstrap() }
    }

    // MARK: - Runtime 卡片

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Runtime").font(.headline)
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
                Button("刷新") { Task { await model.refresh(force: true) } }
                    .disabled(model.loading)
            }
            ForEach(model.runtimes) { runtime in
                HStack(spacing: 8) {
                    Image(systemName: runtime.kind == .cliAgent ? "terminal" : "server.rack")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(runtime.displayName).fontWeight(.medium)
                            if runtime.id == model.defaultID { statusBadge("默认", tint: .blue) }
                            if runtime.isInstalled && runtime.canRunAnalysis { statusBadge("可分析", tint: .green) }
                            if runtime.isInstalled && !runtime.canRunAnalysis { statusBadge("已检测，分析适配待续", tint: .secondary) }
                            if !runtime.isInstalled { Text("未检测到").font(.caption).foregroundStyle(.tertiary) }
                        }
                        Text(runtime.executablePath ?? "—")
                            .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(runtime.version ?? "").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            if model.runtimes.contains(where: \.isInstalled) {
                Picker("默认 Runtime", selection: $model.defaultID) {
                    Text("未设置").tag(String?.none)
                    ForEach(model.runtimes.filter(\.isInstalled)) { runtime in
                        Text(runtime.displayName).tag(Optional(runtime.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
                .onChange(of: model.defaultID) { _, newValue in model.saveDefault(newValue) }
            }
        }
    }

    // MARK: - AI 空间分析卡片

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI 空间分析").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: contextIcon).foregroundStyle(contextTint)
                Text(contextStatusText).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if model.runtimes.contains(where: \.isInstalled) {
                    Picker("分析 Runtime", selection: $model.selectedID) {
                        ForEach(model.runtimes.filter(\.isInstalled)) { runtime in
                            Text(runtime.displayName).tag(Optional(runtime.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                }
            }
            if let hint = model.selectionHint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            HStack {
                switch model.analysis {
                case .running(let start):
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text("分析中… 已用时 \(Int(context.date.timeIntervalSince(start))) 秒")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button("取消") { model.cancel() }
                default:
                    Button("开始分析") { Task { await model.runAnalysis() } }
                        .disabled(!model.canRunAnalysis)
                }
                Spacer()
                if case .done(let result) = model.analysis { Text("耗时 \(String(format: "%.1f", result.duration)) 秒").font(.caption).foregroundStyle(.tertiary) }
            }
            if case .done(let result) = model.analysis {
                ScrollView {
                    MarkdownText(result.stdoutText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: 360)
                HStack {
                    Button("复制全文") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.stdoutText, forType: .string)
                    }
                    Spacer()
                }
            }
            if case .failed(let message) = model.analysis {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var contextIcon: String {
        switch model.contextAvailable { case .some(true): "checkmark.circle"; case .some(false): "exclamationmark.triangle"; default: "questionmark.circle" }
    }
    private var contextTint: Color {
        switch model.contextAvailable { case .some(true): .green; case .some(false): .orange; default: .secondary }
    }
    private var contextStatusText: String {
        switch (model.contextProvider == nil, model.contextAvailable) {
        case (true, _): "上下文提供器不可用（请从应用主界面使用 AI 分析）"
        case (_, .some(true)): "扫描上下文就绪"
        case (_, .some(false)): "尚无扫描结果，请先完成一次扫描"
        default: "正在检查扫描上下文…"
        }
    }
}

// MARK: - 视图模型

/// @MainActor 视图模型：runtime 加载（进入时一次 + 手动刷新）、默认 runtime 持久化、AI 分析执行与取消。
@MainActor @Observable
final class AIRuntimeModel {
    enum AnalysisPhase {
        case idle
        case running(start: Date)
        case done(AIAnalysisResult)
        case failed(String)
    }

    var runtimes: [AIRuntime] = []
    var loading = false
    var defaultID: String?
    var selectedID: String?
    var analysis: AnalysisPhase = .idle
    /// nil = 尚未检查；false = 上下文提供器返回空（未扫描）
    var contextAvailable: Bool?

    @ObservationIgnored let contextProvider: (@Sendable () async -> String?)?
    @ObservationIgnored private let detector: any RuntimeDetecting
    @ObservationIgnored private let runner: any AnalysisRunning
    @ObservationIgnored private var runTask: Task<Void, Never>?

    init(
        contextProvider: (@Sendable () async -> String?)?,
        detector: any RuntimeDetecting = RuntimeDetector(),
        runner: any AnalysisRunning = AIAnalysisRunner()
    ) {
        self.contextProvider = contextProvider
        self.detector = detector
        self.runner = runner
        self.defaultID = RuntimePreferences.readDefault()
    }

    /// 进入页面：刷新一次 + 检查上下文可用性。
    func bootstrap() async {
        guard runtimes.isEmpty else { return }
        await refresh(force: true)
    }

    func refresh(force: Bool) async {
        loading = true
        defer { loading = false }
        runtimes = await detector.detectAll(forceRefresh: force)
        if defaultID == nil || !runtimes.contains(where: { $0.id == defaultID && $0.isInstalled }) {
            defaultID = RuntimePreferences.readDefault() // 清理指向未安装 runtime 的偏好展示
        }
        if selectedID == nil || !runtimes.contains(where: { $0.id == selectedID && $0.isInstalled }) {
            selectedID = defaultID ?? runtimes.first(where: { $0.canRunAnalysis })?.id ?? runtimes.first(where: \.isInstalled)?.id
        }
        if contextAvailable == nil, let contextProvider {
            contextAvailable = await contextProvider() != nil
        }
    }

    /// 持久化默认 runtime（Picker 变更触发；nil = 清除）。
    func saveDefault(_ id: String?) {
        guard RuntimePreferences.writeDefault(id) else {
            analysis = .failed("无法设置默认 runtime：\(id ?? "") 不是受支持的 runtime")
            return
        }
        if let id, selectedID == nil { selectedID = id }
    }

    var canRunAnalysis: Bool {
        guard case .idle = analysis else { return false }
        guard contextAvailable == true, let id = selectedID else { return false }
        return runtimes.first { $0.id == id }?.canRunAnalysis == true
    }

    /// 选中 runtime 暂不可分析时的说明（nil = 无提示）。
    var selectionHint: String? {
        guard let id = selectedID, let runtime = runtimes.first(where: { $0.id == id }), runtime.isInstalled else { return nil }
        return runtime.canRunAnalysis ? nil : "\(runtime.displayName) 已检测到，分析适配待续（当前支持 Codex CLI 与 OpenCode）"
    }

    func runAnalysis() async {
        guard let id = selectedID else { return }
        analysis = .running(start: Date())
        runTask = Task { [runner] in
            do {
                guard let context = await contextProvider?() , !context.isEmpty else {
                    await MainActor.run { self.analysis = .failed("尚无扫描结果，请先完成一次扫描") }
                    return
                }
                let result = try await runner.run(
                    runtimeID: id, prompt: Self.analysisPrompt(context: context),
                    workDir: nil, timeout: AIAnalysisRunner.defaultTimeout)
                await MainActor.run { self.analysis = .done(result) }
            } catch is CancellationError {
                await MainActor.run { self.analysis = .failed("已取消分析") }
            } catch {
                await MainActor.run { self.analysis = .failed("\(error)") }
            }
        }
        await runTask?.value
    }

    func cancel() { runTask?.cancel() }

    /// 分析提示词：上下文由 App 侧脱敏生成，本模块不感知扫描细节。
    static func analysisPrompt(context: String) -> String {
        """
        你是 macOS 磁盘清理顾问。以下是本机磁盘扫描的脱敏摘要，请分析磁盘空间构成，\
        指出最值得清理的类别与目录，并按预计可回收空间排序给出安全的清理建议。\
        你只输出分析建议，不要执行任何操作。

        【扫描上下文】
        \(context)
        """
    }
}

// MARK: - 小组件

private func statusBadge(_ text: String, tint: Color) -> some View {
    Text(text).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
        .background(tint.opacity(0.15), in: Capsule()).foregroundStyle(tint)
}

/// 基础 Markdown 文本（保留换行；解析失败退回纯文本）。
struct MarkdownText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed).font(.callout)
        } else {
            Text(text).font(.callout)
        }
    }
}
