import Foundation
import HeistCore
import Testing
@testable import ServerCore

private let fresh = SeatPair(a: Ratings.starting(at: 1000), b: Ratings.starting(at: 1000))

@Test func aRoundMovesOnlyTheRoleRatingsOfThatRound() {
    let after = Elo.rate(fresh, rounds: [RatedRound(thief: .a, winner: .a)], winner: .a, rules: EloRules())
    #expect(after.a.thief.value == 1016)
    #expect(after.b.police.value == 984)
    #expect(after.a.police == fresh.a.police)
    #expect(after.b.thief == fresh.b.thief)
    #expect(after.a.thief.games == 1 && after.b.police.games == 1)
    #expect(after.a.overall.value == 1016 && after.b.overall.value == 984)
}

@Test func aDrawBetweenEqualsChangesNothingOverall() {
    let rounds = [RatedRound(thief: .a, winner: .a), RatedRound(thief: .b, winner: .b)]
    let after = Elo.rate(fresh, rounds: rounds, winner: nil, rules: EloRules())
    #expect(after.a.overall.value == 1000 && after.b.overall.value == 1000)
    #expect(after.a.overall.games == 1)
    #expect(after.a.thief.value == 1016 && after.b.thief.value == 1016)
}

@Test func beatingAStrongerPlayerEarnsMore() {
    var ratings = fresh
    ratings.b.overall = Rating(value: 1200, games: 50)
    let after = Elo.rate(ratings, rounds: [], winner: .a, rules: EloRules())
    #expect(after.a.overall.value - 1000 > 24)
    // Settled ratings move at the smaller K.
    #expect(1200 - after.b.overall.value < 13)
}

@Test func theThiefAdvantageMakesPoliceWinsWorthMore() {
    var rules = EloRules()
    rules.thiefAdvantage = 100
    let after = Elo.rate(fresh, rounds: [RatedRound(thief: .a, winner: .b)], winner: .b, rules: rules)
    #expect(after.b.police.value - 1000 > 16)
    #expect(1000 - after.a.thief.value > 16)
}

@Test func closeRatingsPairAtOnce() {
    var queue = Matchmaker(window: 300, windowPerSecond: 100, botFill: .seconds(10))
    let start = ContinuousClock.now
    queue.join("a", rating: 1000, at: start)
    queue.join("b", rating: 1200, at: start)
    #expect(queue.pairings(at: start) == [.players("a", "b")])
    #expect(queue.waiting.isEmpty)
}

@Test func farRatingsWaitForTheWindowToWiden() {
    var queue = Matchmaker(window: 300, windowPerSecond: 100, botFill: .seconds(10))
    let start = ContinuousClock.now
    queue.join("a", rating: 1000, at: start)
    queue.join("b", rating: 1600, at: start)
    #expect(queue.pairings(at: start + .seconds(1)).isEmpty)
    #expect(queue.pairings(at: start + .seconds(3)) == [.players("a", "b")])
}

@Test func aLonePlayerGetsABotAfterTenSeconds() {
    var queue = Matchmaker(window: 300, windowPerSecond: 100, botFill: .seconds(10))
    let start = ContinuousClock.now
    queue.join("a", rating: 1000, at: start)
    #expect(queue.pairings(at: start + .seconds(9.9)).isEmpty)
    #expect(queue.pairings(at: start + .seconds(10)) == [.bot("a")])
    queue.join("b", rating: 1000, at: start)
    queue.leave("b")
    #expect(queue.pairings(at: start + .seconds(20)).isEmpty)
}

@Test func messagesSurviveTheWire() throws {
    let envelope = ClientEnvelope(.turnSubmit(.init(turn: 3, plan: MovePlan(path: [Hex(q: 1, r: -1)], card: .run))))
    let text = String(decoding: try JSONEncoder.wire.encode(envelope), as: UTF8.self)
    #expect(text.contains("\"type\":\"turn.submit\""))
    #expect(try JSONDecoder().decode(ClientEnvelope.self, from: Data(text.utf8)) == envelope)
    let ready = try JSONDecoder().decode(ClientEnvelope.self, from: Data(#"{"type":"match.ready"}"#.utf8))
    #expect(ready.message == .matchReady)
}
