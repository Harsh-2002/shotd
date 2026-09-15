import Foundation

public struct MediaDimensions: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw ShotdError.processing("Media dimensions must be positive.")
        }
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double { Double(width) / Double(height) }
    public var shorterEdge: Int { min(width, height) }
    public var longerEdge: Int { max(width, height) }
}

public enum RatioClass: String, Codable, Sendable {
    case portrait
    case nearSquare
    case landscape
    case wide
    case ultraWide

    public static func classify(_ dimensions: MediaDimensions) -> RatioClass {
        switch dimensions.aspectRatio {
        case ..<0.80: .portrait
        case ..<1.25: .nearSquare
        case ..<1.80: .landscape
        case ..<2.50: .wide
        default: .ultraWide
        }
    }
}
