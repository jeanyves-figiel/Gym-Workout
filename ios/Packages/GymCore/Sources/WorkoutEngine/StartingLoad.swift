import Foundation

/// Who is lifting, for first-time load estimates. Every field is optional; sensible defaults fill the gaps.
public struct Athlete: Sendable, Hashable {
    public enum Sex: Sendable, Hashable {
        case female, male, unspecified
    }

    public var bodyKg: Double?
    public var sex: Sex
    public var age: Int?
    public var experience: Experience
    /// Fat-free mass from body fat (#185): strength follows muscle, not total weight.
    public var leanKg: Double?
    /// Latest upper arm / thigh girth (#185): refine arm and leg estimates a little.
    public var upperArmCm: Double?
    public var thighCm: Double?

    public init(bodyKg: Double? = nil, sex: Sex = .unspecified, age: Int? = nil, experience: Experience = .beginner,
                leanKg: Double? = nil, upperArmCm: Double? = nil, thighCm: Double? = nil) {
        self.bodyKg = bodyKg
        self.sex = sex
        self.age = age
        self.experience = experience
        self.leanKg = leanKg
        self.upperArmCm = upperArmCm
        self.thighCm = thighCm
    }
}

/// Starting load for an exercise that was never logged (#115): from a related exercise the member did log,
/// else from body weight, sex, age and experience. Deliberately conservative: the first session should feel
/// easy rather than fail, and double progression takes over from there.
public enum StartingLoad {
    /// What the weight is lifted with; loads differ a lot between a barbell, one dumbbell and a stack.
    enum Implement: Equatable {
        case barbell, dumbbell, machine
    }

    static func implement(_ e: Exercise) -> Implement? {
        let eq = Set(e.equipment)
        if !eq.isDisjoint(with: [.barbell, .trapBar, .smith, .landmine]) { return .barbell }
        if !eq.isDisjoint(with: [.dumbbells, .kettlebells]) { return .dumbbell }
        let stacks: Set<Equipment> = [.cable, .legPress, .hackSquat, .legCurl, .legExtension, .latPulldown, .seatedRow,
                                      .chestPress, .pecDeck, .hipThrustMachine]
        if !eq.isDisjoint(with: stacks) { return .machine }
        return nil
    }

    /// Estimated one-rep max as a multiple of body weight for an intermediate male lifter, with the
    /// implement it is usually done with (lateral raises and isolation machines are rated on their own kit).
    static func ratio(_ p: Pattern) -> Double? {
        switch p {
        case .squat: 1.25
        case .hinge: 1.5
        case .singleLeg: 0.6
        case .hPush: 1.0
        case .vPush: 0.6
        case .hPull: 0.8
        case .vPull: 0.85
        case .armsFlex: 0.45
        case .armsExt: 0.4
        case .lateralRaise, .shoulderHealth: 0.12
        case .kneeExt: 0.7
        case .kneeFlex: 0.55
        case .calves: 1.2
        default: nil
        }
    }

    static func isLowerBody(_ p: Pattern) -> Bool {
        [.squat, .hinge, .singleLeg, .kneeExt, .kneeFlex, .calves].contains(p)
    }

    /// Load relative to the barbell version: one dumbbell is far lighter, a stack a bit lighter.
    static func implementFactor(_ i: Implement, pattern p: Pattern, equipment eq: [Equipment] = []) -> Double {
        // A leg press sled moves a lot more than a barbell squat.
        if eq.contains(.legPress) { return 1.6 }
        // Ratios for these are already per dumbbell / per machine.
        if [.lateralRaise, .shoulderHealth].contains(p) { return 1 }
        if [.kneeExt, .kneeFlex, .calves].contains(p) { return i == .dumbbell ? 0.3 : 1 }
        switch i {
        case .barbell: return 1
        case .machine: return 0.9
        case .dumbbell:
            switch p {
            case .hPull: return 0.45
            case .armsFlex, .armsExt: return 0.45
            case .singleLeg: return 0.5
            default: return 0.38
            }
        }
    }

    /// Load for `reps` reps leaving `rir` in reserve, from a one-rep max (inverse Epley).
    static func working(oneRM: Double, reps: Int, rir: Int) -> Double {
        oneRM / (1 + Double(reps + rir) / 30)
    }

    /// Rounds down to the equipment step, never below the lightest sensible load.
    static func finish(_ kg: Double, exercise e: Exercise, implement i: Implement) -> Double {
        let step = LoadAdvisor.steps(for: e, kg: kg).granularity
        let floor: Double = switch i {
        case .barbell: Set(e.equipment).contains(.barbell) && !Set(e.equipment).contains(.smith) ? 20 : step
        case .dumbbell: 2
        case .machine: step * 2
        }
        return max(floor, LoadAdvisor.round(kg, to: step, .down))
    }

    static func target(_ p: Prescription) -> (reps: Int, rir: Int)? {
        guard let reps = p.repRange?.low else { return nil }
        return (reps, p.targetRIR ?? 2)
    }

