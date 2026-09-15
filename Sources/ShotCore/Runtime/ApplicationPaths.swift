import Foundation

public struct ApplicationPaths: Sendable {
    public let home: URL
    public let applicationSupport: URL
    public let configuration: URL
    public let legacyConfiguration: URL
    public let stateDirectory: URL
    public let logsDirectory: URL
    public let launchAgentsDirectory: URL

    public init(fileManager: FileManager = .default) throws {
        guard let home = fileManager.homeDirectoryForCurrentUser as URL? else {
            throw ShotdError.filesystem("Unable to resolve the current user's home directory.")
        }
        self.init(home: home)
    }

    public init(home: URL) {
        self.home = home
        self.applicationSupport = home.appending(path: "Library/Application Support/shotd", directoryHint: .isDirectory)
        self.configuration = applicationSupport.appending(path: "settings.json", directoryHint: .notDirectory)
        self.legacyConfiguration = applicationSupport.appending(path: "config.json", directoryHint: .notDirectory)
        self.stateDirectory = applicationSupport.appending(path: "state", directoryHint: .isDirectory)
        self.logsDirectory = home.appending(path: "Library/Logs/shotd", directoryHint: .isDirectory)
        self.launchAgentsDirectory = home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
    }

    public func createRequiredDirectories(fileManager: FileManager = .default) throws {
        for directory in [applicationSupport, stateDirectory, logsDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    public func expandUserPath(_ value: String) -> URL {
        if value == "~" {
            return home
        }
        if value.hasPrefix("~/") {
            return home.appending(path: String(value.dropFirst(2)))
        }
        return URL(filePath: value)
    }
}
