import CryptoKit
import Foundation

public struct S3Signer: Sendable {
    public let region: String
    public let service: String

    public init(region: String, service: String = "s3") {
        self.region = region == "auto" ? "us-east-1" : region
        self.service = service
    }

    public func sign(_ request: URLRequest, payload: Data, credentials: StorageCredentials, now: Date = .now) throws -> URLRequest {
        guard let url = request.url, url.host != nil else { throw ShotdError.storage("S3 request has no URL host.") }
        let timestamp = Self.timestamp(now)
        let payloadHash = Self.hex(SHA256.hash(data: payload))
        var signed = request
        signed.setValue(hostWithPort(url), forHTTPHeaderField: "Host")
        signed.setValue(timestamp, forHTTPHeaderField: "x-amz-date")
        signed.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        if let token = credentials.sessionToken { signed.setValue(token, forHTTPHeaderField: "x-amz-security-token") }
        let canonical = canonicalRequest(signed, payloadHash: payloadHash)
        let scopeDate = String(timestamp.prefix(8))
        let scope = "\(scopeDate)/\(region)/\(service)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(timestamp)\n\(scope)\n\(Self.hex(SHA256.hash(data: Data(canonical.text.utf8))))"
        let key = signingKey(secret: credentials.secretAccessKey, date: scopeDate)
        let signature = Self.hex(Self.hmac(Data(stringToSign.utf8), key: key))
        signed.setValue("AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(scope), SignedHeaders=\(canonical.signedHeaders), Signature=\(signature)", forHTTPHeaderField: "Authorization")
        return signed
    }

    public func presignedGET(url: URL, credentials: StorageCredentials, expiresIn: Int, now: Date = .now) throws -> URL {
        guard expiresIn > 0, expiresIn <= 604_800, url.host != nil else { throw ShotdError.storage("Invalid presigned URL request.") }
        let timestamp = Self.timestamp(now)
        let scopeDate = String(timestamp.prefix(8))
        let scope = "\(scopeDate)/\(region)/\(service)/aws4_request"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var query = components.queryItems ?? []
        query += [
            .init(name: "X-Amz-Algorithm", value: "AWS4-HMAC-SHA256"),
            .init(name: "X-Amz-Credential", value: "\(credentials.accessKeyID)/\(scope)"),
            .init(name: "X-Amz-Date", value: timestamp),
            .init(name: "X-Amz-Expires", value: String(expiresIn)),
            .init(name: "X-Amz-SignedHeaders", value: "host")
        ]
        if let token = credentials.sessionToken { query.append(.init(name: "X-Amz-Security-Token", value: token)) }
        components.queryItems = query
        guard let unsignedURL = components.url else { throw ShotdError.storage("Unable to create presigned URL.") }
        let canonicalQuery = canonicalQueryString(unsignedURL)
        let canonical = "GET\n\(canonicalPath(unsignedURL))\n\(canonicalQuery)\nhost:\(hostWithPort(unsignedURL))\n\nhost\nUNSIGNED-PAYLOAD"
        let stringToSign = "AWS4-HMAC-SHA256\n\(timestamp)\n\(scope)\n\(Self.hex(SHA256.hash(data: Data(canonical.utf8))))"
        let signature = Self.hex(Self.hmac(Data(stringToSign.utf8), key: signingKey(secret: credentials.secretAccessKey, date: scopeDate)))
        components.queryItems?.append(.init(name: "X-Amz-Signature", value: signature))
        guard let signedURL = components.url else { throw ShotdError.storage("Unable to finalize presigned URL.") }
        return signedURL
    }

    private func canonicalRequest(_ request: URLRequest, payloadHash: String) -> (text: String, signedHeaders: String) {
        let url = request.url!
        let headers = (request.allHTTPHeaderFields ?? [:]).map { key, value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return (key.lowercased(), normalized)
        }.sorted { $0.0 < $1.0 }
        let canonicalHeaders = headers.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = headers.map(\.0).joined(separator: ";")
        return ("\(request.httpMethod ?? "GET")\n\(canonicalPath(url))\n\(canonicalQueryString(url))\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)", signedHeaders)
    }

    private func signingKey(secret: String, date: String) -> SymmetricKey {
        let dateKey = Self.hmac(Data(date.utf8), key: SymmetricKey(data: Data("AWS4\(secret)".utf8)))
        let regionKey = Self.hmac(Data(region.utf8), key: SymmetricKey(data: dateKey))
        let serviceKey = Self.hmac(Data(service.utf8), key: SymmetricKey(data: regionKey))
        return SymmetricKey(data: Self.hmac(Data("aws4_request".utf8), key: SymmetricKey(data: serviceKey)))
    }

    private static func hmac(_ data: Data, key: SymmetricKey) -> Data { Data(HMAC<SHA256>.authenticationCode(for: data, using: key)) }
    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .init(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private func canonicalPath(_ url: URL) -> String {
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty else { return "/" }
        return "/" + components.map { Self.percentEncode(String($0)) }.joined(separator: "/")
    }

    private func canonicalQueryString(_ url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let pairs: [(String, String)] = items.map { item in
            (Self.percentEncode(item.name), Self.percentEncode(item.value ?? ""))
        }
        return pairs.sorted { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }
    private func hostWithPort(_ url: URL) -> String { guard let host = url.host else { return "" }; guard let port = url.port else { return host }; return "\(host):\(port)" }
    private static func percentEncode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")) ?? value }
}
