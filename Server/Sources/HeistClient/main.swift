// A command-line player for end-to-end tests: signs in, joins the queue and plays a whole match against
// whoever it meets, deciding with the HeistCore bot from the views the server sends.
//
//   swift run heist-client [--url ws://localhost:8080/ws] [--name Tester] [--token TOKEN] [--seed N] [--quiet]
//
// Exits with 1 if the server refused an action or sent a view with something the role mustn't know.

import Foundation
import HeistCore
import ServerCore

func option(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

setvbuf(stdout, nil, _IOLBF, 0)  // a line at a time, also when piped
let url = URL(string: option("--url") ?? "ws://localhost:8080/ws")!
let name = option("--name") ?? "Tester"
let quiet = CommandLine.arguments.contains("--quiet")
let seed = option("--seed").flatMap(UInt64.init) ?? UInt64.random(in: 1...UInt64.max)

func say(_ line: String) {
    if !quiet { print("[\(name)] \(line)") }
}

func rating(_ r: Rating) -> String { String(Int(r.value.rounded())) }

let socket = URLSession(configuration: .default).webSocketTask(with: url)
socket.resume()

func send(_ message: ClientMessage) async throws {
    let data = try JSONEncoder().encode(ClientEnvelope(message))
    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
}

var player = AutoPlayer(seed: seed)
var youAre = Seat.a
try await send(.hello(.init(token: option("--token"), name: name)))

while player.result == nil {
    guard case .string(let text) = try await socket.receive() else { continue }
    let message = try JSONDecoder().decode(ServerEnvelope.self, from: Data(text.utf8)).message
    switch message {
    case .welcome(let welcome):
        say("Signed in as \(welcome.player.name) (\(welcome.player.id)), overall \(rating(welcome.player.ratings.overall)); token \(welcome.token)")
        if welcome.matchId == nil { try await send(.queueJoin(.init())) }
    case .queueStatus(let status):
        say("In the queue for \(status.waitedSeconds) s (a bot after \(status.botAfterSeconds) s)")
    case .matchFound(let found):
        say("Match found: \(found.opponent.name)\(found.opponent.isBot ? " (bot)" : ""), overall \(rating(found.opponent.ratings.overall))")
    case .seriesStart(let start):
        youAre = start.youAre
        say("Seat \(start.youAre.rawValue.uppercased()): thief in rounds \(start.thiefSchedule.indices.filter { start.thiefSchedule[$0] == start.youAre }.map { $0 + 1 })")
    case .roundBriefing(let briefing):
        say("Round \(briefing.round): you are the \(briefing.role.rawValue); score \(briefing.score.a)-\(briefing.score.b)")
    case .prepDeal(let deal):
        say("  Dealt \(deal.hand.map(\.name).joined(separator: ", ")), \(deal.points) points")
    case .prepResult(let result):
        for note in result.intel { say("  Intel: \(note.text)") }
    case .turnResult(let result):
        for note in result.notes { say("  Turn \(result.turn): \(note.text)") }
    case .infoResult(let info):
        say("  \(info.note.text)")
    case .roundEnd(let end):
        say("Round \(end.round): \(end.result.winner.rawValue) wins by \(end.result.reason.rawValue) on turn \(end.result.turns); you \(end.youWon ? "won" : "lost"); score \(end.score.a)-\(end.score.b)")
    case .seriesEnd(let end):
        let verdict = end.draw ? "a draw" : end.youWon ? "you won" : "you lost"
        print("[\(name)] Match over: \(verdict), \(end.score[youAre])-\(end.score[youAre.other])\(end.forfeitBy.map { " (seat \($0.rawValue.uppercased()) forfeited)" } ?? "")")
        print("[\(name)] Overall \(rating(end.ratingsBefore.overall)) → \(rating(end.ratingsAfter.overall)), thief \(rating(end.ratingsBefore.thief)) → \(rating(end.ratingsAfter.thief)), police \(rating(end.ratingsBefore.police)) → \(rating(end.ratingsAfter.police))")
    case .matchCancelled(let cancelled):
        say("Match cancelled (\(cancelled.reason)); back in the queue: \(cancelled.requeued)")
    case .error(let error):
        print("[\(name)] Server refused: \(error.code): \(error.message)")
    default:
        break
    }
    for reply in player.respond(to: message) {
        try await send(reply)
    }
}

socket.cancel(with: .normalClosure, reason: nil)
if !player.leaks.isEmpty { print("[\(name)] LEAKS: \(player.leaks)") }
exit(player.errors.isEmpty && player.leaks.isEmpty ? 0 : 1)
