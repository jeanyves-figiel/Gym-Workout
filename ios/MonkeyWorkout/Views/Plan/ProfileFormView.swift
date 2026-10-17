import MapKit
import SwiftUI
import WorkoutEngine

/// Training profile editor: goal tiles with their recommended week, visual day pickers, an "I climb" switch
/// for climbing days, and a gym picker with map search. Onboarding shows every section in one guided form;
/// the Training profile hub (#99) opens one `section` at a time.
struct ProfileFormView: View {
    let onSave: (Profile) -> Void
    /// Gym or equipment changed (#271): Your gym keeps each edit at once, so nothing is lost without SAVE.
    var onGymChange: ((Profile) -> Void)?
    /// Only this section (hub / Community entry); nil = full onboarding form.
    private let section: ProfileSection?
    @State private var p: Profile
    /// The profile as the section opened, for Undo (#285).
    @State private var start: Profile
    @State private var closeGuard = CloseGuard()
    @Environment(HealthManager.self) private var health
    @Environment(AppModel.self) private var model
    /// Body figure for muscle maps, asked once in onboarding (#110); changed later in Settings → Body & Health.
    @State private var figure: BodyFigure = .male
    private let isNew: Bool
    /// Section to scroll to on appear (demo screenshots).
    private let scrollTo: String?

    /// `restoring`: the section's values brought back by Undo (#285).
    init(initial: Profile?, section: ProfileSection? = nil, scrollTo: String? = nil, onGymChange: ((Profile) -> Void)? = nil,
         restoring: Profile? = nil, onSave: @escaping (Profile) -> Void) {
        self.onSave = onSave
        self.onGymChange = onGymChange
        self.section = section
        self.scrollTo = scrollTo
        isNew = initial == nil
        var start = initial ?? Profile()
        if initial == nil {
            start.applyGoal(start.goal)
            start.climbs = false
        }
        _start = State(initialValue: start)
        // Gym and equipment saved themselves already (#271): keep the current ones.
        var shown = restoring ?? start
        shown.gym = start.gym
        shown.equipment = start.equipment
        shown.gymLayout = start.gymLayout
        _p = State(initialValue: shown)
    }

    private var minutes: Int { Generator.sessionMinutes(p) }

    /// Picking climbing weekdays keeps the climbing days count in sync with them.
    private var climbingDays: Binding<[Int]> {
        Binding(
            get: { p.climbingDays },
            set: { days in
                p.climbingWeekdays = days.isEmpty ? nil : days
                if days.isEmpty {
                    p.climbingDaysPerWeek = min(max(p.climbingDaysPerWeek, 1), 4)
                } else {
                    p.syncClimbingDays()
                }
            })
    }

    private var gymDays: Binding<[Int]> {
        Binding(get: { p.gymDays }, set: { days in p.gymWeekdays = days.isEmpty ? nil : days })
    }

