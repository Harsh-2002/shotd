import Foundation
import Security

public struct StorageCredentials: Codable, Sendable, Equatable {
    public let accessKeyID: String
    public let secretAccessKey: String
    public let sessionToken: String?

    public init(accessKeyID: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }
}

public enum CredentialStore {
    private static let service = "io.shotd.storage"

    public static func set(_ credentials: StorageCredentials, named name: String) throws {
        guard !name.isEmpty, !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
            throw ShotdError.invalidArguments("Credential name, access key ID, and secret access key are required.")
        }
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw keychainError(addStatus) }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }
    }

    public static func get(named name: String) throws -> StorageCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw status == errSecItemNotFound ? ShotdError.storage("No Keychain credentials named \(name).") : keychainError(status)
        }
        do {
            return try JSONDecoder().decode(StorageCredentials.self, from: data)
        } catch {
            throw ShotdError.storage("Stored Keychain credentials are invalid.")
        }
    }

    public static func get(for configuration: StorageConfiguration) throws -> StorageCredentials {
        if let credentials = configuration.developmentCredentials {
            guard URL(string: configuration.endpoint)?.host()?.lowercased() == "localhost" else {
                throw ShotdError.invalidConfiguration("Development credentials can be used only with localhost storage.")
            }
            return credentials
        }
        return try get(named: configuration.credential)
    }

    public static func delete(named name: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
    }

    private static func keychainError(_ status: OSStatus) -> ShotdError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        return .storage(message)
    }
}
