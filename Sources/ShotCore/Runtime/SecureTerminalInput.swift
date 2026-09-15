import Darwin
import Foundation

enum SecureTerminalInput {
    static func read(prompt: String, secret: Bool, allowEmpty: Bool = false) throws -> String {
        FileHandle.standardOutput.write(Data(prompt.utf8))
        guard secret, isatty(STDIN_FILENO) == 1 else {
            guard let value = readLine(), allowEmpty || !value.isEmpty else { throw ShotdError.invalidArguments("A non-empty value is required.") }
            return value
        }
        var attributes = termios()
        guard tcgetattr(STDIN_FILENO, &attributes) == 0 else { throw ShotdError.filesystem("Unable to read terminal settings.") }
        var original = attributes
        attributes.c_lflag &= ~tcflag_t(ECHO)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &attributes) == 0 else { throw ShotdError.filesystem("Unable to disable terminal echo.") }
        defer {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &original)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        guard let value = readLine(), allowEmpty || !value.isEmpty else { throw ShotdError.invalidArguments("A non-empty value is required.") }
        return value
    }
}
