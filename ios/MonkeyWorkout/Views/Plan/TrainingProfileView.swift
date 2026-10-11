import SwiftUI
import WorkoutEngine

/// One part of the training profile, editable on its own screen (#99).
enum ProfileSection: String, CaseIterable, Identifiable, Hashable {
    case goal, week, variety, style, gym
    var id: String { rawValue }

    var title: String {
        switch self {
        case .goal: "Goal"
        case .week: "Your week"
        case .variety: "Week to week"
        case .style: "Training style"
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
                    ForEach(ProfileSection.allCases) { s in
                        NavigationLink(value: s) { ProfileSectionCard(section: s, profile: p) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationDestination(for: ProfileSection.self) { ProfileSectionView(section: $0) }
    }
}

/// One section's editor; saving re-plans the current week and goes back. Also opened from Community (Your gym).
struct ProfileSectionView: View {
    let section: ProfileSection
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProfileFormView(initial: model.profile, section: section) { p in
            model.updateProfile(p)
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.75)
                Text(value).font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(big.0).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.5)
                Text(big.1).font(Theme.label(9)).tracking(1.2).opacity(0.8).lineLimit(1)
            }
            .fixedSize()
            .layoutPriority(2)
            Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title): \(value)")
    }

    private var gymName: String { profile.gym?.name ?? Gym.puls5.name }

    private var symbol: String {
        switch section {
        case .goal: profile.goal.symbol
        case .week: "calendar"
        case .variety: profile.planVariety.symbol
        case .style: profile.rest.symbol
        case .gym: "building.2.fill"
        }
    }

    private var value: String {
        switch section {
        case .goal: profile.goal.config.label
        case .week:
            ([profile.experience.rawValue.capitalized,
             profile.maxSessionMinutes.map { "max \($0) min" },
             profile.climbs ? "climbing \(profile.climbingDays.isEmpty ? profile.climbingDaysPerWeek : profile.climbingDays.count)× / week" : nil] as [String?])
                .compactMap { $0 }.joined(separator: " · ")
        case .variety: profile.planVariety.title
        case .style: "\(profile.rest.label) · \(profile.group.label)"
        case .gym: gymName
        }
    }

    private var big: (String, String) {
        switch section {
        case .goal: ("\(Generator.sessionMinutes(profile))′", "PER SESSION")
        case .week: (String(format: "%.1fh", Double(Generator.sessionMinutes(profile) * profile.sessionsPerWeek) / 60), "PER WEEK")
        case .variety: profile.planVariety.count
        case .style: (profile.rest.range.value, profile.rest.range.unit)
        case .gym: ("\(profile.equipment.count)", "ITEMS")
        }
    }

    private var gradient: LinearGradient {
        switch section {
        case .goal: profile.goal.gradient
        case .week: WorkoutEngine.Category.cardio.gradient
        case .variety: profile.planVariety.gradient
        case .style: profile.rest.gradient
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
