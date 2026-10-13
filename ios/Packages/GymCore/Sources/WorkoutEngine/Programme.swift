import Foundation

// MARK: - Training programmes (#255)

/// A stage of a programme. Each maps onto one week of the 4-week block the generator already knows.
public enum ProgrammePhaseKind: String, Codable, Sendable, CaseIterable {
    case base, build, peak, ease, test

    /// Generator week (1 Base … 4 Deload) a programme week of this phase is built as.
    public var cycleWeek: Int {
        switch self {
        case .base: 1
        case .build: 2
        case .peak: 3
        case .ease, .test: 4
        }
    }

    public var label: String {
        switch self {
        case .base: "Base"
        case .build: "Build"
        case .peak: "Peak"
        case .ease: "Ease"
        case .test: "Test"
        }
    }
}

public struct ProgrammePhase: Hashable, Sendable {
    public let kind: ProgrammePhaseKind
    public let weeks: Int
    /// What this phase does, one line.
    public let note: String
}

/// A workout the programme pins into every week of some phases: the generated session of the closest type keeps its
/// warm-up, cardio and cool-down, its strength block becomes these exercises.
public struct ProgrammeSignature: Hashable, Sendable, Identifiable {
    public struct Dose: Hashable, Sendable {
        public let sets: Int
        public let reps: String
        public init(_ sets: Int, _ reps: String) {
            self.sets = sets
            self.reps = reps
        }
    }

    public struct Item: Hashable, Sendable {
        public let exerciseId: String
        /// Dose per phase; phases not listed use `dose`.
        public let byPhase: [ProgrammePhaseKind: Dose]
        public let dose: Dose
        public let restSec: Int

        init(_ exerciseId: String, _ dose: Dose, rest: Int = 90, _ byPhase: [ProgrammePhaseKind: Dose] = [:]) {
            self.exerciseId = exerciseId
            self.dose = dose
            self.restSec = rest
            self.byPhase = byPhase
        }

        public func dose(_ phase: ProgrammePhaseKind) -> Dose { byPhase[phase] ?? dose }
    }

    public let id: String
    public let name: String
    /// Session types it can take the place of, best first.
    public let replaces: [Focus]
    /// Phases it is pinned in.
    public let phases: Set<ProgrammePhaseKind>
    public let items: [Item]
}

