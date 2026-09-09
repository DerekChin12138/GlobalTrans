import AppKit
import SwiftUI

@main
struct GlobalTransApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(model: model)
        } label: {
            MenuBarStatusLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Models", id: "models") {
            ModelsSettingsView(model: AppModel.shared)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        WindowGroup("Preview", id: "preview", for: PreviewWindowID.self) { $kind in
            ResultPreviewWindow(kind: kind, model: AppModel.shared)
        } defaultValue: {
            .ocr
        }
        .windowResizability(.automatic)
        .defaultSize(width: 760, height: 640)
        .defaultLaunchBehavior(.suppressed)

        Window("Merge OCR", id: "ocr-merge") {
            OCRMergeWindow(model: AppModel.shared)
        }
        .windowResizability(.automatic)
        .defaultSize(width: 900, height: 640)
        .defaultLaunchBehavior(.suppressed)
    }
}
