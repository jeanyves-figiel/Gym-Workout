#if DEBUG
import APIClient
import Foundation
import WorkoutEngine

/// DEBUG-only: `-demo [-demoScreen week|pr|pr-attempt|pr-result|onboarding|onboarding-climbing|session|player|player-rest|explore|muscle|exercise|technique|progress|progress-empty|history|body|account|account-password|account-email|readiness|cycle|picker|library|library-plan|builder|calendar|away|gyms|variety|welcome|community|community-join|community-share|community-profile]`
/// launches with sample data and no network — used by CI screenshots and previews.
enum Demo {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), args.indices.contains(i + 1) else { return "week" }
        return args[i + 1]
    }

    static let user: User? = {
        let json = #"{"id":"demo","email":"climber@example.com","name":"JY","emailVerified":true,"hasPassword":true,"appleLinked":false,"createdAt":"2026-10-07T10:00:00Z"}"#
        return try? JSONDecoder().decode(User.self, from: Data(json.utf8))
    }()

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
            secondary: [.adductors], machine: "Technogym Selection 700", cues: ["Slow return, 2 s"], drawing: pose)
    }()

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
            let week = w % 4 + 1
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

    /// Climbs logged in the app: a hard boulder session yesterday and a lead session last week.
    static func climbs() -> [ClimbLog] {
        let day: Double = 86_400
        return [
            ClimbLog(kind: .boulder, start: Date().addingTimeInterval(-day - 3_600 * 3), minutes: 105, effort: 8, topGrade: "6C+"),
            ClimbLog(kind: .lead, start: Date().addingTimeInterval(-6 * day), minutes: 120, effort: 6, topGrade: "6b"),
        ]
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
#endif
