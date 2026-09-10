import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenGrabError: LocalizedError {
    case noDisplay
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display is available for capture."
        case .captureFailed:
            return "Screen capture failed. Grant Screen Recording permission in System Settings."
        }
    }
}

enum ScreenGrabber {
    static func captureItem(rectInScreen: CGRect) async throws -> CaptureItem {
        var surface: CGImage? = try await capture(rectInScreen: rectInScreen)
        let item = autoreleasepool { () -> CaptureItem in
            let captured = surface!
            surface = nil
            return CaptureItem.make(cgImage: captured, kind: .screen)
        }
        return item
    }

    static func capture(rectInScreen: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let nsScreen = NSScreen.screens.first(where: { $0.frame.intersects(rectInScreen) }) ?? NSScreen.main else {
            throw ScreenGrabError.noDisplay
        }
        let displayID = (nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw ScreenGrabError.noDisplay
        }

        let local = nsScreen.convertToCGDisplayRect(rectInScreen)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = nsScreen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = max(Int((local.width * scale).rounded()), 2)
        config.height = max(Int((local.height * scale).rounded()), 2)
        config.showsCursor = false
        config.captureResolution = .best

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            throw ScreenGrabError.captureFailed
        }
    }
}

private extension NSScreen {
    func convertToCGDisplayRect(_ appKitGlobal: CGRect) -> CGRect {
        let clipped = appKitGlobal.intersection(frame)
        return CGRect(
            x: clipped.origin.x - frame.origin.x,
            y: frame.maxY - clipped.origin.y - clipped.height,
            width: clipped.width,
            height: clipped.height
        )
    }
}
