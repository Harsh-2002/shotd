@preconcurrency import CoreGraphics
@preconcurrency import ImageIO
import Foundation

public enum ImageDecoder {
    public static func decode(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ShotdError.processing("Unable to decode image \(url.lastPathComponent).")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height),
            kCGImageSourceShouldCache: true
        ]
        guard let orientedImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ShotdError.processing("Unable to apply image orientation for \(url.lastPathComponent).")
        }
        return orientedImage
    }
}
