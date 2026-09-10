import AppKit
import Foundation
import GlobalTransCore

enum CaptureKind: Equatable {
    case screen
    case file
    case text
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
    /// JPEG on disk. Uncompressed Retina RGBA is 60–80 MB and must not stay in RAM.
    var jpegURL: URL?
    var thumbPNG: Data
    var ocrText = ""
    var translatedText = ""
    var translatedTarget: TranslateLanguage?
    var stage: CaptureStage = .queued

    func jpegData() -> Data? {
        guard let jpegURL else { return nil }
        return CaptureStore.load(jpegURL)
    }

    var thumbnailImage: NSImage {
        NSImage(data: thumbPNG) ?? NSImage(size: NSSize(width: 72, height: 72))
    }

    var displayBadge: String {
        if kind == .text, case .queued = stage { return "text" }
        return stage.badge
    }

    mutating func discardPixels() {
        CaptureStore.remove(jpegURL)
        jpegURL = nil
        thumbPNG = Data()
    }

    func needsTranslate(to target: TranslateLanguage) -> Bool {
        let source = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return false }
        switch stage {
        case .recognizing, .translating:
            return false
        case .translated:
            return translatedTarget != target
        default:
            return true
        }
    }

    static let cacheLimit = 5

    static func makeText(id: UUID = UUID()) -> CaptureItem {
        CaptureItem(
            id: id,
            createdAt: Date(),
            kind: .text,
            jpegURL: nil,
            thumbPNG: textThumbnailPNG(),
            stage: .queued
        )
    }

    static func make(cgImage: CGImage, kind: CaptureKind) -> CaptureItem {
        let encoded = ImageResizer.encodedJPEGAndThumb(cgImage)
        let jpegURL = try? CaptureStore.writeJPEG(encoded.jpeg)
        return CaptureItem(
            id: UUID(),
            createdAt: Date(),
            kind: kind,
            jpegURL: jpegURL,
            thumbPNG: encoded.thumb
        )
    }

    private static func textThumbnailPNG() -> Data {
        let size = NSSize(width: 72, height: 52)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.windowBackgroundColor.setFill()
            rect.fill()
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            if let symbol = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            {
                let symbolSize = symbol.size
                let drawn = NSRect(
                    x: rect.midX - symbolSize.width / 2,
                    y: rect.midY - symbolSize.height / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                NSColor.secondaryLabelColor.set()
                symbol.draw(in: drawn)
            }
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return Data() }
        return png
    }
}
