import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageIOError: LocalizedError {
    case encodeFailed

    public var errorDescription: String? {
        "Could not encode the captured image."
    }
}

public enum ImageResizer {
    public static func capped(_ image: CIImage, maxPixels: Int) -> CIImage {
        let width = max(image.extent.width, 1)
        let height = max(image.extent.height, 1)
        let pixels = width * height
        guard pixels > CGFloat(maxPixels) else { return image }
        let scale = sqrt(CGFloat(maxPixels) / pixels)
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    public static func writePNG(_ image: CIImage, maxPixels: Int) throws -> URL {
        let resized = capped(image, maxPixels: maxPixels)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "globaltrans-\(UUID().uuidString).png")
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        try context.writePNGRepresentation(
            of: resized,
            to: url,
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return url
    }

    public static func jpegData(_ image: CIImage, maxPixels: Int, quality: CGFloat = 0.85) throws -> Data {
        let resized = capped(image, maxPixels: maxPixels)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let cgImage = context.createCGImage(
            resized,
            from: resized.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw ImageIOError.encodeFailed
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageIOError.encodeFailed
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageIOError.encodeFailed
        }
        return data as Data
    }
}
