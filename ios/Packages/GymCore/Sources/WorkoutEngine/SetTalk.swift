import Foundation

/// Talk to Coach mid-set (#874, design A + C from `ai-epic/b1.png`): the member holds the mic in Up next and says
/// "too heavy?" or "felt it in my lower back"; Coach answers out loud with the set on screen, this workout's sets and
/// last time in mind, and offers up to two one-tap fixes (lighter / heavier weight, swap, rest). Common questions are
/// answered here by rules (instant, offline); others go to the on-device model, then the server Coach (Pro).

/// What Coach knows about the set on screen. No identifiers besides exercise ids.
public struct SetTalkContext: Codable, Equatable, Sendable {
    public struct Logged: Codable, Equatable, Sendable {
        public var kg: Double
        public var reps: Int
        public var rir: Int?

        public init(kg: Double, reps: Int, rir: Int? = nil) {
            self.kg = kg
            self.reps = reps
            self.rir = rir
        }
    }

    public struct Option: Codable, Equatable, Sendable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var exercise: String
    /// Coming set, from 1.
    public var set: Int
    public var sets: Int
    public var kg: Double?
    public var reps: Int?
    /// Weight step of the kg stepper (2.5 barbell, 1 dumbbell …).
    public var step: Double
    /// Sets of this exercise already done in this workout.
    public var done: [Logged]
    /// "97.5 kg × 5" last time, if any.
    public var lastTime: String?
    /// Planned rest between sets.
    public var restSec: Int?
    /// Swaps for the same muscles with the member's kit, best first (at most 4).
    public var swaps: [Option]

    public init(exercise: String, set: Int, sets: Int, kg: Double?, reps: Int?, step: Double = 2.5, done: [Logged] = [],
                lastTime: String? = nil, restSec: Int? = nil, swaps: [Option] = []) {
        self.exercise = exercise
        self.set = set
        self.sets = sets
        self.kg = kg
        self.reps = reps
        self.step = step
        self.done = done
        self.lastTime = lastTime
        self.restSec = restSec
        self.swaps = Array(swaps.prefix(4))
    }

    /// The context as lines for a model.
    public var facts: String {
        var lines = ["Exercise: \(exercise), set \(set) of \(sets)"]
        if let kg { lines.append("Coming set: \(SetTalk.kg(kg)) kg\(reps.map { " × \($0)" } ?? "")") } else if let reps { lines.append("Coming set: \(reps) reps") }
        for (i, d) in done.enumerated() {
            lines.append("Set \(i + 1) done: \(SetTalk.kg(d.kg)) kg × \(d.reps)\(d.rir.map { ", \($0) reps in reserve" } ?? "")")
        }
        if let lastTime { lines.append("Last time: \(lastTime)") }
        if let restSec { lines.append("Planned rest: \(restSec) s") }
        if !swaps.isEmpty { lines.append("Swaps: " + swaps.map { "\($0.name) (id \($0.id))" }.joined(separator: ", ")) }
        lines.append("Weight step: \(SetTalk.kg(step)) kg")
        return lines.joined(separator: "\n")
    }
}

/// A one-tap fix under Coach's answer.
public enum SetTalkAction: Codable, Equatable, Hashable, Sendable {
    case weight(Double)
    case swap(id: String, name: String)
    case rest(Int)

    public var label: String {
        switch self {
        case let .weight(kg): return "Use \(SetTalk.kg(kg)) kg"
        case let .swap(_, name): return "Swap to \(name.lowercased())"
        case let .rest(sec): return "Rest \(sec / 60):\(String(format: "%02d", sec % 60))"
        }
    }

    public var symbol: String {
        switch self {
        case .weight: return "scalemass.fill"
        case .swap: return "arrow.triangle.2.circlepath"
        case .rest: return "timer"
        }
    }
}

/// Wire shape of a fix, as the server and the on-device model give it: kind "weight" (kg), "swap" (exerciseId),
/// "rest" (sec); anything else is dropped by `SetTalk.cleaned`.
public struct SetTalkWireAction: Codable, Equatable, Sendable {
    public var kind: String
    public var kg: Double?
    public var exerciseId: String?
    public var sec: Int?

    public init(kind: String, kg: Double? = nil, exerciseId: String? = nil, sec: Int? = nil) {
        self.kind = kind
        self.kg = kg
        self.exerciseId = exerciseId
        self.sec = sec
    }
}

public struct SetTalkWireAnswer: Codable, Equatable, Sendable {
    public var answer: String
    public var actions: [SetTalkWireAction]

    public init(answer: String, actions: [SetTalkWireAction] = []) {
        self.answer = answer
        self.actions = actions
    }
}

public struct SetTalkAnswer: Equatable, Sendable {
    public enum Source: String, Sendable { case rules, onDevice, server }

    public var heard: String
    public var text: String
    public var actions: [SetTalkAction]
    public var source: Source

    public init(heard: String, text: String, actions: [SetTalkAction] = [], source: Source) {
        self.heard = heard
        self.text = text
        self.actions = actions
        self.source = source
    }
}

