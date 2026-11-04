// The wire protocol between the app and the game server: small JSON objects over one WebSocket, inside an
// envelope {seq, type, matchId, payload}. Message names follow the Master Plan's "Server and connection"
// tab. Times are milliseconds since 1970 in server time.

public enum WireProtocol {
    /// Bumped whenever a message changes shape; the server refuses older apps at `hello`.
    public static let version = 1
}

public enum GameMode: String, Codable, Sendable {
    case tournament
}

/// An Elo rating and how many games it is based on.
public struct Rating: Codable, Sendable, Equatable {
    public var value: Double
    public var games: Int

    public init(value: Double, games: Int = 0) {
        self.value = value
        self.games = games
    }
}

/// Every player keeps three ratings: overall (per match) and one per role (per round).
public struct Ratings: Codable, Sendable, Equatable {
    public var overall: Rating
    public var thief: Rating
    public var police: Rating

    public init(overall: Rating, thief: Rating, police: Rating) {
        self.overall = overall
        self.thief = thief
        self.police = police
    }

    public static func starting(at value: Double) -> Ratings {
        Ratings(overall: Rating(value: value), thief: Rating(value: value), police: Rating(value: value))
    }

    public subscript(role: Role) -> Rating {
        get { role == .thief ? thief : police }
        set {
            if role == .thief { thief = newValue } else { police = newValue }
        }
    }
}

/// How a player is shown to their opponent.
public struct PlayerCard: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var ratings: Ratings
    /// The app is always told when the opponent is a bot.
    public var isBot: Bool

    public init(id: String, name: String, ratings: Ratings, isBot: Bool) {
        self.id = id
        self.name = name
        self.ratings = ratings
        self.isBot = isBot
    }
}

// MARK: App → server

public enum ClientMessage: Sendable, Equatable {
    /// First message on every connection. Without a token the server makes a new guest account.
    case hello(Hello)
    case queueJoin(QueueJoin)
    case queueLeave
    /// The app has loaded the match (the ready check).
    case matchReady
    case prepSubmit(PrepSubmit)
    /// An instant card (Compass, Radar) while planning a turn.
    case infoUse(InfoUse)
    case turnSubmit(TurnSubmit)
    /// After a reconnect: the server answers with `match.state`.
    case resync
    case matchLeave
    case emote(Emote)

    public struct Hello: Codable, Sendable, Equatable {
        public var token: String?
        public var name: String
        public var protocolVersion: Int

        public init(token: String?, name: String, protocolVersion: Int = WireProtocol.version) {
            self.token = token
            self.name = name
            self.protocolVersion = protocolVersion
        }
    }

    public struct QueueJoin: Codable, Sendable, Equatable {
        public var mode: GameMode

        public init(mode: GameMode = .tournament) {
            self.mode = mode
        }
    }

    public struct PrepSubmit: Codable, Sendable, Equatable {
        public var plays: [PrepPlay]

        public init(plays: [PrepPlay]) {
            self.plays = plays
        }
    }

    public struct InfoUse: Codable, Sendable, Equatable {
        public var card: CardID

        public init(card: CardID) {
            self.card = card
        }
    }

    public struct TurnSubmit: Codable, Sendable, Equatable {
        public var turn: Int
        public var plan: MovePlan

        public init(turn: Int, plan: MovePlan) {
            self.turn = turn
            self.plan = plan
        }
    }

    public var type: String {
        switch self {
        case .hello: "hello"
        case .queueJoin: "queue.join"
        case .queueLeave: "queue.leave"
        case .matchReady: "match.ready"
        case .prepSubmit: "prep.submit"
        case .infoUse: "info.use"
        case .turnSubmit: "turn.submit"
        case .resync: "match.resync"
        case .matchLeave: "match.leave"
        case .emote: "emote"
        }
    }
}

public struct Emote: Codable, Sendable, Equatable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

// MARK: Server → app

public enum ServerMessage: Sendable, Equatable {
    case welcome(Welcome)
    case queueStatus(QueueStatus)
    case matchFound(MatchFound)
    case seriesStart(SeriesStart)
    case roundBriefing(RoundBriefing)
    case prepDeal(PrepDeal)
    case prepResult(PrepResult)
    case turnStart(TurnStart)
    case infoResult(InfoResult)
    case opponentLocked(OpponentLocked)
    case turnResult(TurnResult)
    case roundEnd(RoundEnd)
    case seriesEnd(SeriesEnd)
    case matchState(MatchState)
    case matchCancelled(MatchCancelled)
    case emote(Emote)
    case error(ServerError)

