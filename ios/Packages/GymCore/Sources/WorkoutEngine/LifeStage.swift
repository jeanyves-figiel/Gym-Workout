import Foundation

/// Life-stage programmes (#625, designs A + B + C from `apple-tech-radar/batch4.html`): safe, coach-led blocks for
/// pregnancy, after birth, 50+ and coming back after injury or a break. No medical claims: each starts with a short
/// check-in and a reminder to get a doctor's OK; a safety guard swaps risky moves and says why; loads go by feel.
public enum LifeStage: String, Codable, CaseIterable, Sendable, Identifiable {
    case pregnancy, postpartum, fiftyPlus, backToTraining

    public var id: String { rawValue }

    public var programmeId: String { "life-\(rawValue)" }

    public static func of(programmeId: String?) -> LifeStage? { allCases.first { $0.programmeId == programmeId } }

    public var label: String {
        switch self {
        case .pregnancy: "Pregnancy"
        case .postpartum: "Postpartum"
        case .fiftyPlus: "50+"
        case .backToTraining: "Back to training"
        }
    }

    public var tagline: String {
        switch self {
        case .pregnancy: "Trimester-aware strength"
        case .postpartum: "Core + pelvic floor return"
        case .fiftyPlus: "Balance · bone · power"
        case .backToTraining: "After injury or break"
        }
    }

    /// One swap: the move replaced, its replacement and why.
    public struct Swap: Hashable, Sendable {
        public let from: String
        public let to: String
        public let why: String
    }

    /// What the guard swaps for this stage at this point (trimester 1–3, weeks since birth).
    public func rules(_ check: LifeStageCheckIn?, now: Date) -> [Swap] {
        let jumps = ["box-jump", "depth-jump", "broad-jump", "squat-jump", "tuck-jump", "burpee", "lateral-bound", "plyo-push-up", "jump-rope"]
        let flexion = ["crunch-machine", "sit-up", "decline-sit-up", "v-up", "dragon-flag", "bicycle-crunch", "russian-twist", "toes-to-bar", "ab-wheel"]
        let supine = ["bench-press", "db-bench", "db-floor-press", "lying-leg-raise", "hollow-hold", "dead-bug", "glute-bridge"]
        let heavy = ["back-squat", "deadlift", "sumo-deadlift", "power-clean", "hang-power-clean", "barbell-row"]
        func swap(_ ids: [String], _ to: [String: String], _ why: String) -> [Swap] {
            ids.compactMap { id in to[id].map { Swap(from: id, to: $0, why: why) } }
        }
        let jumpTo = ["box-jump": "step-up", "depth-jump": "step-up", "broad-jump": "goblet-squat", "squat-jump": "goblet-squat",
                      "tuck-jump": "goblet-squat", "burpee": "bird-dog", "lateral-bound": "lateral-lunge", "plyo-push-up": "incline-push-up",
                      "jump-rope": "incline-walk"]
        let flexTo = ["crunch-machine": "dead-bug", "sit-up": "dead-bug", "decline-sit-up": "dead-bug", "v-up": "dead-bug",
                      "dragon-flag": "pallof-press", "bicycle-crunch": "dead-bug", "russian-twist": "pallof-press",
                      "toes-to-bar": "bird-dog", "ab-wheel": "bird-dog"]
        switch self {
        case .pregnancy:
            let tri = check?.trimester(now: now) ?? 1
            var out = swap(jumps, jumpTo, "Pregnancy: no jumping or bounding")
            if tri >= 2 {
                let supTo = ["bench-press": "incline-db-press", "db-bench": "incline-db-press", "db-floor-press": "incline-db-press",
                             "lying-leg-raise": "pallof-press", "hollow-hold": "pallof-press", "dead-bug": "bird-dog",
                             "glute-bridge": "step-up"]
                out += swap(flexion, flexTo.mapValues { $0 == "dead-bug" ? "pallof-press" : $0 }, "\(Self.ordinal(tri)) trimester: no crunching")
                out += swap(supine, supTo, "\(Self.ordinal(tri)) trimester: no lying flat on your back for long")
                out += swap(heavy, ["back-squat": "goblet-squat", "deadlift": "kb-deadlift", "sumo-deadlift": "kb-deadlift",
                                    "power-clean": "kb-deadlift", "hang-power-clean": "kb-deadlift", "barbell-row": "chest-supported-row"],
                            "\(Self.ordinal(tri)) trimester: lighter loads, no breath holding")
            } else {
                out += swap(flexion, flexTo, "1st trimester: gentle core, no crunching")
            }
            return out
        case .postpartum:
            let weeks = check?.weeksSinceBirth(now: now) ?? 0
            guard weeks < 16 else { return swap(["depth-jump", "tuck-jump"], jumpTo, "After birth: build up to impact") }
            return swap(jumps, jumpTo, "After birth: no impact until about week 16")
                + swap(flexion, flexTo, "After birth: core and pelvic floor first, no crunching")
        case .fiftyPlus:
            return swap(["depth-jump", "tuck-jump", "burpee", "dragon-flag", "toes-to-bar"],
                        ["depth-jump": "step-up", "tuck-jump": "squat-jump", "burpee": "bird-dog", "dragon-flag": "dead-bug", "toes-to-bar": "dead-bug"],
                        "50+: power with control, joints first")
        case .backToTraining:
            let weeks = check?.weeksOff ?? 0
            guard weeks >= 4 else { return [] }
            return swap(["depth-jump", "tuck-jump", "power-clean", "hang-power-clean"],
                        ["depth-jump": "step-up", "tuck-jump": "squat-jump", "power-clean": "kb-deadlift", "hang-power-clean": "kb-deadlift"],
                        "Back after \(weeks) weeks: rebuild before high-impact and fast lifts")
        }
    }

