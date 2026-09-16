import Foundation

public struct PendingUpload: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let localPath: String
    public let objectKey: String
    public let contentType: String
    public let sourcePath: String?
    public let sourceFingerprint: SourceFingerprint?
    public let deleteSourceAfterUpload: Bool
    public var attempts: Int
    public var nextAttempt: Date

    public init(
        id: UUID = UUID(),
        localPath: String,
        objectKey: String,
        contentType: String,
        sourcePath: String? = nil,
        sourceFingerprint: SourceFingerprint? = nil,
        deleteSourceAfterUpload: Bool = false,
        attempts: Int = 0,
        nextAttempt: Date = .now
    ) {
        self.id = id
        self.localPath = localPath
        self.objectKey = objectKey
        self.contentType = contentType
        self.sourcePath = sourcePath
        self.sourceFingerprint = sourceFingerprint
        self.deleteSourceAfterUpload = deleteSourceAfterUpload
        self.attempts = attempts
        self.nextAttempt = nextAttempt
    }

    private enum CodingKeys: String, CodingKey {
        case id, localPath, objectKey, contentType, sourcePath, sourceFingerprint, deleteSourceAfterUpload, attempts, nextAttempt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            localPath: try values.decode(String.self, forKey: .localPath),
            objectKey: try values.decode(String.self, forKey: .objectKey),
            contentType: try values.decode(String.self, forKey: .contentType),
            sourcePath: try values.decodeIfPresent(String.self, forKey: .sourcePath),
            sourceFingerprint: try values.decodeIfPresent(SourceFingerprint.self, forKey: .sourceFingerprint),
            deleteSourceAfterUpload: try values.decodeIfPresent(Bool.self, forKey: .deleteSourceAfterUpload) ?? false,
            attempts: try values.decodeIfPresent(Int.self, forKey: .attempts) ?? 0,
            nextAttempt: try values.decodeIfPresent(Date.self, forKey: .nextAttempt) ?? .now
        )
    }
}

public struct UploadRetryState: Codable, Sendable {
    public var pending: [PendingUpload]
    public init(pending: [PendingUpload] = []) { self.pending = pending }
}

public actor UploadRetryQueue {
    private let store: StateStore<UploadRetryState>

    public init(paths: ApplicationPaths) {
        self.store = StateStore(file: paths.stateDirectory.appending(path: "uploads.json"), defaultValue: .init())
    }

    public func enqueue(_ upload: PendingUpload) async throws {
        try store.update { state in
            if !state.pending.contains(where: { $0.localPath == upload.localPath && $0.objectKey == upload.objectKey }) {
                state.pending.append(upload)
            }
        }
    }

    public func due(at date: Date = .now) async throws -> [PendingUpload] {
        try store.load().pending.filter { $0.nextAttempt <= date }
    }

    public func succeeded(_ id: UUID) async throws {
        try store.update { $0.pending.removeAll { $0.id == id } }
    }

    public func failed(_ id: UUID, at date: Date = .now) async throws {
        try store.update { state in
            guard let index = state.pending.firstIndex(where: { $0.id == id }) else { return }
            state.pending[index].attempts += 1
            let delay = min(3_600.0, pow(2, Double(min(state.pending[index].attempts, 12))))
            // Deterministic bounded jitter avoids synchronized retries while retaining restart-safe scheduling.
            let jitter = Double(id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 1_000) / 1_000
            state.pending[index].nextAttempt = date.addingTimeInterval(delay * (0.5 + jitter))
        }
    }
}
