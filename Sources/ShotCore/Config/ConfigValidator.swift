import Foundation

public enum ConfigValidator {
    public static func validate(_ configuration: ShotdConfiguration, paths: ApplicationPaths) throws {
        guard configuration.version == ShotdConfiguration.currentVersion else {
            throw ShotdError.invalidConfiguration("Unsupported configuration version \(configuration.version).")
        }
        try validateDirectory(configuration.watch.directory, name: "watch.directory", paths: paths)
        try validateDirectory(configuration.output.directory, name: "output.directory", paths: paths)
        let watchDirectory = paths.expandUserPath(configuration.watch.directory).standardizedFileURL
        let outputDirectory = paths.expandUserPath(configuration.output.directory).standardizedFileURL
        guard !overlap(watchDirectory, outputDirectory) else {
            throw ShotdError.invalidConfiguration("watch.directory and output.directory must not contain one another.")
        }
        guard (0...1).contains(configuration.layout.paddingPercent) else {
            throw ShotdError.invalidConfiguration("layout.paddingPercent must be between 0 and 1.")
        }
        guard configuration.layout.minimumPadding >= 0, configuration.layout.maximumPadding >= configuration.layout.minimumPadding else {
            throw ShotdError.invalidConfiguration("layout padding limits are invalid.")
        }
        guard (0...1).contains(configuration.style.shadow.opacity) else {
            throw ShotdError.invalidConfiguration("style.shadow.opacity must be between 0 and 1.")
        }
        guard configuration.image.maximumDimension > 0 else {
            throw ShotdError.invalidConfiguration("image.maximumDimension must be positive.")
        }
        if let quality = configuration.image.quality, !(0...100).contains(quality) {
            throw ShotdError.invalidConfiguration("image.quality must be between 0 and 100.")
        }
        try validate(background: configuration.background, paths: paths, allowDesktop: true)
        if let storage = configuration.storage {
            guard let endpoint = URL(string: storage.endpoint), let scheme = endpoint.scheme?.lowercased(), scheme == "https" || (scheme == "http" && endpoint.host() == "localhost") else {
                throw ShotdError.invalidConfiguration("storage.endpoint must use HTTPS, except for localhost development endpoints.")
            }
            guard !storage.bucket.isEmpty, !storage.credential.isEmpty else {
                throw ShotdError.invalidConfiguration("storage.bucket and storage.credential are required.")
            }
            if let credentials = storage.developmentCredentials {
                guard endpoint.host()?.lowercased() == "localhost", !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
                    throw ShotdError.invalidConfiguration("storage.developmentCredentials are permitted only for localhost and require an access key ID and secret access key.")
                }
            }
            guard (1...604_800).contains(storage.presignExpirationSeconds) else {
                throw ShotdError.invalidConfiguration("storage.presignExpirationSeconds must be between 1 and 604800.")
            }
            guard storage.multipartThresholdMB > 0, storage.multipartPartSizeMB >= 5, storage.multipartPartSizeMB <= 5_120 else {
                throw ShotdError.invalidConfiguration("storage multipart limits are invalid.")
            }
        }
    }

    private static func validateDirectory(_ value: String, name: String, paths: ApplicationPaths) throws {
        guard !value.isEmpty, paths.expandUserPath(value).path.hasPrefix(paths.home.path) else {
            throw ShotdError.invalidConfiguration("\(name) must be a non-empty path inside the current user's home directory.")
        }
    }

    private static func overlap(_ first: URL, _ second: URL) -> Bool {
        let firstPath = first.path.hasSuffix("/") ? first.path : first.path + "/"
        let secondPath = second.path.hasSuffix("/") ? second.path : second.path + "/"
        return first == second || firstPath.hasPrefix(secondPath) || secondPath.hasPrefix(firstPath)
    }

    private static func validate(background: BackgroundConfiguration, paths: ApplicationPaths, allowDesktop: Bool) throws {
        switch background.type {
        case .desktop:
            guard allowDesktop else { throw ShotdError.invalidConfiguration("A desktop background cannot be used as its own fallback.") }
            if background.screen == .specific, (background.display?.isEmpty ?? true) {
                throw ShotdError.invalidConfiguration("background.display is required when background.screen is specific.")
            }
        case .image:
            guard let path = background.path, !path.isEmpty else {
                throw ShotdError.invalidConfiguration("background.path is required for image backgrounds.")
            }
            _ = paths.expandUserPath(path)
        case .solid:
            guard let color = background.color, isColor(color) else {
                throw ShotdError.invalidConfiguration("background.color must be #RRGGBB or #RRGGBBAA for solid backgrounds.")
            }
        case .gradient:
            guard let colors = background.colors, colors.count >= 2, colors.allSatisfy(isColor) else {
                throw ShotdError.invalidConfiguration("Gradient backgrounds require at least two valid colors.")
            }
        }
        if let fallback = background.fallback {
            let converted = BackgroundConfiguration(type: fallback.type, path: fallback.path, fit: fallback.fit ?? background.fit, position: fallback.position ?? background.position, color: fallback.color, angle: fallback.angle, colors: fallback.colors, fallback: nil)
            try validate(background: converted, paths: paths, allowDesktop: false)
        }
    }

    private static func isColor(_ value: String) -> Bool {
        let expression = try? NSRegularExpression(pattern: "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")
        let range = NSRange(value.startIndex..., in: value)
        return expression?.firstMatch(in: value, range: range) != nil
    }
}