public enum SetTalk {
    private static let painWords: Set<String> = [
        "pain", "painful", "hurt", "hurts", "hurting", "sore", "pinch", "pinched", "pinching", "sharp", "twinge", "tweak",
        "tweaked", "strain", "strained", "back", "knee", "knees", "shoulder", "shoulders", "elbow", "wrist", "hip", "neck",
    ]
    private static let heavyWords: Set<String> = ["heavy", "hard", "tough", "grind", "grinding", "failed", "fail", "struggle", "struggling", "much"]
    private static let lightWords: Set<String> = ["light", "easy", "easier", "more"]
    private static let restWords: Set<String> = ["rest", "break", "wait", "breather", "recover"]

    /// Instant answers for the questions members ask most; nil = ask a model.
    public static func rules(_ question: String, _ c: SetTalkContext) -> SetTalkAnswer? {
        // "Back squat" or "shoulder press" in the question aren't a body part.
        let t = question.lowercased().replacingOccurrences(of: c.exercise.lowercased(), with: " ")
        let words = Set(t.split { !$0.isLetter }.map(String.init))
        let lower = c.kg.map { round(max(c.step, $0 * 0.9), step: c.step) }
        if !words.isDisjoint(with: painWords) {
            var actions: [SetTalkAction] = []
            if let lower, let kg = c.kg, lower < kg { actions.append(.weight(lower)) }
            if let s = c.swaps.first { actions.append(.swap(id: s.id, name: s.name)) }
            let drop = lower.map { "Drop to \(kg($0)) kg and" } ?? "Go lighter and"
            return SetTalkAnswer(heard: question, text: "\(drop) brace harder, slow on the way down. If it's sharp pain, stop this one\(c.swaps.isEmpty ? "" : " and swap") and get it checked.",
                                 actions: actions, source: .rules)
        }
        if words.contains("too") || t.contains("should i") || t.contains("go up") || t.contains("go down") {
            if !words.isDisjoint(with: heavyWords), let kg = c.kg, let lower = c.kg.map({ round(max(c.step, $0 - max(c.step, $0 * 0.05)), step: c.step) }), lower < kg {
                return SetTalkAnswer(heard: question, text: "Drop to \(SetTalk.kg(lower)) kg and keep every rep clean. Speed beats grinding.",
                                     actions: [.weight(lower)], source: .rules)
            }
            if !words.isDisjoint(with: lightWords) || t.contains("go up"), let kg = c.kg, lastLeftReps(c) {
                let up = round(kg + max(c.step, kg * 0.025), step: c.step)
                return SetTalkAnswer(heard: question, text: "Reps look easy. Go to \(SetTalk.kg(up)) kg, same reps.", actions: [.weight(up)], source: .rules)
            }
        }
        if !words.isDisjoint(with: restWords) {
            let sec = restFor(c)
            let heavy = (c.reps ?? 10) <= 6
            return SetTalkAnswer(heard: question, text: "Take \(sec / 60):\(String(format: "%02d", sec % 60))\(heavy ? ", heavy set coming." : ", then go.")",
                                 actions: [.rest(sec)], source: .rules)
        }
        return nil
    }

    /// Keeps fixes that fit the set on screen: a weight within 60–130 % of the coming set, on the stepper's grid; a swap
    /// from `swaps` only; rest 30 s – 10 min. One fix per kind, at most two.
    public static func cleaned(_ wire: SetTalkWireAnswer, heard: String, context c: SetTalkContext, source: SetTalkAnswer.Source) -> SetTalkAnswer? {
        let text = wire.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var out: [SetTalkAction] = []
        var kinds: Set<String> = []
        for a in wire.actions where out.count < 2 && !kinds.contains(a.kind) {
            switch a.kind {
            case "weight":
                guard let kg = a.kg, kg > 0, let now = c.kg, now > 0 else { continue }
                let r = round(kg, step: c.step)
                guard r >= now * 0.6, r <= now * 1.3, r != now else { continue }
                out.append(.weight(r))
            case "swap":
                guard let s = c.swaps.first(where: { $0.id == a.exerciseId }) else { continue }
                out.append(.swap(id: s.id, name: s.name))
            case "rest":
                guard let sec = a.sec else { continue }
                out.append(.rest(min(600, max(30, (sec / 15) * 15))))
            default: continue
            }
            kinds.insert(a.kind)
        }
        return SetTalkAnswer(heard: heard, text: String(text.prefix(240)), actions: out, source: source)
    }

    static func restFor(_ c: SetTalkContext) -> Int {
        if let r = c.restSec, r >= 30 { return min(600, r + ((c.done.last?.rir ?? 2) <= 1 ? 30 : 0)) }
        switch c.reps ?? 10 {
        case ...5: return 180
        case ...8: return 150
        case ...12: return 90
        default: return 60
        }
    }

    /// The last set left 3+ reps in reserve, or nothing logged yet to say otherwise.
    private static func lastLeftReps(_ c: SetTalkContext) -> Bool {
        guard let last = c.done.last else { return true }
        return (last.rir ?? 3) >= 3
    }

    static func round(_ kg: Double, step: Double) -> Double {
        let s = step > 0 ? step : 2.5
        return (kg / s).rounded() * s
    }

    static func kg(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}
