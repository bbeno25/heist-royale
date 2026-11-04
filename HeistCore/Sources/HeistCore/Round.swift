// The rules engine for one round: the prep stage, then the chase.
// Ported from the app's stand-in (App/Match/SampleRound.swift), which follows the Master Plan's settled
// 2.0 rules: rob one chest then escape, catch on the same tile or a swap, the turn clock, vision, bushes,
// tunnels, mystery boxes and the 15 launch cards. On top of it: map walls, two real players instead of
// a user and a bot, every action checked, and a separate view for each role so nothing hidden leaks.

import Foundation

/// Timers live on the server; these are the numbers the rules use. Starting values from the
/// Master Plan's "Game logic" tab and the app's MatchRules.
public struct RoundRules: Codable, Sendable, Equatable {
    public var chaseTurns = 14
    /// Your own tile plus the tiles this many steps around it.
    public var sight = 1
    public var prepPoints = 3
    public var boxChance = 0.15
    public var maxBoxes = 2
    public var startingBoxes = 1
    public var cameraCutTurns = 4
    public var smokeTurns = 2
    public var lockdownTurns = 3
    public var cards = CardPools.launch

    public init() {}

    public static let standard = RoundRules()
}

/// One prep card played, with its tile if it has one.
public struct PrepPlay: Codable, Sendable, Equatable, Hashable {
    public var card: CardID
    public var tile: Hex?

    public init(card: CardID, tile: Hex? = nil) {
        self.card = card
        self.tile = tile
    }
}

/// A chase move: the tiles stepped into (none to wait), and the card played with it.
public struct MovePlan: Codable, Sendable, Equatable {
    public var path: [Hex]
    public var card: CardID?

    public init(path: [Hex] = [], card: CardID? = nil) {
        self.path = path
        self.card = card
    }
}

/// Where one side last saw the other, and on which turn.
public struct Sighting: Codable, Sendable, Equatable {
    public var tile: Hex
    public var turn: Int

    public init(tile: Hex, turn: Int) {
        self.tile = tile
        self.turn = turn
    }
}

/// Something one side is told: a line of the intel reveal, a chase event, or a card's answer.
/// `kind` and the fields are what the app renders; `text` is an English fallback with prototype tile names.
public struct Note: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        // Prep intel
        case scan, insideMan, cutWires, security, noIntel
        // Chase
        case smoke, lockdown, lockdownBlocked, tunnel, box, detectorPing, smokeCache, robbed, alarm, reinforced
        case cameraSpotted, lookoutSpotted, radar, radarJammed, compass
    }

    public enum Tone: String, Codable, Sendable {
        case info, good, alert
    }

    /// A direction on the board in the prototype's pointy-top layout (x right, y down), length 1.
    public struct Vector: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
    }

    public var kind: Kind
    public var text: String
    public var tone: Tone
    public var tile: Hex?
    public var card: CardID?
    /// A count the note is about, such as the Compass distance.
    public var number: Int?
    public var direction: Vector?

    public init(_ kind: Kind, _ text: String, tone: Tone = .info, tile: Hex? = nil, card: CardID? = nil, number: Int? = nil, direction: Vector? = nil) {
        self.kind = kind
        self.text = text
        self.tone = tone
        self.tile = tile
        self.card = card
        self.number = number
        self.direction = direction
    }
}

public struct RoundResult: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable {
        case caught, escaped, time
    }

    public var reason: Reason
    public var tile: Hex?
    /// Chase turns played, the last one included.
    public var turns: Int

    public var winner: Role { reason == .escaped ? .thief : .police }
}

/// Why an action was refused. The server sends `code` back in an `error` message.
public enum ActionError: Error, Equatable, Sendable {
    case wrongStage
    case notYourCard(CardID)
    case notInHand(CardID)
    case playedTwice(CardID)
    case overBudget
    case badTarget(CardID)
    case needsInfoUse(CardID)
    case notInstant(CardID)
    case oneCardPerTurn
    case tooManySteps
    case illegalStep(Hex)

