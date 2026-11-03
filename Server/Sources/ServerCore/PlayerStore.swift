import Foundation
import HeistCore

/// A player account. Guests sign in with the secret token they got at their first `hello`; Sign in with
/// Apple and Game Center come with task 2.2. Bots are accounts too, so their ratings move like anyone's
/// and the rating shown is their real strength.
public struct PlayerRecord: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var token: String?
    public var isBot: Bool
    public var ratings: Ratings
    public var matches: Int
    public var created: Date

    public var card: PlayerCard {
        PlayerCard(id: id, name: name, ratings: ratings, isBot: isBot)
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
}

/// Accounts and match records, kept as JSON files in one folder (nothing on disk when `directory` is nil).
/// Fine for the alpha; a database replaces it when the player count needs one.
public actor PlayerStore {
    private var players: [String: PlayerRecord] = [:]
    private var tokens: [String: String] = [:]
    private let directory: URL?
    private let elo: EloRules

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

    /// The player for `token`, or a new guest account when the token is unknown or missing.
    public func signIn(token: String?, name: String) throws -> PlayerRecord {
        let name = Self.clean(name)
        if let token, let id = tokens[token], var player = players[id] {
            if !name.isEmpty, name != player.name {
                player.name = name
                players[id] = player
                try save()
            }
            return player
        }
        let id = "p-" + Self.randomHex(bytes: 6)
        let token = Self.randomHex(bytes: 24)
        let player = PlayerRecord(id: id, name: name.isEmpty ? "Guest \(id.suffix(4))" : name, token: token, isBot: false,
                                  ratings: .starting(at: elo.start), matches: 0, created: .now)
        players[id] = player
        tokens[token] = id
        try save()
        return player
    }

    public func player(_ id: String) -> PlayerRecord? { players[id] }

    public func bots() -> [PlayerRecord] {
        players.values.filter(\.isBot).sorted { $0.id < $1.id }
    }

    /// Applies a finished match to both players' ratings and stores its record.
    public func finish(_ record: MatchRecord, rounds: [RatedRound], winner: Seat?) throws -> SeatPair<(before: Ratings, after: Ratings)> {
        guard var a = players[record.players.a], var b = players[record.players.b] else {
            throw StoreError.unknownPlayer
        }
        let before = SeatPair(a: a.ratings, b: b.ratings)
        let after = Elo.rate(before, rounds: rounds, winner: winner, rules: elo)
        a.ratings = after.a
        b.ratings = after.b
        a.matches += 1
        b.matches += 1
        players[a.id] = a
        players[b.id] = b
        try save()
        if let directory {
            try JSONEncoder.store.encode(record).write(to: directory.appending(path: "matches/\(record.id).json"), options: .atomic)
        }
        return SeatPair(a: (before.a, after.a), b: (before.b, after.b))
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

extension JSONEncoder {
    static var store: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Compact JSON for the wire.
    static var wire: JSONEncoder {
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
