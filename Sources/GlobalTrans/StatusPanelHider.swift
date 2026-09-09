import AppKit

@MainActor
enum StatusPanelHider {
    private static var hidden: [NSWindow] = []

    static func hide() async {
        hidden = NSApp.windows.filter { window in
            window.isVisible && window.level != .screenSaver
        }
        for window in hidden {
            window.orderOut(nil)
        }
        try? await Task.sleep(for: .milliseconds(180))
    }

    static func restore() {
        for window in hidden {
            window.orderFrontRegardless()
        }
        hidden.removeAll()
        NSApp.activate(ignoringOtherApps: true)
    }
}