    public var code: String {
        switch self {
        case .wrongStage: "wrong_stage"
        case .notYourCard: "not_your_card"
        case .notInHand: "not_in_hand"
        case .playedTwice: "played_twice"
        case .overBudget: "over_budget"
        case .badTarget: "bad_target"
        case .needsInfoUse: "needs_info_use"
        case .notInstant: "not_instant"
        case .oneCardPerTurn: "one_card_per_turn"
        case .tooManySteps: "too_many_steps"
        case .illegalStep: "illegal_step"
        }
    }

    public var message: String {
        switch self {
        case .wrongStage: "That can't be done right now."
        case .notYourCard(let card): "\(card.name) isn't a card for your role at this stage."
        case .notInHand(let card): "\(card.name) isn't in your hand."
        case .playedTwice(let card): "\(card.name) was played twice."
        case .overBudget: "Those cards cost more than your prep points."
        case .badTarget(let card): "\(card.name) can't go there."
        case .needsInfoUse(let card): "\(card.name) answers at once: use it with info.use."
        case .notInstant(let card): "\(card.name) is played with a move, not on its own."
        case .oneCardPerTurn: "Only one card per turn."
        case .tooManySteps: "Too many steps for this turn."
        case .illegalStep(let hex): "Can't step to (\(hex.q), \(hex.r))."
        }
    }
}

public struct Round: Sendable {
    public enum Stage: String, Codable, Sendable {
        case prep, chase, over
    }

    public enum SecurityKind: String, Codable, Sendable {
        case camera, dummyCamera, motionDetector
    }

    /// Stored with every match; bump it whenever a rule changes, so old records replay on old rules.
    public static let rulesVersion = 1

    public let map: GameMap
    public let rules: RoundRules
    public let terrain: Terrain
    private var random: SeededRandom

    public private(set) var stage = Stage.prep
    public private(set) var prepHands: RolePair<[CardID]>
    /// Chase cards in hand.
    public private(set) var cards: RolePair<[CardID]>

    // Board
    public private(set) var bushes: Set<Hex>
    public private(set) var boxes: [Hex] = []

    // What prep built
    public private(set) var cameras: Set<Hex> = []
    public private(set) var dummyCameras: Set<Hex> = []
    public private(set) var detectors: Set<Hex> = []
    public private(set) var reinforced: Set<Hex> = []
    public private(set) var plantedBushes: Set<Hex> = []
    public private(set) var lookouts: Set<Hex> = []
    public private(set) var smokeCaches: Set<Hex> = []

    // The chase
    public private(set) var turn = 1
    public private(set) var thief: Hex
    public private(set) var police: Hex
    public private(set) var hasLoot = false
    public private(set) var robbed: Set<Hex> = []
    public private(set) var cracking: Hex?
    public private(set) var smokeThrough = 0
    public private(set) var lockdownThrough = 0
    public private(set) var camerasOffThrough = 0
    public private(set) var result: RoundResult?
    /// Where each side stood at the start and after every turn, for the replay.
    public private(set) var trails = RolePair<[Hex]>(repeating: [])

    // What each side knows
    private var thiefKnownChests: Set<Hex> = []
    private var thiefKnownReinforced: Set<Hex> = []
    private var thiefKnownSecurity: [Hex: SecurityKind] = [:]
    private var policeKnownBushes: Set<Hex> = []
    private var policeKnownExits: Set<Hex> = []
    private var policeSawThief: Sighting?
    private var thiefSawPolice: Sighting?
    private var alarm: Sighting?
    private var seen = RolePair<Set<Hex>>(repeating: [])
    /// The turn each side last used an instant card (one card per turn).
    private var instantTurn = RolePair(repeating: 0)