    public struct Welcome: Codable, Sendable, Equatable {
        public var player: PlayerCard
        /// Keep it: it signs this guest account in next time.
        public var token: String
        public var protocolVersion: Int
        /// Set when the player is still in a running match; the app should resync.
        public var matchId: String?

        public init(player: PlayerCard, token: String, protocolVersion: Int, matchId: String?) {
            self.player = player
            self.token = token
            self.protocolVersion = protocolVersion
            self.matchId = matchId
        }
    }

    public struct QueueStatus: Codable, Sendable, Equatable {
        public var waitedSeconds: Int
        public var botAfterSeconds: Int

        public init(waitedSeconds: Int, botAfterSeconds: Int) {
            self.waitedSeconds = waitedSeconds
            self.botAfterSeconds = botAfterSeconds
        }
    }

    public struct MatchFound: Codable, Sendable, Equatable {
        public var mode: GameMode
        public var opponent: PlayerCard
        /// Send `match.ready` before this.
        public var readyDeadline: Int64

        public init(mode: GameMode, opponent: PlayerCard, readyDeadline: Int64) {
            self.mode = mode
            self.opponent = opponent
            self.readyDeadline = readyDeadline
        }
    }

    public struct SeriesStart: Codable, Sendable, Equatable {
        public var youAre: Seat
        public var you: PlayerCard
        public var opponent: PlayerCard
        /// Which seat plays thief in each round, rounds 1 to 8.
        public var thiefSchedule: [Seat]
        public var winTarget: Int
        /// When round 1's role reveal starts; the coin flip shows until then.
        public var firstRoundAt: Int64?

        public init(youAre: Seat, you: PlayerCard, opponent: PlayerCard, thiefSchedule: [Seat], winTarget: Int, firstRoundAt: Int64? = nil) {
            self.youAre = youAre
            self.you = you
            self.opponent = opponent
            self.thiefSchedule = thiefSchedule
            self.winTarget = winTarget
            self.firstRoundAt = firstRoundAt
        }
    }

    public struct RoundBriefing: Codable, Sendable, Equatable {
        public var round: Int
        public var role: Role
        public var view: PlayerView
        public var score: SeatPair<Int>
        public var deadline: Int64

        public init(round: Int, role: Role, view: PlayerView, score: SeatPair<Int>, deadline: Int64) {
            self.round = round
            self.role = role
            self.view = view
            self.score = score
            self.deadline = deadline
        }
    }

    public struct PrepDeal: Codable, Sendable, Equatable {
        public var round: Int
        public var hand: [CardID]
        public var points: Int
        public var deadline: Int64

        public init(round: Int, hand: [CardID], points: Int, deadline: Int64) {
            self.round = round
            self.hand = hand
            self.points = points
            self.deadline = deadline
        }
    }

    public struct PrepResult: Codable, Sendable, Equatable {
        public var intel: [Note]
        public var view: PlayerView
        /// When the intel reveal ends and the chase starts.
        public var deadline: Int64

        public init(intel: [Note], view: PlayerView, deadline: Int64) {
            self.intel = intel
            self.view = view
            self.deadline = deadline
        }
    }

    public struct TurnStart: Codable, Sendable, Equatable {
        public var turn: Int
        public var view: PlayerView
        public var deadline: Int64

        public init(turn: Int, view: PlayerView, deadline: Int64) {
            self.turn = turn
            self.view = view
            self.deadline = deadline
        }
    }

    public struct InfoResult: Codable, Sendable, Equatable {
        public var note: Note
        public var view: PlayerView

        public init(note: Note, view: PlayerView) {
            self.note = note
            self.view = view
        }
    }

    public struct OpponentLocked: Codable, Sendable, Equatable {
        /// "prep" or "turn".
        public var stage: String

        public init(stage: String) {
            self.stage = stage
        }
    }

    public struct TurnResult: Codable, Sendable, Equatable {
        public var turn: Int
        public var notes: [Note]
        public var view: PlayerView

        public init(turn: Int, notes: [Note], view: PlayerView) {
            self.turn = turn
            self.notes = notes
            self.view = view
        }
    }

    public struct RoundEnd: Codable, Sendable, Equatable {
        public var round: Int
        public var result: RoundResult
        public var winner: Seat
        public var youWon: Bool
        public var score: SeatPair<Int>
        public var reveal: RoundReveal
        /// When the next round's briefing starts; nil when the match is over.
        public var nextRoundAt: Int64?

        public init(round: Int, result: RoundResult, winner: Seat, youWon: Bool, score: SeatPair<Int>, reveal: RoundReveal, nextRoundAt: Int64?) {
            self.round = round
            self.result = result
            self.winner = winner
            self.youWon = youWon
            self.score = score
            self.reveal = reveal
            self.nextRoundAt = nextRoundAt
        }
    }

