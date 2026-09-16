import Darwin
import Foundation

public enum PersistentStateError: LocalizedError {
    case unsupportedSchema(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(found, supported):
            "Persistent state schema \(found) is newer than supported schema \(supported). Update shotd before continuing."
        }
    }
}

public final class StateStore<Value: Codable & Sendable>: @unchecked Sendable {
    private let file: URL
    private let defaultValue: Value

    public init(file: URL, defaultValue: Value) {
        self.file = file
        self.defaultValue = defaultValue
    }

    public func load() throws -> Value {
        try withLock { try loadUnlocked() }
    }

    public func update<Result>(_ mutation: (inout Value) throws -> Result) throws -> Result {
        try withLock {
            var value = try loadUnlocked()
            let result = try mutation(&value)
            try saveUnlocked(value)
            return result
        }
    }

    public func save(_ value: Value) throws {
        try withLock { try saveUnlocked(value) }
    }

    private func loadUnlocked() throws -> Value {
        guard FileManager.default.fileExists(atPath: file.path) else { return defaultValue }
        do {
            return try JSONDecoder().decode(Value.self, from: Data(contentsOf: file))
        } catch let error as PersistentStateError {
            throw error
        } catch {
            let corrupt = file.deletingPathExtension().appendingPathExtension("corrupt-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: file, to: corrupt)
            Log.storage.error("Ignoring corrupt persistent state at \(self.file.path, privacy: .private)")
            return defaultValue
        }
    }

    private func saveUnlocked(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try AtomicWriter.write(encoder.encode(value), to: file)
    }

    private func withLock<Result>(_ operation: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lockFile = file.appendingPathExtension("lock")
        let descriptor = open(lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ShotdError.filesystem("Unable to lock persistent state at \(file.path).") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw ShotdError.filesystem("Unable to lock persistent state at \(file.path).") }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
