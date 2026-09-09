import AppKit
import SwiftUI

enum MenuBarIcon {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "MenuBarIconTemplate", withExtension: "pdf"),
           let loaded = NSImage(contentsOf: url)
        {
            let image = loaded.copy() as? NSImage ?? loaded
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(
            systemSymbolName: "doc.text.viewfinder",
            accessibilityDescription: "GlobalTrans"
        ) ?? NSImage()
    }()
}

struct MenuBarStatusLabel: View {
    var body: some View {
        Image(nsImage: MenuBarIcon.image)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .accessibilityLabel("GlobalTrans")
    }
}
