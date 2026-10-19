import Foundation

// MARK: - Daily auto-tune (#495, option B)

/// How hard today's workout goes.
public enum TuneLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case light, medium, push
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .push: "Push"
        }
    }

    public var rule: String {
        switch self {
        case .light: "1 RPE lower, one set less on accessories"
        case .medium: "As planned"
        case .push: "One more set on the main lift"
        }
    }
}

/// What today's verdict is made from. Recovery markers come from Apple Health; nil when Health has none.
public struct TuneInputs: Sendable, Hashable {
    public var hrv: Double?
    public var hrvBaseline: Double?
    public var restingHR: Double?
    public var restingHRBaseline: Double?
    public var sleepHours: Double?
    /// Average reps in reserve of the last workout's logged sets.
    public var lastRIR: Double?
    /// Days trained in a row up to yesterday.
    public var daysInARow: Int
    /// Muscle groups the member tapped as sore.
    public var sore: Set<MuscleGroup>

    public init(hrv: Double? = nil, hrvBaseline: Double? = nil, restingHR: Double? = nil, restingHRBaseline: Double? = nil,
                sleepHours: Double? = nil, lastRIR: Double? = nil, daysInARow: Int = 0, sore: Set<MuscleGroup> = []) {
        self.hrv = hrv
        self.hrvBaseline = hrvBaseline
        self.restingHR = restingHR
        self.restingHRBaseline = restingHRBaseline
        self.sleepHours = sleepHours
        self.lastRIR = lastRIR
        self.daysInARow = daysInARow
        self.sore = sore
    }

    public var hasRecovery: Bool { hrv != nil || restingHR != nil || sleepHours != nil }
}

/// One thing that moved the score, e.g. "Sleep · 5.7 h · −13".
public struct TuneFactor: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var points: Int
}

public struct TuneVerdict: Hashable, Sendable {
    /// 5…100.
    public var score: Int
    public var level: TuneLevel
    public var factors: [TuneFactor]
    /// One line: the factors that took points off, e.g. "Short sleep, legs sore".
    public var reason: String
}

public enum AutoTune {
    static let base = 80
    /// Under this: Light. From `pushFrom` (with Health data): Push. Medium between.
    public static let lightBelow = 50
    public static let pushFrom = 85

    public static func assess(_ i: TuneInputs) -> TuneVerdict {
        var f: [TuneFactor] = []
        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, v)) }
        if let h = i.hrv, let b = i.hrvBaseline, b > 0 {
            let pts = clamp(Int(((h / b - 1) * 100).rounded()), -30, 10)
            f.append(TuneFactor(id: "hrv", title: "HRV", detail: "\(Int(h)) ms · normal \(Int(b))", points: pts))
        }
        if let r = i.restingHR, let b = i.restingHRBaseline, b > 0 {
            let pts = clamp(-Int(((r - b) * 3).rounded()), -20, 5)
            f.append(TuneFactor(id: "rhr", title: "Resting HR", detail: "\(Int(r)) bpm · normal \(Int(b))", points: pts))
        }
        if let s = i.sleepHours {
            let pts = s < 7 ? max(-25, -Int(((7 - s) * 10).rounded())) : s >= 8 ? 5 : 0
            f.append(TuneFactor(id: "sleep", title: "Sleep", detail: String(format: "%.1f h last night", s), points: pts))
        }
        if let rir = i.lastRIR {
            let pts = rir <= 1 ? -8 : rir >= 3 ? 3 : 0
            f.append(TuneFactor(id: "effort", title: "Last workout", detail: rir <= 1 ? "Hard, near failure" : rir >= 3 ? "Easy" : "Normal effort", points: pts))
        }
        if i.daysInARow >= 2 {
            f.append(TuneFactor(id: "streak", title: "Days in a row", detail: "\(i.daysInARow) days trained", points: -min(12, 6 * (i.daysInARow - 1))))
        }
        if !i.sore.isEmpty {
            let names = MuscleGroup.allCases.filter { i.sore.contains($0) }.map(\.label).joined(separator: ", ")
            f.append(TuneFactor(id: "sore", title: "Sore", detail: names, points: -min(18, 6 * i.sore.count)))
        }
        let score = clamp(base + f.reduce(0) { $0 + $1.points }, 5, 100)
        let level: TuneLevel = score < lightBelow ? .light : (score >= pushFrom && i.hasRecovery ? .push : .medium)
        let low = f.filter { $0.points < 0 }.sorted { $0.points < $1.points }.map { factor -> String in
            switch factor.id {
            case "hrv": "HRV low"
            case "rhr": "resting HR up"
            case "sleep": "short sleep"
            case "effort": "last workout was hard"
            case "streak": "\(i.daysInARow) days in a row"
            default: "\(factor.detail.lowercased()) sore"
            }
        }
        let reason = low.isEmpty ? (level == .push ? "Recovered and fresh" : "Nothing off today") : low.prefix(2).joined(separator: ", ")
        return TuneVerdict(score: score, level: level, factors: f, reason: reason.prefix(1).uppercased() + reason.dropFirst())
    }
}

