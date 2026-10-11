import Foundation

/// Builds weekly plans: warm-up → explosive → strength → mobility → cardio → cool-down.
public enum Generator {
    public static let mesocycleWeeks = Rules.mesocycleWeeks
    static let transitionSec = 30.0

    // MARK: Session length

    public static func isClimber(_ p: Profile) -> Bool { p.goal == .climbing || p.climbingDaysPerWeek >= 1 }

    /// Goal × weekly frequency × experience × climbing load, capped by the user limit.
    /// Fewer sessions → longer sessions; total weekly time still grows with frequency.
    public static func sessionMinutes(_ p: Profile) -> Int {
        let g = p.goal.config
        let raw = g.baseMinutes * (Rules.frequencyFactor[p.sessionsPerWeek] ?? 1)
            + Rules.experienceDelta(p.experience)
            - 2 * Double(max(0, p.climbingDaysPerWeek - 1))
        let clamped = min(Double(Rules.maxSession), max(Double(Rules.minSession), raw))
        let rounded = round5(clamped)
        let cap = p.maxSessionMinutes.map { max(Rules.minSession - 10, $0) } ?? Rules.maxSession
        return min(rounded, cap)
    }

    public static func weekLabel(_ week: Int) -> String {
        ["Base · RPE −1", "Build · target RPE", "Peak · +1 set on main lifts", "Deload · −40% volume"][phaseIndex(week)]
    }

    /// 0-based position of `week` in the 4-week cycle (Base, Build, Peak, Deload).
    /// Single source of truth for every screen that shows the current phase.
    public static func phaseIndex(_ week: Int) -> Int { ((max(1, week) - 1) % mesocycleWeeks) }

    /// Phase name only ("Base", "Build", "Peak", "Deload").
    public static func phaseName(_ week: Int) -> String {
        weekLabel(week).components(separatedBy: " · ").first ?? ""
    }

    // MARK: Week

    public static func generateWeek(_ profile: Profile, week: Int = 1, seed: UInt32) -> WeekPlan {
        var profile = profile
        profile.syncClimbingDays()
        let week = min(mesocycleWeeks, max(1, week))
        let ctx = Ctx(profile: profile, week: week, seed: seed)
        if ctx.variety == .same && week != 1 {
            ctx.replay = record(profile, seed: seed)
        }
        return generateWeek(ctx)
    }

    static func generateWeek(_ ctx: Ctx) -> WeekPlan {
        let profile = ctx.profile, week = ctx.week
        let base = sessionMinutes(profile)
        let minutes = ctx.deload ? max(Rules.minSession - 5, round5(Double(base) * 0.8)) : base
        let baseSplit = Rules.splits[profile.sessionsPerWeek] ?? Rules.splits[3]!
        let rotate = ctx.variety == .rotate
        let split = rotate ? Rules.rotatedSplit(baseSplit, week: week) : baseSplit
        // With climbing / gym weekdays set, sessions are re-ordered and placed on weekdays.
        let prefs = profile.climbPrefs
        let slots = WeekSchedule.assign(split, climbing: profile.climbingDays, gym: profile.gymDays, prefs: prefs)
        let order = slots?.map(\.focus) ?? split
        var seen: [Focus: Int] = [:]
        let rotation = profile.goal.config.cardio
        var sessions: [Session] = []
        for (i, focus) in order.enumerated() {
            let n = seen[focus, default: 0]
            seen[focus] = n + 1
            let mode: CardioMode = focus == .conditioning ? .intervals : rotation[i % rotation.count]
            let weekday = slots?[i].weekday
            let beforeClimb = weekday.map { profile.climbingDays.contains(WeekSchedule.next($0)) } ?? false
            // Day before climbing (#47): light/rest → no jumps + grip spared; strong → grip spared only.
            ctx.preClimb = beforeClimb && (prefs.before == .light || prefs.before == .rest)
            ctx.preClimbGrip = beforeClimb && prefs.before == .strong
            // `.rotate`: A/B slot orders swap weekly too.
            let variant = (n + (rotate ? week - 1 : 0)) % 2
            var session = generateSession(ctx, focus: focus, variant: variant, index: i, minutes: minutes, cardio: mode)
            session.weekday = weekday
            sessions.append(session)
        }
        ctx.preClimb = false
        ctx.preClimbGrip = false
        return WeekPlan(week: week, deload: ctx.deload, seed: ctx.seed, sessionMinutes: minutes, sessions: sessions)
    }

