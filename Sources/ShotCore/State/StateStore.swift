import Foundation

public actor StateStore<Value: Codable & Sendable> {
    private let file: URL
    private let defaultValue: Value
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    public init(file: URL, defaultValue: Value) {
        self.file = file
        self.defaultValue = defaultValue
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    public func load() throws -> Value {
        guard FileManager.default.fileExists(atPath: file.path) else { return defaultValue }
        do {
            return try decoder.decode(Value.self, from: Data(contentsOf: file))
        } catch {
            let corrupt = file.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: corrupt)
            Log.storage.error("Ignoring corrupt persistent state at \(self.file.path, privacy: .private)")
            return defaultValue
        }
    }

    public func save(_ value: Value) throws {
        try AtomicWriter.write(encoder.encode(value), to: file)
    }
}
