import Foundation

/// On-device Coach (#608, design A): which Ask Coach questions Apple's on-device model answers. Short training questions
/// (rest, form, weight, sets) stay on the phone: offline, instant, nothing sent. Asking for a workout goes to the server
/// Coach, which builds it from the member's gym.
public enum CoachRoute {
    private static let workoutWords: Set<String> = [
        "workout", "workouts", "session", "routine", "program", "programme", "plan", "build", "create", "generate",
        "min", "mins", "minute", "minutes", "today", "tomorrow", "week",
    ]
    private static let workoutPhrases = ["make me", "give me", "full body", "upper body", "lower body"]

    public static func onDevice(_ text: String) -> Bool {
        let t = text.lowercased()
        let words = t.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.count >= 2, words.count <= 25 else { return false }
        if words.contains(where: { workoutWords.contains($0) }) || workoutPhrases.contains(where: { t.contains($0) }) { return false }
        return true
    }
}

/// Instant recap (#608, design B): two lines on what happened and one tip for next time, the second a workout ends.
/// Built from the record here; the on-device model rewords `facts` when it can, this text is the fallback.
public struct WorkoutRecap: Equatable, Sendable {
    /// "PUSH DAY · 48′"
    public var title: String
    public var recap: String
    public var tip: String
    /// Plain facts for the on-device model.
    public var facts: [String]

    public init(title: String, recap: String, tip: String, facts: [String] = []) {
        self.title = title
        self.recap = recap
        self.tip = tip
        self.facts = facts
    }

    /// `history`: earlier workouts, any order; each exercise compares with the last time it was done.
    public static func build(_ r: WorkoutRecord, history: [WorkoutRecord]) -> WorkoutRecap? {
        let lifts = r.exercises.filter { $0.setsDone > 0 && ($0.weightKg ?? 0) > 0 && $0.category != .warmup }
        let earlier = history.filter { $0.id != r.id && $0.startedAt < r.startedAt }.sorted { $0.startedAt > $1.startedAt }
        func last(_ id: String) -> Double? {
            for h in earlier { if let e = h.exercises.first(where: { $0.exerciseId == id && $0.setsDone > 0 }), let w = e.weightKg, w > 0 { return w } }
            return nil
        }
        func name(_ id: String) -> String { Exercise.find(id)?.name ?? id }
        let title = "\(r.title.uppercased()) · \(max(1, r.durationSec / 60))′"
        guard r.totalSets > 0 else { return nil }

        var facts = ["\(r.totalSets) sets in \(max(1, r.durationSec / 60)) min"]
        var gains: [(name: String, delta: Double, kg: Double)] = []
        for e in lifts {
            let w = e.weightKg ?? 0
            let reps = e.reps.map { " × \(Int($0.rounded()))" } ?? ""
            if let before = last(e.exerciseId) {
                facts.append("\(name(e.exerciseId)): \(kg(w)) kg\(reps), last time \(kg(before)) kg, \(e.setsDone) of \(e.setsPlanned) sets")
                if w > before { gains.append((name(e.exerciseId), w - before, w)) }
            } else {
                facts.append("\(name(e.exerciseId)): \(kg(w)) kg\(reps), first time logged, \(e.setsDone) of \(e.setsPlanned) sets")
            }
        }
        let missed = r.exercises.filter { $0.setsDone > 0 && $0.setsDone < $0.setsPlanned && $0.category != .warmup }
        for m in missed.prefix(2) { facts.append("\(name(m.exerciseId)) stopped at \(m.setsDone) of \(m.setsPlanned) sets") }

        let first: String
        if let g = gains.max(by: { $0.delta < $1.delta }) {
            first = "\(g.name) +\(kg(g.delta)) kg vs last time."
        } else if r.volumeKg >= 1000 {
            first = String(format: "%.1f t lifted in %d sets.", r.volumeKg / 1000, r.totalSets)
        } else {
            first = "\(r.totalSets) sets in \(max(1, r.durationSec / 60)) min."
        }
        let second: String
        if let m = missed.first {
            second = "\(name(m.exerciseId)) stopped at \(m.setsDone) of \(m.setsPlanned) sets."
        } else if !lifts.isEmpty {
            second = "Every planned set done."
        } else {
            second = "Nice and steady."
        }

        let tip: String
        if let m = missed.first {
            tip = "Finish all \(m.setsPlanned) sets of \(name(m.exerciseId)) before adding weight."
        } else if let e = lifts.filter({ $0.setsDone >= $0.setsPlanned }).max(by: { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }), let w = e.weightKg {
            let step = w >= 20 ? 2.5 : 1
            tip = "Try \(kg(w + step)) kg on \(name(e.exerciseId))\(e.reps.map { " × \(Int($0.rounded()))" } ?? "")."
        } else {
            tip = "Same plan next time, one more rep on the last set."
        }
        return WorkoutRecap(title: title, recap: first + " " + second, tip: tip, facts: facts)
    }

    static func kg(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

/// Visual Intelligence (#617 C): what the camera saw (labels like "leg press", "dumbbell") → exercises for that
/// machine or kit, an exact exercise name first, main lifts before the rest.
public enum MachineMatch {
    public static func exercises(labels: [String], limit: Int = 10) -> [Exercise] {
        var out: [Exercise] = []
        func add(_ e: Exercise) { if !out.contains(where: { $0.id == e.id }) { out.append(e) } }
        for raw in labels {
            let label = clean(raw)
            guard label.count >= 3 else { continue }
            if let e = Exercise.named(label) { add(e) }
            for eq in Equipment.allCases where names(eq).contains(where: { label.contains($0) || ($0.contains(label) && label.count >= 5) }) {
                Exercise.search().filter { $0.equipment.contains(eq) }.sorted { $0.main && !$1.main }.forEach(add)
            }
        }
        return Array(out.prefix(limit))
    }

    private static func clean(_ s: String) -> String {
        var t = s.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        if t.hasSuffix("s"), !t.hasSuffix("ss"), t.count > 4 { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// "Barbell & plates" → "barbell", "Squat/power rack" → "squat", "power rack"; singular.
    private static func names(_ eq: Equipment) -> [String] {
        let label = eq.label.lowercased()
        var out = [eq.rawValue.replacingOccurrences(of: "-", with: " ")]
        out += label.components(separatedBy: CharacterSet(charactersIn: "&/(),")).map { $0.trimmingCharacters(in: .whitespaces) }
        return out.map(clean).filter { $0.count >= 4 }
    }
}
