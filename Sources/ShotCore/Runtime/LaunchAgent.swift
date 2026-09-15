import Darwin
import Foundation

public enum LaunchAgent {
    public static let label = "io.shotd"

    public static func install(paths: ApplicationPaths, executable: URL) throws {
        guard getuid() != 0 else {
            throw ShotdError.invalidArguments("shotd must be installed by the logged-in macOS user, not with sudo.")
        }
        try paths.createRequiredDirectories()
        let fileManager = FileManager.default
        let source = executable.standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.isExecutableFile(atPath: source.path) else {
            throw ShotdError.filesystem("The shotd executable is missing or is not executable: \(source.path)")
        }
        let binaryDirectory = paths.applicationSupport.appending(path: "bin", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: binaryDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let binary = binaryDirectory.appending(path: "shotd")
        let replacementNeeded = binary.standardizedFileURL.resolvingSymlinksInPath() != source
        let staged = binaryDirectory.appending(path: ".shotd-\(UUID().uuidString).tmp")
        if replacementNeeded {
            try fileManager.copyItem(at: source, to: staged)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
        }
        try fileManager.createDirectory(at: paths.launchAgentsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let plist = plistURL(paths: paths)
        let content: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary.path, "run"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 10,
            "ProcessType": "Background",
            "StandardOutPath": paths.logsDirectory.appending(path: "daemon.log").path,
            "StandardErrorPath": paths.logsDirectory.appending(path: "daemon-error.log").path
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: content, format: .xml, options: 0)
        _ = try runLaunchctl(["bootout", domain(paths), plist.path], allowingFailure: true)
        let backup = binaryDirectory.appending(path: "shotd.previous")
        do {
            if replacementNeeded {
                try? fileManager.removeItem(at: backup)
                if fileManager.fileExists(atPath: binary.path) {
                    _ = try fileManager.replaceItemAt(binary, withItemAt: staged, backupItemName: backup.lastPathComponent, options: [])
                } else {
                    try fileManager.moveItem(at: staged, to: binary)
                }
            }
            try AtomicWriter.write(data, to: plist)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plist.path)
            let result = try runLaunchctl(["bootstrap", domain(paths), plist.path])
            guard result.status == 0 else { throw ShotdError.filesystem("Unable to install LaunchAgent: \(result.output)") }
            try? fileManager.removeItem(at: backup)
        } catch {
            try? fileManager.removeItem(at: staged)
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: binary)
                try? fileManager.moveItem(at: backup, to: binary)
                _ = try? runLaunchctl(["bootstrap", domain(paths), plist.path], allowingFailure: true)
            }
            throw error
        }
    }

    public static func uninstall(paths: ApplicationPaths) throws {
        _ = try runLaunchctl(["bootout", domain(paths), plistURL(paths: paths).path], allowingFailure: true)
        try? FileManager.default.removeItem(at: plistURL(paths: paths))
        try? FileManager.default.removeItem(at: paths.applicationSupport.appending(path: "bin/shotd"))
    }

    public static func start(paths: ApplicationPaths) throws {
        let plist = plistURL(paths: paths)
        guard FileManager.default.fileExists(atPath: plist.path) else { throw ShotdError.filesystem("LaunchAgent is not installed.") }
        let result = try runLaunchctl(["bootstrap", domain(paths), plist.path], allowingFailure: true)
        if result.status != 0 && !result.output.localizedCaseInsensitiveContains("already bootstrapped") {
            throw ShotdError.filesystem("Unable to start LaunchAgent: \(result.output)")
        }
        let kickstart = try runLaunchctl(["kickstart", "-k", "\(domain(paths))/\(label)"])
        guard kickstart.status == 0 else { throw ShotdError.filesystem("Unable to start LaunchAgent: \(kickstart.output)") }
    }

    public static func stop(paths: ApplicationPaths) throws {
        let result = try runLaunchctl(["bootout", domain(paths), plistURL(paths: paths).path], allowingFailure: true)
        guard result.status == 0 || result.output.localizedCaseInsensitiveContains("no such process") else {
            throw ShotdError.filesystem("Unable to stop LaunchAgent: \(result.output)")
        }
    }

    public static func restart(paths: ApplicationPaths) throws {
        try stop(paths: paths)
        try start(paths: paths)
    }

    public static func status(paths: ApplicationPaths) -> String {
        guard FileManager.default.fileExists(atPath: plistURL(paths: paths).path) else { return "not installed" }
        guard let result = try? runLaunchctl(["print", "\(domain(paths))/\(label)"], allowingFailure: true) else { return "installed (status unavailable)" }
        return result.status == 0 ? "running" : "installed but stopped"
    }

    private static func domain(_ paths: ApplicationPaths) -> String { "gui/\(getuid())" }
    private static func plistURL(paths: ApplicationPaths) -> URL { paths.launchAgentsDirectory.appending(path: "\(label).plist") }

    private static func runLaunchctl(_ arguments: [String], allowingFailure: Bool = false) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw ShotdError.filesystem("Unable to run launchctl: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowingFailure && process.terminationStatus != 0 {
            throw ShotdError.filesystem(text.isEmpty ? "launchctl failed." : text)
        }
        return (process.terminationStatus, text)
    }
}
