/// The bot that fills an empty seat, takes over for a player who drops, and plays the simulator.
///
/// Its decisions are the app's bot (App/Match/SampleRound.swift: `botPrep`, `policeBot`, `thiefBot`), with
/// two changes so it plays by the same rules as a person: it decides only from its own `PlayerView`, so
/// the thief explores until it finds a chest instead of knowing one, and it plays only the cards it was
/// dealt, within the prep points. A little seeded randomness keeps it from being read.
public struct Bot: Sendable {
    private var random: SeededRandom
    private var patrol: Hex?
    private var explore: Hex?

    public init(seed: UInt64) {
        random = SeededRandom(seed: seed)
    }

    // MARK: Prep

    /// Plays one 2-point and one 1-point card from the hand when it can, placed the way the app's bot places them.
    public mutating func prep(view: PlayerView, hand: [CardID], points: Int) -> [PrepPlay] {
        var plays: [PrepPlay] = []
        var left = points
        var taken: Set<Hex> = []
        let free = freeTiles(view)

        func add(_ card: CardID, _ tile: Hex?) {
            guard card.cost <= left, card.target == .none || tile != nil else { return }
            plays.append(PrepPlay(card: card, tile: tile))
            left -= card.cost
            if let tile, card.target == .freeTile { taken.insert(tile) }
        }
        func spot(_ ok: (Hex) -> Bool) -> Hex? {
            random.pick(free.filter { !taken.contains($0) && ok($0) })
        }

        switch view.role {
        case .police:
            let chests = random.shuffle(view.chests.map(\.tile))
            if let card = random.pick(hand.filter { $0.cost == 2 }), let first = chests.first {
                switch card {
                case .camera: add(card, spot { $0.distance(to: first) == 1 })
                case .reinforcedChest: add(card, chests.count > 1 ? chests[1] : first)
                default: break
                }
            }
            if let card = random.pick(hand.filter { $0.cost == 1 }) {
                switch card {
                case .motionDetector: add(card, spot { $0.distance(to: view.thiefStart) == 3 })
                case .dummyCamera: add(card, spot { $0.length <= 2 })
                default: break
                }
            }
        case .thief:
            if let card = [CardID.insideMan, .blueprintScan, .cutWires].first(where: hand.contains) {
                switch card {
                case .blueprintScan:
                    // Chests sit at least a board radius from the thief start; scan the likeliest band.
                    let band = view.board.cells.filter { $0.distance(to: view.thiefStart) == view.radius }
                    let closest = band.map(\.length).min() ?? 0
                    add(card, random.pick(band.filter { $0.length <= closest + 1 }))
                default:
                    add(card, nil)
                }
            }
            if let card = [CardID.plantBush, .lookout, .smokeCache].first(where: hand.contains) {
                let gap = card == .lookout ? 3 : 2
                add(card, spot { $0.distance(to: view.thiefStart) == gap })
            }
        }
        return plays
    }

    /// Tiles a build may aim at, as this role knows the board.
    private func freeTiles(_ view: PlayerView) -> [Hex] {
        let terrain = view.terrain
        let bushes = Set(view.bushes), boxes = Set(view.boxes)
        let chests = Set(view.chests.map(\.tile)), exits = Set(view.exits)
        return view.board.cells.filter {
            terrain.isOpen($0) && terrain.tunnelExit[$0] == nil && $0 != view.thiefStart && $0 != view.policeStart
                && !bushes.contains($0) && !boxes.contains($0) && !chests.contains($0) && !exits.contains($0)
        }
    }

    // MARK: Chase

    /// An instant card to use while planning, before choosing the move. The police uses Radar when the
    /// trail has gone cold; the thief's bot never uses Compass, as in the app.
    public mutating func instant(view: PlayerView) -> CardID? {
        guard view.stage == .chase, view.role == .police, !view.instantUsed, view.cards.contains(.radar) else { return nil }
        let cold = view.opponent.map { view.turn - $0.turn >= 3 } ?? (view.turn >= 3)
        return cold ? .radar : nil
    }

    public mutating func move(view: PlayerView) -> MovePlan {
        guard view.stage == .chase else { return MovePlan() }
        return view.role == .police ? policeMove(view) : thiefMove(view)
    }

