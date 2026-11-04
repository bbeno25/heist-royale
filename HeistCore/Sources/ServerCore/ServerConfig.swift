import HeistCore

/// Every timer and tuning number the server uses. Starting values from the Master Plan; live config
/// will replace these later (task 2.9).
public struct ServerConfig: Sendable {
    // Match phases. The app shows a screen in each pause: the coin flip before round 1, the role reveal
    // before each briefing, and the round result and series score between rounds.
    public var readyCheck: Duration = .seconds(10)
    public var coinFlip: Duration = .seconds(5)
    public var roleReveal: Duration = .seconds(3)
    public var briefing: Duration = .seconds(5)
    public var prep: Duration = .seconds(40)
    public var intel: Duration = .seconds(5)
    public var turn: Duration = .seconds(15)
    public var roundResult: Duration = .seconds(8)
    public var seriesBreak: Duration = .seconds(6)
    /// How long a dropped player has to come back before forfeiting; a bot plays for them meanwhile.
    public var disconnectGrace: Duration = .seconds(60)
    /// Chase timeouts in a row before a bot plays the rest of the round for that player.
    public var timeoutsBeforeTakeover = 2

    // Matchmaking
    /// A player still alone in the queue after this long gets a bot.
    public var botFill: Duration = .seconds(10)
    public var queueStatusEvery: Duration = .seconds(2)
    public var matchmakingTick: Duration = .milliseconds(250)
    /// Two players match when their overall ratings are this close, plus the growth for each second waited.
    public var ratingWindow = 300.0
    public var ratingWindowPerSecond = 100.0

    // Bots: think times in seconds, so they don't answer instantly.
    public var botPrepThink: ClosedRange<Double> = 4...12
    public var botTurnThink: ClosedRange<Double> = 1.5...5

    public var round = RoundRules.standard
    public var map = MapRules.standard
    public var elo = EloRules()
    public var botNames = ["Mira", "Jonas", "Kenji", "Lola", "Arda", "Sofia", "Theo", "Nadia", "Rafa", "Elif", "Oskar", "Yuki"]

    public init() {}

    public static let standard = ServerConfig()

    /// The same rules with every timer multiplied by `factor`, for tests.
    public func scaled(_ factor: Double) -> ServerConfig {
        var config = self
        for path in [\ServerConfig.readyCheck, \.coinFlip, \.roleReveal, \.briefing, \.prep, \.intel, \.turn, \.roundResult, \.seriesBreak, \.disconnectGrace,
                     \.botFill, \.queueStatusEvery, \.matchmakingTick] {
            config[keyPath: path] = self[keyPath: path] * factor
        }
        config.botPrepThink = botPrepThink.lowerBound * factor...botPrepThink.upperBound * factor
        config.botTurnThink = botTurnThink.lowerBound * factor...botTurnThink.upperBound * factor
        config.ratingWindowPerSecond = ratingWindowPerSecond / factor
        return config
    }
}

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
