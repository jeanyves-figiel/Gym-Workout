import Foundation

// Lift Focus (#499, design A from `expert-lifters/proposals.png`): one lift, a target and a test day. The block's
// sessions of that lift follow a peaking template (% of the working max, deloads, taper, test with attempts); the rest
// of the plan can drop to maintenance volume; weak-point accessories follow the focus lift.

/// The peaking template of a Lift Focus block.
public enum FocusTemplate: String, Codable, CaseIterable, Sendable, Identifiable {
    case monkeyPeak, wave531, gzcl, smolovJr

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .monkeyPeak: "Monkey peak"
        case .wave531: "5/3/1 wave"
        case .gzcl: "GZCL T1"
        case .smolovJr: "Smolov Jr"
        }
    }

    public var blurb: String {
        switch self {
        case .monkeyPeak: "Waves from 72% to 92%, deload every 4th week, taper, test. Twice a week."
        case .wave531: "5s, 3s, 5/3/1 weeks at 90% training max, last set AMRAP, 5×5 back-offs. Once a week."
        case .gzcl: "Heavy T1: 5×3, 6×2, 10×1, deload. Plus a lighter 3×8 day. Twice a week."
        case .smolovJr: "3 hard weeks, 4 sessions of the lift a week, +2.5% a week. Short and brutal."
        }
    }

    /// Block lengths offered, test week included.
    public var lengths: [Int] {
        switch self {
        case .monkeyPeak: [8, 10, 12]
        case .wave531, .gzcl: [5, 9, 13]
        case .smolovJr: [4]
        }
    }

    /// Sessions of the focus lift per week (fewer when the week has fewer workouts).
    public var perWeek: Int {
        switch self {
        case .monkeyPeak, .gzcl: 2
        case .wave531: 1
        case .smolovJr: 4
        }
    }
}

/// Where the lift stalls: picks the weak-point accessories.
public enum WeakPoint: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, bottom, lockout

    public var id: String { rawValue }

    public func label(for exerciseId: String) -> String {
        switch self {
        case .none: return "No helpers"
        case .bottom:
            switch LiftFocus.family(exerciseId) ?? "" {
            case "bench": return "Off the chest"
            case "squat": return "Out of the hole"
            case "deadlift": return "Off the floor"
            default: return "Bottom"
            }
        case .lockout: return "Lockout"
        }
    }
}

/// Phase of a block week.
public enum FocusPhase: String, Codable, Sendable {
    case build, deload, taper, test

    public var label: String {
        switch self {
        case .build: "Build"
        case .deload: "Deload"
        case .taper: "Taper"
        case .test: "Test"
        }
    }
}

/// One set of the template, as a share of the working max.
public struct FocusSet: Hashable, Sendable {
    public var pct: Double
    public var reps: Int
    public var amrap: Bool

    public init(_ pct: Double, _ reps: Int, amrap: Bool = false) {
        self.pct = pct
        self.reps = reps
        self.amrap = amrap
    }
}

public struct LiftFocus: Codable, Hashable, Sendable {
    public var exerciseId: String
    public var targetKg: Double
    /// Monday of block week 1 (start of day).
    public var start: Date
    public var weeks: Int
    public var template: FocusTemplate
    /// Estimated 1RM when the block started.
    public var startOneRepMax: Double
    public var weakPoint: WeakPoint
    /// Other strength work drops to maintenance volume (−30% sets).
    public var maintenance: Bool

    public init(exerciseId: String, targetKg: Double, start: Date, weeks: Int, template: FocusTemplate,
                startOneRepMax: Double, weakPoint: WeakPoint = .none, maintenance: Bool = true) {
        self.exerciseId = exerciseId
        self.targetKg = targetKg
        self.start = start
        self.weeks = max(1, weeks)
        self.template = template
        self.startOneRepMax = startOneRepMax
        self.weakPoint = weakPoint
        self.maintenance = maintenance
    }

