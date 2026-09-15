import Foundation

public struct FileStabilizer: Sendable {
    public let debounce: Duration
    public let maximumAttempts: Int

    public init(debounce: Duration = .milliseconds(100), maximumAttempts: Int = 20) {
        self.debounce = debounce
        self.maximumAttempts = maximumAttempts
    }

    public func waitUntilStable(_ url: URL) async throws -> SourceFingerprint {
        var previous: SourceFingerprint?
        for _ in 0..<maximumAttempts {
            let current = try fingerprint(url)
            if current == previous { return current }
            previous = current
            try await Task.sleep(for: debounce)
        }
        throw ShotdError.processing("Source did not stabilize before timeout: \(url.lastPathComponent).")
    }

    public func fingerprint(_ url: URL) throws -> SourceFingerprint {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw ShotdError.filesystem("Unable to read source metadata for \(url.lastPathComponent).")
        }
        guard let size = attributes[.size] as? NSNumber,
              let modification = attributes[.modificationDate] as? Date else {
            throw ShotdError.filesystem("Source metadata is incomplete for \(url.lastPathComponent).")
        }
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        return SourceFingerprint(path: url.standardizedFileURL.path, inode: inode, size: size.uint64Value, modificationTime: modification)
    }
}