    /// Deals both hands and the starting chase cards from `seed`, and drops the first mystery box.
    public init(map: GameMap, rules: RoundRules = .standard, seed: UInt64) {
        self.map = map
        self.rules = rules
        terrain = map.terrain
        random = SeededRandom(seed: seed)
        thief = map.thiefStart
        police = map.policeStart
        bushes = Set(map.bushes)
        prepHands = RolePair(thief: [], police: [])
        cards = RolePair(thief: [], police: [])
        for role in [Role.thief, .police] {
            prepHands[role] = Dealer.prepHand(for: role, from: rules.cards, random: &random)
            cards[role] = Dealer.chaseCard(for: role, from: rules.cards, random: &random).map { [$0] } ?? []
        }
        trails = RolePair(thief: [thief], police: [police])
        for _ in 0..<rules.startingBoxes {
            let spots = map.board.cells.filter {
                isFree($0) && !boxes.contains($0) && $0.distance(to: thief) >= 2 && $0.distance(to: police) >= 2
            }
            if let spot = random.pick(spots) { boxes.append(spot) }
        }
        look()
    }

    public func position(of role: Role) -> Hex { role == .thief ? thief : police }

    private func name(_ hex: Hex) -> String { map.board.name(of: hex) }

    /// A tile nothing stands on: the truth, used when builds land.
    func isFree(_ hex: Hex) -> Bool {
        terrain.isOpen(hex) && terrain.tunnelExit[hex] == nil && hex != map.thiefStart && hex != map.policeStart
            && !map.chests.contains(hex) && !map.exits.contains(hex) && !bushes.contains(hex) && !boxes.contains(hex)
    }

    /// A tile a role may aim a build at, judged by what that role knows. A build aimed at something it
    /// can't know about (the police doesn't know the exits, the thief doesn't know the chests) is accepted
    /// and moves to the nearest free tile when prep resolves, so refusals never leak hidden tiles.
    public func isPlaceable(_ hex: Hex, by role: Role) -> Bool {
        guard terrain.isOpen(hex), terrain.tunnelExit[hex] == nil, hex != map.thiefStart, hex != map.policeStart,
              !map.bushes.contains(hex), !boxes.contains(hex) else { return false }
        return role == .police ? !map.chests.contains(hex) : !map.exits.contains(hex)
    }

    // MARK: Prep

    /// Checks a prep submission: dealt cards only, each once, within the points, on valid targets.
    public func checkPrep(_ plays: [PrepPlay], for role: Role) throws(ActionError) {
        guard stage == .prep else { throw .wrongStage }
        var used: Set<CardID> = []
        var taken: Set<Hex> = []
        var cost = 0
        for play in plays {
            let card = play.card
            guard card.phase == .prep, card.roles.contains(role) else { throw .notYourCard(card) }
            guard prepHands[role].contains(card) else { throw .notInHand(card) }
            guard used.insert(card).inserted else { throw .playedTwice(card) }
            cost += card.cost
            switch card.target {
            case .freeTile:
                guard let tile = play.tile, isPlaceable(tile, by: role), !taken.contains(tile) else { throw .badTarget(card) }
                taken.insert(tile)
            case .chest:
                guard let tile = play.tile, map.chests.contains(tile) else { throw .badTarget(card) }
            case .area:
                guard let tile = play.tile, map.board.contains(tile) else { throw .badTarget(card) }
            case .none:
                break
            }
        }
        guard cost <= rules.prepPoints else { throw .overBudget }
    }

