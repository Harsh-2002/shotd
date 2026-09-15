import Foundation

public enum BuildInfo {
    public static let version = "v2026.09.15"
    public static let repository = "Harsh-2002/shotd"

    public static func isNewer(_ candidate: String, than current: String = version) -> Bool {
        guard let candidateParts = versionParts(candidate), let currentParts = versionParts(current) else { return false }
        return candidateParts.lexicographicallyPrecedes(currentParts) == false && candidateParts != currentParts
    }

    public static func assetName(for version: String, architecture: String) -> String {
        "shotd-\(version)-macos-\(architecture).zip"
    }

    public static func binaryChecksumAssetName(for version: String, architecture: String) -> String {
        "shotd-\(version)-macos-\(architecture).binary.sha256"
    }

    private static func versionParts(_ value: String) -> [Int]? {
        let parts = value.drop(while: { $0 == "v" }).split(separator: ".")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }
        return [year, month, day]
    }
}
