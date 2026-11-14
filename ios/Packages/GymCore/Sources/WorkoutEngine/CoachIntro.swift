import Foundation

/// Wow onboarding (#1084, mix A + B + C from `wow-onboarding/{a,b,c}.png`): Coach Monkey asks one question at a
/// time on sign up, answers are big gradient cards, Coach reacts to each. Then the gym steps, a "Building your
/// plan…" checklist and the plan reveal.
public enum CoachIntroQuestion: String, CaseIterable, Sendable, Identifiable {
    case goal, days, weekdays, minutes, experience, sports, sportDays, focus, pain, level, diet, allergies
    case figure, pronouns, health, reminder
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
    /// Gym weekdays (1 = Monday … 7 = Sunday); nil = any day.
    public var weekdays: [Int]?
    /// Sports besides the gym, and the weekdays they're on.
    public var sports: [Sport] = []
    public var sportDays: [Int] = []
    /// Muscle groups to bring up (max 2).
    public var focus: [MuscleGroup] = []
    /// A spot to protect (train around pain, #870).
    public var pain: PainArea?
    public var allergies: Set<Allergen> = []
    public var figure: BodyMapLayout.Figure?
    public var pronouns: Pronouns?
    /// Connect Apple Health: true = asked iOS.
    public var health: Bool?
    /// Workout-day reminder, minutes after midnight; nil = none.
    public var reminder: Int?
    /// "No reminders" tapped: workout-day reminders go off (skip keeps them as they are).
    public var noReminders = false
    /// Questions answered, in order.
    public var answered: [CoachIntroQuestion] = []

    public init() {}

    /// Diet and allergies only when Fuel is part of the picked level; sport days only with a sport.
    public var questions: [CoachIntroQuestion] {
        let fuel = (level ?? .everything).modules.contains(.fuel)
        return CoachIntroQuestion.allCases.filter { q in
            switch q {
            case .diet, .allergies: fuel
            case .sportDays: !sports.isEmpty
            default: true
            }
        }
    }

    public static let maxFocus = 2

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
        case .weekdays: weekdays = nil
        case .sports: sports = []; sportDays = []
        case .sportDays: sportDays = []
        case .focus: focus = []
        case .pain: pain = nil
        case .allergies: allergies = []
        case .figure: figure = nil
        case .pronouns: pronouns = nil
        case .health: health = nil
        case .reminder: reminder = nil; noReminders = false
        }
    }

    /// Puts the answers on the profile: goal first (it resets the week size), then the days picked.
    public func apply(to p: inout Profile) {
        if let goal { p.applyGoal(goal) }
        if let days { p.sessionsPerWeek = days }
        if answered.contains(.minutes) { p.maxSessionMinutes = minutes }
        if let experience { p.experience = experience }
        if let weekdays, !weekdays.isEmpty {
            p.gymWeekdays = weekdays.sorted()
            p.sessionsPerWeek = weekdays.count
        }
        let sportWeekdays = sportDays.sorted()
        if sports.contains(.climbing) {
            p.climbs = true
            if !sportWeekdays.isEmpty {
                p.climbingWeekdays = sportWeekdays
                p.climbingDaysPerWeek = sportWeekdays.count
            }
        }
        let others = sports.filter { $0 != .climbing }
        if !others.isEmpty { p.sports = others.map { SportPlan(sport: $0, weekdays: sportWeekdays) } }
        if !focus.isEmpty { p.focusMuscles = focus }
    }

    /// Toggles a weekday (1…7) in a multi-pick list.
    public static func toggled(_ list: [Int], _ day: Int) -> [Int] {
        list.contains(day) ? list.filter { $0 != day } : (list + [day]).sorted()
    }
}

public enum CoachIntro {
    public static let dayChoices = [2, 3, 4, 5, 6]
    /// nil = "Let Coach pick" (the goal's own length).
    public static let minuteChoices: [Int?] = [30, 45, 60, 90, nil]

