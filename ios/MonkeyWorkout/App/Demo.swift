#if DEBUG
import APIClient
import Foundation
import WorkoutEngine

/// DEBUG-only: `-demo [-demoScreen week|pr|pr-attempt|pr-result|onboarding|onboarding-climbing|session|player|player-rest|explore|muscle|exercise|technique|progress|progress-empty|history|body|account|account-password|account-email|account-security|account-reauth|account-2step|account-recovery|account-passkeys|signin-2step|readiness|cycle|picker|library|library-plan|builder|calendar|day|move|add-workout|add-workout-quick|away|gyms|variety|variation|welcome|signin|signup|verify|community|community-join|community-plans|community-fuel|community-mine|community-plan|community-share-plan|community-tip|community-share|community-profile|profile|profile-gym|profile-gym-add|profile-goal|profile-goal-focus|day-focus|profile-method|profile-flow|flow-session|flow-builder|flow-picks|paywall|pro|pro-offer|pro-gate|equipment|equipment-zones|equipment-by-zone|floor-plan|session-zones|swap-zones|player-zones|gym-setup|gym-swipe|gym-result|not-here|measurements|measurement-log|measurement-detail|measurement-howto|measurement-guide|whats-new|whats-new-history|watch-lift|lift-practice|watch-home|game-{week|session|done|progress}-{coach|deck|rings}|game-quest-deck|game-ladder|game-levelup|game-levelup-legend|game-level-row|explore-programmes|programme|programme-running|train-programme|programme-test|progress-programmes|profile-programme|calendar-programme|programme-finished|programme-length|programme-grid|programme-grid-running|programme-mine|programme-builder|programme-builder-week|snow-ready|hyrox-ready|train-missed|missed-catchup|missed-log|calendar-missed|train-day-picked|train-rest-day|train-past-day|train-skipped|undo-bar|edit-exercises|session-edited|flow-warmup|flow-cooldown|quick-flow|taste|train-taste|coach-chat|coach-chat-empty|position|position-mistake|position-press|your-week-sports|add-sport|plan-sport|calendar-trip|day-trip|fresh-start|train-smart|block-tweak|auto-tune|growth-path|coach-memory|lift-lab|lift-focus|lift-focus-setup|set-style|train-comeback|train-run|train-hybrid|run-session|run-start|run-goal|zone-week|onboarding-gym|onboarding-machines|onboarding-map|onboarding-plan|onboarding-tour|app-tour|train-setup|onboarding-hub|fuel-setup-card]`
/// launches with sample data and no network — used by CI screenshots and previews.
enum Demo {
    /// Studio coach voices (#395) for the `coach-settings` screen.
    static let coachVoices = CoachVoiceCatalog(available: true, voices: [
        .init(id: "Joanna", name: "Joanna", gender: "female", accent: "us", label: "American"),
        .init(id: "Ruth", name: "Ruth", gender: "female", accent: "us", label: "American, bright"),
        .init(id: "Matthew", name: "Matthew", gender: "male", accent: "us", label: "American"),
        .init(id: "Amy", name: "Amy", gender: "female", accent: "gb", label: "British"),
        .init(id: "Arthur", name: "Arthur", gender: "male", accent: "gb", label: "British"),
    ], lines: [])

    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), args.indices.contains(i + 1) else { return "week" }
        return args[i + 1]
    }

    /// App style for game-look screens (#227): `-appStyle coach|deck|rings`, or the suffix of a `game-…` screen.
    static var appStyle: WatchHomeStyle? {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-appStyle"), args.indices.contains(i + 1) { return WatchHomeStyle(rawValue: args[i + 1]) }
        guard screen.hasPrefix("game-") else { return nil }
        return screen.split(separator: "-").last.flatMap { WatchHomeStyle(rawValue: String($0)) }
    }

    /// What a finished workout earned, for the `game-done-…` screens.
    static var reward: GameReward {
        let badges = Achievements.evaluate(records: [], weights: [], targetPerWeek: 3)
        let streak = badges.first { $0.id == "s4" }
        return GameReward(xp: 340, levelUp: 8, weekCleared: true, badges: streak.map { [$0] } ?? [])
    }

    /// Wins you missed (#501) for the `game-done-…` screens.
    static let wins: [Win] = [
        Win(.comeback, title: "Back after 12 days", detail: "Comeback quest 1/3 · +100 XP", value: "1/3", unit: "quest"),
        Win(.heavier, title: "Goblet squat", detail: "Heavier than last time · 20 → 22 kg", value: "+2", unit: "kg"),
        Win(.feel, title: "Training lifts you", detail: "Felt good after 4 of your last 5 sessions", value: "4/5", unit: "felt good"),
    ]

    static let user: User? = {
        let json = #"{"id":"demo","email":"climber@example.com","name":"JY","emailVerified":true,"hasPassword":true,"appleLinked":false,"createdAt":"2026-10-07T10:00:00Z"}"#
        return try? JSONDecoder().decode(User.self, from: Data(json.utf8))
    }()

    /// Security page (#257): 2-step on, 2 passkeys.
    static let security = SecurityOverview(
        hasPassword: true, appleLinked: true, mfaEnabled: true, recoveryCodesLeft: 8,
        passkeys: [Passkey(id: "p1", name: "iPhone", createdAt: "2026-10-13T20:00:00Z", lastUsedAt: "2026-10-13T21:00:00Z"),
                   Passkey(id: "p2", name: "iPad", createdAt: "2026-10-13T20:05:00Z")],
        reauthMethods: [.passkey, .apple, .password, .totp, .emailCode])
    static let recoveryCodes = ["3f9a2-7c1d4", "b81e0-55a9c", "0d4c7-e2f18", "9a6b3-1c0e7", "c4e21-8f9a0",
                                "71d0b-a3e64", "e5f92-0b7c1", "28a6d-f41e3", "f0c38-9d2b5", "6b1e4-c7a09"]

    /// Workout library (#62): one of mine shared with members, two from other members.
    static let customWorkouts: [CustomWorkout] = [
        CustomWorkout(
            name: "Push day",
            items: [
                .init(exerciseId: "bench-press", sets: 4, reps: 8, restSec: 120),
                .init(exerciseId: "ohp", sets: 3, reps: 8, restSec: 120),
                .init(exerciseId: "dips", kcal: 40),
                .init(exerciseId: "db-lateral-raise", sets: 3, reps: 12, restSec: 60),
            ],
            createdAt: Date(timeIntervalSince1970: 1_790_000_000), visibility: .members),
    ]

    static let sharedWorkouts: [SharedWorkout] = [
        SharedWorkout(
            name: "Engine builder",
            items: [.init(exerciseId: "rower", sets: 1, reps: 12, restSec: 60), .init(exerciseId: "kb-swing", sets: 4, reps: 15, restSec: 45),
                    .init(exerciseId: "bike", sets: 1, reps: 10, restSec: 0)],
            saves: 12, author: .init(userId: "u-lea", nickname: "lea_climbs")),
        SharedWorkout(
            name: "Pull strength",
            items: [.init(exerciseId: "pull-up", sets: 4, reps: 6, restSec: 150), .init(exerciseId: "barbell-row", sets: 4, reps: 8, restSec: 120),
                    .init(exerciseId: "face-pull", sets: 3, reps: 12, restSec: 60), .init(exerciseId: "hammer-curl", sets: 3, reps: 10, restSec: 60)],
            saves: 8, author: .init(userId: "u-marco", nickname: "marco")),
    ]

    /// A user-built machine exercise with a pose drawing (#52).
    static let customExercise: CustomExercise = {
        var pose = ExerciseDrawing(template: .seated)
        pose.frames[1] = FigurePose(legN: (-25, 70), legF: (0, 90), armN: (60, 0), armF: (65, 0))
        pose.props = [DrawingProp(.seat), DrawingProp(.machine, dx: -20), DrawingProp(.pad, anchor: .kneeN)]
        return CustomExercise(
            id: UUID(uuidString: "6F0C2B1E-5A47-4E4B-9C3A-2B7D7F1A9E10")!, name: "Hip abductor machine",
            createdAt: Date(timeIntervalSince1970: 1_791_000_000), category: .strength, primary: [.glutes],
            secondary: [.adductors], equipment: [.hipAdAbductor], machine: "Technogym Selection 700", cues: ["Slow return, 2 s"], drawing: pose)
    }()

    /// Training programme screens (#255): Strength foundation running (week 4, or week 8 = test week), and
    /// Climber's power finished earlier; a member-made programme on Explore (#269).
    @MainActor static func programme(_ model: AppModel) {
        let running = ["train-programme", "programme-test", "programme-running", "programme-grid-running", "progress-programmes", "profile-programme",
                       "calendar-programme"]
        if screen == "explore-programmes" {
            // Member-made programme (#269) in My programmes.
            guard var mine = Programme.find("strength-foundation")?.copy(name: "My summer strength") else { return }
            mine.phases = Programme.phases(weeks: 10, test: true)
            model.state.synced?.customProgrammes = [mine]
        }
        guard running.contains(screen) || screen == "programme-finished" else { return }
        let cal = Progression.calendar()
        let now = Date()
        let past = cal.date(byAdding: .weekOfYear, value: -14, to: now)!
        model.state.synced?.programmeHistory = [
            ProgrammeRecord(programmeId: "climbers-power", start: past, end: cal.date(byAdding: .weekOfYear, value: 6, to: past)!,
                            finished: true, weeks: 6),
        ]
        guard running.contains(screen), let prog = Programme.find("strength-foundation") else { return }
        let start = cal.date(byAdding: .weekOfYear, value: screen == "programme-test" ? -7 : -3, to: now)!
        model.state.synced?.programme = ActiveProgramme(
            programmeId: prog.id, start: Progression.weekStart(start, cal), seed: 11,
            saved: .init(profile: profile, seed: 7, week: week))
        model.syncProgramme(now: now, starting: true)
    }

    /// Plan sport screens (#474): snowboard Saturdays in season, a paused bike, and a snowboard week next week.
    @MainActor static func sportTrips(_ model: AppModel) {
        guard ["your-week-sports", "add-sport", "plan-sport", "calendar-trip", "day-trip"].contains(screen),
              var p = model.state.synced?.profile else { return }
        let cal = Progression.calendar()
        let monday = Progression.weekStart(Date(), cal)
        func key(_ days: Int) -> String { PlanCalendar.key(cal.date(byAdding: .day, value: days, to: monday)!, cal) }
        p.climbingWeekdays = [2, 5]
        p.syncClimbingDays()
        p.sports = [SportPlan(sport: .snowboard, weekdays: [6], seasonMonths: [12, 1, 2, 3]),
                    SportPlan(sport: .roadBike, weekdays: [3, 7], seasonMonths: [4, 5, 6, 7, 8, 9], paused: true)]
        p.sportTrips = [SportTrip(sport: .snowboard, start: key(12), end: key(18), name: "Laax week")]
        model.state.synced?.away = nil
        model.state.synced?.profile = p
        model.replanCurrentWeek()
    }

    /// Run & cardio screens (#618): a 10K on the Sunday 7 weeks out (Build), or Hybrid mode.
    @MainActor static func runs(_ model: AppModel) {
        guard ["train-run", "train-hybrid", "run-session", "run-start", "run-goal"].contains(screen),
              var p = model.state.synced?.profile else { return }
        let cal = Progression.calendar()
        let race = cal.date(byAdding: .day, value: 7 * 7 + 6, to: Progression.weekStart(Date(), cal)) ?? Date()
        p.runGoal = screen == "train-hybrid" ? RunGoal(mode: .hybrid)
            : RunGoal(distance: .k10, raceDate: RunPlanner.dayKey(race, cal), targetSeconds: 49 * 60 + 30, raceName: "Zürich")
        model.state.synced?.profile = p
        model.replanCurrentWeek()
    }

    /// Onboarding screens (#664): gym and plan done, the rest on the set-up card; the tour on its Explore stop.
    @MainActor static func onboarding(_ model: AppModel) {
        if ["train-setup", "onboarding-hub"].contains(screen) {
            model.state.synced?.onboarding = OnboardingProgress(done: [.gym, .plan])
        }
        if screen == "app-tour" {
            model.tab = .explore
            model.tourStep = 1
        }
    }

    /// Missed session screens (#266): the first session of the week not done and today on the second one's day.
    @MainActor static func missed(_ model: AppModel) {
        if ["train-missed", "missed-catchup", "missed-log", "calendar-missed", "train-day-picked", "train-rest-day", "train-past-day", "train-skipped", "train-sport-day"].contains(screen) {
            // No away periods: they re-plan undone sessions from the real today, so nothing would be missed.
            model.state.synced?.away = nil
            model.state.done = [:]
            // Sessions on weekdays (gym Mon/Wed/Fri/Sun, climbing Tue/Sat), so the week strip shows.
            var p = Demo.profile
            p.gymWeekdays = [1, 3, 5, 7]
            p.climbingWeekdays = [2, 6]
            if screen == "train-sport-day" {
                // Sport block (#658): every non-gym day a snowboard day, no climbing.
                p.climbingWeekdays = []
                p.climbingDaysPerWeek = 0
                p.sports = [SportPlan(sport: .snowboard, weekdays: [2, 4, 6])]
            }
            model.state.synced?.profile = p
            model.state.plan = Generator.generateWeek(p, week: Demo.week, seed: 7)
            model.replanCurrentWeek()
        }
        if screen == "train-past-day" {
            // Past day card (#592): a bouldering session logged on Tuesday, the climbing day before "today".
            let cal = model.planCalendar
            let tue = cal.date(byAdding: .day, value: 1, to: Progression.weekStart(Date(), cal)) ?? Date()
            let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: tue) ?? tue
            model.state.climbs = [ClimbLog(kind: .boulder, start: start, minutes: 90, effort: 7, topGrade: "6C+")]
        }
        // "Today" = the first session not done (nothing missed), or the second one's day on the screens above.
        let ordered = model.plan.map(WeekProgress.ordered) ?? []
        let next = model.state.done.isEmpty ? ordered.dropFirst().first : ordered.first { !model.doneIds.contains($0.id) }
        model.demoToday = next?.weekday ?? 3
        if screen == "train-skipped", let s = model.plan?.sessions.first(where: { $0.weekday == model.todayWeekday }) {
            // Today's session skipped from the long press (#643): dash in the strip, Unskip on the card.
            model.skipSession(s.id)
        }
    }

    /// Current cycle week (2 = Build). Every demo screen (Train chip, cycle sheet, calendar, library) reads it via the plan.
    static let week = 2

    static let profile = Profile(goal: .balanced, sessionsPerWeek: 4, experience: .intermediate, climbingDaysPerWeek: 2)

    /// Onboarding screenshot with the climbing goal picked.
    static let climbingProfile = Profile(
        goal: .climbing, sessionsPerWeek: 2, experience: .intermediate, climbingDaysPerWeek: 2,
        climbingWeekdays: [2, 4], gymWeekdays: [1, 5])

    static let health: HealthSnapshot = {
        var s = HealthSnapshot()
        s.weightKg = 72.4
        s.heightCm = 178
        s.birthYear = 1988
        s.sex = .male
        s.restingHR = 54
        s.restingHRBaseline = 52
        s.hrv = 58
        s.hrvBaseline = 62
        s.vo2Max = 47
        s.sleepHours = 7.2
        s.climbingPerWeek4w = 2
        let day: Double = 86_400
        s.recentClimbs = [
            ClimbEntry(id: UUID(), start: Date().addingTimeInterval(-4 * day), end: Date().addingTimeInterval(-4 * day + 7_200), source: "MonkeyGrade"),
            ClimbEntry(id: UUID(), start: Date().addingTimeInterval(-9 * day), end: Date().addingTimeInterval(-9 * day + 5_400), source: "MonkeyGrade"),
        ]
        let now = Date()
        s.weightTrend = (0..<12).map { i in .init(date: now.addingTimeInterval(Double(i - 12) * 7 * 86_400), value: 74 - Double(i) * 0.15) }
        s.vo2Trend = (0..<6).map { i in .init(date: now.addingTimeInterval(Double(i - 6) * 30 * 86_400), value: 44 + Double(i) * 0.6) }
        return s
    }()

    /// Six weeks of plausible history with progressing weights.
    static func history() -> (records: [WorkoutRecord], logs: [LogEntry]) {
        let cal = Progression.calendar()
        let thisWeek = Progression.weekStart(Date(), cal)
        var records: [WorkoutRecord] = []
        var logs: [LogEntry] = []
        for w in 0..<6 {
            // Cycle weeks counted back from the current one, so last week is the phase before this one.
            let week = PlanCalendar.cycleWeek(current: Self.week, offset: w - 6)
            let plan = Generator.generateWeek(profile, week: week, seed: 7)
            let start = cal.date(byAdding: .weekOfYear, value: w - 6, to: thisWeek)!
            for (i, session) in plan.sessions.enumerated() where !(w == 2 && i == 3) {
                let day = cal.date(byAdding: .day, value: [0, 2, 3, 5][i], to: start)!
                let begin = cal.date(bySettingHour: i == 1 ? 6 : 18, minute: 30, second: 0, of: day)!
                var sets: [String: Int] = [:]
                var weights: [String: Double] = [:]
                for b in session.blocks {
                    for it in b.items {
                        sets[it.uid] = it.prescription.sets
                        if b.kind == .strength, it.slot != .shoulderHealth, it.slot != .forearmAntagonist, !Exercise.get(it.exerciseId).equipment.isEmpty {
                            let step = Double(it.exerciseId.count % 5)
                            let kg = 40 + step * 10 + Double(w) * 2.5
                            weights[it.exerciseId] = kg
                            logs.append(LogEntry(date: begin, exerciseId: it.exerciseId, sessionId: session.id, weightKg: kg))
                        }
                    }
                }
                var r = WorkoutRecord.build(
                    session: session, week: week, deload: plan.deload, setsDone: sets, weights: weights,
                    startedAt: begin, endedAt: begin.addingTimeInterval(Double(session.estMin + 3) * 60), bodyMassKg: 72.4)
                r.avgHeartRate = 118 + Double((w + i) % 5) * 4
                r.maxHeartRate = 162 + Double((w * i) % 7) * 2
                records.append(r)
            }
        }
        return (records, logs)
    }

    /// Away periods (#68): two busy days later this week and a hotel-gym trip next week.
    static func away() -> [AwayPeriod] {
        let cal = Progression.calendar()
        let monday = Progression.weekStart(Date(), cal)
        func key(_ days: Int) -> String { PlanCalendar.key(cal.date(byAdding: .day, value: days, to: monday)!, cal) }
        return [
            AwayPeriod(kind: .off, start: key(3), end: key(4), note: "Conference"),
            AwayPeriod(kind: .travel, start: key(7), end: key(10), note: "Berlin", setup: .hotelGym),
        ]
    }

    /// Gyms set up before (#162): a hotel used on a trip and a day-pass gym.
    /// Machine setups (#355): the first equipment exercise of the demo player's session and the leg press, at the
    /// home gym; the leg press also at the hotel gym (to copy).
    static func machineNotes(plan: WeekPlan?, home: GymRef) -> [MachineNote] {
        let first = plan?.sessions.dropFirst().first?.blocks.filter { $0.kind == .strength }.flatMap(\.items)
            .first { !Exercise.get($0.exerciseId).equipment.isEmpty }?.exerciseId
        var notes: [MachineNote] = []
        for id in Set([first, "leg-press"].compactMap { $0 }) {
            notes.append(MachineNote(gymId: home.id, gymName: home.name, exerciseId: id,
                                     equipment: Exercise.get(id).equipment.first?.rawValue,
                                     fields: [.init(label: "Seat", value: "4"), .init(label: "Pad", value: "2"), .init(label: "ROM", value: "off")],
                                     text: "Pad just above the heels."))
        }
        notes.append(MachineNote(gymId: "custom:demo-adlon", gymName: "Hotel Adlon gym", exerciseId: "leg-press", equipment: "leg-press",
                                 fields: [.init(label: "Seat", value: "6"), .init(label: "Foot plate", value: "high")]))
        return notes
    }

    static let savedGyms: [SavedGym] = [
        SavedGym(ref: GymRef(id: "custom:demo-adlon", name: "Hotel Adlon gym", address: ""), kind: .hotel,
                 equipment: GymKind.hotel.equipment, updated: Date().addingTimeInterval(-20 * 86_400)),
        SavedGym(ref: GymRef(id: "map:52.52000,13.40500", name: "McFit Berlin-Mitte", address: "Alexanderplatz, Berlin"), kind: .budget,
                 equipment: GymKind.budget.equipment, updated: Date().addingTimeInterval(-40 * 86_400)),
    ]

    /// What other members found at Holmes Place (#162).
    /// Gym zones (#274): the usual layout with a floor plan, kettlebells moved to the stretch corner.
    static let layout: GymLayout = {
        var l = GymLayout.starter
        l.zones[0].name = "Rack corner"
        l.move(.kettlebells, to: "stretch")
        l.zones[4].name = "Stretch & KB"
        l.unassign(.landmine) // "No zone" (#289)
        let rects = [GymLayout.Rect(x: 0, y: 0, w: 0.5, h: 0.4), GymLayout.Rect(x: 0.55, y: 0, w: 0.45, h: 0.65),
                     GymLayout.Rect(x: 0, y: 0.45, w: 0.5, h: 0.2), GymLayout.Rect(x: 0, y: 0.75, w: 1, h: 0.25),
                     GymLayout.Rect(x: 0.55, y: 0.65, w: 0.45, h: 0.1)]
        for i in l.zones.indices { l.zones[i].rect = rects[i] }
        l.door = GymLayout.Point(x: 1, y: 0.7) // Gym Map (#406)
        return l
    }()

    /// Gym Map (#406): the plan 14 members at the home gym agree on, and a busy rack corner right now.
    static let sharedGymMap = SharedGymMap(layout: layout, members: 14, agreement: 94)
    static let gymCrowd = GymCrowd(
        now: [.init(zone: "rack corner", reports: 3)],
        forecast: [.init(zone: "rack corner", hours: (0..<24).map { [17, 18, 19].contains($0) ? 6 : $0 > 7 && $0 < 22 ? 1 : 0 })]
    )

    static let knownGym = KnownGym(
        place: GymTally(members: 7, votes: [:], equipment: GymKind.bigClub.equipment.filter { $0 != .sled && $0 != .skiErg }.map(\.rawValue)),
        chain: GymTally(members: 3, votes: [:], equipment: GymKind.budget.equipment.map(\.rawValue), name: "holmes place", gyms: 2)
    )

    static let holmes = GymRef(id: "map:47.37800,8.53000", name: "Holmes Place Europaallee", address: "Europaallee 15, 8004 Zürich",
                               latitude: 47.378, longitude: 8.53)

    /// Climbs logged in the app: a hard boulder session yesterday and a lead session last week.
    static func climbs() -> [ClimbLog] {
        let day: Double = 86_400
        return [
            ClimbLog(kind: .boulder, start: Date().addingTimeInterval(-day - 3_600 * 3), minutes: 105, effort: 8, topGrade: "6C+"),
            ClimbLog(kind: .lead, start: Date().addingTimeInterval(-6 * day), minutes: 120, effort: 6, topGrade: "6b"),
        ]
    }

    /// Other sports for the History page and sport widgets (#442, #444).
    static func sportLogs() -> [SportLog] {
        let day: Double = 86_400
        return [
            SportLog(sport: .snowboard, start: Date().addingTimeInterval(-2 * day - 3_600 * 5), minutes: 240, effort: 7, distanceKm: 38),
            SportLog(sport: .hyrox, start: Date().addingTimeInterval(-8 * day), minutes: 84, effort: 9),
            SportLog(sport: .run, start: Date().addingTimeInterval(-4 * day), minutes: 42, effort: 5, distanceKm: 8.2),
            SportLog(sport: .snowboard, start: Date().addingTimeInterval(-16 * day), minutes: 300, effort: 6, distanceKm: 45),
            SportLog(sport: .run, start: Date().addingTimeInterval(-11 * day), minutes: 35, effort: 4, distanceKm: 6.5),
        ]
    }

    /// Body measurements (#185): four check-ins over 12 weeks, arms and thighs growing, waist down.
    static func measurements() -> [BodyMeasurement] {
        (0..<4).map { i in
            let k = Double(i)
            var m = BodyMeasurement(
                id: UUID(uuidString: "5A1D7C4E-0B3F-4C2A-9E61-00000000000\(i)")!,
                date: Date().addingTimeInterval((k - 3) * 28 * 86_400 - 2 * 86_400), weightKg: 74 - k * 0.5, bodyFatPct: 19 - k * 0.8)
            m.setGirth(.neck, 38)
            m.setGirth(.shoulders, 116 + k * 0.8)
            m.setGirth(.chest, 100 + k * 0.7)
            m.setGirth(.waist, 84 - k * 1.1)
            m.setGirth(.hips, 98 - k * 0.3)
            m.setGirth(.upperArm, side: .left, 34 + k * 0.4)
            m.setGirth(.upperArm, side: .right, 34.5 + k * 0.4)
            m.setGirth(.forearm, 29 + k * 0.2)
            m.setGirth(.thigh, 56 + k * 0.5)
            m.setGirth(.calf, 37.5 + k * 0.1)
            return m
        }
    }

    /// Bench press PR attempts: a missed single, a 5RM, a 90 kg single and today's 92.5 kg record.
    static func prAttempts() -> [PRAttempt] {
        let day: Double = 86_400
        func single(_ kg: Double, made: Bool, prev: Double?, ago: Double) -> PRAttempt {
            PRPlanner.finish(exerciseId: "bench-press", kind: .oneRepMax, targetReps: 1, sets: [PRSet(kg: kg, reps: 1, made: made)],
                             previousBest: prev, date: Date().addingTimeInterval(-ago * day))
        }
        return [
            single(87.5, made: false, prev: nil, ago: 69),
            PRPlanner.finish(exerciseId: "bench-press", kind: .repMax, targetReps: 5, sets: [PRSet(kg: 80, reps: 5)],
                             previousBest: 77.5, date: Date().addingTimeInterval(-51 * day)),
            single(90, made: true, prev: 85, ago: 28),
            prResult,
        ]
    }

    static let prResult: PRAttempt = PRPlanner.finish(
        exerciseId: "bench-press", kind: .oneRepMax, targetReps: 1,
        sets: [PRSet(kg: 40, reps: 8, warmup: true), PRSet(kg: 92.5, reps: 1), PRSet(kg: 95, reps: 1, made: false)],
        previousBest: 90, date: Date().addingTimeInterval(-600))
}

extension Demo {
    /// A session's list edited before starting (#295): second strength move out, first one +1 set, a cable fly added.
    static func editedBlocks(_ s: Session) -> [Block] {
        var blocks = s.blocks
        let strength = s.blocks.first { $0.kind == .strength }?.items ?? []
        if strength.count > 2 { blocks.remove(strength[1].uid) }
        if let first = strength.first { blocks.setSets(first.uid, first.prescription.sets + 1) }
        if let fly = Exercise.find("cable-fly") ?? Exercise.find("pec-deck") {
            blocks.add(fly, to: .strength, sessionId: s.id, id: UUID(uuidString: "00000000-0000-0000-0000-000000000295")!)
        }
        return blocks
    }
}
#endif
