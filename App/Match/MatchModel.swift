import Foundation
import HeistCore
import SwiftUI

/// Runs a Tournament match against whoever the server finds (another player, or a bot after 10 s): the
/// queue, the coin flip, each round's role reveal, briefing, prep, intel and chase, the round result and
/// series scoreboard, and the match end. The server runs the rules and the timers and sends this player's
/// view; the model turns its messages into screens, paced by the server's deadlines, and sends the
/// player's choices back. Debug builds can play the same match offline against the in-app server.
@MainActor
@Observable
final class MatchModel {
    enum Phase: Equatable {
        case connecting, searching, failed
        case coinFlip, roleReveal, briefing, prep, prepLocked, intel, chase, resolving, roundResult, series, matchOver

        /// Phases shown as their own full screen rather than over the board.
        var isInterstitial: Bool {
            switch self {
            case .connecting, .searching, .failed, .coinFlip, .roleReveal, .roundResult, .series, .matchOver: true
            default: false
            }
        }
    }

    enum MoveChoice: Equatable {
        case none, wait, tile(Hex)
    }

    private(set) var phase: Phase = .connecting
    private(set) var roundNumber = 1
    private(set) var role: Role = .thief
    /// What this player knows of the round, as the server last sent it.
    private(set) var view = PlayerView.empty
    private(set) var score = Score()
    private(set) var secondsLeft = 0
    private(set) var phaseLength = 1

    // Queue
    private(set) var waitedSeconds = 0
    private(set) var botAfterSeconds = 10
    private(set) var opponentFound = false
    /// Why the match can't go on, on the failed screen.
    private(set) var problem = ""

    // Prep
    private(set) var hand: [CardID] = []
    private(set) var plays: [PrepPlay] = []
    private(set) var selectedCard: CardID?
    private(set) var targetTile: Hex?
    private(set) var intel: [IntelLine] = []

    // Chase
    private(set) var move: MoveChoice = .none
    private(set) var armedCard: CardID?
    /// An instant card already played this turn (one card per turn).
    private(set) var instantPlayed = false
    /// The opponent has locked in this turn or prep.
    private(set) var opponentLocked = false
    private(set) var toast: MatchNote?
    private(set) var feedback = Feedback(kind: .selection, count: 0)

    // Series
    private(set) var player = PlayerSummary.sample
    private(set) var opponent = Opponent.unknown
    /// Won the coin flip: Player 1 (seat A) is the thief in rounds 1–3 and 7.
    private(set) var userIsPlayer1 = true
    private(set) var startRatings = Ratings(thief: 1000, police: 1000, overall: 1000)
    private(set) var ratings = Ratings(thief: 1000, police: 1000, overall: 1000)
    private(set) var records: [RoundRecord] = []
    private(set) var finalResult: ServerMessage.SeriesEnd?

    // Quick chat
    private(set) var myBubble: ChatBubble?
    private(set) var theirBubble: ChatBubble?
    private(set) var muted = false
    private var chatReadyAt = Date.distantPast

    private let onExit: () -> Void
    private let onPlayAgain: () -> Void
    private let connection: GameConnection
    private var started = false
    private var you = Seat.a
    private var series = Tournament()
    /// Both players' full ratings as the match goes, for each round's rating change.
    private var myRatings = HeistCore.Ratings.starting(at: 1000)
    private var theirRatings = HeistCore.Ratings.starting(at: 1000)
    /// The bushes on the map before prep, so planted ones can look different.
    private(set) var mapBushes: Set<Hex> = []
    /// Server clock minus this phone's clock, in seconds.
    private var clockOffset = 0.0
    private var deadline: Double?
    private var resultEndsAt: Double?
    private var ticker: Task<Void, Never>?
    private var inbox: [ServerMessage] = []
    private var pump: Task<Void, Never>?
    private var reconnects = 0
    private var toastQueue: [MatchNote] = []
    private var toastTask: Task<Void, Never>?

    struct Score: Equatable {
        var you = 0
        /// The opponent's round wins (a bot or a player).
        var bot = 0
    }

    struct Feedback: Equatable {
        enum Kind { case selection, lock, alert, success, failure }
        let kind: Kind
        let count: Int
    }

