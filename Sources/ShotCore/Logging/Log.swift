import Foundation
import OSLog

public enum Log {
    private static let subsystem = "io.shotd"
    public static let runtime = Logger(subsystem: subsystem, category: "runtime")
    public static let configuration = Logger(subsystem: subsystem, category: "configuration")
    public static let processing = Logger(subsystem: subsystem, category: "processing")
    public static let storage = Logger(subsystem: subsystem, category: "storage")

    public static func error(_ message: String) {
        fputs("shotd: \(message)\n", stderr)
        runtime.error("\(message, privacy: .public)")
    }

    public static func info(_ message: String) {
        print(message)
        runtime.info("\(message, privacy: .public)")
    }
}
