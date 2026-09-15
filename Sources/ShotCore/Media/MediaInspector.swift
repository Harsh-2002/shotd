@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ImageIO
import UniformTypeIdentifiers

public struct ImageMediaInfo: Sendable {
    public let dimensions: MediaDimensions
    public let typeIdentifier: String
    public let hasAlpha: Bool
    public let orientation: CGImagePropertyOrientation
    public let colorSpaceName: String?

    public init(dimensions: MediaDimensions, typeIdentifier: String, hasAlpha: Bool, orientation: CGImagePropertyOrientation, colorSpaceName: String?) {
        self.dimensions = dimensions
        self.typeIdentifier = typeIdentifier
        self.hasAlpha = hasAlpha
        self.orientation = orientation
        self.colorSpaceName = colorSpaceName
    }
}

public struct VideoMediaInfo: Sendable {
    public let dimensions: MediaDimensions
    public let duration: CMTime
    public let nominalFrameRate: Float
    public let hasAudio: Bool
    public let preferredTransform: CGAffineTransform

    public init(dimensions: MediaDimensions, duration: CMTime, nominalFrameRate: Float, hasAudio: Bool, preferredTransform: CGAffineTransform) {
        self.dimensions = dimensions
        self.duration = duration
        self.nominalFrameRate = nominalFrameRate
        self.hasAudio = hasAudio
        self.preferredTransform = preferredTransform
    }
}

public enum MediaInfo: Sendable {
    case image(ImageMediaInfo)
    case video(VideoMediaInfo)

    public var type: MediaType {
        switch self {
        case .image: .image
        case .video: .video
        }
    }

    public var dimensions: MediaDimensions {
        switch self {
        case .image(let value): value.dimensions
        case .video(let value): value.dimensions
        }
    }
}

public enum MediaInspector {
    public static func inspect(at url: URL) async throws -> MediaInfo {
        if let image = try inspectImage(at: url) {
            return .image(image)
        }
        return .video(try await inspectVideo(at: url))
    }

    public static func inspectImage(at url: URL) throws -> ImageMediaInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let type = CGImageSourceGetType(source) else {
            throw ShotdError.processing("Unable to inspect image metadata for \(url.lastPathComponent).")
        }
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        let alphaInfo = image?.alphaInfo
        let hasAlpha = alphaInfo.map { $0 != .none && $0 != .noneSkipFirst && $0 != .noneSkipLast } ?? false
        let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        let dimensions: MediaDimensions
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            dimensions = try .init(width: height, height: width)
        default:
            dimensions = try .init(width: width, height: height)
        }
        return ImageMediaInfo(
            dimensions: dimensions,
            typeIdentifier: type as String,
            hasAlpha: hasAlpha,
            orientation: orientation,
            colorSpaceName: image?.colorSpace?.name as String?
        )
    }

    public static func inspectVideo(at url: URL) async throws -> VideoMediaInfo {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else {
            throw ShotdError.processing("Video is not readable: \(url.lastPathComponent).")
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw ShotdError.processing("No video track found in \(url.lastPathComponent).")
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = size.applying(transform)
        let dimensions = try MediaDimensions(width: Int(abs(transformed.width.rounded())), height: Int(abs(transformed.height.rounded())))
        let duration = try await asset.load(.duration)
        let rate = try await track.load(.nominalFrameRate)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        return VideoMediaInfo(dimensions: dimensions, duration: duration, nominalFrameRate: rate, hasAudio: !audioTracks.isEmpty, preferredTransform: transform)
    }
}