    public struct SeriesEnd: Codable, Sendable, Equatable {
        /// Nil on a draw.
        public var winner: Seat?
        public var youWon: Bool
        public var draw: Bool
        /// Set when a player left or didn't come back in time; they lose the match.
        public var forfeitBy: Seat?
        public var score: SeatPair<Int>
        public var ratingsBefore: Ratings
        public var ratingsAfter: Ratings
        /// The match seed, revealed now for replays.
        public var seed: String

        public init(winner: Seat?, youWon: Bool, draw: Bool, forfeitBy: Seat?, score: SeatPair<Int>, ratingsBefore: Ratings, ratingsAfter: Ratings, seed: String) {
            self.winner = winner
            self.youWon = youWon
            self.draw = draw
            self.forfeitBy = forfeitBy
            self.score = score
            self.ratingsBefore = ratingsBefore
            self.ratingsAfter = ratingsAfter
            self.seed = seed
        }
    }

    /// The full current state after a reconnect.
    public struct MatchState: Codable, Sendable, Equatable {
        public var matchId: String
        public var youAre: Seat
        public var opponent: PlayerCard
        public var round: Int
        public var role: Role
        /// "ready", "briefing", "prep", "intel", "chase", "roundEnd" or "over".
        public var phase: String
        public var deadline: Int64?
        public var score: SeatPair<Int>
        public var view: PlayerView?
        /// The prep hand while it can still be played.
        public var hand: [CardID]?
        /// This player has already locked in for the current prep or turn.
        public var locked: Bool

        public init(matchId: String, youAre: Seat, opponent: PlayerCard, round: Int, role: Role, phase: String, deadline: Int64?, score: SeatPair<Int>, view: PlayerView?, hand: [CardID]?, locked: Bool) {
            self.matchId = matchId
            self.youAre = youAre
            self.opponent = opponent
            self.round = round
            self.role = role
            self.phase = phase
            self.deadline = deadline
            self.score = score
            self.view = view
            self.hand = hand
            self.locked = locked
        }
    }

    public struct MatchCancelled: Codable, Sendable, Equatable {
        /// "ready_timeout": someone didn't confirm in time. A player who did is put back in the queue.
        public var reason: String
        public var requeued: Bool

        public init(reason: String, requeued: Bool) {
            self.reason = reason
            self.requeued = requeued
        }
    }

    public struct ServerError: Codable, Sendable, Equatable {
        public var code: String
        public var message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public var type: String {
        switch self {
        case .welcome: "welcome"
        case .queueStatus: "queue.status"
        case .matchFound: "match.found"
        case .seriesStart: "series.start"
        case .roundBriefing: "round.briefing"
        case .prepDeal: "prep.deal"
        case .prepResult: "prep.result"
        case .turnStart: "turn.start"
        case .infoResult: "info.result"
        case .opponentLocked: "opponent.locked"
        case .turnResult: "turn.result"
        case .roundEnd: "round.end"
        case .seriesEnd: "series.end"
        case .matchState: "match.state"
        case .matchCancelled: "match.cancelled"
        case .emote: "emote"
        case .error: "error"
        }
    }
}

// MARK: Envelopes

private enum EnvelopeKey: String, CodingKey {
    case seq, type, matchId, serverTime, payload
}

private struct Empty: Codable {}

public struct ClientEnvelope: Codable, Sendable, Equatable {
    public var seq: Int?
    public var matchId: String?
    public var message: ClientMessage

    public init(_ message: ClientMessage, seq: Int? = nil, matchId: String? = nil) {
        self.message = message
        self.seq = seq
        self.matchId = matchId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: EnvelopeKey.self)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq)
        matchId = try c.decodeIfPresent(String.self, forKey: .matchId)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "hello": message = .hello(try c.decode(ClientMessage.Hello.self, forKey: .payload))
        case "queue.join": message = .queueJoin(try c.decodeIfPresent(ClientMessage.QueueJoin.self, forKey: .payload) ?? .init())
        case "queue.leave": message = .queueLeave
        case "match.ready": message = .matchReady
        case "prep.submit": message = .prepSubmit(try c.decode(ClientMessage.PrepSubmit.self, forKey: .payload))
        case "info.use": message = .infoUse(try c.decode(ClientMessage.InfoUse.self, forKey: .payload))
        case "turn.submit": message = .turnSubmit(try c.decode(ClientMessage.TurnSubmit.self, forKey: .payload))
        case "match.resync": message = .resync
        case "match.leave": message = .matchLeave
        case "emote": message = .emote(try c.decode(Emote.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown message type \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: EnvelopeKey.self)
        try c.encodeIfPresent(seq, forKey: .seq)
        try c.encodeIfPresent(matchId, forKey: .matchId)
        try c.encode(message.type, forKey: .type)
        switch message {
        case .hello(let p): try c.encode(p, forKey: .payload)
        case .queueJoin(let p): try c.encode(p, forKey: .payload)
        case .prepSubmit(let p): try c.encode(p, forKey: .payload)
        case .infoUse(let p): try c.encode(p, forKey: .payload)
        case .turnSubmit(let p): try c.encode(p, forKey: .payload)
        case .emote(let p): try c.encode(p, forKey: .payload)
        case .queueLeave, .matchReady, .resync, .matchLeave: try c.encode(Empty(), forKey: .payload)
        }
    }
}

