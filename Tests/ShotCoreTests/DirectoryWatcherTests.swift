import XCTest
@testable import ShotCore

final class DirectoryWatcherTests: XCTestCase {
    func testWatcherReattachesWhenDirectoryIsRecreated() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let watched = root.appending(path: "watched", directoryHint: .isDirectory)
        let moved = root.appending(path: "moved", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        let observed = expectation(description: "recreated directory event")
        let watcher = DirectoryWatcher(directory: watched) { files in
            if files.contains(where: { $0.lastPathComponent == "new.png" }) {
                observed.fulfill()
            }
        }
        try watcher.start()
        defer { watcher.stop() }

        try FileManager.default.moveItem(at: watched, to: moved)
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: watched.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: watched.path))
        try Data([1]).write(to: watched.appending(path: "new.png"))

        await fulfillment(of: [observed], timeout: 3)
    }
}
