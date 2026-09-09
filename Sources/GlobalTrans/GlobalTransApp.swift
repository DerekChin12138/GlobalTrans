import AppKit
import GlobalTransCore
import SwiftUI

@main
struct GlobalTransApp: App {
    @State private var model = AppModel.shared

    init() {
        MLXRuntime.configure()
        NSApplication.shared.setActivationPolicy(.accessory)
        HotKey.register {
            Task { @MainActor in
                await AppModel.shared.captureRegion()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("GlobalTrans", systemImage: "doc.text.viewfinder") {
            StatusPanel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Models", id: "models") {
            ModelsSettingsView(model: AppModel.shared)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
