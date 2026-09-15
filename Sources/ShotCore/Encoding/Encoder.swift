@preconcurrency import CoreGraphics
import Foundation

public enum EncoderBackend: String, Sendable { case imageIO = "ImageIO", bundledWebP = "bundled libwebp", bundledAVIF = "bundled libavif" }

public struct CodecAvailability: Sendable, Equatable {
    public let format: ImageFormat
    public let available: Bool
    public let lossless: Bool
    public let backend: EncoderBackend?

    public init(format: ImageFormat, available: Bool, lossless: Bool, backend: EncoderBackend?) {
        self.format = format
        self.available = available
        self.lossless = lossless
        self.backend = backend
    }
}

public struct EncodedImage: Sendable {
    public let data: Data
    public let format: OutputFormat

    public init(data: Data, format: OutputFormat) {
        self.data = data
        self.format = format
    }
}

@MainActor
public protocol ImageEncoding {
    var availability: CodecAvailability { get }
    func encode(_ image: CGImage, configuration: ImageConfiguration) throws -> EncodedImage
}
