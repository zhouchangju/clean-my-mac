import SwiftUI
import AppKit
import PerformanceUI
import PerformanceDomain
import PerformanceCore
import PerformanceMacPlatform

/// Developer-only isolated host: never opens the cleaner's database or bundle.
@main
struct PerformancePreview: App {
    @State private var controller = PerformanceController(sampler: PreviewSampler())
    var body: some Scene {
        WindowGroup(id: "performance-preview") {
            PreviewRoot(controller: controller)
                .frame(minWidth: 950, minHeight: 650)
        }
    }
}

private struct PreviewRoot: View {
    let controller: PerformanceController
    @Environment(\.openWindow) private var openWindow
    @State private var settings = false
    @State private var menu: OverviewMenuController?
    var body: some View {
        PerformanceDetail(controller: controller)
            .toolbar {
                Button("系统概览") { menu?.toggle() }.accessibilityIdentifier("preview.overview")
                Button("概览设置") { settings = true }
            }
            .sheet(isPresented: $settings) {
                VStack {
                    PerformanceSettings(controller: controller)
                    Button("完成") { settings = false }.padding()
                }.frame(width: 560, height: 380)
            }
            .onAppear {
                if menu == nil {
                    menu = OverviewMenuController(controller: controller) {
                        menu?.shutdown()
                        Task { await controller.shutdown(); NSApp.terminate(nil) }
                    }
                }
                controller.navigate = { route in
                    openWindow(id: "performance-preview")
                    NSApp.activate(ignoringOtherApps: true)
                    settings = route == .settings
                    menu?.close()
                }
            }
            .onChange(of: controller.menuEnabled) { menu?.setEnabled(controller.menuEnabled) }
            .onChange(of: controller.snapshot.sequence) {
                if ProcessInfo.processInfo.arguments.contains("--trace") {
                    print("sessionCPU=\(String(describing: controller.snapshot.system?.cpuPercent.value))")
                    fflush(stdout)
                }
            }
    }
}

private actor PreviewSampler: PerformanceSampler {
    let base = MacPerformanceSampler()
    private var independent = CPUCalculator()
    func readSystem() async -> RawSystemSample {
        let raw = await base.readSystem()
        if ProcessInfo.processInfo.arguments.contains("--trace") {
            let value = independent.consume(raw.ticks)
            print("rawCPU=\(String(describing: raw.ticks.value)); referenceCPU=\(String(describing: value.value))")
            fflush(stdout)
        }
        return raw
    }
    func readProcesses() async -> RawProcessSample { await base.readProcesses() }
    func readStartupVolume() async -> VolumeSnapshot { await base.readStartupVolume() }
}
