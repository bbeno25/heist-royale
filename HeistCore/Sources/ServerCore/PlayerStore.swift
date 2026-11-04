import Foundation
import HeistCore

/// A player account. Guests sign in with the secret token they got at their first `hello`; Sign in with
/// Apple and Game Center come with task 2.2. Bots are accounts too, so their ratings move like anyone's
/// and the rating shown is their real strength (bots stay off the leaderboards).
public struct PlayerRecord: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var token: String?
    public var isBot: Bool
    public var ratings: Ratings
    public var matches: Int
    public var created: Date
    /// ISO 3166 region from the app, for the country leaderboards.
    public var country: String?
    public var stats = PlayerStats()
    public var lastPlayed: Date?

    public var card: PlayerCard {
        PlayerCard(id: id, name: name, ratings: ratings, isBot: isBot)
    }
}

extension PlayerRecord {
    /// Fields added after the first release default when missing, so older players.json files still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        isBot = try c.decode(Bool.self, forKey: .isBot)
        ratings = try c.decode(Ratings.self, forKey: .ratings)
        matches = try c.decode(Int.self, forKey: .matches)
        created = try c.decode(Date.self, forKey: .created)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        stats = try c.decodeIfPresent(PlayerStats.self, forKey: .stats) ?? PlayerStats()
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
    }
}

/// One player's ratings before and after a match.
public struct RatingChange: Codable, Sendable, Equatable {
    public var before: Ratings
    public var after: Ratings

    public init(before: Ratings, after: Ratings) {
        self.before = before
        self.after = after
    }
}

/// One finished match as stored: rules version, seed and every action, so it replays exactly.
public struct MatchRecord: Codable, Sendable, Equatable {
    public struct RoundRecord: Codable, Sendable, Equatable {
        public struct Instant: Codable, Sendable, Equatable {
            public var turn: Int
            public var seat: Seat
            public var card: CardID
        }

        public struct Turn: Codable, Sendable, Equatable {
            public var turn: Int
            public var thief: MovePlan
            public var police: MovePlan
        }

        /// Hex; the map and the round are both generated from it.
        public var seed: String
        public var thief: Seat
        public var prep = SeatPair<[PrepPlay]>(repeating: [])
        public var instants: [Instant] = []
        public var turns: [Turn] = []
        public var result: RoundResult?
    }

    public var id: String
    public var mode: GameMode
    public var rulesVersion: Int
    public var seed: String
    public var started: Date
    public var ended: Date?
    public var players: SeatPair<String>
    public var rounds: [RoundRecord] = []
    /// "a", "b" or "draw".
    public var outcome: String?
    public var forfeitBy: Seat?
    /// Both players' ratings before and after, as the match was rated.
    public var ratings: SeatPair<RatingChange>?
}

