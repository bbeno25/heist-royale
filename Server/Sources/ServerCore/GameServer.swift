import Foundation
import HeistCore

/// The whole game server apart from the network: sign-in, the queue, and the match rooms. The WebSocket
/// layer calls `connect`, `receive` and `disconnect`; everything else happens in here.
public actor GameServer {
    private let config: ServerConfig
    private let store: PlayerStore
    private var matchmaker: Matchmaker
    /// Which player each connection signed in as, and each player's current connection.
    private var signedIn: [UUID: String] = [:]
    private var links: [String: ClientLink] = [:]
    private var rooms: [String: MatchRoom] = [:]
    private var inMatch: [String: (matchID: String, seat: Seat)] = [:]
    private var loop: Task<Void, Never>?

    public init(config: ServerConfig = .standard, store: PlayerStore) {
        self.config = config
        self.store = store
        matchmaker = Matchmaker(window: config.ratingWindow, windowPerSecond: config.ratingWindowPerSecond, botFill: config.botFill)
    }

    /// Starts the matchmaking loop.
    public func start() {
        guard loop == nil else { return }
        let tick = config.matchmakingTick
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                await self?.matchmakingTick()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public var activeMatches: Int { rooms.count }

    // MARK: Connections

    public func connect(_ link: ClientLink) {}

    public func disconnect(_ link: ClientLink) async {
        guard let player = signedIn.removeValue(forKey: link.linkID), links[player]?.linkID == link.linkID else { return }
        links[player] = nil
        matchmaker.leave(player)
        if let match = inMatch[player], let room = rooms[match.matchID] {
            await room.detach(match.seat)
        }
    }

    public func receive(_ text: String, from link: ClientLink) async {
        let envelope: ClientEnvelope
        do {
            envelope = try JSONDecoder().decode(ClientEnvelope.self, from: Data(text.utf8))
        } catch {
            return link.sendError("bad_message", "That message couldn't be read.")
        }
        if case .hello(let hello) = envelope.message {
            return await signIn(hello, link: link)
        }
        guard let player = signedIn[link.linkID] else {
            return link.sendError("hello_first", "Send hello first.")
        }
        switch envelope.message {
        case .queueJoin:
            guard inMatch[player] == nil else { return link.sendError("in_match", "You are already in a match.") }
            guard let record = await store.player(player) else { return }
            matchmaker.join(player, rating: record.ratings.overall.value, at: .now)
            link.send(.queueStatus(.init(waitedSeconds: 0, botAfterSeconds: Int(config.botFill.seconds.rounded()))))
        case .queueLeave:
            matchmaker.leave(player)
        default:
            guard let match = inMatch[player], let room = rooms[match.matchID] else {
                return link.sendError("not_in_match", "You are not in a match.")
            }
            await room.handle(envelope.message, from: match.seat)
        }
    }

    private func signIn(_ hello: ClientMessage.Hello, link: ClientLink) async {
        guard hello.protocolVersion >= WireProtocol.version else {
            link.sendError("update_required", "Please update Heist Royale to keep playing online.")
            return link.close()
        }
        let player: PlayerRecord
        do {
            player = try await store.signIn(token: hello.token, name: hello.name)
        } catch {
            return link.sendError("server_error", "Couldn't sign in. Try again.")
        }
        // One connection per player: a new one replaces the old.
        if let old = links[player.id], old.linkID != link.linkID {
            signedIn[old.linkID] = nil
            old.close()
        }
        if let previous = signedIn[link.linkID], previous != player.id {
            links[previous] = nil
            matchmaker.leave(previous)
        }
        signedIn[link.linkID] = player.id
        links[player.id] = link
        let match = inMatch[player.id]
        link.send(.welcome(.init(player: player.card, token: player.token ?? "", protocolVersion: WireProtocol.version, matchId: match?.matchID)))
        if let match, let room = rooms[match.matchID] {
            await room.attach(match.seat, link: link)
        }
    }

    // MARK: Matchmaking

    func matchmakingTick() async {
        let now = ContinuousClock.now
        for pairing in matchmaker.pairings(at: now) {
            switch pairing {
            case .players(let first, let second):
                await createMatch(first, second)
            case .bot(let player):
                guard let bot = await pickBot(for: player) else { continue }
                await createMatch(player, bot)
            }
        }
        for (player, waited) in matchmaker.statusDue(at: now, every: config.queueStatusEvery) {
            links[player]?.send(.queueStatus(.init(waitedSeconds: Int(waited.seconds), botAfterSeconds: Int(config.botFill.seconds.rounded()))))
        }
    }

    /// The free bot whose overall rating is closest to the player's, so the match is a fair test.
    private func pickBot(for player: String) async -> String? {
        guard let rating = await store.player(player)?.ratings.overall.value else { return nil }
        let bots = await store.bots()
        let free = bots.filter { inMatch[$0.id] == nil }
        return (free.isEmpty ? bots : free).min { abs($0.ratings.overall.value - rating) < abs($1.ratings.overall.value - rating) }?.id
    }

    private func createMatch(_ first: String, _ second: String) async {
        guard let one = await store.player(first), let two = await store.player(second) else { return }
        var generator = SystemRandomNumberGenerator()
        let seed = generator.next()
        // The coin flip: seat A plays thief first.
        let (a, b) = Bool.random(using: &generator) ? (one, two) : (two, one)
        let id = "m-" + PlayerStore.randomHex(bytes: 8)
        let room = MatchRoom(
            id: id, config: config, seed: seed, players: SeatPair(a: a.card, b: b.card),
            links: SeatPair(a: links[a.id], b: links[b.id]),
            onFinish: { [weak self] report in await self?.matchFinished(report) },
            onCancel: { [weak self] matchID, requeue in await self?.matchCancelled(matchID, requeue: requeue) }
        )
        rooms[id] = room
        inMatch[a.id] = (id, .a)
        inMatch[b.id] = (id, .b)
        await room.start()
    }

    private func matchFinished(_ report: MatchReport) async -> RatingUpdate? {
        let id = report.record.id
        rooms[id] = nil
        for player in [report.record.players.a, report.record.players.b] where inMatch[player]?.matchID == id {
            inMatch[player] = nil
        }
        return try? await store.finish(report.record, rounds: report.rounds, winner: report.winner)
    }

    private func matchCancelled(_ matchID: String, requeue: [String]) async {
        guard let room = rooms.removeValue(forKey: matchID) else { return }
        let seats = await room.seats
        for player in [seats.a.player.id, seats.b.player.id] where inMatch[player]?.matchID == matchID {
            inMatch[player] = nil
        }
        for player in requeue {
            guard let rating = await store.player(player)?.ratings.overall.value, links[player] != nil else { continue }
            matchmaker.join(player, rating: rating, at: .now)
        }
    }
}
