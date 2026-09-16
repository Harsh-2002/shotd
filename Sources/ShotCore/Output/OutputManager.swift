import Foundation
import UniformTypeIdentifiers

public enum OutputKind: Sendable { case image, video }

public struct OutputFormat: Sendable, Equatable {
    public let fileExtension: String
    public let mimeType: String

    public init(fileExtension: String, mimeType: String) {
        self.fileExtension = fileExtension
        self.mimeType = mimeType
    }

    public static func image(for format: ImageFormat) -> OutputFormat? {
        switch format {
        case .png: .init(fileExtension: "png", mimeType: "image/png")
        case .webp: .init(fileExtension: "webp", mimeType: "image/webp")
        case .avif: .init(fileExtension: "avif", mimeType: "image/avif")
        case .heic: .init(fileExtension: "heic", mimeType: "image/heic")
        case .jpeg: .init(fileExtension: "jpg", mimeType: "image/jpeg")
        case .preserve: nil
        }
    }

    public static func video(for format: VideoFormat) -> OutputFormat {
        switch format {
        case .mp4: .init(fileExtension: "mp4", mimeType: "video/mp4")
        case .mov: .init(fileExtension: "mov", mimeType: "video/quicktime")
        }
    }
}

public struct OutputManager: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func destination(for source: URL, format: OutputFormat) -> URL {
        let base = Self.sanitizedBaseName(source.deletingPathExtension().lastPathComponent)
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        return directory.appending(path: "\(base)-\(id).\(format.fileExtension)")
    }

    public func objectKey(for source: URL, kind: OutputKind, format: OutputFormat, prefix: String, now: Date = .now) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: now)
        let month = String(format: "%02d", components.month ?? 1)
        let id = String(UUID().uuidString.prefix(6)).lowercased()
        let base = Self.sanitizedBaseName(source.deletingPathExtension().lastPathComponent)
        let cleanPrefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(cleanPrefix)/\(components.year ?? 1970)/\(month)/\(id)-\(base).\(format.fileExtension)"
    }

    public static func sanitizedBaseName(_ value: String) -> String {
        let permitted = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. "))
        let sanitized = value.unicodeScalars.map { permitted.contains($0) ? Character(String($0)) : "-" }
        let collapsed = String(sanitized).replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "capture" : String(collapsed.prefix(120))
    }

    public func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}
