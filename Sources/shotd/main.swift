import Foundation
import ShotCore

@main
struct ShotdMain {
    static func main() async {
        let runner = CommandRunner(arguments: Array(CommandLine.arguments.dropFirst()))
        let exitCode = await runner.run()
        Foundation.exit(exitCode.rawValue)
    }
}
