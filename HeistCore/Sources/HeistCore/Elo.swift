import Foundation

/// The rating rules, decided 3 Nov 2026: Elo, with an overall rating that moves once per match and a
/// thief and a police rating that move after every round played in that role.
public struct EloRules: Codable, Sendable, Equatable {
    public var start = 1000.0
    /// New ratings move fast, settled ones slowly.
    public var provisionalK = 32.0
    public var settledK = 16.0
    public var provisionalGames = 20
    /// Elo points the thief side is worth in a round between equal players, so a police win against a
    /// strong role counts for more. 0 until real matches measure it (a weekly job, task 2.6).
    public var thiefAdvantage = 0.0

    public init() {}

    func k(_ rating: Rating) -> Double {
        rating.games < provisionalGames ? provisionalK : settledK
    }
}

/// One round as the ratings see it.
public struct RatedRound: Codable, Sendable, Equatable {
    public var thief: Seat
    public var winner: Seat

    public init(thief: Seat, winner: Seat) {
        self.thief = thief
        self.winner = winner
    }
}

public enum Elo {
    /// The expected score (0 to 1) of a player rated `rating` against `other`.
    public static func expected(_ rating: Double, against other: Double) -> Double {
        1 / (1 + pow(10, (other - rating) / 400))
    }

    /// New ratings for both seats. Role ratings update round by round: the thief's against the opponent's
    /// police rating and the other way round. The overall ratings update once from the match result.
    /// `winner` nil is a draw.
    public static func rate(_ ratings: SeatPair<Ratings>, rounds: [RatedRound], winner: Seat?, rules: EloRules) -> SeatPair<Ratings> {
        var out = ratings
        for round in rounds {
            let thief = round.thief, police = thief.other
            let t = out[thief].thief, p = out[police].police
            let expected = expected(t.value + rules.thiefAdvantage, against: p.value)
            let score = round.winner == thief ? 1.0 : 0.0
            out[thief].thief = Rating(value: t.value + rules.k(t) * (score - expected), games: t.games + 1)
            out[police].police = Rating(value: p.value + rules.k(p) * ((1 - score) - (1 - expected)), games: p.games + 1)
        }
        let a = ratings.a.overall, b = ratings.b.overall
        let expectedA = expected(a.value, against: b.value)
        let scoreA = winner == .a ? 1.0 : winner == .b ? 0.0 : 0.5
        out.a.overall = Rating(value: a.value + rules.k(a) * (scoreA - expectedA), games: a.games + 1)
        out.b.overall = Rating(value: b.value + rules.k(b) * ((1 - scoreA) - (1 - expectedA)), games: b.games + 1)
        return out
    }
}
