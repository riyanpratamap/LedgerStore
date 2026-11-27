/// Deterministic PRNG so the fixture is byte-for-byte reproducible.
///
/// We avoid `Int.random(in:using:)` because the stdlib does not promise that
/// its sampling algorithm stays the same across Swift versions.
struct SplitMix64 {
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

    /// Uniform integer in `0..<upperBound`. Modulo bias is irrelevant at these sizes.
    mutating func int(_ upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(range.count)
    }

    /// True with probability `percent / 100`.
    mutating func chance(_ percent: Int) -> Bool {
        int(100) < percent
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(items.count)]
    }

    /// Distinct values from `0..<upperBound`, in draw order.
    mutating func distinct(_ count: Int, below upperBound: Int, excluding: Set<Int> = []) -> [Int] {
        var seen = excluding
        var result: [Int] = []
        while result.count < count {
            let value = int(upperBound)
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}
