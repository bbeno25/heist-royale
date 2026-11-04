import Foundation
import HeistCore
import Testing
@testable import ServerCore

private func result(_ reason: RoundResult.Reason, turns: Int) -> RoundResult {
    try! JSONDecoder().decode(RoundResult.self, from: Data(#"{"reason":"\#(reason.rawValue)","turns":\#(turns)}"#.utf8))
}

/// A finished match between two stored players: each round is (who was thief, how it ended, on which turn).
private func match(_ a: String, _ b: String, _ rounds: [(Seat, RoundResult.Reason, Int)], winner: Seat?, forfeitBy: Seat? = nil)
    -> (record: MatchRecord, rated: [RatedRound]) {
    var record = MatchRecord(id: "m-" + PlayerStore.randomHex(bytes: 4), mode: .tournament, rulesVersion: Round.rulesVersion, seed: "1",
                             started: .now, players: SeatPair(a: a, b: b))
    record.rounds = rounds.map { thief, reason, turns in
        var round = MatchRecord.RoundRecord(seed: "1", thief: thief)
        round.result = result(reason, turns: turns)
        return round
    }
    record.ended = .now
    record.outcome = winner?.rawValue ?? "draw"
    record.forfeitBy = forfeitBy
    let rated = rounds.map { thief, reason, _ in RatedRound(thief: thief, winner: reason == .escaped ? thief : thief.other) }
    return (record, rated)
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "heist-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func statsCountTheMatchAndEveryRound() async throws {
    let store = try PlayerStore(directory: nil, botNames: [])
    let ada = try await store.signIn(token: nil, name: "Ada", region: "tr")
    let bo = try await store.signIn(token: nil, name: "Bo", region: "Germany")
    #expect(ada.country == "TR")
    #expect(bo.country == nil)

    let (record, rated) = match(ada.id, bo.id, [(.a, .escaped, 7), (.a, .caught, 4), (.a, .time, 12), (.b, .escaped, 9)], winner: .a)
    _ = try await store.finish(record, rounds: rated, winner: .a)
    let a = try #require(await store.player(ada.id)).stats
    let b = try #require(await store.player(bo.id)).stats
    #expect(a.wins == 1 && a.losses == 0 && a.draws == 0)
    #expect(a.thiefRounds == 3 && a.escapes == 1 && a.escapeTurns == 7)
    #expect(a.policeRounds == 1 && a.policeWins == 0 && a.catches == 0)
    #expect(b.losses == 1)
    #expect(b.policeRounds == 3 && b.policeWins == 2 && b.catches == 1)
    #expect(b.thiefRounds == 1 && b.escapes == 1 && b.escapeTurns == 9)

    let (forfeited, forfeitRounds) = match(ada.id, bo.id, [(.a, .caught, 3)], winner: .a, forfeitBy: .b)
    _ = try await store.finish(forfeited, rounds: forfeitRounds, winner: .a)
    let after = try #require(await store.player(bo.id))
    #expect(after.stats.forfeits == 1 && after.stats.losses == 2 && after.matches == 2)
}

@Test func leaderboardsRankHumansWithGamesBestFirst() async throws {
    let store = try PlayerStore(directory: nil, botNames: ["Mira"])
    let ada = try await store.signIn(token: nil, name: "Ada", region: "TR")
    let bo = try await store.signIn(token: nil, name: "Bo", region: "TR")
    let cem = try await store.signIn(token: nil, name: "Cem", region: "DE")
    let dan = try await store.signIn(token: nil, name: "Dan", region: "TR")
    let first = match(ada.id, bo.id, [(.a, .escaped, 6)], winner: .a)
    _ = try await store.finish(first.record, rounds: first.rated, winner: .a)
    let second = match(cem.id, "bot-mira", [(.b, .caught, 5)], winner: .a)
    _ = try await store.finish(second.record, rounds: second.rated, winner: .a)

    // Ada and Cem both won their first match (1016): they share first place. Bots and Dan, who hasn't
    // played, stay off the board.
    let overall = await store.leaderboard(.overall, limit: 100)
    #expect(overall.players == 3)
    #expect(overall.entries.map(\.rank) == [1, 1, 3])
    #expect(Set(overall.entries.prefix(2).map(\.name)) == ["Ada", "Cem"])
    #expect(overall.entries.last?.name == "Bo" && overall.entries.last?.rating == 984)
    #expect(overall.scope == .global && overall.you == nil)

    // Role boards only list players who played that role.
    let thief = await store.leaderboard(.thief, limit: 100)
    #expect(thief.entries.map(\.name) == ["Ada"])
    let police = await store.leaderboard(.police, limit: 100)
    #expect(police.entries.map(\.name).sorted() == ["Bo", "Cem"])

    let turkey = await store.leaderboard(.overall, country: "tr", limit: 100, you: dan.id)
    #expect(turkey.scope == .country && turkey.country == "TR")
    #expect(turkey.entries.map(\.name) == ["Ada", "Bo"] && turkey.entries.map(\.rank) == [1, 2])
    #expect(turkey.you == nil)

    // The asking player's row comes back even when it is below the page.
    let top = await store.leaderboard(.overall, limit: 1, you: bo.id)
    #expect(top.entries.count == 1)
    #expect(top.you?.rank == 3 && top.you?.name == "Bo")
}

@Test func olderPlayerFilesStillLoad() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let old = """
    [{"created":"2026-11-04T10:00:00Z","id":"p-0123456789ab","isBot":false,"matches":3,"name":"Ada",
      "ratings":{"overall":{"games":3,"value":1030},"police":{"games":9,"value":1010},"thief":{"games":10,"value":1022}},
      "token":"secret"}]
    """
    try Data(old.utf8).write(to: directory.appending(path: "players.json"))
    let store = try PlayerStore(directory: directory, botNames: [])
    let ada = try #require(await store.player("p-0123456789ab"))
    #expect(ada.ratings.overall.value == 1030 && ada.matches == 3)
    #expect(ada.stats == PlayerStats() && ada.country == nil && ada.lastPlayed == nil)
    let again = try await store.signIn(token: "secret", name: "Ada", region: "TR")
    #expect(again.id == ada.id && again.country == "TR")
    let saved = try String(contentsOf: directory.appending(path: "players.json"), encoding: .utf8)
    #expect(saved.contains("\"country\" : \"TR\"") && saved.contains("\"stats\""))
}

@Test func matchFilesKeepTheRatingChanges() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try PlayerStore(directory: directory, botNames: [])
    let ada = try await store.signIn(token: nil, name: "Ada")
    let bo = try await store.signIn(token: nil, name: "Bo")
    let played = match(ada.id, bo.id, [(.a, .escaped, 6), (.b, .caught, 8)], winner: nil)
    let changes = try await store.finish(played.record, rounds: played.rated, winner: nil)
    let file = directory.appending(path: "matches/\(played.record.id).json")
    let stored = try JSONDecoder.store.decode(MatchRecord.self, from: Data(contentsOf: file))
    #expect(stored.ratings == changes)
    #expect(stored.ratings?.a.before.overall.value == 1000)
    #expect(stored.ratings?.a.after.thief.value == 1016)

    // Everything survives a restart.
    let reopened = try PlayerStore(directory: directory, botNames: [])
    #expect(await reopened.player(ada.id)?.stats.draws == 1)
    #expect(await reopened.leaderboard(.thief, limit: 10).entries.map(\.name) == ["Ada", "Bo"])
}

