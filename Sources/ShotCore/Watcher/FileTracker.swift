import Foundation

public actor FileTracker {
    private let store: StateStore<ProcessingState>
    private var processing: Set<SourceFingerprint> = []

    public init(paths: ApplicationPaths) {
        self.store = StateStore(file: paths.stateDirectory.appending(path: "processed.json"), defaultValue: .init())
    }

    public func shouldProcess(_ fingerprint: SourceFingerprint) async throws -> Bool {
        let state = try store.load()
        if state.hasProcessed(fingerprint) {
            _ = try store.update { $0.pending.removeValue(forKey: fingerprint.path) }
            return false
        }
        guard !processing.contains(fingerprint) else { return false }
        processing.insert(fingerprint)
        return true
    }

    public func processed(_ record: ProcessedSource, deleteSource: Bool = false) async throws {
        let currentFingerprint = try? FileStabilizer().fingerprint(URL(filePath: record.fingerprint.path))
        try store.update { state in
            state.records[record.fingerprint.path] = record
            if let currentFingerprint, currentFingerprint != record.fingerprint {
                state.observed[record.fingerprint.path] = currentFingerprint
                state.pending[record.fingerprint.path] = currentFingerprint
            } else {
                state.observed[record.fingerprint.path] = record.fingerprint
                state.pending.removeValue(forKey: record.fingerprint.path)
            }
            if deleteSource {
                state.pendingDeletions[record.fingerprint.path] = record.fingerprint
            }
        }
        processing = processing.filter { $0.path != record.fingerprint.path }
    }

    public func failed(_ fingerprint: SourceFingerprint) {
        processing.remove(fingerprint)
    }

    public func reconcile(directory: URL, fingerprints: [SourceFingerprint]) async throws -> [SourceFingerprint] {
        let directoryPath = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let current = Dictionary(uniqueKeysWithValues: fingerprints.map { fingerprint in
            let path = URL(filePath: directoryPath, directoryHint: .isDirectory).appending(path: URL(filePath: fingerprint.path).lastPathComponent).path
            var normalized = fingerprint
            normalized.path = path
            return (path, normalized)
        })
        let stillPresentPending: ([String: SourceFingerprint]) -> [String: SourceFingerprint] = { pending in
            pending.filter { path, fingerprint in
                current[path] == fingerprint || (try? FileStabilizer().fingerprint(URL(filePath: path))) == fingerprint
            }
        }
        return try store.update { state in
            if state.requiresBaseline || state.watchDirectory != directoryPath {
                let retained = stillPresentPending(state.pending)
                state.watchDirectory = directoryPath
                state.observed = current.merging(retained) { current, _ in current }
                state.pending = retained
                state.requiresBaseline = false
                return retained.values.sorted { $0.path < $1.path }
            }

            state.observed.keys.filter {
                URL(filePath: $0).deletingLastPathComponent().path == directoryPath && current[$0] == nil
            }.forEach {
                state.observed.removeValue(forKey: $0)
                state.pending.removeValue(forKey: $0)
                state.pendingDeletions.removeValue(forKey: $0)
                state.records.removeValue(forKey: $0)
            }
            for (path, fingerprint) in current where state.observed[path] != fingerprint {
                state.observed[path] = fingerprint
                state.pending[path] = fingerprint
            }
            for path in state.pending.keys.filter({
                URL(filePath: $0).deletingLastPathComponent().path == directoryPath && current[$0] != state.pending[$0]
            }) {
                state.pending.removeValue(forKey: path)
            }
            return state.pending.values.sorted { $0.path < $1.path }
        }
    }

    public func requireBaseline() async throws {
        try store.update { state in
            state.requiresBaseline = true
        }
        processing.removeAll()
    }

    public func pendingDeletions() throws -> [SourceFingerprint] {
        try store.load().pendingDeletions.values.sorted { $0.path < $1.path }
    }

    public func completedDeletion(_ fingerprint: SourceFingerprint) throws {
        try store.update { state in
            if state.pendingDeletions[fingerprint.path] == fingerprint {
                state.pendingDeletions.removeValue(forKey: fingerprint.path)
            }
        }
    }
}
