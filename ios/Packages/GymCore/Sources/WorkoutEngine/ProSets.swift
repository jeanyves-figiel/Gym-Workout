import Foundation

// Pro Sets (#499, design B from `expert-lifters/proposals.png`): set styles expert lifters use, per exercise, in the
// player: top set + back-offs, AMRAP, drop sets, myo-reps, rest-pause, clusters and % of 1RM. Warm-up ramp and plate
// maths for barbell work.

/// How the sets of one exercise are done. Chosen per exercise; `straight` is the plan as generated.
public enum SetStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case straight, topBackoff, amrap, drop, myoRep, restPause, cluster, percent

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .straight: "Straight sets"
        case .topBackoff: "Top set + back-offs"
        case .amrap: "AMRAP last set"
        case .drop: "Drop sets"
        case .myoRep: "Myo-reps"
        case .restPause: "Rest-pause"
        case .cluster: "Cluster sets"
        case .percent: "% of 1RM"
        }
    }

    public var short: String {
        switch self {
        case .straight: "Straight"
        case .topBackoff: "Top+back-off"
        case .amrap: "AMRAP"
        case .drop: "Drop"
        case .myoRep: "Myo-rep"
        case .restPause: "Rest-pause"
        case .cluster: "Cluster"
        case .percent: "% 1RM"
        }
    }

    public var symbol: String {
        switch self {
        case .straight: "equal"
        case .topBackoff: "chart.bar.xaxis"
        case .amrap: "plus.circle.fill"
        case .drop: "arrow.down.right"
        case .myoRep: "bolt.fill"
        case .restPause: "pause.circle.fill"
        case .cluster: "square.grid.3x1.below.line.grid.1x2"
        case .percent: "percent"
        }
    }

    public var blurb: String {
        switch self {
        case .straight: "Same weight every set, as the plan says."
        case .topBackoff: "One heavy set at RPE 8, then lighter back-offs. Rate the top set and the back-offs follow."
        case .amrap: "Last set as many reps as you can, 1-2 left in the tank."
        case .drop: "Last set then 2 drops of 20% with no rest."
        case .myoRep: "One activation set, then 4 mini sets of 3-5 reps with 15 s rest."
        case .restPause: "Last set to near failure, 20 s rest, 2 more mini sets."
        case .cluster: "5% heavier, each set split in minis with 20 s rest."
        case .percent: "Weight from your estimated 1RM, leaving 2 reps in reserve."
        }
    }
}

/// What a planned set is for; drives its tag and rest.
public enum SetRole: String, Codable, Sendable {
    case work, top, backoff, amrap, drop, activation, mini, cluster, attempt

    public var tag: String? {
        switch self {
        case .work: nil
        case .top: "TOP"
        case .backoff: "BACK-OFF"
        case .amrap: "AMRAP"
        case .drop: "DROP"
        case .activation: "ACTIVATION"
        case .mini: "MINI"
        case .cluster: "CLUSTER"
        case .attempt: "ATTEMPT"
        }
    }
}

/// One set as planned: what to load (nil = the usual suggestion), reps and the rest after it.
public struct PlannedSet: Hashable, Sendable {
    public var role: SetRole
    public var kg: Double?
    public var reps: Int?
    /// "5+", "3-5", "6 (3+3)": what the set asks, as shown.
    public var target: String
    public var restSec: Int
    /// Short line under the set, e.g. "−10% of top" or "Opener".
    public var note: String?

    public init(role: SetRole, kg: Double?, reps: Int?, target: String, restSec: Int, note: String? = nil) {
        self.role = role
        self.kg = kg
        self.reps = reps
        self.target = target
        self.restSec = restSec
        self.note = note
    }
}

public enum ProSets {
    /// Loaded strength in reps: the only exercises set styles and Lift Focus apply to.
    public static func eligible(_ e: Exercise) -> Bool {
        PRPlanner.eligible(e) && !PRPlanner.isBodyweight(e) && !e.equipment.isEmpty
    }

    /// Share of 1RM that can be lifted for `n` reps to failure (inverse Epley, the formula LoadAdvisor uses).
    public static func percentOf1RM(repsToFailure n: Int) -> Double {
        n <= 1 ? 1 : 1 / (1 + Double(n) / 30)
    }

    /// Estimated 1RM from a set and its reps in reserve (RPE-style).
    public static func oneRepMax(kg: Double, reps: Int, rir: Int?) -> Double? {
        guard kg > 0, reps >= 1 else { return nil }
        let n = reps + max(0, rir ?? 0)
        guard n <= 15 else { return nil }
        return kg / percentOf1RM(repsToFailure: n)
    }

