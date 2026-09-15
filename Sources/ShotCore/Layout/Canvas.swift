import Foundation

public struct EdgeInsets: Equatable, Sendable {
    public let top: Double
    public let left: Double
    public let bottom: Double
    public let right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct Canvas: Equatable, Sendable {
    public let sourceDimensions: MediaDimensions
    public let outputDimensions: MediaDimensions
    public let insets: EdgeInsets
    public let ratioClass: RatioClass

    public init(sourceDimensions: MediaDimensions, outputDimensions: MediaDimensions, insets: EdgeInsets, ratioClass: RatioClass) {
        self.sourceDimensions = sourceDimensions
        self.outputDimensions = outputDimensions
        self.insets = insets
        self.ratioClass = ratioClass
    }
}
