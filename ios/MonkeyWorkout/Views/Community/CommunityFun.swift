import APIClient
import SwiftUI
import WorkoutEngine

// More fun Community (#566): a colour per workout focus, Coach Monkey lines, moment cards and Trained today.

/// Special posts: a personal best, a streak milestone or a level up. Old record posts count as personal bests.
enum CommunityMoment: String {
    case pr, streak, level

    init?(_ post: CommunityPost) {
        if post.kind == "record" { self = .pr; return }
        guard let s = post.payload.style, s.hasPrefix("moment:"), let m = CommunityMoment(rawValue: String(s.dropFirst(7))) else { return nil }
        self = m
    }

    var label: String {
        switch self {
        case .pr: "NEW PR 🏆"
        case .streak: "STREAK 🔥"
        case .level: "LEVEL UP ⬆︎"
        }
    }

    var colors: [Color] {
        switch self {
        case .pr: [Color(hex: 0xFFD84A), Color(hex: 0xFF9A2F)]
        case .streak: [Color(hex: 0xFF3B30), Color(hex: 0xFF9A2F)]
        case .level: [Color(hex: 0x8A4DFF), Color(hex: 0x2F6BFF)]
        }
    }

    var ink: Color { self == .pr ? Theme.ink : .white }
}

/// Workout focus read from the title, so Legs, Chest and Pull days each get their own colour.
enum WorkoutFocus: CaseIterable {
    case legs, push, pull, arms, shoulders, core, full

    init(title: String) {
        let t = title.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        self = if has(["leg", "squat", "glute", "quad", "hamstring", "lower"]) {
            .legs
        } else if has(["chest", "push", "bench", "pec"]) {
            .push
        } else if has(["pull", "back", "row", "lat ", "lats", "deadlift"]) {
            .pull
        } else if has(["arm", "bicep", "tricep", "curl"]) {
            .arms
        } else if has(["shoulder", "delt", "press", "upper"]) {
            .shoulders
        } else if has(["core", "abs", "plank"]) {
            .core
        } else {
            .full
        }
    }

    var colors: [Color] {
        switch self {
        case .legs: [Color(hex: 0xFF7A2F), Color(hex: 0xE8455E)]
        case .push: [Color(hex: 0xE84FB0), Color(hex: 0x8A4FF0)]
        case .pull: [Color(hex: 0x00C9A7), Color(hex: 0x2F8CFF)]
        case .arms: [Color(hex: 0xFF2D55), Color(hex: 0xFF8A00)]
        case .shoulders: [Color(hex: 0x8A4DFF), Color(hex: 0x2EC5FF)]
        case .core: [Color(hex: 0x14B87A), Color(hex: 0x00A0D0)]
        case .full: WorkoutEngine.Category.strength.colors
        }
    }

    var emoji: String {
        switch self {
        case .legs: "🦵"
        case .push: "💪"
        case .pull: "🦍"
        case .arms: "💪"
        case .shoulders: "🏋️"
        case .core: "🎯"
        case .full: "🏋️"
        }
    }
}

extension CommunityPost {
    /// Card colours: moments first, then the focus of a strength workout, else the card's own style.
    var colors: [Color] {
        if let m = CommunityMoment(self) { return m.colors }
        if kind == "workout", (payload.style ?? "strength") == "strength" { return WorkoutFocus(title: payload.title).colors }
        return payload.colors
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
    var ink: Color { CommunityMoment(self)?.ink ?? .white }

    /// Little picture for the Trained today tile.
    var emoji: String {
        if let s = payload.style, s.hasPrefix("sport:") { return s == "sport:climbing" ? "🧗" : "🏃" }
        if kind == "climb" { return "🧗" }
        return WorkoutFocus(title: payload.title).emoji
    }
}

/// Coach Monkey's one-liner under a shared workout: the big number turned into something silly.
enum CoachQuip {
    static func line(for post: CommunityPost) -> String? {
        guard CommunityMoment(post) == nil, ["workout", "climb"].contains(post.kind), let m = post.payload.metric else { return nil }
        let value = Double(m.value.replacingOccurrences(of: ",", with: ".")) ?? 0
        let unit = m.unit.lowercased()
        // Stable per post (String.hashValue changes every launch).
        let pick = post.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let first: String? = if unit.hasPrefix("t lifted"), value > 0 {
            value >= 6 ? "\(fmt(value / 6)) elephants lifted." : value >= 1.5 ? "\(fmt(value / 1.5)) cars lifted." : "\(fmt(value / 0.5)) grand pianos lifted."
        } else if unit == "km", value > 0 {
            "\(fmt(value / 0.105)) football pitches."
        } else if unit == "top grade" {
            "Gravity filed a complaint."
        } else if unit == "min", value > 0 {
            "\(Int((value / 3.5).rounded())) songs of pure effort."
        } else { nil }
        guard let first else { return nil }
        return "\(first) \(tails[pick % tails.count])"
    }

