import Foundation
import HeistCore
import ServerCore

/// One connection to a game server. Messages to the server go out in the order they are sent; messages
/// from it reach `onEvent` in order on the main actor.
///
/// `.remote` is the real server over a WebSocket. `.local` runs the server's own logic (ServerCore) inside
/// the app, for the offline match against a bot: the same protocol, so the match screens can't tell.
@MainActor
final class GameConnection {
    enum Target {
        case remote(URL)
        case local(ServerConfig)
    }

    enum Event {
        case message(ServerEnvelope)
        /// The connection dropped or couldn't be made.
        case lost
    }

    var onEvent: (Event) -> Void = { _ in }
    let target: Target

    private var socket: URLSessionWebSocketTask?
    private var listener: Task<Void, Never>?
    private var local: (server: GameServer, link: LocalLink, outgoing: AsyncStream<String>.Continuation)?

    init(target: Target) {
        self.target = target
    }

    /// Connects and signs in; without `hello` it only connects (enough for the leaderboards).
    func open(_ hello: ClientMessage.Hello?) {
        close()
        switch target {
        case .remote(let url):
            let socket = URLSession.shared.webSocketTask(with: url)
            socket.maximumMessageSize = 1 << 20
            self.socket = socket
            socket.resume()
            listener = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        let message = try await socket.receive()
                        guard case .string(let text) = message,
                              let envelope = try? JSONDecoder().decode(ServerEnvelope.self, from: Data(text.utf8)) else { continue }
                        self?.onEvent(.message(envelope))
                    } catch {
                        if !Task.isCancelled { self?.onEvent(.lost) }
                        return
                    }
                }
            }
        case .local(let config):
            guard let store = try? PlayerStore(directory: nil, elo: config.elo, botNames: config.botNames) else { return }
            let server = GameServer(config: config, store: store)
            let link = LocalLink()
            let (outgoing, continuation) = AsyncStream<String>.makeStream()
            local = (server, link, continuation)
            // One task feeds the server in order, another hands its answers to the app in order.
            Task {
                await server.start()
                for await text in outgoing {
                    await server.receive(text, from: link)
                }
                await server.stop()
            }
            listener = Task { [weak self] in
                for await envelope in link.envelopes {
                    self?.onEvent(.message(envelope))
                }
            }
        }
        if let hello { send(.hello(hello)) }
    }

    func send(_ message: ClientMessage) {
        guard let data = try? JSONEncoder().encode(ClientEnvelope(message)) else { return }
        let text = String(decoding: data, as: UTF8.self)
        if let socket {
            socket.send(.string(text)) { _ in }
        } else {
            local?.outgoing.yield(text)
        }
    }

    func close() {
        listener?.cancel()
        listener = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        local?.outgoing.finish()
        local?.link.close()
        local = nil
    }
}

/// The in-app server's side of the offline connection.
private final class LocalLink: ClientLink {
    let linkID = UUID()
    let envelopes: AsyncStream<ServerEnvelope>
    private let continuation: AsyncStream<ServerEnvelope>.Continuation

    init() {
        (envelopes, continuation) = AsyncStream.makeStream()
    }

    func send(_ envelope: ServerEnvelope) {
        continuation.yield(envelope)
    }

    func close() {
        continuation.finish()
    }
}

/// Which server the app plays on, and the guest sign-in it keeps for it.
enum GameServerAddress {
    /// The dev server on Google Cloud (Server/deploy).
    static let dev = URL(string: "wss://136-64-123-56.sslip.io/ws")!

    /// Debug builds can point elsewhere with `-serverURL ws://localhost:8080/ws`, or play offline against
    /// the in-app server with `-offlineMatch YES`.
    static var target: GameConnection.Target {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "offlineMatch") {
            var config = ServerConfig.standard
            config.botFill = .zero
            config.matchmakingTick = .milliseconds(100)
            if MatchRules.timerScale > 1 { config = config.scaled(Double(MatchRules.timerScale)) }
            return .local(config)
        }
        if let text = UserDefaults.standard.string(forKey: "serverURL"), let url = URL(string: text) {
            return .remote(url)
        }
        #endif
        return .remote(dev)
    }
}
