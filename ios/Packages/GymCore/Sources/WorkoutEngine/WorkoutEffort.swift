import Foundation

/// Apple workout effort (#614): 1–10, the score Apple Health uses for Training Load.
public enum WorkoutEffort {
    public static let range = 1...10

    /// Prefill from the session's reps in reserve: 0 left → 10, 1 → 9, 3 → 7. Nil without any RIR logged.
    public static func fromRIR(_ rirs: [Int]) -> Int? {
        guard !rirs.isEmpty else { return nil }
        let avg = Double(rirs.reduce(0, +)) / Double(rirs.count)
        return clamp(Int((10 - avg).rounded()))
    }

    public static func clamp(_ v: Int) -> Int { min(range.upperBound, max(range.lowerBound, v)) }

    /// Apple's bands: easy 1–3, moderate 4–6, hard 7–8, all out 9–10.
    public static func word(_ v: Int) -> String {
        switch v {
        case ...3: "easy"
        case 4...6: "moderate"
        case 7...8: "hard"
        default: "all out"
        }
    }
}
