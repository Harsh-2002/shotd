import Darwin
import Dispatch
import Foundation

public final class DirectoryWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([URL]) -> Void

    private let directory: URL
    private let queue: DispatchQueue
    private let handler: Handler
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?

    public init(directory: URL, queue: DispatchQueue = DispatchQueue(label: "io.shotd.directory-watcher", qos: .utility), handler: @escaping Handler) {
        self.directory = directory
        self.queue = queue
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        guard source == nil else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { throw ShotdError.filesystem("Unable to watch \(directory.path).") }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in self?.directoryDidChange() }
        source.setCancelHandler { [descriptor] in if descriptor >= 0 { close(descriptor) } }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    public func currentFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func directoryDidChange() {
        do {
            handler(try currentFiles())
        } catch {
            Log.processing.error("Unable to enumerate watched directory: \(error.localizedDescription, privacy: .public)")
        }
    }
}