    init(onExit: @escaping () -> Void, onPlayAgain: @escaping () -> Void) {
        self.onExit = onExit
        self.onPlayAgain = onPlayAgain
        connection = GameConnection(target: GameServerAddress.target)
    }

    var pointsLeft: Int {
        MatchRules.prepPoints - plays.reduce(0) { $0 + $1.card.cost }
    }

    var chaseCards: [CardID] { view.cards }

    var roundLabel: String { "Round \(roundNumber) · Tournament" }

    func role(inRound number: Int) -> Role {
        let role = MatchRules.player1Role(inRound: number)
        return userIsPlayer1 ? role : role.other
    }

    var nextRole: Role { role(inRound: roundNumber + 1) }

    var lastRecord: RoundRecord? { records.last }

    /// The match has a result: someone reached 4 wins in rounds 1 to 6, or both extension rounds are played.
    var isDecided: Bool { series.outcome != nil || finalResult != nil }

    /// Rounds 7 and 8, played at 3–3.
    var isExtension: Bool { roundNumber > MatchRules.regularRounds }

    var outcome: Outcome {
        if let finalResult { return finalResult.draw ? .draw : finalResult.youWon ? .win : .loss }
        return score.you > score.bot ? .win : score.you < score.bot ? .loss : .draw
    }

    /// Sample rewards for finishing the match, until the economy exists.
    var rewards: (coins: Int, xp: Int) {
        switch outcome {
        case .win: (240, 600)
        case .draw: (160, 450)
        case .loss: (120, 300)
        }
    }

    // MARK: Connection

    func start() {
        guard !started else { return }
        started = true
        connection.onEvent = { [weak self] event in self?.receive(event) }
        connect()
    }

    private func connect() {
        phase = phase == .failed ? .connecting : phase
        var token: String?
        var name = UserDefaults.standard.string(forKey: "playerName") ?? ""
        switch connection.target {
        case .remote(let url): token = GuestToken.load(for: url.host() ?? "")
        case .local: name = player.name
        }
        connection.open(ClientMessage.Hello(token: token, name: name))
    }

    /// Tries again from the failed screen.
    func retry() {
        reconnects = 0
        phase = .connecting
        connect()
    }

    private func receive(_ event: GameConnection.Event) {
        switch event {
        case .message(let envelope):
            if let time = envelope.serverTime {
                clockOffset = Double(time) / 1000 - Date.now.timeIntervalSince1970
            }
            inbox.append(envelope.message)
            if pump == nil {
                pump = Task { await self.drain() }
            }
        case .lost:
            guard phase != .matchOver, phase != .failed else { return }
            reconnects += 1
            guard reconnects <= 5 else { return fail("Can't reach the game server. Check your connection and try again.") }
            show([MatchNote(text: "Connection lost. Reconnecting…", tone: .alert)])
            after(Double(reconnects)) { $0.connect() }
        }
    }

    /// Handles messages one at a time; some leave a pause before the next, so moves can play out.
    private func drain() async {
        while !inbox.isEmpty {
            let message = inbox.removeFirst()
            if let pause = handle(message) {
                try? await Task.sleep(for: pause)
            }
        }
        pump = nil
    }