    /// Builds both sides' prep in the engine's order (police builds, thief builds, thief scans) and returns
    /// what each side learns at the intel reveal. A submission that fails `checkPrep` counts as no prep.
    public mutating func resolvePrep(thief thiefPlays: [PrepPlay], police policePlays: [PrepPlay]) -> RolePair<[Note]> {
        var intel = RolePair<[Note]>(repeating: [])
        guard stage == .prep else { return intel }
        let policePlays = (try? checkPrep(policePlays, for: .police)) == nil ? [] : policePlays
        let thiefPlays = (try? checkPrep(thiefPlays, for: .thief)) == nil ? [] : thiefPlays

        var taken: Set<Hex> = []
        for play in policePlays {
            guard var tile = play.tile else { continue }
            if play.card.target == .freeTile {
                tile = settle(tile, avoiding: taken)
                taken.insert(tile)
            }
            switch play.card {
            case .camera:
                cameras.insert(tile)
                intel.police.append(Note(.security, "Camera watching \(name(tile)) and the 6 tiles around it.", tile: tile, card: .camera))
            case .dummyCamera:
                dummyCameras.insert(tile)
                intel.police.append(Note(.security, "Dummy camera on \(name(tile)).", tile: tile, card: .dummyCamera))
            case .motionDetector:
                detectors.insert(tile)
                intel.police.append(Note(.security, "Motion detector hidden on \(name(tile)).", tile: tile, card: .motionDetector))
            case .reinforcedChest:
                reinforced.insert(tile)
                intel.police.append(Note(.security, "The chest on \(name(tile)) takes 2 turns to crack.", tile: tile, card: .reinforcedChest))
            default:
                break
            }
        }
        // A thief build on a tile the police used (or a chest it didn't know about) moves to the nearest
        // free tile, silently.
        for play in thiefPlays where play.card.target == .freeTile {
            guard let aimed = play.tile else { continue }
            let tile = settle(aimed, avoiding: taken)
            taken.insert(tile)
            switch play.card {
            case .plantBush:
                plantedBushes.insert(tile)
                bushes.insert(tile)
            case .lookout:
                lookouts.insert(tile)
            case .smokeCache:
                smokeCaches.insert(tile)
            default:
                break
            }
        }
        for play in thiefPlays {
            switch play.card {
            case .blueprintScan:
                guard let center = play.tile else { continue }
                var found: [String] = []
                for tile in map.board.cells where tile.distance(to: center) <= 2 {
                    if map.chests.contains(tile) {
                        thiefKnownChests.insert(tile)
                        if reinforced.contains(tile) { thiefKnownReinforced.insert(tile) }
                        found.append((reinforced.contains(tile) ? "reinforced chest on " : "chest on ") + name(tile))
                    }
                    if cameras.contains(tile) || dummyCameras.contains(tile) {
                        thiefKnownSecurity[tile] = .camera
                        found.append("camera on " + name(tile))
                    }
                    if detectors.contains(tile) {
                        thiefKnownSecurity[tile] = .motionDetector
                        found.append("motion detector on " + name(tile))
                    }
                }
                let text = found.isEmpty ? "Nothing within 2 of \(name(center))." : "Found " + found.joined(separator: ", ") + "."
                intel.thief.append(Note(.scan, text, tone: found.isEmpty ? .info : .good, tile: center, card: .blueprintScan, number: found.count))
            case .insideMan:
                let unknown = map.chests.filter { !thiefKnownChests.contains($0) }
                let pick = random.pick(unknown.isEmpty ? map.chests : unknown)!
                thiefKnownChests.insert(pick)
                intel.thief.append(Note(.insideMan, "A real chest is on \(name(pick)).", tone: .good, tile: pick, card: .insideMan))
            case .cutWires:
                camerasOffThrough = rules.cameraCutTurns
                intel.thief.append(Note(.cutWires, "Cameras stay off until turn \(rules.cameraCutTurns + 1).", tone: .good, card: .cutWires, number: rules.cameraCutTurns))
            default:
                break
            }
        }
        if intel.police.isEmpty {
            intel.police = [Note(.noIntel, "You placed no security this round.")]
        }
        if intel.thief.isEmpty {
            intel.thief = [Note(.noIntel, "No intel this round: you know the exits, but the chests are hidden.")]
        }
        stage = .chase
        look()
        return intel
    }

    /// The tile a build lands on: the one aimed at when it is free, else the nearest free one.
    private func settle(_ tile: Hex, avoiding taken: Set<Hex>) -> Hex {
        if isFree(tile) && !taken.contains(tile) { return tile }
        return map.board.cells.filter { isFree($0) && !taken.contains($0) }
            .min { ($0.distance(to: tile), $0) < ($1.distance(to: tile), $1) } ?? tile
    }