    /// Week 1's picks for `.same` replays: only those that made it into the plan, so a later week never swaps
    /// in an exercise week 1 dropped for time.
    static func record(_ profile: Profile, seed: UInt32) -> [String: String] {
        let ctx = Ctx(profile: profile, week: 1, seed: seed)
        let plan = generateWeek(ctx)
        var kept: [String: Set<String>] = [:]
        for s in plan.sessions {
            kept["s\(s.index + 1)-"] = Set(s.blocks.flatMap { $0.items.flatMap { [$0.exerciseId] + [$0.pairedWith].compactMap { $0 } } })
        }
        return ctx.picks.filter { key, id in
            kept[String(key.prefix { $0 != "-" }) + "-"]?.contains(id) ?? false
        }
    }

    // MARK: Session

    static func generateSession(_ ctx: Ctx, focus: Focus, variant: Int, index: Int, minutes: Int, cardio: CardioMode) -> Session {
        let id = "w\(ctx.week)s\(index + 1)"
        ctx.usedSession = []
        let warm = clamp(Int((Double(minutes) * 0.12).rounded()), 6, 10)
        let cool = clamp(Int((Double(minutes) * 0.11).rounded()), 6, 10)
        let work = Double(minutes - warm - cool)
        let mix = sessionMix(ctx.profile, focus)

        var powerMin = Int((work * mix.power).rounded())
        var mobilityMin = Int((work * mix.mobility).rounded())
        var cardioMin = Int((work * mix.cardio).rounded())
        if powerMin < 4 { powerMin = 0 }
        if mobilityMin < 3 { mobilityMin = 0 }
        if cardioMin < 6 { cardioMin = 0 }
        let strengthMin = Int(work) - powerMin - mobilityMin - cardioMin

        var regions = Rules.regions(focus)
        if ctx.climber { for r in [Region.hips, .shoulders] where !regions.contains(r) { regions.append(r) } }

        var blocks: [Block] = [warmup(ctx, focus, warm, "\(id)-wu")]
        // Climbing tomorrow: no explosive block, its time goes to (grip-sparing) strength work.
        let pw = ctx.preClimb ? nil : power(ctx, focus, powerMin, "\(id)-pw")
        if let pw { blocks.append(pw) }
        let powerLeft = pw.map { max(0, powerMin - Int($0.estMin.rounded())) } ?? powerMin
        var st = strength(ctx, focus, variant, strengthMin + powerLeft, "\(id)-st", regions, leadStep: ctx.week - 1 + index)
        // Supersets / circuits (#78); the rest time they save goes back into extra rounds (not in a deload week).
        let grouping = focus == .conditioning ? Grouping.straight : ctx.profile.group
        st = applyGrouping(st, grouping)
        if grouping != .straight && !ctx.deload { st = fillGroupedTime(st, targetMin: st.targetMin) }
        if ctx.preClimb {
            st.note = ["Climbing tomorrow: no jumps or heavy grip work today.", st.note].compactMap { $0 }.joined(separator: " ")
        } else if ctx.preClimbGrip {
            st.note = ["Climbing tomorrow: push hard, keep heavy pulling and grip light.", st.note].compactMap { $0 }.joined(separator: " ")
        }
        blocks.append(st)
        if let mo = mobility(ctx, focus, mobilityMin, "\(id)-mo") { blocks.append(mo) }
        if let ca = cardioBlock(ctx, cardio, cardioMin, "\(id)-ca") { blocks.append(ca) }
        blocks.append(cooldown(ctx, cool, blocks, "\(id)-cd"))

        let est = Int(blocks.reduce(0) { $0 + $1.estMin }.rounded())
        return Session(id: id, index: index, focus: focus, title: "Day \(index + 1) · \(focus.label)", targetMin: minutes, estMin: est, blocks: blocks)
    }

    static func sessionMix(_ p: Profile, _ focus: Focus) -> Mix {
        let g = p.goal.config.mix
        let f = Rules.focusMix(focus)
        var m = Mix(power: g.power * f.power, strength: g.strength * f.strength, mobility: g.mobility * f.mobility, cardio: g.cardio * f.cardio)
        if p.goal != .climbing && p.climbingDaysPerWeek >= 1 { m.mobility *= 1.3 }
        return m.normalised
    }

