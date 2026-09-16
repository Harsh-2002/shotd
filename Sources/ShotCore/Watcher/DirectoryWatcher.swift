import Darwin
import Dispatch
import Foundation

public final class DirectoryWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([URL]) -> Void

    private let directory: URL
    private let queue: DispatchQueue
    private let handler: Handler
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var active = false

    public init(directory: URL, queue: DispatchQueue = DispatchQueue(label: "io.shotd.directory-watcher", qos: .utility), handler: @escaping Handler) {
        self.directory = directory
        self.queue = queue
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        lock.lock()
        guard !active else { lock.unlock(); return }
        active = true
        lock.unlock()
        do {
            try attach()
        } catch {
            lock.lock()
            active = false
            lock.unlock()
            throw error
        }
    }

    private func attach() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { throw ShotdError.filesystem("Unable to watch \(directory.path).") }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let source else { return }
            self?.directoryDidChange(events: source.data)
        }
        source.setCancelHandler { close(descriptor) }
        lock.lock()
        guard active, self.source == nil else {
            lock.unlock()
            source.resume()
            source.cancel()
            return
        }
        self.descriptor = descriptor
        self.source = source
        lock.unlock()
        source.resume()
    }

    public func stop() {
        lock.lock()
        active = false
        let existingSource = source
        source = nil
        descriptor = -1
        lock.unlock()
        existingSource?.cancel()
    }

    public func currentFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]).filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func directoryDidChange(events: DispatchSource.FileSystemEvent) {
        if events.contains(.rename) || events.contains(.delete) {
            lock.lock()
            let oldSource = source
            source = nil
            descriptor = -1
            let shouldReattach = active
            lock.unlock()
            oldSource?.cancel()
            if shouldReattach { scheduleReattach() }
            return
        }
        do {
            handler(try currentFiles())
        } catch {
            Log.processing.error("Unable to enumerate watched directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleReattach() {
        queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            guard let self else { return }
            do {
                try self.attach()
                self.handler(try self.currentFiles())
            } catch {
                self.lock.lock()
                let retry = self.active
                self.lock.unlock()
                if retry { self.scheduleReattach() }
            }
        }
    }
}
