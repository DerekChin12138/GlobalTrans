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
        presentPanelWhenReady(attempts: 16, alreadyClicked: false)
    }

    /// Click the status item at most once. Retrying `performClick` toggles the
    /// MenuBarExtra closed again and looks like the panel is flashing.
    private func presentPanelWhenReady(attempts: Int, alreadyClicked: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if StatusItemContextMenu.isPanelVisible() { return }
            if alreadyClicked { return }
            let clicked = StatusItemContextMenu.presentMainPanel()
            if !StatusItemContextMenu.isPanelVisible(), attempts > 1 {
                self.presentPanelWhenReady(
                    attempts: attempts - 1,
                    alreadyClicked: clicked
                )
            }
        }
    }
}