    public static let weekdayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    /// Sports offered as tiles (more in Settings → Sports).
    public static let sportChoices: [Sport] = [.climbing, .run, .roadBike, .mountainBike, .swim, .football,
                                               .tennis, .padel, .martialArts, .yoga, .hyrox, .ski]
    /// Reminder times offered (minutes after midnight); nil = no reminder.
    public static let reminderChoices: [Int?] = [7 * 60, 12 * 60, 17 * 60 + 30, 19 * 60, nil]

    public static func dayList(_ days: [Int]) -> String {
        days.sorted().compactMap { (1...7).contains($0) ? weekdayShort[$0 - 1] : nil }.joined(separator: ", ")
    }

    public static func clock(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }

    public static func sportList(_ sports: [Sport]) -> String { sports.map(\.label).joined(separator: ", ") }

    public static func question(_ q: CoachIntroQuestion, _ a: CoachIntroAnswers = CoachIntroAnswers()) -> String {
        switch q {
        case .weekdays: "Which days suit you? Tap them, or any day."
        case .sports: "Any sports besides the gym? Tap all you do."
        case .sportDays: "Which days do you do \(sportList(a.sports))?"
        case .focus: "Muscles you want to bring up? Pick up to \(CoachIntroAnswers.maxFocus)."
        case .pain: "Anything hurting right now? I'll train around it."
        case .allergies: "Anything you can't eat?"
        case .figure: "Which figure should your body maps show?"
        case .pronouns: "How should I talk about you?"
        case .health: "Connect Apple Health? Sleep, steps and Watch workouts make your readiness smarter."
        case .reminder: "Want a nudge on workout days?"
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
        case .weekdays:
            if let w = a.weekdays, !w.isEmpty { return "\(dayList(w)) locked in 📅" }
            return "Any day works. I'll spread them out."
        case .sports:
            if a.sports.isEmpty { return "Gym only, full focus 💪" }
            return "\(sportList(a.sports))! I'll plan the gym around it."
        case .sportDays:
            if a.sportDays.isEmpty { return "No fixed days, log them when you go." }
            return "\(dayList(a.sportDays)) for sport. The gym stays light the day before."
        case .focus:
            if a.focus.isEmpty { return "Balanced it is: every muscle the same." }
            return "Extra sets for \(a.focus.map { $0.label.lowercased() }.joined(separator: " and ")) 🎯"
        case .pain:
            if let p = a.pain { return "I'll pick moves that spare your \(p.label). If it gets worse, see a doctor." }
            return "Great, nothing to protect."
        case .allergies:
            if a.allergies.isEmpty { return "No limits, every recipe on." }
            let list = Allergen.allCases.filter { a.allergies.contains($0) }.map { $0.label.lowercased() }
            return "No \(list.joined(separator: ", ")) in any recipe."
        case .figure:
            return a.figure == nil ? "I'll pick one, change it in Body & Health." : "Your body maps show this figure."
        case .pronouns:
            return a.pronouns == nil ? "No problem." : "Thanks! I'll use \(a.pronouns?.label ?? "that")."
        case .health:
            return a.health == true ? "Health on ❤️ Readiness gets smarter every day." : "Later then: Settings → Body & Health."
        case .reminder:
            if let m = a.reminder { return "I'll nudge you at \(clock(m)) on workout days ⏰" }
            return a.noReminders ? "No reminders. You've got this 😉" : "Change reminders any time in Settings."
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
        let days = a.weekdays.flatMap { $0.isEmpty ? nil : $0.count } ?? a.days ?? goal.recommendedSessions
        steps.append(a.minutes.map { "\(days) days × \($0) min" } ?? "\(days) days a week")
        if !a.sports.isEmpty { steps.append("Gym around \(sportList(a.sports))") }
        if !a.focus.isEmpty { steps.append("Focus: \(a.focus.map(\.label).joined(separator: " + "))") }
        if let p = a.pain { steps.append(p.friendly) }
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
