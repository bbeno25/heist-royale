/// A small seeded generator (SplitMix64). Every random choice in a round comes from one of these, so a
/// round replays exactly from its seed. The helpers below are written out by hand instead of using the
/// standard library's random APIs, whose algorithms may change between Swift releases.
public struct SeededRandom: RandomNumberGenerator, Sendable, Codable, Equatable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A whole number in `0..<bound`, without modulo bias.
    public mutating func below(_ bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        let b = UInt64(bound)
        let limit = UInt64.max - UInt64.max % b
        var x = next()
        while x >= limit { x = next() }
        return Int(x % b)
    }

    /// A number in `0..<1`.
    public mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    /// True with probability `p`.
    public mutating func chance(_ p: Double) -> Bool {
        unit() < p
    }

    /// A number in `range`.
    public mutating func number(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    public mutating func pick<T>(_ items: [T]) -> T? {
        items.isEmpty ? nil : items[below(items.count)]
    }

    /// Fisher–Yates.
    public mutating func shuffle<T>(_ items: [T]) -> [T] {
        var out = items
        guard out.count > 1 else { return out }
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            out.swapAt(i, below(i + 1))
        }
        return out
    }

    /// A new generator seeded from this one, for an independent stream (a round, a bot).
    public mutating func split() -> SeededRandom {
        SeededRandom(seed: next())
    }
}
