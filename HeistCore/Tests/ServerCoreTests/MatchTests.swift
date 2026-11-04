import Foundation
import HeistCore
import Synchronization
import Testing
@testable import ServerCore

/// An in-memory connection. Everything it receives goes through JSON, as on the wire.
final class TestLink: ClientLink {
    let linkID = UUID()
    let messages: AsyncStream<ServerMessage>
    private let continuation: AsyncStream<ServerMessage>.Continuation
    private let closed = Mutex(false)

    init() {
        (messages, continuation) = AsyncStream.makeStream()
    }

    var isClosed: Bool { closed.withLock { $0 } }

    func send(_ envelope: ServerEnvelope) {
        let decoded = try! JSONDecoder().decode(ServerEnvelope.self, from: Data(envelope.json().utf8))
        continuation.yield(decoded.message)
    }

    func close() {
        closed.withLock { $0 = true }
        continuation.finish()
    }
}

/// Every timer at 1/100 of its real length.
private let fast = ServerConfig.standard.scaled(0.01)

private func makeServer() throws -> (GameServer, PlayerStore) {
    let store = try PlayerStore(directory: nil, elo: fast.elo, botNames: ["Mira", "Jonas"])
    let server = GameServer(config: fast, store: store)
    return (server, store)
}

private func send(_ message: ClientMessage, to server: GameServer, from link: TestLink) async {
    let text = String(decoding: try! JSONEncoder.wire.encode(ClientEnvelope(message)), as: UTF8.self)
    await server.receive(text, from: link)
}

/// Signs in, joins the queue and plays until the match ends (or `stopAfter` says to stop).
private func play(on server: GameServer, link: TestLink, name: String, token: String? = nil, seed: UInt64,
                  stopAfter: @escaping @Sendable (ServerMessage) -> Bool = { _ in false }) async -> (player: AutoPlayer, welcome: ServerMessage.Welcome?, seen: [String]) {
    var player = AutoPlayer(seed: seed)
    var welcome: ServerMessage.Welcome?
    var seen: [String] = []
    await send(.hello(.init(token: token, name: name)), to: server, from: link)
    for await message in link.messages {
        seen.append(message.type)
        if case .welcome(let w) = message {
            welcome = w
            if w.matchId == nil { await send(.queueJoin(.init()), to: server, from: link) }
            continue
        }
        for reply in player.respond(to: message) {
            await send(reply, to: server, from: link)
        }
        if player.result != nil || stopAfter(message) { break }
    }
    return (player, welcome, seen)
}

