import Darwin
import Dispatch
import Foundation

public final class SignalHandler: @unchecked Sendable {
    private let sources: [DispatchSourceSignal]

    public init(handler: @escaping @Sendable () -> Void) {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        self.sources = [SIGINT, SIGTERM].map { signalNumber in
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .userInitiated))
            source.setEventHandler(handler: handler)
            source.resume()
            return source
        }
    }

    public func cancel() {
        sources.forEach { $0.cancel() }
    }
}
