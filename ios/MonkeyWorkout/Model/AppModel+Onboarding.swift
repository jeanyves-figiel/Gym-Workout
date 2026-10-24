import Foundation
import WorkoutEngine

/// New member onboarding (#664): guided steps, the app tour and the set-up card for what was skipped.
extension AppModel {
    /// nil for members from before #664 (no set-up card); Settings → Onboarding starts one for them.
    var onboarding: OnboardingProgress? { state.synced?.onboarding }

    /// Records a finished step. Before the plan step there is no profile yet: the guided flow keeps those itself.
    func completeOnboarding(_ step: OnboardingStep) {
        guard state.synced != nil else { return }
        var p = state.synced?.onboarding ?? OnboardingProgress()
        guard !p.isDone(step) else { return }
        p.complete(step)
        saveOnboarding(p)
    }

    /// First plan made in the guided flow: the steps done before it, and a fresh card for the rest.
    func startOnboarding(done: [OnboardingStep]) {
        var p = state.synced?.onboarding ?? OnboardingProgress()
        for s in done { p.complete(s) }
        p.cardHidden = false
        saveOnboarding(p)
    }

    /// ✕ on the set-up card: the steps left stay in Settings → Onboarding. `false` brings the card back.
    func hideSetupCard(_ hidden: Bool = true) {
        var p = state.synced?.onboarding ?? OnboardingProgress()
        guard p.cardHidden != hidden else { return }
        p.cardHidden = hidden
        saveOnboarding(p)
    }

    private func saveOnboarding(_ p: OnboardingProgress) {
        guard state.synced != nil, state.synced?.onboarding != p else { return }
        state.synced?.onboarding = p
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    // MARK: App tour

    /// Starts the tour on Train; sheets on top close first.
    func startTour() {
        settingsOpen = false
        meOpen = false
        onboardingOpen = false
        tab = AppTour.steps[0].tab ?? .train
        tourStep = 0
    }

    /// Next bubble, or the end of the tour.
    func nextTourStep() {
        guard let i = tourStep else { return }
        if i + 1 < AppTour.steps.count {
            tourStep = i + 1
            if let t = AppTour.steps[i + 1].tab { tab = t }
        } else {
            endTour(finished: true)
        }
    }

    /// Done or skipped: a finished tour counts as done; a skipped one waits on the set-up card.
    func endTour(finished: Bool) {
        tourStep = nil
        tab = .train
        if finished { completeOnboarding(.tour) }
        if proAfterTour {
            proAfterTour = false
            offerPro = true
        }
    }
}

/// One bubble of the app tour (#664): the tab it opens and what that part of the app is for.
struct AppTourStep: Identifiable {
    let id: String
    let tab: MainTab?
    let symbol: String
    let title: String
    let text: String
    let category: WorkoutEngine.Category
}

enum AppTour {
    static let steps: [AppTourStep] = [
        AppTourStep(id: "train", tab: .train, symbol: "bolt.heart.fill", title: "Train",
                    text: "Your week, built for your gym. Today's workout starts here; earlier days can be logged.",
                    category: .strength),
        AppTourStep(id: "explore", tab: .explore, symbol: "figure.arms.open", title: "Explore",
                    text: "Every exercise by muscle or by machine in your gym, ready-made workouts and programmes.",
                    category: .cardio),
        AppTourStep(id: "progress", tab: .progress, symbol: "chart.line.uptrend.xyaxis", title: "Progress",
                    text: "Lifts, records, body and streaks. Pick the widgets you want on your board.",
                    category: .power),
        AppTourStep(id: "fuel", tab: .fuel, symbol: "fork.knife", title: "Fuel",
                    text: "Meals, meal plans, water and supplements. Snap the fridge to log what you ate.",
                    category: .warmup),
        AppTourStep(id: "community", tab: .community, symbol: "person.3.fill", title: "Community",
                    text: "Share workouts, find gym buddies and join the week challenge.",
                    category: .mobility),
        AppTourStep(id: "coach", tab: .train, symbol: "bubble.left.and.text.bubble.right.fill", title: "Coach Monkey",
                    text: "Tap 🐵 at the top right to ask Coach anything, hold to talk. The Me pill at the top right has Settings, and this tour again under Onboarding.",
                    category: .stretch),
    ]
}
