import SwiftUI
import AppKit
import Observation
import CleanerDomain
import PerformanceUI

/// The application owns storage once, independent of either window's lifetime.
@MainActor @Observable
final class UtilityApplication {
    static let shared = UtilityApplication()
    let storage = CleanerModel()
    let performance = PerformanceController()
    private var menu: OverviewMenuController?
    private var observing = true
    private var observationGeneration: UInt64 = 0
    private var diagnosticsTask: Task<Void, Never>?
    private(set) var quitting = false

    private init() { observeStorage() }

    func install(openWindow: @escaping @MainActor () -> Void) {
        storage.prepareIndex() // Idempotent; preparation belongs to the App, not a selected page.
        startFixtureDiagnosticsIfRequested()
        if menu == nil {
            menu = OverviewMenuController(controller: performance) { NSApp.terminate(nil) }
        }
        performance.navigate = { [weak self] route in
            guard let self else { return }
            self.performance.route = route
            openWindow()
            NSApp.activate(ignoringOtherApps: true)
            self.menu?.close()
        }
    }

    func updateMenu() { menu?.setEnabled(performance.menuEnabled) }
    func toggleOverview() { menu?.toggle() }

    private func startFixtureDiagnosticsIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard diagnosticsTask == nil, args.contains("-lmcUITest"), args.contains("-lmcPerformanceDiagnostics") else { return }
        let directory = URL(fileURLWithPath: storage.storagePath, isDirectory: true)
        guard directory.lastPathComponent.hasPrefix("LMC-UI-") else { return }
        let output = directory.appendingPathComponent("performance-diagnostics.jsonl")
        if !FileManager.default.fileExists(atPath: output.path) {
            guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return }
        }
        guard let handle = try? FileHandle(forWritingTo: output), (try? handle.seekToEnd()) != nil else { return }
        diagnosticsTask = Task { @MainActor [weak self] in
            defer { try? handle.close() }
            while !Task.isCancelled {
                guard let self, !self.quitting else { break }
                let current = await self.performance.session.snapshot()
                let subscribers = await self.performance.session.subscriberCount
                let record: [String: Any] = [
                    "timestamp": Date().timeIntervalSince1970,
                    "pid": ProcessInfo.processInfo.processIdentifier,
                    "sequence": current.sequence,
                    "subscribers": subscribers,
                    "visibleMainWindows": NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.isVisible && !$0.isMiniaturized }.count,
                    "scanning": self.storage.scanning,
                    "preparingIndex": self.storage.preparingIndex,
                    "processSampleCount": current.processes.count,
                    "route": self.performance.route.rawValue
                ]
                if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
                    try? handle.write(contentsOf: data + Data([10]))
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    private func observeStorage() {
        guard observing else { return }
        observationGeneration &+= 1
        let generation = observationGeneration
        withObservationTracking {
            performance.storage = Self.summary(storage)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observing, self.observationGeneration == generation else { return }
                self.observeStorage()
            }
        }
    }

    static func summary(_ storage: CleanerModel) -> StorageOverview {
        if storage.preparingIndex {
            return .init(title: "正在准备索引", detail: "准备本地分析索引；尚未开始扫描你的文件")
        }
        if let error = storage.indexPreparationError {
            return .init(title: "索引准备失败", detail: error, incomplete: true)
        }
        guard let run = storage.run else {
            return .init(title: storage.scanning ? "准备扫描" : "本次启动尚未扫描",
                         detail: storage.maintenanceNotice ?? "从主窗口选择范围并扫描")
        }
        let title: String
        if storage.cancelling { title = "正在停止" }
        else if storage.scanning { title = "正在扫描" }
        else {
            switch run.state {
            case .completed: title = "扫描已完成"
            case .partial: title = "部分扫描结果"
            case .cancelled: title = "扫描已停止"
            case .failed: title = "扫描失败"
            case .preparing: title = "准备扫描"
            case .running: title = "正在扫描"
            case .idle: title = "尚未扫描"
            }
        }
        var details = ["\(run.processedCount) 项 · \(run.issueCount) 处读取缺口"]
        if let summary = storage.summary {
            if storage.noSuccessfulMeasurement { details.append("尚未成功计量") }
            else {
                details.append("已知占用 " + ByteCountFormatter.string(fromByteCount: Int64(clamping: summary.knownAllocatedBytes), countStyle: .file))
                details.append("\(summary.unknownCount) 项计量未知")
            }
        } else { details.append("计量结果尚未取得") }
        if let date = run.finishedAt { details.append("扫描于 " + date.formatted(date: .abbreviated, time: .shortened)) }
        if let reason = run.stopReason { details.append(reason) }
        return .init(title: title, detail: details.joined(separator: "\n"), measuredAt: run.finishedAt ?? run.startedAt,
                     incomplete: run.state != .completed || storage.summary == nil || run.issueCount > 0 || (storage.summary?.unknownCount ?? 0) > 0)
    }

    func terminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        diagnosticsTask?.cancel(); diagnosticsTask = nil
        observing = false
        observationGeneration &+= 1
        menu?.shutdown()
        if storage.scanning { storage.cancel() }
        Task { @MainActor in
            await performance.session.suspend()
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while (storage.scanning || storage.preparingIndex) && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if storage.scanning || storage.preparingIndex {
                quitting = false; observing = true
                observeStorage(); updateMenu()
                await performance.session.resume()
                storage.errorMessage = storage.preparingIndex
                    ? "本地索引仍在安全准备，退出已取消。请准备结束后再退出。"
                    : "扫描仍在停止，退出已取消。请等待任务停止后再退出。"
                performance.open(.storage)
                sender.reply(toApplicationShouldTerminate: false)
            } else {
                await performance.shutdown()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@MainActor
final class UtilityAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        UtilityApplication.shared.terminate(sender)
    }
}

struct UtilityRootView: View {
    private let application = UtilityApplication.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        @Bindable var performance = application.performance
        VStack(spacing: 0) {
            HStack {
                Picker("功能", selection: $performance.route) {
                    Text("存储分析").tag(UtilityRoute.storage)
                    Text("性能监控").tag(UtilityRoute.performance)
                    Text("应用设置").tag(UtilityRoute.settings)
                }.pickerStyle(.segmented).frame(width: 360).accessibilityIdentifier("utility.navigation")
                Spacer()
                Button("系统概览", systemImage: "waveform.path.ecg") { application.toggleOverview() }
                    .disabled(!performance.menuEnabled).accessibilityIdentifier("utility.overview")
            }.padding(12)
            Divider()
            switch performance.route {
            case .storage: CleanerView(model: application.storage)
            case .performance: PerformanceDetail(controller: performance)
            case .settings:
                VStack {
                    PerformanceSettings(controller: performance)
                    Button("打开存储设置") {
                        application.storage.page = .settings
                        application.storage.changePage()
                        performance.route = .storage
                    }.padding()
                }
            }
        }
        .onAppear { application.install { openWindow(id: "lmc-main") } }
        .onChange(of: performance.menuEnabled) { application.updateMenu() }
    }
}
