import AppKit

@MainActor
enum StatusItemContextMenu {
    private static var monitor: Any?
    private static let controller = StatusItemMenuController()

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            let isContextClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isContextClick, let window = event.window, isStatusBarWindow(window) else {
                return event
            }
            let button = statusBarButton(from: event) ?? findStatusBarButton(in: window)
            if let button {
                showMenu(from: button, event: event)
            } else {
                showMenu(at: NSEvent.mouseLocation)
            }
            return nil
        }
    }

    static func presentMainPanel() {
        let panelVisible = NSApp.windows.contains {
            $0.isVisible && $0.identifier?.rawValue == StatusPanelHider.panelWindowID
        }
        guard !panelVisible, let button = findStatusBarButton() else { return }
        button.performClick(nil)
    }

    private static func showMenu(from button: NSStatusBarButton, event: NSEvent) {
        let menu = controller.makeMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    private static func showMenu(at screenPoint: NSPoint) {
        let menu = controller.makeMenu()
        menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    private static func statusBarButton(from event: NSEvent) -> NSStatusBarButton? {
        guard let window = event.window, isStatusBarWindow(window) else { return nil }
        var view: NSView? = window.contentView?.hitTest(event.locationInWindow) ?? window.contentView
        while let current = view {
            if let button = current as? NSStatusBarButton {
                return button
            }
            view = current.superview
        }
        return findStatusBarButton(in: window)
    }

    private static func findStatusBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows where isStatusBarWindow(window) {
            if let button = findStatusBarButton(in: window) {
                return button
            }
        }
        return nil
    }

    private static func findStatusBarButton(in window: NSWindow) -> NSStatusBarButton? {
        if let button = window.contentView as? NSStatusBarButton {
            return button
        }
        return firstStatusBarButton(in: window.contentView)
    }

    private static func firstStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let button = firstStatusBarButton(in: subview) {
                return button
            }
        }
        return nil
    }

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        let name = window.className
        if name.contains("NSStatusBarWindow") || name.contains("StatusItem") {
            return true
        }
        let screenTop = window.screen?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        return window.frame.height <= 48
            && window.frame.width <= 120
            && window.frame.maxY >= screenTop - 12
    }
}

@MainActor
private final class StatusItemMenuController: NSObject, NSMenuItemValidation {
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = true

        let capture = NSMenuItem(
            title: "截图翻译",
            action: #selector(captureScreenshot),
            keyEquivalent: ""
        )
        capture.target = self
        menu.addItem(capture)

        let unload = NSMenuItem(
            title: "卸载所有模型",
            action: #selector(unloadModels),
            keyEquivalent: ""
        )
        unload.target = self
        menu.addItem(unload)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出应用",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let model = AppModel.shared
        switch menuItem.action {
        case #selector(captureScreenshot):
            return model.canAddCapture
        case #selector(unloadModels):
            return model.modelLoaded && !model.isBusy
        default:
            return true
        }
    }

    @objc func captureScreenshot() {
        Task { @MainActor in
            await AppModel.shared.captureRegion()
        }
    }

    @objc func unloadModels() {
        Task { @MainActor in
            await AppModel.shared.unloadNow()
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
