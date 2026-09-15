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
    private var pendingVideos: [VideoJob] = []
    private var videoProcessing = false
    private var retryTask: Task<Void, Never>?
    private var running = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    public init(paths: ApplicationPaths) {
        self.paths = paths
        self.loader = ConfigLoader(paths: paths)
        self.tracker = FileTracker(paths: paths)
        self.storageDelivery = StorageDelivery(paths: paths)
    }

    public func start() async throws {
        guard !running else { return }
        let loaded = try await loader.loadOrCreateDefault()
        let inbox = paths.expandUserPath(loaded.watch.directory).standardizedFileURL
        let output = paths.expandUserPath(loaded.output.directory).standardizedFileURL
        guard inbox != output else { throw ShotdError.invalidConfiguration("watch.directory and output.directory must be different.") }
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        configuration = loaded
        await prewarmBackground(configuration: loaded)
        await storageDelivery.retryDueUploads(configuration: loaded.storage)
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.retryDueUploads()
            }
        }

        let inboxWatcher = makeInboxWatcher(directory: inbox)
        let configurationFile = paths.configuration.standardizedFileURL
        let configWatcher = DirectoryWatcher(directory: paths.applicationSupport) { [weak self] files in
            guard files.contains(where: { $0.standardizedFileURL == configurationFile }) else { return }
            Task { await self?.reloadConfiguration() }
        }
        try inboxWatcher.start()
        try configWatcher.start()
        self.inboxWatcher = inboxWatcher
        self.configWatcher = configWatcher
        running = true
        await enqueueStartupFiles(try inboxWatcher.currentFiles(), configuration: loaded)
        Log.info("shotd is watching \(inbox.path)")
    }

    public func stop() {
        inboxWatcher?.stop()
        configWatcher?.stop()
        inboxWatcher = nil
        configWatcher = nil
        retryTask?.cancel()
        retryTask = nil
        pendingImages.removeAll()
        pendingVideos.removeAll()
        running = false
        let waiters = stopWaiters
        stopWaiters.removeAll()
        waiters.forEach { $0.resume() }
        Log.info("shotd stopped")
    }

    public func waitForever() async {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                stopWaiters.append(continuation)
            }
        }, onCancel: {
            Task { await self.stop() }
        })
    }

    private func reloadConfiguration() async {
        do {
            guard running else { return }
            let loaded = try await loader.load()
            let inbox = paths.expandUserPath(loaded.watch.directory).standardizedFileURL
            let output = paths.expandUserPath(loaded.output.directory).standardizedFileURL
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

            let currentInbox = configuration.map { paths.expandUserPath($0.watch.directory).standardizedFileURL }
            if inbox != currentInbox {
                let replacement = makeInboxWatcher(directory: inbox)
                try replacement.start()
                let startupFiles = try replacement.currentFiles()
                let previous = inboxWatcher
                inboxWatcher = replacement
                configuration = loaded
                previous?.stop()
                await enqueueStartupFiles(startupFiles, configuration: loaded)
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
    }

    private func makeInboxWatcher(directory: URL) -> DirectoryWatcher {
        DirectoryWatcher(directory: directory) { [weak self] files in
            Task { await self?.enqueue(files) }
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

    private func enqueueStartupFiles(_ files: [URL], configuration: ShotdConfiguration) async {
        let output = OutputManager(directory: paths.expandUserPath(configuration.output.directory))
        var pending: [URL] = []
        for source in files {
            guard let format = expectedFormat(for: source, configuration: configuration) else {
                pending.append(source)
                continue
            }
            let destination = output.destination(for: source, format: format)
            let sourceDate = try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let outputDate = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard let sourceDate, let outputDate, outputDate >= sourceDate,
                  let fingerprint = try? stabilizer.fingerprint(source) else {
                pending.append(source)
                continue
            }
            try? await tracker.processed(.init(fingerprint: fingerprint, outputPath: destination.path))
        }
        enqueue(pending)
    }

    private func expectedFormat(for source: URL, configuration: ShotdConfiguration) -> OutputFormat? {
        switch source.pathExtension.lowercased() {
        case "mov", "mp4":
            return OutputFormat.video(for: configuration.video.format)
        default:
            return OutputFormat.image(for: configuration.image.format)
        }
    }

    private func startNextImageIfNeeded() {
        guard running, !imageProcessing, !pendingImages.isEmpty, let configuration else { return }
        imageProcessing = true
        let source = pendingImages.removeFirst()
        Task { await processImage(source, configuration: configuration) }
    }

    private func processImage(_ source: URL, configuration: ShotdConfiguration) async {
        defer {
            imageProcessing = false
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
                try await tracker.processed(.init(fingerprint: stableFingerprint, outputPath: result.outputURL.path, objectKey: key))
                scheduleDelivery(file: result.outputURL, source: source, fingerprint: stableFingerprint, objectKey: key, contentType: result.format.mimeType, configuration: configuration)
                if configuration.source.retention == .replaceAfterSuccess {
                    try await replaceSource(result.outputURL, source: source, fingerprint: stableFingerprint, objectKey: key)
                    Log.info("Processed and replaced screenshot: \(source.lastPathComponent)")
                } else {
                    Log.info("Processed screenshot: \(source.lastPathComponent) -> \(result.outputURL.path)")
                }
                return
            case .video:
                pendingVideos.append(.init(source: source, configuration: configuration, fingerprint: stableFingerprint))
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
        Task { await processVideo(job) }
    }

    private func processVideo(_ job: VideoJob) async {
        defer {
            videoProcessing = false
            startNextVideoIfNeeded()
        }
        do {
            let result = try await VideoProcessor(paths: paths).process(sourceURL: job.source, configuration: job.configuration)
            let output = OutputManager(directory: paths.expandUserPath(job.configuration.output.directory))
            let key = output.objectKey(for: job.source, kind: .video, format: result.format, prefix: job.configuration.storage?.paths.videos ?? "recordings")
            try await tracker.processed(.init(fingerprint: job.fingerprint, outputPath: result.outputURL.path, objectKey: key))
            scheduleDelivery(file: result.outputURL, source: job.source, fingerprint: job.fingerprint, objectKey: key, contentType: result.format.mimeType, configuration: job.configuration)
            Log.info("Processed recording: \(job.source.lastPathComponent) -> \(result.outputURL.path)")
        } catch {
            await tracker.failed(job.fingerprint)
            Log.processing.error("Failed to process recording \(job.source.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleDelivery(file: URL, source: URL, fingerprint: SourceFingerprint, objectKey: String, contentType: String, configuration: ShotdConfiguration) {
        Task { [storageDelivery] in
            let delivery = await storageDelivery.deliver(file: file, objectKey: objectKey, contentType: contentType, configuration: configuration.storage)
            if configuration.source.retention == .deleteAfterSuccess && (!configuration.source.deleteRequiresUpload || delivery.uploaded) {
                guard (try? FileStabilizer().fingerprint(source)) == fingerprint else { return }
                try? FileManager.default.removeItem(at: source)
            }
        }
    }

    private func replaceSource(_ output: URL, source: URL, fingerprint: SourceFingerprint, objectKey: String) async throws {
        guard try stabilizer.fingerprint(source) == fingerprint else {
            Log.processing.notice("Source changed after processing; keeping the edited original.")
            return
        }
        try AtomicWriter.write(Data(contentsOf: output), to: source)
        let replacement = try stabilizer.fingerprint(source)
        try await tracker.processed(.init(fingerprint: replacement, outputPath: source.path, objectKey: objectKey))
    }
}
