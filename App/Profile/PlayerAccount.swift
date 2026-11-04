import Foundation
import HeistCore

/// The player's online account as this phone last saw it: name, the three ratings and the match record.
/// The server holds the real values; the phone keeps a copy (one per server, like the guest token) so
/// home shows the real ratings at launch and offline, and refreshes it at every sign-in. The offline
/// match's in-app server keeps nothing, so it never changes this.
@MainActor
@Observable
final class PlayerAccount {
    struct Saved: Codable, Equatable {
        var id: String
        var name: String
        var ratings: HeistCore.Ratings
        var stats: PlayerStats
        var country: String?
        var updated: Date
    }

    private(set) var saved: Saved?
    private let defaults: UserDefaults
    private var refreshing: GameConnection?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let host = Self.host, let data = defaults.data(forKey: Self.key(host)) {
            saved = try? JSONDecoder().decode(Saved.self, from: data)
        }
    }

    /// The online server's host, or nil when matches run on the offline in-app server.
    static var host: String? {
        if case .remote(let url) = GameServerAddress.target { return url.host() }
        return nil
    }

    /// The phone's region (such as "TR"), for the country leaderboards.
    static var region: String? { cleanRegion(Locale.current.region?.identifier) }

    private static func key(_ host: String) -> String { "account.\(host)" }

    /// What home and the match screens show: the real name and ratings, with sample level, coins and
    /// season until the economy exists.
    var summary: PlayerSummary {
        var summary = PlayerSummary.sample
        let ratings = saved?.ratings ?? .starting(at: 1000)
        let typed = defaults.string(forKey: "playerName") ?? ""
        summary.name = saved?.name ?? (typed.isEmpty ? "Guest" : typed)
        summary.rating = Int(ratings.overall.value.rounded())
        summary.thief = RankLadder.rank(for: Int(ratings.thief.value.rounded()), role: .thief)
        summary.police = RankLadder.rank(for: Int(ratings.police.value.rounded()), role: .police)
        return summary
    }

    var ratings: HeistCore.Ratings { saved?.ratings ?? .starting(at: 1000) }

    /// Saves what the server sent at sign-in.
    func update(from welcome: ServerMessage.Welcome) {
        let previous = saved?.id == welcome.player.id ? saved : nil
        store(Saved(id: welcome.player.id, name: welcome.player.name, ratings: welcome.player.ratings,
                    stats: welcome.stats ?? previous?.stats ?? PlayerStats(), country: welcome.country ?? previous?.country, updated: .now))
    }

    /// Saves the ratings a finished match left; the match record arrives with the next refresh.
    func update(ratings: HeistCore.Ratings) {
        guard var next = saved else { return }
        next.ratings = ratings
        next.updated = .now
        store(next)
    }

    private func store(_ next: Saved) {
        guard let host = Self.host, next != saved else { return }
        saved = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.key(host)) }
    }

    /// Signs in quietly to fetch the latest ratings and record. Needs an account already (a token from an
    /// earlier match), so just opening the app doesn't create one. Never call it while a match is open:
    /// the server keeps one connection per player and would drop the match's.
    func refresh() {
        guard refreshing == nil, case .remote(let url) = GameServerAddress.target,
              let token = GuestToken.load(for: url.host() ?? "") else { return }
        let connection = GameConnection(target: .remote(url))
        refreshing = connection
        connection.onEvent = { [weak self, weak connection] event in
            if case .message(let envelope) = event {
                guard case .welcome(let welcome) = envelope.message else { return }
                self?.update(from: welcome)
            }
            connection?.close()
            self?.refreshing = nil
        }
        // An empty name keeps the one the server has.
        connection.open(ClientMessage.Hello(token: token, name: "", region: Self.region))
        Task { [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(10))
            guard let connection, self?.refreshing === connection else { return }
            connection.close()
            self?.refreshing = nil
        }
    }
}
