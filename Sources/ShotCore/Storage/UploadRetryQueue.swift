import Foundation

public struct PendingUpload: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let localPath: String
    public let objectKey: String
    public let contentType: String
    public var attempts: Int
    public var nextAttempt: Date

    public init(id: UUID = UUID(), localPath: String, objectKey: String, contentType: String, attempts: Int = 0, nextAttempt: Date = .now) {
        self.id = id
        self.localPath = localPath
        self.objectKey = objectKey
        self.contentType = contentType
        self.attempts = attempts
        self.nextAttempt = nextAttempt
    }
}

public struct UploadRetryState: Codable, Sendable {
    public var pending: [PendingUpload]
    public init(pending: [PendingUpload] = []) { self.pending = pending }
}

public actor UploadRetryQueue {
    private let store: StateStore<UploadRetryState>
    private var state: UploadRetryState?

    public init(paths: ApplicationPaths) {
        self.store = StateStore(file: paths.stateDirectory.appending(path: "uploads.json"), defaultValue: .init())
    }

    public func enqueue(_ upload: PendingUpload) async throws {
        var state = try await loaded()
        if !state.pending.contains(where: { $0.localPath == upload.localPath && $0.objectKey == upload.objectKey }) {
            state.pending.append(upload)
            try await save(state)
        }
    }

    public func due(at date: Date = .now) async throws -> [PendingUpload] {
        try await loaded().pending.filter { $0.nextAttempt <= date }
    }

    public func succeeded(_ id: UUID) async throws {
        var state = try await loaded()
        state.pending.removeAll { $0.id == id }
        try await save(state)
    }

    public func failed(_ id: UUID, at date: Date = .now) async throws {
        var state = try await loaded()
        guard let index = state.pending.firstIndex(where: { $0.id == id }) else { return }
        state.pending[index].attempts += 1
        let delay = min(3_600.0, pow(2, Double(min(state.pending[index].attempts, 12))))
        // Deterministic bounded jitter avoids synchronized retries while retaining restart-safe scheduling.
        let jitter = Double(id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 1_000) / 1_000
        state.pending[index].nextAttempt = date.addingTimeInterval(delay * (0.5 + jitter))
        try await save(state)
    }

    private func loaded() async throws -> UploadRetryState {
        if let state { return state }
        let loaded = try await store.load()
        state = loaded
        return loaded
    }

    private func save(_ value: UploadRetryState) async throws {
        try await store.save(value)
        state = value
    }
}
