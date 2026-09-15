import Darwin
import Foundation

public enum ExitCode: Int32, Sendable { case success = 0, failure = 1, usage = 2 }

public struct CommandRunner: Sendable {
    private let arguments: [String]

    public init(arguments: [String]) { self.arguments = arguments }

    public func run() async -> ExitCode {
        do {
            let paths = try ApplicationPaths()
            let loader = ConfigLoader(paths: paths)
            switch arguments {
            case ["config", "path"]:
                print(paths.configuration.path)
            case ["config", "init"]:
                _ = try await loader.loadOrCreateDefault()
                Log.info("Configuration initialized at \(paths.configuration.path)")
            case ["config", "validate"]:
                _ = try await loader.load()
                Log.info("Configuration valid")
            case _ where arguments.count == 3 && arguments[0] == "background" && arguments[1] == "import":
                let source = URL(filePath: arguments[2]).standardizedFileURL
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw ShotdError.filesystem("Background file does not exist: \(source.path)")
                }
                let extensionName = source.pathExtension.isEmpty ? "image" : source.pathExtension.lowercased()
                let name = OutputManager.sanitizedBaseName(source.deletingPathExtension().lastPathComponent)
                let directory = paths.applicationSupport.appending(path: "backgrounds", directoryHint: .isDirectory)
                let destination = directory.appending(path: "\(name)-\(UUID().uuidString).\(extensionName)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let temporary = directory.appending(path: ".\(destination.lastPathComponent).tmp")
                do {
                    try FileManager.default.copyItem(at: source, to: temporary)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                    try AtomicWriter.replaceFile(at: temporary, with: destination)
                } catch {
                    try? FileManager.default.removeItem(at: temporary)
                    throw ShotdError.filesystem("Unable to import background: \(error.localizedDescription)")
                }
                var configuration = try await loader.load()
                configuration.background.type = .image
                configuration.background.path = destination.path
                try await loader.write(configuration)
                Log.info("Background imported to \(destination.path)")
            case ["install"]:
                _ = try await loader.loadOrCreateDefault()
                try LaunchAgent.install(paths: paths, executable: try invokedExecutable())
                Log.info("LaunchAgent installed")
            case ["uninstall"]:
                try LaunchAgent.uninstall(paths: paths)
                Log.info("LaunchAgent uninstalled")
            case ["start"]:
                try LaunchAgent.start(paths: paths)
                Log.info("LaunchAgent started")
            case ["stop"]:
                try LaunchAgent.stop(paths: paths)
                Log.info("LaunchAgent stopped")
            case ["restart"]:
                try LaunchAgent.restart(paths: paths)
                Log.info("LaunchAgent restarted")
            case ["status"]:
                print(LaunchAgent.status(paths: paths))
            case _ where arguments.count == 2 && arguments[0] == "process":
                let file = arguments[1]
                let source = URL(filePath: file).standardizedFileURL
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw ShotdError.filesystem("Source file does not exist: \(source.path)")
                }
                let configuration = try await loader.loadOrCreateDefault()
                let output = OutputManager(directory: paths.expandUserPath(configuration.output.directory))
                let media = try await MediaInspector.inspect(at: source)
                let processed: (url: URL, format: OutputFormat, kind: OutputKind, prefix: String)
                switch media {
                case .image:
                    let result = try await MainActor.run {
                        try StillCaptureProcessor(paths: paths).process(sourceURL: source, configuration: configuration)
                    }
                    processed = (result.outputURL, result.format, .image, configuration.storage?.paths.images ?? "screenshots")
                case .video:
                    let result = try await VideoProcessor(paths: paths).process(sourceURL: source, configuration: configuration)
                    processed = (result.outputURL, result.format, .video, configuration.storage?.paths.videos ?? "recordings")
                }
                let key = output.objectKey(for: source, kind: processed.kind, format: processed.format, prefix: processed.prefix)
                let delivery = StorageDelivery(paths: paths)
                _ = await delivery.deliver(file: processed.url, objectKey: key, contentType: processed.format.mimeType, configuration: configuration.storage)
                Log.info(processed.url.path)
            case ["codecs"]:
                let codecs = await MainActor.run { EncoderRegistry().codecs() }
                print("Image encoders\n")
                for codec in codecs {
                    print("\(codec.format.rawValue.uppercased())")
                    print("  available: \(codec.available ? "yes" : "no")")
                    print("  lossless: \(codec.lossless ? "yes" : "no")")
                    print("  backend: \(codec.backend?.rawValue ?? "unavailable")\n")
                }
            case ["run"]:
                let daemon = Daemon(paths: paths)
                try await daemon.start()
                let signals = SignalHandler { Task { await daemon.stop() } }
                await daemon.waitForever()
                signals.cancel()
            case ["version"]:
                print("shotd \(BuildInfo.version)")
            case _ where arguments.first == "setup":
                try await setup(paths: paths, loader: loader)
            case ["update", "--check"]:
                print(try await ReleaseUpdater.check())
            case ["update"]:
                print(try await ReleaseUpdater.update(paths: paths))
            case _ where arguments.count == 3 && arguments[0] == "storage" && arguments[1] == "set-credentials":
                let name = arguments[2]
                let environment = ProcessInfo.processInfo.environment
                let accessKeyID = try environment["SHOTD_ACCESS_KEY_ID"] ?? SecureTerminalInput.read(prompt: "Access key ID: ", secret: false)
                let secretAccessKey = try environment["SHOTD_SECRET_ACCESS_KEY"] ?? SecureTerminalInput.read(prompt: "Secret access key: ", secret: true)
                let sessionToken = try environment["SHOTD_SESSION_TOKEN"] ?? (environment["SHOTD_ACCESS_KEY_ID"] != nil && environment["SHOTD_SECRET_ACCESS_KEY"] != nil ? "" : SecureTerminalInput.read(prompt: "Session token (optional): ", secret: true, allowEmpty: true))
                try CredentialStore.set(.init(accessKeyID: accessKeyID, secretAccessKey: secretAccessKey, sessionToken: sessionToken.isEmpty ? nil : sessionToken), named: name)
                Log.info("Stored credentials \(name) in Keychain")
            case ["storage", "set-development-credentials"]:
                var configuration = try await loader.load()
                guard var storage = configuration.storage, URL(string: storage.endpoint)?.host()?.lowercased() == "localhost" else {
                    throw ShotdError.invalidConfiguration("Development credentials can be set only for a localhost storage endpoint.")
                }
                let environment = ProcessInfo.processInfo.environment
                let accessKeyID = try environment["SHOTD_ACCESS_KEY_ID"] ?? SecureTerminalInput.read(prompt: "Access key ID: ", secret: false)
                let secretAccessKey = try environment["SHOTD_SECRET_ACCESS_KEY"] ?? SecureTerminalInput.read(prompt: "Secret access key: ", secret: true)
                let sessionToken = try environment["SHOTD_SESSION_TOKEN"] ?? (environment["SHOTD_ACCESS_KEY_ID"] != nil && environment["SHOTD_SECRET_ACCESS_KEY"] != nil ? "" : SecureTerminalInput.read(prompt: "Session token (optional): ", secret: true, allowEmpty: true))
                storage.developmentCredentials = .init(accessKeyID: accessKeyID, secretAccessKey: secretAccessKey, sessionToken: sessionToken.isEmpty ? nil : sessionToken)
                configuration.storage = storage
                try await loader.write(configuration)
                Log.info("Stored localhost development credentials in the protected config file")
            case ["storage", "test"]:
                let configuration = try await loader.load()
                guard let storage = configuration.storage else { throw ShotdError.invalidConfiguration("storage is not configured.") }
                let credentials = try CredentialStore.get(for: storage)
                let client = S3Client(configuration: storage, credentials: credentials)
                let key = "shotd-diagnostics/\(UUID().uuidString) % # ?.txt"
                let data = Data("shotd storage diagnostics\n".utf8)
                try await client.put(data: data, key: key, contentType: "text/plain")
                try await client.head(key: key)
                _ = try await client.remoteURL(for: key)
                try await client.delete(key: key)
                Log.info("Storage test passed")
            case ["storage", "multipart-test"]:
                let configuration = try await loader.load()
                guard let storage = configuration.storage else { throw ShotdError.invalidConfiguration("storage is not configured.") }
                let credentials = try CredentialStore.get(for: storage)
                let client = S3Client(configuration: storage, credentials: credentials)
                let key = "shotd-diagnostics/\(UUID().uuidString).bin"
                let temporary = paths.stateDirectory.appending(path: "multipart-\(UUID().uuidString).bin")
                let size = max(storage.multipartPartSizeMB + 1, 6) * 1_024 * 1_024
                try AtomicWriter.write(Data(repeating: 0xA5, count: size), to: temporary)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try await MultipartUploader().upload(file: temporary, key: key, contentType: "application/octet-stream", client: client, partSizeMB: storage.multipartPartSizeMB)
                try await client.head(key: key)
                try await client.delete(key: key)
                Log.info("Multipart storage test passed")
            case ["doctor"]:
                let configuration = try await loader.loadOrCreateDefault()
                try paths.createRequiredDirectories()
                let output = OutputManager(directory: paths.expandUserPath(configuration.output.directory))
                try output.prepareDirectory()
                let codecs = await MainActor.run { EncoderRegistry().codecs() }
                let codecStatus = codecs.map { "\($0.format.rawValue): \($0.available ? "available" : "unavailable")" }.joined(separator: ", ")
                print("configuration: valid")
                print("output directory: writable")
                print("launch agent: \(LaunchAgent.status(paths: paths))")
                print("codecs: \(codecStatus)")
                if let storage = configuration.storage {
                    _ = try CredentialStore.get(for: storage)
                    print("storage credentials: available")
                } else {
                    print("storage: not configured")
                }
            case ["help"], []:
                print(Self.help)
            default:
                throw ShotdError.invalidArguments("Unknown command.\n\n\(Self.help)")
            }
            return .success
        } catch let error as ShotdError {
            Log.error(error.localizedDescription)
            return error.isUsageError ? .usage : .failure
        } catch {
            Log.error(error.localizedDescription)
            return .failure
        }
    }

    private func setup(paths: ApplicationPaths, loader: ConfigLoader) async throws {
        var startAfterSetup = true
        var acceptDefaults = false
        var watchDirectory: String?
        var outputDirectory: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--yes":
                acceptDefaults = true
            case "--no-start":
                startAfterSetup = false
            case "--watch-directory", "--output-directory":
                guard index + 1 < arguments.count else {
                    throw ShotdError.invalidArguments("\(arguments[index]) requires a directory path.")
                }
                if arguments[index] == "--watch-directory" {
                    watchDirectory = arguments[index + 1]
                } else {
                    outputDirectory = arguments[index + 1]
                }
                index += 1
            default:
                throw ShotdError.invalidArguments("Unknown setup option: \(arguments[index])")
            }
            index += 1
        }

        let exists = FileManager.default.fileExists(atPath: paths.configuration.path)
        var configuration = try await loader.loadOrCreateDefault()
        if exists && (watchDirectory != nil || outputDirectory != nil) {
            throw ShotdError.invalidArguments("shotd is already configured. Edit \(paths.configuration.path) to change its directories.")
        }
        if !exists {
            if let watchDirectory { configuration.watch.directory = watchDirectory }
            if let outputDirectory { configuration.output.directory = outputDirectory }
            if !acceptDefaults, isatty(STDIN_FILENO) == 1 {
                print("\nWelcome to shotd. Press Return to keep a suggested folder.")
                if watchDirectory == nil {
                    let answer = try SecureTerminalInput.read(prompt: "Where should macOS save screenshots? [\(configuration.watch.directory)] ", secret: false, allowEmpty: true)
                    if !answer.isEmpty { configuration.watch.directory = answer }
                }
                if outputDirectory == nil {
                    let answer = try SecureTerminalInput.read(prompt: "Where should shotd save finished media? [\(configuration.output.directory)] ", secret: false, allowEmpty: true)
                    if !answer.isEmpty { configuration.output.directory = answer }
                }
            }
            try await loader.write(configuration)
        }

        let watch = paths.expandUserPath(configuration.watch.directory).path
        let output = paths.expandUserPath(configuration.output.directory).path
        print("""

        shotd setup
        -----------
        Your screenshots will be ready to paste automatically.

        Watch folder: \(watch)
        Output folder: \(output)

        In macOS, press Shift-Command-5, choose Options, then set Save to this watch folder.
        Keep captures in Pictures when possible. Desktop, Documents, Downloads, external drives, and network folders can require additional macOS permission.
        """)

        guard startAfterSetup else {
            print("Setup is ready. Run `shotd install` when you want shotd to start automatically.")
            return
        }
        if !acceptDefaults {
            guard isatty(STDIN_FILENO) == 1 else {
                throw ShotdError.invalidArguments("Run `shotd setup --yes` to install non-interactively.")
            }
            let answer = try SecureTerminalInput.read(prompt: "Start shotd automatically now? [Y/n] ", secret: false, allowEmpty: true)
            if !answer.isEmpty, !["y", "yes"].contains(answer.lowercased()) {
                print("Setup is ready. Run `shotd install` when you want shotd to start automatically.")
                return
            }
        }
        try LaunchAgent.install(paths: paths, executable: try invokedExecutable())
        Log.info("shotd is ready. Run `shotd doctor` any time to check its setup.")
    }

    private func invokedExecutable() throws -> URL {
        let invocation = CommandLine.arguments[0]
        let fileManager = FileManager.default
        let candidate: URL?
        if invocation.contains("/") {
            candidate = invocation.hasPrefix("/")
                ? URL(filePath: invocation)
                : URL(filePath: fileManager.currentDirectoryPath).appending(path: invocation)
        } else {
            candidate = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").lazy
                .map { URL(filePath: String($0)).appending(path: invocation) }
                .first(where: { fileManager.isExecutableFile(atPath: $0.path) })
        }
        guard let candidate, fileManager.isExecutableFile(atPath: candidate.path) else {
            throw ShotdError.filesystem("Unable to locate the running shotd executable.")
        }
        return candidate.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static let help = """
    Usage: shotd <command>

      setup [--yes] [--no-start] [--watch-directory <path>] [--output-directory <path>]
      install | uninstall | start | stop | restart | status
      run | process <file>
      config path | config validate
      background import <file>
      storage set-credentials <name> | storage set-development-credentials
      storage test | storage multipart-test
      codecs | doctor | update [--check] | version
    """
}

private extension ShotdError {
    var isUsageError: Bool {
        if case .invalidArguments = self { return true }
        return false
    }
}
