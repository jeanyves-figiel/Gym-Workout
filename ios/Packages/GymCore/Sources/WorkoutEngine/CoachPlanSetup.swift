import Foundation

/// Set up the plan by talking to Coach (#873, design B + C from `ai-epic/a3.png`). The member says what they want in
/// one sentence; Coach answers the plan form's values, shown as tiles to fix before the plan is built. Every value is
/// checked again here, so a wrong answer can only fall back to the form's defaults.
public struct CoachPlanDraft: Codable, Sendable, Equatable {
    public var goal: String
    public var experience: String
    public var sessions: Int
    public var weekdays: [Int]
    public var minutes: Int?
    public var climbs: Bool
    public var climbDays: Int?
    /// Body part to spare ("left knee"), kept as a Coach note.
    public var protect: String?
    public var summary: String

    public init(goal: String, experience: String, sessions: Int, weekdays: [Int] = [], minutes: Int? = nil, climbs: Bool = false,
                climbDays: Int? = nil, protect: String? = nil, summary: String = "") {
        self.goal = goal
        self.experience = experience
        self.sessions = sessions
        self.weekdays = weekdays
        self.minutes = minutes
        self.climbs = climbs
        self.climbDays = climbDays
        self.protect = protect
        self.summary = summary
    }

    public static let lengths = [45, 60, 75, 90]

    public var goalValue: Goal { Goal(rawValue: goal) ?? .balanced }
    public var experienceValue: Experience { Experience(rawValue: experience) ?? .beginner }
    public var sessionCount: Int { min(6, max(2, sessions)) }
    public var days: [Int] { Array(Set(weekdays.filter { (1...7).contains($0) })).sorted().prefix(sessionCount).map { $0 } }
    public var length: Int? { minutes.flatMap { m in Self.lengths.contains(m) ? m : nil } }
    public var protectText: String? {
        let t = protect?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : String(t.prefix(30))
    }

    /// The draft on the form's profile: gym, machines and map from the steps before stay as they are.
    public func applied(to base: Profile) -> Profile {
        var p = base
        p.applyGoal(goalValue)
        p.experience = experienceValue
        p.sessionsPerWeek = sessionCount
        p.gymWeekdays = days.isEmpty ? nil : days
        p.maxSessionMinutes = length
        p.climbs = climbs || goalValue == .climbing
        if p.climbs, let climbDays { p.climbingDaysPerWeek = min(4, max(1, climbDays)) }
        return p
    }
}

/// "Not sure? Ask Coach" on one plan form step (#873, design C): the step's options and the answers so far go up.
public struct CoachPlanHelpAsk: Codable, Sendable, Equatable {
    public struct Option: Codable, Sendable, Equatable {
        public var id: String
        public var label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    public var step: String
    public var options: [Option]
    public var so: [String]
    public var question: String?

    public init(step: String, options: [Option], so: [String], question: String? = nil) {
        self.step = step
        self.options = options
        self.so = so
        self.question = question
    }

    /// The answers so far, short, for Coach's context.
    public static func soFar(_ p: Profile) -> [String] {
        var out = ["Goal: \(p.goal.config.label)", "Experience: \(p.experience.rawValue)", "\(p.sessionsPerWeek) gym days a week"]
        if let m = p.maxSessionMinutes { out.append("\(m) min sessions") }
        if p.climbs { out.append("Climbs \(p.climbingDaysPerWeek)× a week") }
        if let g = p.gym { out.append("Gym: \(String(g.name.prefix(40)))") }
        return out
    }
}

public struct CoachPlanHelp: Codable, Sendable, Equatable {
    public var answer: String
    public var pick: String?

    public init(answer: String, pick: String? = nil) {
        self.answer = answer
        self.pick = pick
    }

    /// Coach's pick only when it is one of the step's options.
    public func pick(in ask: CoachPlanHelpAsk) -> CoachPlanHelpAsk.Option? {
        ask.options.first { $0.id == pick }
    }
}
