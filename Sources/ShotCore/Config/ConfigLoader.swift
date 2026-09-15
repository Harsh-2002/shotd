import Foundation

public actor ConfigLoader {
    public let paths: ApplicationPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: ApplicationPaths) {
        self.paths = paths
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func loadOrCreateDefault() throws -> ShotdConfiguration {
        try paths.createRequiredDirectories()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.configuration.path) else {
            let configuration = ShotdConfiguration()
            try write(configuration)
            return configuration
        }
        return try load()
    }

    public func load() throws -> ShotdConfiguration {
        let configuration = try loadUnvalidated()
        try ConfigValidator.validate(configuration, paths: paths)
        return configuration
    }

    public func loadUnvalidated() throws -> ShotdConfiguration {
        let data = try Data(contentsOf: paths.configuration)
        let configuration: ShotdConfiguration
        do {
            configuration = try decoder.decode(ShotdConfiguration.self, from: data)
        } catch {
            throw ShotdError.invalidConfiguration("Unable to decode \(paths.configuration.path): \(error.localizedDescription)")
        }
        return configuration
    }

    public func write(_ configuration: ShotdConfiguration) throws {
        try ConfigValidator.validate(configuration, paths: paths)
        let data = try encoder.encode(configuration)
        try AtomicWriter.write(data, to: paths.configuration)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.configuration.path)
    }
}
