import Foundation

public actor Daemon {
    private struct VideoJob: Sendable {
        let source: URL
        let configuration: ShotdConfiguration
        let fingerprint: SourceFingerprint
    }
    private let paths: ApplicationPaths
    private let loader: ConfigLoader
    private let stabilizer = FileStabilizer()
    private let tracker: FileTracker
    private let storageDelivery: StorageDelivery
    private var configuration: ShotdConfiguration?
    private var inboxWatcher: DirectoryWatcher?
    private var configWatcher: DirectoryWatcher?
    private var pendingImages: [URL] = []
    private var imageProcessing = false
    private var imageTask: Task<Void, Never>?
    private var pendingVideos: [VideoJob] = []
    private var videoProcessing = false
    private var videoTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var running = false
    private var starting = false
    private var reloading = false
    private var reloadRequested = false
    private var lifecycleGeneration = 0
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    public init(paths: ApplicationPaths) {
        self.paths = paths
        self.loader = ConfigLoader(paths: paths)
        self.tracker = FileTracker(paths: paths)
        self.storageDelivery = StorageDelivery(paths: paths)
    }

    public func start() async throws {
        guard !running, !starting else { return }
        starting = true
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        defer { starting = false }
        let loaded = try await loader.loadOrCreateDefault()
        guard generation == lifecycleGeneration else { throw CancellationError() }
        let inbox = paths.expandUserPath(loaded.watch.directory).standardizedFileURL.resolvingSymlinksInPath()
        let output = paths.expandUserPath(loaded.output.directory).standardizedFileURL.resolvingSymlinksInPath()
        guard inbox != output else { throw ShotdError.invalidConfiguration("watch.directory and output.directory must be different.") }
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let inboxWatcher = makeInboxWatcher(directory: inbox)
        let configurationFile = paths.configuration.standardizedFileURL
        let configWatcher = DirectoryWatcher(directory: paths.applicationSupport) { [weak self] files in
            guard files.contains(where: { $0.standardizedFileURL == configurationFile }) else { return }
            Task { await self?.reloadConfiguration() }
        }
        do {
            try await reconcile(try inboxWatcher.currentFiles(), directory: inbox)
            guard generation == lifecycleGeneration else { throw CancellationError() }
            configuration = loaded
            try inboxWatcher.start()
            self.inboxWatcher = inboxWatcher
            running = true
            try configWatcher.start()
            self.configWatcher = configWatcher
            try await scan(directory: inbox)
            await retryPendingDeletions()
        } catch {
            inboxWatcher.stop()
            configWatcher.stop()
            self.inboxWatcher = nil
            self.configWatcher = nil
            configuration = nil
            pendingImages.removeAll()
            pendingVideos.removeAll()
            running = false
            throw error
        }
        await prewarmBackground(configuration: loaded)
        guard running, generation == lifecycleGeneration else { return }
        retryTask = Task { [weak self] in
            await self?.startDeliveryIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.startDeliveryIfNeeded()
            }
        }
        Log.info("shotd is watching \(inbox.path)")
    }

    public func stop() async {
        if starting { lifecycleGeneration += 1 }
        guard running || imageTask != nil || videoTask != nil || deliveryTask != nil else { return }
        running = false
        inboxWatcher?.stop()
        configWatcher?.stop()
        inboxWatcher = nil
        configWatcher = nil
        retryTask?.cancel()
        retryTask = nil
        deliveryTask?.cancel()
        let activeImage = imageTask
        let activeVideo = videoTask
        let activeDelivery = deliveryTask
        await activeImage?.value
        await activeVideo?.value
        await activeDelivery?.value
        imageTask = nil
        videoTask = nil
        deliveryTask = nil
        pendingImages.removeAll()
        pendingVideos.removeAll()
        let waiters = stopWaiters
        stopWaiters.removeAll()
        waiters.forEach { $0.resume() }
        Log.info("shotd stopped")
    }

    public func waitForever() async {
        guard running else { return }
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if running {
                    stopWaiters.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        }, onCancel: {
            Task { await self.stop() }
        })
    }

    private func reloadConfiguration() async {
        guard !reloading else {
            reloadRequested = true
            return
        }
        reloading = true
        defer {
            reloading = false
            if reloadRequested {
                reloadRequested = false
                Task { await self.reloadConfiguration() }
            }
        }
        do {
            guard running else { return }
            let loaded = try await loader.load()
            guard running else { return }
            let inbox = paths.expandUserPath(loaded.watch.directory).standardizedFileURL.resolvingSymlinksInPath()
            let output = paths.expandUserPath(loaded.output.directory).standardizedFileURL.resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

            let currentInbox = configuration.map { paths.expandUserPath($0.watch.directory).standardizedFileURL.resolvingSymlinksInPath() }
            if inbox != currentInbox {
                let replacement = makeInboxWatcher(directory: inbox)
                let startupFiles = try replacement.currentFiles()
                try replacement.start()
                do {
                    try await reconcile(startupFiles, directory: inbox)
                } catch {
                    replacement.stop()
                    throw error
                }
                guard running else {
                    replacement.stop()
                    return
                }
                let previous = inboxWatcher
                inboxWatcher = replacement
                configuration = loaded
                previous?.stop()
                do {
                    try await scan(directory: inbox)
                } catch {
                    Log.processing.error("Unable to reconcile the new watch directory: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                configuration = loaded
            }
            await prewarmBackground(configuration: loaded)
            Log.info("Configuration reloaded")
        } catch {
            // The active configuration remains untouched after an invalid reload.
            Log.configuration.error("Configuration reload rejected: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func retryDueUploads() async {
        guard running, let configuration else { return }
        await storageDelivery.retryDueUploads(configuration: configuration.storage)
        await retryPendingDeletions()
    }

    private func startDeliveryIfNeeded() {
        guard running, deliveryTask == nil else { return }
        deliveryTask = Task { [weak self] in
            await self?.runDeliveryPass()
        }
    }

    private func runDeliveryPass() async {
        await retryDueUploads()
        deliveryTask = nil
    }

    private func makeInboxWatcher(directory: URL) -> DirectoryWatcher {
        DirectoryWatcher(directory: directory) { [weak self] _ in
            Task { await self?.handle(directory: directory) }
        }
    }

    private func handle(directory: URL) async {
        guard running,
              let configuration,
              paths.expandUserPath(configuration.watch.directory).standardizedFileURL.resolvingSymlinksInPath() == directory else { return }
        do {
            try await scan(directory: directory)
        } catch {
            Log.processing.error("Unable to reconcile watched files: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func prewarmBackground(configuration: ShotdConfiguration) async {
        await MainActor.run {
            guard let dimensions = try? MediaDimensions(width: 1, height: 1) else { return }
            _ = try? BackgroundResolver(paths: paths).resolve(configuration.background, sourceDimensions: dimensions)
        }
    }

    private func enqueue(_ files: [URL]) {
        let ordered = files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
            return left == right ? $0.path < $1.path : left < right
        }
        for file in ordered where !pendingImages.contains(file) {
            pendingImages.append(file)
        }
        startNextImageIfNeeded()
    }

    private func reconcile(_ files: [URL], directory: URL) async throws {
        let supported = files.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
        let fingerprints = try supported.map { try stabilizer.fingerprint($0) }
        let pending = try await tracker.reconcile(directory: directory, fingerprints: fingerprints)
        enqueue(pending.map { URL(filePath: $0.path) })
    }

    private func scan(directory: URL) async throws {
        guard let watcher = inboxWatcher else { return }
        try await reconcile(try watcher.currentFiles(), directory: directory)
    }

    private static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "avif", "tif", "tiff", "mov", "mp4"]

    private func startNextImageIfNeeded() {
        guard running, !imageProcessing, !pendingImages.isEmpty, let configuration else { return }
        imageProcessing = true
        let source = pendingImages.removeFirst()
        imageTask = Task { await processImage(source, configuration: configuration) }
    }

    private func processImage(_ source: URL, configuration: ShotdConfiguration) async {
        defer {
            imageProcessing = false
            imageTask = nil
            startNextImageIfNeeded()
        }
        var fingerprint: SourceFingerprint?
        do {
            let stableFingerprint = try await stabilizer.waitUntilStable(source)
            fingerprint = stableFingerprint
            guard try await tracker.shouldProcess(stableFingerprint) else { return }
            switch try await MediaInspector.inspect(at: source) {
            case .image:
                var processingConfiguration = configuration
                if configuration.source.retention == .replaceAfterSuccess {
                    processingConfiguration.image.format = .preserve
                    processingConfiguration.image.compression = nil
                }
                let result = try await MainActor.run {
                    try StillCaptureProcessor(paths: paths).process(sourceURL: source, configuration: processingConfiguration)
                }
                let output = OutputManager(directory: paths.expandUserPath(configuration.output.directory))
                let key = output.objectKey(for: source, kind: .image, format: result.format, prefix: configuration.storage?.paths.images ?? "screenshots")
                try await queueDelivery(file: result.outputURL, source: source, fingerprint: stableFingerprint, objectKey: key, contentType: result.format.mimeType, configuration: configuration)
                if configuration.source.retention == .replaceAfterSuccess {
                    if try await replaceSource(result.outputURL, source: source, fingerprint: stableFingerprint, objectKey: key) {
                        Log.info("Processed and replaced screenshot: \(source.lastPathComponent)")
                    } else {
                        Log.info("Processed screenshot; edited source was kept: \(source.lastPathComponent) -> \(result.outputURL.path)")
                    }
                } else {
                    let deleteLocally = configuration.source.retention == .deleteAfterSuccess && !configuration.source.deleteRequiresUpload
                    try await tracker.processed(.init(fingerprint: stableFingerprint, outputPath: result.outputURL.path, objectKey: key), deleteSource: deleteLocally)
                    if deleteLocally { await deleteSourceIfReady(stableFingerprint) }
                    Log.info("Processed screenshot: \(source.lastPathComponent) -> \(result.outputURL.path)")
                }
                triggerDelivery()
                return
            case .video:
                var videoConfiguration = configuration
                if configuration.source.retention == .replaceAfterSuccess {
                    videoConfiguration.video.format = source.pathExtension.lowercased() == "mov" ? .mov : .mp4
                }
                pendingVideos.append(.init(source: source, configuration: videoConfiguration, fingerprint: stableFingerprint))
                startNextVideoIfNeeded()
                return
            }
        } catch {
            if let fingerprint { await tracker.failed(fingerprint) }
            Log.processing.error("Failed to process \(source.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startNextVideoIfNeeded() {
        guard running, !videoProcessing, !pendingVideos.isEmpty else { return }
        videoProcessing = true
        let job = pendingVideos.removeFirst()
        videoTask = Task { await processVideo(job) }
    }

    private func processVideo(_ job: VideoJob) async {
        defer {
            videoProcessing = false
            videoTask = nil
            startNextVideoIfNeeded()
        }
        do {
            let result = try await VideoProcessor(paths: paths).process(sourceURL: job.source, configuration: job.configuration)
            let output = OutputManager(directory: paths.expandUserPath(job.configuration.output.directory))
            let key = output.objectKey(for: job.source, kind: .video, format: result.format, prefix: job.configuration.storage?.paths.videos ?? "recordings")
            try await queueDelivery(file: result.outputURL, source: job.source, fingerprint: job.fingerprint, objectKey: key, contentType: result.format.mimeType, configuration: job.configuration)
            if job.configuration.source.retention == .replaceAfterSuccess {
                if try await replaceSource(result.outputURL, source: job.source, fingerprint: job.fingerprint, objectKey: key) {
                    Log.info("Processed and replaced recording: \(job.source.lastPathComponent)")
                } else {
                    Log.info("Processed recording; edited source was kept: \(job.source.lastPathComponent) -> \(result.outputURL.path)")
                }
            } else {
                let deleteLocally = job.configuration.source.retention == .deleteAfterSuccess && !job.configuration.source.deleteRequiresUpload
                try await tracker.processed(.init(fingerprint: job.fingerprint, outputPath: result.outputURL.path, objectKey: key), deleteSource: deleteLocally)
                if deleteLocally { await deleteSourceIfReady(job.fingerprint) }
                Log.info("Processed recording: \(job.source.lastPathComponent) -> \(result.outputURL.path)")
            }
            triggerDelivery()
        } catch {
            await tracker.failed(job.fingerprint)
            Log.processing.error("Failed to process recording \(job.source.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func queueDelivery(file: URL, source: URL, fingerprint: SourceFingerprint, objectKey: String, contentType: String, configuration: ShotdConfiguration) async throws {
        guard configuration.storage != nil else { return }
        let deleteAfterUpload = configuration.source.retention == .deleteAfterSuccess && configuration.source.deleteRequiresUpload
        try await storageDelivery.enqueue(.init(
            localPath: file.path,
            objectKey: objectKey,
            contentType: contentType,
            sourcePath: deleteAfterUpload ? source.path : nil,
            sourceFingerprint: deleteAfterUpload ? fingerprint : nil,
            deleteSourceAfterUpload: deleteAfterUpload
        ))
    }

    private func triggerDelivery() {
        startDeliveryIfNeeded()
    }

    private func retryPendingDeletions() async {
        guard running else { return }
        do {
            for fingerprint in try await tracker.pendingDeletions() {
                await deleteSourceIfReady(fingerprint)
            }
        } catch {
            Log.processing.error("Unable to load pending source deletions: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteSourceIfReady(_ fingerprint: SourceFingerprint) async {
        let source = URL(filePath: fingerprint.path)
        guard FileManager.default.fileExists(atPath: source.path) else {
            try? await tracker.completedDeletion(fingerprint)
            return
        }
        guard (try? stabilizer.fingerprint(source)) == fingerprint else {
            try? await tracker.completedDeletion(fingerprint)
            Log.processing.notice("Source changed after processing; keeping the edited original.")
            return
        }
        do {
            try FileManager.default.removeItem(at: source)
            try await tracker.completedDeletion(fingerprint)
        } catch {
            Log.processing.error("Unable to delete source \(source.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func replaceSource(_ output: URL, source: URL, fingerprint: SourceFingerprint, objectKey: String) async throws -> Bool {
        guard try stabilizer.fingerprint(source) == fingerprint else {
            Log.processing.notice("Source changed after processing; keeping the edited original.")
            try await tracker.processed(.init(fingerprint: fingerprint, outputPath: output.path, objectKey: objectKey))
            return false
        }
        try AtomicWriter.copyFile(at: output, to: source)
        let replacement = try stabilizer.fingerprint(source)
        try await tracker.processed(.init(fingerprint: replacement, outputPath: source.path, objectKey: objectKey))
        return true
    }
}