    /// Lifts that can be focused: the big barbell lifts first, then any loaded strength move.
    public static let suggested = ["back-squat", "bench-press", "deadlift", "ohp", "front-squat", "sumo-deadlift",
                                   "incline-bench-press", "weighted-pull-up", "hip-thrust", "barbell-row"]

    static func family(_ id: String) -> String? {
        switch id {
        case "bench-press", "incline-bench-press", "close-grip-bench": "bench"
        case "back-squat", "front-squat", "box-squat": "squat"
        case "deadlift", "sumo-deadlift", "deficit-deadlift": "deadlift"
        case "ohp", "push-press", "z-press": "press"
        default: nil
        }
    }

    /// Accessories for a weak point; empty for lifts without a known family.
    public static func accessories(for exerciseId: String, _ weak: WeakPoint) -> [String] {
        guard weak != .none, let f = family(exerciseId) else { return [] }
        let table: [String: [WeakPoint: [String]]] = [
            "bench": [.bottom: ["incline-bench-press", "weighted-dip"], .lockout: ["close-grip-bench", "barbell-floor-press"]],
            "squat": [.bottom: ["box-squat", "front-squat"], .lockout: ["good-morning", "leg-press"]],
            "deadlift": [.bottom: ["deficit-deadlift", "barbell-row"], .lockout: ["rack-pull", "rdl"]],
            "press": [.bottom: ["z-press", "weighted-dip"], .lockout: ["push-press", "close-grip-bench"]],
        ]
        return (table[f]?[weak] ?? []).filter { $0 != exerciseId && Exercise.find($0) != nil }
    }

    // MARK: Calendar

    /// Day of the test (Monday of the last week + 5 = its Saturday).
    public var testDate: Date { start.addingTimeInterval(Double((weeks - 1) * 7 + 5) * 86400) }

