@preconcurrency import CoreGraphics
import Foundation

@MainActor
public enum ImageRenderer {
    public static func render(source: CGImage, media: ImageMediaInfo, configuration: ShotdConfiguration, background: ResolvedBackground) throws -> CGImage {
        let canvas = try LayoutEngine.canvas(for: media.dimensions, configuration: configuration.layout, maximumDimension: configuration.image.maximumDimension)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: canvas.outputDimensions.width,
            height: canvas.outputDimensions.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ShotdError.processing("Unable to create the image render context.")
        }
        let bounds = CGRect(x: 0, y: 0, width: canvas.outputDimensions.width, height: canvas.outputDimensions.height)
        background.draw(in: context, rect: bounds)

        let sourceRect = CGRect(
            x: CGFloat(canvas.insets.left),
            y: CGFloat(canvas.insets.bottom),
            width: CGFloat(canvas.sourceDimensions.width),
            height: CGFloat(canvas.sourceDimensions.height)
        )
        let applyPresentationStyle = !ImageAlphaInspector.hasMeaningfulEdgeTransparency(source)
        if applyPresentationStyle && configuration.style.shadow.enabled {
            let radius = cornerRadius(for: canvas.sourceDimensions)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -max(4, radius * 0.35)), blur: max(8, radius * 1.2), color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: configuration.style.shadow.opacity))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.addPath(CGPath(roundedRect: sourceRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        if applyPresentationStyle && configuration.style.adaptiveCornerRadius {
            let radius = cornerRadius(for: canvas.sourceDimensions)
            context.addPath(CGPath(roundedRect: sourceRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
        }
        context.interpolationQuality = .high
        context.draw(source, in: sourceRect)
        context.restoreGState()
        guard let image = context.makeImage() else { throw ShotdError.processing("Unable to finalize image rendering.") }
        return image
    }

    private static func cornerRadius(for dimensions: MediaDimensions) -> CGFloat {
        min(48, max(8, CGFloat(dimensions.shorterEdge) * 0.025))
    }
}

private enum ImageAlphaInspector {
    static func hasMeaningfulEdgeTransparency(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 1, height > 1,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return image.alphaInfo != .none }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let step = max(1, min(width, height) / 200)
        for x in stride(from: 0, to: width, by: step) {
            if pixels[(x * 4) + 3] < 250 || pixels[((height - 1) * width + x) * 4 + 3] < 250 { return true }
        }
        for y in stride(from: 0, to: height, by: step) {
            if pixels[(y * width) * 4 + 3] < 250 || pixels[(y * width + width - 1) * 4 + 3] < 250 { return true }
        }
        return false
    }
}
