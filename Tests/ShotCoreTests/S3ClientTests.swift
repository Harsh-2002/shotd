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

    func testOnboardingVerificationOperationsUseSignedRequests() async throws {
        let endpoint = MockURLProtocol.register(statuses: ["PUT": 200, "HEAD": 200, "DELETE": 204])
        defer { MockURLProtocol.remove(endpoint: endpoint) }
        let client = makeClient(endpoint: endpoint)
        let key = "shotd-diagnostics/check % # ?.txt"

        try await client.put(data: Data("verification".utf8), key: key, contentType: "text/plain")
        try await client.head(key: key)
        let remoteURL = try await client.remoteURL(for: key)
        try await client.delete(key: key)

        let requests = MockURLProtocol.requests(endpoint: endpoint)
        XCTAssertEqual(requests.map(\.httpMethod), ["PUT", "HEAD", "DELETE"])
        XCTAssertEqual(requests.compactMap { $0.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath } }, Array(repeating: "/shotd-test/shotd-diagnostics/check%20%25%20%23%20%3F.txt", count: 3))
        let putRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(putRequest.value(forHTTPHeaderField: "Content-Type"), "text/plain")
        XCTAssertEqual(putRequest.value(forHTTPHeaderField: "Content-Length"), "12")
        for request in requests {
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 Credential=test/") == true)
            XCTAssertNotNil(request.value(forHTTPHeaderField: "x-amz-date"))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "x-amz-content-sha256"))
        }

        let remoteComponents = try XCTUnwrap(URLComponents(url: remoteURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(remoteComponents.host, URL(string: endpoint)?.host)
        XCTAssertEqual(remoteComponents.percentEncodedPath, "/shotd-test/shotd-diagnostics/check%20%25%20%23%20%3F.txt")
        let query = Dictionary(uniqueKeysWithValues: (remoteComponents.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["X-Amz-Algorithm"], "AWS4-HMAC-SHA256")
        XCTAssertEqual(query["X-Amz-Expires"], "86400")
        XCTAssertEqual(query["X-Amz-SignedHeaders"], "host")
        XCTAssertNotNil(query["X-Amz-Signature"])
    }

    func testVerificationOperationsReportActionableHTTPFailures() async {
        let endpoint = MockURLProtocol.register(statuses: ["PUT": 403, "HEAD": 404, "DELETE": 500])
        defer { MockURLProtocol.remove(endpoint: endpoint) }
        let client = makeClient(endpoint: endpoint)

        await assertStorageError("S3 upload failed with HTTP 403.") {
            try await client.put(data: Data("test".utf8), key: "verification.txt", contentType: "text/plain")
        }
        await assertStorageError("S3 HEAD failed with HTTP 404.") {
            try await client.head(key: "verification.txt")
        }
        await assertStorageError("S3 delete failed with HTTP 500.") {
            try await client.delete(key: "verification.txt")
        }
    }

    private func makeClient(endpoint: String) -> S3Client {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        return S3Client(
            configuration: .init(endpoint: endpoint, bucket: "shotd-test", credential: "unused", addressing: .path),
            credentials: .init(accessKeyID: "test", secretAccessKey: "test"),
            session: URLSession(configuration: sessionConfiguration)
        )
    }

    private func assertStorageError(_ expected: String, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected storage operation to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, expected)
        }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Scenario {
        let statuses: [String: Int]
        var requests: [URLRequest] = []
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var scenarios: [String: Scenario] = [:]
    }

    private static let state = State()

    static func register(statuses: [String: Int]) -> String {
        let endpoint = "https://\(UUID().uuidString.lowercased()).example.test"
        state.lock.lock()
        state.scenarios[endpoint] = Scenario(statuses: statuses)
        state.lock.unlock()
        return endpoint
    }

    static func remove(endpoint: String) {
        state.lock.lock()
        state.scenarios.removeValue(forKey: endpoint)
        state.lock.unlock()
    }

    static func requests(endpoint: String) -> [URLRequest] {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.scenarios[endpoint]?.requests ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let endpoint = request.url.map({ "\($0.scheme ?? "")://\($0.host ?? "")" }) else { return false }
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.scenarios[endpoint] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let endpoint = "\(url.scheme ?? "")://\(url.host ?? "")"
        Self.state.lock.lock()
        Self.state.scenarios[endpoint]?.requests.append(request)
        let status = Self.state.scenarios[endpoint]?.statuses[request.httpMethod ?? ""]
        Self.state.lock.unlock()

        guard let status, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
