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
    public var records: [String: ProcessedSource]

    public init(records: [String: ProcessedSource] = [:]) {
        self.records = records
    }

    public func hasProcessed(_ fingerprint: SourceFingerprint) -> Bool {
        records[fingerprint.path]?.fingerprint == fingerprint
    }
}
