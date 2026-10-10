import Foundation
import WorkoutEngine

/// Climbing session types offered when logging a climb (#44).
enum ClimbKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case boulder, lead, topRope, outdoor
    var id: String { rawValue }

    var label: String {
        switch self {
        case .boulder: "Boulder"
        case .lead: "Lead"
        case .topRope: "Top rope"
        case .outdoor: "Outdoor"
        }
    }

    var symbol: String {
        switch self {
        case .boulder: "figure.climbing"
        case .lead: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .topRope: "arrow.up.and.down.circle.fill"
        case .outdoor: "mountain.2.fill"
        }
    }
}

/// A climb logged in this app. Stored locally and, when connected, written to Apple Health.
struct ClimbLog: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: ClimbKind = .boulder
    var start: Date
    var minutes: Int = 90
    /// 1 (very easy) … 10 (max effort).
    var effort: Int = 7
    /// Free text, any scale (6B+, V5, 7a).
    var topGrade: String?
    var notes: String?

    var end: Date { start.addingTimeInterval(Double(minutes) * 60) }

    static func effortLabel(_ e: Int) -> String {
        switch e {
        case ...3: "Easy"
        case 4...5: "Moderate"
        case 6...7: "Solid"
        case 8...9: "Hard"
        default: "Max"
        }
    }
}

/// One climb shown in the app: logged here, or read from Apple Health (any app, e.g. MonkeyGrade).
struct ClimbEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    /// App that recorded it ("MonkeyWorkout" for climbs logged here).
    let source: String
    var kind: ClimbKind?
    var effort: Int?
    var topGrade: String?
    /// True when logged in this app (can be deleted here).
    var local = false
    /// Extra line, e.g. "12 sends · 3 flashes" from MonkeyGrade.
    var detail: String?

    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

    init(id: UUID, start: Date, end: Date, source: String, kind: ClimbKind? = nil, effort: Int? = nil, topGrade: String? = nil, local: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.source = source
        self.kind = kind
        self.effort = effort
        self.topGrade = topGrade
        self.local = local
    }

    init(_ log: ClimbLog) {
        self.init(id: log.id, start: log.start, end: log.end, source: "MonkeyWorkout",
                  kind: log.kind, effort: log.effort, topGrade: log.topGrade, local: true)
    }

    /// Hard on fingers and pulling: logged effort ≥ 8, or ≥ 2 h when the effort is unknown.
    var isHard: Bool {
        if let effort { return effort >= 8 }
        return minutes >= 120
    }
}

enum Climbs {
    /// Logged climbs, MonkeyGrade sessions, and Health climbs not already covered by either, newest first.
    /// Health copies are matched by id (written here) or by overlapping time (written by MonkeyGrade's app).
    static func merged(local: [ClimbLog], health: [ClimbEntry], monkeyGrade: [ClimbEntry] = []) -> [ClimbEntry] {
        let ids = Set(local.map(\.id))
        let mine = local.map { ClimbEntry($0) }
        let others = health.filter { h in
            !ids.contains(h.id) && !monkeyGrade.contains { overlaps($0, h) }
        }
        return (mine + monkeyGrade + others).sorted { $0.start > $1.start }
    }

    static func overlaps(_ a: ClimbEntry, _ b: ClimbEntry) -> Bool {
        a.start < b.end && b.start < a.end
    }

    /// Hardest grade when labels are all Font (6A, 7B+) or all V-scale (V5); nil for colours or mixed scales.
    static func hardest(_ labels: [String]) -> String? {
        let l = labels.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
        guard !l.isEmpty else { return nil }
        let isFont = l.allSatisfy { $0.range(of: #"^[3-9][ABC]?\+?$"#, options: .regularExpression) != nil }
        if isFont { return l.max { fontRank($0) < fontRank($1) } }
        let isV = l.allSatisfy { $0.range(of: #"^V\d{1,2}$"#, options: .regularExpression) != nil }
        if isV { return l.max { (Int($0.dropFirst()) ?? 0) < (Int($1.dropFirst()) ?? 0) } }
        return nil
    }

    private static func fontRank(_ g: String) -> Int {
        let chars = Array(g)
        let n = Int(String(chars[0])) ?? 0
        let letter = chars.count > 1 && chars[1] != "+" ? Int(chars[1].asciiValue ?? 65) - 64 : 0
        return n * 100 + letter * 10 + (g.hasSuffix("+") ? 1 : 0)
    }

    static func thisWeek(_ climbs: [ClimbEntry], now: Date = Date()) -> Int {
        let cal = Progression.calendar()
        let start = Progression.weekStart(now, cal)
        return climbs.filter { $0.start >= start && $0.start <= now }.count
    }

    /// Hard climb finished yesterday or today → keep grip and pulling light in the next gym session.
    static func recentHard(_ climbs: [ClimbEntry], now: Date = Date()) -> ClimbEntry? {
        let cal = Progression.calendar()
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) else { return nil }
        return climbs.first { $0.isHard && $0.end >= yesterday && $0.start <= now }
    }

    /// Rough active energy: climbing MET ≈ 5.8 (top rope) … 8 (bouldering/lead), scaled by effort.
    static func kcal(_ log: ClimbLog, weightKg: Double?) -> Double? {
        guard let w = weightKg, w > 0 else { return nil }
        let met = (log.kind == .topRope ? 5.8 : 8.0) * (0.7 + 0.06 * Double(min(max(log.effort, 1), 10)))
        return (met * w * Double(log.minutes) / 60).rounded()
    }
}
