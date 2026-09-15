import Foundation

public enum ShotdError: LocalizedError, Sendable {
    case invalidArguments(String)
    case invalidConfiguration(String)
    case filesystem(String)
    case unsupported(String)
    case processing(String)
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message), .invalidConfiguration(let message), .filesystem(let message), .unsupported(let message), .processing(let message), .storage(let message):
            message
        }
    }
}
