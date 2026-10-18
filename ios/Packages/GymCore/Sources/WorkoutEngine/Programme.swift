import Foundation

// MARK: - Training programmes (#255)

/// A stage of a programme. Each maps onto one week of the 4-week block the generator already knows.
public enum ProgrammePhaseKind: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
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

public struct ProgrammePhase: Codable, Hashable, Sendable {
    public var kind: ProgrammePhaseKind
    public var weeks: Int
    /// What this phase does, one line.
    public var note: String

    public init(kind: ProgrammePhaseKind, weeks: Int, note: String) {
        self.kind = kind
        self.weeks = weeks
        self.note = note
    }
}

/// A workout the programme pins into every week of some phases: the generated session of the closest type keeps its
/// warm-up, cardio and cool-down, its strength block becomes these exercises.
public struct ProgrammeSignature: Codable, Hashable, Sendable, Identifiable {
    public struct Dose: Codable, Hashable, Sendable {
        public let sets: Int
        public let reps: String
        public init(_ sets: Int, _ reps: String) {
            self.sets = sets
            self.reps = reps
        }
    }

    public struct Item: Codable, Hashable, Sendable {
        public let exerciseId: String
        /// Dose per phase; phases not listed use `dose`.
        public let byPhase: [ProgrammePhaseKind: Dose]
        public let dose: Dose
        public let restSec: Int
        /// Pace or load to aim for (Hyrox ready #431: from the goal time and division), shown as the intensity.
        public var target: String?

        public init(_ exerciseId: String, _ dose: Dose, rest: Int = 90, _ byPhase: [ProgrammePhaseKind: Dose] = [:]) {
            self.exerciseId = exerciseId
            self.dose = dose
            self.restSec = rest
            self.byPhase = byPhase
        }

        public func dose(_ phase: ProgrammePhaseKind) -> Dose { byPhase[phase] ?? dose }
    }

    public var id: String
    public var name: String
    /// Session types it can take the place of, best first.
    public var replaces: [Focus]
    /// Phases it is pinned in.
    public var phases: Set<ProgrammePhaseKind>
    public var items: [Item]

    public init(id: String, name: String, replaces: [Focus], phases: Set<ProgrammePhaseKind>, items: [Item]) {
        self.id = id
        self.name = name
        self.replaces = replaces
        self.phases = phases
        self.items = items
    }
}