public struct ServerEnvelope: Codable, Sendable, Equatable {
    /// Numbered per player within a match (0 outside one), so a dropped app can tell what it missed.
    public var seq: Int
    public var matchId: String?
    /// The server's clock when it sent this, in milliseconds since 1970.
    public var serverTime: Int64?
    public var message: ServerMessage

    public init(_ message: ServerMessage, seq: Int = 0, matchId: String? = nil) {
        self.message = message
        self.seq = seq
        self.matchId = matchId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: EnvelopeKey.self)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        matchId = try c.decodeIfPresent(String.self, forKey: .matchId)
        serverTime = try c.decodeIfPresent(Int64.self, forKey: .serverTime)
        let type = try c.decode(String.self, forKey: .type)
        func payload<T: Decodable>(_: T.Type) throws -> T { try c.decode(T.self, forKey: .payload) }
        switch type {
        case "welcome": message = .welcome(try payload(ServerMessage.Welcome.self))
        case "queue.status": message = .queueStatus(try payload(ServerMessage.QueueStatus.self))
        case "match.found": message = .matchFound(try payload(ServerMessage.MatchFound.self))
        case "series.start": message = .seriesStart(try payload(ServerMessage.SeriesStart.self))
        case "round.briefing": message = .roundBriefing(try payload(ServerMessage.RoundBriefing.self))
        case "prep.deal": message = .prepDeal(try payload(ServerMessage.PrepDeal.self))
        case "prep.result": message = .prepResult(try payload(ServerMessage.PrepResult.self))
        case "turn.start": message = .turnStart(try payload(ServerMessage.TurnStart.self))
        case "info.result": message = .infoResult(try payload(ServerMessage.InfoResult.self))
        case "opponent.locked": message = .opponentLocked(try payload(ServerMessage.OpponentLocked.self))
        case "turn.result": message = .turnResult(try payload(ServerMessage.TurnResult.self))
        case "round.end": message = .roundEnd(try payload(ServerMessage.RoundEnd.self))
        case "series.end": message = .seriesEnd(try payload(ServerMessage.SeriesEnd.self))
        case "match.state": message = .matchState(try payload(ServerMessage.MatchState.self))
        case "match.cancelled": message = .matchCancelled(try payload(ServerMessage.MatchCancelled.self))
        case "emote": message = .emote(try payload(Emote.self))
        case "error": message = .error(try payload(ServerMessage.ServerError.self))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown message type \(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: EnvelopeKey.self)
        try c.encode(seq, forKey: .seq)
        try c.encodeIfPresent(matchId, forKey: .matchId)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
        try c.encode(message.type, forKey: .type)
        switch message {
        case .welcome(let p): try c.encode(p, forKey: .payload)
        case .queueStatus(let p): try c.encode(p, forKey: .payload)
        case .matchFound(let p): try c.encode(p, forKey: .payload)
        case .seriesStart(let p): try c.encode(p, forKey: .payload)
        case .roundBriefing(let p): try c.encode(p, forKey: .payload)
        case .prepDeal(let p): try c.encode(p, forKey: .payload)
        case .prepResult(let p): try c.encode(p, forKey: .payload)
        case .turnStart(let p): try c.encode(p, forKey: .payload)
        case .infoResult(let p): try c.encode(p, forKey: .payload)
        case .opponentLocked(let p): try c.encode(p, forKey: .payload)
        case .turnResult(let p): try c.encode(p, forKey: .payload)
        case .roundEnd(let p): try c.encode(p, forKey: .payload)
        case .seriesEnd(let p): try c.encode(p, forKey: .payload)
        case .matchState(let p): try c.encode(p, forKey: .payload)
        case .matchCancelled(let p): try c.encode(p, forKey: .payload)
        case .emote(let p): try c.encode(p, forKey: .payload)
        case .error(let p): try c.encode(p, forKey: .payload)
        }
    }
}
