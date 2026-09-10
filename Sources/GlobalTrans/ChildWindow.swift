import AppKit
import SwiftUI

/// MenuBarExtra sits at status-bar level; child windows must be higher or they
/// open behind the panel and never take key focus.
enum ChildWindow {
    static let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    static func focus(_ window: NSWindow?) {
        guard let window, window.level != .screenSaver else { return }
        window.level = level
        window.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct FrontmostWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        private var didFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                didFocus = false
                return
            }
            guard !didFocus else { return }
            didFocus = true
            ChildWindow.focus(window)
        }
    }
}
