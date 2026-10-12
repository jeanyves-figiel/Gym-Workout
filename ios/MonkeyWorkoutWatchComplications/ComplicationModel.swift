import Foundation
import SwiftUI

/// What every complication shows, flattened from the last phone snapshot for a given moment (#190).
struct ComplicationInfo {
    enum Day { case today, next, rest, weekDone }

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

    var progress: Double { target == 0 ? 0 : min(1, Double(done) / Double(target)) }

    static let sample = ComplicationInfo(
        day: .today, title: "Upper Push", dayLabel: "Mon", minutes: 50, exercises: 6, tint: 0x2F6BFF, tint2: 0x00C9A7,
        week: 2, deload: false, done: 2, target: 3, streak: 4, bestStreak: 6, readiness: "Ready to push")

    /// nil = nothing synced from the iPhone yet.
    init?(_ snap: WatchSnapshot?, at date: Date) {
        guard let snap, !snap.sessions.isEmpty || !snap.extras.isEmpty else { return nil }
        let cal = Calendar(identifier: .iso8601)
        // A new week started since the last sync: the phone resets the week, so does the watch face.
        let rolled = !cal.isDate(snap.generatedAt, equalTo: date, toGranularity: .weekOfYear)
        var sessions = snap.sessions
        if rolled { for i in sessions.indices { sessions[i].done = false } }
        let next = rolled ? sessions.first : (snap.nextSessionId.flatMap { id in sessions.first { $0.id == id } } ?? sessions.first { !$0.done })
        let today = WeekdayName.index(date, cal)

        if let next {
            let planned = WeekdayName.all.firstIndex(of: next.dayLabel)
            let named = planned != nil
            // Later this week = rest today; earlier (missed) or no weekdays = still next up.
            if let planned { day = planned == today ? .today : planned > today ? .rest : .next } else { day = .next }
            title = next.title
            dayLabel = named ? String(next.dayLabel.prefix(3)) : next.dayLabel
            minutes = next.estMin
            exercises = next.items.count
            tint = next.tint
            tint2 = next.blocks.first { $0.tint == next.tint }?.tint2 ?? next.tint
        } else {
            day = .weekDone
            title = "Week complete"
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
    }

    init(day: Day, title: String, dayLabel: String, minutes: Int, exercises: Int, tint: UInt32, tint2: UInt32,
         week: Int, deload: Bool, done: Int, target: Int, streak: Int, bestStreak: Int, readiness: String?) {
        self.day = day; self.title = title; self.dayLabel = dayLabel; self.minutes = minutes; self.exercises = exercises
        self.tint = tint; self.tint2 = tint2; self.week = week; self.deload = deload; self.done = done; self.target = target
        self.streak = streak; self.bestStreak = bestStreak; self.readiness = readiness
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
}

/// Plan weekday names as the phone sends them (`WeekSchedule.names`, 1 = Monday).
enum WeekdayName {
    static let all = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// 0 = Monday … 6 = Sunday (Calendar weekday 1 = Sunday).
    static func index(_ date: Date, _ cal: Calendar) -> Int { (cal.component(.weekday, from: date) + 5) % 7 }
}

enum MW {
    static let lime = Color(red: 0.80, green: 1.0, blue: 0.24)
    static let flame = color(0xFFC23D)
    static let flame2 = color(0xFF7A3D)
    static let mint = color(0x3DFFB0)

    static func color(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func gradient(_ a: UInt32, _ b: UInt32) -> LinearGradient {
        LinearGradient(colors: [color(a), color(b)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
}
