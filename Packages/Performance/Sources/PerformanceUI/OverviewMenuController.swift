import AppKit
import SwiftUI

/// AppKit owns visibility so closing the panel explicitly releases sampling,
/// independently of SwiftUI view retention or the app's activation state.
@MainActor
public final class OverviewMenuController: NSObject, NSPopoverDelegate {
    private let controller: PerformanceController
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let consumerID = UUID()
    private var observation: Task<Void, Never>?
    private let onQuit: @MainActor () -> Void

    public init(controller: PerformanceController, onQuit: @escaping @MainActor () -> Void) {
        self.controller = controller; self.onQuit = onQuit
        super.init()
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = false
        setEnabled(controller.menuEnabled)
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled, item == nil {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            status.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "系统概览")
            status.button?.image?.isTemplate = true
            status.button?.toolTip = "Local Mac Cleaner · 系统概览"
            status.button?.target = self
            status.button?.action = #selector(toggle)
            status.button?.setAccessibilityIdentifier("overview.statusItem")
            item = status
        } else if !enabled {
            close()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }

    @objc public func toggle() {
        if popover.isShown { close(); return }
        guard let button = item?.button else { return }
        // Create content only while visible; no retained TimelineView when hidden.
        popover.contentViewController = NSHostingController(rootView: OverviewPanel(controller: controller, onQuit: onQuit))
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    public func close() {
        popover.performClose(nil)
        stopObservation()
    }

    public func popoverDidShow(_ notification: Notification) {
        guard observation == nil else { return }
        observation = Task { [controller, consumerID] in
            await controller.observe(consumerID: consumerID, demand: .overview)
        }
    }

    public func popoverDidClose(_ notification: Notification) { stopObservation() }
    private func stopObservation() {
        observation?.cancel()
        observation = nil
        popover.contentViewController = nil
    }

    public func shutdown() {
        close()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }
}
