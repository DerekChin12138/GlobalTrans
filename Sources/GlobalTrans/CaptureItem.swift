import AppKit
import Foundation
import GlobalTransCore

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

    mutating func discardPixels() {
        CaptureStore.remove(jpegURL)
        jpegURL = nil
        thumbPNG = Data()
    }

    func needsTranslate(to target: TranslateLanguage) -> Bool {
        switch stage {
        case .ocrReady, .translateFailed:
            return true
        case .translated:
            return translatedTarget != target
        default:
            return false
        }
    }

    static let cacheLimit = 5

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
}