    /// Block week 1…weeks of `date`; nil before the start or after the block.
    public func week(on date: Date, calendar cal: Calendar = Progression.calendar()) -> Int? {
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: date)).day ?? -1
        guard days >= 0 else { return nil }
        let w = days / 7 + 1
        return w <= weeks ? w : nil
    }

    public func finished(on date: Date, calendar cal: Calendar = Progression.calendar()) -> Bool {
        cal.startOfDay(for: date) > cal.startOfDay(for: start.addingTimeInterval(Double(weeks * 7) * 86400))
    }

    public func phase(week w: Int) -> FocusPhase {
        if w >= weeks { return .test }
        switch template {
        case .monkeyPeak:
            if w == weeks - 1 { return .taper }
            return w % 4 == 0 ? .deload : .build
        case .wave531, .gzcl:
            return w % 4 == 0 ? .deload : .build
        case .smolovJr:
            return .build
        }
    }

    /// Build weeks of a Monkey peak block, in order (for the ramp).
    private var buildWeeks: [Int] { (1...weeks).filter { phase(week: $0) == .build } }

    // MARK: Loads

    /// Max the week's percentages are taken from. Monkey peak climbs from the start 1RM to the target, never more than
    /// 5% over the live estimate; 5/3/1 uses 90% of the live estimate, GZCL 95%, Smolov Jr the start 1RM.
    public func workingMax(week w: Int, live: Double?) -> Double {
        let now = live ?? startOneRepMax
        switch template {
        case .monkeyPeak:
            let t = weeks > 1 ? Double(w - 1) / Double(weeks - 1) : 1
            let planned = startOneRepMax + (targetKg - startOneRepMax) * t
            return min(planned, now * 1.05)
        case .wave531: return now * 0.9
        case .gzcl: return now * 0.95
        case .smolovJr: return startOneRepMax
        }
    }

    /// Sets of each focus session of week `w`, first session first. Test week: one session, the attempts.
    public func doses(week w: Int) -> [[FocusSet]] {
        let ph = phase(week: w)
        if ph == .test { return [] }
        switch template {
        case .monkeyPeak:
            switch ph {
            case .deload: return [Array(repeating: FocusSet(0.65, 3), count: 3)]
            case .taper: return [Array(repeating: FocusSet(0.9, 1), count: 2), Array(repeating: FocusSet(0.7, 3), count: 3)]
            default:
                let b = buildWeeks
                let k = b.firstIndex(of: w) ?? 0
                let pct = b.count > 1 ? 0.72 + 0.2 * Double(k) / Double(b.count - 1) : 0.8
                let reps = pct < 0.75 ? 5 : pct < 0.8 ? 4 : pct < 0.85 ? 3 : pct < 0.9 ? 2 : 1
                let sets = reps >= 3 ? 5 : reps == 2 ? 4 : 3
                let heavy = Array(repeating: FocusSet(pct, reps), count: sets)
                let volume = Array(repeating: FocusSet(pct - 0.12, reps + 2), count: 4)
                return [heavy, volume]
            }
        case .wave531:
            let cw = (w - 1) % 4
            let wave: [(Double, Int)] = switch cw {
            case 0: [(0.65, 5), (0.75, 5), (0.85, 5)]
            case 1: [(0.7, 3), (0.8, 3), (0.9, 3)]
            case 2: [(0.75, 5), (0.85, 3), (0.95, 1)]
            default: [(0.4, 5), (0.5, 5), (0.6, 5)]
            }
            var sets = wave.enumerated().map { i, s in FocusSet(s.0, s.1, amrap: i == 2 && cw != 3) }
            if cw != 3 { sets += Array(repeating: FocusSet(wave[0].0, 5), count: 3) }
            return [sets]
        case .gzcl:
            let cw = (w - 1) % 4
            let t1: [FocusSet] = switch cw {
            case 0: (0..<5).map { FocusSet(0.85, 3, amrap: $0 == 4) }
            case 1: (0..<6).map { FocusSet(0.88, 2, amrap: $0 == 5) }
            case 2: (0..<10).map { FocusSet(0.91, 1, amrap: $0 == 9) }
            default: Array(repeating: FocusSet(0.7, 3), count: 3)
            }
            return cw == 3 ? [t1] : [t1, Array(repeating: FocusSet(0.65, 8), count: 3)]
        case .smolovJr:
            let bump = 1 + 0.025 * Double(w - 1)
            let days: [(sets: Int, reps: Int, pct: Double)] = [(6, 6, 0.7), (7, 5, 0.75), (8, 4, 0.8), (10, 3, 0.85)]
            return days.map { Array(repeating: FocusSet($0.pct * bump, $0.reps), count: $0.sets) }
        }
    }

    /// Test-day attempts from an estimated 1RM: opener 91%, second 96%, third the target when within reach (≤ 103%),
    /// else 101%. Rounded to the equipment step.
    public static func attempts(oneRepMax orm: Double, target: Double?, exercise e: Exercise) -> [Double] {
        let s = LoadAdvisor.steps(for: e, kg: orm).granularity
        let first = LoadAdvisor.round(orm * 0.91, to: s, .down)
        let second = LoadAdvisor.round(orm * 0.96, to: s, .down)
        var third = LoadAdvisor.round(orm * 1.01, to: s, .up)
        if let target, target > second, target <= orm * 1.03 { third = LoadAdvisor.round(target, to: s) }
        return [first, second, max(second + s, third)]
    }

    /// Planned sets of focus session `index` in week `w`, loads from the working max.
    public func plannedSets(week w: Int, index: Int, live: Double?, exercise e: Exercise) -> [PlannedSet] {
        let step = LoadAdvisor.steps(for: e, kg: startOneRepMax).granularity
        if phase(week: w) == .test {
            guard index == 0 else { return [] }
            let orm = max(live ?? startOneRepMax, workingMax(week: w, live: live) * 0.97)
            let names = ["Opener", "Second", "Third"]
            return Self.attempts(oneRepMax: orm, target: targetKg, exercise: e).enumerated().map { i, kg in
                PlannedSet(role: .attempt, kg: kg, reps: 1, target: "1", restSec: 240, note: names[i])
            }
        }
        let d = doses(week: w)
        guard d.indices.contains(index) else { return [] }
        let wm = workingMax(week: w, live: live)
        let heavy = d[index].first.map { $0.pct >= 0.85 } ?? false
        return d[index].map { s in
            let kg = LoadAdvisor.round(wm * s.pct, to: step)
            return PlannedSet(role: s.amrap ? .amrap : .work, kg: kg, reps: s.reps, target: s.amrap ? "\(s.reps)+" : "\(s.reps)",
                              restSec: heavy ? 210 : 150, note: "\(Int((s.pct * 100).rounded()))%")
        }
    }

    /// Focus sessions planned in week `w` (test week: 1).
    public func sessionsPerWeek(week w: Int) -> Int { phase(week: w) == .test ? 1 : doses(week: w).count }

    // MARK: Prediction

    /// Estimated 1RM on the test day from the weekly e1RM trend (least squares over the last 8 points); nil with
    /// fewer than 2 points. Never predicts a drop below the latest value by more than 5%.
    public func predicted(trend: [(Date, Double)]) -> Double? {
        let pts = Array(trend.suffix(8))
        guard pts.count >= 2, let last = pts.last else { return nil }
        let t0 = pts[0].0.timeIntervalSince1970
        let xs = pts.map { ($0.0.timeIntervalSince1970 - t0) / 86400 }
        let ys = pts.map(\.1)
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return last.1 }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx
        // A peaking block adds on top of a trend; cap the daily gain at 0.5% of the lift.
        let perDay = min(slope, my * 0.005)
        let days = (testDate.timeIntervalSince1970 - t0) / 86400
        return max(last.1 * 0.95, my + perDay * (days - mx))
    }
}

