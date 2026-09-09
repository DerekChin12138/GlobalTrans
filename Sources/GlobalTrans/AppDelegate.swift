import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HotKey.register {
            Task { @MainActor in
                await AppModel.shared.captureRegion()
            }
        }
        StatusItemContextMenu.install()
        presentPanelWhenReady(attempts: 12)
    }

    private func presentPanelWhenReady(attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            StatusItemContextMenu.presentMainPanel()
            let panelVisible = NSApp.windows.contains {
                $0.isVisible && $0.identifier?.rawValue == StatusPanelHider.panelWindowID
            }
            if !panelVisible, attempts > 1 {
                self.presentPanelWhenReady(attempts: attempts - 1)
            }
        }
    }
}
