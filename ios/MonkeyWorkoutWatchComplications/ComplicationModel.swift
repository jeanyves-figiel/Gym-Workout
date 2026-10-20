import Foundation
import SwiftUI

/// What every complication shows, flattened from the last phone snapshot for a given moment (#190).
struct ComplicationInfo {
    enum Day { case today, next, rest, weekDone }
    /// One weekday on the week strip.
    enum DayState { case done, today, planned, missed, rest, restToday }

    var day: Day
    var title: String
    /// "Wed" for the next session's weekday, "Day 2" without weekdays.
    var dayLabel: String
    var minutes: Int
    var exercises: Int
    var tint: UInt32
    var tint2: UInt32
    var week: Int
    var deload: Bool
    var done: Int
    var target: Int
    var streak: Int
    var bestStreak: Int
    var readiness: String?
    /// Monday … Sunday; nil when the plan has no weekdays ("Day 1", "Day 2").
    var days: [DayState]?
    var records: [WRecord] = []
    var last: WRecent?
    var water: WWater?

    var progress: Double { target == 0 ? 0 : min(1, Double(done) / Double(target)) }

    static let sample = ComplicationInfo(
        day: .today, title: "Upper Push", dayLabel: "Mon", minutes: 50, exercises: 6, tint: 0x2F6BFF, tint2: 0x8A4DFF,
        week: 2, deload: false, done: 2, target: 3, streak: 4, bestStreak: 6, readiness: "Ready to push",
        days: [.done, .rest, .today, .rest, .planned, .rest, .rest],
        records: [WRecord(name: "Bench Press", kg: 100)],
        last: WRecent(title: "Lower Strength", date: Date().addingTimeInterval(-86_400), minutes: 52, sets: 18))

    /// nil = nothing synced from the iPhone yet.
    init?(_ snap: WatchSnapshot?, at date: Date) {
        guard let snap, !snap.sessions.isEmpty || !snap.extras.isEmpty else { return nil }
        let cal = Calendar(identifier: .iso8601)
        // A new week started since the last sync: the phone resets the week, so does the watch face.
        let rolled = !cal.isDate(snap.generatedAt, equalTo: date, toGranularity: .weekOfYear)
        var sessions = snap.sessions
        if rolled { for i in sessions.indices { sessions[i].done = false } }
        // A phone that sends `missed` (#266) decides next up: nil = nothing left this week, never a missed session.
        let phoneDecides = sessions.contains { $0.missed != nil }
        let next = rolled ? sessions.first : (snap.nextSessionId.flatMap { id in sessions.first { $0.id == id } }
            ?? (phoneDecides ? nil : sessions.first { !$0.done }))
        let today = WeekdayName.index(date, cal)

        if let next {
            let planned = WeekdayName.all.firstIndex(of: next.dayLabel)
            // Later this week = rest today; earlier (missed) or no weekdays = still next up.
            if let planned { day = planned == today ? .today : planned > today ? .rest : .next } else { day = .next }
            title = next.title
            dayLabel = planned != nil ? String(next.dayLabel.prefix(3)) : next.dayLabel
            minutes = next.estMin
            exercises = next.items.count
            tint = next.tint
            tint2 = next.blocks.first { $0.tint == next.tint }?.tint2 ?? next.tint
        } else {
            day = .weekDone
            title = sessions.contains(where: \.isMissed) ? "No more this week" : "Week complete"
            dayLabel = ""
            minutes = 0
            exercises = 0
            tint = 0x3DFFB0
            tint2 = 0x1E9BFF
        }
        week = snap.week
        deload = snap.deload
        done = rolled ? 0 : snap.progress.thisWeek
        target = snap.progress.target
        streak = snap.progress.streakWeeks
        bestStreak = snap.progress.bestStreakWeeks
        readiness = snap.readiness
        records = snap.progress.records
        last = snap.progress.recent.first
        water = snap.water

        let byDay = Dictionary(sessions.compactMap { s in WeekdayName.all.firstIndex(of: s.dayLabel).map { ($0, s) } },
                               uniquingKeysWith: { a, _ in a })
        if !sessions.isEmpty, sessions.allSatisfy({ WeekdayName.all.contains($0.dayLabel) }) {
            days = (0..<7).map { d in
                guard let s = byDay[d] else { return d == today ? .restToday : .rest }
                if s.done { return .done }
                return d == today ? .today : d < today ? .missed : .planned
            }
        } else {
            days = nil
        }
    }

    init(day: Day, title: String, dayLabel: String, minutes: Int, exercises: Int, tint: UInt32, tint2: UInt32,
         week: Int, deload: Bool, done: Int, target: Int, streak: Int, bestStreak: Int, readiness: String?,
         days: [DayState]?, records: [WRecord], last: WRecent?) {
        self.day = day; self.title = title; self.dayLabel = dayLabel; self.minutes = minutes; self.exercises = exercises
        self.tint = tint; self.tint2 = tint2; self.week = week; self.deload = deload; self.done = done; self.target = target
        self.streak = streak; self.bestStreak = bestStreak; self.readiness = readiness
        self.days = days; self.records = records; self.last = last
    }

    /// "TODAY · WEEK 2", "NEXT · WED", "REST DAY · NEXT WED", "WEEK COMPLETE".
    var eyebrow: String {
        let wk = deload ? "DELOAD" : "WEEK \(week)"
        switch day {
        case .today: return "TODAY · \(wk)"
        case .next: return "NEXT · \(dayLabel.uppercased())"
        case .rest: return "REST DAY · NEXT \(dayLabel.uppercased())"
        case .weekDone: return "WEEK COMPLETE"
        }
    }

    /// Readiness from the phone's headline: 3 ready, 2 as planned, 1 easier, nil unknown.
    var readinessLevel: Int? {
        guard let r = readiness else { return nil }
        if r.hasPrefix("Ready") { return 3 }
        if r.hasPrefix("Train") { return 2 }
        return 1
    }
}

/// Plan weekday names as the phone sends them (`WeekSchedule.names`, 1 = Monday).
enum WeekdayName {
    static let all = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    /// 0 = Monday … 6 = Sunday (Calendar weekday 1 = Sunday).
    static func index(_ date: Date, _ cal: Calendar) -> Int { (cal.component(.weekday, from: date) + 5) % 7 }
}

enum MW {
    static let lime = Color(red: 0.80, green: 1.0, blue: 0.24)
    static let mint = color(0x3DFFB0)

    static func color(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func gradient(_ a: UInt32, _ b: UInt32) -> LinearGradient {
        LinearGradient(colors: [color(a), color(b)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }

    static func kg(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

    /// "Today", "Yesterday", "Mon", "3 Oct".
    static func relativeDay(_ d: Date, from now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "Today" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 0
        if days == 1 { return "Yesterday" }
        return days < 7 ? d.formatted(.dateTime.weekday(.abbreviated)) : d.formatted(.dateTime.day().month(.abbreviated))
    }
}