/// A multi-week programme toward one goal (#255, design C hybrid): phases, signature workouts, the rest of each week
/// built by the generator for the member's gym, days and time, and an optional PR test week to finish.
public struct Programme: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tagline: String
    public let summary: String
    public let symbol: String
    /// Explore palette of its cards.
    public let palette: Category
    public let goal: Goal
    public let sessionsPerWeek: Int
    public let split: SplitStyle
    public let method: TrainingMethod
    public let focusMuscles: [MuscleGroup]
    public let phases: [ProgrammePhase]
    public let signatures: [ProgrammeSignature]
    /// Lifts tested in the test week and compared start vs now in Progress.
    public let lifts: [String]
    /// Climbing days stay part of the week (climbing goal).
    public var climbing: Bool { goal == .climbing }

    public var weeks: Int { phases.reduce(0) { $0 + $1.weeks } }

    /// Phase of programme week `week` (1-based; clamped to the programme).
    public func phase(week: Int) -> ProgrammePhase {
        var left = min(max(1, week), weeks)
        for p in phases {
            if left <= p.weeks { return p }
            left -= p.weeks
        }
        return phases[phases.count - 1]
    }

    /// First programme week of each phase, in order.
    public var phaseStarts: [(phase: ProgrammePhase, week: Int)] {
        var w = 1
        return phases.map { p in
            defer { w += p.weeks }
            return (p, w)
        }
    }

    /// Generator week (1…4) programme week `week` is built as.
    public func cycleWeek(week: Int) -> Int { phase(week: week).kind.cycleWeek }

    public var hasTest: Bool { phases.contains { $0.kind == .test } }

    /// The member's profile running this programme: goal, split, method and focus muscles come from the programme;
    /// days, gym, time, experience, climbing and every other choice stay the member's.
    public func profile(from base: Profile, starting: Bool = false) -> Profile {
        var p = base
        p.goal = goal
        p.split = split
        p.splitDays = nil
        p.method = method
        p.focusMuscles = focusMuscles.isEmpty ? nil : focusMuscles
        if starting { p.sessionsPerWeek = sessionsPerWeek }
        return p
    }

    /// Whether a profile still carries what this programme sets (an edit elsewhere may have changed it).
    public func isApplied(to p: Profile) -> Bool {
        profile(from: p) == p
    }

    /// Variation seed of programme week `week`: same week, same plan; next week, fresh picks.
    public static func seed(_ base: UInt32, week: Int) -> UInt32 { base &+ UInt32(max(0, week - 1)) &* 2_654_435_761 }

    // MARK: Signature workouts

    /// Signature workouts of programme week `week` placed into `plan`: each replaces the first generated session of
    /// a type it can take, keeping that session's day, warm-up and finishers. Exercises the member's gym lacks are
    /// swapped for the closest one it has, or dropped.
    public func signatureInserts(week: Int, plan: WeekPlan, profile: Profile) -> [PlanInsert] {
        let kind = phase(week: week).kind
        var taken = Set<Int>()
        var out: [PlanInsert] = []
        for sig in signatures where sig.phases.contains(kind) {
            guard let index = slot(for: sig, in: plan, taken: taken) else { continue }
            taken.insert(index)
            let base = plan.sessions[index]
            guard let session = Self.signatureSession(sig, phase: kind, on: base, profile: profile) else { continue }
            let insertId = Self.insertId(programme: id, signature: sig.id, week: week)
            out.append(PlanInsert(id: insertId, week: plan.week, replacing: index,
                                  workout: CustomWorkout(id: insertId, name: sig.name, createdAt: Date(timeIntervalSince1970: 0)),
                                  generated: session))
        }
        return out
    }

    /// Generated session index a signature takes: the first free one whose type it lists (in its order of preference),
    /// else the first free strength day that isn't conditioning.
    func slot(for sig: ProgrammeSignature, in plan: WeekPlan, taken: Set<Int>) -> Int? {
        for f in sig.replaces {
            if let i = plan.sessions.indices.first(where: { !taken.contains($0) && plan.sessions[$0].focus == f }) { return i }
        }
        return plan.sessions.indices.first { !taken.contains($0) && plan.sessions[$0].focus != .conditioning }
    }

    static func signatureSession(_ sig: ProgrammeSignature, phase: ProgrammePhaseKind, on base: Session, profile: Profile) -> Session? {
        let equipment = Set(profile.equipment)
        var used = Set<String>()
        var items: [PlannedExercise] = []
        for (n, it) in sig.items.enumerated() {
            guard let wanted = Exercise.find(it.exerciseId) else { continue }
            let e = Selector.isAvailable(wanted, equipment) && !used.contains(wanted.id)
                ? wanted
                : wanted.swapOptions(for: profile, excluding: used).first { Selector.isAvailable($0, equipment) }
            guard let e else { continue }
            used.insert(e.id)
            let d = it.dose(phase)
            let reps = Double(Int(d.reps.prefix { $0.isNumber }) ?? 8)
            let work = Double(d.sets) * reps * (e.secPerRep ?? 3) * (e.unilateral ? 2 : 1)
            items.append(PlannedExercise(
                uid: "\(base.id)-sig\(n)", exerciseId: e.id, slot: e.pattern,
                prescription: Prescription(sets: d.sets, reps: d.reps, restSec: it.restSec,
                                           intensity: phase == .ease ? "Light: 3+ reps in reserve" : nil,
                                           note: e.id == wanted.id ? nil : "Instead of \(wanted.name)"),
                estSec: Int(work) + (d.sets - 1) * it.restSec + 60))
        }
        guard !items.isEmpty else { return nil }
        var s = base
        s.title = sig.name
        // Warm-up, power, mobility, cardio and cool-down stay; the strength block becomes the signature's exercises.
        var blocks = s.blocks.filter { $0.kind != .strength }
        let strengthAt = s.blocks.firstIndex { $0.kind == .strength }.map { i in
            s.blocks[..<i].filter { $0.kind != .strength }.count
        } ?? min(1, blocks.count)
        let est = Int((Double(items.reduce(0) { $0 + $1.estSec }) / 60).rounded())
        blocks.insert(Block(kind: .strength, title: sig.name, targetMin: est, items: items, note: nil), at: strengthAt)
        s.blocks = blocks
        s.estMin = Int(blocks.reduce(0) { $0 + $1.estMin }.rounded())
        s.targetMin = max(s.targetMin, s.estMin)
        return s
    }

    /// Stable id of a signature insert, so a re-applied week keeps its ticks and logs.
    static func insertId(programme: String, signature: String, week: Int) -> UUID {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in "\(programme)|\(signature)|\(week)".utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i] = UInt8(truncatingIfNeeded: h >> (8 * UInt64(i))) }
        h = h &* 0x9e37_79b9_7f4a_7c15
        for i in 0..<8 { bytes[8 + i] = UInt8(truncatingIfNeeded: h >> (8 * UInt64(i))) }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - Running a programme

