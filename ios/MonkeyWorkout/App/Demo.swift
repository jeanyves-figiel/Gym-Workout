#if DEBUG
import APIClient
import Foundation
import WorkoutEngine

/// DEBUG-only: `-demo [-demoScreen week|onboarding|onboarding-climbing|session|player|explore|muscle|exercise|technique|progress|history|body|readiness|cycle|picker|welcome]`
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

    /// Climbs logged in the app: a hard boulder session yesterday and a lead session last week.
    static func climbs() -> [ClimbLog] {
        let day: Double = 86_400
        return [
            ClimbLog(kind: .boulder, start: Date().addingTimeInterval(-day - 3_600 * 3), minutes: 105, effort: 8, topGrade: "6C+"),
            ClimbLog(kind: .lead, start: Date().addingTimeInterval(-6 * day), minutes: 120, effort: 6, topGrade: "6b"),
        ]
    }
}
#endif
