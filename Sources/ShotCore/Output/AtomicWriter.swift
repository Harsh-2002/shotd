import Foundation

public enum AtomicWriter {
    public static func write(_ data: Data, to destination: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: [.atomic])
            try synchronize(temporary)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary, backupItemName: nil, options: [])
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw ShotdError.filesystem("Unable to atomically write \(destination.path): \(error.localizedDescription)")
        }
    }

    private static func synchronize(_ file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    public static func replaceFile(at temporary: URL, with destination: URL, fileManager: FileManager = .default) throws {
        do {
            try synchronize(temporary)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary, backupItemName: nil, options: [])
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw ShotdError.filesystem("Unable to atomically publish \(destination.path): \(error.localizedDescription)")
        }
    }
}
