/// The queue. Two waiting players match when their overall ratings are close enough; the window widens
/// every second, so with few players online anyone pairs up within a few seconds. A player still alone
/// after `botFill` gets a bot.
struct Matchmaker {
    struct Waiting {
        let id: String
        let rating: Double
        let since: ContinuousClock.Instant
        var lastStatus: ContinuousClock.Instant
    }

    enum Pairing: Equatable {
        case players(String, String)
        case bot(String)
    }

    var window: Double
    var windowPerSecond: Double
    var botFill: Duration
    private(set) var waiting: [Waiting] = []

    init(window: Double, windowPerSecond: Double, botFill: Duration) {
        self.window = window
        self.windowPerSecond = windowPerSecond
        self.botFill = botFill
    }

    func contains(_ id: String) -> Bool {
        waiting.contains { $0.id == id }
    }

    mutating func join(_ id: String, rating: Double, at now: ContinuousClock.Instant) {
        guard !contains(id) else { return }
        waiting.append(Waiting(id: id, rating: rating, since: now, lastStatus: now))
    }

    mutating func leave(_ id: String) {
        waiting.removeAll { $0.id == id }
    }

    /// Players due a `queue.status`, with how long each has waited; marks them as told.
    mutating func statusDue(at now: ContinuousClock.Instant, every interval: Duration) -> [(id: String, waited: Duration)] {
        var due: [(String, Duration)] = []
        for index in waiting.indices where now - waiting[index].lastStatus >= interval {
            waiting[index].lastStatus = now
            due.append((waiting[index].id, now - waiting[index].since))
        }
        return due
    }

    /// Takes every pairing that can be made now out of the queue, longest-waiting players first.
    mutating func pairings(at now: ContinuousClock.Instant) -> [Pairing] {
        var out: [Pairing] = []
        var taken: Set<String> = []
        func reach(_ w: Waiting) -> Double { window + windowPerSecond * (now - w.since).seconds }
        for player in waiting where !taken.contains(player.id) {
            let partner = waiting
                .filter { $0.id != player.id && !taken.contains($0.id) }
                .filter { abs($0.rating - player.rating) <= min(reach(player), reach($0)) }
                .min { abs($0.rating - player.rating) < abs($1.rating - player.rating) }
            if let partner {
                taken.formUnion([player.id, partner.id])
                out.append(.players(player.id, partner.id))
            } else if now - player.since >= botFill {
                taken.insert(player.id)
                out.append(.bot(player.id))
            }
        }
        waiting.removeAll { taken.contains($0.id) }
        return out
    }
}
