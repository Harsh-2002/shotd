import Foundation

public struct MultipartUploader: Sendable {
    public init() {}

    public func upload(file: URL, key: String, contentType: String, client: S3Client, partSizeMB: Int) async throws {
        let partSize = partSizeMB * 1_024 * 1_024
        guard partSize >= 5 * 1_024 * 1_024 else { throw ShotdError.invalidConfiguration("S3 multipart part size must be at least 5 MB.") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let uploadID = try await client.createMultipartUpload(key: key, contentType: contentType)
        var parts: [(number: Int, eTag: String)] = []
        do {
            var part = 1
            while let data = try handle.read(upToCount: partSize), !data.isEmpty {
                guard part <= 10_000 else { throw ShotdError.storage("S3 multipart upload exceeds 10,000 parts.") }
                parts.append((part, try await client.uploadPart(data: data, key: key, uploadID: uploadID, partNumber: part)))
                part += 1
            }
            guard !parts.isEmpty else { throw ShotdError.storage("Cannot multipart upload an empty file.") }
            try await client.completeMultipartUpload(key: key, uploadID: uploadID, parts: parts)
        } catch {
            try? await client.abortMultipartUpload(key: key, uploadID: uploadID)
            throw error
        }
    }
}
