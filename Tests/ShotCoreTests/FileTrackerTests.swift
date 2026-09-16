import Foundation
import XCTest
@testable import ShotCore

final class FileTrackerTests: XCTestCase {
    func testFirstEnrollmentBaselinesExistingFilesAndOnlyReturnsLaterChanges() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ApplicationPaths(home: home)
        let tracker = FileTracker(paths: paths)
        let directory = home.appending(path: "Screenshots", directoryHint: .isDirectory)
        let old = fingerprint(directory.appending(path: "old.png"), inode: 1)

        let baseline = try await tracker.reconcile(directory: directory, fingerprints: [old])
        XCTAssertTrue(baseline.isEmpty)
        let unchanged = try await tracker.reconcile(directory: directory, fingerprints: [old])
        XCTAssertTrue(unchanged.isEmpty)

        let new = fingerprint(directory.appending(path: "new.png"), inode: 2)
        let added = try await tracker.reconcile(directory: directory, fingerprints: [old, new])
        XCTAssertEqual(added, [new])
        try await tracker.processed(.init(fingerprint: new, outputPath: "/output/new.png"))
        let processed = try await tracker.reconcile(directory: directory, fingerprints: [old, new])
        XCTAssertTrue(processed.isEmpty)

        let changed = fingerprint(directory.appending(path: "old.png"), inode: 3)
        let modified = try await tracker.reconcile(directory: directory, fingerprints: [changed, new])
        XCTAssertEqual(modified, [changed])
    }

    func testWatchDirectoryChangeAndExplicitResetCreateFreshBaseline() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let tracker = FileTracker(paths: ApplicationPaths(home: home))
        let first = home.appending(path: "First", directoryHint: .isDirectory)
        let second = home.appending(path: "Second", directoryHint: .isDirectory)
        let firstFile = fingerprint(first.appending(path: "first.png"), inode: 1)
        let secondFile = fingerprint(second.appending(path: "historical.png"), inode: 2)

        let firstBaseline = try await tracker.reconcile(directory: first, fingerprints: [firstFile])
        XCTAssertTrue(firstBaseline.isEmpty)
        let secondBaseline = try await tracker.reconcile(directory: second, fingerprints: [secondFile])
        XCTAssertTrue(secondBaseline.isEmpty)

        let whileUninstalled = fingerprint(second.appending(path: "offline.png"), inode: 3)
        try await tracker.requireBaseline()
        let reinstallBaseline = try await tracker.reconcile(directory: second, fingerprints: [secondFile, whileUninstalled])
        XCTAssertTrue(reinstallBaseline.isEmpty)
    }

    func testWatchDirectoryChangeRetainsDetectedWorkFromOldDirectory() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let first = home.appending(path: "First", directoryHint: .isDirectory)
        let second = home.appending(path: "Second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let tracker = FileTracker(paths: ApplicationPaths(home: home))
        let old = try writeFingerprint(first.appending(path: "old.png"), byte: 1)
        let pending = try writeFingerprint(first.appending(path: "pending.png"), byte: 2)
        let historical = try writeFingerprint(second.appending(path: "historical.png"), byte: 3)

        _ = try await tracker.reconcile(directory: first, fingerprints: [old])
        _ = try await tracker.reconcile(directory: first, fingerprints: [old, pending])
        let afterSwitch = try await tracker.reconcile(directory: second, fingerprints: [historical])
        let afterSecondScan = try await tracker.reconcile(directory: second, fingerprints: [historical])

        XCTAssertEqual(afterSwitch, [pending])
        XCTAssertEqual(afterSecondScan, [pending])
    }

    func testExplicitResetPreservesAlreadyPendingWorkButBaselinesOfflineFiles() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let tracker = FileTracker(paths: ApplicationPaths(home: home))
        let directory = home.appending(path: "Screenshots", directoryHint: .isDirectory)
        let old = fingerprint(directory.appending(path: "old.png"), inode: 1)
        let pending = fingerprint(directory.appending(path: "pending.png"), inode: 2)
        let offline = fingerprint(directory.appending(path: "offline.png"), inode: 3)

        _ = try await tracker.reconcile(directory: directory, fingerprints: [old])
        let detected = try await tracker.reconcile(directory: directory, fingerprints: [old, pending])
        XCTAssertEqual(detected, [pending])
        try await tracker.requireBaseline()

        let recovered = try await tracker.reconcile(directory: directory, fingerprints: [old, pending, offline])
        XCTAssertEqual(recovered, [pending])
    }

    func testIndependentTrackersDoNotOverwritePendingState() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ApplicationPaths(home: home)
        let first = FileTracker(paths: paths)
        let second = FileTracker(paths: paths)
        let directory = home.appending(path: "Screenshots", directoryHint: .isDirectory)
        let old = fingerprint(directory.appending(path: "old.png"), inode: 1)
        let addedA = fingerprint(directory.appending(path: "a.png"), inode: 2)
        let addedB = fingerprint(directory.appending(path: "b.png"), inode: 3)

        _ = try await first.reconcile(directory: directory, fingerprints: [old])
        let firstPending = try await first.reconcile(directory: directory, fingerprints: [old, addedA])
        XCTAssertEqual(firstPending, [addedA])
        let pending = try await second.reconcile(directory: directory, fingerprints: [old, addedA, addedB])
        XCTAssertEqual(Set(pending), Set([addedA, addedB]))
    }

    func testEquivalentSymlinkWatchPathsDoNotReplayExistingFiles() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let real = home.appending(path: "real", directoryHint: .isDirectory)
        let firstAlias = home.appending(path: "alias-a", directoryHint: .isDirectory)
        let secondAlias = home.appending(path: "alias-b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: firstAlias, withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: secondAlias, withDestinationURL: real)
        let tracker = FileTracker(paths: ApplicationPaths(home: home))
        let firstFingerprint = fingerprint(firstAlias.appending(path: "old.png"), inode: 1)
        let secondFingerprint = fingerprint(secondAlias.appending(path: "old.png"), inode: 1)

        _ = try await tracker.reconcile(directory: firstAlias, fingerprints: [firstFingerprint])
        let replayed = try await tracker.reconcile(directory: secondAlias, fingerprints: [secondFingerprint])
        XCTAssertTrue(replayed.isEmpty)
    }

    func testLegacyStateRequiresSafeBaseline() throws {
        let old = fingerprint(URL(filePath: "/tmp/old.png"), inode: 1)
        let legacy = try JSONEncoder().encode(["records": [old.path: ProcessedSource(fingerprint: old, outputPath: "/tmp/output.png")]])
        let decoded = try JSONDecoder().decode(ProcessingState.self, from: legacy)

        XCTAssertTrue(decoded.requiresBaseline)
        XCTAssertTrue(decoded.observed.isEmpty)
        XCTAssertEqual(decoded.records.count, 1)
    }

    func testFutureStateSchemaIsRejectedWithoutChangingTheFile() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ApplicationPaths(home: home)
        try paths.createRequiredDirectories()
        let stateFile = paths.stateDirectory.appending(path: "processed.json")
        let original = Data("{\"schemaVersion\":999,\"futureField\":true}".utf8)
        try original.write(to: stateFile)

        do {
            _ = try await FileTracker(paths: paths).reconcile(directory: home, fingerprints: [])
            XCTFail("Expected a newer schema to be rejected")
        } catch let error as PersistentStateError {
            XCTAssertEqual(error.localizedDescription, "Persistent state schema 999 is newer than supported schema 2. Update shotd before continuing.")
        }
        XCTAssertEqual(try Data(contentsOf: stateFile), original)
    }

    func testPendingSourceDeletionSurvivesRestartUntilCompleted() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ApplicationPaths(home: home)
        let directory = home.appending(path: "Screenshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try writeFingerprint(directory.appending(path: "delete.png"), byte: 1)
        let tracker = FileTracker(paths: paths)
        _ = try await tracker.reconcile(directory: directory, fingerprints: [])
        _ = try await tracker.reconcile(directory: directory, fingerprints: [source])
        try await tracker.processed(.init(fingerprint: source, outputPath: "/tmp/output.png"), deleteSource: true)

        let restored = try await FileTracker(paths: paths).pendingDeletions()
        XCTAssertEqual(restored, [source])

        try await FileTracker(paths: paths).completedDeletion(source)
        let completed = try await FileTracker(paths: paths).pendingDeletions()
        XCTAssertTrue(completed.isEmpty)
    }

    func testReplacementCompletionClearsOriginalFingerprintFromInFlightSet() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let tracker = FileTracker(paths: ApplicationPaths(home: home))
        let original = fingerprint(home.appending(path: "capture.png"), inode: 1)
        let replacement = fingerprint(home.appending(path: "capture.png"), inode: 2)

        let started = try await tracker.shouldProcess(original)
        XCTAssertTrue(started)
        try await tracker.processed(.init(fingerprint: replacement, outputPath: replacement.path))
        let restarted = try await tracker.shouldProcess(original)
        XCTAssertTrue(restarted)
    }

    func testCompletionDoesNotDiscardANewerEditAtTheSamePath() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appending(path: "Screenshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appending(path: "capture.png")
        let original = try writeFingerprint(source, byte: 1)
        let tracker = FileTracker(paths: ApplicationPaths(home: home))
        _ = try await tracker.reconcile(directory: directory, fingerprints: [])
        _ = try await tracker.reconcile(directory: directory, fingerprints: [original])
        _ = try await tracker.shouldProcess(original)

        let edited = try writeFingerprint(source, byte: 2)
        _ = try await tracker.reconcile(directory: directory, fingerprints: [edited])
        try await tracker.processed(.init(fingerprint: original, outputPath: "/tmp/output.png"))

        let pending = try await tracker.reconcile(directory: directory, fingerprints: [edited])
        XCTAssertEqual(pending, [edited])
    }

    private func fingerprint(_ url: URL, inode: UInt64) -> SourceFingerprint {
        SourceFingerprint(path: url.path, inode: inode, size: inode * 10, modificationTime: Date(timeIntervalSince1970: TimeInterval(inode)))
    }

    private func writeFingerprint(_ url: URL, byte: UInt8) throws -> SourceFingerprint {
        try Data([byte]).write(to: url)
        return try FileStabilizer().fingerprint(url)
    }
}
