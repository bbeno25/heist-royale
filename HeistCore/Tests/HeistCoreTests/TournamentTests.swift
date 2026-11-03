import Testing
@testable import HeistCore

private func play(_ winners: [Seat]) -> Tournament {
    var series = Tournament()
    for winner in winners { series.record(winner: winner) }
    return series
}

@Test func seatAIsThiefFirstThenRolesSwap() {
    #expect((1...8).map { Tournament.thief(inRound: $0) } == [.a, .a, .a, .b, .b, .b, .a, .b])
    #expect(Tournament.role(of: .b, inRound: 4) == .thief)
    #expect(Tournament.role(of: .a, inRound: 4) == .police)
}

@Test func fourWinsEndTheMatchAtOnce() {
    #expect(play([.a, .a, .a]).outcome == nil)
    #expect(play([.a, .a, .a, .a]).outcome == .win(.a))
    #expect(play([.b, .a, .b, .b, .b]).outcome == .win(.b))
    #expect(play([.a, .b, .a, .b, .a, .a]).outcome == .win(.a))
}

@Test func threeAllGoesToTheExtension() {
    let tied = play([.a, .a, .a, .b, .b, .b])
    #expect(tied.outcome == nil)
    #expect(tied.round == 7)
    #expect(play([.a, .a, .a, .b, .b, .b, .a]).outcome == nil)
}

@Test func winningBothExtensionRoundsWinsElseADraw() {
    let regular: [Seat] = [.a, .b, .a, .b, .a, .b]
    #expect(play(regular + [.a, .a]).outcome == .win(.a))
    #expect(play(regular + [.b, .b]).outcome == .win(.b))
    #expect(play(regular + [.a, .b]).outcome == .draw)
    #expect(play(regular + [.b, .a]).outcome == .draw)
    #expect(play(regular + [.a, .b]).score == SeatPair(a: 4, b: 4))
}