/// One change auto-tune made to today's session; the member can undo each.
public struct TuneChange: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case dropSet, addSet, swap, easier
    }

    public var kind: Kind
    public var uid: String
    public var exerciseId: String
    /// Swap target.
    public var to: String?
    public var fromSets: Int?
    public var toSets: Int?
    public var id: String { "\(kind.rawValue)-\(uid)" }
}

extension Session {
    /// Today's session tuned to `level` and the sore muscle groups. Changes in `undone` are left out.
    /// Sore: a move loading a sore group swaps to one that doesn't (one set less when none fits).
    /// Light: 1 RPE lower on the main lift, one set less on accessories. Push: one more set on the main lift
    /// (not in a deload week).
    public func autoTuned(
        _ level: TuneLevel, sore: Set<MuscleGroup>, profile: Profile, deload: Bool = false, undone: Set<String> = []
    ) -> (session: Session, changes: [TuneChange]) {
        var s = self
        var changes: [TuneChange] = []
        var used = Set(blocks.flatMap(\.items).map(\.exerciseId))
        for b in s.blocks.indices where s.blocks[b].kind == .strength || s.blocks[b].kind == .power {
            let kind = s.blocks[b].kind
            let floor = kind == .power ? 2 : 1
            for i in s.blocks[b].items.indices {
                var it = s.blocks[b].items[i]
                let isMain = kind == .strength && i == 0
                let groups = Set(Exercise.find(it.exerciseId)?.primary.map(\.group) ?? [])
                func apply(_ c: TuneChange, _ edit: (inout PlannedExercise) -> Void) {
                    guard !undone.contains(c.id) else { return }
                    edit(&it)
                    changes.append(c)
                }
                func setsTo(_ n: Int) -> (inout PlannedExercise) -> Void {
                    { item in
                        let perSet = Double(item.estSec) / Double(max(1, item.prescription.sets))
                        item.estSec = max(0, item.estSec + Int((perSet * Double(n - item.prescription.sets)).rounded()))
                        item.prescription.sets = n
                    }
                }
                let sets = it.prescription.sets
                if !sore.isEmpty && !groups.isDisjoint(with: sore) {
                    let option = Exercise.find(it.exerciseId)?.swapOptions(for: profile, excluding: used)
                        .first { Set($0.primary.map(\.group)).isDisjoint(with: sore) }
                    if let option {
                        let c = TuneChange(kind: .swap, uid: it.uid, exerciseId: it.exerciseId, to: option.id)
                        apply(c) { $0.exerciseId = option.id }
                        if !undone.contains(c.id) { used.insert(option.id) }
                    } else if sets > floor {
                        apply(TuneChange(kind: .dropSet, uid: it.uid, exerciseId: it.exerciseId, fromSets: sets, toSets: sets - 1), setsTo(sets - 1))
                    }
                } else if level == .light {
                    if isMain, let rpe = it.prescription.rpeValue, rpe > 5 {
                        apply(TuneChange(kind: .easier, uid: it.uid, exerciseId: it.exerciseId)) {
                            $0.prescription.intensity = $0.prescription.intensity?.replacingOccurrences(of: "RPE \(rpe)", with: "RPE \(rpe - 1)")
                        }
                    } else if !isMain && sets > floor {
                        apply(TuneChange(kind: .dropSet, uid: it.uid, exerciseId: it.exerciseId, fromSets: sets, toSets: sets - 1), setsTo(sets - 1))
                    }
                } else if level == .push && isMain && !deload {
                    apply(TuneChange(kind: .addSet, uid: it.uid, exerciseId: it.exerciseId, fromSets: sets, toSets: sets + 1), setsTo(sets + 1))
                }
                s.blocks[b].items[i] = it
            }
        }
        if !changes.isEmpty {
            s.estMin = Int(s.blocks.reduce(0) { $0 + $1.estMin }.rounded())
        }
        return (s, changes)
    }
}

extension WeekPlan {
    /// The plan with the sessions in `ids` tuned, and every change made.
    public func autoTuned(_ ids: Set<String>, level: TuneLevel, sore: Set<MuscleGroup>, profile: Profile, undone: Set<String> = []) -> (plan: WeekPlan, changes: [TuneChange]) {
        guard !ids.isEmpty else { return (self, []) }
        var p = self
        var all: [TuneChange] = []
        for k in p.sessions.indices where ids.contains(p.sessions[k].id) {
            let t = p.sessions[k].autoTuned(level, sore: sore, profile: profile, deload: deload, undone: undone)
            p.sessions[k] = t.session
            all += t.changes
        }
        return (p, all)
    }
}
