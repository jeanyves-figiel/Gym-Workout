import Foundation

// Climbing live (#829, A + B from `climb-track-live/proposals.png`): one tap per problem on the iPhone or the Watch,
// tallied into sends, falls, a top grade and a grade pyramid; the finished session becomes a logged climb.

/// How one problem or route went.
public enum ClimbResult: String, Codable, CaseIterable, Sendable {
    /// Topped on the first go.
    case flash
    /// Topped after earlier goes.
    case send
    case fall

    public var topped: Bool { self != .fall }
}

/// One go on a problem or route, at a grade of the session's scale.
public struct ClimbAttempt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var grade: String
    public var result: ClimbResult
    public var at: Date

    public init(id: UUID = UUID(), grade: String, result: ClimbResult, at: Date = Date()) {
        self.id = id
        self.grade = grade
        self.result = result
        self.at = at
    }
}

/// Grade scale for the chips: Font (bouldering in Europe, also French sport grades) or V-scale.
public enum ClimbScale: String, Codable, CaseIterable, Identifiable, Sendable {
    case font, v

    public var id: String { rawValue }
    public var label: String { self == .font ? "Font" : "V" }

    /// Easiest to hardest.
    public var grades: [String] {
        switch self {
        case .font: ["4", "4+", "5", "5+", "6A", "6A+", "6B", "6B+", "6C", "6C+", "7A", "7A+", "7B", "7B+", "7C", "7C+", "8A", "8A+"]
        case .v: (0...12).map { "V\($0)" }
        }
    }

    /// Where the chips open for a new member: a middle grade (6A / V3).
    public var start: String { self == .font ? "6A" : "V3" }

    public func rank(_ grade: String) -> Int? { grades.firstIndex(of: grade) }
}

/// Counts and the grade pyramid of a session's attempts.
public struct ClimbTally: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let grade: String
        public let tops: Int
        public let falls: Int
    }

    public let flashes: Int
    public let sends: Int
    public let falls: Int
    /// Hardest topped grade on the scale; nil when nothing was topped.
    public let top: String?
    /// Grades tried, hardest first.
    public let pyramid: [Row]

    /// Flashes count as sends here: "6 sends · 2 flashes".
    public var tops: Int { flashes + sends }
    public var attempts: Int { tops + falls }

    public init(_ attempts: [ClimbAttempt], scale: ClimbScale) {
        flashes = attempts.filter { $0.result == .flash }.count
        sends = attempts.filter { $0.result == .send }.count
        falls = attempts.filter { $0.result == .fall }.count
        // Grades off the scale (an older session in the other scale) sort below every grade on it.
        let rank = { (g: String) in scale.rank(g) ?? -1 }
        top = attempts.filter(\.result.topped).map(\.grade).max { rank($0) < rank($1) }
        let grades = Set(attempts.map(\.grade)).sorted { rank($0) > rank($1) }
        pyramid = grades.map { g in
            let at = attempts.filter { $0.grade == g }
            return Row(grade: g, tops: at.filter { $0.result.topped }.count, falls: at.filter { $0.result == .fall }.count)
        }
    }

    /// "6 sends · 2 flashes · 3 falls"; nil with no attempts.
    public var summary: String? {
        guard attempts > 0 else { return nil }
        var parts = ["\(tops) send\(tops == 1 ? "" : "s")"]
        if flashes > 0 { parts.append("\(flashes) flash\(flashes == 1 ? "" : "es")") }
        if falls > 0 { parts.append("\(falls) fall\(falls == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    /// Effort 1…10 for the logged climb: volume of goes and time on the wall (90 min with 20 goes ≈ 8, hard).
    public static func effort(attempts: Int, minutes: Int) -> Int {
        min(10, max(1, 3 + attempts / 6 + minutes / 30))
    }

    /// Seconds since the last attempt (rest between goes); nil before the first one.
    public static func rest(_ attempts: [ClimbAttempt], now: Date) -> Int? {
        attempts.map(\.at).max().map { max(0, Int(now.timeIntervalSince($0))) }
    }
}
