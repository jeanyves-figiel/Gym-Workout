import SwiftUI
import WorkoutEngine

/// One part of the training profile, editable on its own screen (#99).
enum ProfileSection: String, CaseIterable, Identifiable, Hashable {
    case goal, week, time, variety, style, flow, method, gym
    var id: String { rawValue }

    /// Set by a running training programme (#255); shown locked.
    var programmeLocked: Bool { self == .goal || self == .method }

    var title: String {
        switch self {
        case .goal: "Goal"
        case .week: "Your week"
        case .time: "Workout time"
        case .variety: "Week to week"
        case .style: "Training style"
        case .flow: "Session flow"
        case .method: "Training method"
        case .gym: "Your gym"
        }
    }
}

/// Train → Training profile: a hub of vivid section cards, each opening its own editor.
struct TrainingProfileView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let p = model.profile {
                VStack(spacing: 12) {
                    // Training programme (#255): sets goal, split and method while it runs.
                    ProgrammeProfileCard()
                    ForEach(ProfileSection.allCases) { s in
                        if model.runningProgramme != nil && s.programmeLocked {
                            ProfileSectionCard(section: s, profile: p, locked: true)
                        } else {
                            NavigationLink(value: s) { ProfileSectionCard(section: s, profile: p) }
                                .buttonStyle(.plain)
                        }
                    }
                    // Lift Focus (#499): peak one lift for a target.
                    LiftFocusCard()
                    // Start fresh (#492): a brand new plan, history kept.
                    FreshStartCard()
                }
                .padding(16)
            }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationDestination(for: ProfileSection.self) { ProfileSectionView(section: $0) }
        .navigationDestination(for: ProgrammeRoute.self) { r in model.findProgramme(r.id).map { ProgrammeDetailView(programme: $0) } }
    }
}

/// One section's editor; saving re-plans the current week and goes back. Also opened from Community (Your gym).
struct ProfileSectionView: View {
    let section: ProfileSection
    /// Values brought back by Undo (#285).
    var restoring: Profile?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProfileFormView(initial: model.profile, section: section,
                        onGymChange: section == .gym ? { model.editGym($0) } : nil, restoring: restoring) { p in
            if section == .gym { model.editGym(p) } else { model.updateProfile(p) }
            dismiss()
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Explore-style section card: icon tile left, heavy title and current value, big number right.
struct ProfileSectionCard: View {
    let section: ProfileSection
    let profile: Profile
    /// Set by a running programme (#255): dimmed, lock instead of the chevron.
    var locked = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(light ? Theme.ink.opacity(0.12) : .white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.6)
                Text(value).font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(big.0).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.5)
                Text(big.1).font(Theme.label(9)).tracking(1.2).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
            }
            // Natural width only: a capped flexible frame always took 96 pt and truncated titles (#231).
            .fixedSize()
            Image(systemName: locked ? "lock.fill" : "chevron.right").font(.footnote.bold()).opacity(0.7)
        }
        .foregroundStyle(light ? Theme.ink : .white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
        .opacity(locked ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title): \(value)\(locked ? ", set by your programme" : "")")
    }

    private var gymName: String { profile.gym?.name ?? Gym.puls5.name }

    /// On the light warm-up gradient: dark type (#540).
    private var light: Bool {
        switch section {
        case .flow: true
        case .time: WorkoutTimeOfDay(profile.workoutTime) == .morning || WorkoutTimeOfDay(profile.workoutTime) == .unset
        case .method: profile.trainingMethod == .volume
        default: false
        }
    }

    private var symbol: String {
        switch section {
        case .goal: profile.goal.symbol
        case .week: "calendar"
        case .time: WorkoutTimeOfDay(profile.workoutTime).symbol
        case .variety: profile.planVariety.symbol
        case .style: profile.rest.symbol
        case .flow: "rectangle.split.3x1.fill"
        case .method: profile.trainingMethod.symbol
        case .gym: "building.2.fill"
        }
    }

    /// Also the Undo detail (#285).
    var value: String {
        switch section {
        case .goal:
            ([profile.goal.config.label,
              profile.customSplit ? "Custom split" : profile.split.map(\.title)] as [String?])
                .compactMap { $0 }.joined(separator: " · ")
        case .week:
            ([profile.experience.rawValue.capitalized,
             profile.maxSessionMinutes.map { "max \($0) min" },
             profile.climbs ? "climbing \(profile.climbingDays.isEmpty ? profile.climbingDaysPerWeek : profile.climbingDays.count)× / week" : nil] as [String?])
                .compactMap { $0 }.joined(separator: " · ")
        case .time: WorkoutTimeOfDay(profile.workoutTime).summary
        case .variety: profile.planVariety.title
        case .style: "\(profile.rest.label) · \(profile.group.label)"
        case .flow: (profile.sessionFlow ?? SessionFlow()).summary(profile)
        case .method: profile.trainingMethod.label
        case .gym: gymName
        }
    }

    private var big: (String, String) {
        switch section {
        case .goal: ("\(Generator.sessionMinutes(profile))′", "PER SESSION")
        case .week: (String(format: "%.1fh", Double(Generator.sessionMinutes(profile) * profile.sessionsPerWeek) / 60), "PER WEEK")
        case .time: profile.workoutTime.map { (WorkoutTimeOfDay.clock($0), "USUALLY") } ?? ("–", "NOT SET")
        case .variety: profile.planVariety.count
        case .style: (profile.rest.range.value, profile.rest.range.unit)
        case .flow:
            ("\(Generator.flowMinutes(profile, focus: Generator.referenceFocus(profile), minutes: Generator.sessionMinutes(profile), flow: profile.sessionFlow).count)", "BLOCKS")
        case .method: (profile.trainingMethod.big.value, profile.trainingMethod.big.unit)
        case .gym: ("\(profile.equipment.count)", "ITEMS")
        }
    }

    private var gradient: LinearGradient {
        switch section {
        case .goal: profile.goal.gradient
        case .week: WorkoutEngine.Category.cardio.gradient
        case .time: WorkoutTimeOfDay(profile.workoutTime).gradient
        case .variety: profile.planVariety.gradient
        case .style: profile.rest.gradient
        case .flow: WorkoutEngine.Category.warmup.gradient
        case .method: profile.trainingMethod.gradient
        case .gym: WorkoutEngine.Category.strength.gradient
        }
    }
}

/// Community → Your gym: same editor as Training profile → Your gym.
struct CommunityGymCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let p = model.profile {
            NavigationLink { ProfileSectionView(section: .gym) } label: { ProfileSectionCard(section: .gym, profile: p) }
                .buttonStyle(.plain)
        }
    }
}
