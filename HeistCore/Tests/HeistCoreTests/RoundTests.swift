import Testing
@testable import HeistCore

/// A hand-built map: the thief starts at the bottom, the police at the top, chests left and right of the
/// centre, exits on the left and right borders.
private func map(thief: Hex = Hex(q: 0, r: 3), police: Hex = Hex(q: 0, r: -3), walls: [Wall] = [], bushes: [Hex] = [], tunnels: [Tunnel] = []) -> GameMap {
    GameMap(
        radius: 4, thiefStart: thief, policeStart: police,
        chests: [Hex(q: 2, r: 0), Hex(q: -2, r: 0)], exits: [Hex(q: 4, r: -2), Hex(q: -4, r: 2)],
        rocks: [Hex(q: 0, r: -1)], bushes: bushes, walls: walls, tunnels: tunnels
    )
}

/// Fixed hands, no boxes: the police holds Camera, Reinforced chest, Motion detector and Dummy camera;
/// the thief holds Inside man, Blueprint scan, Plant bush and Lookout.
private func rules(thiefChase: CardID = .run, policeChase: CardID = .lockdown) -> RoundRules {
    var rules = RoundRules()
    rules.startingBoxes = 0
    rules.boxChance = 0
    rules.cards = CardPools(
        prep: RolePair(thief: [.plantBush, .lookout, .insideMan, .blueprintScan], police: CardPools.launch.prep.police),
        chase: RolePair(thief: [thiefChase], police: [policeChase])
    )
    return rules
}

private func chase(_ map: GameMap, _ rules: RoundRules = rules()) -> Round {
    var round = Round(map: map, rules: rules, seed: 1)
    _ = round.resolvePrep(thief: [], police: [])
    return round
}

@Test func meetingOnATileIsACatch() {
    var round = chase(map(thief: Hex(q: 0, r: 2), police: Hex(q: 0, r: 0)))
    _ = round.resolveTurn(thief: MovePlan(path: [Hex(q: 0, r: 1)]), police: MovePlan(path: [Hex(q: 0, r: 1)]))
    #expect(round.result?.reason == .caught)
    #expect(round.result?.winner == .police)
    #expect(round.stage == .over)
}

@Test func swappingTilesIsACatch() {
    var round = chase(map(thief: Hex(q: 0, r: 1), police: Hex(q: 0, r: 0)))
    _ = round.resolveTurn(thief: MovePlan(path: [.origin]), police: MovePlan(path: [Hex(q: 0, r: 1)]))
    #expect(round.result?.reason == .caught)
}

@Test func robThenEscape() {
    var round = chase(map(thief: Hex(q: 3, r: 0), police: Hex(q: -3, r: 0)))
    let notes = round.resolveTurn(thief: MovePlan(path: [Hex(q: 2, r: 0)]), police: MovePlan())
    #expect(round.hasLoot)
    #expect(notes.thief.contains { $0.kind == .robbed })
    #expect(notes.police.contains { $0.kind == .alarm && $0.tile == Hex(q: 2, r: 0) })
    #expect(round.view(for: .police).alarm == Sighting(tile: Hex(q: 2, r: 0), turn: 1))

    _ = round.resolveTurn(thief: MovePlan(path: [Hex(q: 3, r: -1)]), police: MovePlan())
    _ = round.resolveTurn(thief: MovePlan(path: [Hex(q: 4, r: -2)]), police: MovePlan())
    #expect(round.result?.reason == .escaped)
    #expect(round.result?.winner == .thief)
    #expect(round.result?.turns == 3)
    let reveal = round.reveal()
    #expect(reveal.thiefTrail == [Hex(q: 3, r: 0), Hex(q: 2, r: 0), Hex(q: 3, r: -1), Hex(q: 4, r: -2)])
    #expect(reveal.policeTrail?.count == 4)
    #expect(reveal.robbedAt == Sighting(tile: Hex(q: 2, r: 0), turn: 1))
}

@Test func lockdownSealsTheExits() {
    var round = chase(map(thief: Hex(q: 3, r: -1), police: Hex(q: -3, r: 0)))
    _ = round.resolveTurn(thief: MovePlan(path: [Hex(q: 2, r: 0)]), police: MovePlan())
    _ = round.resolveTurn(thief: MovePlan(path: [Hex(q: 3, r: -1)]), police: MovePlan(card: .lockdown))
    let notes = round.resolveTurn(thief: MovePlan(path: [Hex(q: 4, r: -2)]), police: MovePlan())
    #expect(round.result == nil)
    #expect(notes.thief.contains { $0.kind == .lockdownBlocked })
    _ = round.resolveTurn(thief: MovePlan(), police: MovePlan())
    _ = round.resolveTurn(thief: MovePlan(), police: MovePlan())
    #expect(round.result?.reason == .escaped)
}