    public static func ordinal(_ n: Int) -> String { n == 1 ? "1st" : n == 2 ? "2nd" : "3rd" }

    /// Pace by feel (C): every working set by the talk test.
    public static let talkTest = "Easy–medium · you can still talk"

    /// The plan with the guard applied (B) and loads by feel (C). Swapped items keep their uid; each block that
    /// changed says what and why in its note.
    public func guarded(_ plan: WeekPlan, _ check: LifeStageCheckIn?, now: Date) -> (plan: WeekPlan, swaps: [Swap]) {
        let rules = Dictionary(rules(check, now: now).map { ($0.from, $0) }, uniquingKeysWith: { a, _ in a })
        var used: [Swap] = []
        var out = plan
        out.sessions = plan.sessions.map { s in
            var s = s
            s.blocks = s.blocks.map { b in
                var b = b
                var notes: [String] = []
                b.items = b.items.map { it in
                    var it = it
                    if let r = rules[it.exerciseId], Exercise.find(r.to) != nil {
                        it.exerciseId = r.to
                        let line = "\(Exercise.get(r.from).name) → \(Exercise.get(r.to).name): \(r.why)"
                        if !notes.contains(line) { notes.append(line) }
                        if !used.contains(r) { used.append(r) }
                    }
                    if [.power, .strength].contains(b.kind) { it.prescription.intensity = Self.talkTest }
                    return it
                }
                if !notes.isEmpty { b.note = (["Swapped for you · " + notes.joined(separator: " · ")] + [b.note].compactMap { $0 }).joined(separator: " ") }
                return b
            }
            return s
        }
        return (out, used)
    }
}

/// The short check-in a life-stage programme starts with (#625 A). Stored with the profile.
public struct LifeStageCheckIn: Codable, Hashable, Sendable {
    public var stage: LifeStage
    /// Pregnancy: due date (trimester follows it).
    public var dueDate: Date?
    /// Postpartum: the birth.
    public var birthDate: Date?
    /// Back to training: weeks without training.
    public var weeksOff: Int?
    /// The member confirmed a doctor or midwife said exercise is OK.
    public var doctorOK: Bool
    public var at: Date

    public init(stage: LifeStage, dueDate: Date? = nil, birthDate: Date? = nil, weeksOff: Int? = nil, doctorOK: Bool, at: Date = Date()) {
        self.stage = stage
        self.dueDate = dueDate
        self.birthDate = birthDate
        self.weeksOff = weeksOff
        self.doctorOK = doctorOK
        self.at = at
    }

    /// 1–3 from the due date (40 weeks); 1 without one.
    public func trimester(now: Date) -> Int {
        guard let dueDate else { return 1 }
        let weeksLeft = dueDate.timeIntervalSince(now) / (7 * 86_400)
        let week = 40 - weeksLeft
        return week < 14 ? 1 : week < 28 ? 2 : 3
    }

    public func weeksSinceBirth(now: Date) -> Int {
        guard let birthDate else { return 0 }
        return max(0, Int(now.timeIntervalSince(birthDate) / (7 * 86_400)))
    }
}

extension Programme {
    public var lifeStage: LifeStage? { LifeStage.of(programmeId: id) }

    private typealias Item = ProgrammeSignature.Item
    private typealias Dose = ProgrammeSignature.Dose

    private static func life(_ stage: LifeStage, summary: String, symbol: String, palette: Category, focus: [MuscleGroup],
                             phases: [ProgrammePhase], signature: ProgrammeSignature, lifts: [String]) -> Programme {
        Programme(id: stage.programmeId, name: stage.label, tagline: "\(stage.tagline) · 3× a week", summary: summary, symbol: symbol,
                  palette: palette, goal: .balanced, sessionsPerWeek: 3, split: .fullBody, method: .autoregulated,
                  focusMuscles: focus, phases: phases, signatures: [signature], lifts: lifts)
    }

