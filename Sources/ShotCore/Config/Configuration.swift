import Foundation

public struct ShotdConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var watch: WatchConfiguration
    public var source: SourceConfiguration
    public var output: OutputConfiguration
    public var background: BackgroundConfiguration
    public var layout: LayoutConfiguration
    public var style: StyleConfiguration
    public var image: ImageConfiguration
    public var video: VideoConfiguration
    public var clipboard: ClipboardConfiguration
    public var storage: StorageConfiguration?

    public init(
        version: Int = currentVersion,
        watch: WatchConfiguration = .init(),
        source: SourceConfiguration = .init(),
        output: OutputConfiguration = .init(),
        background: BackgroundConfiguration = .init(),
        layout: LayoutConfiguration = .init(),
        style: StyleConfiguration = .init(),
        image: ImageConfiguration = .init(),
        video: VideoConfiguration = .init(),
        clipboard: ClipboardConfiguration = .init(),
        storage: StorageConfiguration? = nil
    ) {
        self.version = version
        self.watch = watch
        self.source = source
        self.output = output
        self.background = background
        self.layout = layout
        self.style = style
        self.image = image
        self.video = video
        self.clipboard = clipboard
        self.storage = storage
    }

    private enum CodingKeys: String, CodingKey {
        case version, watch, source, output, background, layout, style, image, video, clipboard, storage
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try values.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion,
            watch: try values.decodeIfPresent(WatchConfiguration.self, forKey: .watch) ?? .init(),
            source: try values.decodeIfPresent(SourceConfiguration.self, forKey: .source) ?? .init(),
            output: try values.decodeIfPresent(OutputConfiguration.self, forKey: .output) ?? .init(),
            background: try values.decodeIfPresent(BackgroundConfiguration.self, forKey: .background) ?? .init(),
            layout: try values.decodeIfPresent(LayoutConfiguration.self, forKey: .layout) ?? .init(),
            style: try values.decodeIfPresent(StyleConfiguration.self, forKey: .style) ?? .init(),
            image: try values.decodeIfPresent(ImageConfiguration.self, forKey: .image) ?? .init(),
            video: try values.decodeIfPresent(VideoConfiguration.self, forKey: .video) ?? .init(),
            clipboard: try values.decodeIfPresent(ClipboardConfiguration.self, forKey: .clipboard) ?? .init(),
            storage: try values.decodeIfPresent(StorageConfiguration.self, forKey: .storage)
        )
    }
}

public struct WatchConfiguration: Codable, Equatable, Sendable {
    public var directory: String
    public init(directory: String = "~/Pictures/shotd/inbox") { self.directory = directory }
}

public enum SourceRetention: String, Codable, Sendable { case keep, deleteAfterSuccess, replaceAfterSuccess }

public struct SourceConfiguration: Codable, Equatable, Sendable {
    public var retention: SourceRetention
    public var deleteRequiresUpload: Bool
    public init(retention: SourceRetention = .keep, deleteRequiresUpload: Bool = false) {
        self.retention = retention
        self.deleteRequiresUpload = deleteRequiresUpload
    }
}

public struct OutputConfiguration: Codable, Equatable, Sendable {
    public var directory: String
    public init(directory: String = "~/Pictures/shotd/output") { self.directory = directory }
}

public enum BackgroundType: String, Codable, Sendable { case desktop, image, solid, gradient }
public enum ScreenPolicy: String, Codable, Sendable { case main, specific, bestMatch }
public enum BackgroundFit: String, Codable, Sendable { case cover, contain, stretch }
public enum CanvasPosition: String, Codable, Sendable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
}

public struct BackgroundConfiguration: Codable, Equatable, Sendable {
    public var type: BackgroundType
    public var screen: ScreenPolicy
    public var display: String?
    public var path: String?
    public var fit: BackgroundFit
    public var position: CanvasPosition
    public var color: String?
    public var angle: Double?
    public var colors: [String]?
    public var fallback: BackgroundFallbackConfiguration?