/// The member's programme in progress, synced with the profile. While it runs it replaces the plan; the member's
/// own plan (`saved`) comes back when they pause, leave or finish.
public struct ActiveProgramme: Codable, Hashable, Sendable {
    public var programmeId: String
    /// Monday of programme week 1.
    public var start: Date
    /// Monday of the week it was paused; nil while running.
    public var pausedAt: Date?
    /// Whole weeks spent paused, not counted as programme weeks.
    public var pausedWeeks: Int
    /// Base of each week's variation seed.
    public var seed: UInt32
    /// Programme week the plan was last built for.
    public var appliedWeek: Int?
    /// The member's own plan to restore.
    public var saved: SavedPlan

    public struct SavedPlan: Codable, Hashable, Sendable {
        public var profile: Profile
        public var seed: UInt32
        public var week: Int

        public init(profile: Profile, seed: UInt32, week: Int) {
            self.profile = profile
            self.seed = seed
            self.week = week
        }
    }

    public init(programmeId: String, start: Date, seed: UInt32, saved: SavedPlan, pausedAt: Date? = nil, pausedWeeks: Int = 0) {
        self.programmeId = programmeId
        self.start = start
        self.seed = seed
        self.saved = saved
        self.pausedAt = pausedAt
        self.pausedWeeks = pausedWeeks
    }

    public var programme: Programme? { Programme.find(programmeId) }
    public var paused: Bool { pausedAt != nil }

    /// Programme week on `date` (1-based; above `weeks` once it is over). Paused: the week it was paused in.
    public func week(on date: Date, calendar cal: Calendar = Progression.calendar()) -> Int {
        let monday = Progression.weekStart(pausedAt ?? date, cal)
        let start = Progression.weekStart(self.start, cal)
        let elapsed = cal.dateComponents([.weekOfYear], from: start, to: monday).weekOfYear ?? 0
        return max(1, elapsed + 1 - pausedWeeks)
    }

    /// Resumed in the week of `date`: the paused weeks stop counting.
    public func resumed(on date: Date, calendar cal: Calendar = Progression.calendar()) -> ActiveProgramme {
        guard let p = pausedAt else { return self }
        var r = self
        let from = Progression.weekStart(p, cal), to = Progression.weekStart(date, cal)
        r.pausedWeeks += max(0, cal.dateComponents([.weekOfYear], from: from, to: to).weekOfYear ?? 0)
        r.pausedAt = nil
        r.appliedWeek = nil
        return r
    }

    /// Whether the programme is over on `date`.
    public func finished(on date: Date, calendar cal: Calendar = Progression.calendar()) -> Bool {
        guard let prog = programme, !paused else { return false }
        return week(on: date, calendar: cal) > prog.weeks
    }
}

/// A programme the member finished or left, for Progress.
public struct ProgrammeRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var programmeId: String
    public var start: Date
    public var end: Date
    public var finished: Bool
    /// Programme weeks trained (finished = all of them).
    public var weeks: Int

    public init(id: UUID = UUID(), programmeId: String, start: Date, end: Date, finished: Bool, weeks: Int) {
        self.id = id
        self.programmeId = programmeId
        self.start = start
        self.end = end
        self.finished = finished
        self.weeks = weeks
    }

    public var programme: Programme? { Programme.find(programmeId) }
}