    // MARK: Chase

    /// Information cards answer at once while planning, so the player can still change their move.
    public mutating func useInstant(_ card: CardID, by role: Role) throws(ActionError) -> Note {
        guard stage == .chase else { throw .wrongStage }
        guard card.isInstant else { throw .notInstant(card) }
        guard card.roles.contains(role) else { throw .notYourCard(card) }
        guard cards[role].contains(card) else { throw .notInHand(card) }
        guard instantTurn[role] != turn else { throw .oneCardPerTurn }
        discard(card, from: role)
        instantTurn[role] = turn
        switch card {
        case .radar:
            guard turn > smokeThrough else { return Note(.radarJammed, "Radar jammed: the thief is in smoke.", card: .radar) }
            policeSawThief = Sighting(tile: thief, turn: turn)
            return Note(.radar, "Radar: the thief is on \(name(thief)).", tone: .alert, tile: thief, card: .radar)
        default:
            let targets = map.chests.filter { !robbed.contains($0) }
            guard let nearest = targets.min(by: { ($0.distance(to: thief), $0) < ($1.distance(to: thief), $1) }) else {
                return Note(.compass, "Compass: no chests left.", card: .compass)
            }
            let steps = thief.distance(to: nearest)
            let vector = Self.vector(from: thief, to: nearest)
            return Note(.compass, "Compass: the nearest chest is \(steps) \(steps == 1 ? "tile" : "tiles") \(Self.compassWord(vector)).",
                        tone: .good, card: .compass, number: steps, direction: vector)
        }
    }

    /// Checks a chase move: legal steps (two with Run), and a card from the hand that is played with a
    /// move. Instant cards go through `useInstant`, and only one card is played per turn.
    public func checkPlan(_ plan: MovePlan, for role: Role) throws(ActionError) {
        guard stage == .chase else { throw .wrongStage }
        if let card = plan.card {
            guard card.phase == .chase, card.roles.contains(role) else { throw .notYourCard(card) }
            guard !card.isInstant else { throw .needsInfoUse(card) }
            guard cards[role].contains(card) else { throw .notInHand(card) }
            guard instantTurn[role] != turn else { throw .oneCardPerTurn }
        }
        guard plan.path.count <= (plan.card == .run ? 2 : 1) else { throw .tooManySteps }
        var at = position(of: role)
        for tile in plan.path {
            guard terrain.canStep(from: at, to: tile) else { throw .illegalStep(tile) }
            at = terrain.landing(tile)
        }
    }

    /// Tiles a role can step into this turn, each with the tiles stepped into on the way.
    public func moves(for role: Role, steps: Int) -> [Hex: [Hex]] {
        terrain.moves(from: position(of: role), steps: steps)
    }

