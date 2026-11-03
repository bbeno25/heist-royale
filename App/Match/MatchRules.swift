import HeistCore
import SwiftUI

/// Timers and limits for a round, from the Master Plan's 2.0 starting values ("Game logic" tab).
enum MatchRules {
    static let briefingSeconds = 5
    static let prepSeconds = 40
    static let intelSeconds = 5
    static let chaseTurnSeconds = 15
    static let resultSeconds = 8
    static let coinFlipSeconds = 5
    static let roleRevealSeconds = 3
    static let seriesSeconds = 6
    static var chaseTurns: Int { debugNumber("matchTurns") ?? 14 }
    static let prepPoints = 3
    /// Your own tile plus the tiles this many steps around it.
    /// The plan and the prototype use 1; the chase mockup says "Sight 2".
    static let sight = 1
    /// Classic: best of 8, first to 5 round wins; 4–4 is a draw. Debug builds can shorten it with `-matchRounds 2`.
    static var rounds: Int { debugNumber("matchRounds") ?? 8 }
    static var winsNeeded: Int { rounds / 2 + 1 }

    /// Your role in a round when you are Player 1 (the coin-flip winner, thief first): 3 thief, 3 police, then one each.
    /// (Shortened debug series just alternate.)
    static func player1Role(inRound round: Int) -> Role {
        guard rounds == 8 else { return round % 2 == 1 ? .thief : .police }
        return [1, 2, 3, 7].contains(round) ? .thief : .police
    }

    /// Multiplies every countdown; debug builds can stretch them with `-matchTimerScale 4` for testing.
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

enum Role: Hashable {
    case thief, police

    var other: Role { self == .thief ? .police : .thief }
    var title: String { self == .thief ? "Thief" : "Police" }
    /// The role's main colour on the board and in the HUD.
    var color: Color { self == .thief ? Color(hex: 0xFFB547) : Color(hex: 0x5AA2FF) }
    /// Diamond for the thief, shield for the police (24-unit view box).
    var emblem: String {
        self == .thief ? "M12 1.5L22.5 12 12 22.5 1.5 12z" : "M12 1.5L21 5v6.5c0 5.5-4 9.2-9 11-5-1.8-9-5.5-9-11V5z"
    }
}

/// The cards the sample round deals, as data: cost, what they target and what they do.
/// Wording follows the Master Plan's "Cards" tab and the card mockups.
enum CardID: String, CaseIterable, Identifiable {
    // Police prep (security)
    case camera, motionDetector, dummyCamera, reinforcedChest
    // Thief prep (intel and terrain)
    case plantBush, lookout, smokeCache, blueprintScan, insideMan, cutWires
    // Chase
    case run, compass, smoke, radar, lockdown

    var id: Self { self }

    enum Target: Equatable {
        /// A tile with nothing on it: no rock, cave, start, chest or exit.
        case freeTile
        /// One of the chests.
        case chest
        /// Any tile; the card covers everything within this many steps.
        case area(Int)
        /// Played without a target.
        case none
    }

    var name: String {
        switch self {
        case .camera: "Camera"
        case .motionDetector: "Motion detector"
        case .dummyCamera: "Dummy camera"
        case .reinforcedChest: "Reinforced chest"
        case .plantBush: "Plant bush"
        case .lookout: "Lookout"
        case .smokeCache: "Smoke cache"
        case .blueprintScan: "Blueprint scan"
        case .insideMan: "Inside man"
        case .cutWires: "Cut wires"
        case .run: "Run"
        case .compass: "Compass"
        case .smoke: "Smoke"
        case .radar: "Radar"
        case .lockdown: "Lockdown"
        }
    }

    /// Whose card it is; Run belongs to both pools.
    var role: Role? {
        switch self {
        case .camera, .motionDetector, .dummyCamera, .reinforcedChest, .radar, .lockdown: .police
        case .plantBush, .lookout, .smokeCache, .blueprintScan, .insideMan, .cutWires, .compass, .smoke: .thief
        case .run: nil
        }
    }

    var isChase: Bool {
        switch self {
        case .run, .compass, .smoke, .radar, .lockdown: true
        default: false
        }
    }

    /// Prep points; chase cards are free.
    var cost: Int {
        switch self {
        case .motionDetector, .dummyCamera, .plantBush, .lookout, .smokeCache: 1
        case .camera, .reinforcedChest, .blueprintScan, .insideMan, .cutWires: 2
        default: 0
        }
    }

    var category: String {
        switch self {
        case .camera, .motionDetector, .dummyCamera, .reinforcedChest: "SECURITY"
        case .plantBush, .smokeCache: "TERRAIN"
        case .lookout, .blueprintScan, .insideMan, .cutWires: "INTEL"
        case .compass, .radar: "INSTANT"
        case .run, .smoke, .lockdown: "PLAYS WITH MOVE"
        }
    }

    var target: Target {
        switch self {
        case .camera, .motionDetector, .dummyCamera, .plantBush, .lookout, .smokeCache: .freeTile
        case .reinforcedChest: .chest
        case .blueprintScan: .area(2)
        default: .none
        }
    }

    /// Chase cards that answer at once while planning, so the move can still change.
    var isInstant: Bool { self == .compass || self == .radar }

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

    static let policeChasePool: [CardID] = [.run, .radar, .lockdown]
    static let thiefChasePool: [CardID] = [.run, .compass, .smoke]
}

/// The Pirate Harbor map from the match mockups, and the tile names players see.
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

    static func hex(_ name: String) -> Hex {
        let q = Int(name.unicodeScalars.first!.value) - 65 - board.radius
        let top = max(-board.radius, -board.radius - q)
        return Hex(q: q, r: top + Int(name.dropFirst())! - 1)
    }

    static func hexes(_ names: String...) -> Set<Hex> { Set(names.map(hex)) }

    // The mockups' sample map: barrels are rocks, fishing nets are bushes, sea caves are a tunnel pair.
    static let exits = hexes("A3", "E1", "I4")
    static let chests = hexes("C4", "F3", "G6")
    static let rocks = hexes("B2", "D2", "E6", "G3", "F7", "H4")
    static let bushes = hexes("B5", "D6", "E3", "G5", "H2", "C2")
    static let caves = (hex("A5"), hex("I1"))
    static let thiefStart = hex("C7")
    static let policeStart = hex("G1")
    static let firstBox = hex("C6")

    /// One of the six directions in words, as seen on the tilted board (north is away from you).
    static func direction(from a: Hex, to b: Hex) -> String {
        let dq = Double(b.q - a.q), dr = Double(b.r - a.r)
        let x = 1.5 * dq
        let z = 3.0.squareRoot() * (dr + dq / 2)
        let degrees = atan2(-z, x) * 180 / .pi
        let names: [(Double, String)] = [(90, "north"), (30, "north-east"), (-30, "south-east"), (-90, "south"), (-150, "south-west"), (150, "north-west")]
        return names.min { angleGap($0.0, degrees) < angleGap($1.0, degrees) }!.1
    }

    private static func angleGap(_ a: Double, _ b: Double) -> Double {
        let gap = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(gap, 360 - gap)
    }
}