/// Start vs now for one programme lift: best estimated 1RM in the 8 weeks before the start, and since.
public struct ProgrammeLift: Hashable, Sendable, Identifiable {
    public let exerciseId: String
    public let before: Double?
    public let now: Double?
    public var id: String { exerciseId }
    public var change: Double? {
        guard let before, let now else { return nil }
        return now - before
    }

    public static func compare(_ lifts: [String], logs: [SetLog], attempts: [PRAttempt], start: Date, end: Date = .distantFuture) -> [ProgrammeLift] {
        let from = start.addingTimeInterval(-56 * 86_400)
        return lifts.map { id in
            let mine = logs.filter { $0.exerciseId == id }
            let tries = attempts.filter { $0.exerciseId == id && $0.success }
            let before = PRPlanner.estimatedOneRepMax(logs: mine.filter { $0.date >= from && $0.date < start },
                                                   attempts: tries.filter { $0.date >= from && $0.date < start })
            let now = PRPlanner.estimatedOneRepMax(logs: mine.filter { $0.date >= start && $0.date <= end },
                                                attempts: tries.filter { $0.date >= start && $0.date <= end })
            return ProgrammeLift(exerciseId: id, before: before, now: now)
        }
    }
}

// MARK: - Catalog

extension Programme {
    public static func find(_ id: String) -> Programme? { all.first { $0.id == id } }

    public static let all: [Programme] = [strengthFoundation, muscleBuilder, climbersPower]

    private typealias Item = ProgrammeSignature.Item
    private typealias Dose = ProgrammeSignature.Dose

    static let strengthFoundation = Programme(
        id: "strength-foundation", name: "Strength foundation",
        tagline: "Squat · bench · deadlift · 3× a week",
        summary: "Eight weeks to a stronger squat, bench and deadlift: five sets of five, then heavier triples and doubles, an easy week, then you test all three.",
        symbol: "figure.strengthtraining.traditional", palette: .power,
        goal: .strength, sessionsPerWeek: 3, split: .fullBody, method: .block, focusMuscles: [],
        phases: [
            ProgrammePhase(kind: .base, weeks: 3, note: "5×5 on the main lifts, a weight you could lift 7 times"),
            ProgrammePhase(kind: .build, weeks: 2, note: "Heavier triples, same accessories"),
            ProgrammePhase(kind: .peak, weeks: 1, note: "Doubles near your best"),
            ProgrammePhase(kind: .ease, weeks: 1, note: "Light week so you test fresh"),
            ProgrammePhase(kind: .test, weeks: 1, note: "PR attempts on squat, bench and deadlift"),
        ],
        signatures: [
            ProgrammeSignature(
                id: "heavy-squat", name: "Heavy squat day", replaces: [.fullLower, .lower, .legs, .fullPower],
                phases: [.base, .build, .peak, .ease],
                items: [
                    Item("back-squat", Dose(5, "5"), rest: 180, [.build: Dose(5, "3"), .peak: Dose(6, "2"), .ease: Dose(3, "5")]),
                    Item("rdl", Dose(3, "8"), rest: 120, [.peak: Dose(3, "6"), .ease: Dose(2, "8")]),
                    Item("bulgarian-split-squat", Dose(3, "8"), [.ease: Dose(2, "8")]),
                    Item("hanging-knee-raise", Dose(3, "12"), rest: 60),
                ]),
            ProgrammeSignature(
                id: "bench-pull", name: "Bench + pull day", replaces: [.fullUpper, .upper, .push, .fullPower],
                phases: [.base, .build, .peak, .ease],
                items: [
                    Item("bench-press", Dose(5, "5"), rest: 180, [.build: Dose(5, "3"), .peak: Dose(6, "2"), .ease: Dose(3, "5")]),
                    Item("barbell-row", Dose(4, "8"), rest: 120, [.ease: Dose(2, "8")]),
                    Item("ohp", Dose(3, "6"), rest: 120, [.ease: Dose(2, "6")]),
                    Item("pull-up", Dose(3, "6"), rest: 120),
                ]),
        ],
        lifts: ["back-squat", "bench-press", "deadlift"])