    /// First-time load from body weight. Nil for body-weight, timed or unrated movements.
    public static func estimate(exercise e: Exercise, prescription p: Prescription, athlete a: Athlete) -> LoadSuggestion? {
        guard e.unit != .sec, let base = ratio(e.pattern), let imp = implement(e), let t = target(p) else { return nil }
        let lower = isLowerBody(e.pattern)
        let sexFactor: Double = switch a.sex {
        case .male: 1
        case .female: lower ? 0.75 : 0.6
        case .unspecified: lower ? 0.87 : 0.8
        }
        let bodyKg = a.bodyKg.flatMap { $0 > 30 && $0 < 250 ? $0 : nil } ?? (a.sex == .female ? 63 : a.sex == .male ? 78 : 70)
        let levelFactor: Double = switch a.experience {
        case .beginner: 0.65
        case .intermediate: 1
        case .advanced: 1.3
        }
        var ageFactor = 1.0
        if let age = a.age {
            if age > 40 { ageFactor = max(0.7, 1 - 0.01 * Double(age - 40)) } else if age < 18 { ageFactor = 0.85 }
        }
        // Single-limb work on a barbell/stack moves less than the bilateral lift the ratio describes.
        let unilateral = e.unilateral && imp != .dumbbell && e.pattern != .singleLeg ? 0.5 : 1
        let body = bodyFactors(a, bodyKg: bodyKg, pattern: e.pattern)
        let oneRM = bodyKg * body.factor * base * sexFactor * levelFactor * ageFactor
            * implementFactor(imp, pattern: e.pattern, equipment: e.equipment) * unilateral
        // 15 % under the estimate: the first session calibrates, it doesn't test.
        let kg = finish(working(oneRM: oneRM, reps: t.reps, rir: t.rir) * 0.85, exercise: e, implement: imp)
        let from = body.used.isEmpty ? "body weight (\(LoadAdvisor.formatKg(bodyKg)) kg)" : body.used.joined(separator: ", ")
        return LoadSuggestion(kg: kg, reps: t.reps, action: .hold, basisKg: kg,
                              reason: "Estimate from \(from) and \(a.experience.rawValue) level",
                              source: .estimate)
    }

    /// Typical lean share of body weight per sex: the ratios above assume this build.
    static func typicalLeanShare(_ s: Athlete.Sex) -> Double {
        switch s {
        case .male: 0.84
        case .female: 0.74
        case .unspecified: 0.79
        }
    }

    /// Typical relaxed-flexed upper arm and thigh girth (cm) at the default body weight per sex.
    static func typicalGirth(_ s: Athlete.Sex) -> (arm: Double, thigh: Double, kg: Double) {
        switch s {
        case .male: (34, 56, 78)
        case .female: (29, 55, 63)
        case .unspecified: (31.5, 55.5, 70)
        }
    }

    static let maxLeanShift = 0.15
    static let maxGirthShift = 0.08

    /// Body-composition refinements (#185), each capped so a typo can't swing a load:
    /// lean mass vs the typical lean share (±15 %), and arm girth for arm work / thigh girth for knee-dominant
    /// leg work vs the typical girth at this body weight (±8 %; girth grows with √weight).
    static func bodyFactors(_ a: Athlete, bodyKg: Double, pattern p: Pattern) -> (factor: Double, used: [String]) {
        var f = 1.0
        var used: [String] = []
        if let lean = a.leanKg, lean > 20, lean < bodyKg {
            let shift = lean / (bodyKg * typicalLeanShare(a.sex))
            f *= min(1 + maxLeanShift, max(1 - maxLeanShift, shift))
            used.append("lean mass (\(LoadAdvisor.formatKg((lean * 10).rounded() / 10)) kg)")
        }
        let typical = typicalGirth(a.sex)
        let scale = (bodyKg / typical.kg).squareRoot()
        var girth: (cm: Double?, typical: Double, name: String)?
        switch p {
        case .armsFlex, .armsExt: girth = (a.upperArmCm, typical.arm, "arm")
        case .squat, .singleLeg, .kneeExt, .kneeFlex: girth = (a.thighCm, typical.thigh, "thigh")
        default: girth = nil
        }
        if let g = girth, let cm = g.cm, cm > 10, cm < 120 {
            f *= min(1 + maxGirthShift, max(1 - maxGirthShift, cm / (g.typical * scale)))
            used.append("\(g.name) girth (\(LoadAdvisor.formatKg(cm)) cm)")
        }
        if !used.isEmpty { used.insert("body weight (\(LoadAdvisor.formatKg(bodyKg)) kg)", at: 0) }
        return (f, used)
    }

    /// First-time load from the best recent set of a logged exercise with the same movement pattern
    /// (e.g. bench press → incline bench press), converted between barbell, dumbbell and machine.
    /// `related` pairs each logged exercise with its sessions, oldest first.
    public static func fromRelated(
        exercise e: Exercise, prescription p: Prescription, related: [(exercise: Exercise, sessions: [ExerciseSession])]
    ) -> LoadSuggestion? {
        guard e.unit != .sec, ratio(e.pattern) != nil, let imp = implement(e), let t = target(p) else { return nil }
        var best: (date: Date, oneRM: Double, name: String)?
        for r in related where r.exercise.id != e.id && r.exercise.pattern == e.pattern && r.exercise.unilateral == e.unilateral {
            guard let srcImp = implement(r.exercise),
                  let s = r.sessions.last(where: { !$0.deload && $0.bestOneRepMax != nil }), let orm = s.bestOneRepMax else { continue }
            // Same kit: a variant (−10 %); different kit: convert and stay a bit more careful.
            let factor = implementFactor(imp, pattern: e.pattern, equipment: e.equipment)
                / implementFactor(srcImp, pattern: e.pattern, equipment: r.exercise.equipment) * (srcImp == imp ? 0.9 : 0.85)
            if best == nil || s.date > best!.date { best = (s.date, orm * factor, r.exercise.name) }
        }
        guard let best else { return nil }
        let kg = finish(working(oneRM: best.oneRM, reps: t.reps, rir: t.rir), exercise: e, implement: imp)
        return LoadSuggestion(kg: kg, reps: t.reps, action: .hold, basisKg: kg,
                              reason: "Estimate from your \(best.name.lowercased())", source: .related)
    }
}
