@preconcurrency import AppKit
@preconcurrency import CoreGraphics
import Foundation

@MainActor
public final class BackgroundResolver {
    private struct ImageCacheKey: Hashable {
        let path: String
        let modificationDate: Date?
    }

    private static var cache: [ImageCacheKey: CGImage] = [:]
    private let paths: ApplicationPaths

    public init(paths: ApplicationPaths) {
        self.paths = paths
    }

    public func resolve(_ configuration: BackgroundConfiguration, sourceDimensions: MediaDimensions) throws -> ResolvedBackground {
        do {
            return try resolvePrimary(configuration, sourceDimensions: sourceDimensions)
        } catch {
            guard let fallback = configuration.fallback else { throw error }
            let fallbackConfiguration = BackgroundConfiguration(
                type: fallback.type,
                screen: .main,
                path: fallback.path,
                fit: fallback.fit ?? configuration.fit,
                position: fallback.position ?? configuration.position,
                color: fallback.color,
                angle: fallback.angle,
                colors: fallback.colors,
                fallback: nil
            )
            return try resolvePrimary(fallbackConfiguration, sourceDimensions: sourceDimensions)
        }
    }

    private func resolvePrimary(_ configuration: BackgroundConfiguration, sourceDimensions: MediaDimensions) throws -> ResolvedBackground {
        switch configuration.type {
        case .desktop:
            let screen = try screen(for: configuration, sourceDimensions: sourceDimensions)
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
                throw ShotdError.processing("Unable to resolve the configured desktop wallpaper.")
            }
            return .image(try cachedImage(at: url), fit: configuration.fit, position: configuration.position)
        case .image:
            guard let path = configuration.path else { throw ShotdError.invalidConfiguration("background.path is required for image backgrounds.") }
            return .image(try cachedImage(at: paths.expandUserPath(path)), fit: configuration.fit, position: configuration.position)
        case .solid:
            guard let value = configuration.color, let color = CGColor.hex(value) else {
                throw ShotdError.invalidConfiguration("Invalid solid background color.")
            }
            return .solid(color)
        case .gradient:
            guard let values = configuration.colors else { throw ShotdError.invalidConfiguration("Gradient backgrounds require colors.") }
            let colors = try values.map { value -> CGColor in
                guard let color = CGColor.hex(value) else { throw ShotdError.invalidConfiguration("Invalid gradient color.") }
                return color
            }
            return .gradient(colors: colors, angle: configuration.angle ?? 135)
        }
    }

    private func cachedImage(at url: URL) throws -> CGImage {
        let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let key = ImageCacheKey(path: url.standardizedFileURL.path, modificationDate: modificationDate)
        if let image = Self.cache[key] { return image }
        Self.cache = Self.cache.filter { $0.key.path != key.path }
        let image = try ImageDecoder.decode(at: url)
        Self.cache[key] = image
        return image
    }

    private func screen(for configuration: BackgroundConfiguration, sourceDimensions: MediaDimensions) throws -> NSScreen {
        let screens = NSScreen.screens
        guard let main = NSScreen.main ?? screens.first else {
            throw ShotdError.processing("No active macOS display is available.")
        }
        switch configuration.screen {
        case .main:
            return main
        case .specific:
            guard let identifier = configuration.display,
                  let screen = screens.first(where: { Self.displayIdentifier(for: $0) == identifier }) else {
                throw ShotdError.processing("Configured display was not found.")
            }
            return screen
        case .bestMatch:
            let matches = screens.filter { screen in
                let size = CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
                return Int(size.width.rounded()) == sourceDimensions.width && Int(size.height.rounded()) == sourceDimensions.height
            }
            return matches.count == 1 ? matches[0] : main
        }
    }

    public static func displayIdentifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

private extension CGColor {
    static func hex(_ value: String) -> CGColor? {
        guard value.hasPrefix("#") else { return nil }
        let hex = String(value.dropFirst())
        guard hex.count == 6 || hex.count == 8, let number = UInt64(hex, radix: 16) else { return nil }
        let red = CGFloat((number >> (hex.count == 8 ? 24 : 16)) & 0xff) / 255
        let green = CGFloat((number >> (hex.count == 8 ? 16 : 8)) & 0xff) / 255
        let blue = CGFloat((number >> (hex.count == 8 ? 8 : 0)) & 0xff) / 255
        let alpha = hex.count == 8 ? CGFloat(number & 0xff) / 255 : 1
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