/// A multi-week programme toward one goal (#255, design C hybrid): phases, signature workouts, the rest of each week
/// built by the generator for the member's gym, days and time, and an optional PR test week to finish.
public struct Programme: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var tagline: String
    public var summary: String
    public var symbol: String
    /// Explore palette of its cards.
    public var palette: Category
    public var goal: Goal
    public var sessionsPerWeek: Int
    public var split: SplitStyle
    public var method: TrainingMethod
    public var focusMuscles: [MuscleGroup]
    public var phases: [ProgrammePhase]
    public var signatures: [ProgrammeSignature]
    /// Lifts tested in the test week and compared start vs now in Progress.
    public var lifts: [String]
    /// Member-made programme (#269): the catalog programme it was copied from, if any.
    public var basedOn: String?

    public init(id: String, name: String, tagline: String, summary: String, symbol: String, palette: Category, goal: Goal,
                sessionsPerWeek: Int, split: SplitStyle, method: TrainingMethod, focusMuscles: [MuscleGroup],
                phases: [ProgrammePhase], signatures: [ProgrammeSignature], lifts: [String], basedOn: String? = nil) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.summary = summary
        self.symbol = symbol
        self.palette = palette
        self.goal = goal
        self.sessionsPerWeek = sessionsPerWeek
        self.split = split
        self.method = method
        self.focusMuscles = focusMuscles
        self.phases = phases
        self.signatures = signatures
        self.lifts = lifts
        self.basedOn = basedOn
    }

    /// Made by the member (#269), not from the catalog.
    public var mine: Bool { id.hasPrefix(Programme.minePrefix) }
    public static let minePrefix = "my-"
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

    // MARK: Length (#268)

    /// Lengths a member can pick: Base and Build get longer or shorter, Peak, Ease and Test stay as they are.
    public var lengths: [ProgrammeLength] {
        let std = Programme.find(id) ?? self
        let tail = std.weeks - std.coreWeeks
        return [(-2, "Quick"), (0, "Standard"), (2, "Extended"), (4, "Long haul")].compactMap { delta, name in
            let core = std.coreWeeks + delta
            guard core >= 2 else { return nil }
            return ProgrammeLength(name: name, weeks: core + tail, standard: delta == 0, phases: std.resized(to: core + tail).phases)
        }
    }

    /// Weeks of Base and Build.
    var coreWeeks: Int { phases.filter { $0.kind == .base || $0.kind == .build }.reduce(0) { $0 + $1.weeks } }

    /// This programme at `weeks` weeks: Base and Build share the change in the catalog's ratio, one week each at least.
    public func resized(to weeks: Int) -> Programme {
        let std = Programme.find(id) ?? self
        let core = std.coreWeeks
        let target = weeks - (std.weeks - core)
        guard target != core, target >= 2, let baseStd = std.phases.first(where: { $0.kind == .base })?.weeks,
              std.phases.contains(where: { $0.kind == .build }) else { return std }
        let base = min(target - 1, max(1, Int((Double(target * baseStd) / Double(core)).rounded())))
        var p = std
        p.phases = std.phases.map { ph in
            switch ph.kind {
            case .base: ProgrammePhase(kind: .base, weeks: base, note: ph.note)
            case .build: ProgrammePhase(kind: .build, weeks: target - base, note: ph.note)
            default: ph
            }
        }
        return p
    }

    /// Programme week `week` as the member gets it, for the programme page: the generated week with its signature
    /// workouts. `starting`: the member has not started it yet (their session count becomes the programme's).
    public func previewWeek(_ week: Int, member: Profile, seed: UInt32, starting: Bool) -> WeekPlan {
        let p = self.profile(from: member, starting: starting)
        let plan = Generator.generateWeek(p, week: cycleWeek(week: week), seed: Programme.seed(seed, week: week))
        return plan.applying(signatureInserts(week: week, plan: plan, profile: p))
    }

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
            // "4 min" and "500 m" (Hyrox ready) are time and distance, not reps.
            let per = d.reps.hasSuffix(" min") ? 60 : d.reps.hasSuffix(" m") ? 0.3 : (e.unit == .sec ? 1 : e.secPerRep ?? 3)
            let work = Double(d.sets) * reps * per * (e.unilateral ? 2 : 1)
            items.append(PlannedExercise(
                uid: "\(base.id)-sig\(n)", exerciseId: e.id, slot: e.pattern,
                prescription: Prescription(sets: d.sets, reps: d.reps, restSec: it.restSec,
                                           intensity: phase == .ease ? "Light: 3+ reps in reserve" : it.target,
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
    public static func insertId(programme: String, signature: String, week: Int) -> UUID {
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

/// One length a programme can run at (#268).
public struct ProgrammeLength: Hashable, Sendable, Identifiable {
    public let name: String
    public let weeks: Int
    /// The catalog's length.
    public let standard: Bool
    public let phases: [ProgrammePhase]
    public var id: Int { weeks }
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
    /// Weeks picked by the member (#268); nil = the programme's standard length.
    public var length: Int?
    /// The member's own programme as it was started (#269); nil for a catalog one.
    public var custom: Programme?
    /// Snow ready (#428): the member's first day on snow the length was fitted to.
    public var firstDay: Date?
    /// Hyrox ready (#431): the race days the season was built around, in order.
    public var races: [Date]?

    public struct SavedPlan: Codable, Hashable, Sendable {
        public var profile: Profile
        public var seed: UInt32
        public var week: Int

        public init(profile: Profile, seed: UInt32, week: Int) {
            self.profile = profile
            self.seed = seed
            self.week = week
        }

        /// The member's own plan back on `current`: only what a programme sets (goal, split, method, focus,
        /// sessions per week) comes from the saved profile; edits made meanwhile (gym, equipment, days…) stay.
        public func restoring(onto current: Profile) -> Profile {
            var p = current
            p.goal = profile.goal
            p.split = profile.split
            p.splitDays = profile.splitDays
            p.method = profile.method
            p.focusMuscles = profile.focusMuscles
            p.sessionsPerWeek = profile.sessionsPerWeek
            return p
        }
    }

    public init(programmeId: String, start: Date, seed: UInt32, saved: SavedPlan, pausedAt: Date? = nil, pausedWeeks: Int = 0,
                length: Int? = nil, custom: Programme? = nil) {
        self.programmeId = programmeId
        self.length = length
        self.custom = custom
        self.start = start
        self.seed = seed
        self.saved = saved
        self.pausedAt = pausedAt
        self.pausedWeeks = pausedWeeks
    }

    /// The programme at the member's length.
    public var programme: Programme? { Programme.find(programmeId, length: length, custom: custom) }
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
    /// Length the member ran it at (#268); nil = standard.
    public var length: Int?
    /// The member's own programme (#269); nil for a catalog one.
    public var custom: Programme?

    public init(id: UUID = UUID(), programmeId: String, start: Date, end: Date, finished: Bool, weeks: Int, length: Int? = nil,
                custom: Programme? = nil) {
        self.id = id
        self.length = length
        self.custom = custom
        self.programmeId = programmeId
        self.start = start
        self.end = end
        self.finished = finished
        self.weeks = weeks
    }

    public var programme: Programme? { Programme.find(programmeId, length: length, custom: custom) }
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
    public static func find(_ id: String) -> Programme? { all.first { $0.id == id } ?? [snowReadySki, snowReadyBoard].first { $0.id == id } }

    /// Catalog programme (or the member's own, `custom`) at `length` weeks (nil = standard).
    public static func find(_ id: String, length: Int?, custom: Programme? = nil) -> Programme? {
        (custom ?? find(id)).map { p in length.map { p.resized(to: $0) } ?? p }
    }

    public static let all: [Programme] = [strengthFoundation, muscleBuilder, climbersPower, athleticEngine, freshStart, snowReadyBoth, hyroxReady]

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

    static let athleticEngine = Programme(
        id: "athletic-engine", name: "Athletic engine",
        tagline: "Jump, lift, condition · 3× a week",
        summary: "Six weeks to be quicker and fitter: jumps and a heavy trap-bar pull on leg day, a kettlebell and slam circuit for conditioning, then you test your pull and swing.",
        symbol: "bolt.heart.fill", palette: .warmup,
        goal: .athletic, sessionsPerWeek: 3, split: .hybrid, method: .undulating, focusMuscles: [],
        phases: [
            ProgrammePhase(kind: .base, weeks: 2, note: "Learn the jumps, moderate pulls, steady circuits"),
            ProgrammePhase(kind: .build, weeks: 2, note: "Heavier pulls, faster circuits"),
            ProgrammePhase(kind: .peak, weeks: 1, note: "Heaviest pulls, sharpest jumps"),
            ProgrammePhase(kind: .test, weeks: 1, note: "Test your trap-bar deadlift and swing"),
        ],
        signatures: [
            ProgrammeSignature(
                id: "jump-lift", name: "Jump + lift", replaces: [.fullLower, .lower, .legs, .fullPower],
                phases: [.base, .build, .peak],
                items: [
                    Item("box-jump", Dose(4, "3"), rest: 90),
                    Item("trap-bar-deadlift", Dose(4, "5"), rest: 180, [.build: Dose(5, "3"), .peak: Dose(5, "2")]),
                    Item("step-up", Dose(3, "8")),
                    Item("dead-bug", Dose(3, "10"), rest: 60),
                ]),
            ProgrammeSignature(
                id: "engine-circuit", name: "Engine circuit", replaces: [.conditioning, .fullPower, .fullUpper],
                phases: [.base, .build, .peak],
                items: [
                    Item("kb-swing", Dose(4, "15"), rest: 60, [.build: Dose(5, "15"), .peak: Dose(5, "12")]),
                    Item("ball-slam", Dose(4, "10"), rest: 60),
                    Item("broad-jump", Dose(3, "5"), rest: 90),
                    Item("goblet-squat", Dose(3, "12"), rest: 60),
                ]),
        ],
        lifts: ["trap-bar-deadlift", "kb-swing"])

    static let freshStart = Programme(
        id: "fresh-start", name: "Fresh start",
        tagline: "New or coming back · 3× a week",
        summary: "Four weeks to learn the basics and build the habit: simple full-body sessions, a few more reps each week, then you see where you stand.",
        symbol: "sparkles", palette: .mobility,
        goal: .balanced, sessionsPerWeek: 3, split: .fullBody, method: .minimal, focusMuscles: [],
        phases: [
            ProgrammePhase(kind: .base, weeks: 2, note: "Learn each move, stop 3 reps before it gets hard"),
            ProgrammePhase(kind: .build, weeks: 1, note: "A little heavier, same moves"),
            ProgrammePhase(kind: .test, weeks: 1, note: "Find your 10-rep bests"),
        ],
        signatures: [
            ProgrammeSignature(
                id: "full-body-basics", name: "Full body basics", replaces: [.fullLower, .fullPower, .lower, .legs],
                phases: [.base, .build],
                items: [
                    Item("goblet-squat", Dose(3, "10"), [.build: Dose(3, "8")]),
                    Item("db-bench", Dose(3, "10"), [.build: Dose(3, "8")]),
                    Item("lat-pulldown", Dose(3, "10")),
                    Item("glute-bridge", Dose(3, "12"), rest: 60),
                    Item("dead-bug", Dose(2, "10"), rest: 60),
                ]),
            ProgrammeSignature(
                id: "pull-hinge-basics", name: "Pull + hinge basics", replaces: [.fullUpper, .upper, .pull, .fullPower],
                phases: [.base, .build],
                items: [
                    Item("seated-cable-row", Dose(3, "10")),
                    Item("db-rdl", Dose(3, "10"), [.build: Dose(3, "8")]),
                    Item("step-up", Dose(2, "8")),
                    Item("plank", Dose(2, "30 s"), rest: 60),
                ]),
        ],
        lifts: ["goblet-squat", "db-bench", "lat-pulldown"])
}

// MARK: - Member-made programmes (#269)

extension Programme {
    /// Phases of a member-made programme at `weeks` weeks: Peak, an easy week from 6 weeks on, and a test week when it
    /// has lifts to test; Base and Build share the rest, Base a little more.
    public static func phases(weeks: Int, test: Bool) -> [ProgrammePhase] {
        let weeks = min(16, max(4, weeks))
        let ease = weeks >= 6 || !test
        let core = max(2, weeks - 1 - (ease ? 1 : 0) - (test ? 1 : 0))
        let base = max(1, min(core - 1, Int((Double(core) * 0.6).rounded())))
        var out = [
            ProgrammePhase(kind: .base, weeks: base, note: "Learn the moves, leave a few reps in reserve"),
            ProgrammePhase(kind: .build, weeks: core - base, note: "Heavier, fewer reps"),
            ProgrammePhase(kind: .peak, weeks: 1, note: "Heaviest week"),
        ]
        if ease { out.append(ProgrammePhase(kind: .ease, weeks: 1, note: "Light week to recover")) }
        if test { out.append(ProgrammePhase(kind: .test, weeks: 1, note: "Test your bests")) }
        return out
    }

    /// Split, method, icon and colours that suit `goal` for a member-made programme.
    public static func defaults(for goal: Goal) -> (split: SplitStyle, method: TrainingMethod, symbol: String, palette: Category) {
        switch goal {
        case .strength: (.fullBody, .block, "figure.strengthtraining.traditional", .power)
        case .build: (.upperLower, .volume, "dumbbell.fill", .strength)
        case .athletic: (.hybrid, .undulating, "bolt.heart.fill", .warmup)
        case .climbing: (.auto, .block, "figure.climbing", .cardio)
        case .endurance: (.hybrid, .autoregulated, "heart.circle.fill", .cardio)
        case .balanced: (.fullBody, .minimal, "sparkles", .mobility)
        }
    }

    /// A member's copy of this programme to edit ("Make it mine").
    public func copy(name: String? = nil) -> Programme {
        var p = self
        p.id = Programme.minePrefix + UUID().uuidString.lowercased()
        p.name = name ?? "My " + self.name.prefix(1).lowercased() + String(self.name.dropFirst())
        p.basedOn = mine ? basedOn : id
        return p
    }
}

extension ProgrammeSignature {
    /// A workout's strength and power exercises as a signature workout (#269). With `progression`, rep exercises
    /// get heavier as the phases go (Build: 2 fewer reps, Peak: about half, Ease: one set less).
    public static func from(id: String, name: String, focus: Focus?, items: [(exerciseId: String, sets: Int, reps: Int, restSec: Int)],
                            progression: Bool) -> ProgrammeSignature {
        var out: [Item] = []
        for it in items {
            guard let e = Exercise.find(it.exerciseId), e.category == .strength || e.category == .power,
                  !out.contains(where: { $0.exerciseId == e.id }) else { continue }
            let sets = max(1, it.sets)
            let measure = CustomWorkout.Measure(e)
            let reps = measure == .seconds ? "\(it.reps) s" : measure == .minutes ? "\(it.reps) min" : "\(it.reps)"
            var byPhase: [ProgrammePhaseKind: Dose] = [:]
            if progression, measure == .reps, it.reps >= 5 {
                byPhase[.build] = Dose(sets, "\(max(3, it.reps - 2))")
                byPhase[.peak] = Dose(sets, "\(max(2, it.reps / 2))")
                byPhase[.ease] = Dose(max(1, sets - 1), reps)
            } else if progression {
                byPhase[.ease] = Dose(max(1, sets - 1), reps)
            }
            out.append(Item(e.id, Dose(sets, reps), rest: max(30, it.restSec), byPhase))
        }
        return ProgrammeSignature(id: id, name: name, replaces: Focus.ranked(focus: focus, exercises: out.map(\.exerciseId)),
                                  phases: [.base, .build, .peak, .ease], items: out)
    }
}

extension Focus {
    /// Session types a workout fits, best first, then every other type so it always finds a day: `focus` when the
    /// workout has one, else from what its exercises train (legs, push, pull).
    static func ranked(focus: Focus?, exercises: [String]) -> [Focus] {
        var lower = 0, push = 0, pull = 0
        for id in exercises {
            switch Exercise.find(id)?.pattern {
            case .squat, .hinge, .singleLeg: lower += 1
            case .hPush, .vPush: push += 1
            case .hPull, .vPull: pull += 1
            default: break
            }
        }
        var best: [Focus]
        if lower > push + pull {
            best = [.legs, .lower, .fullLower, .posterior, .fullPower]
        } else if push > 0, pull > 0, lower == 0 {
            best = [.upper, .fullUpper, .chestBack, .push, .pull]
        } else if push > pull, lower == 0 {
            best = [.push, .chestTri, .upper, .fullUpper, .shouldersArms]
        } else if pull > push, lower == 0 {
            best = [.pull, .backBi, .upper, .fullUpper]
        } else {
            best = [.fullPower, .fullLower, .fullUpper, .conditioning]
        }
        if let focus { best.insert(focus, at: 0) }
        var out: [Focus] = []
        for f in best + Focus.allCases where !out.contains(f) { out.append(f) }
        return out
    }
}