    private var scheduleHint: String {
        var lines: [String] = []
        if p.climbs && !p.climbingDays.isEmpty {
            lines.append("Sessions are placed around your climbing days: no heavy pulling, grip work or jumps the day before you climb.")
        }
        let gym = p.gymDays.count
        if gym > 0 && gym < p.sessionsPerWeek {
            lines.append("\(gym) gym day\(gym == 1 ? "" : "s") picked for \(p.sessionsPerWeek) sessions — the rest go on the best free days.")
        }
        if lines.isEmpty {
            lines.append("Optional: pick your days to get each session on a weekday.")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let section {
                        content(section)
                    } else {
                        content(.goal)
                        Text("Your week").eyebrow().padding(.top, 14)
                        content(.week)
                        Text("Week to week").eyebrow().padding(.top, 14).id("variety")
                        content(.variety)
                        content(.style).id("style")
                        Text("Session flow").eyebrow().padding(.top, 14).id("flow")
                        content(.flow)
                        Text("Training method").eyebrow().padding(.top, 14).id("method")
                        content(.method)
                        Text("Your gym").eyebrow().padding(.top, 14)
                        content(.gym)

                        if isNew {
                            Text("Your body figure").eyebrow().padding(.top, 14).id("figure")
                            Text("The figure drawn on your muscle maps. Change it any time in Settings → Body & Health.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                            BodyFigurePicker(selection: $figure)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, section == nil ? 0 : 8)
                .padding(.bottom, 24)
            }
            .readableWidth()
            .onAppear { if let scrollTo { proxy.scrollTo(scrollTo, anchor: .top) } }
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button {
                closeGuard.done()
                onSave(p)
                if isNew { model.setBodyFigure(figure) }
            } label: {
                Text(section == nil ? "GENERATE PLAN" : "SAVE")
            }
            .buttonStyle(LimeButtonStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .readableColumn()
            .background(Theme.bg.opacity(0.92).ignoresSafeArea())
        }
        .onChange(of: p.equipment) { onGymChange?(p) }
        .onChange(of: p.gym) { onGymChange?(p) }
        .animation(.spring(duration: 0.3), value: p.goal)
        .animation(.spring(duration: 0.3), value: p.climbs)
        .onAppear {
            if isNew { figure = model.body.figure ?? BodyMetrics.suggestedFigure(sex: health.snapshot.sex ?? model.body.sex) }
            // New profile: climbing on when Apple Health shows climbing workouts.
            if isNew, !p.climbs, let perWeek = health.snapshot.climbingPerWeek4w, perWeek >= 0.5 {
                p.climbingDaysPerWeek = min(4, max(1, Int(perWeek.rounded())))
            }
        }
        .undoableClose(closeGuard, offer: undoOffer)
    }

    /// Undo bar when a hub section was changed (#285); gym and equipment save themselves, onboarding never offers.
    private var undoOffer: UndoOffer? {
        guard let section, !isNew else { return nil }
        var edited = p
        edited.gym = start.gym
        edited.equipment = start.equipment
        edited.gymLayout = start.gymLayout
        guard edited != start else { return nil }
        let kept = p
        return UndoOffer(title: "\(section.title) closed", detail: ProfileSectionCard(section: section, profile: kept).value, symbol: "slider.horizontal.3",
                         colors: WorkoutEngine.Category.strength.colors) {
            AnyView(UndoReopenedPush { ProfileSectionView(section: section, restoring: kept) })
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func content(_ s: ProfileSection) -> some View {
        switch s {
        case .goal:
            Text("Pick a goal, then how your week splits your muscles.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            goals
        case .week:
            summary
            week
        case .time:
            WorkoutTimeSection(profile: $p)
        case .variety:
            variety
        case .style:
            TrainingStyleSection(profile: $p)
        case .flow:
            SessionFlowSection(profile: $p)
        case .method:
            TrainingMethodSection(profile: $p)
        case .gym:
            GymPicker(profile: $p)
        }
    }

    private var goals: some View {
        VStack(spacing: 12) {
            ForEach(Goal.allCases) { g in
                GoalCard(goal: g, minutes: p.recommendedMinutes(for: g), selected: p.goal == g) {
                    if p.goal != g { p.applyGoal(g) }
                }
                // How the week alternates muscles, right under the picked goal (#200).
                if p.goal == g {
                    SplitFocusPanel(profile: $p)
                        .id("split")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var week: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Gym sessions / week")
                HStack(spacing: 8) {
                    ForEach(2...6, id: \.self) { n in
                        NumberPill(
                            value: n, selected: p.sessionsPerWeek == n, fill: p.goal.gradient,
                            recommended: n == p.goal.recommendedSessions, inRange: p.goal.sessionRange.contains(n)
                        ) {
                            // Per-day picks (#200) were for the old week size.
                            if p.sessionsPerWeek != n { p.splitDays = nil }
                            p.sessionsPerWeek = n
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Experience")
                HStack(spacing: 8) {
                    ForEach(Experience.allCases) { e in
                        Chip(title: e.rawValue.capitalized, selected: p.experience == e) { p.experience = e }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Session length")
                HStack(spacing: 8) {
                    Chip(title: "Auto", selected: p.maxSessionMinutes == nil) { p.maxSessionMinutes = nil }
                    ForEach([45, 60, 75, 90], id: \.self) { m in
                        Chip(title: "\(m)′", selected: p.maxSessionMinutes == m) { p.maxSessionMinutes = m }
                    }
                }
            }

            Toggle(isOn: $p.climbs) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.climbing")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WorkoutEngine.Category.mobility.gradient))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("I climb").font(.system(size: 15, weight: .heavy, design: .rounded))
                        Text("Gym sessions are placed around climbing").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            .tint(Theme.lime)

            if p.climbs {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("I climb on", symbol: "figure.climbing")
                    DayTiles(days: climbingDays, symbol: "figure.climbing", fill: AnyShapeStyle(WorkoutEngine.Category.mobility.gradient), ink: .white)
                    if p.climbingDays.isEmpty {
                        HStack(spacing: 8) {
                            Text("or days / week").font(.footnote).foregroundStyle(Theme.muted)
                            ForEach(1...4, id: \.self) { n in
                                Chip(title: "\(n)", selected: p.climbingDaysPerWeek == n) { p.climbingDaysPerWeek = n }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Other sports (#416, design B): planned around like climbing days.
            MySportsEditor(sports: $p.sports)

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Gym days", symbol: "dumbbell.fill", optional: true)
                DayTiles(days: gymDays, symbol: "dumbbell.fill", fill: AnyShapeStyle(WorkoutEngine.Category.strength.gradient), ink: .white)
            }

            Text(scheduleHint).font(.footnote).foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var variety: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How your plan changes across the \(Generator.mesocycleWeeks)-week cycle.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            ForEach(PlanVariety.allCases) { v in
                VarietyCard(variety: v, selected: p.planVariety == v) { p.variety = v }
            }
            if p.planVariety != .same {
                Toggle(isOn: Binding(get: { p.rotateVariations == true }, set: { p.rotateVariations = $0 ? true : nil })) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Rotate variations").font(.system(size: 15, weight: .heavy, design: .rounded))
                            Text("Accessories switch to another variation each week (e.g. machine row ↔ cable row). Main lifts stay. A swap you keep always wins.")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .tint(Theme.lime)
                .padding(.top, 4)
            }
        }
        .animation(.spring(duration: 0.3), value: p.variety)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            bigStat("\(minutes)′", "per session")
            bigStat("\(p.sessionsPerWeek)×", "gym / week")
            bigStat(String(format: "%.1fh", Double(minutes * p.sessionsPerWeek) / 60), "per week")
        }
        .foregroundStyle(.white)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(p.goal.gradient))
    }

    private func bigStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(30)).monospacedDigit()
            Text(label).font(Theme.label(11)).tracking(1.4).textCase(.uppercase).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private func fieldLabel(_ title: String, symbol: String? = nil, optional: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
            if optional { Text("· optional").foregroundStyle(Theme.muted) }
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
    }
}

// MARK: - Goal

extension Goal {
    var symbol: String {
        switch self {
        case .balanced: "figure.mixed.cardio"
        case .build: "dumbbell.fill"
        case .strength: "figure.strengthtraining.traditional"
        case .climbing: "figure.climbing"
        case .endurance: "heart.fill"
        case .athletic: "bolt.fill"
        }
    }

    var gradient: LinearGradient {
        let c: WorkoutEngine.Category = switch self {
        case .balanced: .strength
        case .build: .warmup
        case .strength: .power
        case .climbing: .mobility
        case .endurance: .cardio
        case .athletic: .stretch
        }
        return c.gradient
    }
}

/// Vivid gradient goal card (Explore style): icon tile, heavy title, big recommended frequency.
/// The picked goal expands with its training mix; the others dim.
private struct GoalCard: View {
    let goal: Goal
    let minutes: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: goal.symbol)
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.22)))
                        .overlay(alignment: .topTrailing) {
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.ink, Theme.lime)
                                    .offset(x: 7, y: -7)
                            }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goal.config.label).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.75)
                        Text("~\(minutes) min · \(goal.sessionRange.lowerBound)–\(goal.sessionRange.upperBound) / week")
                            .font(.footnote.weight(.semibold)).opacity(0.85)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(goal.recommendedSessions)×").font(Theme.display(28))
                        Text("WEEK").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                    }
                }
                if selected {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(goal.config.blurb).font(.footnote.weight(.medium)).opacity(0.9)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        MixBar(goal: goal)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(goal.gradient))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white, lineWidth: selected ? 3 : 0))
            .opacity(selected ? 1 : 0.55)
            .saturation(selected ? 1 : 0.7)
            .shadow(color: .black.opacity(selected ? 0.35 : 0), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(goal.config.label), \(goal.recommendedSessions) sessions a week, about \(minutes) minutes")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Power / strength / mobility / cardio split of a goal, drawn on its gradient card.
private struct MixBar: View {
    let goal: Goal

    private var parts: [(String, Double)] {
        let s = goal.mixShares
        return [("Power", s.power), ("Strength", s.strength), ("Mobility", s.mobility), ("Cardio", s.cardio)]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(parts, id: \.0) { title, share in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int((share * 100).rounded()))%").font(Theme.display(17))
                    Capsule().fill(.white.opacity(0.25)).frame(height: 6)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in Capsule().fill(.white).frame(width: geo.size.width * min(1, share / 0.7)) }
                        }
                        .clipShape(Capsule())
                    Text(title.uppercased()).font(Theme.label(9)).tracking(1).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Variety

extension PlanVariety {
    var title: String {
        switch self {
        case .same: "Same every week"
        case .fresh: "Fresh each week"
        case .rotate: "Rotate muscle focus"
        }
    }

    var subtitle: String {
        switch self {
        case .same: "Same exercises per day · load goes up"
        case .fresh: "Main lifts stay · accessories change"
        case .rotate: "Day order and lead lift rotate weekly"
        }
    }

    var blurb: String {
        switch self {
        case .same: "Each day repeats its exercises all cycle, so every session is a chance to beat last week. Only sets and effort change with the week."
        case .fresh: "Your main lift per day stays for clean progression; accessories, warm-up, mobility and cardio change every week to keep it fresh."
        case .rotate: "Each week the days shift and a different lift leads each session, so muscles get a new emphasis. Weekly volume per muscle stays the same."
        }
    }

    var symbol: String {
        switch self {
        case .same: "repeat"
        case .fresh: "shuffle"
        case .rotate: "arrow.triangle.2.circlepath"
        }
    }

    /// Big number on the card: distinct weekly layouts across the cycle.
    var count: (String, String) {
        switch self {
        case .same: ("1", "PLAN")
        case .fresh: ("\(Generator.mesocycleWeeks)", "VARIANTS")
        case .rotate: ("\(Generator.mesocycleWeeks)", "FOCUSES")
        }
    }

    var gradient: LinearGradient {
        let c: WorkoutEngine.Category = switch self {
        case .same: .cardio
        case .fresh: .warmup
        case .rotate: .power
        }
        return c.gradient
    }
}

/// Week-to-week choice as a vivid Explore-style card; the picked one expands with its explanation.
private struct VarietyCard: View {
    let variety: PlanVariety
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: variety.symbol)
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.22)))
                        .overlay(alignment: .topTrailing) {
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.ink, Theme.lime)
                                    .offset(x: 7, y: -7)
                            }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(variety.title).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.75)
                        Text(variety.subtitle).font(.footnote.weight(.semibold)).opacity(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(variety.count.0).font(Theme.display(28))
                        Text(variety.count.1).font(Theme.label(9)).tracking(1.2).opacity(0.8)
                    }
                }
                if selected {
                    Text(variety.blurb).font(.footnote.weight(.medium)).opacity(0.92)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(variety.gradient))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white, lineWidth: selected ? 3 : 0))
            .opacity(selected ? 1 : 0.55)
            .saturation(selected ? 1 : 0.7)
            .shadow(color: .black.opacity(selected ? 0.35 : 0), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(variety.title). \(variety.subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Controls

private struct NumberPill: View {
    let value: Int
    let selected: Bool
    let fill: LinearGradient
    let recommended: Bool
    let inRange: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(value)")
                .font(Theme.display(24))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white.opacity(selected || inRange ? 1 : 0.45))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? AnyShapeStyle(fill) : AnyShapeStyle(Theme.cardStrong)))
                .overlay(alignment: .top) {
                    if recommended {
                        Text("REC")
                            .font(Theme.label(8))
                            .tracking(1)
                            .foregroundStyle(Theme.lime)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.bg))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.lime))
                            .offset(y: -7)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) sessions\(recommended ? ", recommended" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(selected ? Theme.ink : .white)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Seven tall Monday-first day tiles; picked days are filled and show an icon.
struct DayTiles: View {
    @Binding var days: [Int]
    let symbol: String
    let fill: AnyShapeStyle
    let ink: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WeekSchedule.weekdays, id: \.self) { d in
                let on = days.contains(d)
                Button {
                    if on { days.removeAll { $0 == d } } else { days = (days + [d]).sorted() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .bold))
                            .opacity(on ? 1 : 0)
                        Text(WeekSchedule.initial(d)).font(Theme.label(14))
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(on ? ink : Color.white.opacity(0.8))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? fill : AnyShapeStyle(Theme.cardStrong)))
                    .scaleEffect(on ? 1 : 0.96)
                    .animation(.spring(duration: 0.25), value: on)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WeekSchedule.name(d))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - Gym

