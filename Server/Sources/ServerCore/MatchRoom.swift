import Foundation
import HeistCore

/// What the room reports back when a match ends.
struct MatchReport: Sendable {
    var record: MatchRecord
    var rounds: [RatedRound]
    /// Nil on a draw.
    var winner: Seat?
}

/// Rating changes for both seats, as `PlayerStore.finish` returns them.
typealias RatingUpdate = SeatPair<(before: Ratings, after: Ratings)>

/// One match: the ready check, then the tournament's rounds (briefing, deal, prep, intel reveal, chase
/// turns, result) on server timers. The room holds the full state and sends each player only their own
/// view. Bots, takeovers and dropped players are played by the HeistCore bot from that player's view.
actor MatchRoom {
    enum Phase: String {
        case ready, briefing, prep, intel, chase, roundEnd, over
    }

    private enum TimerAction {
        case readyTimeout, beginPrep, prepTimeout, beginTurn, turnTimeout, nextRound
    }

    /// Identifies a moment of the match, so a late timer or bot answer for an earlier one is ignored.
    private struct Moment: Equatable {
        var round: Int
        var phase: Phase
        var turn: Int
    }

    struct SeatState {
        var player: PlayerCard
        var link: ClientLink?
        var ready: Bool
        var seq = 0
        var timeoutsInRow = 0
        /// The bot decides for this seat: a bot player, a player who dropped, or one who timed out too often.
        var botControl: Bool
        var bot = Bot(seed: 0)
        var graceGeneration = 0
    }

    let id: String
    private let config: ServerConfig
    private let seedHex: String
    private var random: SeededRandom
    private(set) var seats: SeatPair<SeatState>
    private var series = Tournament()
    private var round: Round?
    /// The round being played, or just finished during its result screen.
    private var roundNumber = 1
    private(set) var phase = Phase.ready
    private var deadline: Int64?
    private var timerGeneration = 0
    private var prepPlays = SeatPair<[PrepPlay]?>(repeating: nil)
    private var plans = SeatPair<MovePlan?>(repeating: nil)
    private var record: MatchRecord
    private let onFinish: @Sendable (MatchReport) async -> RatingUpdate?
    private let onCancel: @Sendable (_ matchID: String, _ requeue: [String]) async -> Void

    /// `players` are already in seat order: the coin flip that picks seat A happens before.
    init(id: String, config: ServerConfig, seed: UInt64, players: SeatPair<PlayerCard>, links: SeatPair<ClientLink?>,
         onFinish: @escaping @Sendable (MatchReport) async -> RatingUpdate?,
         onCancel: @escaping @Sendable (String, [String]) async -> Void) {
        self.id = id
        self.config = config
        self.onFinish = onFinish
        self.onCancel = onCancel
        random = SeededRandom(seed: seed)
        seedHex = String(seed, radix: 16)
        seats = SeatPair(
            a: SeatState(player: players.a, link: links.a, ready: players.a.isBot, botControl: players.a.isBot),
            b: SeatState(player: players.b, link: links.b, ready: players.b.isBot, botControl: players.b.isBot)
        )
        record = MatchRecord(id: id, mode: .tournament, rulesVersion: Round.rulesVersion, seed: seedHex, started: .now,
                             players: SeatPair(a: players.a.id, b: players.b.id))
    }

    private var moment: Moment {
        Moment(round: roundNumber, phase: phase, turn: round?.turn ?? 0)
    }

    private func role(of seat: Seat) -> Role {
        Tournament.role(of: seat, inRound: roundNumber)
    }

    private func seat(playing role: Role) -> Seat {
        let thief = Tournament.thief(inRound: roundNumber)
        return role == .thief ? thief : thief.other
    }

    // MARK: Sending

    private func send(_ message: ServerMessage, to seat: Seat) {
        guard let link = seats[seat].link else { return }
        seats[seat].seq += 1
        link.send(ServerEnvelope(message, seq: seats[seat].seq, matchId: id))
    }

    private func error(_ error: ActionError, to seat: Seat) {
        send(.error(.init(code: error.code, message: error.message)), to: seat)
    }

    private func error(_ code: String, _ message: String, to seat: Seat) {
        send(.error(.init(code: code, message: message)), to: seat)
    }

    // MARK: Timers

    private func schedule(_ duration: Duration, _ action: TimerAction) {
        timerGeneration += 1
        let generation = timerGeneration
        deadline = wallClock(after: duration)
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            await self?.fire(action, generation: generation)
        }
    }

    private func fire(_ action: TimerAction, generation: Int) async {
        guard generation == timerGeneration, phase != .over else { return }
        switch action {
        case .readyTimeout: await cancel()
        case .beginPrep: beginPrep()
        case .prepTimeout: resolvePrep()
        case .beginTurn: beginTurn()
        case .turnTimeout: turnTimedOut()
        case .nextRound: beginRound()
        }
    }

    /// Lets the bot decide for `seat` after a human-looking pause.
    private func scheduleBot(_ seat: Seat, think: ClosedRange<Double>) {
        let at = moment
        let delay = Double.random(in: think)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.botAct(seat, at: at)
        }
    }

    private func botAct(_ seat: Seat, at: Moment) async {
        guard at == moment, seats[seat].botControl, var round else { return }
        let role = role(of: seat)
        switch phase {
        case .prep where prepPlays[seat] == nil:
            let plays = seats[seat].bot.prep(view: round.view(for: role), hand: round.prepHands[role], points: round.rules.prepPoints)
            submitPrep(plays, from: seat)
        case .chase where plans[seat] == nil:
            if let card = seats[seat].bot.instant(view: round.view(for: role)), (try? round.useInstant(card, by: role)) != nil {
                self.round = round
                record.rounds[record.rounds.count - 1].instants.append(.init(turn: round.turn, seat: seat, card: card))
            }
            let plan = seats[seat].bot.move(view: round.view(for: role))
            submitPlan(plan, turn: round.turn, from: seat, byPlayer: false)
        default:
            break
        }
    }

    // MARK: Flow

    func start() {
        phase = .ready
        schedule(config.readyCheck, .readyTimeout)
        for seat in Seat.allCases {
            send(.matchFound(.init(mode: .tournament, opponent: seats[seat.other].player, readyDeadline: deadline ?? 0)), to: seat)
        }
        startIfReady()
    }

    private func startIfReady() {
        guard phase == .ready, seats.a.ready, seats.b.ready else { return }
        for seat in Seat.allCases {
            send(.seriesStart(.init(youAre: seat, you: seats[seat].player, opponent: seats[seat.other].player,
                                    thiefSchedule: Tournament.thiefSchedule, winTarget: Tournament.winTarget)), to: seat)
        }
        beginRound()
    }

    /// Someone didn't confirm in time: the match is off, and whoever did confirm goes back in the queue.
    private func cancel() async {
        phase = .over
        timerGeneration += 1
        var requeue: [String] = []
        for seat in Seat.allCases where !seats[seat].player.isBot {
            let ready = seats[seat].ready && seats[seat].link != nil
            if ready { requeue.append(seats[seat].player.id) }
            send(.matchCancelled(.init(reason: "ready_timeout", requeued: ready)), to: seat)
        }
        await onCancel(id, requeue)
    }

    private func beginRound() {
        roundNumber = series.round
        let roundSeed = random.next()
        var roundRandom = SeededRandom(seed: roundSeed)
        let map = MapGenerator.generate(config.map, random: &roundRandom)
        let round = Round(map: map, rules: config.round, seed: roundRandom.next())
        self.round = round
        for seat in Seat.allCases {
            seats[seat].bot = Bot(seed: roundRandom.next())
            seats[seat].timeoutsInRow = 0
            if !seats[seat].player.isBot, seats[seat].link != nil { seats[seat].botControl = false }
        }
        prepPlays = .init(repeating: nil)
        plans = .init(repeating: nil)
        record.rounds.append(.init(seed: String(roundSeed, radix: 16), thief: Tournament.thief(inRound: roundNumber)))
        phase = .briefing
        schedule(config.briefing, .beginPrep)
        for seat in Seat.allCases {
            let role = role(of: seat)
            send(.roundBriefing(.init(round: roundNumber, role: role, view: round.view(for: role), score: series.score, deadline: deadline ?? 0)), to: seat)
        }
    }

    private func beginPrep() {
        guard let round else { return }
        phase = .prep
        schedule(config.prep, .prepTimeout)
        for seat in Seat.allCases {
            let role = role(of: seat)
            send(.prepDeal(.init(round: roundNumber, hand: round.prepHands[role], points: round.rules.prepPoints, deadline: deadline ?? 0)), to: seat)
            if seats[seat].botControl { scheduleBot(seat, think: config.botPrepThink) }
        }
    }

    private func submitPrep(_ plays: [PrepPlay], from seat: Seat) {
        guard phase == .prep, let round else { return error(.wrongStage, to: seat) }
        guard prepPlays[seat] == nil else { return error("already_locked", "You have already locked in.", to: seat) }
        do {
            try round.checkPrep(plays, for: role(of: seat))
        } catch {
            return self.error(error, to: seat)
        }
        prepPlays[seat] = plays
        send(.opponentLocked(.init(stage: "prep")), to: seat.other)
        if prepPlays.a != nil, prepPlays.b != nil { resolvePrep() }
    }

    /// Police builds, thief builds, thief scans; a player who didn't lock in places nothing.
    private func resolvePrep() {
        guard phase == .prep, var round else { return }
        let thief = seat(playing: .thief), police = thief.other
        let thiefPlays = prepPlays[thief] ?? [], policePlays = prepPlays[police] ?? []
        let intel = round.resolvePrep(thief: thiefPlays, police: policePlays)
        self.round = round
        record.rounds[record.rounds.count - 1].prep = thief == .a ? SeatPair(a: thiefPlays, b: policePlays) : SeatPair(a: policePlays, b: thiefPlays)
        phase = .intel
        schedule(config.intel, .beginTurn)
        for seat in Seat.allCases {
            let role = role(of: seat)
            send(.prepResult(.init(intel: intel[role], view: round.view(for: role), deadline: deadline ?? 0)), to: seat)
        }
    }

    private func beginTurn() {
        guard let round else { return }
        phase = .chase
        plans = .init(repeating: nil)
        schedule(config.turn, .turnTimeout)
        for seat in Seat.allCases {
            send(.turnStart(.init(turn: round.turn, view: round.view(for: role(of: seat)), deadline: deadline ?? 0)), to: seat)
            if seats[seat].botControl { scheduleBot(seat, think: config.botTurnThink) }
        }
    }

    private func useInstant(_ card: CardID, from seat: Seat) {
        guard phase == .chase, var round else { return error(.wrongStage, to: seat) }
        guard plans[seat] == nil else { return error("already_locked", "You have already locked in.", to: seat) }
        do {
            let note = try round.useInstant(card, by: role(of: seat))
            self.round = round
            record.rounds[record.rounds.count - 1].instants.append(.init(turn: round.turn, seat: seat, card: card))
            send(.infoResult(.init(note: note, view: round.view(for: role(of: seat)))), to: seat)
        } catch {
            self.error(error, to: seat)
        }
    }

    private func submitPlan(_ plan: MovePlan, turn: Int, from seat: Seat, byPlayer: Bool) {
        guard phase == .chase, let round else { return error(.wrongStage, to: seat) }
        guard turn == round.turn else { return error("wrong_turn", "That turn is over.", to: seat) }
        guard plans[seat] == nil else { return error("already_locked", "You have already locked in.", to: seat) }
        do {
            try round.checkPlan(plan, for: role(of: seat))
        } catch {
            return self.error(error, to: seat)
        }
        plans[seat] = plan
        if byPlayer { seats[seat].timeoutsInRow = 0 }
        send(.opponentLocked(.init(stage: "turn")), to: seat.other)
        if plans.a != nil, plans.b != nil { resolveTurn() }
    }

    /// A player who didn't lock in waits; too many timeouts in a row and the bot plays the rest of the round.
    private func turnTimedOut() {
        for seat in Seat.allCases where plans[seat] == nil {
            plans[seat] = MovePlan()
            guard !seats[seat].botControl else { continue }
            seats[seat].timeoutsInRow += 1
            if seats[seat].timeoutsInRow >= config.timeoutsBeforeTakeover {
                seats[seat].botControl = true
            }
        }
        resolveTurn()
    }

    private func resolveTurn() {
        guard phase == .chase, var round else { return }
        let thief = seat(playing: .thief), police = thief.other
        let turn = round.turn
        let thiefPlan = plans[thief] ?? MovePlan(), policePlan = plans[police] ?? MovePlan()
        let notes = round.resolveTurn(thief: thiefPlan, police: policePlan)
        self.round = round
        record.rounds[record.rounds.count - 1].turns.append(.init(turn: turn, thief: thiefPlan, police: policePlan))
        for seat in Seat.allCases {
            let role = role(of: seat)
            send(.turnResult(.init(turn: turn, notes: notes[role], view: round.view(for: role))), to: seat)
        }
        if let result = round.result {
            finishRound(result)
        } else {
            beginTurn()
        }
    }

    private func finishRound(_ result: RoundResult) {
        guard let round else { return }
        let winner = seat(playing: result.winner)
        record.rounds[record.rounds.count - 1].result = result
        series.record(winner: winner)
        let over = series.outcome != nil
        phase = .roundEnd
        if !over { schedule(config.roundResult, .nextRound) }
        for seat in Seat.allCases {
            send(.roundEnd(.init(round: roundNumber, result: result, winner: winner, youWon: winner == seat, score: series.score,
                                 reveal: round.reveal(), nextRoundAt: over ? nil : deadline)), to: seat)
        }
        if over {
            Task { await self.finishSeries(forfeitBy: nil) }
        }
    }

    /// Ends the match, rates it and tells both players. A forfeit hands the match to the other seat.
    private func finishSeries(forfeitBy: Seat?) async {
        guard phase != .over else { return }
        phase = .over
        timerGeneration += 1
        let winner: Seat?
        if let forfeitBy {
            winner = forfeitBy.other
        } else if case .win(let seat) = series.outcome {
            winner = seat
        } else {
            winner = nil
        }
        record.ended = .now
        record.outcome = winner?.rawValue ?? "draw"
        record.forfeitBy = forfeitBy
        let rounds = record.rounds.compactMap { round in
            round.result.map { RatedRound(thief: round.thief, winner: $0.winner == .thief ? round.thief : round.thief.other) }
        }
        let update = await onFinish(MatchReport(record: record, rounds: rounds, winner: winner))
        for seat in Seat.allCases {
            let before = update?[seat].before ?? seats[seat].player.ratings
            let after = update?[seat].after ?? before
            send(.seriesEnd(.init(winner: winner, youWon: winner == seat, draw: winner == nil, forfeitBy: forfeitBy, score: series.score,
                                  ratingsBefore: before, ratingsAfter: after, seed: seedHex)), to: seat)
        }
    }

    // MARK: Messages and connections

    func handle(_ message: ClientMessage, from seat: Seat) async {
        switch message {
        case .matchReady:
            seats[seat].ready = true
            startIfReady()
        case .prepSubmit(let submit):
            guard !seats[seat].botControl else { return error("bot_playing", "The bot is playing this round for you.", to: seat) }
            submitPrep(submit.plays, from: seat)
        case .infoUse(let use):
            guard !seats[seat].botControl else { return error("bot_playing", "The bot is playing this round for you.", to: seat) }
            useInstant(use.card, from: seat)
        case .turnSubmit(let submit):
            guard !seats[seat].botControl else { return error("bot_playing", "The bot is playing this round for you.", to: seat) }
            submitPlan(submit.plan, turn: submit.turn, from: seat, byPlayer: true)
        case .resync:
            sendState(to: seat)
        case .matchLeave:
            if phase == .ready {
                await cancel()
            } else {
                await finishSeries(forfeitBy: seat)
            }
        case .emote(let emote):
            send(.emote(emote), to: seat.other)
        case .hello, .queueJoin, .queueLeave:
            break
        }
    }

    /// The player's app dropped: the bot plays for them, and they forfeit if not back in time.
    func detach(_ seat: Seat) {
        seats[seat].link = nil
        guard phase != .over, phase != .ready else { return }
        seats[seat].botControl = true
        if phase == .prep, prepPlays[seat] == nil { scheduleBot(seat, think: config.botTurnThink) }
        if phase == .chase, plans[seat] == nil { scheduleBot(seat, think: config.botTurnThink) }
        seats[seat].graceGeneration += 1
        let generation = seats[seat].graceGeneration
        let grace = config.disconnectGrace
        Task { [weak self] in
            try? await Task.sleep(for: grace)
            await self?.graceEnded(seat, generation: generation)
        }
    }

    private func graceEnded(_ seat: Seat, generation: Int) async {
        guard seats[seat].graceGeneration == generation, seats[seat].link == nil, phase != .over else { return }
        await finishSeries(forfeitBy: seat)
    }

    /// The player is back (a new connection after `hello`): they take over again and get the full state.
    func attach(_ seat: Seat, link: ClientLink) {
        seats[seat].link = link
        seats[seat].graceGeneration += 1
        if phase != .over {
            seats[seat].botControl = false
            seats[seat].timeoutsInRow = 0
        }
        sendState(to: seat)
    }

    private func sendState(to seat: Seat) {
        let role = role(of: seat)
        let locked = phase == .prep ? prepPlays[seat] != nil : phase == .chase ? plans[seat] != nil : false
        let hand = phase == .prep && prepPlays[seat] == nil ? round?.prepHands[role] : nil
        send(.matchState(.init(matchId: id, youAre: seat, opponent: seats[seat.other].player, round: roundNumber, role: role,
                               phase: phase.rawValue, deadline: phase == .over ? nil : deadline, score: series.score,
                               view: round?.view(for: role), hand: hand, locked: locked)), to: seat)
    }
}
