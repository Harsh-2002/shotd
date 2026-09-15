import Foundation

public actor FileTracker {
    private let store: StateStore<ProcessingState>
    private var state: ProcessingState?
    private var processing: Set<SourceFingerprint> = []

    public init(paths: ApplicationPaths) {
        self.store = StateStore(file: paths.stateDirectory.appending(path: "processed.json"), defaultValue: .init())
    }

    public func shouldProcess(_ fingerprint: SourceFingerprint) async throws -> Bool {
        let state = try await loaded()
        guard !state.hasProcessed(fingerprint), !processing.contains(fingerprint) else { return false }
        processing.insert(fingerprint)
        return true
    }

    public func processed(_ record: ProcessedSource) async throws {
        var state = try await loaded()
        state.records[record.fingerprint.path] = record
        try await store.save(state)
        self.state = state
        processing.remove(record.fingerprint)
    }

    public func failed(_ fingerprint: SourceFingerprint) {
        processing.remove(fingerprint)
    }

    private func loaded() async throws -> ProcessingState {
        if let state { return state }
        let state = try await store.load()
        self.state = state
        return state
    }
}