    public init(
        type: BackgroundType = .desktop,
        screen: ScreenPolicy = .main,
        display: String? = nil,
        path: String? = nil,
        fit: BackgroundFit = .cover,
        position: CanvasPosition = .center,
        color: String? = nil,
        angle: Double? = nil,
        colors: [String]? = nil,
        fallback: BackgroundFallbackConfiguration? = .init(type: .solid, color: "#17191F")
    ) {
        self.type = type
        self.screen = screen
        self.display = display
        self.path = path
        self.fit = fit
        self.position = position
        self.color = color
        self.angle = angle
        self.colors = colors
        self.fallback = fallback
    }
}

public struct BackgroundFallbackConfiguration: Codable, Equatable, Sendable {
    public var type: BackgroundType
    public var path: String?
    public var fit: BackgroundFit?
    public var position: CanvasPosition?
    public var color: String?
    public var angle: Double?
    public var colors: [String]?

    public init(type: BackgroundType, path: String? = nil, fit: BackgroundFit? = nil, position: CanvasPosition? = nil, color: String? = nil, angle: Double? = nil, colors: [String]? = nil) {
        self.type = type
        self.path = path
        self.fit = fit
        self.position = position
        self.color = color
        self.angle = angle
        self.colors = colors
    }
}

public struct LayoutConfiguration: Codable, Equatable, Sendable {
    public var paddingPercent: Double
    public var minimumPadding: Double
    public var maximumPadding: Double
    public var alignment: CanvasPosition
    public init(paddingPercent: Double = 0.07, minimumPadding: Double = 40, maximumPadding: Double = 160, alignment: CanvasPosition = .center) {
        self.paddingPercent = paddingPercent
        self.minimumPadding = minimumPadding
        self.maximumPadding = maximumPadding
        self.alignment = alignment
    }
}

public struct ShadowConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var adaptive: Bool
    public var opacity: Double
    public init(enabled: Bool = true, adaptive: Bool = true, opacity: Double = 0.22) {
        self.enabled = enabled
        self.adaptive = adaptive
        self.opacity = opacity
    }
}

public struct StyleConfiguration: Codable, Equatable, Sendable {
    public var adaptiveCornerRadius: Bool
    public var shadow: ShadowConfiguration
    public init(adaptiveCornerRadius: Bool = true, shadow: ShadowConfiguration = .init()) {
        self.adaptiveCornerRadius = adaptiveCornerRadius
        self.shadow = shadow
    }
}

public enum ImageFormat: String, Codable, Sendable { case png, webp, avif, heic, jpeg, preserve }
public enum Compression: String, Codable, Sendable { case lossless, lossy }

public struct ImageConfiguration: Codable, Equatable, Sendable {
    public var format: ImageFormat
    public var compression: Compression?
    public var quality: Int?
    public var fallbackFormat: ImageFormat
    public var maximumDimension: Int
    public var colorSpace: String
    public init(format: ImageFormat = .webp, compression: Compression? = nil, quality: Int? = nil, fallbackFormat: ImageFormat = .png, maximumDimension: Int = 10_000, colorSpace: String = "sRGB") {
        self.format = format
        self.compression = compression
        self.quality = quality
        self.fallbackFormat = fallbackFormat
        self.maximumDimension = maximumDimension
        self.colorSpace = colorSpace
    }
}

public enum VideoFormat: String, Codable, Sendable { case mp4, mov }
public enum VideoCodec: String, Codable, Sendable { case h264, hevc }

public struct VideoConfiguration: Codable, Equatable, Sendable {
    public var format: VideoFormat
    public var codec: VideoCodec
    public var preserveFrameRate: Bool
    public var preserveAudio: Bool
    public init(format: VideoFormat = .mp4, codec: VideoCodec = .h264, preserveFrameRate: Bool = true, preserveAudio: Bool = true) {
        self.format = format
        self.codec = codec
        self.preserveFrameRate = preserveFrameRate
        self.preserveAudio = preserveAudio
    }
}

public enum ClipboardImageMode: String, Codable, Sendable { case image, disabled }
public enum ClipboardVideoMode: String, Codable, Sendable { case url, disabled }

