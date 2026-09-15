@preconcurrency import CoreGraphics
@preconcurrency import ImageIO
import Foundation

public struct ProcessedStillCapture: Sendable {
    public let outputURL: URL
    public let format: OutputFormat

    public init(outputURL: URL, format: OutputFormat) {
        self.outputURL = outputURL
        self.format = format
    }
}

@MainActor
public final class StillCaptureProcessor {
    private let paths: ApplicationPaths
    private let resolver: BackgroundResolver
    private let encoders: EncoderRegistry

    public init(paths: ApplicationPaths) {
        self.paths = paths
        self.resolver = BackgroundResolver(paths: paths)
        self.encoders = EncoderRegistry()
    }

    public func process(sourceURL: URL, configuration: ShotdConfiguration, publishToClipboard: Bool = true) throws -> ProcessedStillCapture {
        guard let info = try MediaInspector.inspectImage(at: sourceURL) else {
            throw ShotdError.processing("The source is not a supported still image.")
        }
        let source = try ImageDecoder.decode(at: sourceURL)
        let background = try resolver.resolve(configuration.background, sourceDimensions: info.dimensions)
        let rendered = try ImageRenderer.render(source: source, media: info, configuration: configuration, background: background)
        let encoded = try encoders.encode(rendered, configuration: configuration.image, sourceTypeIdentifier: info.typeIdentifier)
        let output = OutputManager(directory: paths.expandUserPath(configuration.output.directory).standardizedFileURL)
        try output.prepareDirectory()
        let destination = output.destination(for: sourceURL, format: encoded.format)
        try AtomicWriter.write(encoded.data, to: destination)
        if publishToClipboard, configuration.clipboard.image == .image {
            ClipboardService.publishImage(rendered)
        }
        return ProcessedStillCapture(outputURL: destination, format: encoded.format)
    }
}
