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
}