    /// Load for `reps` with `rir` in reserve from an estimated 1RM, rounded down to the equipment step.
    public static func load(oneRepMax: Double, reps: Int, rir: Int, exercise e: Exercise) -> Double {
        let raw = oneRepMax * percentOf1RM(repsToFailure: reps + rir)
        return LoadAdvisor.round(raw, to: LoadAdvisor.steps(for: e, kg: raw).granularity, .down)
    }

    /// Back-off load once the top set is done: from the top set's effort when rated, else 10% under it.
    public static func backoffKg(topKg: Double, topReps: Int, topRIR: Int?, backoffReps: Int, exercise e: Exercise) -> Double {
        let step = LoadAdvisor.steps(for: e, kg: topKg).granularity
        guard let rir = topRIR, let orm = oneRepMax(kg: topKg, reps: topReps, rir: rir) else {
            return LoadAdvisor.round(topKg * 0.9, to: step, .down)
        }
        // Back-offs leave 3 in reserve, never heavier than the top set.
        return min(topKg, load(oneRepMax: orm, reps: backoffReps, rir: 3, exercise: e))
    }

    /// The prescription as the style does it: set count and the intensity line. Straight leaves it as is.
    public static func styled(_ p: Prescription, _ style: SetStyle) -> Prescription {
        guard style != .straight, let range = p.repRange else { return p }
        var out = p
        let s = max(1, p.sets)
        switch style {
        case .straight: break
        case .topBackoff:
            out.sets = max(3, s)
            out.intensity = "Top set RPE 8, then back-offs"
        case .amrap:
            out.intensity = "Last set AMRAP"
        case .drop:
            out.sets = s + 2
            out.intensity = "Last set + 2 drops"
        case .myoRep:
            out.sets = 5
            out.intensity = "Myo-reps: \(max(range.high, 12)) then minis of 3-5"
        case .restPause:
            out.sets = s + 2
            out.intensity = "Last set rest-pause"
        case .cluster:
            out.intensity = "Cluster: minis, 20 s rest"
        case .percent:
            out.intensity = "% of 1RM, 2 in reserve"
        }
        return out
    }

    /// Sets of one exercise in the style. `p`: the prescription already `styled` (as the plan has it); one entry per set.
    /// `workingKg`: the usual suggestion; `oneRepMax`: estimated, for % of 1RM.
    public static func sets(_ style: SetStyle, prescription p: Prescription, workingKg: Double?,
                            oneRepMax: Double?, exercise e: Exercise) -> [PlannedSet] {
        let range = p.repRange ?? RepRange(low: 8, high: 8)
        let rest = p.restSec
        let n = max(1, p.sets)
        let step = LoadAdvisor.steps(for: e, kg: workingKg ?? 20).granularity
        func r(_ kg: Double?) -> Double? { kg.map { LoadAdvisor.round($0, to: step) } }
        func work(_ i: Int) -> PlannedSet {
            PlannedSet(role: .work, kg: workingKg, reps: range.low, target: p.reps, restSec: rest)
        }
        switch style {
        case .straight:
            return (0..<n).map(work)
        case .topBackoff:
            let top = r(workingKg.map { $0 * 1.05 })
            let back = top.map { backoffKg(topKg: $0, topReps: range.low, topRIR: nil, backoffReps: range.low, exercise: e) }
            let first = PlannedSet(role: .top, kg: top, reps: range.low, target: "\(range.low) @ RPE 8", restSec: max(rest, 150))
            let backoffs: [PlannedSet] = (1..<n).map { _ in
                PlannedSet(role: .backoff, kg: back, reps: range.low, target: "\(range.low)", restSec: rest, note: "−10% of top")
            }
            return [first] + backoffs
        case .amrap:
            return (0..<n).map { i -> PlannedSet in
                i == n - 1 ? PlannedSet(role: .amrap, kg: workingKg, reps: range.low, target: "\(range.low)+", restSec: rest,
                                        note: "As many as you can, 1-2 in the tank")
                    : work(i)
            }
        case .drop:
            guard n >= 3 else { return (0..<n).map(work) }
            let base = n - 2
            let w = workingKg
            let head: [PlannedSet] = (0..<base).map { i -> PlannedSet in
                var s = work(i)
                if i == base - 1 { s.restSec = 0 }
                return s
            }
            return head + [
                PlannedSet(role: .drop, kg: r(w.map { $0 * 0.8 }), reps: range.low, target: "max", restSec: 0, note: "−20%, no rest"),
                PlannedSet(role: .drop, kg: r(w.map { $0 * 0.64 }), reps: range.low, target: "max", restSec: rest, note: "−20% again"),
            ]
        case .myoRep:
            let kg = r(workingKg.map { $0 * 0.85 })
            let act = max(range.high, 12)
            let first = PlannedSet(role: .activation, kg: kg, reps: act, target: "\(act)-\(act + 3)", restSec: 20,
                                   note: "1-2 in the tank")
            let minis: [PlannedSet] = (1..<n).map { i in
                PlannedSet(role: .mini, kg: kg, reps: 4, target: "3-5", restSec: i == n - 1 ? rest : 15, note: "Same weight")
            }
            return [first] + minis
        case .restPause:
            guard n >= 3 else { return (0..<n).map(work) }
            let base = n - 2
            let head: [PlannedSet] = (0..<base).map { i -> PlannedSet in
                var s = work(i)
                if i == base - 1 {
                    s.restSec = 20
                    s.note = "Near failure"
                }
                return s
            }
            return head + [
                PlannedSet(role: .mini, kg: workingKg, reps: 3, target: "max", restSec: 20, note: "20 s pause"),
                PlannedSet(role: .mini, kg: workingKg, reps: 2, target: "max", restSec: rest, note: "Last one"),
            ]
        case .cluster:
            let mini = max(1, range.low / 3 + (range.low % 3 == 0 ? 0 : 1))
            let parts = (range.low + mini - 1) / mini
            let split = Array(repeating: "\(mini)", count: parts).joined(separator: "+")
            return (0..<n).map { _ in
                PlannedSet(role: .cluster, kg: r(workingKg.map { $0 * 1.05 }), reps: range.low, target: "\(range.low) (\(split))",
                           restSec: rest, note: "20 s between minis")
            }
        case .percent:
            let kg = oneRepMax.map { load(oneRepMax: $0, reps: range.low, rir: 2, exercise: e) } ?? workingKg
            let pct = Int((percentOf1RM(repsToFailure: range.low + 2) * 100).rounded())
            return (0..<n).map { _ in
                PlannedSet(role: .work, kg: kg, reps: range.low, target: p.reps, restSec: rest, note: oneRepMax == nil ? nil : "\(pct)% of 1RM")
            }
        }
    }

