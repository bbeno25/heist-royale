// Hex geometry: axial coordinates (q, r), pointy-top tiles, hexagon-shaped board.
// Ported from the HTML prototype (prototype/index.html, "HEX GEOMETRY").

/// A tile position in axial coordinates.
public struct Hex: Hashable, Sendable, Codable {
    public var q: Int
    public var r: Int

    public init(q: Int, r: Int) {
        self.q = q
        self.r = r
    }

    public static let origin = Hex(q: 0, r: 0)

    /// Steps from the centre of the board.
    public var length: Int { max(abs(q), abs(r), abs(q + r)) }

    /// Fewest steps between two tiles, ignoring terrain.
    public func distance(to other: Hex) -> Int { (self - other).length }

    public static func + (a: Hex, b: Hex) -> Hex { Hex(q: a.q + b.q, r: a.r + b.r) }
    public static func - (a: Hex, b: Hex) -> Hex { Hex(q: a.q - b.q, r: a.r - b.r) }
}

/// One step: waiting in place or moving to one of the six neighbouring tiles.
public enum Move: String, CaseIterable, Sendable, Codable {
    case wait
    case northWest, northEast, west, east, southWest, southEast

    /// The six real directions, without `wait`.
    public static let directions: [Move] = [.northWest, .northEast, .west, .east, .southWest, .southEast]

    public var offset: Hex {
        switch self {
        case .wait: Hex(q: 0, r: 0)
        case .northWest: Hex(q: 0, r: -1)
        case .northEast: Hex(q: 1, r: -1)
        case .west: Hex(q: -1, r: 0)
        case .east: Hex(q: 1, r: 0)
        case .southWest: Hex(q: -1, r: 1)
        case .southEast: Hex(q: 0, r: 1)
        }
    }
}

/// A hexagon-shaped board; radius 4 gives 61 tiles.
public struct Board: Hashable, Sendable, Codable {
    public let radius: Int

    public init(radius: Int) {
        self.radius = radius
    }

    /// Every tile, row by row from the top, left to right within each row.
    public var cells: [Hex] {
        var out: [Hex] = []
        for r in -radius...radius {
            for q in max(-radius, -r - radius)...min(radius, -r + radius) {
                out.append(Hex(q: q, r: r))
            }
        }
        return out
    }

    public func contains(_ p: Hex) -> Bool { p.length <= radius }

    public func isBorder(_ p: Hex) -> Bool { p.length == radius }

    public func neighbors(of p: Hex) -> [Hex] {
        Move.directions.map { p + $0.offset }.filter(contains)
    }

    /// The name players see: row letter (A at the top) plus position in the row, e.g. "E5".
    public func name(of p: Hex) -> String {
        let row = Character(UnicodeScalar(UInt8(65 + p.r + radius)))
        return "\(row)\(p.q - max(-radius, -p.r - radius) + 1)"
    }
}
