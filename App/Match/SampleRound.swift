import Foundation
import HeistCore

/// A stand-in for the rules engine, so the match screens can be played end to end against a simple bot.
/// It follows the Master Plan's settled 2.0 rules (rob one chest then escape, catch on the same tile or a
/// swap, the turn clock, vision, bushes, the cave tunnel, mystery boxes) and the sample cards, and leaves the
/// rest out. It lives in the app, not HeistCore, and is replaced once the engine and backend are chosen.
struct SampleRound {
    let user: Role
    private var random: SeededRandom

    // Board
    let rocks = Harbor.rocks
    let chests = Harbor.chests
    let exits = Harbor.exits
    let tunnel: [Hex: Hex] = [Harbor.caves.0: Harbor.caves.1, Harbor.caves.1: Harbor.caves.0]
    private(set) var bushes = Harbor.bushes
    private(set) var boxes: Set<Hex> = [Harbor.firstBox]

    // What prep built
    private(set) var cameras: Set<Hex> = []
    private(set) var dummyCameras: Set<Hex> = []
    private(set) var detectors: Set<Hex> = []
    private(set) var reinforced: Set<Hex> = []
    private(set) var plantedBushes: Set<Hex> = []
    private(set) var lookouts: Set<Hex> = []
    private(set) var smokeCaches: Set<Hex> = []
    private(set) var camerasCutThrough = 0

    // The chase
    private(set) var turn = 1
    private(set) var thief = Harbor.thiefStart
    private(set) var police = Harbor.policeStart
    private(set) var hasLoot = false
    private(set) var robbed: Set<Hex> = []
    private(set) var cracking: Hex?
    private(set) var cards: [Role: [CardID]] = [:]
    private(set) var smokeThrough = 0
    private(set) var lockdownThrough = 0
    private(set) var end: RoundEnd?

    // What each side knows
    private(set) var thiefKnownChests: Set<Hex> = []
    /// Security the thief has scanned or seen, as the art it shows (a dummy camera looks like a camera).
    private(set) var thiefKnownSecurity: [Hex: String] = [:]
    private(set) var policeKnownBushes: Set<Hex> = []
    private(set) var policeSawThief: Sighting?
    private(set) var thiefSawPolice: Sighting?
    private(set) var alarm: Sighting?

    // Where both players stood at the start and after every turn, for the highlight replay.
    private(set) var thiefTrail: [Hex] = [Harbor.thiefStart]
    private(set) var policeTrail: [Hex] = [Harbor.policeStart]

    private var botChest: Hex
    private var patrol: Hex

    init(user: Role, seed: UInt64) {
        self.user = user
        random = SeededRandom(seed: seed)
        let chestList = chests.sorted { Harbor.name($0) < Harbor.name($1) }
        botChest = chestList.randomElement(using: &random)!
        patrol = chestList.min { $0.distance(to: Harbor.policeStart) < $1.distance(to: Harbor.policeStart) }!
        cards[.thief] = [CardID.thiefChasePool.randomElement(using: &random)!]
        cards[.police] = [CardID.policeChasePool.randomElement(using: &random)!]
    }

    // MARK: Board helpers

    func isOpen(_ hex: Hex) -> Bool {
        Harbor.board.contains(hex) && !rocks.contains(hex)
    }

    /// A tile prep can build on: no rock, cave, start, chest, exit or bush.
    func isFree(_ hex: Hex) -> Bool {
        isOpen(hex) && tunnel[hex] == nil && hex != Harbor.thiefStart && hex != Harbor.policeStart
            && !chests.contains(hex) && !exits.contains(hex) && !bushes.contains(hex)
    }

    /// Where a step into a tile ends up: a cave carries you to the other cave.
    func landing(_ hex: Hex) -> Hex { tunnel[hex] ?? hex }

    func position(of role: Role) -> Hex { role == .thief ? thief : police }

