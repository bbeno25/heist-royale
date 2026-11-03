/// What one player may know at a moment of the round: their role's column of the Master Plan's
/// "Who knows what" table. The server builds one per player and sends nothing else, so a modified app
/// has nothing hidden to reveal. Bots decide from the same view.
public struct PlayerView: Codable, Sendable, Equatable {
    public struct Chest: Codable, Sendable, Equatable {
        public var tile: Hex
        public var robbed: Bool
        public var reinforced: Bool
    }

    public struct Security: Codable, Sendable, Equatable {
        public var tile: Hex
        /// The thief sees a dummy camera as a camera.
        public var kind: Round.SecurityKind
    }

    public var role: Role
    public var stage: Round.Stage
    public var turn: Int
    public var turnLimit: Int
    public var radius: Int
    public var position: Hex
    public var thiefStart: Hex
    public var policeStart: Hex

    // Terrain: both sides know it from the briefing, plus the bushes each has seen planted.
    public var rocks: [Hex]
    public var bushes: [Hex]
    public var walls: [Wall]
    public var tunnels: [Tunnel]

    /// The thief knows every exit; the police only the ones it has seen.
    public var exits: [Hex]
    /// The police knows every chest; the thief only the ones it has scanned, been told of or seen.
    public var chests: [Chest]
    /// The police's own security, or what the thief has scanned or seen of it.
    public var security: [Security]
    /// The thief's own builds.
    public var lookouts: [Hex]
    public var smokeCaches: [Hex]
    /// Mystery boxes; both sides see them.
    public var boxes: [Hex]

    /// Tiles in sight now; `seen` is every tile seen this round.
    public var visible: [Hex]
    public var seen: [Hex]

    /// Where the opponent was last seen, and whether they are in sight now.
    public var opponent: Sighting?
    public var opponentVisible: Bool
    /// Police only: where and when a chest was robbed.
    public var alarm: Sighting?
    /// Thief: carrying the loot. Police: knows a chest was robbed.
    public var hasLoot: Bool
    /// Thief only: the reinforced chest being cracked.
    public var cracking: Hex?
    /// Thief only: hidden in smoke through this turn.
    public var smokeThrough: Int
    /// Exits are sealed through this turn (both sides are told).
    public var lockdownThrough: Int
    /// Thief only: cameras are off through this turn.
    public var camerasOffThrough: Int

    /// Chase cards in hand.
    public var cards: [CardID]
    /// An instant card was already played this turn (one card per turn).
    public var instantUsed: Bool

    public var terrain: Terrain {
        Terrain(radius: radius, rocks: rocks, walls: walls, tunnels: tunnels)
    }

    public var board: Board { Board(radius: radius) }
}