    /// Resolves one chase turn in the engine's order: cards, then movement tick by tick (catch, tile
    /// effects, escape), then cracking, vision and the clock. A plan that fails `checkPlan` counts as a wait.
    public mutating func resolveTurn(thief thiefPlan: MovePlan, police policePlan: MovePlan) -> RolePair<[Note]> {
        var notes = RolePair<[Note]>(repeating: [])
        guard stage == .chase else { return notes }
        var plans = RolePair(thief: thiefPlan, police: policePlan)
        for role in [Role.thief, .police] where (try? checkPlan(plans[role], for: role)) == nil {
            plans[role] = MovePlan()
        }

        for role in [Role.thief, .police] {
            guard let card = plans[role].card else { continue }
            discard(card, from: role)
            switch card {
            case .smoke:
                smokeThrough = turn + rules.smokeTurns - 1
                notes.thief.append(Note(.smoke, "Smoke! You're invisible this turn and next.", tone: .good, card: .smoke))
            case .lockdown:
                lockdownThrough = turn + rules.lockdownTurns - 1
                notes.police.append(Note(.lockdown, "Lockdown: every exit is sealed for 3 turns.", tone: .good, card: .lockdown, number: rules.lockdownTurns))
                notes.thief.append(Note(.lockdown, "Lockdown: every exit is sealed for 3 turns.", tone: .alert, card: .lockdown, number: rules.lockdownTurns))
            default:
                break
            }
        }

        for tick in 0..<2 {
            let thiefFrom = thief, policeFrom = police
            let thiefMoves = tick < plans.thief.path.count
            let policeMoves = tick < plans.police.path.count
            for role in [Role.thief, .police] where tick < plans[role].path.count {
                let entered = plans[role].path[tick]
                let land = terrain.landing(entered)
                if role == .thief { thief = land } else { police = land }
                if land != entered {
                    notes[role].append(Note(.tunnel, "Through the tunnel to \(name(land)).", tile: land))
                }
            }
            if thief == police || (thiefMoves && policeMoves && thief == policeFrom && police == thiefFrom) {
                finish(.caught, at: police)
                return notes
            }
            stepEffects(&notes)
            if map.exits.contains(thief) && hasLoot {
                if turn > lockdownThrough {
                    finish(.escaped, at: thief)
                    return notes
                } else if tick == 0 || thiefMoves {
                    notes.thief.append(Note(.lockdownBlocked, "The exits are sealed by Lockdown!", tone: .alert, tile: thief))
                }
            }
        }

        crackReinforced(&notes)
        look(&notes)
        if turn >= rules.chaseTurns {
            finish(.time, at: nil)
            return notes
        }
        recordTrails()
        spawnBox()
        turn += 1
        return notes
    }

    private mutating func finish(_ reason: RoundResult.Reason, at tile: Hex?) {
        result = RoundResult(reason: reason, tile: tile, turns: turn)
        stage = .over
        recordTrails()
    }

    private mutating func recordTrails() {
        trails.thief.append(thief)
        trails.police.append(police)
    }

    private mutating func stepEffects(_ notes: inout RolePair<[Note]>) {
        for role in [Role.thief, .police] {
            let at = position(of: role)
            guard let index = boxes.firstIndex(of: at) else { continue }
            boxes.remove(at: index)
            if let card = random.pick(rules.cards.chase[role]) {
                cards[role].append(card)
                notes[role].append(Note(.box, "Mystery box: you got \(card.name).", tone: .good, tile: at, card: card))
            }
        }
        if detectors.contains(thief) {
            detectors.remove(thief)
            policeSawThief = Sighting(tile: thief, turn: turn)
            notes.police.append(Note(.detectorPing, "Motion detector on \(name(thief)) pinged!", tone: .alert, tile: thief, card: .motionDetector))
        }
        if smokeCaches.contains(thief) {
            smokeCaches.remove(thief)
            cards.thief.append(.smoke)
            notes.thief.append(Note(.smokeCache, "You picked up your hidden Smoke card.", tone: .good, tile: thief, card: .smoke))
        }
        if !hasLoot, map.chests.contains(thief), !robbed.contains(thief), !reinforced.contains(thief) {
            rob(thief, &notes)
        }
    }

    /// A reinforced chest is cracked after the thief ends two turns in a row on it.
    private mutating func crackReinforced(_ notes: inout RolePair<[Note]>) {
        guard !hasLoot, reinforced.contains(thief), !robbed.contains(thief) else {
            cracking = nil
            return
        }
        thiefKnownChests.insert(thief)
        thiefKnownReinforced.insert(thief)
        if cracking == thief {
            rob(thief, &notes)
            cracking = nil
        } else {
            cracking = thief
            notes.thief.append(Note(.reinforced, "Reinforced chest! Stay a turn to crack it.", tile: thief, card: .reinforcedChest))
        }
    }

    private mutating func rob(_ tile: Hex, _ notes: inout RolePair<[Note]>) {
        hasLoot = true
        robbed.insert(tile)
        thiefKnownChests.insert(tile)
        alarm = Sighting(tile: tile, turn: turn)
        notes.thief.append(Note(.robbed, "You cracked the chest on \(name(tile))! Now reach an exit.", tone: .good, tile: tile))
        notes.police.append(Note(.alarm, "Alarm! The chest on \(name(tile)) was robbed.", tone: .alert, tile: tile))
    }

