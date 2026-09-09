import AppKit
import CoreImage
import PDFKit

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
    static func loadCIImage(from url: URL) throws -> CIImage {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try renderPDFPage(url)
        }
        if let image = CIImage(contentsOf: url) {
            return image
        }
        throw DocumentImportError.unsupported
    }

    static func renderPDFPage(_ url: URL, pageIndex: Int = 0, scale: CGFloat = 2) throws -> CIImage {
        guard let document = PDFDocument(url: url), let page = document.page(at: pageIndex) else {
            throw DocumentImportError.emptyPDF
        }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let nsImage = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = nsImage.tiffRepresentation, let ciImage = CIImage(data: tiff) else {
            throw DocumentImportError.unsupported
        }
        return ciImage
    }
}