@Test(.timeLimit(.minutes(1))) func leaderboardsWorkBeforeSignInAndShowYouAfter() async throws {
    let store = try PlayerStore(directory: nil, botNames: [])
    let server = GameServer(config: .standard.scaled(0.01), store: store)
    let ada = try await store.signIn(token: nil, name: "Ada", region: "TR")
    let bo = try await store.signIn(token: nil, name: "Bo", region: "TR")
    let played = match(ada.id, bo.id, [(.a, .escaped, 6)], winner: .a)
    _ = try await store.finish(played.record, rounds: played.rated, winner: .a)

    let link = TestLink()
    var inbox = link.messages.makeAsyncIterator()
    func send(_ message: ClientMessage) async {
        await server.receive(String(decoding: try! JSONEncoder.wire.encode(ClientEnvelope(message)), as: UTF8.self), from: link)
    }

    await send(.leaderboardGet(.init(board: .overall)))
    guard case .leaderboard(let anonymous) = await inbox.next() else { Issue.record("no leaderboard"); return }
    #expect(anonymous.entries.map(\.name) == ["Ada", "Bo"] && anonymous.you == nil)

    await send(.leaderboardGet(.init(board: .overall, scope: .country)))
    guard case .error(let error) = await inbox.next() else { Issue.record("no error"); return }
    #expect(error.code == "no_country")

    await send(.hello(.init(token: bo.token, name: "Bo", region: "TR")))
    guard case .welcome(let welcome) = await inbox.next() else { Issue.record("no welcome"); return }
    #expect(welcome.stats?.losses == 1 && welcome.country == "TR")

    await send(.leaderboardGet(.init(board: .police, scope: .country)))
    guard case .leaderboard(let mine) = await inbox.next() else { Issue.record("no leaderboard"); return }
    #expect(mine.country == "TR" && mine.you?.name == "Bo" && mine.you?.rank == 1)
}

@Test func leaderboardMessagesSurviveTheWire() throws {
    let page = ServerMessage.Leaderboard(board: .thief, scope: .country, country: "TR",
                                         entries: [LeaderboardEntry(rank: 1, playerId: "p-1", name: "Ada", rating: 1016, games: 3, country: "TR")],
                                         you: nil, players: 1)
    let envelope = ServerEnvelope(.leaderboard(page))
    #expect(try JSONDecoder().decode(ServerEnvelope.self, from: Data(envelope.json().utf8)).message == envelope.message)
    let request = ClientEnvelope(.leaderboardGet(.init(board: .police, scope: .global)))
    #expect(try JSONDecoder().decode(ClientEnvelope.self, from: JSONEncoder.wire.encode(request)) == request)
    // An app from before regions still signs in.
    let hello = try JSONDecoder().decode(ClientEnvelope.self, from: Data(#"{"type":"hello","payload":{"name":"Ada","protocolVersion":1}}"#.utf8))
    #expect(hello.message == .hello(.init(token: nil, name: "Ada")))
}
