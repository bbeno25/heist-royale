import Foundation
import HeistCore

/// Loads the leaderboards from the game server over its own short-lived connection. With an account
/// (a saved guest token) it signs in first, so each page also brings the player's own place; without one
/// it only reads, so looking at the boards doesn't create an account.
@MainActor
@Observable
final class LeaderboardModel {
    struct Key: Hashable {
        var board: LeaderboardBoard
        var scope: LeaderboardScope
    }

    var board: LeaderboardBoard = .overall {
        didSet { if board != oldValue { load() } }
    }
    var scope: LeaderboardScope = .global {
        didSet { if scope != oldValue { load() } }
    }

    private(set) var pages: [Key: ServerMessage.Leaderboard] = [:]
    private(set) var loading: Set<Key> = []
    /// Why the current page couldn't load.
    private(set) var problem: String?
    /// The phone's region, for the country boards; nil hides them.
    let region = PlayerAccount.region

    private let account: PlayerAccount
    private var connection: GameConnection?
    private var waiting: [Key: [CheckedContinuation<Void, Never>]] = [:]

    init(account: PlayerAccount) {
        self.account = account
    }

    var key: Key { Key(board: board, scope: scope) }
    var page: ServerMessage.Leaderboard? { pages[key] }
    var isLoading: Bool { loading.contains(key) }

    /// Shows the current board, fetching it if it isn't here yet.
    func load() {
        problem = nil
        if pages[key] == nil { request(key) }
    }

    /// Pull to refresh: fetches the current board again and returns once it is in.
    func reload() async {
        let key = key
        problem = nil
        request(key)
        await withCheckedContinuation { waiting[key, default: []].append($0) }
    }

    func stop() {
        connection?.close()
        connection = nil
        finish(Array(loading))
    }

    private func request(_ key: Key) {
        if connection == nil { connect() }
        loading.insert(key)
        let country = key.scope == .country ? region : nil
        connection?.send(.leaderboardGet(.init(board: key.board, scope: key.scope, country: country)))
    }

    private func connect() {
        let target = GameServerAddress.target
        let connection = GameConnection(target: target)
        self.connection = connection
        connection.onEvent = { [weak self] event in self?.receive(event) }
        var hello: ClientMessage.Hello?
        if case .remote(let url) = target, let token = GuestToken.load(for: url.host() ?? "") {
            hello = ClientMessage.Hello(token: token, name: "", region: PlayerAccount.region)
        }
        connection.open(hello)
    }

    private func receive(_ event: GameConnection.Event) {
        switch event {
        case .message(let envelope):
            switch envelope.message {
            case .welcome(let welcome):
                account.update(from: welcome)
            case .leaderboard(let page):
                let key = Key(board: page.board, scope: page.scope)
                pages[key] = page
                finish([key])
            case .error(let error):
                problem = error.message
                finish(Array(loading))
            default:
                break
            }
        case .lost:
            connection?.close()
            connection = nil
            if !loading.isEmpty || pages[key] == nil { problem = "Can't reach the game server. Check your connection and try again." }
            finish(Array(loading))
        }
    }

    private func finish(_ keys: [Key]) {
        for key in keys {
            loading.remove(key)
            for continuation in waiting.removeValue(forKey: key) ?? [] { continuation.resume() }
        }
    }
}
