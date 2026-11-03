// Walls, tunnels and the movement rules that follow from the terrain.

extension Hex: Comparable {
    /// Row by row from the top, left to right: the same order as `Board.cells`, used wherever a choice
    /// must not depend on how a `Set` happens to be laid out in memory.
    public static func < (a: Hex, b: Hex) -> Bool {
        a.r != b.r ? a.r < b.r : a.q < b.q
    }
}

/// A wall on the edge between two neighbouring tiles. The two tiles are stored in order, so the same
/// edge always compares equal.
public struct Wall: Hashable, Codable, Sendable {
    public let a: Hex
    public let b: Hex

    public init(_ x: Hex, _ y: Hex) {
        if x < y {
            a = x
            b = y
        } else {
            a = y
            b = x
        }
    }
}

/// Step into one end and come out of the other in the same step.
public struct Tunnel: Hashable, Codable, Sendable {
    public let a: Hex
    public let b: Hex

    public init(_ a: Hex, _ b: Hex) {
        self.a = a
        self.b = b
    }
}

/// The six directions around a tile, in turning order (used to lay walls along a tile's edges).
let ring: [Move] = [.east, .northEast, .northWest, .west, .southWest, .southEast]

/// What blocks movement: rocks, walls between tiles, and tunnels that carry you to their other end.
public struct Terrain: Sendable {
    public let board: Board
    public let rocks: Set<Hex>
    public let walls: Set<Wall>
    public let tunnelExit: [Hex: Hex]

    public init(radius: Int, rocks: some Sequence<Hex>, walls: some Sequence<Wall>, tunnels: some Sequence<Tunnel>) {
        board = Board(radius: radius)
        self.rocks = Set(rocks)
        self.walls = Set(walls)
        var exits: [Hex: Hex] = [:]
        for tunnel in tunnels {
            exits[tunnel.a] = tunnel.b
            exits[tunnel.b] = tunnel.a
        }
        tunnelExit = exits
    }

    public func isOpen(_ hex: Hex) -> Bool {
        board.contains(hex) && !rocks.contains(hex)
    }

    /// One step between neighbours: onto an open tile and not across a wall.
    public func canStep(from a: Hex, to b: Hex) -> Bool {
        a.distance(to: b) == 1 && isOpen(b) && !walls.contains(Wall(a, b))
    }

    /// Where a step into a tile ends up: a tunnel end carries you to the other end.
    public func landing(_ hex: Hex) -> Hex { tunnelExit[hex] ?? hex }

    /// Tiles that can be stepped into this turn from `start`, each with the tiles stepped into on the way
    /// (Run allows two steps). Ending back on `start` is not a move; waiting is. Stepping back into `start`
    /// still counts when it is a tunnel end that carries you away.
    public func moves(from start: Hex, steps: Int) -> [Hex: [Hex]] {
        var result: [Hex: [Hex]] = [:]
        var frontier: [(at: Hex, path: [Hex])] = [(start, [])]
        for _ in 0..<steps {
            var next: [(at: Hex, path: [Hex])] = []
            for node in frontier {
                for tile in board.neighbors(of: node.at) where canStep(from: node.at, to: tile) && result[tile] == nil && landing(tile) != start {
                    let path = node.path + [tile]
                    result[tile] = path
                    next.append((landing(tile), path))
                }
            }
            frontier = next
        }
        return result
    }

    /// The tiles stepped into along a shortest route, tunnels included; nil when there is none.
    public func route(from start: Hex, to goal: Hex) -> [Hex]? {
        if start == goal { return [] }
        var previous: [Hex: (from: Hex, entered: Hex)] = [:]
        var queue = [start]
        var head = 0
        var seen: Set<Hex> = [start]
        while head < queue.count {
            let at = queue[head]
            head += 1
            for tile in board.neighbors(of: at) where canStep(from: at, to: tile) {
                let land = landing(tile)
                guard !seen.contains(land) else { continue }
                seen.insert(land)
                previous[land] = (at, tile)
                if land == goal || tile == goal {
                    var steps: [Hex] = [tile]
                    var back = at
                    while back != start, let link = previous[back] {
                        steps.insert(link.entered, at: 0)
                        back = link.from
                    }
                    return steps
                }
                queue.append(land)
            }
        }
        return nil
    }

    /// True when every open tile can reach every other.
    public func isConnected() -> Bool {
        let open = board.cells.filter(isOpen)
        guard let first = open.first else { return true }
        var seen: Set<Hex> = [first]
        var queue = [first]
        var head = 0
        while head < queue.count {
            let at = queue[head]
            head += 1
            for tile in board.neighbors(of: at) where canStep(from: at, to: tile) && !seen.contains(tile) {
                seen.insert(tile)
                queue.append(tile)
            }
        }
        return seen.count == open.count
    }
}