public struct ClipboardConfiguration: Codable, Equatable, Sendable {
    public var image: ClipboardImageMode
    public var video: ClipboardVideoMode
    public init(image: ClipboardImageMode = .image, video: ClipboardVideoMode = .url) {
        self.image = image
        self.video = video
    }
}

public enum S3Addressing: String, Codable, Sendable { case auto, path, virtualHost }

public struct StoragePathsConfiguration: Codable, Equatable, Sendable {
    public var images: String
    public var videos: String
    public init(images: String = "screenshots", videos: String = "recordings") {
        self.images = images
        self.videos = videos
    }
}

public struct StorageConfiguration: Codable, Equatable, Sendable {
    public var endpoint: String
    public var region: String
    public var bucket: String
    public var credential: String
    public var developmentCredentials: StorageCredentials?
    public var addressing: S3Addressing
    public var publicBaseURL: String?
    public var presignExpirationSeconds: Int
    public var paths: StoragePathsConfiguration
    public var multipartThresholdMB: Int
    public var multipartPartSizeMB: Int
    public init(endpoint: String, region: String = "auto", bucket: String, credential: String, developmentCredentials: StorageCredentials? = nil, addressing: S3Addressing = .auto, publicBaseURL: String? = nil, presignExpirationSeconds: Int = 86_400, paths: StoragePathsConfiguration = .init(), multipartThresholdMB: Int = 100, multipartPartSizeMB: Int = 16) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.credential = credential
        self.developmentCredentials = developmentCredentials
        self.addressing = addressing
        self.publicBaseURL = publicBaseURL
        self.presignExpirationSeconds = presignExpirationSeconds
        self.paths = paths
        self.multipartThresholdMB = multipartThresholdMB
        self.multipartPartSizeMB = multipartPartSizeMB
    }
}

// Configuration sections decode independently so a user can override only the values they need.
extension WatchConfiguration {
    private enum CodingKeys: String, CodingKey { case directory }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(directory: try values.decodeIfPresent(String.self, forKey: .directory) ?? Self().directory)
    }
}

extension SourceConfiguration {
    private enum CodingKeys: String, CodingKey { case retention, deleteRequiresUpload }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(retention: try values.decodeIfPresent(SourceRetention.self, forKey: .retention) ?? .keep, deleteRequiresUpload: try values.decodeIfPresent(Bool.self, forKey: .deleteRequiresUpload) ?? false)
    }
}

extension OutputConfiguration {
    private enum CodingKeys: String, CodingKey { case directory }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(directory: try values.decodeIfPresent(String.self, forKey: .directory) ?? Self().directory)
    }
}

extension BackgroundConfiguration {
    private enum CodingKeys: String, CodingKey { case type, screen, display, path, fit, position, color, angle, colors, fallback }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            type: try values.decodeIfPresent(BackgroundType.self, forKey: .type) ?? .desktop,
            screen: try values.decodeIfPresent(ScreenPolicy.self, forKey: .screen) ?? .main,
            display: try values.decodeIfPresent(String.self, forKey: .display),
            path: try values.decodeIfPresent(String.self, forKey: .path),
            fit: try values.decodeIfPresent(BackgroundFit.self, forKey: .fit) ?? .cover,
            position: try values.decodeIfPresent(CanvasPosition.self, forKey: .position) ?? .center,
            color: try values.decodeIfPresent(String.self, forKey: .color),
            angle: try values.decodeIfPresent(Double.self, forKey: .angle),
            colors: try values.decodeIfPresent([String].self, forKey: .colors),
            fallback: try values.decodeIfPresent(BackgroundFallbackConfiguration.self, forKey: .fallback) ?? .init(type: .solid, color: "#17191F")
        )
    }
}

extension LayoutConfiguration {
    private enum CodingKeys: String, CodingKey { case paddingPercent, minimumPadding, maximumPadding, alignment }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(paddingPercent: try values.decodeIfPresent(Double.self, forKey: .paddingPercent) ?? 0.07, minimumPadding: try values.decodeIfPresent(Double.self, forKey: .minimumPadding) ?? 40, maximumPadding: try values.decodeIfPresent(Double.self, forKey: .maximumPadding) ?? 160, alignment: try values.decodeIfPresent(CanvasPosition.self, forKey: .alignment) ?? .center)
    }
}