    private mutating func spawnBox() {
        guard boxes.count < rules.maxBoxes, random.chance(rules.boxChance) else { return }
        let spots = map.board.cells.filter { isFree($0) && $0 != thief && $0 != police && !boxes.contains($0) }
        if let spot = random.pick(spots) { boxes.append(spot) }
    }

    private mutating func discard(_ card: CardID, from role: Role) {
        if let index = cards[role].firstIndex(of: card) { cards[role].remove(at: index) }
    }

    // MARK: Vision

    var camerasOn: Bool { turn > camerasOffThrough }

    var thiefHidden: Bool { turn <= smokeThrough || bushes.contains(thief) }

    func policeSeesThief() -> Bool {
        guard !thiefHidden else { return false }
        if police.distance(to: thief) <= rules.sight { return true }
        return camerasOn && cameras.contains { $0.distance(to: thief) <= 1 }
    }

    func thiefSeesPolice() -> Bool {
        !bushes.contains(police) && thief.distance(to: police) <= rules.sight
    }

    /// Tiles a role can see right now: around its pawn, and around working cameras for the police.
    public func visibleTiles(for role: Role) -> Set<Hex> {
        let me = position(of: role)
        var tiles = Set(map.board.cells.filter { $0.distance(to: me) <= rules.sight })
        if role == .police, camerasOn {
            for camera in cameras {
                tiles.formUnion(map.board.cells.filter { $0.distance(to: camera) <= 1 })
            }
        }
        return tiles
    }

    private mutating func look() {
        var ignored = RolePair<[Note]>(repeating: [])
        look(&ignored)
    }

    /// Updates what each side has seen, after a step or at the start of the chase.
    private mutating func look(_ notes: inout RolePair<[Note]>) {
        if stage != .prep, policeSeesThief() {
            let byCamera = police.distance(to: thief) > rules.sight
            if byCamera, policeSawThief?.tile != thief || policeSawThief?.turn != turn {
                notes.police.append(Note(.cameraSpotted, "Your camera spotted the thief on \(name(thief)).", tone: .alert, tile: thief, card: .camera))
            }
            policeSawThief = Sighting(tile: thief, turn: turn)
        }
        if stage != .prep {
            if thiefSeesPolice() {
                thiefSawPolice = Sighting(tile: police, turn: turn)
            } else if let lookout = lookouts.sorted().first(where: { $0.distance(to: police) <= 1 }) {
                thiefSawPolice = Sighting(tile: police, turn: turn)
                notes.thief.append(Note(.lookoutSpotted, "Your lookout on \(name(lookout)) spotted the police on \(name(police)).", tile: police, card: .lookout))
            }
        }
        let thiefSees = visibleTiles(for: .thief)
        seen.thief.formUnion(thiefSees)
        for tile in thiefSees {
            if map.chests.contains(tile) { thiefKnownChests.insert(tile) }
            if cameras.contains(tile) || dummyCameras.contains(tile) { thiefKnownSecurity[tile] = .camera }
        }
        let policeSees = visibleTiles(for: .police)
        seen.police.formUnion(policeSees)
        for tile in policeSees {
            if plantedBushes.contains(tile) { policeKnownBushes.insert(tile) }
            if map.exits.contains(tile) { policeKnownExits.insert(tile) }
        }
    }

    // MARK: Views

