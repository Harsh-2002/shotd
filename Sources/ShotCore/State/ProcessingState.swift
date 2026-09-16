import Foundation

public struct SourceFingerprint: Codable, Hashable, Sendable {
    public var path: String
    public var inode: UInt64
    public var size: UInt64
    public var modificationTime: Date

    public init(path: String, inode: UInt64, size: UInt64, modificationTime: Date) {
        self.path = path
        self.inode = inode
        self.size = size
        self.modificationTime = modificationTime
    }
}

public struct ProcessedSource: Codable, Equatable, Sendable {
    public var fingerprint: SourceFingerprint
    public var outputPath: String
    public var objectKey: String?
    public var processedAt: Date

    public init(fingerprint: SourceFingerprint, outputPath: String, objectKey: String? = nil, processedAt: Date = .now) {
        self.fingerprint = fingerprint
        self.outputPath = outputPath
        self.objectKey = objectKey
        self.processedAt = processedAt
    }
}

public struct ProcessingState: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var watchDirectory: String?
    public var observed: [String: SourceFingerprint]
    public var pending: [String: SourceFingerprint]
    public var pendingDeletions: [String: SourceFingerprint]
    public var records: [String: ProcessedSource]
    public var requiresBaseline: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        watchDirectory: String? = nil,
        observed: [String: SourceFingerprint] = [:],
        pending: [String: SourceFingerprint] = [:],
        pendingDeletions: [String: SourceFingerprint] = [:],
        records: [String: ProcessedSource] = [:],
        requiresBaseline: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.watchDirectory = watchDirectory
        self.observed = observed
        self.pending = pending
        self.pendingDeletions = pendingDeletions
        self.records = records
        self.requiresBaseline = requiresBaseline
    }

    public func hasProcessed(_ fingerprint: SourceFingerprint) -> Bool {
        records[fingerprint.path]?.fingerprint == fingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, watchDirectory, observed, pending, pendingDeletions, records, requiresBaseline
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
        if let version, version > Self.currentSchemaVersion {
            throw PersistentStateError.unsupportedSchema(found: version, supported: Self.currentSchemaVersion)
        }
        self.init(
            schemaVersion: Self.currentSchemaVersion,
            watchDirectory: try values.decodeIfPresent(String.self, forKey: .watchDirectory),
            observed: try values.decodeIfPresent([String: SourceFingerprint].self, forKey: .observed) ?? [:],
            pending: try values.decodeIfPresent([String: SourceFingerprint].self, forKey: .pending) ?? [:],
            pendingDeletions: try values.decodeIfPresent([String: SourceFingerprint].self, forKey: .pendingDeletions) ?? [:],
            records: try values.decodeIfPresent([String: ProcessedSource].self, forKey: .records) ?? [:],
            // Legacy state has completion records but no full directory inventory, so migration must baseline safely.
            requiresBaseline: version == Self.currentSchemaVersion
                ? try values.decodeIfPresent(Bool.self, forKey: .requiresBaseline) ?? true
                : true
        )
    }
}
