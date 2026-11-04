import Foundation
import HeistCore

/// Something the player is told during the chase.
struct MatchNote: Identifiable, Equatable {
    enum Tone { case info, good, alert }

    let id = UUID()
    let text: String
    let tone: Tone
    var tile: Hex?
}

/// One line of the intel reveal.
struct IntelLine: Identifiable, Equatable {
    let id = UUID()
    let card: CardID?
    let text: String
}

/// How a round ended, from the board's point of view.
enum RoundEnd: Equatable {
    case caught(Hex), escaped(Hex), time

    init(_ result: RoundResult) {
        switch result.reason {
        case .caught: self = .caught(result.tile ?? .origin)
        case .escaped: self = .escaped(result.tile ?? .origin)
        case .time: self = .time
        }
    }

    var winner: Role {
        if case .escaped = self { return .thief }
        return .police
    }
}

extension Note {
    /// The note in the app's words. The server's own text uses the prototype's tile names; the app names
    /// tiles the way they read on this board, and fills in scan results from what the view now knows.
    func appText(for role: Role, view: PlayerView?) -> String {
        let here = tile.map(Harbor.name) ?? ""
        switch kind {
        case .scan:
            guard let center = tile else { return text }
            var found: [String] = []
            for chest in view?.chests ?? [] where chest.tile.distance(to: center) <= 2 {
                found.append((chest.reinforced ? "reinforced chest on " : "chest on ") + Harbor.name(chest.tile))
            }
            for item in view?.security ?? [] where item.tile.distance(to: center) <= 2 {
                found.append((item.kind == .motionDetector ? "motion detector on " : "camera on ") + Harbor.name(item.tile))
            }
            return found.isEmpty ? "Nothing within 2 of \(here)." : "Found " + found.joined(separator: ", ") + "."
        case .insideMan: return "A real chest is on \(here)."
        case .cutWires: return "Cameras stay off until turn \((number ?? 4) + 1)."
        case .security:
            switch card {
            case .camera: return "Watching \(here) and the 6 tiles around it."
            case .motionDetector: return "Hidden on \(here)."
            case .dummyCamera: return "Decoy camera on \(here)."
            case .reinforcedChest: return "The chest on \(here) takes 2 turns to crack."
            default: return text
            }
        case .noIntel:
            return role == .police ? "You placed no security this round." : "No intel this round: you know the exits, but the chests are hidden."
        case .smoke: return "Smoke! You're invisible this turn and next."
        case .lockdown: return "Lockdown: every exit is sealed for 3 turns."
        case .lockdownBlocked: return "The exits are sealed by Lockdown!"
        case .tunnel: return "Through the sea cave to \(here)."
        case .box: return "Mystery box: you got \(card?.name ?? "a card")."
        case .detectorPing: return "Motion detector on \(here) pinged!"
        case .smokeCache: return "You picked up your hidden Smoke card."
        case .robbed: return "You cracked the chest on \(here)! Now reach an exit."
        case .alarm: return "Alarm! The chest on \(here) was robbed."
        case .reinforced: return "Reinforced chest! Stay a turn to crack it."
        case .cameraSpotted: return "Your camera spotted the thief on \(here)."
        case .lookoutSpotted: return "Your lookout spotted the police on \(here)."
        case .radar: return "Radar: the thief is on \(here)."
        case .radarJammed: return "Radar jammed: the thief is in smoke."
        case .compass:
            guard let steps = number, let direction else { return "Compass: no chests left." }
            return "Compass: the nearest chest is \(steps) \(steps == 1 ? "tile" : "tiles") \(Harbor.direction(of: direction))."
        }
    }

    var matchTone: MatchNote.Tone {
        switch tone {
        case .info: .info
        case .good: .good
        case .alert: .alert
        }
    }
}
