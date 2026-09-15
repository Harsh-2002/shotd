@preconcurrency import CoreGraphics
import Foundation

@MainActor
public final class ImageProcessor {
    private let resolver: BackgroundResolver
    private let encoders: EncoderRegistry

    public init(resolver: BackgroundResolver, encoders: EncoderRegistry) {
        self.resolver = resolver
        self.encoders = encoders
    }

    public func process(sourceURL: URL, configuration: ShotdConfiguration) throws -> EncodedImage {
        guard let info = try MediaInspector.inspectImage(at: sourceURL) else {
            throw ShotdError.processing("The source is not a supported still image.")
        }
        let source = try ImageDecoder.decode(at: sourceURL)
        let background = try resolver.resolve(configuration.background, sourceDimensions: info.dimensions)
        let rendered = try ImageRenderer.render(source: source, media: info, configuration: configuration, background: background)
        return try encoders.encode(rendered, configuration: configuration.image, sourceTypeIdentifier: info.typeIdentifier)
    }
}
