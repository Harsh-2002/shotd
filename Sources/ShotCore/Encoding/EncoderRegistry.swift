@preconcurrency import CoreGraphics
@preconcurrency import ImageIO
import Foundation

@MainActor
public final class EncoderRegistry {
    private let encoders: [ImageFormat: any ImageEncoding]
    private let supportedTypes: Set<String>

    public init() {
        let types = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        self.supportedTypes = Set(types)
        var available: [ImageFormat: any ImageEncoding] = [:]
        Self.register(.png, identifier: "public.png", lossless: true, types: supportedTypes, into: &available)
        Self.register(.jpeg, identifier: "public.jpeg", lossless: false, types: supportedTypes, into: &available)
        Self.register(.heic, identifier: "public.heic", lossless: false, types: supportedTypes, into: &available)
        // Bundled codecs guarantee consistent behavior across supported macOS releases.
        available[.webp] = BundledWebPEncoder()
        available[.avif] = BundledAVIFEncoder(losslessVerified: BundledCodecs.avifLosslessRoundTripIsExact())
        self.encoders = available
    }

    public func codecs() -> [CodecAvailability] {
        ImageFormat.allCases.filter { $0 != .preserve }.map { format in
            encoders[format]?.availability ?? .init(format: format, available: false, lossless: false, backend: nil)
        }
    }

    public func encode(_ image: CGImage, configuration: ImageConfiguration, sourceTypeIdentifier: String? = nil) throws -> EncodedImage {
        let requested = try resolvedFormat(for: configuration, sourceTypeIdentifier: sourceTypeIdentifier)
        if let encoder = encoders[requested], supports(configuration, with: encoder.availability) {
            return try encoder.encode(image, configuration: configuration)
        }
        guard configuration.fallbackFormat != requested, let encoder = encoders[configuration.fallbackFormat] else {
            throw ShotdError.unsupported("The requested \(requested.rawValue) encoder is unavailable and no configured fallback is available.")
        }
        var fallbackConfiguration = configuration
        fallbackConfiguration.format = configuration.fallbackFormat
        fallbackConfiguration.compression = configuration.fallbackFormat == .png ? .lossless : fallbackConfiguration.compression
        return try encoder.encode(image, configuration: fallbackConfiguration)
    }

    private func resolvedFormat(for configuration: ImageConfiguration, sourceTypeIdentifier: String?) throws -> ImageFormat {
        guard configuration.format == .preserve else { return configuration.format }
        guard let sourceTypeIdentifier else { return .png }
        switch sourceTypeIdentifier {
        case "public.png": return .png
        case "public.jpeg", "public.jpeg-2000": return .jpeg
        case "public.heic", "public.heif": return .heic
        case "org.webmproject.webp": return .webp
        case "public.avif": return .avif
        default: return .png
        }
    }

    private func supports(_ configuration: ImageConfiguration, with availability: CodecAvailability) -> Bool {
        guard availability.available else { return false }
        if configuration.compression == .lossless { return availability.lossless }
        return true
    }

    private static func register(_ format: ImageFormat, identifier: String, lossless: Bool, types: Set<String>, into encoders: inout [ImageFormat: any ImageEncoding]) {
        guard types.contains(identifier) else { return }
        encoders[format] = ImageIOEncoder(format: format, destinationType: identifier as CFString, lossless: lossless)
    }
}

private extension ImageFormat {
    static var allCases: [ImageFormat] { [.png, .webp, .avif, .heic, .jpeg, .preserve] }
}