    /// Warm-up sets before the first working set of a heavy barbell lift (≥ 40 kg): empty bar, then steps toward it.
    public static func warmups(to kg: Double, exercise e: Exercise) -> [RampStep] {
        guard kg >= 40, let bar = Plates.barKg(for: e) else { return [] }
        let s = LoadAdvisor.steps(for: e, kg: kg).granularity
        var out = [RampStep(kg: bar, reps: 10)]
        for (pct, reps) in [(0.5, 5), (0.7, 3), (0.85, 1)] {
            let w = LoadAdvisor.round(kg * pct, to: s)
            if w > (out.last?.kg ?? 0) && w < kg { out.append(RampStep(kg: w, reps: reps)) }
        }
        return out
    }
}

/// Plates to load per side of a barbell.
public enum Plates {
    public static let standard: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    /// Bar weight for barbell and trap-bar lifts; nil for everything else (machines, dumbbells, Smith).
    public static func barKg(for e: Exercise) -> Double? {
        let eq = Set(e.equipment)
        if eq.contains(.trapBar) { return 25 }
        if eq.contains(.barbell) && !eq.contains(.smith) { return 20 }
        return nil
    }

    /// Plates per side, heaviest first, for `total` on a `bar`. nil when `total` is below the bar or can't be made exactly.
    public static func perSide(total: Double, bar: Double, plates: [Double] = standard) -> [Double]? {
        guard total >= bar else { return nil }
        var left = (total - bar) / 2
        var out: [Double] = []
        for p in plates.sorted(by: >) {
            while left + 1e-6 >= p {
                out.append(p)
                left -= p
            }
        }
        return abs(left) < 1e-6 ? out : nil
    }
}

extension WeekPlan {
    /// Set styles the member picked per exercise (#499) applied to every loaded strength item not in a superset.
    public func applyingSetStyles(_ styles: [String: SetStyle]) -> WeekPlan {
        guard !styles.isEmpty else { return self }
        var p = self
        for s in p.sessions.indices {
            for b in p.sessions[s].blocks.indices where p.sessions[s].blocks[b].kind == .strength {
                for i in p.sessions[s].blocks[b].items.indices {
                    var it = p.sessions[s].blocks[b].items[i]
                    guard let style = styles[it.exerciseId], style != .straight, it.group == nil, it.supersetWith == nil,
                          let e = Exercise.find(it.exerciseId), ProSets.eligible(e) else { continue }
                    let before = max(1, it.prescription.sets)
                    it.prescription = ProSets.styled(it.prescription, style)
                    it.estSec = it.estSec * it.prescription.sets / before
                    p.sessions[s].blocks[b].items[i] = it
                }
            }
        }
        return p
    }
}