    /// Chases what it last saw or heard, otherwise patrols the chests.
    private mutating func policeMove(_ view: PlayerView) -> MovePlan {
        let terrain = view.terrain
        let turn = view.turn
        var card: CardID?
        if view.alarm != nil, view.cards.contains(.lockdown), view.lockdownThrough < turn, !view.instantUsed {
            card = .lockdown
        }

        let chests = view.chests.map(\.tile)
        let goal: Hex
        if let seen = view.opponent, turn - seen.turn <= 3 {
            goal = seen.tile
        } else if let alarm = view.alarm, turn - alarm.turn <= 4 {
            goal = alarm.tile
        } else {
            if patrol == nil {
                patrol = chests.min { ($0.distance(to: view.policeStart), $0) < ($1.distance(to: view.policeStart), $1) }
            }
            if view.position == patrol {
                patrol = random.pick(chests.filter { $0 != patrol }) ?? patrol
            }
            goal = patrol ?? view.position
        }
        var path = terrain.route(from: view.position, to: goal) ?? []
        let fresh = view.opponent.map { $0.turn == turn - 1 || $0.turn == turn } ?? false
        if card == nil, view.cards.contains(.run), !view.instantUsed, fresh, path.count >= 2 {
            card = .run
        }
        path = Array(path.prefix(card == .run ? 2 : 1))
        return MovePlan(path: path, card: card)
    }

    /// Heads for a chest it knows of (exploring until it finds one), then the nearest exit, stepping away
    /// from a police it can see.
    private mutating func thiefMove(_ view: PlayerView) -> MovePlan {
        let terrain = view.terrain
        if !view.hasLoot, view.cracking == view.position {
            return MovePlan()  // stay to crack it
        }
        let goals: [Hex]
        if view.hasLoot {
            goals = view.exits
        } else if let chest = knownChest(view, terrain) {
            goals = [chest]
        } else if let target = exploreTarget(view) {
            goals = [target]
        } else {
            goals = []
        }
        func distance(from tile: Hex) -> Int {
            goals.compactMap { terrain.route(from: tile, to: $0)?.count }.min() ?? 99
        }
        let danger = view.opponent.flatMap { view.turn - $0.turn <= 1 ? $0.tile : nil }

        var best: (score: Double, path: [Hex]) = (-.infinity, [])
        let steps = terrain.moves(from: view.position, steps: 1).sorted { $0.key < $1.key }.map(\.value)
        for path in [[]] + steps {
            let land = path.last.map(terrain.landing) ?? view.position
            var score = -Double(distance(from: land))
            if let danger {
                let gap = land.distance(to: danger)
                if gap <= 1 { score -= 100 }
                score += Double(min(gap, 3)) * 1.6
            }
            score += random.unit() * 0.3
            if score > best.score { best = (score, path) }
        }
        var plan = MovePlan(path: best.path)
        guard !view.instantUsed else { return plan }
        if let danger, danger.distance(to: view.position) <= 2, view.cards.contains(.smoke) {
            plan.card = .smoke
        } else if view.hasLoot, view.cards.contains(.run),
                  let exitRoute = goals.compactMap({ terrain.route(from: view.position, to: $0) }).min(by: { $0.count < $1.count }),
                  exitRoute.count == 2 {
            plan = MovePlan(path: exitRoute, card: .run)
        }
        return plan
    }

    /// The nearest chest the thief knows of that is still full.
    private func knownChest(_ view: PlayerView, _ terrain: Terrain) -> Hex? {
        view.chests.filter { !$0.robbed }.map(\.tile)
            .min { (terrain.route(from: view.position, to: $0)?.count ?? 99, $0) < (terrain.route(from: view.position, to: $1)?.count ?? 99, $1) }
    }

    /// Where to look for a chest: the nearest unseen tile far enough from the thief start to hold one
    /// (from the prototype's exploreTarget).
    private mutating func exploreTarget(_ view: PlayerView) -> Hex? {
        let seen = Set(view.seen)
        if let explore, !seen.contains(explore) { return explore }
        let terrain = view.terrain
        var best: Hex?
        var bestScore = Double.infinity
        for tile in view.board.cells where !seen.contains(tile) && terrain.isOpen(tile) && tile.distance(to: view.thiefStart) >= view.radius {
            let score = Double(tile.distance(to: view.position)) + random.unit() * 2
            if score < bestScore {
                bestScore = score
                best = tile
            }
        }
        explore = best
        return best
    }
}