    private func handle(_ message: ServerMessage) -> Duration? {
        switch message {
        case .welcome(let welcome):
            reconnects = 0
            player.name = welcome.player.name
            myRatings = welcome.player.ratings
            if case .remote(let url) = connection.target { GuestToken.save(welcome.token, for: url.host() ?? "") }
            if welcome.matchId == nil, phase == .connecting || phase == .searching {
                connection.send(.queueJoin(.init()))
                phase = .searching
            } else if welcome.matchId == nil, phase != .matchOver, finalResult == nil {
                // Back after the match ended without us: away longer than the server's grace period.
                fail("You were away too long, so the match was forfeited.")
            }
        case .queueStatus(let status):
            waitedSeconds = status.waitedSeconds
            botAfterSeconds = status.botAfterSeconds
            if phase == .connecting { phase = .searching }
        case .matchFound(let found):
            opponent = Opponent(found.opponent)
            opponentFound = true
            connection.send(.matchReady)
            buzz(.success)
        case .seriesStart(let start):
            you = start.youAre
            userIsPlayer1 = start.youAre == .a
            opponent = Opponent(start.opponent)
            myRatings = start.you.ratings
            theirRatings = start.opponent.ratings
            startRatings = Ratings(myRatings)
            ratings = startRatings
            records = []
            series = Tournament()
            score = Score()
            finalResult = nil
            withAnimation(.easeInOut(duration: 0.4)) { phase = .coinFlip }
            countdown(to: start.firstRoundAt, fallback: MatchRules.coinFlipSeconds)
        case .roundBriefing(let briefing):
            beginRound(briefing.round, role: briefing.role, view: briefing.view, score: briefing.score)
            withAnimation(.easeInOut(duration: 0.4)) { phase = .roleReveal }
            countdown(to: briefing.deadline)
        case .prepDeal(let deal):
            hand = deal.hand
            plays = []
            cancelSelection()
            phase = .prep
            countdown(to: deal.deadline)
        case .prepResult(let result):
            view = result.view
            intel = result.intel.map { IntelLine(card: $0.card, text: $0.appText(for: role, view: result.view)) }
            phase = .intel
            countdown(to: result.deadline)
        case .turnStart(let start):
            view = start.view
            move = .none
            armedCard = nil
            instantPlayed = start.view.instantUsed
            opponentLocked = false
            phase = .chase
            countdown(to: start.deadline)
        case .infoResult(let info):
            view = info.view
            instantPlayed = true
            show([MatchNote(text: info.note.appText(for: role, view: info.view), tone: info.note.matchTone, tile: info.note.tile)])
        case .opponentLocked:
            opponentLocked = true
        case .turnResult(let result):
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) { view = result.view }
            show(result.notes.map { MatchNote(text: $0.appText(for: role, view: result.view), tone: $0.matchTone, tile: $0.tile) })
            return .seconds(1)
        case .roundEnd(let end):
            finishRound(end)
        case .seriesEnd(let end):
            finalResult = end
            startRatings = Ratings(end.ratingsBefore)
            ratings = Ratings(end.ratingsAfter)
            score = Score(you: end.score[you], bot: end.score[you.other])
            if phase != .roundResult {
                ticker?.cancel()
                buzz(outcome == .win ? .success : .failure)
                withAnimation(.spring(duration: 0.6, bounce: 0.25)) { phase = .matchOver }
            }
        case .matchState(let state):
            restore(state)
        case .matchCancelled(let cancelled):
            opponentFound = false
            if cancelled.requeued {
                phase = .searching
            } else {
                fail("The match was called off before it started.")
            }
        case .emote(let emote):
            if let message = ChatMessage(wire: emote.id), !muted {
                show(ChatBubble(fromYou: false, message: message))
            }
        case .error(let error):
            refused(error)
        }
        return nil
    }

    private func beginRound(_ number: Int, role: Role, view: PlayerView, score seats: SeatPair<Int>) {
        roundNumber = number
        self.role = role
        self.view = view
        mapBushes = Set(view.bushes)
        score = Score(you: seats[you], bot: seats[you.other])
        hand = []
        plays = []
        intel = []
        cancelSelection()
        move = .none
        armedCard = nil
        instantPlayed = false
        opponentLocked = false
        toast = nil
        toastQueue = []
    }

    private func finishRound(_ end: ServerMessage.RoundEnd) {
        series.record(winner: end.winner)
        score = Score(you: end.score[you], bot: end.score[you.other])
        let roundRole = role
        // The rating change this round makes, worked out as the server will at the end of the match.
        let before = myRatings[roundRole]
        let rated = Elo.rate(SeatPair(a: myRatings, b: theirRatings),
                             rounds: [RatedRound(thief: roundRole == .thief ? .a : .b, winner: end.youWon ? .a : .b)],
                             winner: nil, rules: EloRules())
        myRatings[roundRole] = rated.a[roundRole]
        theirRatings[roundRole.other] = rated.b[roundRole.other]
        ratings[roundRole] = Int(myRatings[roundRole].value.rounded())
        records.append(RoundRecord(number: end.round, role: roundRole, end: RoundEnd(end.result), endTurn: end.result.turns,
                                   robbed: end.reveal.robbedAt, ratingBefore: Int(before.value.rounded()),
                                   ratingAfter: ratings[roundRole], replay: RoundReplay(end.reveal, result: end.result)))
        view = view.revealing(end.reveal)
        buzz(end.youWon ? .success : .failure)
        toast = nil
        toastQueue = []
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { phase = .roundResult }
        if let next = end.nextRoundAt {
            resultEndsAt = nil
            countdown(to: next)
        } else {
            resultEndsAt = Date.now.timeIntervalSince1970 + Double(MatchRules.resultSeconds)
            countdown(to: nil, fallback: MatchRules.resultSeconds)
        }
    }

    /// After a reconnect: rebuild the screen from the server's full state.
    private func restore(_ state: ServerMessage.MatchState) {
        you = state.youAre
        userIsPlayer1 = state.youAre == .a
        opponent = Opponent(state.opponent)
        if let view = state.view {
            if state.round != roundNumber || mapBushes.isEmpty { mapBushes = Set(view.bushes) }
            self.view = view
        }
        roundNumber = state.round
        role = state.role
        score = Score(you: state.score[you], bot: state.score[you.other])
        if let hand = state.hand { self.hand = hand }
        switch state.phase {
        case "ready":
            connection.send(.matchReady)
            phase = .searching
        case "coinFlip": phase = .coinFlip
        case "briefing": phase = .briefing
        case "prep": phase = state.locked ? .prepLocked : .prep
        case "intel": phase = .intel
        case "chase":
            move = .none
            armedCard = nil
            instantPlayed = state.view?.instantUsed ?? false
            phase = state.locked ? .resolving : .chase
        case "roundEnd": phase = isDecided ? .roundResult : .series
        default: phase = .matchOver
        }
        countdown(to: state.deadline, fallback: 0)
    }

    private func refused(_ error: ServerMessage.ServerError) {
        let prepRefusals: Set = ["not_your_card", "not_in_hand", "played_twice", "over_budget", "bad_target"]
        let moveRefusals: Set = ["too_many_steps", "illegal_step", "one_card_per_turn", "needs_info_use", "not_instant", "not_your_card", "not_in_hand"]
        switch error.code {
        case "update_required":
            fail(error.message)
        case "wrong_turn", "already_locked", "bot_playing":
            break
        case let code where phase == .prepLocked && prepRefusals.contains(code):
            // Back to choosing, so the player can fix it before the deadline.
            phase = .prep
            show([MatchNote(text: error.message, tone: .alert)])
        case let code where phase == .resolving && moveRefusals.contains(code):
            phase = .chase
            show([MatchNote(text: error.message, tone: .alert)])
        default:
            show([MatchNote(text: error.message, tone: .alert)])
        }
    }

    private func fail(_ message: String) {
        ticker?.cancel()
        connection.close()
        problem = message
        withAnimation(.easeInOut(duration: 0.3)) { phase = .failed }
    }

    // MARK: Leaving and local skips

    /// Leaving a running match forfeits it; leaving the queue just stops the search.
    func leave() {
        switch phase {
        case .connecting, .searching: connection.send(.queueLeave)
        case .matchOver, .failed: break
        default: connection.send(.matchLeave)
        }
        stop()
        onExit()
    }

    func playAgain() {
        stop()
        onPlayAgain()
    }

    private func stop() {
        ticker?.cancel()
        toastTask?.cancel()
        pump?.cancel()
        // Give the last message a moment to go out before the socket closes.
        let connection = connection
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            connection.close()
        }
    }

    /// Skips ahead on screens that only show information; the server keeps the real timers.
    func skipAhead() {
        switch phase {
        case .roleReveal:
            withAnimation(.easeInOut(duration: 0.4)) { phase = .briefing }
        case .roundResult:
            afterResult()
        default:
            break
        }
    }

    private func afterResult() {
        guard phase == .roundResult else { return }
        if isDecided {
            guard finalResult != nil else { return }
            ticker?.cancel()
            buzz(outcome == .win ? .success : .failure)
            withAnimation(.spring(duration: 0.6, bounce: 0.25)) { phase = .matchOver }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) { phase = .series }
        }
    }

    // MARK: Prep choices

    func lockInPrep() {
        guard phase == .prep else { return }
        cancelSelection()
        connection.send(.prepSubmit(.init(plays: plays)))
        phase = .prepLocked
        buzz(.lock)
    }

    func select(_ card: CardID) {
        guard phase == .prep else { return }
        if selectedCard == card {
            cancelSelection()
            return
        }
        let placed = plays.contains { $0.card == card }
        guard placed || card.cost <= pointsLeft else {
            buzz(.failure)
            return
        }
        selectedCard = card
        targetTile = placed ? plays.first { $0.card == card }?.tile : nil
        buzz(.selection)
    }

    func cancelSelection() {
        selectedCard = nil
        targetTile = nil
    }

    var selectedIsPlaced: Bool {
        guard let selectedCard else { return false }
        return plays.contains { $0.card == selectedCard }
    }

    /// Where the selected card may go, judged by what this role knows (the server checks it again).
    var validTargets: Set<Hex> {
        guard let card = selectedCard, !selectedIsPlaced else { return [] }
        let taken = Set(plays.compactMap(\.tile))
        switch card.target {
        case .freeTile: return Set(view.board.cells.filter { isPlaceable($0) && !taken.contains($0) })
        case .chest: return Set(view.chests.map(\.tile)).subtracting(taken)
        case .area: return Set(view.board.cells)
        case .none: return []
        }
    }

    private func isPlaceable(_ tile: Hex) -> Bool {
        let terrain = view.terrain
        guard terrain.isOpen(tile), terrain.tunnelExit[tile] == nil, tile != view.thiefStart, tile != view.policeStart,
              !view.bushes.contains(tile), !view.boxes.contains(tile) else { return false }
        return role == .police ? !view.chests.contains { $0.tile == tile } : !view.exits.contains(tile)
    }

    /// Ready to place: a target is picked, or the card needs none.
    var canPlace: Bool {
        guard let card = selectedCard, !selectedIsPlaced else { return false }
        return card.target == .none || targetTile != nil
    }

    func place() {
        guard canPlace, let card = selectedCard else { return }
        plays.append(PrepPlay(card: card, tile: targetTile))
        cancelSelection()
        buzz(.lock)
    }

    /// Takes a placed card back before locking in, refunding its points.
    func takeBack() {
        guard let card = selectedCard else { return }
        plays.removeAll { $0.card == card }
        cancelSelection()
        buzz(.selection)
    }

    // MARK: Chase choices

    /// Tiles the player can move to this turn, with the steps to each.
    var reach: [Hex: [Hex]] {
        view.terrain.moves(from: view.position, steps: armedCard == .run ? 2 : 1)
    }

    func chooseWait() {
        guard phase == .chase else { return }
        move = move == .wait ? .none : .wait
        buzz(.selection)
    }

    func play(_ card: CardID) {
        guard phase == .chase, !instantPlayed else { return }
        if card.isInstant {
            guard armedCard == nil else { return }
            instantPlayed = true
            connection.send(.infoUse(.init(card: card)))
        } else {
            armedCard = armedCard == card ? nil : card
            if case .tile(let tile) = move, reach[tile] == nil { move = .none }
        }
        buzz(.selection)
    }

    /// Locks the chosen move (no choice locks a wait); the server plays the turn out once both are in.
    func lockMove() {
        guard phase == .chase else { return }
        let path: [Hex]
        if case .tile(let tile) = move { path = reach[tile] ?? [] } else { path = [] }
        connection.send(.turnSubmit(.init(turn: view.turn, plan: MovePlan(path: path, card: armedCard))))
        phase = .resolving
        buzz(.lock)
    }

    func tap(_ tile: Hex) {
        switch phase {
        case .prep:
            guard validTargets.contains(tile) else { return }
            targetTile = tile
            buzz(.selection)
        case .chase:
            guard reach[tile] != nil else { return }
            move = move == .tile(tile) ? .none : .tile(tile)
            buzz(.selection)
        default:
            break
        }
    }

    // MARK: Quick chat

    nonisolated static let chatPhrases = ["Good luck!", "Nice move!", "So close!", "Oops!", "Well played!", "Good game!"]

    /// After a message there is a short pause before the next one.
    var canChat: Bool { Date.now >= chatReadyAt }

    func send(_ message: ChatMessage) {
        guard canChat else { return }
        chatReadyAt = .now.addingTimeInterval(3)
        show(ChatBubble(fromYou: true, message: message))
        connection.send(.emote(HeistCore.Emote(id: message.wire)))
        buzz(.selection)
    }

    func toggleMute() {
        muted.toggle()
        if muted { withAnimation(.easeOut(duration: 0.2)) { theirBubble = nil } }
    }

    private func show(_ bubble: ChatBubble) {
        withAnimation(.spring(duration: 0.35, bounce: 0.35)) {
            if bubble.fromYou { myBubble = bubble } else { theirBubble = bubble }
        }
        after(2.6) { model in
            withAnimation(.easeOut(duration: 0.25)) {
                if model.myBubble == bubble { model.myBubble = nil }
                if model.theirBubble == bubble { model.theirBubble = nil }
            }
        }
    }

    // MARK: Helpers

    /// Counts down to a server deadline (milliseconds since 1970, server clock). The role reveal hands over
    /// to the briefing, and the round result to the series screen, within the same deadline.
    private func countdown(to serverDeadline: Int64?, fallback: Int = 0) {
        ticker?.cancel()
        let now = Date.now.timeIntervalSince1970
        let end = serverDeadline.map { Double($0) / 1000 - clockOffset } ?? now + Double(fallback)
        deadline = end
        phaseLength = max(1, Int((end - now).rounded(.up)))
        secondsLeft = phaseLength
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard let deadline else { return }
        let left = deadline - Date.now.timeIntervalSince1970
        secondsLeft = max(0, Int(left.rounded(.up)))
        switch phase {
        case .roleReveal where left <= Double(MatchRules.briefingSeconds):
            withAnimation(.easeInOut(duration: 0.4)) { phase = .briefing }
            phaseLength = max(1, secondsLeft)
        case .roundResult where resultEndsAt == nil && !isDecided && left <= Double(MatchRules.seriesSeconds):
            afterResult()
            phaseLength = max(1, secondsLeft)
        case .roundResult where resultEndsAt != nil && left <= 0:
            afterResult()
        default:
            break
        }
    }

    private func after(_ seconds: Double, _ action: @escaping (MatchModel) -> Void) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            action(self)
        }
    }

    /// Shows notes one after another under the top bar.
    private func show(_ notes: [MatchNote]) {
        toastQueue += notes.filter { !$0.text.isEmpty }
        if notes.contains(where: { $0.tone == .alert }) { buzz(.alert) }
        guard toastTask == nil else { return }
        toastTask = Task { [weak self] in
            while let self, !self.toastQueue.isEmpty {
                let note = self.toastQueue.removeFirst()
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { self.toast = note }
                try? await Task.sleep(for: .seconds(2.6))
            }
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.toast = nil }
            self.toastTask = nil
        }
    }

    private func buzz(_ kind: Feedback.Kind) {
        feedback = Feedback(kind: kind, count: feedback.count + 1)
    }
}

