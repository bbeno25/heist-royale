import HeistCore
import SwiftUI

/// Numbers the match screens show. The server runs the real timers and sends deadlines; these match its
/// starting values (Master Plan, "Game logic" tab) for texts and the offline match.
enum MatchRules {
    static let briefingSeconds = 5
    static let prepSeconds = 40
    static let intelSeconds = 5
    static let chaseTurnSeconds = 15
    static let resultSeconds = 8
    static let coinFlipSeconds = 5
    static let roleRevealSeconds = 3
    static let seriesSeconds = 6
    static let chaseTurns = RoundRules.standard.chaseTurns
    static let prepPoints = RoundRules.standard.prepPoints
    /// Your own tile plus the tiles this many steps around it.
    static let sight = RoundRules.standard.sight
    /// Tournament: at most 8 rounds; the first to 4 wins in rounds 1 to 6 takes the match, and at 3–3
    /// two extension rounds decide it (win both, or it's a draw).
    static let rounds = Tournament.thiefSchedule.count
    static let regularRounds = Tournament.regularRounds
    static let winsNeeded = Tournament.winTarget

    /// Your role in a round when you are Player 1 (seat A, the coin-flip winner, thief first):
    /// thief in rounds 1 to 3 and 7, police in 4 to 6 and 8.
    static func player1Role(inRound round: Int) -> Role {
        Tournament.role(of: .a, inRound: min(max(round, 1), rounds))
    }

    /// Multiplies every timer of the offline match; debug builds can stretch them with `-matchTimerScale 4`.
    static var timerScale: Int { debugNumber("matchTimerScale") ?? 1 }

    private static func debugNumber(_ key: String) -> Int? {
        #if DEBUG
        let value = UserDefaults.standard.integer(forKey: key)
        return value > 0 ? value : nil
        #else
        return nil
        #endif
    }
}

extension Role {
    var title: String { self == .thief ? "Thief" : "Police" }
    /// The role's main colour on the board and in the HUD.
    var color: Color { self == .thief ? Color(hex: 0xFFB547) : Color(hex: 0x5AA2FF) }
    /// Diamond for the thief, shield for the police (24-unit view box).
    var emblem: String {
        self == .thief ? "M12 1.5L22.5 12 12 22.5 1.5 12z" : "M12 1.5L21 5v6.5c0 5.5-4 9.2-9 11-5-1.8-9-5.5-9-11V5z"
    }
}

/// How the cards look and read in the app. The rules side (cost, target, who plays it) is HeistCore's.
extension CardID: @retroactive Identifiable {
    public var id: Self { self }

    /// Whose card it is; Run belongs to both.
    var role: Role? { roles.count == 1 ? roles[0] : nil }

    var isChase: Bool { phase == .chase }

    var category: String {
        switch self {
        case .camera, .motionDetector, .dummyCamera, .reinforcedChest: "SECURITY"
        case .plantBush, .smokeCache: "TERRAIN"
        case .lookout, .blueprintScan, .insideMan, .cutWires: "INTEL"
        case .compass, .radar: "INSTANT"
        case .run, .smoke, .lockdown: "PLAYS WITH MOVE"
        }
    }

    /// The design's full-art 3D render for the card face. Run has one per role.
    func render(for role: Role) -> String {
        switch self {
        case .run: role == .thief ? "card-run-thief" : "card-run-police"
        case .smokeCache: "card-smoke"
        default: "card-\(rawValue)"
        }
    }

    /// Illustration from the design's art set (flat icons for the board and the intel list).
    var art: String {
        switch self {
        case .camera: "art-camera"
        case .motionDetector: "art-detector"
        case .dummyCamera: "art-dummycam"
        case .reinforcedChest: "art-reinforced"
        case .plantBush: "art-sapling"
        case .lookout: "art-lookout"
        case .smokeCache, .smoke: "art-smokebomb"
        case .blueprintScan: "art-blueprint"
        case .insideMan: "art-insideman"
        case .cutWires: "art-cutwires"
        case .run: "art-run"
        case .compass: "art-compass"
        case .radar: "art-radar"
        case .lockdown: "art-lockdown"
        }
    }

    var effect: String {
        switch self {
        case .camera: "Watches its tile and the 6 around it all round. Reports the thief like sight."
        case .motionDetector: "Hidden on one tile. Pings you when the thief steps on it."
        case .dummyCamera: "Looks exactly like a camera to scans. Does nothing."
        case .reinforcedChest: "One chest takes 2 turns to crack: the thief must stay a turn."
        case .plantBush: "Add a bush on a free tile."
        case .lookout: "Place a lookout. It reports the police whenever it comes within 1 tile."
        case .smokeCache: "Hide a Smoke card on a tile. Step on it to collect."
        case .blueprintScan: "Reveal everything in a radius-2 area: chests, cameras and detectors."
        case .insideMan: "Learn the exact tile of one real chest."
        case .cutWires: "All cameras are off for the first 4 chase turns."
        case .run: "Take two steps this turn."
        case .compass: "Points toward the nearest chest and says how far away it is."
        case .smoke: "Invisible for 2 turns, even right next to the police. Jams Radar."
        case .radar: "Reveals the thief's exact location right now."
        case .lockdown: "Seal every exit for 3 turns: this one and the next two."
        }
    }
}

/// The Pirate Harbor look on a radius-4 board, and the tile names players see.
/// Tiles are flat-topped; a name is the column letter (A on the left) plus the place down the column
/// (E1 is the top of the middle column). HeistCore's axial `Hex` carries the positions.
enum Harbor {
    static let board = Board(radius: 4)
    static let tiles = board.cells

    static func name(_ hex: Hex) -> String {
        let top = max(-board.radius, -board.radius - hex.q)
        let column = Character(UnicodeScalar(UInt8(65 + hex.q + board.radius)))
        return "\(column)\(hex.r - top + 1)"
    }

    /// One of the six directions in words, as seen on the tilted board (north is away from you).
    static func direction(from a: Hex, to b: Hex) -> String {
        direction(dq: Double(b.q - a.q), dr: Double(b.r - a.r))
    }

    /// The same for a direction given in axial steps, which may be fractions.
    static func direction(dq: Double, dr: Double) -> String {
        let x = 1.5 * dq
        let z = 3.0.squareRoot() * (dr + dq / 2)
        let degrees = atan2(-z, x) * 180 / .pi
        let names: [(Double, String)] = [(90, "north"), (30, "north-east"), (-30, "south-east"), (-90, "south"), (-150, "south-west"), (150, "north-west")]
        return names.min { angleGap($0.0, degrees) < angleGap($1.0, degrees) }!.1
    }

    /// The Compass note's direction is in the prototype's pointy-top layout; turn it back into axial steps.
    static func direction(of vector: Note.Vector) -> String {
        let dr = vector.y / 1.5
        let dq = vector.x / 3.0.squareRoot() - dr / 2
        return direction(dq: dq, dr: dr)
    }

    private static func angleGap(_ a: Double, _ b: Double) -> Double {
        let gap = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(gap, 360 - gap)
    }
}
