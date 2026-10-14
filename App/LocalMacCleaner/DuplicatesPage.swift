import SwiftUI
import AppKit
import CleanerExtras

/// 重复文件分析页：三段漏斗（尺寸分桶→头部哈希→全量哈希）只读扫描 + 按浪费字节排序的分组结果 + JSON 导出。
/// 只读红线：本页没有任何删除/移动入口，也不把结果写入计划；清理能力待受控执行开放后另行提供。
struct DuplicatesPage: View {
    @Bindable var model: CleanerModel
    @State private var dup = DuplicatesModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if dup.isScanning { progressSection }
            if let report = dup.report { resultsSection(report) }
            else if !dup.isScanning {
                ContentUnavailableView("尚未扫描", systemImage: "doc.on.doc", description: Text("选择目录后点击“开始扫描”。默认只比较 ≥ 所选阈值的普通文件；符号链接与 .git/.svn 内容不参与判重。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding()
        .onAppear { dup.adoptDefaultRoot(model.scope?.rootPath) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("扫描目录").font(.headline)
                Text(dup.rootPath).font(.callout).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(dup.rootPath)
                Button("选择目录…") { dup.chooseRoot() }.disabled(dup.isScanning)
                Spacer()
                Picker("最小文件", selection: $dup.minBytes) {
                    Text("1 MiB").tag(UInt64(1) << 20); Text("16 MiB").tag(UInt64(16) << 20); Text("128 MiB").tag(UInt64(128) << 20)
                }.frame(width: 170).disabled(dup.isScanning)
                if dup.isScanning { Button("取消", role: .cancel) { dup.cancel() } }
                else { Button("开始扫描") { dup.start() }.buttonStyle(.borderedProminent) }
                Button("导出 JSON") { dup.exportJSON() }.disabled(dup.report == nil || dup.isScanning).help("以 0600 权限写入桌面（不可写时退回临时目录）")
            }
            if let message = dup.message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = dup.lastProgress {
                if let total = p.phaseTotalBytes, total > 0 {
                    ProgressView(value: min(Double(p.scannedBytes) / Double(total), 1))
                } else { ProgressView() .progressViewStyle(.linear) }
                HStack(spacing: 12) {
                    Text(DuplicatesModel.phaseTitle(p.phase)).font(.callout).bold()
                    Text("已处理 \(DuplicatesModel.bytes(p.scannedBytes))" + (p.phaseTotalBytes.map { " / \(DuplicatesModel.bytes($0))" } ?? "")).monospacedDigit()
                    if p.completedGroups > 0 { Text("已确认 \(p.completedGroups) 组").foregroundStyle(.secondary) }
                }.font(.callout)
                Text(p.currentPath ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                ProgressView().progressViewStyle(.linear)
                Text("正在启动扫描…").font(.callout)
            }
        }
    }

    private func resultsSection(_ report: DuplicateReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("共 \(report.groups.count) 组重复").font(.headline)
                Text("名义浪费 \(DuplicatesModel.bytes(report.wastedBytesTotal))").monospacedDigit()
                Text("· 扫描 \(report.scannedFiles) 个文件（\(DuplicatesModel.bytes(report.scannedBytes))）").foregroundStyle(.secondary)
                if report.incomplete { Label("部分结果", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).help("扫描被取消或根不可读，结果不完整") }
                if !report.skipped.isEmpty { Text("· \(report.skipped.count) 项未读取").foregroundStyle(.secondary) }
            }.font(.callout)
            if report.groups.contains(where: \.hardLinked) {
                Text("标有“硬链接组”的分组内含同一文件系统对象的多条路径，删除其中之一不会释放空间。").font(.caption).foregroundStyle(.orange)
            }
            List {
                ForEach(Array(report.groups.enumerated()), id: \.offset) { _, group in
                    DisclosureGroup {
                        ForEach(group.files, id: \.path) { file in fileRow(file) }
                    } label: { groupLabel(group) }
                }
                if !report.skipped.isEmpty {
                    DisclosureGroup("未读取 \(report.skipped.count) 项（权限或枚举失败；这些文件从不参与判重）") {
                        ForEach(report.skipped, id: \.path) { item in
                            HStack {
                                Text(item.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                Spacer()
                                Text(item.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 240)
        }
    }

    private func groupLabel(_ group: DuplicateGroup) -> some View {
        HStack(spacing: 8) {
            Text(DuplicatesModel.bytes(group.wastedBytes)).monospacedDigit().bold().frame(minWidth: 90, alignment: .leading)
            Text("\(group.files.count) 个文件 · 单个 \(DuplicatesModel.bytes(group.size))").foregroundStyle(.secondary)
            if group.hardLinked {
                Label("硬链接组：\(group.distinctObjects) 个真实对象，删除其一不释放空间", systemImage: "link").font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Text(group.files.first?.path ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 360, alignment: .trailing)
        }
    }

    private func fileRow(_ file: DuplicateFile) -> some View {
        HStack(spacing: 8) {
            Text(file.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(file.path)
            if file.linkCount > 1 { Text("nlink=\(file.linkCount)").font(.caption2).foregroundStyle(.orange) }
            Spacer()
            Button("在 Finder 中显示") { DuplicatesModel.reveal(file.path) }.buttonStyle(.link).font(.caption)
        }
        .contextMenu { Button("在 Finder 中显示") { DuplicatesModel.reveal(file.path) } }
        .padding(.leading, 12)
    }

    private var footer: some View {
        HStack {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            Text("分析只读；清理能力将在受控执行开放后提供。本页不提供任何删除操作。").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// 页面状态：持有扫描任务与进度；重活由 DuplicateFinder 在 Task.detached(.utility) 上执行，这里只订阅结果。
@MainActor @Observable
final class DuplicatesModel {
    var rootPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    var minBytes: UInt64 = DuplicateFinder.defaultMinBytes
    var isScanning = false
    var lastProgress: DuplicateProgress?
    var report: DuplicateReport?
    var message: String?
    private var adoptedDefault = false
    private var cancelRequested = false
    private var scanTask: Task<DuplicateReport, Never>?
    private var pumpTask: Task<Void, Never>?

    /// 首次进入页面采用主扫描范围作为默认根；用户手动选择后不再被覆盖。
    func adoptDefaultRoot(_ scopeRoot: String?) {
        guard !adoptedDefault else { return }
        adoptedDefault = true
        if let scopeRoot, !scopeRoot.isEmpty { rootPath = scopeRoot }
    }

    func chooseRoot() {
        guard !isScanning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        panel.message = "选择重复文件分析目录。分析过程只读，不会修改其中任何文件。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootPath = url.path; report = nil; message = nil
    }

    func start() {
        guard !isScanning else { return }
        isScanning = true; cancelRequested = false; report = nil; message = nil; lastProgress = nil
        let finder = DuplicateFinder(config: .init(minBytes: minBytes))
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        Task { [weak self] in
            let (stream, task) = await finder.scanStreaming(root: root)
            guard let self else { task.cancel(); return }
            scanTask = task
            if cancelRequested { task.cancel() }
            pumpTask = Task { [weak self] in for await p in stream { self?.lastProgress = p } }
            let result = await task.value
            finish(result)
        }
    }

    func cancel() {
        cancelRequested = true
        scanTask?.cancel()
        message = "正在取消，等待当前文件处理结束…"
    }

    private func finish(_ result: DuplicateReport) {
        pumpTask?.cancel(); pumpTask = nil; scanTask = nil
        isScanning = false; lastProgress = nil; report = result
        message = result.incomplete ? "扫描未完整（已取消或根不可读），以下为已累计的部分结果。" : nil
    }

    /// 导出报告 JSON：带 0600 属性创建文件（桌面优先，不可写时退回临时目录）。64 位数值均为十进制字符串。
    func exportJSON() {
        guard let report, !isScanning else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { message = "导出失败：报告编码错误"; return }
        let name = "重复文件报告-\(Self.stamp.string(from: Date()))-\(UUID().uuidString.prefix(6)).json"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        for directory in [desktop, FileManager.default.temporaryDirectory].compactMap({ $0 }) {
            let url = directory.appendingPathComponent(name)
            // createFile 在创建时直接套用 0600 属性，避免“先写再 chmod”的可读窗口。
            if FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) {
                message = "已导出（权限 0600）：\(url.path)"; return
            }
        }
        message = "导出失败：桌面与临时目录均不可写"
    }

    static func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    nonisolated static func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file) }
    nonisolated static func phaseTitle(_ phase: DuplicateProgress.Phase) -> String {
        switch phase { case .enumerating: "枚举文件"; case .hashing: "头部哈希分桶"; case .hashConfirming: "全量哈希确认" }
    }
    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f }()
}
