import SwiftUI
import PerformanceDomain

enum MetricText {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }
    static func value<T>(_ metric: Metric<T>?, now: Date, threshold: TimeInterval, format: (T) -> String) -> String {
        guard let metric else { return "正在采样" }
        guard let value = metric.value else {
            if let old = metric.lastKnownValue {
                let age = metric.lastKnownAt.map { now.timeIntervalSince($0) }
                let stale = age.map { $0 < 0 || $0 > threshold } ?? true
                return format(old) + (stale ? " · 上次测量，已过期" : " · 上次测量")
            }
            switch metric.quality {
            case .warmingUp: return "正在采样"
            case .permissionDenied: return "访问受限"
            case .unsupported: return "暂不支持"
            case .unknown: return "未取得"
            case .failed: return "读取失败"
            case .measured: return "未取得"
            }
        }
        return format(value) + (metric.isStale(at: now, after: threshold) ? " · 已过期" : "")
    }
    static func time(_ date: Date?) -> String {
        guard let date else { return "等待有效样本" }
        return "测量于 " + date.formatted(date: .omitted, time: .standard)
    }
}

struct OverviewCard: View {
    let title: String
    let icon: String
    let value: String
    let detail: String
    let action: String
    let identifier: String
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) { cardContent }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(accessibilityDescription)
    }
    private var accessibilityDescription: String {
        [title, value, detail, action].joined(separator: "，")
    }
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.headline)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit().accessibilityIdentifier(identifier + ".value")
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(action).font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
            }
            .frame(minHeight: 130)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
    }
}

public struct OverviewPanel: View {
    private let controller: PerformanceController
    private let onQuit: () -> Void
    public init(controller: PerformanceController, onQuit: @escaping () -> Void) {
        self.controller = controller; self.onQuit = onQuit
    }
    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView { content(now: Date()) }
        }
        .frame(width: 400, height: 500)
    }

    private func content(now: Date) -> some View {
        let s = controller.snapshot.system
        let volume = controller.snapshot.volume
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("系统概览").font(.title2.bold())
                Text(Host.current().localizedName ?? "我的 Mac").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                OverviewCard(title: "CPU", icon: "cpu", value: MetricText.value(s?.cpuPercent, now: now, threshold: controller.freshnessSeconds) { String(format: "%.1f%%", $0) },
                             detail: "系统整体使用率\n" + MetricText.time(s?.cpuPercent.sampledAt ?? s?.cpuPercent.lastKnownAt) + (s?.cpuPercent.value == nil ? "\n" + (s?.cpuPercent.reason ?? "正在采样") : ""), action: "查看进程", identifier: "overview.cpu") { controller.open(.performance) }
                OverviewCard(title: "内存", icon: "memorychip", value: MetricText.value(s?.memoryUsedBytes, now: now, threshold: controller.freshnessSeconds, format: MetricText.bytes),
                             detail: "总量 " + MetricText.value(s?.memoryTotalBytes, now: now, threshold: controller.freshnessSeconds, format: MetricText.bytes) + "\n活跃 + 固定 + 压缩\n压力等级未取得", action: "查看内存占用", identifier: "overview.memory") { controller.open(.performance) }
                OverviewCard(title: "启动盘", icon: "internaldrive", value: MetricText.value(volume?.availableBytes, now: now, threshold: 30, format: MetricText.bytes),
                             detail: "当前可用空间\n" + MetricText.time(volume?.availableBytes.sampledAt ?? volume?.availableBytes.lastKnownAt) + (volume?.availableBytes.value == nil ? "\n" + (volume?.availableBytes.reason ?? "正在采样") : ""), action: "查看存储", identifier: "overview.storage") { controller.open(.storage) }
                OverviewCard(title: "存储任务", icon: "chart.pie", value: controller.storage.title,
                             detail: controller.storage.detail + (controller.storage.incomplete ? "\n覆盖不完整" : ""),
                             action: "查看任务", identifier: "overview.task") { controller.open(.storage) }
            }
            Divider()
            HStack {
                Button("打开主窗口") { controller.open(.storage) }.accessibilityIdentifier("overview.open")
                Spacer()
                Button("设置", systemImage: "gearshape") { controller.open(.settings) }.labelStyle(.iconOnly).help("设置")
                Button("退出", action: onQuit).accessibilityIdentifier("overview.quit")
            }
        }.padding(20)
    }
}