    // MARK: Helpers

    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, v)) }
    static func round5(_ v: Double) -> Int { Int((v / 5).rounded()) * 5 }

    static func workSec(_ e: Exercise, repsMid: Int, holdSec: Double = 40) -> Double {
        (e.unit == .sec ? holdSec : Double(repsMid) * (e.secPerRep ?? 3)) * (e.unilateral ? 2 : 1)
    }

    static func itemSec(_ e: Exercise, _ p: Prescription, repsMid: Int, holdSec: Double = 40) -> Double {
        Double(p.sets) * workSec(e, repsMid: repsMid, holdSec: holdSec) + Double(max(0, p.sets - 1) * p.restSec) + transitionSec
    }

    static func perSide(_ e: Exercise) -> String { e.unilateral ? " / side" : "" }

    static func rpe(_ ctx: Ctx, _ base: Int) -> Int {
        if ctx.deload { return base - 2 }
        if ctx.week % mesocycleWeeks == 1 { return base - 1 }
        return base
    }

    // MARK: Warm-up

    static let raiseUpper = ["rower", "ski-erg", "air-bike", "elliptical"]
    static let raiseLower = ["bike", "incline-walk", "rower", "elliptical", "stair-climber"]

    static func warmup(_ ctx: Ctx, _ focus: Focus, _ minutes: Int, _ uid: String) -> Block {
        ctx.begin(uid)
        let upper = [Focus.upper, .push, .pull, .fullUpper].contains(focus)
        let raiseMin = minutes >= 9 ? 5 : 4
        var items: [PlannedExercise] = []
        if let raise = Selector.select(ctx, Query(category: .cardio, prefer: upper ? raiseUpper : raiseLower)) {
            items.append(PlannedExercise(
                uid: "\(uid)-0", exerciseId: raise.id, slot: .general,
                prescription: Prescription(sets: 1, reps: "\(raiseMin) min", restSec: 0, intensity: "Easy → moderate · RPE 3–5"),
                estSec: raiseMin * 60))
        }
        var regions = Rules.regions(focus)
        if ctx.climber && !regions.contains(.wrists) { regions.append(.wrists) }
        let drills = clamp(Int((Double(minutes - raiseMin) / 0.9).rounded()), 3, 6)
        for i in 0..<drills {
            guard let d = Selector.select(ctx, Query(category: .warmup, regions: [regions[i % regions.count]])) else { continue }
            items.append(PlannedExercise(
                uid: "\(uid)-\(items.count)", exerciseId: d.id, slot: .general,
                prescription: Prescription(sets: 1, reps: d.unilateral ? "6 / side" : "8–10", restSec: 0),
                estSec: 50))
        }
        return Block(kind: .warmup, title: "Warm-up", targetMin: minutes, items: items,
                     note: "Raise heart rate, then move through today's ranges. Ramp-up sets for the first lift come in the strength block.")
    }

    // MARK: Power

    static func power(_ ctx: Ctx, _ focus: Focus, _ minutes: Int, _ uid: String) -> Block? {
        guard minutes >= 4 else { return nil }
        ctx.begin(uid)
        let budget = Double(minutes * 60)
        let patterns = Rules.powerPatterns(focus)
        var items: [PlannedExercise] = []
        var used = 0.0
        var i = 0
        while i < patterns.count * 2 && used < budget * 0.9 {
            defer { i += 1 }
            guard let e = Selector.select(ctx, Query(category: .power, pattern: patterns[i % patterns.count])) else { continue }
            let baseSets = ctx.profile.goal == .athletic && ctx.profile.experience != .beginner ? 4 : 3
            let isSec = e.unit == .sec
            let p = Prescription(
                sets: ctx.deload ? baseSets - 1 : baseSets,
                reps: isSec ? "15 s" : "\(e.id == "kb-swing" ? "8–10" : "3–5")\(perSide(e))",
                restSec: isSec ? 75 : 60,
                intensity: "Max intent · stop before speed drops")
            let est = itemSec(e, p, repsMid: e.id == "kb-swing" ? 9 : 4, holdSec: 15)
            if !items.isEmpty && used + est > budget * 1.1 { break }
            items.append(PlannedExercise(uid: "\(uid)-\(items.count)", exerciseId: e.id, slot: e.pattern, prescription: p, estSec: Int(est.rounded())))
            used += est
        }
        guard !items.isEmpty else { return nil }
        return Block(kind: .power, title: "Explosive", targetMin: minutes, items: items,
                     note: "Done fresh, before strength work. Alternate exercises (A1/A2) so each gets full recovery; quality reps only.")
    }

    // MARK: Strength

    static func climberSlots(_ slots: [Pattern], _ focus: Focus, _ ctx: Ctx) -> [Pattern] {
        guard ctx.climber else { return slots }
        var out = slots
        if ![Focus.lower, .legs].contains(focus) {
            // Prehab right after the main lift so it survives short sessions.
            out.removeAll { $0 == .shoulderHealth || $0 == .forearmAntagonist }
            out.insert(.shoulderHealth, at: min(1, out.count))
            out.insert(.forearmAntagonist, at: min(2, out.count))
        }
        if ctx.spareGrip { out.removeAll { $0 == .armsFlex } }
        return out
    }

    static func dose(_ ctx: Ctx, isMain: Bool, circuit: Bool, _ pattern: Pattern, _ e: Exercise) -> (Prescription, Int) {
        let g = ctx.profile.goal.config
        let beginner = ctx.profile.experience == .beginner
        let light = Rules.lightPatterns.contains(pattern)
        var d: Dose
        if isMain { d = g.main }
        else if light { d = Dose(sets: beginner ? 2 : 3, reps: e.unit == .sec ? "30–45 s" : "12–15", repsMid: 13, restSec: 45, rpe: 7) }
        else { d = g.accessory }
        if circuit { d.sets = 3; d.restSec = 30; d.rpe = 7 }
        else { d.restSec = ctx.profile.rest.restSec(d.restSec, main: isMain, light: light) }

        var sets = d.sets - (beginner && !light && !circuit ? 1 : 0)
        if isMain && ctx.week % mesocycleWeeks == 3 && !beginner { sets += 1 }
        var notes: [String] = []
        if ctx.spareGrip && (pattern == .vPull || pattern == .hPull) {
            sets = max(2, sets - 1)
            notes.append("Reduced: climbing already loads pulling")
        }
        if ctx.deload { sets = max(1, Int((Double(sets) * 0.6).rounded())) }
        if isMain { notes.insert("2–3 ramp-up sets first", at: 0) }

        let reps = pattern == .carry ? "40 s" : (e.unit == .sec && !light ? "30–45 s" : d.reps)
        return (Prescription(sets: sets, reps: reps + perSide(e), restSec: d.restSec, intensity: "RPE \(rpe(ctx, d.rpe))",
                             note: notes.isEmpty ? nil : notes.joined(separator: " · ")), d.repsMid)
    }

    static func strength(_ ctx: Ctx, _ focus: Focus, _ variant: Int, _ minutes: Int, _ uid: String, _ pairRegions: [Region], leadStep: Int = 0) -> Block {
        ctx.begin(uid)
        let budget = Double(minutes * 60)
        let circuit = focus == .conditioning
        var base = Rules.strengthSlots(focus, variant: variant)
        if ctx.variety == .rotate { base = Rules.rotatingLead(base, focus, step: leadStep) }
        let slots = climberSlots(base, focus, ctx)
        var items: [PlannedExercise] = []
        var pairUsed: Set<String> = []
        var used = 0.0

        for (i, pattern) in slots.enumerated() {
            if items.count >= 2 && used >= budget * 1.05 { break }
            let isMain = items.isEmpty && !circuit
            guard let e = Selector.select(ctx, Query(category: .strength, pattern: pattern, main: isMain)) else { continue }
            var (p, repsMid) = dose(ctx, isMain: isMain, circuit: circuit, pattern, e)

            // Light prehab/core work is supersetted into the rest of the last heavy exercise.
            let light = Rules.lightPatterns.contains(pattern) && !circuit
            let hostIndex = light ? items.lastIndex { !Rules.lightPatterns.contains($0.slot) } : nil
            // Long rests (≥ 2 min) fit two prehab partners, shorter rests one.
            let superset = hostIndex.map { h in
                let rest = items[h].prescription.restSec
                let partners = items.filter { $0.supersetWith == items[h].uid }.count
                return rest >= 75 && partners < (rest >= 120 ? 2 : 1)
            } ?? false

            var est = superset ? Double(p.sets) * workSec(e, repsMid: repsMid) + transitionSec : itemSec(e, p, repsMid: repsMid)
            if isMain { est += 180 } // ramp-up sets
            if items.count >= 2 && used + est > budget * 1.1 {
                ctx.usedSession.remove(e.id)
                ctx.usedWeek.remove(e.id)
                continue
            }

            var paired: String?
            if superset, let h = hostIndex {
                items[h].pairedWith = nil // rest now used by the superset
                p.note = ["Superset: do in rest of \(Exercise.get(items[h].exerciseId).name)", p.note].compactMap { $0 }.joined(separator: " · ")
            } else if p.restSec >= 90 {
                let region = pairRegions[(items.count + i) % pairRegions.count]
                let m = Selector.candidates(level: ctx.level, equipment: ctx.equipment, Query(category: .mobility, regions: [region]))
                    .filter { !pairUsed.contains($0.id) && !ctx.usedSession.contains($0.id) }
                if !m.isEmpty, let pick = ctx.pickPaired(m) {
                    pairUsed.insert(pick.id)
                    paired = pick.id
                }
            }
            items.append(PlannedExercise(
                uid: "\(uid)-\(items.count)", exerciseId: e.id, slot: pattern, prescription: p,
                pairedWith: paired, supersetWith: superset ? items[hostIndex!].uid : nil, estSec: Int(est.rounded())))
            used += est
        }

        return Block(
            kind: .strength, title: circuit ? "Strength circuit" : "Strength", targetMin: minutes, items: items,
            note: circuit
                ? "Circuit: move straight between exercises, 30 s transition. Rest 60–90 s after each round."
                : "Leave 1–3 reps in reserve per RPE. Paired mobility drills and supersets happen during rest — no extra time.")
    }

    // MARK: Mobility

    static func mobility(_ ctx: Ctx, _ focus: Focus, _ minutes: Int, _ uid: String) -> Block? {
        guard minutes >= 3 else { return nil }
        ctx.begin(uid)
        var regions = Rules.regions(focus)
        if ctx.climber {
            var r: [Region] = [.hips, .shoulders]
            for x in regions + [.wrists] where !r.contains(x) { r.append(x) }
            regions = r
        }
        let count = clamp(minutes / 2, 2, 8)
        var items: [PlannedExercise] = []
        for i in 0..<count {
            guard let e = Selector.select(ctx, Query(category: .mobility, regions: [regions[i % regions.count]]))
                ?? Selector.select(ctx, Query(category: .mobility, regions: regions)) else { continue }
            items.append(PlannedExercise(
                uid: "\(uid)-\(items.count)", exerciseId: e.id, slot: .general,
                prescription: Prescription(sets: 2, reps: e.unit == .sec ? "45 s\(perSide(e))" : "6–8\(perSide(e))", restSec: 0,
                                           intensity: "Slow · end-range control"),
                estSec: 120))
        }
        guard !items.isEmpty else { return nil }
        return Block(
            kind: .mobility, title: ctx.climber ? "Climber mobility" : "Mobility", targetMin: minutes, items: items,
            note: ctx.climber
                ? "Active range for high-steps, drop-knees, heel hooks and overhead reaches."
                : "Active end-range work — own the range you trained.")
    }

    // MARK: Cardio

    static func cardioPrefer(_ m: CardioMode) -> [String] {
        switch m {
        case .zone2: ["rower", "bike", "incline-walk", "elliptical", "stair-climber", "treadmill-run", "ski-erg"]
        case .intervals: ["air-bike", "rower", "ski-erg", "bike"]
        case .threshold: ["rower", "treadmill-run", "ski-erg", "bike", "stair-climber"]
        case .sprints: ["air-bike", "ski-erg", "rower"]
        }
    }

    static func cardioPrescription(_ mode: CardioMode, _ minutes: Int) -> Prescription {
        switch mode {
        case .zone2:
            return Prescription(sets: 1, reps: "\(minutes) min", restSec: 0, intensity: "Zone 2 · RPE 3–4 · can talk in full sentences")
        case .intervals:
            return Prescription(sets: max(3, (minutes - 3) / 2), reps: "1 min hard / 1 min easy", restSec: 0, intensity: "Hard = RPE 8", note: "3 min easy before")
        case .threshold:
            let long = minutes >= 24
            let work = long ? 4 : 3, rest = long ? 3 : 2
            return Prescription(sets: max(2, (minutes - 3) / (work + rest)), reps: "\(work) min on / \(rest) min easy", restSec: 0,
                                intensity: "On = RPE 7–8 · controlled breathing", note: "3 min easy before")
        case .sprints:
            return Prescription(sets: clamp(minutes - 3, 5, 10), reps: "15 s all-out / 45 s easy", restSec: 0, intensity: "All-out", note: "3 min easy before")
        }
    }

    static func cardioBlock(_ ctx: Ctx, _ mode: CardioMode, _ minutes: Int, _ uid: String) -> Block? {
        guard minutes >= 6 else { return nil }
        ctx.begin(uid)
        let m: CardioMode = ctx.deload ? .zone2 : (minutes < 10 && mode == .threshold ? .intervals : mode)
        let prefer = ctx.climber && m == .zone2 ? ["incline-walk", "stair-climber"] + cardioPrefer(.zone2) : cardioPrefer(m)
        guard let e = Selector.select(ctx, Query(category: .cardio, prefer: prefer)) else { return nil }
        let title: String = switch m {
        case .zone2: "Cardio · Zone 2"
        case .intervals: "Cardio · Intervals"
        case .threshold: "Cardio · Threshold"
        case .sprints: "Cardio · Sprints"
        }
        return Block(kind: .cardio, title: title, targetMin: minutes, items: [
            PlannedExercise(uid: "\(uid)-0", exerciseId: e.id, slot: .general, prescription: cardioPrescription(m, minutes), estSec: minutes * 60),
        ])
    }

    // MARK: Cool-down (derived from session load)

    /// Load per muscle: sets × (primary 1, secondary 0.5); cardio by minutes; grip-heavy adds forearms.
    public static func muscleLoad(_ blocks: [Block]) -> [Muscle: Double] {
        var load: [Muscle: Double] = [:]
        for b in blocks where [.power, .strength, .cardio].contains(b.kind) {
            for it in b.items {
                let e = Exercise.get(it.exerciseId)
                let vol = b.kind == .cardio ? Double(it.estSec) / 300 : Double(it.prescription.sets)
                for m in e.primary { load[m, default: 0] += vol }
                for m in e.secondary { load[m, default: 0] += vol * 0.5 }
                if e.gripHeavy { load[.forearms, default: 0] += vol * 0.5 }
            }
        }
        return load
    }

    /// Every session ends with at least this many static stretches (plus breathing).
    public static let minStretches = 3

    static func cooldown(_ ctx: Ctx, _ minutes: Int, _ prior: [Block], _ uid: String) -> Block {
        let budget = Double(minutes * 60)
        var load = muscleLoad(prior)
        if ctx.climber { load[.forearms, default: 0] += 2 }
        var items: [PlannedExercise] = []
        var used = 0.0

        if let cardio = prior.first(where: { $0.kind == .cardio }), !cardio.title.contains("Zone 2"), let c = cardio.items.first {
            items.append(PlannedExercise(
                uid: "\(uid)-flush", exerciseId: c.exerciseId, slot: .general,
                prescription: Prescription(sets: 1, reps: "2 min", restSec: 0, intensity: "Very easy · bring HR down"), estSec: 120))
            used += 120
        }

        let breathingSec = 90.0
        let stretches = Selector.candidates(level: ctx.level, equipment: ctx.equipment, Query(category: .stretch)).filter { $0.id != "breathing" }
        var remaining = load
        var chosen: Set<String> = []
        var stretchCount = 0
        // Stretching is mandatory: at least `minStretches`, more while the budget allows.
        while stretchCount < minStretches || used + breathingSec < budget {
            var best: Exercise?
            var bestScore = 0.0
            for s in stretches where !chosen.contains(s.id) {
                let sc = s.primary.reduce(0) { $0 + (remaining[$1] ?? 0) }
                if sc > bestScore + 1e-9 { bestScore = sc; best = s }
            }
            guard let b = best else { break }
            let est = (b.unilateral ? 90.0 : 45.0) + 15
            if stretchCount >= minStretches && used + est + breathingSec > budget * 1.1 { break }
            stretchCount += 1
            chosen.insert(b.id)
            for m in b.primary { remaining[m] = (remaining[m] ?? 0) * 0.25 }
            items.append(PlannedExercise(
                uid: "\(uid)-\(items.count)", exerciseId: b.id, slot: .general,
                prescription: Prescription(sets: 1, reps: "45 s\(perSide(b))", restSec: 0, intensity: "Relaxed · long exhales"),
                estSec: Int(est)))
            used += est
        }
        items.append(PlannedExercise(
            uid: "\(uid)-breath", exerciseId: "breathing", slot: .general,
            prescription: Prescription(sets: 1, reps: "90 s", restSec: 0), estSec: Int(breathingSec)))

        let top = load.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.rawValue < $1.key.rawValue) }.prefix(4).map(\.key.label)
        return Block(kind: .cooldown, title: "Stretching & cool-down", targetMin: minutes, items: items,
                     note: "Static stretches for today's most-loaded muscles: \(top.joined(separator: ", ")).")
    }
}