    private static let tails = [
        "Banana earned.", "The rack respects you.", "Mirror selfie allowed.", "Sofa on notice.",
        "Coach is proud.", "Stairs fear you now.", "Certified beast.", "Protein o'clock.",
    ]

    private static func fmt(_ v: Double) -> String { v >= 10 ? "\(Int(v.rounded()))" : String(format: "%.1f", v) }
}

/// Coach Monkey's line on a post card.
struct CoachQuipRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            MonkeyFace(mood: .happy, scale: 0.36)
            Text(text).font(.caption.weight(.bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.2)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach Monkey: \(text)")
    }
}

/// Members who shared a workout today: the story row on Social (#738).
enum TrainedToday {
    /// Newest post of each member made today (workouts, sports and climbs), newest first.
    static func today(_ posts: [CommunityPost], now: Date = Date(), calendar: Calendar = .current) -> [CommunityPost] {
        var seen = Set<String>()
        return posts
            .filter { ["workout", "climb"].contains($0.kind) && !$0.hidden && calendar.isDate($0.createdAt, inSameDayAs: now) }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.author.userId).inserted }
    }
}

// MARK: - Moments to auto-share

extension WinCard {
    /// Streak lengths worth a post.
    static let streakMilestones: Set<Int> = [2, 3, 4, 6, 8, 10, 12, 16, 20, 26, 39, 52]

    static func streak(_ weeks: Int, date: Date) -> WinCard {
        // Dated: a streak that breaks and comes back to the same length is a new post.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return WinCard(kind: "badge", refId: "streak-\(weeks)-\(f.string(from: date))",
                       card: CommunityCard(title: "Unbreakable", subtitle: "Trained every week", metric: .init(value: "\(weeks)", unit: "weeks"),
                                           style: "moment:streak"),
                       symbol: "flame.fill", date: date)
    }

    static func levelUp(_ level: Int, date: Date) -> WinCard {
        let rank = GameProgress(xp: (level - 1) * GameProgress.perLevel).rank
        return WinCard(kind: "badge", refId: "level-\(level)",
                       card: CommunityCard(title: "Now \(rank)", subtitle: "Level \(level - 1) → \(level)", metric: .init(value: "\(level)", unit: "level"),
                                           style: "moment:level"),
                       symbol: "arrow.up.circle.fill", date: date)
    }

    /// New personal bests, streak milestones and level ups that the last 24 h of workouts earned: the history
    /// before them is compared with the whole history. First lifts of an exercise aren't bests.
    static func moments(history: [WorkoutRecord], weights: [WeightEntry], targetPerWeek: Int, moveXP: Int, now: Date = Date()) -> [WinCard] {
        let recent = history.filter { now.timeIntervalSince($0.startedAt) < Community.autoShareWindow }
        guard let latest = recent.map(\.startedAt).max() else { return [] }
        let before = history.filter { now.timeIntervalSince($0.startedAt) >= Community.autoShareWindow }
        let was = Progression.stats(records: before, weights: weights, targetPerWeek: targetPerWeek)
        let after = Progression.stats(records: history, weights: weights, targetPerWeek: targetPerWeek)
        var wins: [WinCard] = []
        let old = Dictionary(was.personalRecords.map { ($0.exerciseId, $0.kg) }, uniquingKeysWith: max)
        let gains = after.personalRecords.compactMap { pr -> (PersonalRecord, Double)? in
            guard let prev = old[pr.exerciseId], pr.kg > prev, now.timeIntervalSince(pr.date) < Community.autoShareWindow else { return nil }
            return (pr, pr.kg / prev)
        }
        // One best per day: the biggest jump.
        if let top = gains.max(by: { $0.1 < $1.1 }) { wins.append(.best(top.0)) }
        if after.currentStreakWeeks > was.currentStreakWeeks, streakMilestones.contains(after.currentStreakWeeks) {
            wins.append(.streak(after.currentStreakWeeks, date: latest))
        }
        let levelBefore = GameProgress.evaluate(records: before, targetPerWeek: targetPerWeek, moveXP: moveXP).level
        let levelNow = GameProgress.evaluate(records: history, targetPerWeek: targetPerWeek, moveXP: moveXP).level
        if levelNow > levelBefore { wins.append(.levelUp(levelNow, date: latest)) }
        return wins
    }
}