enum Outcome { case win, loss, draw }

/// A player's ratings as the screens show them: thief, police, and overall (the main rank).
struct Ratings: Equatable {
    var thief: Int
    var police: Int
    var overall: Int

    /// The main rank.
    var combined: Int { overall }

    init(thief: Int, police: Int, overall: Int) {
        self.thief = thief
        self.police = police
        self.overall = overall
    }

    init(_ ratings: HeistCore.Ratings) {
        self.init(thief: Int(ratings.thief.value.rounded()), police: Int(ratings.police.value.rounded()),
                  overall: Int(ratings.overall.value.rounded()))
    }

    subscript(role: Role) -> Int {
        get { role == .thief ? thief : police }
        set { if role == .thief { thief = newValue } else { police = newValue } }
    }
}

/// Who the server matched you with. Bots are always marked as bots.
struct Opponent {
    let name: String
    let ratings: Ratings
    let isBot: Bool

    static let unknown = Opponent(name: "Opponent", ratings: Ratings(thief: 1000, police: 1000, overall: 1000), isBot: false)

    init(name: String, ratings: Ratings, isBot: Bool) {
        self.name = name
        self.ratings = ratings
        self.isBot = isBot
    }

    init(_ card: PlayerCard) {
        self.init(name: card.name, ratings: Ratings(card.ratings), isBot: card.isBot)
    }
}

