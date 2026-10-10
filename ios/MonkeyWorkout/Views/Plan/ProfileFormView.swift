import MapKit
import SwiftUI
import WorkoutEngine

/// Training profile editor (onboarding + Train → edit): goal tiles with their recommended week,
/// visual day pickers, an "I climb" switch for climbing days, and a gym picker with map search.
struct ProfileFormView: View {
    let onSave: (Profile) -> Void
    @State private var p: Profile
    @State private var showEquipment = false
    @Environment(HealthManager.self) private var health
    private let isNew: Bool
    /// Section to scroll to on appear (demo screenshots).
    private let scrollTo: String?

    init(initial: Profile?, scrollTo: String? = nil, onSave: @escaping (Profile) -> Void) {
        self.onSave = onSave
        self.scrollTo = scrollTo
        isNew = initial == nil
        var start = initial ?? Profile()
        if initial == nil {
            start.applyGoal(start.goal)
            start.climbs = false
        }
        _p = State(initialValue: start)
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
                    Text("Pick a goal. Your week is sized around it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)

                    goals

                    Text("Your week").eyebrow().padding(.top, 14)
                    week
                    summary

                    Text("Week to week").eyebrow().padding(.top, 14).id("variety")
                    variety

                    TrainingStyleSection(profile: $p).id("style")

                    Text("Your gym").eyebrow().padding(.top, 14)
                    GymPicker(profile: $p, showEquipment: $showEquipment)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .onAppear { if let scrollTo { proxy.scrollTo(scrollTo, anchor: .top) } }
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button {
                var out = p
                onSave(out)
            } label: {
                Text("GENERATE PLAN")
            }
            .buttonStyle(LimeButtonStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.bg.opacity(0.92).ignoresSafeArea())
        }
        .sheet(isPresented: $showEquipment) {
            EquipmentSheet(equipment: $p.equipment)
        }
        .animation(.spring(duration: 0.3), value: p.goal)
        .animation(.spring(duration: 0.3), value: p.climbs)
        .onAppear {
            // New profile: climbing on when Apple Health shows climbing workouts.
            if isNew, !p.climbs, let perWeek = health.snapshot.climbingPerWeek4w, perWeek >= 0.5 {
                p.climbingDaysPerWeek = min(4, max(1, Int(perWeek.rounded())))
            }
        }
    }

    // MARK: Sections

    private var goals: some View {
        VStack(spacing: 12) {
            ForEach(Goal.allCases) { g in
                GoalCard(goal: g, minutes: p.recommendedMinutes(for: g), selected: p.goal == g) {
                    if p.goal != g { p.applyGoal(g) }
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
                        ) { p.sessionsPerWeek = n }
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
private struct DayTiles: View {
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
    @Binding var showEquipment: Bool
    @State private var query = ""
    @State private var results: [GymRef] = []
    @State private var searching = false

    private var selectedId: String { profile.gym?.id ?? Gym.puls5.id }

    private var note: String { (profile.gym?.scoped ?? (profile.gym == nil ? Gym.puls5 : nil))?.note ?? Gym.searchedNote }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Gym.scoped) { gym in ScopedGymCard(gym: gym, selected: gym.id == selectedId) { select(gym.ref) } }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search another gym", text: $query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
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
                    ForEach(results) { g in row(g, scoped: false) }
                } else if let g = profile.gym, g.scoped == nil {
                    row(g, scoped: false)
                }
            }
            .card(padding: 12)

            Button { showEquipment = true } label: {
                HStack {
                    Image(systemName: "dumbbell.fill").foregroundStyle(Theme.lime)
                    Text("Equipment").bold()
                    Spacer()
                    Text("\(profile.equipment.count) items").foregroundStyle(Theme.lime).bold()
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(.white)
                .card(padding: 14)
            }
            .buttonStyle(.plain)

            Text(note).font(.footnote).foregroundStyle(Theme.muted)
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

    private func select(_ g: GymRef) {
        if let gym = g.scoped {
            profile.gym = gym.ref
            profile.equipment = gym.equipment
        } else {
            // Unknown inventory: start from a full commercial gym; the user unticks what's missing.
            if profile.gym?.id != g.id { profile.equipment = Equipment.allCases }
            profile.gym = g
        }
        query = ""
    }
}

/// Scoped gym (known inventory) as a vivid Explore-style card.
private struct ScopedGymCard: View {
    let gym: Gym
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "building.2.fill")
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
                    Text(gym.name).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(gym.location).font(.footnote.weight(.medium)).opacity(0.85).lineLimit(2)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(gym.equipment.count)").font(Theme.display(26))
                    Text("ITEMS").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white, lineWidth: selected ? 3 : 0))
            .opacity(selected ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(gym.name), \(gym.location)")
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

struct EquipmentSheet: View {
    @Binding var equipment: [Equipment]
    @Environment(\.dismiss) private var dismiss

    init(equipment: Binding<[Equipment]>) {
        _equipment = equipment
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Equipment.allCases) { e in
                        Toggle(e.label, isOn: Binding(
                            get: { equipment.contains(e) },
                            set: { on in
                                if on { equipment.append(e) } else { equipment.removeAll { $0 == e } }
                            }))
                    }
                } footer: {
                    Text("Untick anything your gym doesn't have.")
                }
            }
            .themedForm()
            .navigationTitle("Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
