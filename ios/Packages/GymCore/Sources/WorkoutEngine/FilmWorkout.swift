import Foundation

/// Film my workout (#952, design B "Show · Lift · Review" with A's sets that log themselves): the member shows the
/// weight to the camera, lifts, and the phone names the move, counts the reps, scores the form and logs each set when
/// they rack. Everything here is pure: the camera, the text reader and the clip live in the app. Moves and reps come
/// from the form check's models (`FormCheck.swift`), so only exercises with a position guide can be named.
public enum FilmWorkout {
    /// One camera frame: seconds since the camera started and the body seen (nil = nobody).
    public typealias Frame = (time: Double, pose: FormPose?)

    /// A move the frames look like.
    public struct Guess: Sendable, Hashable {
        public let exerciseId: String
        /// Share of the top guesses' scores, 0–100: high only when one move stands out.
        public let confidence: Int
        /// Reps this move's model counted on the frames.
        public let reps: Int
    }

    /// Every move the camera can name: the catalog exercises with a form check model.
    public static let models: [FormModel] = Exercise.catalog.compactMap { FormModel(exercise: $0) }

    /// Extra score for a move planned today and for one logged lately (moves that look alike: the likely one wins).
    public static let planBoost = 0.25
    public static let recentBoost = 0.12
    /// Reps seen before the screen names the move.
    public static let repsToGuess = 2
    /// The top guess is taken without a tap after this many reps.
    public static let repsToAccept = 4

    /// The moves `frames` look like, best first. Each model counts reps over the same frames; a move scores by how close
    /// the bottom of its reps came to its guide (70 %) and how much of its range was reached (30 %).
    public static func guess(_ frames: [Frame], models: [FormModel], planned: Set<String> = [], recent: [String] = [],
                             limit: Int = 3) -> [Guess] {
        let recentSet = Set(recent.prefix(10))
        var scored: [(id: String, reps: Int, score: Double)] = []
        for m in models {
            var an = FormAnalyzer(model: m)
            for f in frames { an.add(f.pose, at: f.time) }
            let reps = an.reps
            guard !reps.isEmpty else { continue }
            let n = Double(reps.count)
            let match = Double(reps.map(\.match).reduce(0, +)) / n / 100
            let depth = reps.map { min(1, $0.depth) }.reduce(0, +) / n
            var s = match * 0.7 + depth * 0.3
            if planned.contains(m.exerciseId) { s += planBoost }
            if recentSet.contains(m.exerciseId) { s += recentBoost }
            scored.append((m.exerciseId, reps.count, s))
        }
        let top = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }.prefix(max(1, limit))
        let total = top.map(\.score).reduce(0, +)
        guard total > 0 else { return [] }
        return top.map { Guess(exerciseId: $0.id, confidence: Int(($0.score / total * 100).rounded()), reps: $0.reps) }
    }

    /// Seconds without a new rep (racked, resting, out of view) after which the set logs itself.
    public static let restAfter = 6.0

    /// The set is over: at least one rep and none for `restAfter` seconds.
    public static func setEnded(reps: Int, lastRepAt: Double?, now: Double) -> Bool {
        guard reps > 0, let lastRepAt else { return false }
        return now - lastRepAt >= restAfter
    }
}

/// A set the camera logged.
public struct FilmedSet: Sendable, Hashable, Codable {
    public var reps: Int
    public var kg: Double
    /// Form score 0–100; nil when the form check had nothing to say.
    public var form: Int?

    public init(reps: Int, kg: Double, form: Int? = nil) {
        self.reps = reps
        self.kg = kg
        self.form = form
    }
}

/// One exercise filmed: its sets in order.
public struct FilmedMove: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var exerciseId: String
    public var sets: [FilmedSet]

    public init(id: UUID = UUID(), exerciseId: String, sets: [FilmedSet] = []) {
        self.id = id
        self.exerciseId = exerciseId
        self.sets = sets
    }

    /// "3×8 · 60 kg"; mixed reps show the top set's.
    public var summary: String {
        guard let top = sets.max(by: { $0.kg != $1.kg ? $0.kg < $1.kg : $0.reps < $1.reps }) else { return "No sets" }
        let reps = Set(sets.map(\.reps)).count == 1 ? "\(top.reps)" : "\(sets.map(\.reps).max() ?? top.reps)"
        let kg = top.kg > 0 ? " · \(LoadAdvisor.formatKg(top.kg)) kg" : ""
        return "\(sets.count)×\(reps)\(kg)"
    }

    /// Average form of the sets that have one.
    public var form: Int? {
        let f = sets.compactMap(\.form)
        return f.isEmpty ? nil : Int((Double(f.reduce(0, +)) / Double(f.count)).rounded())
    }
}

/// The weight printed on a dumbbell, kettlebell, plate or machine label, read by the phone's text reader (#952).
public enum WeightReading {
    /// One piece of text the reader found and its height as a share of the frame (bigger print wins).
    public struct Seen: Sendable, Hashable {
        public let text: String
        public let size: Double
        public init(_ text: String, size: Double = 0.05) {
            self.text = text
            self.size = size
        }
    }

    public static let kgPerLb = 0.45359237

    /// The weight in kg, or nil when nothing looks like one. Pounds are converted and rounded to 0.5 kg. A number with
    /// a unit beats a bare one; then the biggest print; bare numbers must look like gym weights (0.5 steps, 1–200).
    public static func kg(from seen: [Seen]) -> Double? {
        var best: (kg: Double, score: Double)?
        for s in seen {
            for c in candidates(s.text) {
                var score = s.size * 10
                if c.unit != nil { score += 2 } else {
                    guard c.value >= 1, c.value <= 200, (c.value * 2).rounded() == c.value * 2 else { continue }
                }
                let kg = c.unit == .lb ? ((c.value * kgPerLb) * 2).rounded() / 2 : c.value
                guard kg >= 0.5, kg <= 400 else { continue }
                if best == nil || score > best!.score { best = (kg, score) }
            }
        }
        return best?.kg
    }

    enum Unit { case kg, lb }

    private static var pattern: NSRegularExpression { try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3}(?:[.,]\d{1,2})?)\s*(kgs?|lbs?|kilos?|pounds?)?(?![.,]?\d)"#, options: [.caseInsensitive]) }

    static func candidates(_ text: String) -> [(value: Double, unit: Unit?)] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let v = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")) else { return nil }
            let u = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2)).lowercased()
            let unit: Unit? = u.map { $0.hasPrefix("l") || $0.hasPrefix("p") ? .lb : .kg }
            return (v, unit)
        }
    }
}
