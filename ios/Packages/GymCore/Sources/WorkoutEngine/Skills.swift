import Foundation

/// Calisthenics skill tree (#621, designs A + B + C from `apple-tech-radar/batch4.html`): bodyweight skills in four
/// branches; each node unlocks the next by a test (max reps or seconds); one skill of the month gets 3 short
/// practices a week.
public enum Skills {
    public enum Branch: String, Codable, CaseIterable, Sendable, Identifiable {
        case pull, push, legs, balance

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .pull: "Pull"
            case .push: "Push"
            case .legs: "Legs"
            case .balance: "Balance & core"
            }
        }

        public var symbol: String {
            switch self {
            case .pull: "figure.climbing"
            case .push: "figure.strengthtraining.functional"
            case .legs: "figure.step.training"
            case .balance: "figure.gymnastics"
            }
        }
    }

    public struct Node: Hashable, Sendable, Identifiable {
        public let branch: Branch
        /// 1-based level in its branch.
        public let level: Int
        public let exerciseId: String
        /// Test target that unlocks the next level: reps, or seconds for holds.
        public let target: Int
        public var id: String { exerciseId }

        public var exercise: Exercise { Exercise.get(exerciseId) }
        public var seconds: Bool { exercise.unit == .sec }
        /// "8 reps", "30 s".
        public var targetText: String { seconds ? "\(target) s" : "\(target) reps" }
    }

    private static func chain(_ b: Branch, _ steps: [(String, Int)]) -> [Node] {
        steps.enumerated().map { Node(branch: b, level: $0.offset + 1, exerciseId: $0.element.0, target: $0.element.1) }
    }

    public static let tree: [Branch: [Node]] = [
        .pull: chain(.pull, [("dead-hang", 30), ("negative-pull-up", 5), ("pull-up", 8), ("archer-pull-up", 4), ("muscle-up", 3)]),
        .push: chain(.push, [("knee-push-up", 15), ("push-up", 20), ("pike-push-up", 10), ("wall-hspu", 5), ("freestanding-hspu", 3)]),
        .legs: chain(.legs, [("bw-squat", 30), ("bw-split-squat", 15), ("box-pistol", 6), ("pistol-squat", 5)]),
        .balance: chain(.balance, [("plank", 60), ("hollow-hold", 30), ("l-sit", 15), ("tuck-front-lever", 10), ("front-lever", 5)]),
    ]

    public static func nodes(_ b: Branch) -> [Node] { tree[b] ?? [] }

    public static func node(_ exerciseId: String) -> Node? { tree.values.flatMap { $0 }.first { $0.exerciseId == exerciseId } }

    // MARK: Practice of the skill of the month (C)

    static let practicePrefix = "skill-practice-"

    /// 10′ practice: the skill itself (or its level below as a ladder) in short sets with long rests.
    public static func practice(_ node: Node) -> WorkoutTemplate {
        let below = nodes(node.branch).first { $0.level == node.level - 1 }
        let dose = node.seconds ? max(5, node.target / 2) : max(2, node.target / 2)
        var items = [WorkoutTemplate.Item(node.exerciseId, sets: 4, reps: dose, rest: 75, block: .strength)]
        if let below { items.append(WorkoutTemplate.Item(below.exerciseId, sets: 2, reps: below.target, rest: 60, block: .strength)) }
        return WorkoutTemplate(id: practicePrefix + node.exerciseId,
                               name: "Skill practice · \(node.exercise.name)", focus: node.branch == .legs ? .lower : .upper,
                               goal: .fullBody, kit: node.exercise.equipment.isEmpty ? "No kit" : "Bar or box", level: min(3, max(1, node.level - 1)),
                               main: .strength, items: items)
    }

    /// A record or session of a skill practice.
    public static func isPractice(_ sessionId: String) -> Bool { sessionId.hasPrefix(WorkoutTemplate.idPrefix + practicePrefix) }

    /// Every practice, so `WorkoutTemplate.find(sessionId:)` resolves them.
    public static let practices: [WorkoutTemplate] = Branch.allCases.flatMap { nodes($0) }.map(practice)

    /// Weekdays (1 = Monday) a skill of the month is practised.
    public static let practiceDays = [1, 3, 5]

    /// Practice days in `month` ("2026-10") up to its end: the month's goal.
    public static func practiceGoal(month: String, calendar cal: Calendar) -> Int {
        guard let start = monthStart(month, cal), let range = cal.range(of: .day, in: .month, for: start) else { return 12 }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: start) }
            .filter { practiceDays.contains(WeekSchedule.fromCalendar(cal.component(.weekday, from: $0))) }.count
    }

    public static func monthKey(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func monthStart(_ month: String, _ cal: Calendar) -> Date? {
        let p = month.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: 1))
    }
}

/// The member's skill tree progress (#621), synced with the profile. Every field optional so older profiles decode.
public struct SkillProgress: Codable, Hashable, Sendable {
    /// Best test per exercise id (reps or seconds).
    public var best: [String: Int]?
    /// Skill of the month: exercise id and month ("2026-10").
    public var focus: String?
    public var focusMonth: String?

    public init(best: [String: Int]? = nil, focus: String? = nil, focusMonth: String? = nil) {
        self.best = best
        self.focus = focus
        self.focusMonth = focusMonth
    }

    /// Highest unlocked level in a branch: level 1 always; each passed test opens the next.
    public func unlocked(_ b: Skills.Branch) -> Int {
        var level = 1
        for n in Skills.nodes(b) where (best?[n.exerciseId] ?? 0) >= n.target {
            guard n.level == level else { break }
            level = min(Skills.nodes(b).count, n.level + 1)
        }
        return level
    }

    /// Whether a node's test was passed.
    public func passed(_ n: Skills.Node) -> Bool { (best?[n.exerciseId] ?? 0) >= n.target }

    /// Records a test; returns the node it unlocked, if any.
    @discardableResult
    public mutating func record(_ n: Skills.Node, result: Int) -> Skills.Node? {
        let before = unlocked(n.branch)
        var b = best ?? [:]
        b[n.exerciseId] = max(b[n.exerciseId] ?? 0, result)
        best = b
        let after = unlocked(n.branch)
        return after > before ? Skills.nodes(n.branch).first { $0.level == after } : nil
    }

    /// The skill of the month when it is this month.
    public func focusNode(now: Date, calendar cal: Calendar) -> Skills.Node? {
        guard focusMonth == Skills.monthKey(now, cal), let f = focus else { return nil }
        return Skills.node(f)
    }
}
