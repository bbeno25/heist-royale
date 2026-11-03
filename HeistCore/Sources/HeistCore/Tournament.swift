/// The two players of a match. Seat A is picked by a coin flip and plays thief first.
public enum Seat: String, Codable, Sendable, CaseIterable, Hashable {
    case a, b

    public var other: Seat { self == .a ? .b : .a }
}

/// One value for each seat.
public struct SeatPair<Value> {
    public var a: Value
    public var b: Value

    public init(a: Value, b: Value) {
        self.a = a
        self.b = b
    }

    public init(repeating value: Value) {
        self.init(a: value, b: value)
    }

    public subscript(seat: Seat) -> Value {
        get { seat == .a ? a : b }
        set {
            if seat == .a { a = newValue } else { b = newValue }
        }
    }
}

extension SeatPair: Sendable where Value: Sendable {}
extension SeatPair: Equatable where Value: Equatable {}
extension SeatPair: Codable where Value: Codable {}

/// The online match format, decided 3 Nov 2026. Seat A is thief in rounds 1 to 3 and seat B in rounds 4
/// to 6; the first to 4 round wins takes the match at once. At 3-3 come two extension rounds, A as thief
/// then B: winning both wins the match, splitting them is a draw.
public struct Tournament: Codable, Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case win(Seat)
        case draw
    }

    public static let thiefSchedule: [Seat] = [.a, .a, .a, .b, .b, .b, .a, .b]
    public static let regularRounds = 6
    public static let winTarget = 4

    /// The winner of each round played, in order.
    public private(set) var winners: [Seat] = []

    public init() {}

    /// The round being played or about to be played.
    public var round: Int { winners.count + 1 }

    public static func thief(inRound round: Int) -> Seat {
        thiefSchedule[round - 1]
    }

    public static func role(of seat: Seat, inRound round: Int) -> Role {
        thief(inRound: round) == seat ? .thief : .police
    }

    public var score: SeatPair<Int> {
        SeatPair(a: winners.filter { $0 == .a }.count, b: winners.filter { $0 == .b }.count)
    }

    /// Nil while the match goes on.
    public var outcome: Outcome? {
        let regular = winners.prefix(Self.regularRounds)
        for seat in Seat.allCases where regular.filter({ $0 == seat }).count >= Self.winTarget {
            return .win(seat)
        }
        guard winners.count == Self.thiefSchedule.count else { return nil }
        let extra = winners[Self.regularRounds...]
        return extra.first == extra.last ? .win(extra.first!) : .draw
    }

    public mutating func record(winner: Seat) {
        precondition(outcome == nil, "the match is already over")
        winners.append(winner)
    }
}