@Test func reinforcedChestTakesTwoTurns() {
    var round = Round(map: map(thief: Hex(q: 3, r: 0), police: Hex(q: -3, r: 0)), rules: rules(), seed: 1)
    _ = round.resolvePrep(thief: [], police: [PrepPlay(card: .reinforcedChest, tile: Hex(q: 2, r: 0))])
    let first = round.resolveTurn(thief: MovePlan(path: [Hex(q: 2, r: 0)]), police: MovePlan())
    #expect(!round.hasLoot)
    #expect(first.thief.contains { $0.kind == .reinforced })
    #expect(round.view(for: .thief).cracking == Hex(q: 2, r: 0))
    _ = round.resolveTurn(thief: MovePlan(), police: MovePlan())
    #expect(round.hasLoot)
}

@Test func theClockGoesToThePolice() {
    var round = chase(map())
    for _ in 1..<round.rules.chaseTurns {
        _ = round.resolveTurn(thief: MovePlan(), police: MovePlan())
        #expect(round.result == nil)
    }
    _ = round.resolveTurn(thief: MovePlan(), police: MovePlan())
    #expect(round.result?.reason == .time)
    #expect(round.result?.turns == round.rules.chaseTurns)
}

@Test func illegalMovesAreRefused() {
    let wall = Wall(Hex(q: 0, r: 3), Hex(q: 1, r: 2))
    var round = chase(map(walls: [wall]))
    #expect(throws: ActionError.illegalStep(Hex(q: 1, r: 2))) { try round.checkPlan(MovePlan(path: [Hex(q: 1, r: 2)]), for: .thief) }
    #expect(throws: ActionError.tooManySteps) { try round.checkPlan(MovePlan(path: [Hex(q: 0, r: 2), Hex(q: 0, r: 1)]), for: .thief) }
    #expect(throws: ActionError.illegalStep(Hex(q: 0, r: 1))) { try round.checkPlan(MovePlan(path: [Hex(q: 0, r: 1)]), for: .thief) }
    #expect(throws: ActionError.illegalStep(Hex(q: 0, r: -1))) { try round.checkPlan(MovePlan(path: [Hex(q: 0, r: -1)]), for: .police) }
    #expect(throws: ActionError.notYourCard(.lockdown)) { try round.checkPlan(MovePlan(card: .lockdown), for: .thief) }
    // Run: two steps.
    #expect((try? round.checkPlan(MovePlan(path: [Hex(q: 0, r: 2), Hex(q: 0, r: 1)], card: .run), for: .thief)) != nil)
    // An illegal plan resolves as a wait.
    _ = round.resolveTurn(thief: MovePlan(path: [Hex(q: 1, r: 2)]), police: MovePlan())
    #expect(round.thief == Hex(q: 0, r: 3))
}

@Test func oneCardPerTurn() throws {
    var round = chase(map(), rules(thiefChase: .run, policeChase: .radar))
    let note = try round.useInstant(.radar, by: .police)
    #expect(note.kind == .radar && note.tile == round.thief)
    #expect(round.view(for: .police).opponent == Sighting(tile: round.thief, turn: 1))
    #expect(throws: ActionError.notInHand(.radar)) { _ = try round.useInstant(.radar, by: .police) }
    #expect(throws: ActionError.needsInfoUse(.compass)) { try round.checkPlan(MovePlan(card: .compass), for: .thief) }
}

