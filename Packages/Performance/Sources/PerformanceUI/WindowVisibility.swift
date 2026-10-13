import AppKit
import SwiftUI

/// A retained SwiftUI window view may not disappear when its window is closed.
/// Native window events therefore govern the detail consumer explicitly.
struct WindowVisibility: NSViewRepresentable {
    let changed: @MainActor (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { VisibilityView(changed: changed) }
    func updateNSView(_ view: VisibilityView, context: Context) {}
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.detach() }

    @MainActor final class VisibilityView: NSView {
        let changed: @MainActor (Bool) -> Void
        private var tokens: [NSObjectProtocol] = []
        init(changed: @escaping @MainActor (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didChangeOcclusionStateNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.reportVisibility()
                    }
                })
            }
            for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.changed(false) }
                })
            }
            for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.reportVisibility() }
                })
            }
            Task { @MainActor [weak self] in self?.reportVisibility() }
        }
        private func reportVisibility() {
            changed(window?.isVisible == true && window?.isMiniaturized == false && !NSApp.isHidden)
        }
        func detach() {
            for token in tokens { NotificationCenter.default.removeObserver(token) }
            tokens.removeAll()
        }
    }
}
