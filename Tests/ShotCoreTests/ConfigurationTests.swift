import XCTest
@testable import ShotCore

final class ConfigurationTests: XCTestCase {
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
    }

    func testCalendarReleaseVersionsCompareChronologically() {
        XCTAssertTrue(BuildInfo.isNewer("v2026.09.16", than: "v2026.09.15"))
        XCTAssertFalse(BuildInfo.isNewer("v2026.09.15", than: "v2026.09.15"))
        XCTAssertFalse(BuildInfo.isNewer("v2026.09.14", than: "v2026.09.15"))
        XCTAssertFalse(BuildInfo.isNewer("0.2.0", than: "v2026.09.15"))
    }

    func testReleaseAssetNameIncludesVersionAndArchitecture() {
        XCTAssertEqual(BuildInfo.assetName(for: "v2026.09.15", architecture: "arm64"), "shotd-v2026.09.15-macos-arm64.zip")
    }
}
