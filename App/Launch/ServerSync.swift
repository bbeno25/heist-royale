import Foundation

/// The once-a-day sync with the game server at launch (zones, skins, rules version and so on).
protocol ServerSyncing: Sendable {
    /// Runs the sync, reporting progress from 0 to 1.
    func sync(progress: @escaping @MainActor @Sendable (Double) -> Void) async throws
}

/// There is no server yet (it arrives in phase 3), so this only waits, standing in for the network work.
struct ServerSync: ServerSyncing {
    var duration: Duration = .seconds(3)

    func sync(progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        let steps = 30
        for step in 1...steps {
            try await Task.sleep(for: duration / steps)
            await progress(Double(step) / Double(steps))
        }
    }
}

/// Remembers the local calendar day of the last successful sync, so the sync runs on the first
/// open of each day.
struct DailySyncRecord {
    private let defaults: UserDefaults
    private let key = "lastServerSyncDay"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func needsSync(now: Date = .now, calendar: Calendar = .current) -> Bool {
        defaults.string(forKey: key) != Self.day(of: now, in: calendar)
    }

    func markSynced(now: Date = .now, calendar: Calendar = .current) {
        defaults.set(Self.day(of: now, in: calendar), forKey: key)
    }

    private static func day(of date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
