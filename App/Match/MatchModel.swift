import HeistCore
import SwiftUI

/// Runs a Classic sample match against a bot (best of 8, first to 5; 4–4 is a draw): the coin flip, each
/// round's role reveal, briefing, prep, intel and chase, the round result and series scoreboard, and the
/// match end, with their timers and the player's choices, on top of the stand-in rules in `SampleRound`.
@MainActor
@Observable
final class MatchModel {
    enum Phase: Equatable {
        case coinFlip, roleReveal, briefing, prep, prepLocked, intel, chase, resolving, roundResult, series, matchOver

        /// Phases shown as their own full screen rather than over the board.
        var isInterstitial: Bool {
            switch self {
            case .coinFlip, .roleReveal, .roundResult, .series, .matchOver: true
            default: false
            }
        }
    }

    enum MoveChoice: Equatable {
        case none, wait, tile(Hex)
    }

    private(set) var phase: Phase = .coinFlip
    private(set) var roundNumber = 1
    private(set) var role: Role
    private(set) var round: SampleRound
    private(set) var score = Score()
    private(set) var secondsLeft = MatchRules.coinFlipSeconds
    private(set) var phaseLength = MatchRules.coinFlipSeconds

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
    private(set) var toast: MatchNote?
    private(set) var feedback = Feedback(kind: .selection, count: 0)

    // Series
    let player = PlayerSummary.sample
    let opponent = Opponent.sample
    /// Won the coin flip: Player 1 is the thief in rounds 1–3 and 7.
    let userIsPlayer1: Bool
    let startRatings: Ratings
    private(set) var ratings: Ratings
    private(set) var records: [RoundRecord] = []

    // Quick chat
    private(set) var myBubble: ChatBubble?
    private(set) var theirBubble: ChatBubble?
    private(set) var muted = false
    private var chatReadyAt = Date.distantPast

    private let onExit: () -> Void
    private let onPlayAgain: () -> Void
    private var seed: UInt64
    private var timer: Task<Void, Never>?
    private var toastQueue: [MatchNote] = []
    private var toastTask: Task<Void, Never>?

    struct Score: Equatable {
        var you = 0
        var bot = 0
    }