    /// Everything one role may know right now, and nothing else. This is all the server ever sends.
    public func view(for role: Role) -> PlayerView {
        let isThief = role == .thief
        let knownBushes = isThief ? bushes : Set(map.bushes).union(policeKnownBushes)
        let chests: [PlayerView.Chest] = map.chests.compactMap { tile in
            guard !isThief || thiefKnownChests.contains(tile) else { return nil }
            let known = isThief ? thiefKnownReinforced.contains(tile) : reinforced.contains(tile)
            return PlayerView.Chest(tile: tile, robbed: robbed.contains(tile) && (isThief || alarm != nil), reinforced: known)
        }
        var security: [PlayerView.Security] = []
        if isThief {
            security = thiefKnownSecurity.keys.sorted().map { PlayerView.Security(tile: $0, kind: thiefKnownSecurity[$0]!) }
        } else {
            security = cameras.sorted().map { .init(tile: $0, kind: .camera) }
                + dummyCameras.sorted().map { .init(tile: $0, kind: .dummyCamera) }
                + detectors.sorted().map { .init(tile: $0, kind: .motionDetector) }
        }
        let visible = stage == .over ? Set(map.board.cells) : visibleTiles(for: role)
        return PlayerView(
            role: role, stage: stage, turn: turn, turnLimit: rules.chaseTurns, radius: map.radius,
            position: position(of: role), thiefStart: map.thiefStart, policeStart: map.policeStart,
            rocks: map.rocks, bushes: knownBushes.sorted(), walls: map.walls, tunnels: map.tunnels,
            exits: isThief ? map.exits : map.exits.filter(policeKnownExits.contains),
            chests: chests, security: security,
            lookouts: isThief ? lookouts.sorted() : [], smokeCaches: isThief ? smokeCaches.sorted() : [],
            boxes: boxes, visible: visible.sorted(), seen: seen[role].sorted(),
            opponent: isThief ? thiefSawPolice : policeSawThief,
            opponentVisible: stage == .chase && (isThief ? thiefSeesPolice() : policeSeesThief()),
            alarm: isThief ? nil : alarm,
            hasLoot: isThief ? hasLoot : alarm != nil,
            cracking: isThief ? cracking : nil,
            smokeThrough: isThief ? smokeThrough : 0,
            lockdownThrough: lockdownThrough,
            camerasOffThrough: isThief ? camerasOffThrough : 0,
            cards: cards[role], instantUsed: instantTurn[role] == turn
        )
    }

    /// The whole board, shown to both players once the round is over.
    public func reveal() -> RoundReveal {
        RoundReveal(
            map: map, thief: thief, police: police, robbed: robbed.sorted(), robbedAt: alarm,
            thiefTrail: trails.thief, policeTrail: trails.police,
            cameras: cameras.sorted(), dummyCameras: dummyCameras.sorted(), motionDetectors: detectors.sorted(),
            reinforced: reinforced.sorted(), plantedBushes: plantedBushes.sorted(), lookouts: lookouts.sorted(),
            smokeCaches: smokeCaches.sorted()
        )
    }

    // MARK: Directions

    static func vector(from a: Hex, to b: Hex) -> Note.Vector {
        let dq = Double(b.q - a.q), dr = Double(b.r - a.r)
        let x = 3.0.squareRoot() * (dq + dr / 2), y = 1.5 * dr
        let length = max((x * x + y * y).squareRoot(), 0.0001)
        return Note.Vector(x: x / length, y: y / length)
    }

    /// One of 8 compass words in the prototype's layout, north up.
    static func compassWord(_ v: Note.Vector) -> String {
        let words = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
        let angle = atan2(v.y, v.x) / (Double.pi / 4)
        let index = ((Int(angle.rounded()) % 8) + 8) % 8
        return words[index]
    }
}

/// Everything about a finished round, for the result screen and replays.
public struct RoundReveal: Codable, Sendable, Equatable {
    public var map: GameMap
    public var thief: Hex
    public var police: Hex
    public var robbed: [Hex]
    /// Where and on which turn the chest was robbed.
    public var robbedAt: Sighting?
    /// Where each side stood at the start and after every turn (absent from older servers).
    public var thiefTrail: [Hex]?
    public var policeTrail: [Hex]?
    public var cameras: [Hex]
    public var dummyCameras: [Hex]
    public var motionDetectors: [Hex]
    public var reinforced: [Hex]
    public var plantedBushes: [Hex]
    public var lookouts: [Hex]
    public var smokeCaches: [Hex]
}
