/// The queue. Players meet first come, first served, whatever their ratings (decided 4 Nov 2026): the two
/// who have waited longest play each other. A player still alone after `botFill` gets a bot (the server
/// picks the free bot rated closest to them).
struct Matchmaker {
    struct Waiting {
        let id: String
        let since: ContinuousClock.Instant
        var lastStatus: ContinuousClock.Instant
    }

    enum Pairing: Equatable {
        case players(String, String)
        case bot(String)
    }

    var botFill: Duration
    /// In the order they joined.
    private(set) var waiting: [Waiting] = []

    init(botFill: Duration) {
        self.botFill = botFill
    }

    func contains(_ id: String) -> Bool {
        waiting.contains { $0.id == id }
    }

    mutating func join(_ id: String, at now: ContinuousClock.Instant) {
        guard !contains(id) else { return }
        waiting.append(Waiting(id: id, since: now, lastStatus: now))
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

    /// Takes every pairing that can be made now out of the queue: players two by two in the order they
    /// joined, then a bot for the one left over once they have waited `botFill`.
    mutating func pairings(at now: ContinuousClock.Instant) -> [Pairing] {
        var out: [Pairing] = []
        while waiting.count >= 2 {
            let first = waiting.removeFirst(), second = waiting.removeFirst()
            out.append(.players(first.id, second.id))
        }
        if let lone = waiting.first, now - lone.since >= botFill {
            waiting.removeFirst()
            out.append(.bot(lone.id))
        }
        return out
    }
}
