import XCTest
@testable import ShotCore

final class ConfigurationTests: XCTestCase {
    func testApplicationPathsUseSettingsFilename() {
        let paths = ApplicationPaths(home: URL(filePath: "/tmp/shotd-test-home"))
        XCTAssertEqual(paths.configuration.lastPathComponent, "settings.json")
        XCTAssertEqual(paths.legacyConfiguration.lastPathComponent, "config.json")
    }

    func testLegacyConfigurationMigratesWithoutSettingsLoss() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ApplicationPaths(home: home)
        try paths.createRequiredDirectories()
        var expected = ShotdConfiguration()
        expected.image.quality = 73
        let data = try JSONEncoder().encode(expected)
        try data.write(to: paths.legacyConfiguration)

        let loaded = try await ConfigLoader(paths: paths).loadOrCreateDefault()

        XCTAssertEqual(loaded.image.quality, 73)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configuration.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.legacyConfiguration.path))
        let persisted = try JSONDecoder().decode(ShotdConfiguration.self, from: Data(contentsOf: paths.configuration))
        XCTAssertEqual(persisted.image.quality, 73)
    }

    func testInvalidLegacyConfigurationIsNotRemoved() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ApplicationPaths(home: home)
        try paths.createRequiredDirectories()
        try Data("not json".utf8).write(to: paths.legacyConfiguration)

        do {
            _ = try await ConfigLoader(paths: paths).loadOrCreateDefault()
            XCTFail("Expected invalid legacy configuration to be rejected")
        } catch {}

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.legacyConfiguration.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configuration.path))
    }

    func testAuthoritativeSettingsDoNotRemoveLegacyFile() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ApplicationPaths(home: home)
        try paths.createRequiredDirectories()
        var settings = ShotdConfiguration()
        settings.image.quality = 61
        try JSONEncoder().encode(settings).write(to: paths.configuration)
        try Data("legacy backup".utf8).write(to: paths.legacyConfiguration)

        let loader = ConfigLoader(paths: paths)
        let loaded = try await loader.load()
        try await loader.write(loaded)

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.legacyConfiguration.path))
        XCTAssertEqual(try String(contentsOf: paths.legacyConfiguration, encoding: .utf8), "legacy backup")
    }

    func testDefaultConfigurationIsValid() throws {
        let paths = try ApplicationPaths()
        XCTAssertNoThrow(try ConfigValidator.validate(ShotdConfiguration(), paths: paths))
    }

    func testSpecificScreenRequiresIdentifier() throws {
        let paths = try ApplicationPaths()
        var configuration = ShotdConfiguration()
        configuration.background.screen = .specific
        XCTAssertThrowsError(try ConfigValidator.validate(configuration, paths: paths))
    }

    func testLossyQualityHasBoundaries() throws {
        let paths = try ApplicationPaths()
        var configuration = ShotdConfiguration()
        configuration.image.quality = 101
        XCTAssertThrowsError(try ConfigValidator.validate(configuration, paths: paths))
    }

    func testWatchAndOutputDirectoriesCannotOverlap() throws {
        let paths = try ApplicationPaths()
        var configuration = ShotdConfiguration()
        configuration.watch.directory = "~/Pictures/Screenshots"
        configuration.output.directory = "~/Pictures/Screenshots/shotd"
        XCTAssertThrowsError(try ConfigValidator.validate(configuration, paths: paths))
        XCTAssertTrue(ConfigValidator.directoriesOverlap(
            watch: configuration.watch.directory,
            output: configuration.output.directory,
            paths: paths
        ))
        XCTAssertFalse(ConfigValidator.directoriesOverlap(
            watch: "~/Pictures/Screenshots",
            output: "~/Pictures/shotd-output",
            paths: paths
        ))
    }

    func testWatchAndOutputDirectoriesCannotOverlapThroughSymlink() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let real = home.appending(path: "real", directoryHint: .isDirectory)
        let watch = real.appending(path: "screens", directoryHint: .isDirectory)
        let alias = home.appending(path: "alias", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let paths = ApplicationPaths(home: home)

        XCTAssertTrue(ConfigValidator.directoriesOverlap(
            watch: watch.path,
            output: alias.appending(path: "screens/output").path,
            paths: paths
        ))
    }

    func testDirectoriesCannotEscapeHomeThroughPrefixOrSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        let outside = root.appending(path: "home-other", directoryHint: .isDirectory)
        let link = home.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let paths = ApplicationPaths(home: home)
        var configuration = ShotdConfiguration()
        configuration.watch.directory = outside.appending(path: "screens").path
        configuration.output.directory = home.appending(path: "output").path
        XCTAssertThrowsError(try ConfigValidator.validate(configuration, paths: paths))

        configuration.watch.directory = link.appending(path: "screens").path
        XCTAssertThrowsError(try ConfigValidator.validate(configuration, paths: paths))
    }

    func testCalendarReleaseVersionsCompareChronologically() {
        XCTAssertTrue(BuildInfo.isNewer("v2026.09.16", than: "v2026.09.15"))
        XCTAssertFalse(BuildInfo.isNewer("v2026.09.15", than: "v2026.09.15"))
        XCTAssertFalse(BuildInfo.isNewer("v2026.09.14", than: "v2026.09.15"))
        XCTAssertFalse(BuildInfo.isNewer("0.2.0", than: "v2026.09.15"))
    }

    func testReleaseAssetNameIncludesVersionAndArchitecture() {
        XCTAssertEqual(BuildInfo.assetName(for: "v2026.09.15", architecture: "arm64"), "shotd-v2026.09.15-macos-arm64.zip")
        XCTAssertEqual(
            BuildInfo.binaryChecksumAssetName(for: "v2026.09.15", architecture: "arm64"),
            "shotd-v2026.09.15-macos-arm64.binary.sha256"
        )
    }
}
