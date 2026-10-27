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

    /// Fine-tune tiles (#760).
    var shortTitle: String {
        switch self {
        case .style: "Style"
        case .flow: "Flow"
        case .method: "Method"
        default: title
        }
    }
}

/// Train → My plan (#760, design B + A's tiles from `my-plan-redesign/proposals.png`): the plan in one sentence
/// with a tappable word per setting, Mix it up (Variation merged with Week to week), Fine-tune tiles and add-on tiles.
struct TrainingProfileView: View {
    static let title = "My plan"

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var varying = false

    var body: some View {
        ScrollView {
            if let p = model.profile {
                VStack(alignment: .leading, spacing: 12) {
                    PlanSentenceCard(profile: p, locked: model.runningProgramme != nil)
                    // Training programme (#255): sets goal, split and method while it runs.
                    ProgrammeProfileCard()
                    mixItUp(p)
                    Text("FINE-TUNE").eyebrow().padding(.top, 4)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach([ProfileSection.style, .flow, .method]) { s in
                            if model.runningProgramme != nil && s.programmeLocked {
                                ProfileSectionCard(section: s, profile: p, locked: true, tile: true)
                            } else {
                                NavigationLink(value: s) { ProfileSectionCard(section: s, profile: p, tile: true) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("ADD TO YOUR PLAN").eyebrow().padding(.top, 4)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                        if model.activeProgramme == nil {
                            Button {
                                dismiss()
                                model.openExploreProgrammes()
                            } label: {
                                ExpertStatCard(symbol: "trophy.fill", title: "Programme", detail: "6 to 8 week plans with a PR test",
                                               value: "", colors: [Color(hex: 0x9B4CF0), Color(hex: 0xE65AD2)])
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens Explore → Programmes")
                        }
                        // Lift Focus (#499): peak one lift for a target.
                        LiftFocusCard()
                        // Run & cardio (#618): a race plan or Hybrid around lifting.
                        RunGoalProfileCard()
                        // HIIT (#693): HIIT days, finisher, impact.
                        HiitProfileCard()
                    }
                    .environment(\.statCardTile, true)
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
        .sheet(isPresented: $varying) {
            VariationSheet(days: Set(model.variableSessions.map(\.id)), keep: model.keptSwapUids)
        }
    }

    /// Variation (#98) and Week to week in one card: shuffle this week now, or set how much changes every week.
    private func mixItUp(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Mix it up", systemImage: "shuffle").font(Theme.display(21))
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(p.planVariety.count.0).font(Theme.display(24))
                    Text(p.planVariety.count.1).font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
            }
            Text("\(p.planVariety.title) · new exercises, same plan")
                .font(.footnote.weight(.semibold)).opacity(0.9)
            HStack(spacing: 8) {
                Button { varying = true } label: {
                    Label("Shuffle this week", systemImage: "shuffle")
                        .font(Theme.label(14)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.shuffle")
                NavigationLink(value: ProfileSection.variety) {
                    Label("Week to week", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(Theme.label(14))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xF0913A), Color(hex: 0xF04A6A)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

/// Icon after the title ("Week to week ›").
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.font(.caption.bold()) }
    }
}

/// "I train 2× a week, evenings for 70 min to build & define at Puls 5 around climbing." Each coloured word opens
/// its section; goal is locked while a programme runs.
private struct PlanSentenceCard: View {
    let profile: Profile
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case let .text(t): Text(t).font(Theme.display(22)).padding(.vertical, 4)
                    case let .word(t, s): word(t, s)
                    }
                }
            }
            Text("Tap a coloured word to change it").font(.footnote.weight(.semibold)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x3F6CF5), Color(hex: 0x8A4CF0)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityIdentifier("plan.sentence")
    }

    private enum Part { case text(String), word(String, ProfileSection) }

    private var parts: [Part] {
        let p = profile
        let time = WorkoutTimeOfDay(p.workoutTime)
        var out: [Part] = [.text("I train"), .word("\(p.sessionsPerWeek)×", .week), .text("a week,"),
                           .word(time == .unset ? "any time" : time.label.lowercased(), .time),
                           .text("for"), .word("\(Generator.sessionMinutes(p)) min", .goal), .text("to"),
                           .word(p.goal.config.label.lowercased(), .goal), .text("at"),
                           .word(p.gym?.name ?? Gym.puls5.name, .gym)]
        if p.climbs { out += [.text("around"), .word("climbing", .week)] }
        return out
    }

    @ViewBuilder
    private func word(_ t: String, _ s: ProfileSection) -> some View {
        let card = ProfileSectionCard(section: s, profile: profile)
        let chip = Text(t).font(Theme.display(22))
            .foregroundStyle(card.light ? Theme.ink : .white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(card.gradient))
        if locked && s.programmeLocked {
            chip.opacity(0.6).accessibilityLabel("\(t), set by your programme")
        } else {
            NavigationLink(value: s) { chip }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t). \(s.title)")
                .accessibilityHint("Opens \(s.title)")
        }
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
    /// Square tile for the Fine-tune grid (#760): icon and big number on top, title and value below.
    var tile = false

    var body: some View {
        if tile { tileBody } else { rowBody }
    }

    private var tileBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: locked ? "lock.fill" : symbol)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(light ? Theme.ink.opacity(0.12) : .white.opacity(0.22)))
                Spacer(minLength: 2)
                Text(big.0).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
            Text(section.shortTitle).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.6)
            Text(value).font(.caption2.weight(.semibold)).opacity(0.88).lineLimit(2)
        }
        .foregroundStyle(light ? Theme.ink : .white)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient))
        .opacity(locked ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title): \(value)\(locked ? ", set by your programme" : "")")
    }

    private var rowBody: some View {
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
    var light: Bool {
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
        case .gym: ("\(profile.equipment.count)", "ITEMS · \(AppModel.machineCount(profile.equipment)) MACHINES") // #823
        }
    }

    var gradient: LinearGradient {
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