private struct GymPicker: View {
    @Binding var profile: Profile
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [GymRef] = []
    @State private var searching = false
    @State private var showEquipment = false
    /// "Add a gym" choices open (#273), and the search field under them.
    #if DEBUG
    @State private var adding = Demo.screen == "profile-gym-add"
    #else
    @State private var adding = false
    #endif
    @State private var searchingByName = false
    @FocusState private var searchFocused: Bool
    /// "Set up this gym in a few swipes" on the equipment page (#180): opens once that page has closed.
    @State private var setupAfterEquipment = false
    /// Map of gyms around you (#165), same finder as for trips.
    @State private var findingNearby = false
    @State private var nearbyPick: GymRef?
    /// New gym setup (#162): a searched place, or `custom` for one without a map place.
    @State private var settingUp: SetupTarget?

    struct SetupTarget: Identifiable {
        let ref: GymRef?
        var id: String { ref?.id ?? "custom" }

        /// A scoped gym's full inventory, one tap away (#180).
        var preset: GymSetupPreset? {
            ref?.scoped.map { GymSetupPreset(title: "Full inventory", line: $0.name, equipment: $0.equipment) }
        }
    }

    private var selectedId: String { selectedRef.id }

    private var selectedRef: GymRef { profile.gym ?? Gym.puls5.ref }