// MARK: - Plan

extension WeekPlan {
    /// The week with the Lift Focus applied (#499): the lift in its sessions with the block's sets (inserted first
    /// in the strength block of the best-matching sessions when the plan lacks it), weak-point accessories after it
    /// in the first focus session, other strength work at maintenance volume. Outside the block: unchanged.
    public func applyingLiftFocus(_ f: LiftFocus?, on date: Date, equipment: Set<Equipment>, calendar cal: Calendar = Progression.calendar()) -> WeekPlan {
        guard let f, let w = f.week(on: date, calendar: cal), let lift = Exercise.find(f.exerciseId),
              Selector.isAvailable(lift, equipment) else { return self }
        let want = f.sessionsPerWeek(week: w)
        guard want > 0 else { return self }
        var p = self
        let candidates = p.sessions.indices.filter { i in
            p.sessions[i].focus != .conditioning && p.sessions[i].blocks.contains { $0.kind == .strength }
        }
        // Sessions already doing the lift, then those training its main muscle, then the rest, in week order.
        func has(_ i: Int) -> Bool { p.sessions[i].blocks.contains { $0.items.contains { $0.exerciseId == f.exerciseId } } }
        func trains(_ i: Int) -> Bool {
            p.sessions[i].blocks.contains { b in
                b.kind == .strength && b.items.contains { Exercise.find($0.exerciseId)?.primary.contains { lift.primary.contains($0) } ?? false }
            }
        }
        let ordered = candidates.filter(has) + candidates.filter { !has($0) && trains($0) } + candidates.filter { !has($0) && !trains($0) }
        let picked = Array(ordered.prefix(want)).sorted()
        for (n, si) in picked.enumerated() {
            let sets = f.plannedSets(week: w, index: n, live: nil, exercise: lift)
            guard !sets.isEmpty else { continue }
            let phase = f.phase(week: w)
            let pres = Prescription(sets: sets.count, reps: sets.map(\.target).uniqued().joined(separator: "/"),
                                    restSec: sets.first?.restSec ?? 180,
                                    intensity: "Lift Focus · week \(w)/\(f.weeks) · \(phase.label)", note: nil)
            let est = sets.count * (lift.unilateral ? 2 : 1) * 30 + sets.reduce(0) { $0 + $1.restSec }
            var s = p.sessions[si]
            guard let bi = s.blocks.firstIndex(where: { $0.kind == .strength }) else { continue }
            if let ii = s.blocks[bi].items.firstIndex(where: { $0.exerciseId == f.exerciseId }) {
                s.blocks[bi].items[ii].prescription = pres
                s.blocks[bi].items[ii].estSec = est
                s.blocks[bi].items[ii].group = nil
                s.blocks[bi].items[ii].supersetWith = nil
                let it = s.blocks[bi].items.remove(at: ii)
                s.blocks[bi].items.insert(it, at: 0)
            } else if let other = s.blocks.indices.first(where: { $0 != bi && s.blocks[$0].items.contains { $0.exerciseId == f.exerciseId } }),
                      let ii = s.blocks[other].items.firstIndex(where: { $0.exerciseId == f.exerciseId }) {
                var it = s.blocks[other].items.remove(at: ii)
                it.prescription = pres
                it.estSec = est
                it.group = nil
                it.supersetWith = nil
                s.blocks[bi].items.insert(it, at: 0)
            } else {
                s.blocks[bi].items.insert(PlannedExercise(uid: "\(s.id)-focus", exerciseId: lift.id, slot: lift.pattern,
                                                          prescription: pres, estSec: est), at: 0)
            }
            if n == 0 && phase != .test {
                let present = Set(s.blocks.flatMap { $0.items.map(\.exerciseId) })
                var at = 1
                for (k, id) in LiftFocus.accessories(for: f.exerciseId, f.weakPoint).enumerated() {
                    guard !present.contains(id), let e = Exercise.find(id), Selector.isAvailable(e, equipment) else { continue }
                    let rest = 120
                    s.blocks[bi].items.insert(PlannedExercise(
                        uid: "\(s.id)-weak\(k)", exerciseId: id, slot: e.pattern,
                        prescription: Prescription(sets: 3, reps: "6–8", restSec: rest, intensity: "RPE 8",
                                                   note: "Weak point: \(f.weakPoint.label(for: f.exerciseId).lowercased())"),
                        estSec: 3 * 7 * Int(e.secPerRep ?? 3) + 2 * rest), at: at)
                    at += 1
                }
            }
            p.sessions[si] = s
        }
        if f.maintenance {
            let focusIds = Set([f.exerciseId] + LiftFocus.accessories(for: f.exerciseId, f.weakPoint))
            for si in p.sessions.indices {
                for bi in p.sessions[si].blocks.indices where p.sessions[si].blocks[bi].kind == .strength {
                    for ii in p.sessions[si].blocks[bi].items.indices {
                        var it = p.sessions[si].blocks[bi].items[ii]
                        guard !focusIds.contains(it.exerciseId), it.prescription.sets > 2 else { continue }
                        let before = it.prescription.sets
                        it.prescription.sets = max(2, Int((Double(before) * 0.7).rounded()))
                        it.estSec = it.estSec * it.prescription.sets / before
                        p.sessions[si].blocks[bi].items[ii] = it
                    }
                }
            }
        }
        for si in p.sessions.indices { p.sessions[si].estMin = Int(p.sessions[si].blocks.reduce(0) { $0 + $1.estMin }.rounded()) }
        return p
    }

    /// Which focus session (0-based) of the week `sessionId` is, or nil when the lift isn't focused there.
    public func liftFocusIndex(sessionId: String, focus f: LiftFocus) -> Int? {
        let withLift = sessions.filter { s in
            s.blocks.contains { $0.items.contains { $0.exerciseId == f.exerciseId && $0.prescription.intensity?.hasPrefix("Lift Focus") == true } }
        }
        return withLift.firstIndex { $0.id == sessionId }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
