import CryptoKit
import Darwin
import Foundation

public enum ReleaseUpdater {
    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey { case tagName = "tag_name", assets }
    }

    private struct Asset: Decodable {
        let name: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey { case name; case downloadURL = "browser_download_url" }
    }

    public static func check() async throws -> String {
        let release = try await latestRelease()
        if BuildInfo.isNewer(release.tagName) {
            return "Update available: \(release.tagName) (installed: \(BuildInfo.version))"
        }
        return "shotd \(BuildInfo.version) is up to date"
    }

    public static func update(paths: ApplicationPaths) async throws -> String {
        guard FileManager.default.fileExists(atPath: installedBinary(paths: paths).path) else {
            throw ShotdError.filesystem("shotd is not installed. Run the installer or `shotd install` first.")
        }
        let release = try await latestRelease()
        guard BuildInfo.isNewer(release.tagName) else { return "shotd \(BuildInfo.version) is up to date" }

        let architecture = try currentArchitecture()
        let archiveName = BuildInfo.assetName(for: release.tagName, architecture: architecture)
        guard let archive = release.assets.first(where: { $0.name == archiveName }),
              let checksums = release.assets.first(where: { $0.name == "SHA256SUMS" }) else {
            throw ShotdError.unsupported("Release \(release.tagName) does not provide a verified macOS \(architecture) download.")
        }

        let checksumText = try await text(from: checksums.downloadURL)
        guard let expectedChecksum = checksum(for: archiveName, in: checksumText) else {
            throw ShotdError.processing("Release \(release.tagName) is missing a checksum for \(archiveName).")
        }

        let directory = paths.stateDirectory.appending(path: "updates/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiveURL = directory.appending(path: archiveName)
        try await download(archive.downloadURL, to: archiveURL)
        guard try sha256(of: archiveURL) == expectedChecksum else {
            throw ShotdError.processing("Downloaded update failed SHA-256 verification.")
        }

        let unpacked = directory.appending(path: "unpacked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try runTool("/usr/bin/ditto", ["-x", "-k", archiveURL.path, unpacked.path])
        let candidate = unpacked.appending(path: "shotd")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw ShotdError.processing("Release archive does not contain an executable shotd binary.")
        }
        try verifySignedUpgrade(current: installedBinary(paths: paths), candidate: candidate)
        try LaunchAgent.install(paths: paths, executable: candidate)
        return "Updated shotd to \(release.tagName)"
    }

    private static func latestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(BuildInfo.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("shotd/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ShotdError.storage("Unable to check GitHub releases.")
        }
        if response.statusCode == 404 {
            throw ShotdError.unsupported("No published shotd releases are available yet.")
        }
        guard response.statusCode == 200 else { throw ShotdError.storage("Unable to check GitHub releases.") }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private static func text(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ShotdError.storage("Unable to download release checksums.")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func download(_ url: URL, to destination: URL) async throws {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ShotdError.storage("Unable to download the shotd update.")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func checksum(for name: String, in checksums: String) -> String? {
        for line in checksums.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            if fields.count == 2, fields[1].trimmingCharacters(in: CharacterSet(charactersIn: " *")) == name {
                return String(fields[0]).lowercased()
            }
        }
        return nil
    }

    private static func sha256(of file: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: file))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func installedBinary(paths: ApplicationPaths) -> URL {
        paths.applicationSupport.appending(path: "bin/shotd")
    }

    private static func currentArchitecture() throws -> String {
        var system = utsname()
        guard uname(&system) == 0 else { throw ShotdError.filesystem("Unable to determine this Mac's architecture.") }
        let capacity = MemoryLayout.size(ofValue: system.machine)
        let machine = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
        switch machine {
        case "arm64": return "arm64"
        default: throw ShotdError.unsupported("shotd releases currently support Apple silicon Macs only.")
        }
    }

    private static func verifySignedUpgrade(current: URL, candidate: URL) throws {
        try runTool("/usr/bin/codesign", ["--verify", "--strict", current.path])
        try runTool("/usr/bin/codesign", ["--verify", "--strict", candidate.path])
        let currentTeam = try signingTeam(for: current)
        let candidateTeam = try signingTeam(for: candidate)
        guard !currentTeam.isEmpty, currentTeam == candidateTeam else {
            throw ShotdError.processing("Downloaded update is not signed by the same Developer ID team as the installed shotd binary.")
        }
    }

    private static func signingTeam(for executable: URL) throws -> String {
        let output = try runTool("/usr/bin/codesign", ["--display", "--verbose=4", executable.path])
        guard let line = output.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
            throw ShotdError.processing("Unable to verify the shotd signing team.")
        }
        return String(line.dropFirst("TeamIdentifier=".count))
    }

    @discardableResult
    private static func runTool(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ShotdError.processing(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }
}
