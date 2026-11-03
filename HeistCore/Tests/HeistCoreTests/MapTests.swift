import Testing
@testable import HeistCore

@Test func generatedMapsKeepTheirDistances() {
    let rules = MapRules.standard
    for seed in UInt64(1)...500 {
        var random = SeededRandom(seed: seed)
        let map = MapGenerator.generate(rules, random: &random)
        let board = map.board
        let special = [map.thiefStart, map.policeStart] + map.chests + map.exits

        #expect(map.chests.count == rules.chests && map.exits.count == rules.exits, "seed \(seed)")
        #expect(Set(special).count == special.count, "seed \(seed): pieces overlap")
        #expect(map.thiefStart.distance(to: map.policeStart) >= rules.startGap, "seed \(seed): starts too close")
        for chest in map.chests {
            #expect(chest.distance(to: map.thiefStart) >= rules.chestGap, "seed \(seed): chest near the thief start")
            #expect(map.chests.allSatisfy { $0 == chest || $0.distance(to: chest) >= rules.chestGap }, "seed \(seed): chests too close")
        }
        for exit in map.exits {
            #expect(board.isBorder(exit), "seed \(seed): exit off the border")
            #expect(map.chests.allSatisfy { $0.distance(to: exit) >= rules.radius }, "seed \(seed): exit near a chest")
        }
        #expect(map.rocks.count == rules.rocks && map.bushes.count == rules.bushes, "seed \(seed)")
        #expect(map.tunnels.count == rules.tunnels && !map.walls.isEmpty, "seed \(seed)")
        let terrain = map.terrain
        #expect(terrain.isConnected(), "seed \(seed): open tiles not connected")
        for piece in special {
            #expect(terrain.isOpen(piece) && !map.bushes.contains(piece) && terrain.tunnelExit[piece] == nil, "seed \(seed)")
        }
        for rock in map.rocks {
            #expect(rock.distance(to: map.thiefStart) >= 2 && rock.distance(to: map.policeStart) >= 2, "seed \(seed): rock next to a start")
        }
        for chest in map.chests {
            #expect(terrain.route(from: map.thiefStart, to: chest) != nil, "seed \(seed): chest unreachable")
        }
    }
}

@Test func theSameSeedMakesTheSameMap() {
    var one = SeededRandom(seed: 42), two = SeededRandom(seed: 42), three = SeededRandom(seed: 43)
    let a = MapGenerator.generate(.standard, random: &one)
    let b = MapGenerator.generate(.standard, random: &two)
    let c = MapGenerator.generate(.standard, random: &three)
    #expect(a == b)
    #expect(a != c)
}

@Test func everyRoundGetsADifferentMap() {
    var random = SeededRandom(seed: 7)
    let maps = (0..<50).map { _ in MapGenerator.generate(.standard, random: &random) }
    #expect(Set(maps.map { "\($0.thiefStart)\($0.chests)\($0.rocks)" }).count == 50)
}

@Test func wallsBlockSteps() {
    let wall = Wall(Hex(q: 1, r: 0), .origin)
    #expect(wall == Wall(.origin, Hex(q: 1, r: 0)))
    let terrain = Terrain(radius: 4, rocks: [Hex(q: 0, r: 1)], walls: [wall], tunnels: [Tunnel(Hex(q: -1, r: 0), Hex(q: 3, r: -3))])
    #expect(!terrain.canStep(from: .origin, to: Hex(q: 1, r: 0)))
    #expect(!terrain.canStep(from: .origin, to: Hex(q: 0, r: 1)))
    #expect(terrain.canStep(from: .origin, to: Hex(q: 1, r: -1)))
    #expect(terrain.landing(Hex(q: -1, r: 0)) == Hex(q: 3, r: -3))
    // Around the wall: two steps instead of one.
    #expect(terrain.route(from: .origin, to: Hex(q: 1, r: 0))?.count == 2)
    // Through the tunnel: one step lands three tiles away.
    #expect(terrain.route(from: .origin, to: Hex(q: 3, r: -3)) == [Hex(q: -1, r: 0)])
}

@Test func dealtHandsMixCosts() {
    var random = SeededRandom(seed: 1)
    for _ in 0..<200 {
        for role in Role.allCases {
            let hand = Dealer.prepHand(for: role, from: .launch, random: &random)
            #expect(hand.count == 4)
            #expect(Set(hand).count == 4)
            #expect(hand.filter { $0.cost == 1 }.count == 2)
            #expect(hand.allSatisfy { CardPools.launch.prep[role].contains($0) })
            let chase = Dealer.chaseCard(for: role, from: .launch, random: &random)!
            #expect(CardPools.launch.chase[role].contains(chase))
        }
    }
}

@Test func randomHelpersStayInRange() {
    var random = SeededRandom(seed: 9)
    var counts = Array(repeating: 0, count: 6)
    for _ in 0..<6000 { counts[random.below(6)] += 1 }
    #expect(counts.allSatisfy { $0 > 850 && $0 < 1150 })
    #expect(random.shuffle(Array(0..<20)).sorted() == Array(0..<20))
}