    static let muscleBuilder = Programme(
        id: "muscle-builder", name: "Muscle builder",
        tagline: "Upper / lower · 4× a week",
        summary: "Six weeks of upper / lower training: sets per muscle rise each week, then a lighter week where you test your 8-rep bests.",
        symbol: "dumbbell.fill", palette: .strength,
        goal: .build, sessionsPerWeek: 4, split: .upperLower, method: .volume, focusMuscles: [],
        phases: [
            ProgrammePhase(kind: .base, weeks: 2, note: "8–12 reps, learn the groove, 2 reps in reserve"),
            ProgrammePhase(kind: .build, weeks: 2, note: "One more set per muscle each week"),
            ProgrammePhase(kind: .peak, weeks: 1, note: "Most volume of the programme"),
            ProgrammePhase(kind: .test, weeks: 1, note: "Lighter week, test your 8-rep bests"),
        ],
        signatures: [
            ProgrammeSignature(
                id: "upper-pump", name: "Upper pump", replaces: [.upper, .fullUpper, .push, .chestTri],
                phases: [.base, .build, .peak],
                items: [
                    Item("incline-db-press", Dose(4, "8–10"), [.build: Dose(4, "10–12"), .peak: Dose(5, "10–12")]),
                    Item("lat-pulldown", Dose(4, "8–10"), [.build: Dose(4, "10–12"), .peak: Dose(5, "10–12")]),
                    Item("seated-cable-row", Dose(3, "10–12")),
                    Item("db-lateral-raise", Dose(3, "12–15"), rest: 60, [.peak: Dose(4, "12–15")]),
                    Item("cable-curl", Dose(3, "12"), rest: 60),
                    Item("triceps-pushdown", Dose(3, "12"), rest: 60),
                ]),
            ProgrammeSignature(
                id: "leg-builder", name: "Leg builder", replaces: [.lower, .fullLower, .legs],
                phases: [.base, .build, .peak],
                items: [
                    Item("hack-squat", Dose(4, "8–10"), rest: 120, [.peak: Dose(5, "8–10")]),
                    Item("rdl", Dose(3, "8–10"), rest: 120),
                    Item("walking-lunge", Dose(3, "10")),
                    Item("leg-curl", Dose(3, "12"), rest: 60, [.peak: Dose(4, "12")]),
                    Item("standing-calf-raise", Dose(4, "12"), rest: 60),
                ]),
        ],
        lifts: ["incline-db-press", "hack-squat", "lat-pulldown"])

    static let climbersPower = Programme(
        id: "climbers-power", name: "Climber's power",
        tagline: "Pull + core + legs · 2× a week + climbing",
        summary: "Six weeks of strength for the wall around your climbing days: heavy and explosive pulling, core and antagonists, then you test your pull.",
        symbol: "figure.climbing", palette: .cardio,
        goal: .climbing, sessionsPerWeek: 2, split: .auto, method: .block, focusMuscles: [.back, .core],
        phases: [
            ProgrammePhase(kind: .base, weeks: 2, note: "Strength base for pulling and core"),
            ProgrammePhase(kind: .build, weeks: 2, note: "Heavier pulls, faster on the way up"),
            ProgrammePhase(kind: .peak, weeks: 1, note: "Heaviest pulls, fewer sets"),
            ProgrammePhase(kind: .test, weeks: 1, note: "Test your weighted pull-up and row"),
        ],
        signatures: [
            ProgrammeSignature(
                id: "pull-power", name: "Pull power", replaces: [.pull, .backBi, .upper, .fullUpper, .fullPower],
                phases: [.base, .build, .peak],
                items: [
                    Item("weighted-pull-up", Dose(5, "5"), rest: 180, [.build: Dose(5, "3"), .peak: Dose(6, "2")]),
                    Item("explosive-pull-up", Dose(3, "4"), rest: 120),
                    Item("one-arm-db-row", Dose(3, "8")),
                    Item("face-pull", Dose(3, "12"), rest: 60),
                    Item("hanging-knee-raise", Dose(3, "10"), rest: 60),
                ]),
        ],
        lifts: ["weighted-pull-up", "one-arm-db-row"])
}
