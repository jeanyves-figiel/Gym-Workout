import Foundation

/// Wow onboarding (#1084, mix A + B + C from `wow-onboarding/{a,b,c}.png`): Coach Monkey asks one question at a
/// time on sign up, answers are big gradient cards, Coach reacts to each. Then the gym steps, a "Building your
/// plan…" checklist and the plan reveal.
public enum CoachIntroQuestion: String, CaseIterable, Sendable, Identifiable {
    case goal, days, minutes, experience, level, diet
    public var id: String { rawValue }
}

/// What the member answered so far. A question answered with "skip" (diet) is in `answered` with no value.
public struct CoachIntroAnswers: Equatable, Sendable {
    public var goal: Goal?
    public var days: Int?
    /// Session length cap in minutes; nil = the goal's own length.
    public var minutes: Int?
    public var experience: Experience?
    public var level: AppLevel?
    public var diet: FuelDiet?
    /// Questions answered, in order.
    public var answered: [CoachIntroQuestion] = []

    public init() {}

    /// Diet is only asked when Fuel is part of the picked level.
    public var questions: [CoachIntroQuestion] {
        CoachIntroQuestion.allCases.filter { $0 != .diet || (level ?? .everything).modules.contains(.fuel) }
    }

    /// The next question to ask; nil = all done.
    public var next: CoachIntroQuestion? { questions.first { !answered.contains($0) } }

    /// 0…1 for the progress bar.
    public var fraction: Double {
        let qs = questions
        return Double(qs.filter { answered.contains($0) }.count) / Double(max(qs.count, 1))
    }

    public mutating func answer(_ q: CoachIntroQuestion) {
        if !answered.contains(q) { answered.append(q) }
    }

    /// Goes back one question, keeping nothing of it.
    public mutating func undoLast() {
        guard let last = answered.popLast() else { return }
        switch last {
        case .goal: goal = nil
        case .days: days = nil
        case .minutes: minutes = nil
        case .experience: experience = nil
        case .level: level = nil
        case .diet: diet = nil
        }
    }

    /// Puts the answers on the profile: goal first (it resets the week size), then the days picked.
    public func apply(to p: inout Profile) {
        if let goal { p.applyGoal(goal) }
        if let days { p.sessionsPerWeek = days }
        if answered.contains(.minutes) { p.maxSessionMinutes = minutes }
        if let experience { p.experience = experience }
    }
}

public enum CoachIntro {
    public static let dayChoices = [2, 3, 4, 5, 6]
    /// nil = "Let Coach pick" (the goal's own length).
    public static let minuteChoices: [Int?] = [30, 45, 60, 90, nil]

    public static func question(_ q: CoachIntroQuestion) -> String {
        switch q {
        case .goal: "Hey! I'm Coach 🐵 Let's build your plan. What are we chasing?"
        case .days: "How many days a week can you train?"
        case .minutes: "How long is a workout?"
        case .experience: "How long have you been lifting?"
        case .level: "How much app do you want? Change it any time in Settings → My app."
        case .diet: "How do you eat? Fuel's recipes will match."
        }
    }

    /// Coach's reaction to an answer, shown as its next bubble.
    public static func reaction(_ q: CoachIntroQuestion, _ a: CoachIntroAnswers) -> String {
        switch q {
        case .goal:
            switch a.goal ?? .balanced {
            case .balanced: return "All-rounder! Strength, cardio and mobility in every workout ⚡"
            case .build: return "Muscle it is 💪 More volume, every muscle hit often."
            case .strength: return "Strong it is 🔥 Heavy lifts, long rests, no junk."
            case .climbing: return "A climber! 🧗 I'll keep the gym light around your wall days."
            case .endurance: return "Engine mode ❤️ Cardio first, strength to stay unbreakable."
            case .athletic: return "Athlete! ⚡ Jumps, sprints and power with your lifts."
            }
        case .days:
            let d = a.days ?? 3
            switch d {
            case ...2: return "\(d) days: full body each time, nothing missed."
            case 3: return "3 days: the classic. Every muscle, every week."
            case 4: return "4 days: every muscle twice a week. Sweet spot."
            default: return "\(d) days! A split that hits every muscle twice."
            }
        case .minutes:
            if let m = a.minutes { return "\(m) min: I'll fit every workout inside it ⏱" }
            return "I'll pick the length that fits your goal."
        case .experience:
            switch a.experience ?? .beginner {
            case .beginner: return "Perfect. I'll start light and show you every move."
            case .intermediate: return "Nice. I'll push you a bit more each week."
            case .advanced: return "Let's go heavy. Weights climb every week 🦍"
            }
        case .level:
            switch a.level ?? .everything {
            case .workouts: return "Just workouts, nothing else. Clean and simple."
            case .plan: return "A plan to follow, with Coach and Insights."
            case .everything: return "The full app! Fuel, Mind, Social and the game too 🎉"
            }
        case .diet:
            if let d = a.diet { return "Got it \(d.emoji) Recipes and meal plans stay \(d.label.lowercased())." }
            return "No problem, Fuel waits until you want it."
        }
    }

    /// The line after the last answer, before the gym steps.
    public static let gymPrompt = "Now show me your gym. I'll build every workout from its machines."

    /// The "Building your plan…" checklist (#1084 B), ticked one by one.
    public static func buildSteps(_ a: CoachIntroAnswers, gymName: String?, machines: Int) -> [String] {
        let goal = a.goal ?? .balanced
        var steps = ["Goal: \(goal.config.label)"]
        let days = a.days ?? goal.recommendedSessions
        steps.append(a.minutes.map { "\(days) days × \($0) min" } ?? "\(days) days a week")
        if let gymName {
            steps.append(machines > 0 ? "\(machines) machines at \(gymName)" : "Workouts for \(gymName)")
        }
        steps.append("Starting weights for \(experienceLabel(a.experience ?? .beginner))")
        let modules = (a.level ?? .everything).modules
        if modules.contains(.fuel) { steps.append("Fuel: \(FuelGoal.from(goal).label.lowercased())") }
        if modules.contains(.mind) { steps.append("Mind: daily check-in") }
        return steps
    }

    public static func experienceLabel(_ e: Experience) -> String {
        switch e {
        case .beginner: "a new lifter"
        case .intermediate: "a regular"
        case .advanced: "a veteran"
        }
    }
}
