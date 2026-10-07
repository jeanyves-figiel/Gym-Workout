/// Deterministic PRNG (mulberry32) — a plan is reproducible from its seed. Matches the original TS engine.
public struct Rng: Sendable {
    private var a: UInt32

    public init(seed: UInt32) { a = seed }

    public mutating func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    public mutating func pick<T>(_ arr: [T]) -> T {
        precondition(!arr.isEmpty, "pick from empty array")
        return arr[Int(next() * Double(arr.count))]
    }
}
