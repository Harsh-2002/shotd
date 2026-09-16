import Foundation

public struct DeliveryResult: Sendable {
    public let uploaded: Bool
    public let remoteURL: URL?

    public init(uploaded: Bool, remoteURL: URL?) {
        self.uploaded = uploaded
        self.remoteURL = remoteURL
    }
}

public actor StorageDelivery {
    private let retryQueue: UploadRetryQueue
    private let uploadLimiter = UploadLimiter(maximumConcurrentUploads: 2)

    public init(paths: ApplicationPaths) {
        self.retryQueue = UploadRetryQueue(paths: paths)
    }

    public func deliver(file: URL, objectKey: String, contentType: String, configuration: StorageConfiguration?) async -> DeliveryResult {
        guard let configuration else { return DeliveryResult(uploaded: true, remoteURL: nil) }
        do {
            let remoteURL = try await upload(file: file, objectKey: objectKey, contentType: contentType, configuration: configuration)
            return DeliveryResult(uploaded: true, remoteURL: remoteURL)
        } catch {
            do {
                try await retryQueue.enqueue(.init(localPath: file.path, objectKey: objectKey, contentType: contentType))
            } catch {
                Log.storage.error("Unable to persist a failed upload: \(error.localizedDescription, privacy: .public)")
            }
            Log.storage.error("Upload queued for retry: \(error.localizedDescription, privacy: .public)")
            return DeliveryResult(uploaded: false, remoteURL: nil)
        }
    }

    public func enqueue(_ upload: PendingUpload) async throws {
        try await retryQueue.enqueue(upload)
    }

    public func retryDueUploads(configuration: StorageConfiguration?) async {
        guard let configuration else { return }
        do {
            let pendingUploads = try await retryQueue.due()
            await withTaskGroup(of: Void.self) { group in
                for pending in pendingUploads {
                    group.addTask { [self] in
                        await retry(pending, configuration: configuration)
                    }
                }
            }
        } catch {
            Log.storage.error("Unable to process upload retry state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upload(file: URL, objectKey: String, contentType: String, configuration: StorageConfiguration) async throws -> URL {
        await uploadLimiter.acquire()
        do {
            let remoteURL = try await performUpload(file: file, objectKey: objectKey, contentType: contentType, configuration: configuration)
            await uploadLimiter.release()
            return remoteURL
        } catch {
            await uploadLimiter.release()
            throw error
        }
    }

    private func retry(_ pending: PendingUpload, configuration: StorageConfiguration) async {
        let file = URL(filePath: pending.localPath)
        do {
            guard FileManager.default.fileExists(atPath: file.path) else {
                try await retryQueue.succeeded(pending.id)
                return
            }
            _ = try await upload(file: file, objectKey: pending.objectKey, contentType: pending.contentType, configuration: configuration)
            if pending.deleteSourceAfterUpload,
               let sourcePath = pending.sourcePath,
               let sourceFingerprint = pending.sourceFingerprint {
                let source = URL(filePath: sourcePath)
                guard (try? FileStabilizer().fingerprint(source)) == sourceFingerprint else {
                    try await retryQueue.succeeded(pending.id)
                    return
                }
                try FileManager.default.removeItem(at: source)
            }
            try await retryQueue.succeeded(pending.id)
        } catch {
            do {
                try await retryQueue.failed(pending.id)
            } catch {
                Log.storage.error("Unable to persist a failed retry: \(error.localizedDescription, privacy: .public)")
            }
            Log.storage.error("Retry failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performUpload(file: URL, objectKey: String, contentType: String, configuration: StorageConfiguration) async throws -> URL {
        let credentials = try CredentialStore.get(for: configuration)
        let client = S3Client(configuration: configuration, credentials: credentials)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if size >= configuration.multipartThresholdMB * 1_024 * 1_024 {
            try await MultipartUploader().upload(file: file, key: objectKey, contentType: contentType, client: client, partSizeMB: configuration.multipartPartSizeMB)
        } else {
            try await client.put(data: Data(contentsOf: file), key: objectKey, contentType: contentType)
        }
        return try await client.remoteURL(for: objectKey)
    }
}

private actor UploadLimiter {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maximumConcurrentUploads: Int) {
        availablePermits = maximumConcurrentUploads
    }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            availablePermits += 1
        }
    }
}
