import Testing
@testable import HeistCore

@Test func boardOfRadiusFourHas61Tiles() {
    #expect(Board(radius: 4).cells.count == 61)
}

@Test func distanceCountsSteps() {
    #expect(Hex.origin.distance(to: Hex(q: 2, r: -1)) == 2)
    #expect(Hex(q: -4, r: 4).distance(to: Hex(q: 4, r: -4)) == 8)
}

@Test func tileNamesMatchThePrototype() {
    let board = Board(radius: 4)
    #expect(board.name(of: Hex(q: 0, r: -4)) == "A1")
    #expect(board.name(of: .origin) == "E5")
    #expect(board.name(of: Hex(q: -4, r: 4)) == "I1")
    #expect(board.name(of: Hex(q: 0, r: 4)) == "I5")
}

@Test func cornersHaveThreeNeighbors() {
    let board = Board(radius: 4)
    #expect(board.neighbors(of: .origin).count == 6)
    #expect(board.neighbors(of: Hex(q: 4, r: -4)).count == 3)
    #expect(board.isBorder(Hex(q: 4, r: -4)))
}
