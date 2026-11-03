// The map of one round and its generator, ported from the prototype's genMap (prototype/index.html,
// "MAP GENERATION") with the distances from the Master Plan's "Game logic" tab.

/// Everything fixed on the board at the start of a round, before the prep stage adds to it.
public struct GameMap: Codable, Sendable, Equatable {
    public var radius: Int
    public var thiefStart: Hex
    public var policeStart: Hex
    public var chests: [Hex]
    public var exits: [Hex]
    public var rocks: [Hex]
    public var bushes: [Hex]
    public var walls: [Wall]
    public var tunnels: [Tunnel]

    public init(radius: Int, thiefStart: Hex, policeStart: Hex, chests: [Hex], exits: [Hex], rocks: [Hex], bushes: [Hex], walls: [Wall], tunnels: [Tunnel]) {
        self.radius = radius
        self.thiefStart = thiefStart
        self.policeStart = policeStart
        self.chests = chests
        self.exits = exits
        self.rocks = rocks
        self.bushes = bushes
        self.walls = walls
        self.tunnels = tunnels
    }

    public var board: Board { Board(radius: radius) }

    public var terrain: Terrain {
        Terrain(radius: radius, rocks: rocks, walls: walls, tunnels: tunnels)
    }

    public func start(of role: Role) -> Hex { role == .thief ? thiefStart : policeStart }
}

/// How many of each piece a generated map gets. These are the prototype's defaults; the simulator
/// retunes them (task 1.5) and live config can change them.
public struct MapRules: Codable, Sendable, Equatable {
    public var radius = 4
    public var rocks = 6
    public var bushes = 6
    /// Short wall pieces of 2 or 3 edges hugging one tile, like a ruined building corner.
    public var wallPieces = 4
    public var tunnels = 1
    public var chests = 2
    public var exits = 2

    public init() {}

    public static let standard = MapRules()

    /// The distances a map aims for (relaxed only when a map can't be placed):
    /// starts at least radius + 2 apart, chests at least radius from the thief start and from each other,
    /// exits on the border at least radius from every chest.
    public var startGap: Int { radius + 2 }
    public var chestGap: Int { radius }
}

public enum MapGenerator {
    /// A new random map. Every start, chest and exit stays reachable: the open tiles are always one
    /// connected area.
    public static func generate(_ rules: MapRules, random: inout SeededRandom) -> GameMap {
        let board = Board(radius: rules.radius)
        let all = board.cells
        let core = placeCore(rules, all: all, border: all.filter(board.isBorder), random: &random)
        let special = [core.thief, core.police] + core.chests + core.exits
        let specialSet = Set(special)

        for attempt in 0..<80 {
            let ease = attempt / 20  // crowded board? place a bit less
            let rockPool = all.filter { !specialSet.contains($0) && $0.distance(to: core.thief) >= 2 && $0.distance(to: core.police) >= 2 }
            let rocks = Array(random.shuffle(rockPool).prefix(max(0, rules.rocks - ease * 2)))
            let rockSet = Set(rocks)
            let open = { (hex: Hex) in board.contains(hex) && !rockSet.contains(hex) }

            var walls: [Wall] = []
            var wallSet: Set<Wall> = []
            for _ in 0..<max(0, rules.wallPieces - ease) {
                guard let center = random.pick(all.filter(open)) else { break }
                let first = random.below(6)
                let length = random.chance(0.4) ? 3 : 2
                for j in 0..<length {
                    let neighbor = center + ring[(first + j) % 6].offset
                    guard open(neighbor) else { continue }
                    let wall = Wall(center, neighbor)
                    if wallSet.insert(wall).inserted { walls.append(wall) }
                }
            }
            let terrain = Terrain(radius: rules.radius, rocks: rocks, walls: walls, tunnels: [Tunnel]())
            guard terrain.isConnected() else { continue }

            let free = all.filter { open($0) && !specialSet.contains($0) }
            let bushes = Array(random.shuffle(free).prefix(rules.bushes))
            let bushSet = Set(bushes)
            var pool = free.filter { tile in !bushSet.contains(tile) && special.allSatisfy { $0.distance(to: tile) >= 2 } }
            var tunnels: [Tunnel] = []
            for _ in 0..<rules.tunnels where pool.count >= 2 {
                let a = random.pick(pool)!
                let far = pool.filter { $0.distance(to: a) >= rules.radius + 1 }
                let b = random.pick(far) ?? random.pick(pool.filter { $0 != a })!
                tunnels.append(Tunnel(a, b))
                pool = pool.filter { $0.distance(to: a) >= 2 && $0.distance(to: b) >= 2 }
            }

            return GameMap(
                radius: rules.radius, thiefStart: core.thief, policeStart: core.police,
                chests: core.chests.sorted(), exits: core.exits.sorted(),
                rocks: rocks.sorted(), bushes: bushes.sorted(),
                walls: walls.sorted { $0.a != $1.a ? $0.a < $1.a : $0.b < $1.b }, tunnels: tunnels
            )
        }
        return GameMap(
            radius: rules.radius, thiefStart: core.thief, policeStart: core.police,
            chests: core.chests.sorted(), exits: core.exits.sorted(), rocks: [], bushes: [], walls: [], tunnels: []
        )
    }

    /// Starts, chests and exits, as far apart as the rules ask; each pass of `slack` relaxes the
    /// distances by one if no layout fits.
    private static func placeCore(_ rules: MapRules, all: [Hex], border: [Hex], random: inout SeededRandom)
        -> (thief: Hex, police: Hex, chests: [Hex], exits: [Hex]) {
        let r = rules.radius
        func place(_ pool: [Hex], _ count: Int, _ ok: (Hex, [Hex]) -> Bool) -> [Hex]? {
            var out: [Hex] = []
            for _ in 0..<count {
                let options = pool.filter { !out.contains($0) && ok($0, out) }
                guard let choice = random.pick(options) else { return nil }
                out.append(choice)
            }
            return out
        }
        for slack in 0...8 {
            for _ in 0..<200 {
                let ts = random.pick(all)!, ps = random.pick(all)!
                if ts == ps || ts.distance(to: ps) < rules.startGap - slack { continue }
                let free = { (c: Hex) in c != ts && c != ps }
                guard let chests = place(all, rules.chests, { c, got in
                    free(c) && c.distance(to: ts) >= rules.chestGap - slack && c.distance(to: ps) >= 2 - slack
                        && got.allSatisfy { $0.distance(to: c) >= rules.chestGap - slack }
                }) else { continue }
                guard let exits = place(slack < 4 ? border : all, rules.exits, { c, got in
                    free(c) && !chests.contains(c) && chests.allSatisfy { $0.distance(to: c) >= r - slack }
                        && c.distance(to: ts) >= r - 1 - slack && c.distance(to: ps) >= 2 - slack
                        && got.allSatisfy { $0.distance(to: c) >= r - slack }
                }) else { continue }
                return (ts, ps, chests, exits)
            }
        }
        let shuffled = random.shuffle(all)
        return (shuffled[0], shuffled[1], Array(shuffled[2..<(2 + rules.chests)]),
                Array(shuffled[(2 + rules.chests)..<(2 + rules.chests + rules.exits)]))
    }
}
