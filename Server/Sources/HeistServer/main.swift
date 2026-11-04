// The Heist Royale game server: GET /health answers "ok", the app plays over one WebSocket at /ws, and
// GET /leaderboard?board=overall|thief|police[&country=TR] returns a leaderboard as JSON.
//
// Settings come from the environment:
//   PORT (8080), HOST (0.0.0.0), DATA_DIR (./data: players.json and matches/),
//   TIMER_SCALE (development only: 0.1 makes every timer ten times shorter).

import Foundation
import HeistCore
import Hummingbird
import HummingbirdWebSocket
import ServerCore

/// One app's WebSocket. Messages queue up in order and a writer task drains them onto the socket.
final class WebSocketLink: ClientLink {
    let linkID = UUID()
    let outgoing: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    init() {
        (outgoing, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1024))
    }

    func send(_ envelope: ServerEnvelope) {
        continuation.yield(envelope.json())
    }

    func close() {
        continuation.finish()
    }
}

let environment = ProcessInfo.processInfo.environment
let port = environment["PORT"].flatMap(Int.init) ?? 8080
let host = environment["HOST"] ?? "0.0.0.0"
let dataDirectory = URL(fileURLWithPath: environment["DATA_DIR"] ?? "data")
var config = ServerConfig.standard
if let scale = environment["TIMER_SCALE"].flatMap(Double.init), scale > 0 {
    config = config.scaled(scale)
}

let store = try PlayerStore(directory: dataDirectory, elo: config.elo, botNames: config.botNames)
let server = GameServer(config: config, store: store)
await server.start()

let router = Router()
router.get("health") { _, _ in "ok" }
router.get("leaderboard") { request, _ -> Response in
    let query = request.uri.queryParameters
    guard let board = LeaderboardBoard(rawValue: String(query["board"] ?? "overall")) else {
        return Response(status: .badRequest, body: .init(byteBuffer: ByteBuffer(string: "board is overall, thief or police\n")))
    }
    let page = await store.leaderboard(board, country: query["country"].map(String.init), limit: config.leaderboardSize)
    let json = try JSONEncoder.wire.encode(page)
    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: json)))
}

let webSocketRouter = Router(context: BasicWebSocketRequestContext.self)
webSocketRouter.ws("ws") { inbound, outbound, _ in
    let link = WebSocketLink()
    await server.connect(link)
    do {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await text in link.outgoing {
                    try await outbound.write(.text(text))
                }
            }
            group.addTask {
                for try await message in inbound.messages(maxSize: 1 << 16) {
                    guard case .text(let text) = message else { continue }
                    await server.receive(text, from: link)
                }
            }
            // Whichever side ends first (the app hung up, or the server closed the link) ends both.
            try await group.next()
            group.cancelAll()
        }
    } catch {}
    link.close()
    await server.disconnect(link)
}

let app = Application(
    router: router,
    server: .http1WebSocketUpgrade(webSocketRouter: webSocketRouter),
    configuration: .init(address: .hostname(host, port: port), serverName: "HeistRoyale")
)
print("Heist Royale server on \(host):\(port), data in \(dataDirectory.path)")
try await app.runService()
