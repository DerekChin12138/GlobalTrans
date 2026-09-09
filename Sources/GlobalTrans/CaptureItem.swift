import AppKit
import CoreImage
import Foundation

enum CaptureKind: Equatable {
    case screen
    case file
}

enum CaptureStage: Equatable {
    case queued
    case recognizing
    case ocrReady
    case ocrFailed(String)
    case translating
    case translated
    case translateFailed(String)

    var needsOCR: Bool {
        switch self {
        case .queued, .ocrFailed: return true
        default: return false
        }
    }

    var needsTranslate: Bool {
        switch self {
        case .ocrReady, .translateFailed: return true
        default: return false
        }
    }

    var badge: String {
        switch self {
        case .queued: return "queued"
        case .recognizing: return "OCR…"
        case .ocrReady: return "OCR"
        case .ocrFailed: return "OCR failed"
        case .translating: return "MT…"
        case .translated: return "done"
        case .translateFailed: return "MT failed"
        }
    }
}

struct CaptureItem: Identifiable {
    let id: UUID
    let createdAt: Date
    let kind: CaptureKind
    let maxTokens: Int
    let maxPixels: Int
    let image: CIImage
    let thumbnail: NSImage
    var ocrText = ""
    var translatedText = ""
    var stage: CaptureStage = .queued

    static let cacheLimit = 5

    static func make(
        image: CIImage,
        kind: CaptureKind,
        maxTokens: Int,
        maxPixels: Int
    ) -> CaptureItem {
        CaptureItem(
            id: UUID(),
            createdAt: Date(),
            kind: kind,
            maxTokens: maxTokens,
            maxPixels: maxPixels,
            image: image,
            thumbnail: thumbnailImage(from: image)
        )
    }

    private static func thumbnailImage(from image: CIImage, maxSide: CGFloat = 72) -> NSImage {
        let extent = image.extent
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let cgImage = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: colorSpace)
        let size: NSSize
        if extent.width > 0, extent.height > 0 {
            let scale = min(maxSide / extent.width, maxSide / extent.height, 1)
            size = NSSize(width: max(extent.width * scale, 1), height: max(extent.height * scale, 1))
        } else {
            size = NSSize(width: maxSide, height: maxSide)
        }
        if let cgImage {
            return NSImage(cgImage: cgImage, size: size)
        }
        return NSImage(size: size)
    }
}