@Test(.timeLimit(.minutes(1))) func aLonePlayerPlaysABotToTheEnd() async throws {
    let (server, store) = try makeServer()
    await server.start()
    let link = TestLink()
    let (player, welcome, seen) = await play(on: server, link: link, name: "Ada", seed: 1)

    let result = try #require(player.result)
    #expect(seen.contains("queue.status") && seen.contains("match.found") && seen.contains("series.start"))
    #expect(player.errors.isEmpty, "\(player.errors)")
    #expect(player.leaks.isEmpty, "\(player.leaks)")

    // The tournament rules: first to 4 in six rounds, or an extension of exactly two more.
    let score = result.score
    #expect(player.rounds.count == score.a + score.b)
    if player.rounds.count <= 6 { #expect(max(score.a, score.b) == 4) } else { #expect(player.rounds.count == 8) }
    #expect(result.draw == (result.winner == nil))
    for (index, end) in player.rounds.enumerated() {
        #expect(end.round == index + 1)
    }

    // Bot matches count for ratings like any other.
    let ada = try #require(await store.player(welcome!.player.id))
    #expect(ada.matches == 1)
    #expect(ada.ratings == result.ratingsAfter)
    #expect(ada.ratings.thief.games + ada.ratings.police.games == player.rounds.count)
    if !result.draw { #expect(ada.ratings.overall.value != 1000) }
    // The match and every round are in the player's stats.
    #expect(ada.stats.matches == 1)
    #expect(ada.stats.wins == (result.youWon ? 1 : 0) && ada.stats.draws == (result.draw ? 1 : 0))
    #expect(ada.stats.thiefRounds == ada.ratings.thief.games && ada.stats.policeRounds == ada.ratings.police.games)
    #expect(ada.stats.escapes + ada.stats.policeWins == player.rounds.filter(\.youWon).count)
    #expect(ada.lastPlayed != nil)
    let bots = await store.bots()
    #expect(bots.contains { $0.matches == 1 })
    #expect(await server.activeMatches == 0)
}

@Test(.timeLimit(.minutes(1))) func twoPlayersInTheQueueMeetEachOther() async throws {
    let (server, store) = try makeServer()
    await server.start()
    let one = TestLink(), two = TestLink()
    async let first = play(on: server, link: one, name: "Ada", seed: 1)
    async let second = play(on: server, link: two, name: "Bo", seed: 2)
    let (a, b) = await (first, second)

    let resultA = try #require(a.player.result), resultB = try #require(b.player.result)
    #expect(a.player.leaks.isEmpty && b.player.leaks.isEmpty)
    #expect(a.player.errors.isEmpty && b.player.errors.isEmpty)
    #expect(resultA.score == resultB.score)
    #expect(resultA.draw == resultB.draw)
    if !resultA.draw { #expect(resultA.youWon != resultB.youWon) }
    #expect(await store.bots().allSatisfy { $0.matches == 0 })
    let ada = try #require(await store.player(a.welcome!.player.id))
    let bo = try #require(await store.player(b.welcome!.player.id))
    #expect(ada.matches == 1 && bo.matches == 1)
    // Elo is zero-sum overall between two fresh players.
    #expect(abs(ada.ratings.overall.value + bo.ratings.overall.value - 2000) < 0.001)
}

@Test(.timeLimit(.minutes(1))) func aDroppedPlayerComesBackAndFinishes() async throws {
    let (server, store) = try makeServer()
    await server.start()
    let link = TestLink()
    let (_, welcome, _) = await play(on: server, link: link, name: "Ada", seed: 3) { message in
        if case .turnStart(let start) = message { return start.turn == 2 }
        return false
    }
    await server.disconnect(link)
    try await Task.sleep(for: .milliseconds(100))

    // Back within the grace period, with the token from the first sign-in.
    let again = TestLink()
    let (player, rewelcome, seen) = await play(on: server, link: again, name: "Ada", token: welcome!.token, seed: 4)
    #expect(rewelcome?.player.id == welcome?.player.id)
    #expect(rewelcome?.matchId != nil)
    #expect(seen.contains("match.state"))
    let result = try #require(player.result)
    #expect(result.forfeitBy == nil)
    #expect(await store.player(welcome!.player.id)?.matches == 1)
}

@Test(.timeLimit(.minutes(1))) func aPlayerWhoNeverComesBackForfeits() async throws {
    let (server, store) = try makeServer()
    await server.start()
    let link = TestLink()
    let (_, welcome, _) = await play(on: server, link: link, name: "Ada", seed: 5) { message in
        if case .prepDeal = message { return true }
        return false
    }
    await server.disconnect(link)
    // Grace is 0.6 s at this speed.
    for _ in 0..<40 where await server.activeMatches > 0 {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(await server.activeMatches == 0)
    let ada = try #require(await store.player(welcome!.player.id))
    #expect(ada.matches == 1)
    #expect(ada.ratings.overall.value < 1000)
}

@Test(.timeLimit(.minutes(1))) func illegalActionsAreRefused() async throws {
    let (server, _) = try makeServer()
    await server.start()
    let link = TestLink()
    await send(.turnSubmit(.init(turn: 1, plan: MovePlan())), to: server, from: link)
    var iterator = link.messages.makeAsyncIterator()
    #expect(await iterator.next() == .error(.init(code: "hello_first", message: "Send hello first.")))

    await send(.hello(.init(token: nil, name: "Ada")), to: server, from: link)
    _ = await iterator.next()  // welcome
    await send(.prepSubmit(.init(plays: [])), to: server, from: link)
    if case .error(let error) = await iterator.next() { #expect(error.code == "not_in_match") } else { Issue.record("expected an error") }

    await send(.queueJoin(.init()), to: server, from: link)
    var turnStart: ServerMessage.TurnStart?
    while turnStart == nil, let message = await iterator.next() {
        switch message {
        case .matchFound: await send(.matchReady, to: server, from: link)
        case .prepDeal(let deal):
            // A card not in the hand, then an empty (legal) hand.
            let stranger = CardID.allCases.first { $0.phase == .prep && !deal.hand.contains($0) }!
            await send(.prepSubmit(.init(plays: [PrepPlay(card: stranger, tile: .origin)])), to: server, from: link)
            await send(.prepSubmit(.init(plays: [])), to: server, from: link)
        case .turnStart(let start): turnStart = start
        case .error(let error): #expect(["not_your_card", "not_in_hand"].contains(error.code))
        default: break
        }
    }
    let start = try #require(turnStart)
    // Three steps at once, and then a turn number from the past.
    let far = start.view.board.cells.first { $0.distance(to: start.view.position) == 3 }!
    await send(.turnSubmit(.init(turn: start.turn, plan: MovePlan(path: [far, far, far]))), to: server, from: link)
    await send(.turnSubmit(.init(turn: start.turn - 1, plan: MovePlan())), to: server, from: link)
    var codes: [String] = []
    while codes.count < 2, let message = await iterator.next() {
        if case .error(let error) = message { codes.append(error.code) }
    }
    #expect(codes == ["too_many_steps", "wrong_turn"])
    await send(.matchLeave, to: server, from: link)
}
