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
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    public static func encodedJPEGAndThumb(_ image: CGImage) -> (jpeg: Data, thumb: Data) {
        let jpeg = jpegData(image) ?? Data()
        let thumb = thumbnail(from: image).flatMap(pngData) ?? Data()
        return (jpeg, thumb)
    }

    public static func rasterize(_ image: CIImage) -> CGImage? {
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1,
              extent.width.isFinite, extent.height.isFinite
        else { return nil }
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .cacheIntermediates: false,
        ])
        let cgImage = context.createCGImage(
            image,
            from: extent,
            format: .RGBA8,
            colorSpace: colorSpace
        )
        context.clearCaches()
        return cgImage
    }

    public static func ciImage(fromJPEG data: Data, maxPixels: Int? = nil) -> CIImage? {
        guard let cgImage = cgImage(fromJPEG: data, maxPixels: maxPixels) else { return nil }
        return CIImage(cgImage: cgImage)
    }

    public static func cgImage(fromJPEG data: Data, maxPixels: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        if let maxPixels, maxPixels > 0,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width > 0, height > 0, width * height > maxPixels
        {
            let scale = sqrt(Double(maxPixels) / Double(width * height))
            let maxSide = max(Int((Double(max(width, height)) * scale).rounded()), 1)
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            options[kCGImageSourceCreateThumbnailWithTransform] = true
            options[kCGImageSourceThumbnailMaxPixelSize] = maxSide
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    public static func clearCaches() {}

    public static func capped(_ image: CIImage, maxPixels: Int) -> CIImage {
        guard let cgImage = rasterize(image) else { return image }
        return CIImage(cgImage: capped(cgImage, maxPixels: maxPixels))
    }

    public static func capped(_ image: CGImage, maxPixels: Int) -> CGImage {
        let width = max(image.width, 1)
        let height = max(image.height, 1)
        let pixels = width * height
        guard pixels > maxPixels else { return image }
        let scale = sqrt(Double(maxPixels) / Double(pixels))
        let newWidth = max(Int((Double(width) * scale).rounded()), 1)
        let newHeight = max(Int((Double(height) * scale).rounded()), 1)
        return self.scale(image, width: newWidth, height: newHeight) ?? image
    }

    public static func thumbnail(from image: CGImage, maxSide: CGFloat = 72) -> CGImage? {
        let width = CGFloat(max(image.width, 1))
        let height = CGFloat(max(image.height, 1))
        let factor = min(maxSide / width, maxSide / height, 1)
        return scale(
            image,
            width: max(Int((width * factor).rounded()), 1),
            height: max(Int((height * factor).rounded()), 1)
        )
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func jpegData(_ image: CGImage, quality: CGFloat = 0.85) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func jpegData(_ image: CIImage, maxPixels: Int, quality: CGFloat = 0.85) throws -> Data {
        guard let rasterized = rasterize(image) else {
            throw ImageIOError.encodeFailed
        }
        guard let data = jpegData(capped(rasterized, maxPixels: maxPixels), quality: quality) else {
            throw ImageIOError.encodeFailed
        }
        return data
    }

    private static func scale(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: max(width, 1),
            height: max(height, 1),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