@Test func prepIsChecked() {
    let round = Round(map: map(), rules: rules(), seed: 1)
    #expect(throws: ActionError.overBudget) {
        try round.checkPrep([PrepPlay(card: .camera, tile: Hex(q: 1, r: 1)), PrepPlay(card: .reinforcedChest, tile: Hex(q: 2, r: 0))], for: .police)
    }
    #expect(throws: ActionError.badTarget(.camera)) { try round.checkPrep([PrepPlay(card: .camera, tile: Hex(q: 2, r: 0))], for: .police) }
    #expect(throws: ActionError.notYourCard(.camera)) { try round.checkPrep([PrepPlay(card: .camera, tile: Hex(q: 1, r: 1))], for: .thief) }
    #expect(throws: ActionError.notInHand(.smokeCache)) { try round.checkPrep([PrepPlay(card: .smokeCache, tile: Hex(q: 1, r: 1))], for: .thief) }
    #expect(throws: ActionError.playedTwice(.plantBush)) {
        try round.checkPrep([PrepPlay(card: .plantBush, tile: Hex(q: 1, r: 1)), PrepPlay(card: .plantBush, tile: Hex(q: 1, r: 2))], for: .thief)
    }
    // The thief may aim a build at a chest it can't know about; the police may aim at a hidden exit.
    #expect((try? round.checkPrep([PrepPlay(card: .plantBush, tile: Hex(q: 2, r: 0))], for: .thief)) != nil)
    #expect((try? round.checkPrep([PrepPlay(card: .motionDetector, tile: Hex(q: 4, r: -2))], for: .police)) != nil)
}

@Test func buildsOnHiddenTilesMoveSilently() {
    var round = Round(map: map(), rules: rules(), seed: 1)
    let intel = round.resolvePrep(
        thief: [PrepPlay(card: .plantBush, tile: Hex(q: 2, r: 0)), PrepPlay(card: .insideMan)],
        police: [PrepPlay(card: .camera, tile: Hex(q: 1, r: 1)), PrepPlay(card: .motionDetector, tile: Hex(q: 4, r: -2))]
    )
    #expect(!round.bushes.contains(Hex(q: 2, r: 0)))
    #expect(round.plantedBushes.count == 1)
    #expect(round.plantedBushes.first!.distance(to: Hex(q: 2, r: 0)) == 1)
    #expect(round.detectors.count == 1 && !round.detectors.contains(Hex(q: 4, r: -2)))
    #expect(intel.thief.contains { $0.kind == .insideMan })
    #expect(intel.police.count == 2)
    #expect(round.stage == .chase)
}

@Test func viewsHideWhatTheOtherSideKnows() {
    var round = Round(map: map(), rules: rules(), seed: 1)
    _ = round.resolvePrep(
        thief: [PrepPlay(card: .lookout, tile: Hex(q: -1, r: 2))],
        police: [PrepPlay(card: .motionDetector, tile: Hex(q: 2, r: 1)), PrepPlay(card: .camera, tile: Hex(q: -2, r: 1))]
    )
    let thief = round.view(for: .thief), police = round.view(for: .police)
    #expect(thief.chests.isEmpty)
    #expect(thief.exits.count == 2)
    #expect(thief.security.isEmpty)
    #expect(thief.opponent == nil && !thief.opponentVisible)
    #expect(thief.lookouts == [Hex(q: -1, r: 2)])
    #expect(police.chests.count == 2)
    #expect(police.exits.isEmpty)
    #expect(police.lookouts.isEmpty)
    #expect(police.security.count == 2)
    #expect(police.opponent == nil)
    #expect(police.position == Hex(q: 0, r: -3) && thief.position == Hex(q: 0, r: 3))
}

@Test func bushesHideAndCamerasWatch() {
    var round = Round(map: map(thief: Hex(q: -1, r: 3), police: Hex(q: 1, r: -3), bushes: [Hex(q: -2, r: 2)]), rules: rules(), seed: 1)
    _ = round.resolvePrep(thief: [], police: [PrepPlay(card: .camera, tile: Hex(q: -1, r: 1))])
    let notes = round.resolveTurn(thief: MovePlan(path: [Hex(q: -1, r: 2)]), police: MovePlan())
    #expect(notes.police.contains { $0.kind == .cameraSpotted })
    #expect(round.view(for: .police).opponentVisible)
    _ = round.resolveTurn(thief: MovePlan(path: [Hex(q: -2, r: 2)]), police: MovePlan())
    #expect(!round.view(for: .police).opponentVisible)
    #expect(round.view(for: .police).opponent?.tile == Hex(q: -1, r: 2))
}

@Test func tunnelsCarryYouAcross() {
    let tunnel = Tunnel(Hex(q: 0, r: 2), Hex(q: 3, r: -3))
    var round = chase(map(tunnels: [tunnel]))
    let notes = round.resolveTurn(thief: MovePlan(path: [Hex(q: 0, r: 2)]), police: MovePlan())
    #expect(round.thief == Hex(q: 3, r: -3))
    #expect(notes.thief.contains { $0.kind == .tunnel })
}
