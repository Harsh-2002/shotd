import Foundation

public actor S3Client {
    private let configuration: StorageConfiguration
    private let credentials: StorageCredentials
    private let signer: S3Signer
    private let session: URLSession

    public init(configuration: StorageConfiguration, credentials: StorageCredentials, session: URLSession = .shared) {
        self.configuration = configuration
        self.credentials = credentials
        self.signer = S3Signer(region: configuration.region)
        self.session = session
    }

    public func put(data: Data, key: String, contentType: String) async throws {
        var request = URLRequest(url: try objectURL(for: key))
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        let signed = try signer.sign(request, payload: data, credentials: credentials)
        let (_, response) = try await session.upload(for: signed, from: data)
        try validate(response, operation: "upload")
    }

    public func head(key: String) async throws {
        var request = URLRequest(url: try objectURL(for: key))
        request.httpMethod = "HEAD"
        let signed = try signer.sign(request, payload: Data(), credentials: credentials)
        let (_, response) = try await session.data(for: signed)
        try validate(response, operation: "HEAD")
    }

    public func delete(key: String) async throws {
        var request = URLRequest(url: try objectURL(for: key))
        request.httpMethod = "DELETE"
        let signed = try signer.sign(request, payload: Data(), credentials: credentials)
        let (_, response) = try await session.data(for: signed)
        try validate(response, operation: "delete")
    }

    public func createMultipartUpload(key: String, contentType: String) async throws -> String {
        var request = URLRequest(url: try requestURL(for: key, query: [.init(name: "uploads", value: "")]))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let signed = try signer.sign(request, payload: Data(), credentials: credentials)
        let (data, response) = try await session.data(for: signed)
        try validate(response, operation: "create multipart upload")
        guard let uploadID = XMLValueParser.value(named: "UploadId", in: data), !uploadID.isEmpty else {
            throw ShotdError.storage("S3 did not return a multipart upload ID.")
        }
        return uploadID
    }

    public func uploadPart(data: Data, key: String, uploadID: String, partNumber: Int) async throws -> String {
        var request = URLRequest(url: try requestURL(for: key, query: [.init(name: "partNumber", value: String(partNumber)), .init(name: "uploadId", value: uploadID)]))
        request.httpMethod = "PUT"
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        let signed = try signer.sign(request, payload: data, credentials: credentials)
        let (_, response) = try await session.upload(for: signed, from: data)
        try validate(response, operation: "upload multipart part")
        guard let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"), !etag.isEmpty else {
            throw ShotdError.storage("S3 did not return an ETag for multipart part \(partNumber).")
        }
        return etag
    }

    public func completeMultipartUpload(key: String, uploadID: String, parts: [(number: Int, eTag: String)]) async throws {
        let body = "<CompleteMultipartUpload>" + parts.sorted { $0.number < $1.number }.map { "<Part><PartNumber>\($0.number)</PartNumber><ETag>\(Self.xmlEscape($0.eTag))</ETag></Part>" }.joined() + "</CompleteMultipartUpload>"
        let data = Data(body.utf8)
        var request = URLRequest(url: try requestURL(for: key, query: [.init(name: "uploadId", value: uploadID)]))
        request.httpMethod = "POST"
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        let signed = try signer.sign(request, payload: data, credentials: credentials)
        let (_, response) = try await session.upload(for: signed, from: data)
        try validate(response, operation: "complete multipart upload")
    }

    public func abortMultipartUpload(key: String, uploadID: String) async throws {
        var request = URLRequest(url: try requestURL(for: key, query: [.init(name: "uploadId", value: uploadID)]))
        request.httpMethod = "DELETE"
        let signed = try signer.sign(request, payload: Data(), credentials: credentials)
        let (_, response) = try await session.data(for: signed)
        try validate(response, operation: "abort multipart upload")
    }

    public func remoteURL(for key: String) throws -> URL {
        if let base = configuration.publicBaseURL, let baseURL = URL(string: base) {
            return baseURL.appending(path: key)
        }
        return try signer.presignedGET(url: objectURL(for: key), credentials: credentials, expiresIn: configuration.presignExpirationSeconds)
    }

    public func objectURL(for key: String) throws -> URL {
        guard !key.hasPrefix("/"), !key.contains(".."), var components = URLComponents(string: configuration.endpoint), let endpointHost = components.host else {
            throw ShotdError.storage("Invalid S3 object key or endpoint.")
        }
        let encodedKey = key.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")) ?? String($0) }.joined(separator: "/")
        switch configuration.addressing {
        case .virtualHost:
            components.host = "\(configuration.bucket).\(endpointHost)"
            components.percentEncodedPath = "/\(encodedKey)"
        case .path, .auto:
            let bucket = configuration.bucket.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")) ?? configuration.bucket
            components.percentEncodedPath = "/\(bucket)/\(encodedKey)"
        }
        guard let url = components.url else { throw ShotdError.storage("Unable to construct S3 object URL.") }
        return url
    }

    private func requestURL(for key: String, query: [URLQueryItem]) throws -> URL {
        let url = try objectURL(for: key)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw ShotdError.storage("Unable to construct S3 request URL.") }
        components.queryItems = query
        guard let result = components.url else { throw ShotdError.storage("Unable to construct S3 request URL.") }
        return result
    }

    private func validate(_ response: URLResponse, operation: String) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ShotdError.storage("S3 \(operation) failed with HTTP \(status).")
        }
    }

    private static func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class XMLValueParser: NSObject, XMLParserDelegate {
    private let target: String
    private var collecting = false
    private var result = ""

    private init(target: String) { self.target = target }

    static func value(named name: String, in data: Data) -> String? {
        let delegate = XMLValueParser(target: name)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        return parser.parse() ? delegate.result : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        collecting = elementName == target
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { result += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == target { collecting = false }
    }
}