    struct Feedback: Equatable {
        enum Kind { case selection, lock, alert, success, failure }
        let kind: Kind
        let count: Int
    }

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max), onExit: @escaping () -> Void, onPlayAgain: @escaping () -> Void) {
        self.seed = seed
        self.onExit = onExit
        self.onPlayAgain = onPlayAgain
        var coin = SeededRandom(seed: seed)
        // The coin flip decides Player 1, who is the thief first.
        var first: Role = Bool.random(using: &coin) ? .thief : .police
        #if DEBUG
        if let forced = UserDefaults.standard.string(forKey: "matchRole") {
            first = forced == "police" ? .police : .thief
        }
        #endif
        role = first
        userIsPlayer1 = first == .thief
        round = SampleRound(user: first, seed: seed &+ 1)
        startRatings = Ratings(thief: player.thief.rating, police: player.police.rating)
        ratings = startRatings
    }

    var pointsLeft: Int {
        MatchRules.prepPoints - plays.reduce(0) { $0 + $1.card.cost }
    }

    var chaseCards: [CardID] { round.cards[role] ?? [] }

    var roundLabel: String { "Round \(roundNumber) · Classic" }

    func role(inRound number: Int) -> Role {
        let role = MatchRules.player1Role(inRound: number)
        return userIsPlayer1 ? role : role.other
    }

    var nextRole: Role { role(inRound: roundNumber + 1) }

    var lastRecord: RoundRecord? { records.last }

    var outcome: Outcome {
        score.you > score.bot ? .win : score.you < score.bot ? .loss : .draw
    }

    /// Sample rewards for finishing the match, until the economy exists.
    var rewards: (coins: Int, xp: Int) {
        switch outcome {
        case .win: (240, 600)
        case .draw: (160, 450)
        case .loss: (120, 300)
        }
    }

    // MARK: Flow

    func start() {
        guard timer == nil else { return }
        #if DEBUG
        // `-matchJumpToResult YES` waits out round 1, shows the board briefly and opens the result.
        if UserDefaults.standard.bool(forKey: "matchJumpToResult") {
            while round.end == nil { _ = round.resolveTurn(user: MovePlan()) }
            phase = .resolving
            after(2) { $0.finishRound($0.round.end ?? .time) }
            return
        }
        #endif
        phase = .coinFlip
        countdown(MatchRules.coinFlipSeconds) { $0.beginRoleReveal() }
    }

    /// Skips the countdown on screens that only show information.
    func skipAhead() {
        switch phase {
        case .roleReveal: beginBriefing()
        case .briefing: beginPrep()
        case .roundResult: afterResult()
        case .series: nextRound()
        default: break
        }
    }

    func leave() {
        timer?.cancel()
        toastTask?.cancel()
        onExit()
    }

    func playAgain() {
        timer?.cancel()
        toastTask?.cancel()
        onPlayAgain()
    }

    private func beginRoleReveal() {
        withAnimation(.easeInOut(duration: 0.4)) { phase = .roleReveal }
        countdown(MatchRules.roleRevealSeconds) { $0.beginBriefing() }
    }

    private func beginBriefing() {
        withAnimation(.easeInOut(duration: 0.4)) { phase = .briefing }
        countdown(MatchRules.briefingSeconds) { $0.beginPrep() }
    }

    private func beginPrep() {
        hand = round.dealHand(for: role)
        plays = []
        selectedCard = nil
        targetTile = nil
        phase = .prep
        countdown(MatchRules.prepSeconds) { $0.lockInPrep() }
    }

    func lockInPrep() {
        guard phase == .prep else { return }
        timer?.cancel()
        selectedCard = nil
        targetTile = nil
        phase = .prepLocked
        buzz(.lock)
        after(1.2) { model in
            let botPlays = model.round.botPrep()
            model.intel = model.round.resolvePrep(user: model.plays, bot: botPlays)
            model.phase = .intel
            model.countdown(MatchRules.intelSeconds) { $0.beginChase() }
        }
    }

    private func beginChase() {
        move = .none
        armedCard = nil
        instantPlayed = false
        phase = .chase
        countdown(MatchRules.chaseTurnSeconds) { $0.lockMove() }
    }

    /// Locks the chosen move (a timeout locks a wait), then plays the turn out.
    func lockMove() {
        guard phase == .chase else { return }
        timer?.cancel()
        let path: [Hex]
        if case .tile(let tile) = move { path = reach[tile] ?? [] } else { path = [] }
        let plan = MovePlan(path: path, card: armedCard)
        phase = .resolving
        buzz(.lock)
        after(0.5) { model in
            let notes = withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                model.round.resolveTurn(user: plan)
            }
            model.show(notes)
            model.after(1.0) { model in
                if let end = model.round.end {
                    model.finishRound(end)
                } else {
                    model.beginChase()
                }
            }
        }
    }

    private func finishRound(_ end: RoundEnd) {
        let won = end.winner == role
        if won { score.you += 1 } else { score.bot += 1 }
        let before = ratings[role]
        let after = before + Self.ratingChange(mine: before, theirs: opponent.ratings[role.other], won: won)
        ratings[role] = after
        records.append(RoundRecord(number: roundNumber, role: role, end: end, endTurn: round.turn, robbed: round.alarm,
                                   ratingBefore: before, ratingAfter: after, replay: RoundReplay(round)))
        buzz(won ? .success : .failure)
        toast = nil
        toastQueue = []
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { phase = .roundResult }
        countdown(MatchRules.resultSeconds) { $0.afterResult() }
    }

    private var isDecided: Bool {
        score.you >= MatchRules.winsNeeded || score.bot >= MatchRules.winsNeeded || roundNumber >= MatchRules.rounds
    }

    private func afterResult() {
        guard phase == .roundResult else { return }
        if isDecided {
            timer?.cancel()
            buzz(outcome == .win ? .success : .failure)
            withAnimation(.spring(duration: 0.6, bounce: 0.25)) { phase = .matchOver }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) { phase = .series }
            countdown(MatchRules.seriesSeconds) { $0.nextRound() }
        }
    }

    private func nextRound() {
        guard phase == .series else { return }
        roundNumber += 1
        role = role(inRound: roundNumber)
        seed = seed &+ 7919
        round = SampleRound(user: role, seed: seed)
        beginRoleReveal()
    }

    /// A simple Elo-style change per round, standing in for the server's Glicko-2 ratings.
    private static func ratingChange(mine: Int, theirs: Int, won: Bool) -> Int {
        let expected = 1 / (1 + pow(10, Double(theirs - mine) / 400))
        return Int((24 * ((won ? 1 : 0) - expected)).rounded())
    }

    // MARK: Prep choices

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

    /// Where the selected card may go.
    var validTargets: Set<Hex> {
        guard let card = selectedCard, !selectedIsPlaced else { return [] }
        let taken = Set(plays.compactMap(\.tile))
        switch card.target {
        case .freeTile: return Set(Harbor.tiles.filter { round.isFree($0) && !taken.contains($0) })
        case .chest: return Harbor.chests.subtracting(taken)
        case .area: return Set(Harbor.tiles)
        case .none: return []
        }
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
        round.moves(for: role, steps: armedCard == .run ? 2 : 1)
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
            show([round.playInstant(card, by: role)])
        } else {
            armedCard = armedCard == card ? nil : card
            if case .tile(let tile) = move, reach[tile] == nil { move = .none }
        }
        buzz(.selection)
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

    static let chatPhrases = ["Good luck!", "Nice move!", "So close!", "Oops!", "Well played!", "Good game!"]

    /// After a message there is a short pause before the next one.
    var canChat: Bool { Date.now >= chatReadyAt }

    func send(_ message: ChatMessage) {
        guard canChat else { return }
        chatReadyAt = .now.addingTimeInterval(3)
        show(ChatBubble(fromYou: true, message: message))
        buzz(.selection)
        guard !muted else { return }
        after(1.4) { model in
            guard !model.muted else { return }
            let reply: ChatMessage = Bool.random() ? .phrase(Self.chatPhrases.randomElement()!) : .emote(Emote.allCases.randomElement()!)
            model.show(ChatBubble(fromYou: false, message: reply))
        }
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

    private func countdown(_ seconds: Int, then action: @escaping (MatchModel) -> Void) {
        timer?.cancel()
        let seconds = seconds * MatchRules.timerScale
        phaseLength = seconds
        secondsLeft = seconds
        timer = Task { [weak self] in
            for _ in 0..<seconds {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.secondsLeft -= 1
            }
            guard let self, !Task.isCancelled else { return }
            action(self)
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

/// A player's thief and police ratings; the combined rating (the main rank) is their average.
struct Ratings: Equatable {
    var thief: Int
    var police: Int

    var combined: Int { (thief + police) / 2 }

    subscript(role: Role) -> Int {
        get { role == .thief ? thief : police }
        set { if role == .thief { thief = newValue } else { police = newValue } }
    }
}

/// The bot in the sample match, clearly marked as one.
struct Opponent {
    let name: String
    let ratings: Ratings

    static let sample = Opponent(name: "Kestrel", ratings: Ratings(thief: 1471, police: 1433))
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

/// Everything needed to play a finished round back on the board, with nothing hidden.
struct RoundReplay {
    let thiefTrail: [Hex]
    let policeTrail: [Hex]
    let robbed: Sighting?
    let end: RoundEnd
    private let props: [Hex: String]

    init(_ round: SampleRound) {
        thiefTrail = round.thiefTrail
        policeTrail = round.policeTrail
        robbed = round.alarm
        end = round.end ?? .time
        var props: [Hex: String] = [:]
        for tile in round.rocks { props[tile] = "art-barrel" }
        for tile in Harbor.bushes { props[tile] = "art-net" }
        props[Harbor.caves.0] = "art-cave"
        props[Harbor.caves.1] = "art-cave"
        for tile in round.exits { props[tile] = "art-exit" }
        for tile in round.chests { props[tile] = round.reinforced.contains(tile) ? "art-reinforced" : "art-chest" }
        for tile in round.cameras { props[tile] = "art-camera" }
        for tile in round.dummyCameras { props[tile] = "art-dummycam" }
        for tile in round.plantedBushes { props[tile] = "art-sapling" }
        for tile in round.lookouts { props[tile] = "art-lookout" }
        self.props = props
    }

    var steps: Int { max(thiefTrail.count, policeTrail.count) }

    /// The board after `step` turns (0 is the start).
    func scene(at step: Int) -> BoardScene {
        var scene = BoardScene()
        scene.props = props
        if let robbed, step >= robbed.turn { scene.props[robbed.tile] = "art-chestopen" }
        let thief = thiefTrail[min(step, thiefTrail.count - 1)]
        let police = policeTrail[min(step, policeTrail.count - 1)]
        scene.pawns = [BoardPawn(role: .thief, tile: thief), BoardPawn(role: .police, tile: police)]
        if step >= steps - 1 {
            switch end {
            case .caught(let tile):
                scene.glow = TileGlow(tile: tile, color: Color(hex: 0xFF6B6B), fill: Color(hex: 0xFF5F7E, opacity: 0.3))
            case .escaped(let tile):
                scene.glow = TileGlow(tile: tile, color: Color(hex: 0x5BD07A), fill: Color(hex: 0x5BD07A, opacity: 0.3))
            case .time:
                break
            }
        }
        return scene
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
}

struct ChatBubble: Identifiable, Equatable {
    let id = UUID()
    let fromYou: Bool
    let message: ChatMessage
}
