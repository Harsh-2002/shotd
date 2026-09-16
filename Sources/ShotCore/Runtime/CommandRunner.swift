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
            case ["config", "repairable"]:
                var configuration = try await loader.loadUnvalidated()
                guard ConfigValidator.directoriesOverlap(
                    watch: configuration.watch.directory,
                    output: configuration.output.directory,
                    paths: paths
                ) else {
                    throw ShotdError.invalidConfiguration("Saved settings require manual repair.")
                }
                let watch = paths.expandUserPath(configuration.watch.directory).standardizedFileURL
                configuration.output.directory = watch.deletingLastPathComponent().appending(path: "shotd-output").path
                try ConfigValidator.validate(configuration, paths: paths)
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
                try LaunchAgent.stop(paths: paths)
                do {
                    try await FileTracker(paths: paths).requireBaseline()
                } catch {
                    try? LaunchAgent.start(paths: paths)
                    throw error
                }
                try LaunchAgent.removeInstallation(paths: paths)
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
            case ["completions", "zsh"]:
                print(Self.zshCompletion)
            case ["logs"]:
                try showLogs(paths: paths, follow: false)
            case ["logs", "--follow"]:
                try showLogs(paths: paths, follow: true)
            case _ where arguments.first == "setup":
                try await setup(paths: paths, loader: loader)
            case ["update", "--check"]:
                print(try await ReleaseUpdater.check(paths: paths))
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
        var importedBackground: URL?
        var credentialRollback: (name: String, previous: StorageCredentials?)?
        var committed = false
        defer {
            if !committed {
                if let importedBackground {
                    try? FileManager.default.removeItem(at: importedBackground)
                }
                if let credentialRollback {
                    if let previous = credentialRollback.previous {
                        try? CredentialStore.set(previous, named: credentialRollback.name)
                    } else {
                        try? CredentialStore.delete(named: credentialRollback.name)
                    }
                }
            }
        }
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
                    watchDirectory = normalizedPath(arguments[index + 1])
                } else {
                    outputDirectory = normalizedPath(arguments[index + 1])
                }
                index += 1
            default:
                throw ShotdError.invalidArguments("Unknown setup option: \(arguments[index])")
            }
            index += 1
        }

        let hadCanonicalSettings = FileManager.default.fileExists(atPath: paths.configuration.path)
        let hadLegacySettings = FileManager.default.fileExists(atPath: paths.legacyConfiguration.path)
        let exists = hadCanonicalSettings || hadLegacySettings
        var configuration = try await (exists ? loader.loadUnvalidated() : ShotdConfiguration())
        let originalConfiguration = exists ? configuration : nil
        configuration.watch.directory = normalizedPath(configuration.watch.directory)
        configuration.output.directory = normalizedPath(configuration.output.directory)
        if let watchDirectory { configuration.watch.directory = watchDirectory }
        if let outputDirectory { configuration.output.directory = outputDirectory }
        if !acceptDefaults, isatty(STDIN_FILENO) == 1 {
            print("\n\(styled("SHOTD SETUP", code: "1;35"))")
            print(exists ? "Update your setup. Press Return to keep each value." : "A few choices, then screenshots are ready to paste.")
            if watchDirectory == nil {
                let answer = try SecureTerminalInput.read(prompt: fieldPrompt("Screenshot folder", defaultValue: configuration.watch.directory), secret: false, allowEmpty: true)
                if !answer.isEmpty { configuration.watch.directory = normalizedPath(answer) }
            }
            if outputDirectory == nil {
                let answer = try SecureTerminalInput.read(prompt: fieldPrompt("Finished media folder", defaultValue: configuration.output.directory), secret: false, allowEmpty: true)
                if !answer.isEmpty { configuration.output.directory = normalizedPath(answer) }
            }
            while ConfigValidator.directoriesOverlap(
                watch: configuration.watch.directory,
                output: configuration.output.directory,
                paths: paths
            ) {
                let watch = paths.expandUserPath(configuration.watch.directory).standardizedFileURL
                let suggestion = watch.deletingLastPathComponent().appending(path: "shotd-output").path
                print(styled("Finished media must be outside the screenshot folder.", code: "1;33"))
                let answer = try SecureTerminalInput.read(
                    prompt: fieldPrompt("Finished media folder", defaultValue: suggestion),
                    secret: false,
                    allowEmpty: true
                )
                configuration.output.directory = answer.isEmpty ? suggestion : normalizedPath(answer)
            }
            let replacing = try promptYesNo(
                "Replace original screenshots?",
                defaultValue: configuration.source.retention == .replaceAfterSuccess
            )
            configuration.source.retention = replacing ? .replaceAfterSuccess : .keep
            print("\n\(styled("APPEARANCE", code: "1;35"))")
            let background = try await configureBackground(configuration.background, preservingCurrent: exists, paths: paths)
            configuration.background = background.configuration
            importedBackground = background.imported
            print("\n\(styled("IMAGE OUTPUT", code: "1;35"))")
            configuration.image = try configureImage(configuration.image)
            print("\n\(styled("CLOUD STORAGE", code: "1;35"))")
            let storage = try await configureStorage(configuration.storage, configuration: configuration, paths: paths)
            configuration.storage = storage.configuration
            credentialRollback = storage.credentialRollback
        }
        if startAfterSetup, !acceptDefaults, isatty(STDIN_FILENO) != 1 {
            throw ShotdError.invalidArguments("Run `shotd setup --yes` to install non-interactively.")
        }
        do {
            try await loader.write(configuration)
        } catch {
            if let credentialRollback {
                do {
                    if let previous = credentialRollback.previous {
                        try CredentialStore.set(previous, named: credentialRollback.name)
                    } else {
                        try CredentialStore.delete(named: credentialRollback.name)
                    }
                } catch let rollbackError {
                    throw ShotdError.storage("Setup failed and Keychain rollback also failed: \(rollbackError.localizedDescription)")
                }
            }
            throw error
        }
        let watch = paths.expandUserPath(configuration.watch.directory).path
        let output = paths.expandUserPath(configuration.output.directory).path
        print("\n\(styled("Setup ready", code: "1;32"))")
        print("  \(styled("Screenshots:", code: "1;34")) \(styled(watch, code: "32"))")
        print("  \(styled("Finished:", code: "1;34"))    \(styled(output, code: "32"))")
        let retentionDescription: String
        switch configuration.source.retention {
        case .keep: retentionDescription = "keep"
        case .deleteAfterSuccess: retentionDescription = "delete after delivery"
        case .replaceAfterSuccess: retentionDescription = "replace safely"
        }
        print("  \(styled("Originals:", code: "1;34"))   \(styled(retentionDescription, code: "32"))")
        print("  \(styled("Background:", code: "1;34"))  \(styled(configuration.background.type.rawValue, code: "32"))")
        print("  \(styled("Image:", code: "1;34"))       \(styled(configuration.image.format.rawValue + (configuration.image.compression.map { " (\($0.rawValue))" } ?? ""), code: "32"))")
        print("  \(styled("Storage:", code: "1;34"))     \(styled(configuration.storage?.bucket ?? "local only", code: "32"))")
        print("\nPress Shift-Command-5, choose Options, then set Save to the screenshot folder above.")
        print("If your desktop wallpaper is stored in Downloads, macOS may ask once for folder access.")

        guard startAfterSetup else {
            committed = true
            if hadLegacySettings, !hadCanonicalSettings { try await loader.finalizeLegacyMigration() }
            print("Setup is ready. Run `shotd install` when you want shotd to start automatically.")
            return
        }
        if !acceptDefaults {
            let answer = try SecureTerminalInput.read(prompt: "Start shotd automatically now? [Y/n] ", secret: false, allowEmpty: true)
            if !answer.isEmpty, !["y", "yes"].contains(answer.lowercased()) {
                committed = true
                if hadLegacySettings, !hadCanonicalSettings { try await loader.finalizeLegacyMigration() }
                print("Setup is ready. Run `shotd install` when you want shotd to start automatically.")
                return
            }
        }
        do {
            try LaunchAgent.install(paths: paths, executable: try invokedExecutable())
        } catch {
            do {
                if hadCanonicalSettings, let originalConfiguration {
                    try await loader.write(originalConfiguration)
                } else {
                    try? FileManager.default.removeItem(at: paths.configuration)
                }
            } catch let rollbackError {
                throw ShotdError.filesystem("Automatic startup failed and settings rollback also failed: \(rollbackError.localizedDescription)")
            }
            if let credentialRollback {
                do {
                    if let previous = credentialRollback.previous {
                        try CredentialStore.set(previous, named: credentialRollback.name)
                    } else {
                        try CredentialStore.delete(named: credentialRollback.name)
                    }
                } catch let rollbackError {
                    throw ShotdError.storage("Automatic startup failed and Keychain rollback also failed: \(rollbackError.localizedDescription)")
                }
            }
            throw error
        }
        committed = true
        if hadLegacySettings, !hadCanonicalSettings { try await loader.finalizeLegacyMigration() }
        Log.info("shotd is ready. Run `shotd doctor` any time to check its setup.")
    }

    private func configureBackground(
        _ current: BackgroundConfiguration,
        preservingCurrent: Bool,
        paths: ApplicationPaths
    ) async throws -> (configuration: BackgroundConfiguration, imported: URL?) {
        let choice = try promptChoice(
            preservingCurrent ? "Background [keep/desktop/custom/solid]" : "Background [desktop/custom/solid]",
            defaultValue: preservingCurrent ? "keep" : "desktop",
            allowed: preservingCurrent ? ["keep", "desktop", "custom", "solid"] : ["desktop", "custom", "solid"]
        )
        var background = current
        switch choice {
        case "keep":
            return (background, nil)
        case "desktop":
            background.type = .desktop
            background.path = nil
            return (background, nil)
        case "solid":
            while true {
                let existing = background.color ?? "#17191F"
                let answer = try SecureTerminalInput.read(prompt: fieldPrompt("Background color", defaultValue: existing), secret: false, allowEmpty: true)
                var candidateBackground = background
                candidateBackground.type = .solid
                candidateBackground.path = nil
                candidateBackground.color = answer.isEmpty ? existing : answer
                var candidate = ShotdConfiguration()
                candidate.background = candidateBackground
                if (try? ConfigValidator.validate(candidate, paths: paths)) != nil { return (candidateBackground, nil) }
                print(styled("Use a color such as #17191F.", code: "1;33"))
            }
        default:
            while true {
                let answer = try SecureTerminalInput.read(prompt: fieldPrompt("Background image path"), secret: false)
                let source = paths.expandUserPath(normalizedPath(answer)).standardizedFileURL
                guard FileManager.default.fileExists(atPath: source.path) else {
                    print(styled("That image file does not exist.", code: "1;33"))
                    continue
                }
                do {
                    _ = try await MainActor.run { try ImageDecoder.decode(at: source) }
                    let imported = try importBackground(source, paths: paths)
                    background.type = .image
                    background.path = imported.path
                    return (background, imported)
                } catch {
                    print(styled("That file is not a readable image.", code: "1;33"))
                }
            }
        }
    }

    private func configureImage(_ current: ImageConfiguration) throws -> ImageConfiguration {
        var image = current
        let compressing = try promptYesNo("Compress screenshots?", defaultValue: current.format != .png)
        if !compressing {
            image.format = .png
            image.compression = .lossless
            image.quality = nil
            return image
        }
        image.format = ImageFormat(rawValue: try promptChoice(
            "Output format [webp/avif/heic/jpeg/png/preserve]",
            defaultValue: current.format.rawValue,
            allowed: ["webp", "avif", "heic", "jpeg", "png", "preserve"]
        ))!
        if image.format == .preserve {
            image.compression = nil
            image.quality = nil
            return image
        } else if image.format == .png {
            image.compression = .lossless
        } else if [.jpeg, .heic].contains(image.format) {
            image.compression = .lossy
        } else {
            image.compression = Compression(rawValue: try promptChoice(
                "Compression [lossless/lossy]",
                defaultValue: current.compression?.rawValue ?? "lossless",
                allowed: ["lossless", "lossy"]
            ))!
        }
        if image.compression == .lossy {
            while true {
                let defaultQuality = image.quality ?? 82
                let answer = try SecureTerminalInput.read(prompt: fieldPrompt("Quality 1-100", defaultValue: String(defaultQuality)), secret: false, allowEmpty: true)
                if answer.isEmpty { image.quality = defaultQuality; break }
                if let quality = Int(answer), (1...100).contains(quality) { image.quality = quality; break }
                print(styled("Enter a number from 1 to 100.", code: "1;33"))
            }
        } else {
            image.quality = nil
        }
        return image
    }

    private func configureStorage(
        _ current: StorageConfiguration?,
        configuration: ShotdConfiguration,
        paths: ApplicationPaths
    ) async throws -> (configuration: StorageConfiguration?, credentialRollback: (name: String, previous: StorageCredentials?)?) {
        if let current {
            let choice = try promptChoice("Storage [keep/change/disable]", defaultValue: "keep", allowed: ["keep", "change", "disable"])
            if choice == "keep" { return (current, nil) }
            if choice == "disable" { return (nil, nil) }
        } else if try !promptYesNo("Upload copies to S3-compatible storage?", defaultValue: false) {
            return (nil, nil)
        }

        let endpoint = try SecureTerminalInput.read(prompt: fieldPrompt("S3 endpoint URL"), secret: false)
        let region = try SecureTerminalInput.read(prompt: fieldPrompt("Region", defaultValue: "auto"), secret: false, allowEmpty: true)
        let bucket = try SecureTerminalInput.read(prompt: fieldPrompt("Bucket"), secret: false)
        let addressing = S3Addressing(rawValue: try promptChoice(
            "Addressing [auto/path/virtualHost]",
            defaultValue: "auto",
            allowed: ["auto", "path", "virtualHost"]
        ))!
        let credential = try SecureTerminalInput.read(prompt: fieldPrompt("Credential name", defaultValue: "default"), secret: false, allowEmpty: true)
        let accessKeyID = try SecureTerminalInput.read(prompt: fieldPrompt("Access key ID"), secret: false)
        let secretAccessKey = try SecureTerminalInput.read(prompt: fieldPrompt("Secret access key"), secret: true)
        let token = try SecureTerminalInput.read(prompt: fieldPrompt("Session token (optional)"), secret: true, allowEmpty: true)
        let credentials = StorageCredentials(accessKeyID: accessKeyID, secretAccessKey: secretAccessKey, sessionToken: token.isEmpty ? nil : token)
        let storage = StorageConfiguration(
            endpoint: endpoint,
            region: region.isEmpty ? "auto" : region,
            bucket: bucket,
            credential: credential.isEmpty ? "default" : credential,
            addressing: addressing
        )
        var candidate = configuration
        candidate.storage = storage
        try ConfigValidator.validate(candidate, paths: paths)
        guard try promptYesNo("Verify storage now? This uploads and deletes a small test file.", defaultValue: true) else {
            throw ShotdError.invalidArguments("Storage must be verified before it can be enabled.")
        }
        try await verifyStorage(storage, credentials: credentials)
        let previous = try CredentialStore.getIfPresent(named: storage.credential)
        try CredentialStore.set(credentials, named: storage.credential)
        print(styled("Storage verified.", code: "1;32"))
        return (storage, (storage.credential, previous))
    }

    private func verifyStorage(_ storage: StorageConfiguration, credentials: StorageCredentials) async throws {
        let client = S3Client(configuration: storage, credentials: credentials)
        let key = "shotd-diagnostics/\(UUID().uuidString).txt"
        let data = Data("shotd storage diagnostics\n".utf8)
        do {
            try await client.put(data: data, key: key, contentType: "text/plain")
            try await client.head(key: key)
            _ = try await client.remoteURL(for: key)
            try await client.delete(key: key)
        } catch {
            try? await client.delete(key: key)
            throw error
        }
    }

    private func importBackground(_ source: URL, paths: ApplicationPaths) throws -> URL {
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
            return destination
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func promptChoice(_ prompt: String, defaultValue: String, allowed: Set<String>) throws -> String {
        while true {
            let answer = try SecureTerminalInput.read(prompt: fieldPrompt(prompt, defaultValue: defaultValue), secret: false, allowEmpty: true)
            let value = answer.isEmpty ? defaultValue : answer
            if allowed.contains(value) { return value }
            print(styled("Choose one of: \(allowed.sorted().joined(separator: ", ")).", code: "1;33"))
        }
    }

    private func promptYesNo(_ prompt: String, defaultValue: Bool) throws -> Bool {
        while true {
            let suffix = defaultValue ? "[Y/n]" : "[y/N]"
            let rendered = "\(styled(prompt, code: "1;34")) \(styled(suffix, code: "33")): "
            let answer = try SecureTerminalInput.read(prompt: rendered, secret: false, allowEmpty: true).lowercased()
            if answer.isEmpty { return defaultValue }
            if ["y", "yes"].contains(answer) { return true }
            if ["n", "no"].contains(answer) { return false }
            print(styled("Enter yes or no.", code: "1;33"))
        }
    }

    private func fieldPrompt(_ label: String, defaultValue: String? = nil) -> String {
        let rendered = styled(label, code: "1;34")
        guard let defaultValue else { return "\(rendered): " }
        return "\(rendered) [\(styled(defaultValue, code: "33"))]: "
    }

    private func showLogs(paths: ApplicationPaths, follow: Bool) throws {
        let files = [paths.logsDirectory.appending(path: "daemon.log"), paths.logsDirectory.appending(path: "daemon-error.log")]
        try FileManager.default.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for file in files where !FileManager.default.fileExists(atPath: file.path) {
            _ = FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tail")
        process.arguments = ["-n", "50"] + (follow ? ["-F"] : []) + files.map(\.path)
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ShotdError.filesystem("Unable to read shotd logs.") }
    }

    private func normalizedPath(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\ ", with: " ").replacingOccurrences(of: "\\~", with: "~")
    }

    private func styled(_ value: String, code: String) -> String {
        guard isatty(STDOUT_FILENO) == 1, ProcessInfo.processInfo.environment["NO_COLOR"] == nil else { return value }
        return "\u{001B}[\(code)m\(value)\u{001B}[0m"
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
      logs [--follow]
      completions zsh
    """

    private static let zshCompletion = """
    #compdef shotd

    _shotd() {
      local -a commands
      commands=(
        'setup:configure and install shotd'
        'install:install or upgrade the LaunchAgent'
        'uninstall:remove the LaunchAgent and binary'
        'start:start the LaunchAgent'
        'stop:stop the LaunchAgent'
        'restart:restart the LaunchAgent'
        'status:show LaunchAgent status'
        'run:run the daemon in the foreground'
        'process:process one media file'
        'config:manage configuration'
        'background:manage backgrounds'
        'storage:manage S3 storage'
        'codecs:list image codecs'
        'doctor:check the installation'
        'logs:show recent processing logs'
        'update:check for or install updates'
        'version:show the installed version'
        'completions:generate shell completions'
      )

      if (( CURRENT == 2 )); then
        _describe 'command' commands
        return
      fi

      case "$words[2]" in
        setup) _arguments '--yes[accept defaults]' '--no-start[do not install the LaunchAgent]' '--watch-directory[set screenshot folder]:directory:_directories' '--output-directory[set output folder]:directory:_directories' ;;
        process) _files ;;
        config) _values 'command' path init validate ;;
        background) _arguments '1:command:(import)' '2:image file:_files' ;;
        storage) _values 'command' set-credentials set-development-credentials test multipart-test ;;
        update) _arguments '--check[check without installing]' ;;
        logs) _arguments '--follow[keep showing new log entries]' ;;
        completions) _values 'shell' zsh ;;
      esac
    }
    """
}

private extension ShotdError {
    var isUsageError: Bool {
        if case .invalidArguments = self { return true }
        return false
    }
}
