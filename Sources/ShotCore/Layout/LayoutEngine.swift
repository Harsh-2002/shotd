import Foundation

public enum LayoutEngine {
    public static func canvas(for source: MediaDimensions, configuration: LayoutConfiguration, maximumDimension: Int) throws -> Canvas {
        let scaled = downscaled(source, maximumDimension: maximumDimension)
        let ratioClass = RatioClass.classify(scaled)
        let basePadding = min(max(Double(scaled.shorterEdge) * configuration.paddingPercent, configuration.minimumPadding), configuration.maximumPadding)
        let ratio = scaled.aspectRatio
        let horizontal: Double
        let vertical: Double

        switch ratioClass {
        case .ultraWide:
            horizontal = basePadding
            vertical = max(configuration.minimumPadding, min(configuration.maximumPadding, basePadding * max(0.55, 2.5 / ratio)))
        case .portrait where ratio < 0.4:
            vertical = basePadding
            horizontal = max(configuration.minimumPadding, min(configuration.maximumPadding, basePadding * max(0.55, ratio / 0.4)))
        default:
            horizontal = basePadding
            vertical = basePadding
        }

        let width = Int((Double(scaled.width) + horizontal * 2).rounded(.up))
        let height = Int((Double(scaled.height) + vertical * 2).rounded(.up))
        return try Canvas(
            sourceDimensions: scaled,
            outputDimensions: .init(width: width, height: height),
            insets: .init(top: vertical, left: horizontal, bottom: vertical, right: horizontal),
            ratioClass: ratioClass
        )
    }

    private static func downscaled(_ source: MediaDimensions, maximumDimension: Int) -> MediaDimensions {
        guard source.longerEdge > maximumDimension else { return source }
        let scale = Double(maximumDimension) / Double(source.longerEdge)
        // Rounding down guarantees the safety limit and avoids accidental upscaling.
        return try! MediaDimensions(width: max(1, Int((Double(source.width) * scale).rounded(.down))), height: max(1, Int((Double(source.height) * scale).rounded(.down))))
    }
}
