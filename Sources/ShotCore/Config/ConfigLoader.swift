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
        guard fileManager.fileExists(atPath: paths.configuration.path)
            || fileManager.fileExists(atPath: paths.legacyConfiguration.path) else {
            let configuration = ShotdConfiguration()
            try write(configuration)
            return configuration
        }
        return try load()
    }

    public func load() throws -> ShotdConfiguration {
        let fileManager = FileManager.default
        let requiresMigration = !fileManager.fileExists(atPath: paths.configuration.path)
            && fileManager.fileExists(atPath: paths.legacyConfiguration.path)
        let configuration = try loadUnvalidated()
        try ConfigValidator.validate(configuration, paths: paths)
        if requiresMigration {
            try write(configuration, removingLegacy: true)
        }
        return configuration
    }

    public func loadUnvalidated() throws -> ShotdConfiguration {
        let source = FileManager.default.fileExists(atPath: paths.configuration.path)
            ? paths.configuration
            : paths.legacyConfiguration
        let data = try Data(contentsOf: source)
        let configuration: ShotdConfiguration
        do {
            configuration = try decoder.decode(ShotdConfiguration.self, from: data)
        } catch {
            throw ShotdError.invalidConfiguration("Unable to decode \(source.path): \(error.localizedDescription)")
        }
        return configuration
    }

    public func write(_ configuration: ShotdConfiguration) throws {
        try write(configuration, removingLegacy: false)
    }

    public func finalizeLegacyMigration() throws {
        guard FileManager.default.fileExists(atPath: paths.legacyConfiguration.path) else { return }
        let persisted = try decoder.decode(ShotdConfiguration.self, from: Data(contentsOf: paths.configuration))
        try ConfigValidator.validate(persisted, paths: paths)
        try FileManager.default.removeItem(at: paths.legacyConfiguration)
    }

    private func write(_ configuration: ShotdConfiguration, removingLegacy: Bool) throws {
        try ConfigValidator.validate(configuration, paths: paths)
        let data = try encoder.encode(configuration)
        try AtomicWriter.write(data, to: paths.configuration)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.configuration.path)
        let persisted = try decoder.decode(ShotdConfiguration.self, from: Data(contentsOf: paths.configuration))
        try ConfigValidator.validate(persisted, paths: paths)
        if removingLegacy, FileManager.default.fileExists(atPath: paths.legacyConfiguration.path) {
            try FileManager.default.removeItem(at: paths.legacyConfiguration)
        }
    }
}
