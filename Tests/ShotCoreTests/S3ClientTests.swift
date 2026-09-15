import XCTest
@testable import ShotCore

final class S3ClientTests: XCTestCase {
    func testObjectURLPercentEncodesEachKeySegmentOnce() async throws {
        let configuration = StorageConfiguration(
            endpoint: "http://localhost:9000",
            bucket: "shotd-test",
            credential: "test",
            addressing: .path
        )
        let client = S3Client(
            configuration: configuration,
            credentials: .init(accessKeyID: "test", secretAccessKey: "test")
        )

        let url = try await client.objectURL(for: "folder/a file%#?.txt")

        XCTAssertEqual(url.absoluteString, "http://localhost:9000/shotd-test/folder/a%20file%25%23%3F.txt")
    }
}