extension ShadowConfiguration {
    private enum CodingKeys: String, CodingKey { case enabled, adaptive, opacity }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true, adaptive: try values.decodeIfPresent(Bool.self, forKey: .adaptive) ?? true, opacity: try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.22)
    }
}

extension StyleConfiguration {
    private enum CodingKeys: String, CodingKey { case adaptiveCornerRadius, shadow }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(adaptiveCornerRadius: try values.decodeIfPresent(Bool.self, forKey: .adaptiveCornerRadius) ?? true, shadow: try values.decodeIfPresent(ShadowConfiguration.self, forKey: .shadow) ?? .init())
    }
}

extension ImageConfiguration {
    private enum CodingKeys: String, CodingKey { case format, compression, quality, fallbackFormat, maximumDimension, colorSpace }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(format: try values.decodeIfPresent(ImageFormat.self, forKey: .format) ?? .webp, compression: try values.decodeIfPresent(Compression.self, forKey: .compression), quality: try values.decodeIfPresent(Int.self, forKey: .quality), fallbackFormat: try values.decodeIfPresent(ImageFormat.self, forKey: .fallbackFormat) ?? .png, maximumDimension: try values.decodeIfPresent(Int.self, forKey: .maximumDimension) ?? 10_000, colorSpace: try values.decodeIfPresent(String.self, forKey: .colorSpace) ?? "sRGB")
    }
}

extension VideoConfiguration {
    private enum CodingKeys: String, CodingKey { case format, codec, preserveFrameRate, preserveAudio }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(format: try values.decodeIfPresent(VideoFormat.self, forKey: .format) ?? .mp4, codec: try values.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .h264, preserveFrameRate: try values.decodeIfPresent(Bool.self, forKey: .preserveFrameRate) ?? true, preserveAudio: try values.decodeIfPresent(Bool.self, forKey: .preserveAudio) ?? true)
    }
}

extension ClipboardConfiguration {
    private enum CodingKeys: String, CodingKey { case image, video }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(image: try values.decodeIfPresent(ClipboardImageMode.self, forKey: .image) ?? .image, video: try values.decodeIfPresent(ClipboardVideoMode.self, forKey: .video) ?? .url)
    }
}

extension StoragePathsConfiguration {
    private enum CodingKeys: String, CodingKey { case images, videos }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(images: try values.decodeIfPresent(String.self, forKey: .images) ?? "screenshots", videos: try values.decodeIfPresent(String.self, forKey: .videos) ?? "recordings")
    }
}

extension StorageConfiguration {
    private enum CodingKeys: String, CodingKey { case endpoint, region, bucket, credential, developmentCredentials, addressing, publicBaseURL, presignExpirationSeconds, paths, multipartThresholdMB, multipartPartSizeMB }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            endpoint: try values.decode(String.self, forKey: .endpoint),
            region: try values.decodeIfPresent(String.self, forKey: .region) ?? "auto",
            bucket: try values.decode(String.self, forKey: .bucket),
            credential: try values.decode(String.self, forKey: .credential),
            developmentCredentials: try values.decodeIfPresent(StorageCredentials.self, forKey: .developmentCredentials),
            addressing: try values.decodeIfPresent(S3Addressing.self, forKey: .addressing) ?? .auto,
            publicBaseURL: try values.decodeIfPresent(String.self, forKey: .publicBaseURL),
            presignExpirationSeconds: try values.decodeIfPresent(Int.self, forKey: .presignExpirationSeconds) ?? 86_400,
            paths: try values.decodeIfPresent(StoragePathsConfiguration.self, forKey: .paths) ?? .init(),
            multipartThresholdMB: try values.decodeIfPresent(Int.self, forKey: .multipartThresholdMB) ?? 100,
            multipartPartSizeMB: try values.decodeIfPresent(Int.self, forKey: .multipartPartSizeMB) ?? 16
        )
    }
}