/// What happened in one finished round, from the player's side.
struct RoundRecord: Identifiable {
    let number: Int
    let role: Role
    let end: RoundEnd
    let endTurn: Int
    let robbed: Sighting?
    let ratingBefore: Int
    let ratingAfter: Int
    let replay: RoundReplay

    var id: Int { number }
    var won: Bool { end.winner == role }

    var headline: String {
        switch (role, end) {
        case (.thief, .escaped): "YOU ESCAPED!"
        case (.thief, .caught): "CAUGHT!"
        case (.police, .caught): "GOT THEM!"
        case (.police, .escaped): "THEY ESCAPED"
        case (_, .time): "TIME'S UP!"
        }
    }

    /// One line of how the round went, for the result screen.
    var detail: String {
        let robbedText = robbed.map { "Robbed \(Harbor.name($0.tile)) on turn \($0.turn)" }
        switch end {
        case .escaped(let exit):
            return [robbedText, "out through \(Harbor.name(exit)) on turn \(endTurn)"].compactMap { $0 }.joined(separator: " · ")
        case .caught(let tile):
            return ["Caught on \(Harbor.name(tile)) on turn \(endTurn)", robbed.map { "after robbing \(Harbor.name($0.tile))" }].compactMap { $0 }.joined(separator: " · ")
        case .time:
            return robbedText.map { "\($0) · no way out in \(MatchRules.chaseTurns) turns" } ?? "No chest robbed in \(MatchRules.chaseTurns) turns"
        }
    }

