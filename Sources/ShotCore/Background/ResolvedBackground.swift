@preconcurrency import CoreGraphics
import Foundation

@MainActor
public enum ResolvedBackground {
    case image(CGImage, fit: BackgroundFit, position: CanvasPosition)
    case solid(CGColor)
    case gradient(colors: [CGColor], angle: Double)

    public func draw(in context: CGContext, rect: CGRect) {
        switch self {
        case .image(let image, let fit, let position):
            context.draw(image, in: imageRect(source: CGSize(width: image.width, height: image.height), target: rect, fit: fit, position: position))
        case .solid(let color):
            context.setFillColor(color)
            context.fill(rect)
        case .gradient(let colors, let angle):
            drawGradient(in: context, rect: rect, colors: colors, angle: angle)
        }
    }

    private func imageRect(source: CGSize, target: CGRect, fit: BackgroundFit, position: CanvasPosition) -> CGRect {
        guard fit != .stretch else { return target }
        let widthScale = target.width / source.width
        let heightScale = target.height / source.height
        let scale = fit == .cover ? max(widthScale, heightScale) : min(widthScale, heightScale)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        let offset = position.offset(container: target.size, content: size)
        return CGRect(x: target.minX + offset.x, y: target.minY + offset.y, width: size.width, height: size.height)
    }

    private func drawGradient(in context: CGContext, rect: CGRect, colors: [CGColor], angle: Double) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil) else { return }
        let radians = angle * .pi / 180
        let vector = CGPoint(x: cos(radians), y: sin(radians))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = hypot(rect.width, rect.height) / 2
        let start = CGPoint(x: center.x - vector.x * radius, y: center.y - vector.y * radius)
        let end = CGPoint(x: center.x + vector.x * radius, y: center.y + vector.y * radius)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
    }
}

private extension CanvasPosition {
    func offset(container: CGSize, content: CGSize) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .topLeft, .left, .bottomLeft: x = 0
        case .top, .center, .bottom: x = (container.width - content.width) / 2
        case .topRight, .right, .bottomRight: x = container.width - content.width
        }
        switch self {
        case .topLeft, .top, .topRight: y = container.height - content.height
        case .left, .center, .right: y = (container.height - content.height) / 2
        case .bottomLeft, .bottom, .bottomRight: y = 0
        }
        return CGPoint(x: x, y: y)
    }
}
