import APIClient
import Foundation
import WorkoutEngine

/// Growing with the member (#495): block reviews level the plan up every 4 weeks (A), daily auto-tune fits
/// today's workout to recovery and sore muscles (B), the growth path keeps a long-term goal, weekly notices and
/// the coach's memory (C).
extension AppModel {
    var growth: GrowthState { state.synced?.growth ?? GrowthState() }

    /// Records a change to the synced growth state and saves.
    func saveGrowth(_ change: (inout GrowthState) -> Void) {
        guard state.synced != nil else { return }
        var g = growth
        change(&g)
        state.synced?.growth = g
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    var growthLevel: Int { growth.level ?? Growth.startLevel(profile?.experience ?? .beginner) }

    // MARK: Block review (A)

    /// The 4-week block that ended last Sunday, when this week starts a new cycle and it wasn't reviewed yet.
    var blockReview: BlockReview? {
        #if DEBUG
        if demo && Demo.screen == "train-smart" { return makeBlockReview() }
        #endif
        guard runningProgramme == nil, state.plan?.week == 1 else { return nil }
        let review = makeBlockReview()
        return review?.blockKey == growth.reviewedBlock ? nil : review
    }

    /// Review of the 4 calendar weeks before this one (demo screens show it whatever the week).
    func makeBlockReview(now: Date = Date()) -> BlockReview? {
        guard let p = profile else { return nil }
        let cal = planCalendar
        guard let start = cal.date(byAdding: .day, value: -7 * Growth.blockWeeks, to: Progression.weekStart(now, cal)) else { return nil }
        let end = Progression.weekStart(now, cal)
        let rirs = state.logs.filter { $0.date >= start && $0.date < end }.compactMap(\.rir)
        return Growth.review(records: state.history, blockStart: start, profile: p, level: growthLevel,
                             number: (growth.blocks ?? 0) + 1, rirs: rirs, calendar: cal)
    }

    /// Start the next block with the picked changes: level up (experience), plateau swaps kept on their plan days,
    /// the lagging muscle as a focus.
    func applyBlockReview(_ r: BlockReview, levelUp: Bool, plateaus: Set<String>, focus: Bool) {
        guard let sp = state.synced else { return }
        var g = growth
        g.level = levelUp ? r.level : growthLevel
        g.blocks = r.number
        g.reviewedBlock = r.blockKey
        state.synced?.growth = g
        var rules = sp.exerciseSwaps ?? []
        if let raw = state.plan, let shown = swappedPlan {
            for pl in r.plateaus where plateaus.contains(pl.exerciseId) {
                guard let to = pl.swapTo else { continue }
                for (rs, ss) in zip(raw.sessions, shown.sessions) where !rs.isPlanInsert {
                    for (ri, si) in zip(rs.blocks.flatMap(\.items), ss.blocks.flatMap(\.items)) where si.exerciseId == pl.exerciseId {
                        let rule = ExerciseSwap(weekday: rs.weekday, sessionIndex: rs.index, from: ri.exerciseId, to: to)
                        rules.removeAll { $0.sameSlot(rule) }
                        rules.append(rule)
                    }
                }
            }
        }
        state.synced?.exerciseSwaps = rules.isEmpty ? nil : rules
        // Re-plans this week with the new profile and saves.
        updateProfile(sp.profile.growing(r, levelUp: levelUp, focus: focus))
    }

    func closeBlockReview(_ r: BlockReview) {
        saveGrowth {
            $0.reviewedBlock = r.blockKey
            $0.blocks = r.number
        }
    }

    // MARK: Daily auto-tune (B)

    var tuneOn: Bool { growth.tuneOff != true }

    func setTuneOn(_ on: Bool) { saveGrowth { $0.tuneOff = on ? nil : true } }

    private var todayKey: String { PlanCalendar.key(Date(), planCalendar) }

    /// Today's choices; a new day starts fresh.
    var dayTune: DayTune {
        if let t = state.dayTune, t.day == todayKey { return t }
        return DayTune(day: todayKey)
    }

    private func editDayTune(_ change: (inout DayTune) -> Void) {
        var t = dayTune
        change(&t)
        state.dayTune = t
        persist()
    }

    /// What today's verdict is made from: Apple Health, the last workout's effort, days in a row, sore muscles.
    var tuneInputs: TuneInputs {
        let s = health?.snapshot
        let cal = planCalendar
        let today = cal.startOfDay(for: Date())
        let last = state.history.filter { $0.startedAt < today }.max { $0.startedAt < $1.startedAt }
        let rirs = last.map { r in state.logs.filter { cal.isDate($0.date, inSameDayAs: r.startedAt) }.compactMap(\.rir) } ?? []
        let days = Set(state.history.map { cal.startOfDay(for: $0.startedAt) })
        var inARow = 0
        while let d = cal.date(byAdding: .day, value: -(inARow + 1), to: today), days.contains(d) { inARow += 1 }
        return TuneInputs(hrv: s?.hrv, hrvBaseline: s?.hrvBaseline, restingHR: s?.restingHR, restingHRBaseline: s?.restingHRBaseline,
                          sleepHours: s?.sleepHours, lastRIR: rirs.isEmpty ? nil : Double(rirs.reduce(0, +)) / Double(rirs.count),
                          daysInARow: inARow, sore: Set(dayTune.sore))
    }

    var tuneVerdict: TuneVerdict { AutoTune.assess(tuneInputs) }

    /// The member's pick for today, else Monkey's.
    var tuneLevel: TuneLevel { dayTune.level ?? tuneVerdict.level }

    /// Today's sessions: on today's weekday, or the next one not done when the plan has no weekdays (as #156).
    func todaySessionIds(_ p: WeekPlan) -> Set<String> {
        let dated = p.sessions.filter { $0.weekday == todayWeekday }
        if !dated.isEmpty { return Set(dated.map(\.id)) }
        if p.sessions.contains(where: { $0.weekday != nil }) { return [] }
        return p.sessions.first { state.done[$0.id] != true }.map { [$0.id] } ?? []
    }

    func tuned(_ p: WeekPlan) -> (plan: WeekPlan, changes: [TuneChange]) {
        guard tuneOn, let profile else { return (p, []) }
        let ids = todaySessionIds(p)
        guard !ids.isEmpty else { return (p, []) }
        let t = dayTune
        return p.autoTuned(ids, level: tuneLevel, sore: Set(t.sore), profile: profile, undone: Set(t.undone))
    }

    /// What auto-tune changed in today's workout.
    var tuneChanges: [TuneChange] {
        guard let p = uneditedPlan?.applying(edits: state.synced?.sessionEdits ?? []) else { return [] }
        return tuned(p).changes
    }

    /// nil = Monkey picks.
    func setTuneLevel(_ level: TuneLevel?) {
        editDayTune {
            $0.level = level
            $0.undone = []
        }
    }

    func toggleSore(_ g: MuscleGroup) {
        editDayTune {
            if let i = $0.sore.firstIndex(of: g) { $0.sore.remove(at: i) } else { $0.sore.append(g) }
            $0.undone = []
        }
    }

    func undoTune(_ c: TuneChange) { editDayTune { $0.undone.append(c.id) } }

    func redoTunes() { editDayTune { $0.undone = [] } }

    // MARK: Growth path (C)

    /// The member's goal, else a suggested one from their main lifts.
    var growthGoal: GrowthGoal? { growth.goal ?? GrowthGoal.suggest(records: state.history, calendar: planCalendar) }

    var goalStatus: GoalStatus? { growthGoal.map { $0.status(records: state.history, calendar: planCalendar) } }

    func setGoal(exerciseId: String, targetKg: Double) {
        let current = Progression.oneRepMaxTrend(exerciseId, records: state.history, calendar: planCalendar).last?.1
        saveGrowth {
            $0.goal = GrowthGoal(exerciseId: exerciseId, targetKg: targetKg, startKg: GrowthGoal.round(min(current ?? targetKg * 0.8, targetKg)),
                                 startDate: Date())
        }
    }

    /// Goal reached: the next one starts from it.
    func nextGoal() {
        guard let g = growthGoal else { return }
        saveGrowth { $0.goal = g.next() }
    }

    /// Rest seconds per exercise in this week's plan.
    private var plannedRest: [String: Int] {
        var out: [String: Int] = [:]
        for s in plan?.sessions ?? [] { for b in s.blocks { for it in b.items { out[it.exerciseId] = it.prescription.restSec } } }
        return out
    }

    /// What Monkey noticed in the last 7 days.
    var noticed: [Insight] {
        guard let p = profile else { return [] }
        return Noticed.week(records: state.history, sets: setLogs, profile: p, goal: growthGoal, plannedRest: plannedRest, calendar: planCalendar)
    }

    private var weekKey: String { PlanCalendar.key(Progression.weekStart(Date(), planCalendar), planCalendar) }

    /// The slim "Monkey noticed" bar on Train, until closed for the week.
    var noticedBar: [Insight] { growth.noticedClosed == weekKey ? [] : noticed }

    func closeNoticed() { saveGrowth { $0.noticedClosed = weekKey } }

    /// Tap on a notice's action.
    func act(on i: Insight) {
        guard var p = profile else { return }
        switch i.kind {
        case .goalHit:
            nextGoal()
        case .skippedDay:
            guard let from = i.weekday, let to = i.toWeekday, var days = p.gymWeekdays, let k = days.firstIndex(of: from) else { return }
            days[k] = to
            p.gymWeekdays = days.sorted()
            updateProfile(p)
        case .untrained:
            guard let g = i.group else { return }
            var f = p.focusMuscles ?? []
            if !f.contains(g) { f.append(g) }
            p.focusMuscles = f
            updateProfile(p)
        case .longRests, .bests:
            return
        }
    }

    /// What the coach remembers about the member, for Ask Coach.
    var coachFacts: [String] {
        guard let p = profile else { return [] }
        let now = Date()
        return CoachMemory.facts(profile: p, goal: growthGoal, goalStatus: goalStatus, level: growthLevel,
                                 liked: learningOn ? memberTaste.liked(at: now) : [], avoided: learningOn ? memberTaste.disliked(at: now) : [],
                                 notes: growth.notes ?? [])
    }

    func addCoachNote(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        saveGrowth { $0.notes = ($0.notes ?? []) + [t] }
    }

    func removeCoachNote(_ text: String) {
        saveGrowth {
            $0.notes?.removeAll { $0 == text }
            if $0.notes?.isEmpty == true { $0.notes = nil }
        }
    }
}

#if DEBUG
extension AppModel {
    /// Demo screens `block-review`, `auto-tune`, `growth-path`, `train-smart`: a goal, a sore day with short sleep,
    /// a note for the coach.
    func applyDemoGrowth() {
        saveGrowthDemo()
        state.dayTune = DayTune(day: PlanCalendar.key(Date(), planCalendar), level: nil, sore: [.legs], undone: [])
    }

    private func saveGrowthDemo() {
        var g = GrowthState()
        g.level = 4
        g.blocks = 2
        g.notes = ["Left knee: no deep lunges"]
        if let suggested = GrowthGoal.suggest(records: state.history, calendar: planCalendar) {
            g.goal = GrowthGoal(exerciseId: suggested.exerciseId, targetKg: suggested.targetKg, startKg: suggested.startKg - 10,
                                startDate: Date().addingTimeInterval(-60 * 86_400))
        }
        state.synced?.growth = g
    }
}
#endif
