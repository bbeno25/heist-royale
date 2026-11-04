import HeistCore

/// Plays a match from the app's side of the protocol, deciding with the HeistCore bot from the views the
/// server sends. Used by the tests and the command-line client to drive full matches end to end.
public struct AutoPlayer: Sendable {
    private var random: SeededRandom
    private var bot: Bot
    private var hand: [CardID] = []
    private var points = 0
    public private(set) var role: Role?
    public private(set) var view: PlayerView?
    public private(set) var result: ServerMessage.SeriesEnd?
    public private(set) var rounds: [ServerMessage.RoundEnd] = []
    public private(set) var errors: [ServerMessage.ServerError] = []
    /// Views that showed something this role must not know (should stay empty).
    public private(set) var leaks: [String] = []

    public init(seed: UInt64) {
        random = SeededRandom(seed: seed)
        bot = Bot(seed: seed)
    }

    /// The messages to send back after `message`.
    public mutating func respond(to message: ServerMessage) -> [ClientMessage] {
        switch message {
        case .matchFound:
            return [.matchReady]
        case .roundBriefing(let briefing):
            bot = Bot(seed: random.next())
            role = briefing.role
            see(briefing.view)
        case .prepDeal(let deal):
            hand = deal.hand
            points = deal.points
            return prep()
        case .prepResult(let result):
            see(result.view)
        case .turnStart(let start):
            see(start.view)
            return chase()
        case .infoResult(let info):
            see(info.view)
            return [.turnSubmit(.init(turn: info.view.turn, plan: bot.move(view: info.view)))]
        case .turnResult(let result):
            see(result.view)
        case .roundEnd(let end):
            rounds.append(end)
        case .seriesEnd(let end):
            result = end
        case .matchState(let state):
            role = state.role
            if let view = state.view { see(view) }
            if let hand = state.hand { self.hand = hand }
            guard !state.locked else { return [] }
            if state.phase == "prep", state.hand != nil { return prep() }
            if state.phase == "chase" { return chase() }
        case .error(let error):
            errors.append(error)
        default:
            break
        }
        return []
    }

    private mutating func prep() -> [ClientMessage] {
        guard let view else { return [.prepSubmit(.init(plays: []))] }
        return [.prepSubmit(.init(plays: bot.prep(view: view, hand: hand, points: points)))]
    }

    private mutating func chase() -> [ClientMessage] {
        guard let view, view.stage == .chase else { return [] }
        if let card = bot.instant(view: view) {
            return [.infoUse(.init(card: card))]
        }
        return [.turnSubmit(.init(turn: view.turn, plan: bot.move(view: view)))]
    }

    private mutating func see(_ view: PlayerView) {
        self.view = view
        if let role, view.role != role { leaks.append("view for \(view.role) sent to \(role)") }
        guard view.stage != .over else { return }
        switch view.role {
        case .thief:
            if view.alarm != nil { leaks.append("thief saw the alarm") }
            if view.security.contains(where: { $0.kind == .dummyCamera }) { leaks.append("thief told a camera is a dummy") }
        case .police:
            if !view.lookouts.isEmpty || !view.smokeCaches.isEmpty { leaks.append("police saw thief builds") }
            if view.cracking != nil || view.smokeThrough != 0 || view.camerasOffThrough != 0 { leaks.append("police saw thief state") }
            if view.opponentVisible, view.opponent?.turn != view.turn - 1, view.opponent?.turn != view.turn { leaks.append("stale sighting shown as visible") }
        }
    }
}