    /// Gyms to switch to in one tap (#162, #180): your home gym while another one is picked, then your saved gyms.
    private var others: [SavedGym] {
        var list = model.savedGyms.filter { $0.id != selectedId }
        let home = model.homeGym
        if home.id != selectedId, !list.contains(where: { $0.id == home.id }) { list.insert(home, at: 0) }
        return list
    }

    /// Scoped gyms you haven't used yet, suggested under the search field.
    private var suggested: [Gym] { Gym.scoped.filter { g in g.id != selectedId && !others.contains { $0.id == g.id } } }

    /// Items of a scoped gym's full inventory that aren't in your list (e.g. added to the catalog after you picked it).
    private var missing: [Equipment] {
        selectedRef.scoped?.equipment.filter { !profile.equipment.contains($0) } ?? []
    }

    private var selectedSaved: SavedGym? { model.savedGyms.first { $0.id == selectedId } }

    private var note: String { (profile.gym?.scoped ?? (profile.gym == nil ? Gym.puls5 : nil))?.note ?? Gym.searchedNote }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GymCard(name: selectedRef.name,
                    location: selectedRef.address.isEmpty ? (selectedSaved?.kind?.label ?? "Your gym") : selectedRef.address,
                    symbol: selectedSaved?.kind?.symbol ?? "building.2.fill", count: profile.equipment.count, selected: true) {
                showEquipment = true
            }

