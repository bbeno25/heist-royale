import Foundation
import HeistCore

/// One app connection. `send` queues the message and returns at once, so messages reach the app in the
/// order they were sent; the WebSocket layer (or a test) drains the queue.
public protocol ClientLink: AnyObject, Sendable {
    var linkID: UUID { get }
    func send(_ envelope: ServerEnvelope)
    func close()
}

extension ClientLink {
    func send(_ message: ServerMessage) {
        send(ServerEnvelope(message))
    }

    func sendError(_ code: String, _ message: String) {
        send(.error(.init(code: code, message: message)))
    }
}

extension ServerEnvelope {
    /// The JSON text that goes over the wire.
    public func json() -> String {
        (try? String(decoding: JSONEncoder.wire.encode(self), as: UTF8.self)) ?? "{}"
    }
}

/// Milliseconds since 1970, the clock deadlines are sent in.
func wallClock(after duration: Duration = .zero) -> Int64 {
    Int64((Date().timeIntervalSince1970 + duration.seconds) * 1000)
}
