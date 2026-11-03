import Testing
@testable import HeistCore

/// Plays one round bot against bot, checking every action the way the server does.
private func playRound(seed: UInt64) throws -> RoundResult {
    var random = SeededRandom(seed: seed)
    let map = MapGenerator.generate(.standard, random: &random)
    var round = Round(map: map, seed: random.next())
    var bots = RolePair(thief: Bot(seed: random.next()), police: Bot(seed: random.next()))

    var plays = RolePair<[PrepPlay]>(repeating: [])
    for role in Role.allCases {
        plays[role] = bots[role].prep(view: round.view(for: role), hand: round.prepHands[role], points: round.rules.prepPoints)
        try round.checkPrep(plays[role], for: role)
        #expect(plays[role].reduce(0) { $0 + $1.card.cost } <= 3)
    }
    _ = round.resolvePrep(thief: plays.thief, police: plays.police)

    while round.result == nil {
        var plans = RolePair(repeating: MovePlan())
        for role in Role.allCases {
            if let card = bots[role].instant(view: round.view(for: role)) {
                _ = try round.useInstant(card, by: role)
            }
            plans[role] = bots[role].move(view: round.view(for: role))
            try round.checkPlan(plans[role], for: role)
        }
        _ = round.resolveTurn(thief: plans.thief, police: plans.police)
    }
    return round.result!
}

@Test func botsPlayLegallyToTheEnd() throws {
    var thiefWins = 0
    var reasons: [RoundResult.Reason: Int] = [:]
    for seed in UInt64(1)...300 {
        let result = try playRound(seed: seed)
        #expect(result.turns <= RoundRules.standard.chaseTurns)
        if result.winner == .thief { thiefWins += 1 }
        reasons[result.reason, default: 0] += 1
    }
    print("Bot vs bot over 300 rounds: thief won \(thiefWins); \(reasons)")
    #expect(reasons.count >= 2)
}

@Test func roundsReplayFromTheirSeed() throws {
    for seed in UInt64(1)...20 {
        #expect(try playRound(seed: seed) == playRound(seed: seed))
    }
}

@Test func botPrepFitsTheHand() {
    var random = SeededRandom(seed: 5)
    for _ in 0..<200 {
        let map = MapGenerator.generate(.standard, random: &random)
        let round = Round(map: map, seed: random.next())
        for role in Role.allCases {
            var bot = Bot(seed: random.next())
            let plays = bot.prep(view: round.view(for: role), hand: round.prepHands[role], points: 3)
            #expect(!plays.isEmpty)
            #expect(plays.allSatisfy { round.prepHands[role].contains($0.card) })
            #expect((try? round.checkPrep(plays, for: role)) != nil)
        }
    }
}