/// Accounts and match records, kept as JSON files in one folder (nothing on disk when `directory` is nil).
/// Fine for the alpha; a database replaces it when the player count needs one.
public actor PlayerStore {
    private var players: [String: PlayerRecord] = [:]
    private var tokens: [String: String] = [:]
    private let directory: URL?
    private let elo: EloRules
    /// Every ranked player's id, best first, per board; rebuilt after ratings change.
    private var rankings: [LeaderboardBoard: [String]] = [:]

    public init(directory: URL?, elo: EloRules = EloRules(), botNames: [String] = ServerConfig.standard.botNames) throws {
        self.directory = directory
        self.elo = elo
        if let directory {
            try FileManager.default.createDirectory(at: directory.appending(path: "matches"), withIntermediateDirectories: true)
            let file = directory.appending(path: "players.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let list = try JSONDecoder.store.decode([PlayerRecord].self, from: Data(contentsOf: file))
                for player in list { players[player.id] = player }
            }
        }
        for player in players.values {
            if let token = player.token { tokens[token] = player.id }
        }
        var added = false
        for name in botNames where players["bot-\(name.lowercased())"] == nil {
            let id = "bot-\(name.lowercased())"
            players[id] = PlayerRecord(id: id, name: name, token: nil, isBot: true, ratings: .starting(at: elo.start), matches: 0, created: .now)
            added = true
        }
        if added { try Self.write(players, to: directory) }
    }

    /// The player for `token`, or a new guest account when the token is unknown or missing. A name or
    /// region that changed is saved.
    public func signIn(token: String?, name: String, region: String? = nil) throws -> PlayerRecord {
        let name = Self.clean(name)
        let region = cleanRegion(region)
        if let token, let id = tokens[token], var player = players[id] {
            let before = player
            if !name.isEmpty { player.name = name }
            if let region { player.country = region }
            if player != before {
                players[id] = player
                try save()
            }
            return player
        }
        let id = "p-" + Self.randomHex(bytes: 6)
        let token = Self.randomHex(bytes: 24)
        let player = PlayerRecord(id: id, name: name.isEmpty ? "Guest \(id.suffix(4))" : name, token: token, isBot: false,
                                  ratings: .starting(at: elo.start), matches: 0, created: .now, country: region)
        players[id] = player
        tokens[token] = id
        try save()
        return player
    }

    public func player(_ id: String) -> PlayerRecord? { players[id] }

    public func bots() -> [PlayerRecord] {
        players.values.filter(\.isBot).sorted { $0.id < $1.id }
    }

    /// Rates a finished match, adds it to both players' stats and stores its record with the rating changes.
    public func finish(_ record: MatchRecord, rounds: [RatedRound], winner: Seat?) throws -> SeatPair<RatingChange> {
        guard let a = players[record.players.a], let b = players[record.players.b] else {
            throw StoreError.unknownPlayer
        }
        let before = SeatPair(a: a.ratings, b: b.ratings)
        let after = Elo.rate(before, rounds: rounds, winner: winner, rules: elo)
        let changes = SeatPair(a: RatingChange(before: before.a, after: after.a), b: RatingChange(before: before.b, after: after.b))
        var seats = SeatPair(a: a, b: b)
        for seat in Seat.allCases {
            seats[seat].ratings = after[seat]
            seats[seat].matches += 1
            seats[seat].lastPlayed = record.ended ?? .now
            seats[seat].stats.add(record, as: seat, winner: winner)
        }
        players[a.id] = seats.a
        players[b.id] = seats.b
        rankings = [:]
        try save()
        if let directory {
            var stored = record
            stored.ratings = changes
            try JSONEncoder.store.encode(stored).write(to: directory.appending(path: "matches/\(record.id).json"), options: .atomic)
        }
        return changes
    }

    // MARK: Leaderboards

    /// One leaderboard: humans with at least one rated game in it, best first. `country` narrows it to one
    /// region; `you` adds that player's own row when they are on it.
    public func leaderboard(_ board: LeaderboardBoard, country: String? = nil, limit: Int, you: String? = nil) -> ServerMessage.Leaderboard {
        let country = cleanRegion(country)
        let ids = ranking(board).filter { country == nil || players[$0]?.country == country }
        var entries: [LeaderboardEntry] = []
        var mine: LeaderboardEntry?
        var rank = 0
        var lastRating: Int?
        for (index, id) in ids.enumerated() {
            guard let player = players[id] else { continue }
            let rating = player.ratings[board]
            let rounded = Int(rating.value.rounded())
            if rounded != lastRating { rank = index + 1 }
            lastRating = rounded
            let entry = LeaderboardEntry(rank: rank, playerId: id, name: player.name, rating: rounded, games: rating.games, country: player.country)
            if index < limit { entries.append(entry) }
            if id == you { mine = entry }
            if index >= limit, mine != nil || you == nil { break }
        }
        return ServerMessage.Leaderboard(board: board, scope: country == nil ? .global : .country, country: country,
                                         entries: entries, you: mine, players: ids.count)
    }

    private func ranking(_ board: LeaderboardBoard) -> [String] {
        if let cached = rankings[board] { return cached }
        let ranked = players.values
            .filter { !$0.isBot && $0.ratings[board].games > 0 }
            .sorted {
                let x = $0.ratings[board], y = $1.ratings[board]
                if x.value != y.value { return x.value > y.value }
                if x.games != y.games { return x.games > y.games }
                return $0.id < $1.id
            }
            .map(\.id)
        rankings[board] = ranked
        return ranked
    }

    private func save() throws {
        try Self.write(players, to: directory)
    }

    private static func write(_ players: [String: PlayerRecord], to directory: URL?) throws {
        guard let directory else { return }
        let list = players.values.sorted { $0.id < $1.id }
        try JSONEncoder.store.encode(list).write(to: directory.appending(path: "players.json"), options: .atomic)
    }

    enum StoreError: Error {
        case unknownPlayer
    }

    static func clean(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isNewline }.prefix(20))
    }

    static func randomHex(bytes: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }
}

extension PlayerStats {
    /// Counts a finished match for the player in `seat`: the result, a forfeit, and each round played.
    mutating func add(_ record: MatchRecord, as seat: Seat, winner: Seat?) {
        switch winner {
        case seat: wins += 1
        case nil: draws += 1
        default: losses += 1
        }
        if record.forfeitBy == seat { forfeits += 1 }
        for round in record.rounds {
            guard let result = round.result else { continue }
            if round.thief == seat {
                thiefRounds += 1
                if result.reason == .escaped {
                    escapes += 1
                    escapeTurns += result.turns
                }
            } else {
                policeRounds += 1
                if result.reason != .escaped { policeWins += 1 }
                if result.reason == .caught { catches += 1 }
            }
        }
    }
}

extension JSONEncoder {
    static var store: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Compact JSON for the wire.
    public static var wire: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var store: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