    /// Tiles a player can step into this turn, each with the steps that get there (Run allows two).
    func moves(for role: Role, steps: Int) -> [Hex: [Hex]] {
        var result: [Hex: [Hex]] = [:]
        var frontier: [(at: Hex, path: [Hex])] = [(position(of: role), [])]
        for _ in 0..<steps {
            var next: [(at: Hex, path: [Hex])] = []
            for node in frontier {
                for tile in Harbor.board.neighbors(of: node.at) where isOpen(tile) && result[tile] == nil && tile != position(of: role) {
                    let path = node.path + [tile]
                    result[tile] = path
                    next.append((landing(tile), path))
                }
            }
            frontier = next
        }
        return result
    }

    /// Steps along a shortest route, tunnels included; nil when there is none.
    func route(from start: Hex, to goal: Hex) -> [Hex]? {
        if start == goal { return [] }
        var previous: [Hex: (from: Hex, entered: Hex)] = [:]
        var queue = [start]
        var seen: Set<Hex> = [start]
        while !queue.isEmpty {
            let at = queue.removeFirst()
            for tile in Harbor.board.neighbors(of: at) where isOpen(tile) {
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

    // MARK: Prep

    /// Deals a prep hand: two 1-point and two 2-point cards, no duplicates.
    mutating func dealHand(for role: Role) -> [CardID] {
        let hand: [CardID]
        switch role {
        case .police:
            hand = [.camera, .reinforcedChest, .motionDetector, .dummyCamera]
        case .thief:
            let cheap = [CardID.plantBush, .lookout, .smokeCache].shuffled(using: &random).prefix(2)
            let dear = [CardID.blueprintScan, .insideMan, .cutWires].shuffled(using: &random).prefix(2)
            hand = Array(dear) + Array(cheap)
        }
        return hand.shuffled(using: &random)
    }

    /// The bot's prep, played blind like the player's.
    mutating func botPrep() -> [PrepPlay] {
        let free = Harbor.tiles.filter(isFree).sorted { Harbor.name($0) < Harbor.name($1) }
        switch user.other {
        case .police:
            let guarded = chests.sorted { Harbor.name($0) < Harbor.name($1) }.shuffled(using: &random)
            let cameraTile = Harbor.board.neighbors(of: guarded[0]).filter(isFree).randomElement(using: &random)
            let detectorTile = free.filter { $0.distance(to: Harbor.thiefStart) == 3 }.randomElement(using: &random)
            let dummyTile = free.filter { $0.length <= 2 && $0 != cameraTile && $0 != detectorTile }.randomElement(using: &random)
            return [
                PrepPlay(card: .camera, tile: cameraTile),
                PrepPlay(card: .reinforcedChest, tile: guarded[1]),
                PrepPlay(card: .motionDetector, tile: detectorTile),
                PrepPlay(card: .dummyCamera, tile: dummyTile),
            ]
        case .thief:
            let bushTile = free.filter { $0.distance(to: Harbor.thiefStart) == 2 }.randomElement(using: &random)
            return [PrepPlay(card: .plantBush, tile: bushTile), PrepPlay(card: .insideMan, tile: nil)]
        }
    }

    /// Builds both sides' prep in the engine's order (police builds, thief builds, thief scans) and
    /// returns what the player learns at the intel reveal.
    mutating func resolvePrep(user plays: [PrepPlay], bot botPlays: [PrepPlay]) -> [IntelLine] {
        let policePlays = user == .police ? plays : botPlays
        let thiefPlays = user == .thief ? plays : botPlays

        for play in policePlays {
            guard let tile = play.tile else { continue }
            switch play.card {
            case .camera: cameras.insert(tile)
            case .dummyCamera: dummyCameras.insert(tile)
            case .motionDetector: detectors.insert(tile)
            case .reinforcedChest: reinforced.insert(tile)
            default: break
            }
        }
        let security = cameras.union(dummyCameras).union(detectors)
        for play in thiefPlays {
            guard var tile = play.tile else { continue }
            // A thief build on a tile the police used moves to the nearest free tile, silently.
            if security.contains(tile) {
                tile = Harbor.tiles.filter { isFree($0) && !security.contains($0) }.min { $0.distance(to: tile) < $1.distance(to: tile) } ?? tile
            }
            switch play.card {
            case .plantBush: plantedBushes.insert(tile); bushes.insert(tile)
            case .lookout: lookouts.insert(tile)
            case .smokeCache: smokeCaches.insert(tile)
            default: break
            }
        }

        var intel: [IntelLine] = []
        for play in thiefPlays {
            switch play.card {
            case .blueprintScan:
                guard let center = play.tile else { continue }
                var found: [String] = []
                for tile in Harbor.tiles where tile.distance(to: center) <= 2 {
                    if chests.contains(tile) {
                        thiefKnownChests.insert(tile)
                        found.append((reinforced.contains(tile) ? "reinforced chest on " : "chest on ") + Harbor.name(tile))
                    }
                    if cameras.contains(tile) || dummyCameras.contains(tile) {
                        thiefKnownSecurity[tile] = "art-camera"
                        found.append("camera on " + Harbor.name(tile))
                    }
                    if detectors.contains(tile) {
                        thiefKnownSecurity[tile] = "art-detector"
                        found.append("motion detector on " + Harbor.name(tile))
                    }
                }
                intel.append(IntelLine(card: .blueprintScan, text: found.isEmpty ? "Nothing within 2 of \(Harbor.name(center))." : "Found " + found.joined(separator: ", ") + "."))
            case .insideMan:
                let pick = chests.subtracting(thiefKnownChests).sorted { Harbor.name($0) < Harbor.name($1) }.randomElement(using: &random)
                    ?? chests.sorted { Harbor.name($0) < Harbor.name($1) }.randomElement(using: &random)!
                thiefKnownChests.insert(pick)
                botChest = pick
                intel.append(IntelLine(card: .insideMan, text: "A real chest is on \(Harbor.name(pick))."))
            case .cutWires:
                camerasCutThrough = 4
                intel.append(IntelLine(card: .cutWires, text: "Cameras stay off until turn 5."))
            default:
                break
            }
        }

        if user == .police {
            // The police learns nothing of the thief's prep; it sees its own security.
            intel = policePlays.compactMap { play in
                guard let tile = play.tile else { return nil }
                switch play.card {
                case .camera: return IntelLine(card: .camera, text: "Watching \(Harbor.name(tile)) and the 6 tiles around it.")
                case .motionDetector: return IntelLine(card: .motionDetector, text: "Hidden on \(Harbor.name(tile)).")
                case .dummyCamera: return IntelLine(card: .dummyCamera, text: "Decoy camera on \(Harbor.name(tile)).")
                case .reinforcedChest: return IntelLine(card: .reinforcedChest, text: "The chest on \(Harbor.name(tile)) takes 2 turns to crack.")
                default: return nil
                }
            }
            if intel.isEmpty {
                intel = [IntelLine(card: nil, text: "You placed no security this round.")]
            }
        } else if intel.isEmpty {
            intel = [IntelLine(card: nil, text: "No intel this round: you know the exits, but the chests are hidden.")]
        }
        updateVision()
        return intel
    }

    // MARK: Chase

    /// Information cards answer at once while planning.
    mutating func playInstant(_ card: CardID, by role: Role) -> MatchNote {
        discard(card, from: role)
        switch card {
        case .radar:
            guard turn > smokeThrough else { return MatchNote(text: "Radar jammed: the thief is in smoke.", tone: .info) }
            policeSawThief = Sighting(tile: thief, turn: turn)
            return MatchNote(text: "Radar: the thief is on \(Harbor.name(thief)).", tone: .alert, tile: thief)
        case .compass:
            let targets = chests.subtracting(robbed)
            guard let nearest = targets.min(by: { $0.distance(to: thief) < $1.distance(to: thief) }) else {
                return MatchNote(text: "Compass: no chests left.", tone: .info)
            }
            let steps = thief.distance(to: nearest)
            return MatchNote(text: "Compass: the nearest chest is \(steps) \(steps == 1 ? "tile" : "tiles") \(Harbor.direction(from: thief, to: nearest)).", tone: .good)
        default:
            return MatchNote(text: "", tone: .info)
        }
    }

    /// Resolves one chase turn: the bot picks its move, then cards, steps, catches, tile effects, escape and
    /// the clock run in the engine's order. Returns what the player is told.
    mutating func resolveTurn(user plan: MovePlan) -> [MatchNote] {
        let notes = playTurn(user: plan)
        thiefTrail.append(thief)
        policeTrail.append(police)
        return notes
    }

    private mutating func playTurn(user plan: MovePlan) -> [MatchNote] {
        var notes: [MatchNote] = []
        let bot = user == .thief ? policeBot() : thiefBot()
        let thiefPlan = user == .thief ? plan : bot
        let policePlan = user == .police ? plan : bot

        for (role, card) in [(Role.thief, thiefPlan.card), (.police, policePlan.card)] {
            guard let card else { continue }
            discard(card, from: role)
            switch card {
            case .smoke:
                smokeThrough = turn + 1
                if role == user { notes.append(MatchNote(text: "Smoke! You're invisible this turn and next.", tone: .good)) }
            case .lockdown:
                lockdownThrough = turn + 2
                notes.append(MatchNote(text: "Lockdown: every exit is sealed for 3 turns.", tone: role == user ? .good : .alert))
            default:
                break
            }
        }

        for tick in 0..<2 {
            let thiefFrom = thief, policeFrom = police
            let thiefMoves = tick < thiefPlan.path.count
            let policeMoves = tick < policePlan.path.count
            if thiefMoves { thief = landing(thiefPlan.path[tick]) }
            if policeMoves { police = landing(policePlan.path[tick]) }
            if user == .thief, thiefMoves, tunnel[thiefPlan.path[tick]] != nil {
                notes.append(MatchNote(text: "Through the sea cave to \(Harbor.name(thief)).", tone: .info))
            }

            if thief == police || (thiefMoves && policeMoves && thief == policeFrom && police == thiefFrom) {
                end = .caught(police)
                return notes
            }
            stepEffects(&notes)
            if exits.contains(thief) && hasLoot {
                if turn > lockdownThrough {
                    end = .escaped(thief)
                    return notes
                } else if user == .thief {
                    notes.append(MatchNote(text: "The exits are sealed by Lockdown!", tone: .alert))
                }
            }
        }

        crackReinforced(&notes)
        updateVision(notes: &notes)
        if end == nil, turn >= MatchRules.chaseTurns {
            end = .time
            return notes
        }
        spawnBox()
        turn += 1
        return notes
    }

    private mutating func stepEffects(_ notes: inout [MatchNote]) {
        for role in [Role.thief, .police] where boxes.contains(position(of: role)) {
            boxes.remove(position(of: role))
            let pool = role == .thief ? CardID.thiefChasePool : CardID.policeChasePool
            let card = pool.randomElement(using: &random)!
            cards[role, default: []].append(card)
            if role == user { notes.append(MatchNote(text: "Mystery box: you got \(card.name).", tone: .good)) }
        }
        if detectors.contains(thief) {
            detectors.remove(thief)
            policeSawThief = Sighting(tile: thief, turn: turn)
            if user == .police { notes.append(MatchNote(text: "Motion detector on \(Harbor.name(thief)) pinged!", tone: .alert, tile: thief)) }
        }
        if smokeCaches.contains(thief) {
            smokeCaches.remove(thief)
            cards[.thief, default: []].append(.smoke)
            if user == .thief { notes.append(MatchNote(text: "You picked up your hidden Smoke card.", tone: .good)) }
        }
        if !hasLoot, chests.contains(thief), !robbed.contains(thief), !reinforced.contains(thief) {
            rob(thief, &notes)
        }
    }

    /// A reinforced chest is cracked after the thief ends two turns in a row on it.
    private mutating func crackReinforced(_ notes: inout [MatchNote]) {
        guard !hasLoot, reinforced.contains(thief), !robbed.contains(thief) else {
            cracking = nil
            return
        }
        if cracking == thief {
            rob(thief, &notes)
            cracking = nil
        } else {
            cracking = thief
            if user == .thief { notes.append(MatchNote(text: "Reinforced chest! Stay a turn to crack it.", tone: .info, tile: thief)) }
        }
    }

    private mutating func rob(_ tile: Hex, _ notes: inout [MatchNote]) {
        hasLoot = true
        robbed.insert(tile)
        thiefKnownChests.insert(tile)
        alarm = Sighting(tile: tile, turn: turn)
        notes.append(user == .thief
            ? MatchNote(text: "You cracked the chest on \(Harbor.name(tile))! Now reach an exit.", tone: .good, tile: tile)
            : MatchNote(text: "Alarm! The chest on \(Harbor.name(tile)) was robbed.", tone: .alert, tile: tile))
    }

    // MARK: Vision

    var thiefHidden: Bool { turn <= smokeThrough || bushes.contains(thief) }

    func policeSeesThief() -> Bool {
        guard !thiefHidden else { return false }
        if police.distance(to: thief) <= MatchRules.sight { return true }
        return turn > camerasCutThrough && cameras.contains { $0.distance(to: thief) <= 1 }
    }

    func thiefSeesPolice() -> Bool {
        !bushes.contains(police) && thief.distance(to: police) <= MatchRules.sight
    }

    /// Tiles the player can see right now: around their pawn, and around working cameras for the police.
    func visibleTiles(for role: Role) -> Set<Hex> {
        var seen = Set(Harbor.tiles.filter { $0.distance(to: position(of: role)) <= MatchRules.sight })
        if role == .police, turn > camerasCutThrough {
            for camera in cameras {
                seen.formUnion(Harbor.tiles.filter { $0.distance(to: camera) <= 1 })
            }
        }
        return seen
    }

    private mutating func updateVision() {
        var ignored: [MatchNote] = []
        updateVision(notes: &ignored)
    }

    private mutating func updateVision(notes: inout [MatchNote]) {
        if policeSeesThief() {
            let byCamera = police.distance(to: thief) > MatchRules.sight
            if user == .police, byCamera, policeSawThief?.tile != thief || policeSawThief?.turn != turn {
                notes.append(MatchNote(text: "Your camera spotted the thief on \(Harbor.name(thief)).", tone: .alert, tile: thief))
            }
            policeSawThief = Sighting(tile: thief, turn: turn)
        }
        if thiefSeesPolice() {
            thiefSawPolice = Sighting(tile: police, turn: turn)
        } else if let lookout = lookouts.first(where: { $0.distance(to: police) <= 1 }) {
            thiefSawPolice = Sighting(tile: police, turn: turn)
            if user == .thief { notes.append(MatchNote(text: "Your lookout on \(Harbor.name(lookout)) spotted the police on \(Harbor.name(police)).", tone: .info, tile: police)) }
        }
        for tile in visibleTiles(for: .thief) {
            if chests.contains(tile) { thiefKnownChests.insert(tile) }
            if cameras.contains(tile) || dummyCameras.contains(tile) { thiefKnownSecurity[tile] = "art-camera" }
        }
        for tile in visibleTiles(for: .police) where plantedBushes.contains(tile) {
            policeKnownBushes.insert(tile)
        }
    }

    private mutating func spawnBox() {
        guard boxes.count < 2, Double.random(in: 0..<1, using: &random) < 0.15 else { return }
        let spots = Harbor.tiles.filter { isFree($0) && $0 != thief && $0 != police && !boxes.contains($0) }
        if let spot = spots.randomElement(using: &random) { boxes.insert(spot) }
    }

    private mutating func discard(_ card: CardID, from role: Role) {
        if let index = cards[role]?.firstIndex(of: card) { cards[role]?.remove(at: index) }
    }

    // MARK: Bot

    /// Chases what it last saw or heard, otherwise patrols the chests.
    private mutating func policeBot() -> MovePlan {
        let hand = cards[.police] ?? []
        if hand.contains(.radar), policeSawThief.map({ turn - $0.turn >= 3 }) ?? (turn >= 3) {
            _ = playInstant(.radar, by: .police)
        }
        var card: CardID?
        if alarm != nil, hand.contains(.lockdown), lockdownThrough < turn { card = .lockdown }

        let goal: Hex
        if let seen = policeSawThief, turn - seen.turn <= 3 {
            goal = seen.tile
        } else if let alarm, turn - alarm.turn <= 4 {
            goal = alarm.tile
        } else {
            if police == patrol {
                let others = chests.subtracting([patrol]).sorted { Harbor.name($0) < Harbor.name($1) }
                patrol = others.randomElement(using: &random) ?? patrol
            }
            goal = patrol
        }
        var path = route(from: police, to: goal) ?? []
        let freshSighting = policeSawThief?.turn == turn - 1 || policeSawThief?.turn == turn
        if card == nil, hand.contains(.run), freshSighting, path.count >= 2 {
            card = .run
        }
        path = Array(path.prefix(card == .run ? 2 : 1))
        return MovePlan(path: path, card: card)
    }

    /// Heads for its chest, then the nearest exit, stepping away from a police it can see.
    private mutating func thiefBot() -> MovePlan {
        if !hasLoot, reinforced.contains(thief), !robbed.contains(thief), chests.contains(thief) {
            return MovePlan()  // stay to crack it
        }
        let goals = hasLoot ? Array(exits) : [botChest]
        func distance(from tile: Hex) -> Int {
            goals.compactMap { route(from: tile, to: $0)?.count }.min() ?? 99
        }
        let danger = thiefSawPolice.flatMap { turn - $0.turn <= 1 ? $0.tile : nil }
        let hand = cards[.thief] ?? []

        var best: (score: Double, path: [Hex]) = (-.infinity, [])
        let steps = moves(for: .thief, steps: 1).sorted { Harbor.name($0.key) < Harbor.name($1.key) }.map(\.value)
        for path in [[]] + steps {
            let land = path.last.map(landing) ?? thief
            var score = -Double(distance(from: land))
            if let danger {
                let gap = land.distance(to: danger)
                if gap <= 1 { score -= 100 }
                score += Double(min(gap, 3)) * 1.6
            }
            score += Double.random(in: 0..<0.3, using: &random)
            if score > best.score { best = (score, path) }
        }
        var plan = MovePlan(path: best.path)
        if let danger, danger.distance(to: thief) <= 2, hand.contains(.smoke) {
            plan.card = .smoke
        } else if hasLoot, hand.contains(.run), let exitRoute = goals.compactMap({ route(from: thief, to: $0) }).min(by: { $0.count < $1.count }), exitRoute.count == 2 {
            plan = MovePlan(path: exitRoute, card: .run)
        }
        return plan
    }
}

/// One prep card played, with its tile if it has one.
struct PrepPlay: Equatable {
    let card: CardID
    var tile: Hex?
}

/// A chase move: the tiles stepped into (none to wait), and the card played with it.
struct MovePlan: Equatable {
    var path: [Hex] = []
    var card: CardID?
}

/// Where one side last saw the other, and when.
struct Sighting: Equatable {
    let tile: Hex
    let turn: Int
}

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

enum RoundEnd: Equatable {
    case caught(Hex), escaped(Hex), time

    var winner: Role {
        if case .escaped = self { return .thief }
        return .police
    }
}

/// A small seeded generator (SplitMix64), so a sample round can be replayed from its seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
