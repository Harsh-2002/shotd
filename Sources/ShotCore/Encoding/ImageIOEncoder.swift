@preconcurrency import CoreGraphics
@preconcurrency import ImageIO
import Foundation

@MainActor
public struct ImageIOEncoder: ImageEncoding {
    public let format: ImageFormat
    public let destinationType: CFString
    public let availability: CodecAvailability

    public init(format: ImageFormat, destinationType: CFString, lossless: Bool = false) {
        self.format = format
        self.destinationType = destinationType
        self.availability = .init(format: format, available: true, lossless: lossless, backend: .imageIO)
    }

    public func encode(_ image: CGImage, configuration: ImageConfiguration) throws -> EncodedImage {
        let buffer = NSMutableData()
        guard let outputFormat = OutputFormat.image(for: format), let destination = CGImageDestinationCreateWithData(buffer, destinationType, 1, nil) else {
            throw ShotdError.processing("Unable to initialize the \(format.rawValue) encoder.")
        }
        var properties: [CFString: Any] = [:]
        if let quality = configuration.quality {
            properties[kCGImageDestinationLossyCompressionQuality] = CGFloat(quality) / 100
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ShotdError.processing("Unable to encode \(format.rawValue) output.")
        }
        return EncodedImage(data: buffer as Data, format: outputFormat)
    }
}