    /// Short line for the series scoreboard.
    var summary: String {
        switch (role, end) {
        case (.thief, .escaped): "You escaped on turn \(endTurn)"
        case (.thief, .caught): "Caught on turn \(endTurn)"
        case (.thief, .time): "Time ran out"
        case (.police, .caught): "You caught them on turn \(endTurn)"
        case (.police, .time): "They ran out of time"
        case (.police, .escaped): "They escaped on turn \(endTurn)"
        }
    }
}

enum Emote: String, CaseIterable {
    case thumbsUp, heart, laugh, goodGame

    var symbol: String? {
        switch self {
        case .thumbsUp: "hand.thumbsup.fill"
        case .heart: "heart.fill"
        case .laugh: "face.smiling.inverse"
        case .goodGame: nil
        }
    }

    var label: String {
        switch self {
        case .thumbsUp: "thumbs up"
        case .heart: "heart"
        case .laugh: "laughing"
        case .goodGame: "G G, good game"
        }
    }

    var colors: [Color] {
        switch self {
        case .thumbsUp: [Color(hex: 0x5BD07A), Color(hex: 0x1E7A3A)]
        case .heart: [Color(hex: 0xFF7AA8), Color(hex: 0xC42A62)]
        case .laugh: [Color(hex: 0xFFE15C), Color(hex: 0xE0A000)]
        case .goodGame: [Color(hex: 0xA27BFF), Color(hex: 0x5B34C9)]
        }
    }
}

enum ChatMessage: Equatable {
    case phrase(String)
    case emote(Emote)

    /// How it travels in an `emote` message: "phrase:Good luck!" or "emote:heart".
    var wire: String {
        switch self {
        case .phrase(let text): "phrase:" + text
        case .emote(let emote): "emote:" + emote.rawValue
        }
    }

    init?(wire: String) {
        if wire.hasPrefix("phrase:") {
            let text = String(wire.dropFirst(7))
            guard MatchModel.chatPhrases.contains(text) else { return nil }
            self = .phrase(text)
        } else if wire.hasPrefix("emote:"), let emote = Emote(rawValue: String(wire.dropFirst(6))) {
            self = .emote(emote)
        } else {
            return nil
        }
    }
}

struct ChatBubble: Identifiable, Equatable {
    let id = UUID()
    let fromYou: Bool
    let message: ChatMessage
}
