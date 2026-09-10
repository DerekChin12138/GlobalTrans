import AppKit
import CoreGraphics
import Foundation
import GlobalTransCore
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum DocumentImportError: LocalizedError {
    case unsupported
    case emptyPDF

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Only PNG, JPEG, TIFF, HEIC, and PDF files are supported."
        case .emptyPDF:
            return "The PDF has no pages."
        }
    }
}

enum DocumentImporter {
    private static let noCache: [CFString: Any] = [
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false,
    ]

    static func makeCaptureItem(from url: URL) throws -> CaptureItem {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try makePDFItem(url)
        }
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, noCache as CFDictionary) else {
            throw DocumentImportError.unsupported
        }
        let jpeg: Data
        if isJPEG(source) || ext == "jpg" || ext == "jpeg" {
            jpeg = data
        } else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, noCache as CFDictionary),
                  let encoded = ImageResizer.jpegData(image)
            else {
                throw DocumentImportError.unsupported
            }
            jpeg = encoded
        }
        let thumb = thumbnailPNG(from: source)
        let jpegURL = try CaptureStore.writeJPEG(jpeg)
        return CaptureItem(
            id: UUID(),
            createdAt: Date(),
            kind: .file,
            jpegURL: jpegURL,
            thumbPNG: thumb
        )
    }

    private static func makePDFItem(_ url: URL) throws -> CaptureItem {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            throw DocumentImportError.emptyPDF
        }
        let bounds = page.bounds(for: .mediaBox)
        let maxSide: CGFloat = 2880
        let scale = min(2, maxSide / max(bounds.width, bounds.height, 1))
        let size = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        let nsImage = page.thumbnail(of: size, for: .mediaBox)
        var rect = NSRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let jpeg = ImageResizer.jpegData(cgImage)
        else {
            throw DocumentImportError.unsupported
        }
        let thumb = ImageResizer.thumbnail(from: cgImage).flatMap(ImageResizer.pngData) ?? Data()
        let jpegURL = try CaptureStore.writeJPEG(jpeg)
        return CaptureItem(
            id: UUID(),
            createdAt: Date(),
            kind: .file,
            jpegURL: jpegURL,
            thumbPNG: thumb
        )
    }

    private static func thumbnailPNG(from source: CGImageSource) -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 72,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let png = ImageResizer.pngData(thumb)
        else {
            return Data()
        }
        return png
    }

    private static func isJPEG(_ source: CGImageSource) -> Bool {
        guard let raw = CGImageSourceGetType(source) as String? else { return false }
        return raw == UTType.jpeg.identifier
    }
}
