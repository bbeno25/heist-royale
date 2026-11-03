// Roles and cards, as data: cost, what a card targets and who may play it.
// Wording and costs follow the Master Plan's "Cards" tab; server v1 deals the 15 cards the app plays.

public enum Role: String, Codable, Sendable, CaseIterable, Hashable {
    case thief, police

    public var other: Role { self == .thief ? .police : .thief }
}

/// One value for each role.
public struct RolePair<Value> {
    public var thief: Value
    public var police: Value

    public init(thief: Value, police: Value) {
        self.thief = thief
        self.police = police
    }

    public init(repeating value: Value) {
        self.init(thief: value, police: value)
    }

    public subscript(role: Role) -> Value {
        get { role == .thief ? thief : police }
        set {
            if role == .thief { thief = newValue } else { police = newValue }
        }
    }
}

extension RolePair: Sendable where Value: Sendable {}
extension RolePair: Equatable where Value: Equatable {}
extension RolePair: Codable where Value: Codable {}

public enum CardID: String, Codable, Sendable, CaseIterable, Hashable {
    // Police prep (security)
    case camera, motionDetector, dummyCamera, reinforcedChest
    // Thief prep (intel and terrain)
    case plantBush, lookout, smokeCache, blueprintScan, insideMan, cutWires
    // Chase
    case run, compass, smoke, radar, lockdown

    public enum Phase: String, Codable, Sendable {
        case prep, chase
    }

    public enum Target: Equatable, Sendable {
        /// A tile with nothing on it: no rock, tunnel end, start, chest, exit, bush or box.
        case freeTile
        /// One of the chests.
        case chest
        /// Any tile; the card covers everything within this many steps.
        case area(Int)
        /// Played without a target.
        case none
    }

    public var phase: Phase {
        switch self {
        case .run, .compass, .smoke, .radar, .lockdown: .chase
        default: .prep
        }
    }

    /// Who may play it; Run belongs to both.
    public var roles: [Role] {
        switch self {
        case .camera, .motionDetector, .dummyCamera, .reinforcedChest, .radar, .lockdown: [.police]
        case .plantBush, .lookout, .smokeCache, .blueprintScan, .insideMan, .cutWires, .compass, .smoke: [.thief]
        case .run: [.thief, .police]
        }
    }

    /// Prep points; chase cards are free.
    public var cost: Int {
        switch self {
        case .motionDetector, .dummyCamera, .plantBush, .lookout, .smokeCache: 1
        case .camera, .reinforcedChest, .blueprintScan, .insideMan, .cutWires: 2
        default: 0
        }
    }

    public var target: Target {
        switch self {
        case .camera, .motionDetector, .dummyCamera, .plantBush, .lookout, .smokeCache: .freeTile
        case .reinforcedChest: .chest
        case .blueprintScan: .area(2)
        default: .none
        }
    }

    /// Chase cards that answer at once while planning, so the move can still change.
    public var isInstant: Bool { self == .compass || self == .radar }

    public var name: String {
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
}

/// The cards each role is dealt from. Live config can switch cards off by leaving them out.
public struct CardPools: Codable, Sendable, Equatable {
    public var prep: RolePair<[CardID]>
    public var chase: RolePair<[CardID]>

    public init(prep: RolePair<[CardID]>, chase: RolePair<[CardID]>) {
        self.prep = prep
        self.chase = chase
    }

    /// The 15 cards the app plays today.
    public static let launch = CardPools(
        prep: RolePair(
            thief: [.plantBush, .lookout, .smokeCache, .blueprintScan, .insideMan, .cutWires],
            police: [.motionDetector, .dummyCamera, .camera, .reinforcedChest]
        ),
        chase: RolePair(thief: [.run, .compass, .smoke], police: [.run, .radar, .lockdown])
    )
}

/// Deals the cards at the start of a round.
public enum Dealer {
    /// Two 1-point and two 2-point cards with no duplicates (fewer when the pool runs short),
    /// so hands differ in what they do, never in what they are worth.
    public static func prepHand(for role: Role, from pools: CardPools, random: inout SeededRandom) -> [CardID] {
        let pool = pools.prep[role]
        let cheap = random.shuffle(pool.filter { $0.cost == 1 }).prefix(2)
        let dear = random.shuffle(pool.filter { $0.cost == 2 }).prefix(2)
        return random.shuffle(Array(dear) + Array(cheap))
    }

    /// The one chase card each player starts the chase with.
    public static func chaseCard(for role: Role, from pools: CardPools, random: inout SeededRandom) -> CardID? {
        random.pick(pools.chase[role])
    }
}
