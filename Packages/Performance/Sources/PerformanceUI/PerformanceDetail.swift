import SwiftUI
import PerformanceCore
import PerformanceDomain

public struct PerformanceDetail: View {
    private let controller: PerformanceController
    @State private var consumerID = UUID()
    @State private var search = ""
    @State private var sort: ProcessSort = .cpu
    @State private var visible = false
    public init(controller: PerformanceController) { self.controller = controller }

    private var freshnessDates: [Date] {
        let now = Date()
        let dates = controller.rankedProcesses(search: search, sort: sort).flatMap { row in
            FreshnessUpdates.dates(row.cpuPercent, now: now, threshold: controller.freshnessSeconds)
            + FreshnessUpdates.dates(row.residentBytes, now: now, threshold: controller.freshnessSeconds)
            + FreshnessUpdates.dates(row.footprintBytes, now: now, threshold: controller.freshnessSeconds)
        }
        return [now] + Array(Set(dates)).sorted()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("性能与进程").font(.largeTitle.bold())
                    Text("只读监控 · 进程 CPU 以单核 100% 计算，可超过 100%").foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(controller.snapshot.processes.count) 个进程").monospacedDigit()
            }
            HStack {
                TextField("搜索进程名称或 PID", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("performance.search")
                Picker("排序", selection: $sort) {
                    Text("CPU").tag(ProcessSort.cpu)
                    Text("驻留内存 RSS").tag(ProcessSort.resident)
                    Text("物理占用 Footprint").tag(ProcessSort.footprint)
                    Text("名称").tag(ProcessSort.name)
                }.frame(width: 250).accessibilityIdentifier("performance.sort")
            }
            if let issue = controller.snapshot.processIssue {
                Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            TimelineView(.explicit(freshnessDates)) { _ in
                let now = Date()
                VStack(spacing: 0) {
                    HStack {
                        Text("进程").frame(maxWidth: .infinity, alignment: .leading)
                        Text("CPU").frame(width: 110, alignment: .leading)
                        Text("驻留内存 RSS").frame(width: 160, alignment: .leading)
                        Text("物理占用 Footprint").frame(width: 180, alignment: .leading)
                    }.font(.caption.weight(.semibold)).padding(12)
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(controller.rankedProcesses(search: search, sort: sort)) { row in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(row.name).lineLimit(2)
                                        Text("PID \(row.pid)").font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text(MetricText.value(row.cpuPercent, now: now, threshold: controller.freshnessSeconds) { String(format: "%.1f%%", $0) }).frame(width: 110, alignment: .leading)
                                    Text(MetricText.value(row.residentBytes, now: now, threshold: controller.freshnessSeconds, format: MetricText.bytes)).frame(width: 160, alignment: .leading)
                                    Text(MetricText.value(row.footprintBytes, now: now, threshold: controller.freshnessSeconds, format: MetricText.bytes)).frame(width: 180, alignment: .leading)
                                }.monospacedDigit().padding(12)
                                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityElement(children: .combine)
                            }
                        }.padding(.vertical, 8)
                    }
                }.accessibilityIdentifier("performance.table")
            }
            if controller.snapshot.processes.isEmpty {
                Text(controller.snapshot.system == nil ? "正在建立采样基线…" : "当前没有可展示的进程样本").foregroundStyle(.secondary)
            }
            Text("默认展示搜索结果前 20 项。RSS 含共享驻留页；Footprint 为系统物理占用口径，缺失不会用虚拟内存替代。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .background(WindowVisibility { visible = $0 }.frame(width: 0, height: 0))
        .task(id: visible) {
            guard visible else { return }
            await controller.observe(consumerID: consumerID, demand: .detail)
        }
    }
}

public struct PerformanceSettings: View {
    @Bindable private var controller: PerformanceController
    public init(controller: PerformanceController) { self.controller = controller }
    public var body: some View {
        Form {
            Section("菜单栏概览") {
                Toggle("显示菜单栏入口", isOn: $controller.menuEnabled).accessibilityIdentifier("settings.overview.enabled")
                Text("关闭面板且性能页不可见时停止采样；不自动扫描存储。")
            }
            Section("性能监控") {
                Picker("刷新间隔", selection: $controller.intervalSeconds) {
                    Text("2 秒").tag(2.0); Text("5 秒").tag(5.0); Text("10 秒").tag(10.0)
                }
                Text("间隔设置立即生效。系统用量与压力是不同指标；首版不提供内存释放或进程退出。")
            }
        }.formStyle(.grouped).padding(24)
    }
}