            Button { showEquipment = true } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled").foregroundStyle(Theme.lime)
                    Text("Equipment").bold()
                    Spacer()
                    Text("\(profile.equipment.count) items").foregroundStyle(Theme.lime).bold()
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(.white)
                .card(padding: 14)
            }
            .buttonStyle(.plain)

            if !missing.isEmpty { missingCard }

            Text("Your plan is built for this gym. Switching keeps your other gyms below, each with its own list. Trips and holidays go in the calendar.")
                .font(.footnote).foregroundStyle(Theme.muted)

            if !others.isEmpty {
                Text("YOUR OTHER GYMS · TAP TO SWITCH").font(Theme.label(12)).tracking(1).foregroundStyle(Theme.muted).padding(.top, 4)
                ForEach(others) { g in SavedGymRow(gym: g) { use(g) } }
            }

            // One way in to another gym (#273): near me, search by name, or home / hotel set up in swipes.
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    adding.toggle()
                    if !adding { searchingByName = false; query = "" }
                }
            } label: {
                Label(adding ? "Close" : "Add a gym", systemImage: adding ? "xmark" : "plus")
                    .font(Theme.label(14)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if adding {
                VStack(spacing: 8) {
                    addChoice("location.magnifyingglass", "Near me", "Gyms around you on the map",
                              WorkoutEngine.Category.strength.gradient) { findingNearby = true }
                    addChoice("magnifyingglass", "Search by name", "Any gym on the map",
                              WorkoutEngine.Category.cardio.gradient) {
                        withAnimation(.spring(duration: 0.3)) { searchingByName = true }
                        searchFocused = true
                    }
                    addChoice("house.fill", "Home or hotel", "No map place · set up in a few swipes",
                              WorkoutEngine.Category.power.gradient) { settingUp = SetupTarget(ref: nil) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if adding && searchingByName {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("Gym name or address", text: $query)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($searchFocused)
                        if searching { ProgressView().controlSize(.small) }
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                    .padding(.bottom, 6)

                    if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                        if results.isEmpty && !searching {
                            Text("No gyms found").font(.footnote).foregroundStyle(Theme.muted).padding(.vertical, 12)
                        }
                        ForEach(results) { g in row(g, scoped: g.scoped != nil) }
                    } else {
                        ForEach(suggested) { g in row(g.ref, scoped: true) }
                    }
                }
                .card(padding: 12)
            }

            Text(note).font(.footnote).foregroundStyle(Theme.muted)
        }
        .sheet(isPresented: $showEquipment, onDismiss: {
            // Zones (#274) are kept as soon as the page closes, like the list.
            if selectedId == model.homeGym.id { model.setGymLayout(profile.gymLayout) }
            if setupAfterEquipment {
                setupAfterEquipment = false
                settingUp = SetupTarget(ref: selectedRef)
            }
        }) {
            EquipmentSheet(equipment: $profile.equipment, layout: $profile.gymLayout) { setupAfterEquipment = true }
        }
        .sheet(isPresented: $findingNearby, onDismiss: {
            // After the map closes, so an unknown gym's setup sheet can open.
            if let ref = nearbyPick { nearbyPick = nil; select(ref) }
        }) {
            GymFinderView { ref in nearbyPick = ref }
        }
        .sheet(item: $settingUp) { t in
            GymSetupView(ref: t.ref, actionTitle: "USE THIS GYM", preset: t.preset) { g in
                model.saveGym(g)
                profile.gym = g.ref
                profile.equipment = g.equipment
                profile.gymLayout = model.savedGyms.first { $0.id == g.id }?.layout
            }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            let found = await GymSearch.search(q)
            searching = false
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    /// One "Add a gym" choice: gradient icon tile, title and line (#273).
    private func addChoice(_ symbol: String, _ title: String, _ line: String, _ fill: LinearGradient,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(line).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(.white)
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }

    /// Full-inventory items missing from your list, so the two counts (inventory vs your list) are explained.
    private var missingCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(missing.count) item\(missing.count == 1 ? "" : "s") of the full inventory \(missing.count == 1 ? "is" : "are") off")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(missing.prefix(3).map(\.label).joined(separator: ", ") + (missing.count > 3 ? "…" : ""))
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button {
                profile.equipment = Equipment.allCases.filter { profile.equipment.contains($0) || missing.contains($0) }
            } label: {
                Text("ADD ALL").font(Theme.label(13)).tracking(1).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .card(padding: 12)
    }

    private func row(_ g: GymRef, scoped: Bool) -> some View {
        let on = g.id == selectedId
        return Button {
            select(g)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: scoped ? "building.2.fill" : "mappin.and.ellipse")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(scoped ? AnyShapeStyle(WorkoutEngine.Category.strength.gradient) : AnyShapeStyle(Theme.cardStrong)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(g.name).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
                        if scoped {
                            Text("SCOPED").font(Theme.label(9)).tracking(1).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.lime))
                        }
                    }
                    if !g.address.isEmpty {
                        Text(g.address).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                }
                Spacer()
                if on {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.ink, Theme.lime)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A gym you have a list for switches in one tap; a new one opens the setup (#162, #180), where a scoped gym's
    /// full inventory or what other members found there is one tap away.
    private func select(_ g: GymRef) {
        query = ""
        adding = false
        searchingByName = false
        guard g.id != selectedId else { return }
        if let saved = others.first(where: { $0.id == g.id }) { return use(saved) }
        settingUp = SetupTarget(ref: g)
    }

    private func use(_ g: SavedGym) {
        profile.gym = g.ref
        profile.equipment = g.equipment
        profile.gymLayout = g.layout
    }
}

/// The gym your plan is built for, as a vivid Explore-style card; the number is your own list. Tap for the equipment.
private struct GymCard: View {
    let name: String
    let location: String
    let symbol: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.22)))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.ink, Theme.lime)
                                .offset(x: 7, y: -7)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(location).font(.footnote.weight(.medium)).opacity(0.85).lineLimit(2)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(count)").font(Theme.display(26))
                    Text("ITEMS").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white, lineWidth: selected ? 3 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(location), \(count) items")
        .accessibilityHint("Shows the equipment")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Apple Maps search for fitness centres.
@MainActor
enum GymSearch {
    static func search(_ text: String) async -> [GymRef] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        var seen = Set<String>()
        return response.mapItems.prefix(12).compactMap { item in
            let c = item.placemark.coordinate
            let id = "map:" + String(format: "%.5f,%.5f", c.latitude, c.longitude)
            guard seen.insert(id).inserted else { return nil }
            return GymRef(id: id, name: item.name ?? "Gym", address: item.placemark.title ?? "", latitude: c.latitude, longitude: c.longitude)
        }
    }
}

/// A saved gym (#162): tap to switch to it with its own equipment.
struct SavedGymRow: View {
    let gym: SavedGym
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: gym.kind?.symbol ?? (gym.isPlace ? "mappin.and.ellipse" : "house.fill"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((gym.kind?.category ?? .strength).gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(gym.ref.name).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
                    Text([gym.kind?.label, gym.ref.address.isEmpty ? nil : gym.ref.address].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Text("\(gym.equipment.count)").font(Theme.display(18)).foregroundStyle(Theme.lime)
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.ink, Theme.lime)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(gym.ref.name), \(gym.equipment.count) items")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