    static let lifePregnancy = life(
        .pregnancy,
        summary: "Strength through pregnancy, adjusted by trimester: no jumping, gentle core, and from the 2nd trimester no lying flat on your back for long and lighter loads. Every set by feel: you can still talk. Check with your doctor or midwife first.",
        symbol: "figure.walk", palette: .stretch, focus: [.legs, .back, .core],
        phases: [ProgrammePhase(kind: .base, weeks: 4, note: "Steady strength, posture and breathing"),
                 ProgrammePhase(kind: .build, weeks: 4, note: "Same moves, a little more, still by feel"),
                 ProgrammePhase(kind: .ease, weeks: 1, note: "Easy week, check in again")],
        signature: ProgrammeSignature(id: "pregnancy-strong", name: "Strong and steady", replaces: [.fullLower, .fullUpper, .lower, .upper],
                                      phases: [.base, .build], items: [
            Item("goblet-squat", Dose(3, "10")), Item("chest-supported-row", Dose(3, "10")), Item("step-up", Dose(2, "8")),
            Item("pallof-press", Dose(2, "10"), rest: 60), Item("bird-dog", Dose(2, "8"), rest: 60),
        ]),
        lifts: [])

    static let lifePostpartum = life(
        .postpartum,
        summary: "A gentle return after birth: breathing, core and pelvic floor first, then strength, and impact only from about week 16. Loads by feel, no PR chasing. Get your doctor's OK first, and see a pelvic health physio if anything feels off.",
        symbol: "figure.and.child.holdinghands", palette: .stretch, focus: [.core, .hips, .back],
        phases: [ProgrammePhase(kind: .base, weeks: 4, note: "Breathing, core connection, light strength"),
                 ProgrammePhase(kind: .build, weeks: 4, note: "More strength, carries, single leg"),
                 ProgrammePhase(kind: .ease, weeks: 1, note: "Easy week, check in again")],
        signature: ProgrammeSignature(id: "postpartum-core", name: "Core return", replaces: [.fullLower, .fullUpper, .lower, .upper],
                                      phases: [.base, .build], items: [
            Item("glute-bridge", Dose(3, "10"), rest: 60), Item("dead-bug", Dose(3, "6"), rest: 60), Item("bird-dog", Dose(2, "8"), rest: 60),
            Item("goblet-squat", Dose(3, "8")), Item("suitcase-carry", Dose(2, "30 s"), rest: 60),
        ]),
        lifts: [])

    static let lifeFiftyPlus = life(
        .fiftyPlus,
        summary: "Strength for the decades ahead: balance and single-leg work against falls, loaded squats and hinges for bone, and quick-but-controlled power. Loads by feel; consistency is the streak.",
        symbol: "figure.strengthtraining.functional", palette: .strength, focus: [.legs, .hips, .core],
        phases: [ProgrammePhase(kind: .base, weeks: 3, note: "Balance, single leg, steady strength"),
                 ProgrammePhase(kind: .build, weeks: 3, note: "Heavier squats and hinges for bone"),
                 ProgrammePhase(kind: .peak, weeks: 1, note: "Power with control: fast up, slow down"),
                 ProgrammePhase(kind: .ease, weeks: 1, note: "Easy week")],
        signature: ProgrammeSignature(id: "fifty-balance", name: "Balance · bone · power", replaces: [.fullLower, .lower, .legs],
                                      phases: [.base, .build, .peak], items: [
            Item("goblet-squat", Dose(3, "8"), [.build: Dose(4, "6")]), Item("kb-deadlift", Dose(3, "8"), [.build: Dose(4, "6")]),
            Item("single-leg-rdl", Dose(2, "8")), Item("step-up", Dose(2, "8")), Item("farmer-carry", Dose(3, "30 s"), rest: 60),
        ]),
        lifts: ["goblet-squat", "kb-deadlift"])

    static let lifeBackToTraining = life(
        .backToTraining,
        summary: "Back after an injury or a long break: lighter loads that build week by week, fast and high-impact moves later, everything by feel. If you are coming back from an injury, follow your physio's limits.",
        symbol: "arrow.uturn.forward", palette: .cardio, focus: [.legs, .back, .chest],
        phases: [ProgrammePhase(kind: .base, weeks: 2, note: "Light and smooth: find the moves again"),
                 ProgrammePhase(kind: .build, weeks: 3, note: "Build back load, still by feel"),
                 ProgrammePhase(kind: .ease, weeks: 1, note: "Easy week, then your plan")],
        signature: ProgrammeSignature(id: "back-basics", name: "Basics again", replaces: [.fullLower, .fullUpper, .lower, .upper],
                                      phases: [.base, .build], items: [
            Item("goblet-squat", Dose(3, "10")), Item("incline-db-press", Dose(3, "10")), Item("chest-supported-row", Dose(3, "10")),
            Item("kb-deadlift", Dose(2, "10")), Item("plank", Dose(2, "30 s"), rest: 60),
        ]),
        lifts: [])

    public static let lifeStages: [Programme] = [lifePregnancy, lifePostpartum, lifeFiftyPlus, lifeBackToTraining]
}
