import LiftSensor
import SwiftUI
import WorkoutEngine

// MARK: - Training programmes (#255)

/// Pushes a programme's page.
struct ProgrammeRoute: Hashable, Identifiable {
    let id: String
}

extension ProgrammePhaseKind {
    /// Same colours as the week card's phases; the test week is gold.
    var colors: [Color] {
        switch self {
        case .base: WorkoutEngine.Category.cardio.colors
        case .build: WorkoutEngine.Category.strength.colors
        case .peak: WorkoutEngine.Category.power.colors
        case .ease: WorkoutEngine.Category.stretch.colors
        case .test: [Color(red: 1, green: 0.72, blue: 0), Color(red: 1, green: 0.31, blue: 0.63)]
        }
    }
}

extension Programme {
    var gradient: LinearGradient {
        isHyrox ? LinearGradient(colors: [Color(hex: 0xFFD400), Color(hex: 0xFF7A00), Color(hex: 0xFF2D55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : snowRide == nil ? palette.gradient
            : LinearGradient(colors: [Color(hex: 0x00C6FF), Color(hex: 0x2B5CFF), Color(hex: 0x8A2BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Explore order: the season ones, Snow ready (#428) and Hyrox ready (#431), first; the rest as the catalog lists them.
    static var catalog: [Programme] {
        let season = { (p: Programme) in p.snowRide != nil || p.isHyrox }
        return all.filter(season) + all.filter { !season($0) }
    }

    /// Same programme for the library: Snow ready variants count as one.
    func sameFamily(_ id: String?) -> Bool {
        guard let id else { return false }
        return id == self.id || (snowRide != nil && Programme.find(id)?.snowRide != nil)
    }
    var plan: String { "\(weeks) weeks · \(sessionsPerWeek)× a week" }
}

/// Explore → Programmes: the running one first, the member's own (#269), then every programme as a bold card.
struct ProgrammeLibrarySection: View {
    @Environment(AppModel.self) private var model
    @State private var building = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let a = model.activeProgramme, let p = a.programme {
                Text(a.paused ? "Paused" : "Running").eyebrow()
                NavigationLink(value: ProgrammeRoute(id: p.id)) { ProgrammeCard(programme: p, week: model.programmeWeek, paused: a.paused) }
                    .buttonStyle(.plain)
            }
            Text("My programmes").eyebrow()
            ForEach(model.myProgrammes.filter { $0.id != model.activeProgramme?.programmeId }) { p in
                NavigationLink(value: ProgrammeRoute(id: p.id)) { ProgrammeCard(programme: p) }
                    .buttonStyle(.plain)
            }
            Button { building = true } label: {
                Label("New programme", systemImage: "plus")
                    .font(Theme.label(15))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.white.opacity(0.85))
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [7, 6])))
            }
            .buttonStyle(.plain)
            // Sport season blocks (#620 A): pick the sport, then its season's first day on the programme page.
            SeasonPickerCard()
            // Calisthenics skill tree (#621).
            SkillTreeCard()
            Text("Programmes").eyebrow()
            ForEach(Programme.catalog.filter { !$0.sameFamily(model.activeProgramme?.programmeId) }) { p in
                NavigationLink(value: ProgrammeRoute(id: p.id)) { ProgrammeCard(programme: p) }
                    .buttonStyle(.plain)
            }
            Text("A programme runs your plan for a few weeks toward one goal: phases, signature workouts and a test at the end. Your days, gym and time still shape every week, and your own plan comes back when you pause or finish. Build your own with New programme, or tap Make it mine on any programme.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .sheet(isPresented: $building) { ProgrammeBuilderView() }
    }
}

/// A programme page as a sheet, for places without a navigation stack of their own (Coach tip, My sports).
struct ProgrammeSheet: View {
    let id: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Programme.find(id).map { ProgrammeDetailView(programme: $0) }
                .toolbar { CloseToolbarItem { dismiss() } }
        }
    }
}

/// Explore-style programme card: icon tile, name and tagline, big week count (or the current week when running).
struct ProgrammeCard: View {
    let programme: Programme
    var week: Int?
    var paused = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: programme.symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(programme.name).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.7)
                Text(week == nil ? programme.tagline : paused ? "Paused · tap to resume" : programme.phase(week: week!).kind.label + " · " + programme.tagline)
                    .font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(week.map { "\($0)/\(programme.weeks)" } ?? "\(programme.weeks)").font(Theme.display(28)).monospacedDigit()
                Text(week == nil ? "WEEKS" : "WEEK").font(Theme.label(9)).tracking(1.2).opacity(0.8)
            }
            .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(programme.gradient))
        .accessibilityElement(children: .combine)
    }
}

/// Phases as one coloured bar, each segment as wide as its weeks.
struct ProgrammePhaseStrip: View {
    let programme: Programme
    /// Outlines the segment holding this programme week.
    var week: Int?

    var body: some View {
        GeometryReader { g in
            let gap: CGFloat = 3
            let free = g.size.width - gap * CGFloat(programme.phases.count - 1)
            HStack(spacing: gap) {
                ForEach(Array(programme.phaseStarts.enumerated()), id: \.offset) { _, item in
                    segment(item.phase, from: item.week)
                        .frame(width: max(0, free * CGFloat(item.phase.weeks) / CGFloat(programme.weeks)))
                }
            }
        }
        .frame(height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(programme.phases.map { "\($0.kind.label) \($0.weeks) weeks" }.joined(separator: ", "))
    }

    private func segment(_ p: ProgrammePhase, from start: Int) -> some View {
        let current = week.map { $0 >= start && $0 < start + p.weeks } ?? false
        return VStack(alignment: .leading, spacing: 1) {
            Text(p.kind.label).font(Theme.label(12))
            Text(p.weeks == 1 ? "wk \(start)" : "wk \(start)–\(start + p.weeks - 1)")
                .font(.system(size: 9, weight: .bold, design: .rounded)).opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: p.kind.colors, startPoint: .leading, endPoint: .trailing))
        .overlay { if current { Rectangle().strokeBorder(Theme.lime, lineWidth: 3) } }
    }
}

/// Programme page: phases, signature workouts, what it changes while it runs, start / pause / resume / leave.
struct ProgrammeDetailView: View {
    /// The catalog programme; `programme` is it at the member's length while it runs.
    let base: Programme
    @Environment(AppModel.self) private var model
    @State private var lengthSheet = false
    @State private var confirmLeave = false
    /// Every programme week's workouts (#268), built for the member's gym, days and focus.
    @State private var weeks: [[Session]] = []
    @State private var picked: PickedProgrammeSession?
    /// Programme open in the editor: the member's own, or a copy to make theirs (#269).
    @State private var editing: Programme?
    /// Snow ready (#428): what the member rides and their first day on snow (the length is fitted to it).
    @State private var ride: SnowRide?
    @State private var firstDay: Date?
    @AppStorage("snowNudgeSeen") private var snowSeen = 0
    /// Hyrox ready (#431): the race days the season is built around.
    @State private var races: [Date] = []
    @State private var newRace = Calendar.current.date(byAdding: .weekOfYear, value: 9, to: .now)!

    /// Demo screenshots: open the length sheet, or scroll to the workouts grid.
    private let demoLength: Bool
    private let demoGrid: Bool
    private let demoEdit: Bool

    init(programme: Programme, demoLength: Bool = false, demoGrid: Bool = false, demoEdit: Bool = false) {
        base = programme
        self.demoLength = demoLength
        self.demoGrid = demoGrid
        self.demoEdit = demoEdit
    }

    private var mine: ActiveProgramme? {
        base.sameFamily(model.activeProgramme?.programmeId) ? model.activeProgramme : nil
    }

    /// The member's own programme as last saved (#269); a catalog one as is; Snow ready as the picked ride.
    private var latest: Programme {
        if base.mine { return model.findProgramme(base.id) ?? base }
        if base.isHyrox { return Programme.hyroxSeason(races: races, now: .now).targeting(model.hyroxTarget) }
        if let r = ride ?? base.snowRide { return Programme.snowReady(r) }
        return base
    }

    /// Snow ready or a sport season block (#620) not started yet: weeks to the week before the first day.
    private var snowWeeks: Int? {
        guard mine == nil, base.snowRide != nil || base.isSeason, let firstDay else { return nil }
        return base.isSeason ? Programme.seasonWeeks(until: firstDay, now: .now) : Programme.snowWeeks(until: firstDay, now: .now)
    }

    /// At its standard length: what the length choices are built from.
    private var standard: Programme { mine?.custom ?? latest }

    private var programme: Programme { mine?.programme ?? snowWeeks.map { latest.resized(to: $0) } ?? latest }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if base.snowRide != nil, mine == nil || mine?.firstDay != nil { snowSetup }
                    if base.isSeason, mine == nil || mine?.firstDay != nil { seasonSetup }
                    if base.isHyrox { hyroxSetup }
                    ProgrammePhaseStrip(programme: programme, week: mine == nil ? nil : model.programmeWeek)
                    if mine != nil, !base.isHyrox { lengthRow }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(programme.phaseStarts.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(LinearGradient(colors: item.phase.kind.colors, startPoint: .top, endPoint: .bottom))
                                    .frame(width: 10, height: 10)
                                Text(item.phase.kind.label).font(Theme.label(14))
                                Text(item.phase.note).font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    if !weeks.isEmpty {
                        HStack {
                            Text("All workouts").eyebrow()
                            Spacer()
                            Text("\(weeks.reduce(0) { $0 + $1.count })").font(Theme.label(13)).foregroundStyle(Theme.lime)
                        }
                        .id("grid")
                        ProgrammeWorkoutGrid(programme: programme, weeks: weeks, current: mine == nil ? nil : model.programmeWeek) {
                            picked = PickedProgrammeSession(week: $0, session: $1)
                        }
                        Text(mine == nil
                             ? "Built from your gym, days and focus; the extra exercises are picked fresh each week when it runs. Tap a workout to see it."
                             : "Tap a workout to see it.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    if !programme.signatures.isEmpty {
                        Text("Signature workouts").eyebrow()
                        ForEach(programme.signatures) { SignatureCard(signature: $0, programme: programme) }
                    }
                    changes
                    if programme.hasTest {
                        Text("Finish line").eyebrow()
                        HStack(spacing: 14) {
                            Image(systemName: "trophy.fill").font(.system(size: 24, weight: .bold))
                                .frame(width: 52, height: 52)
                                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.25)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Test week").font(Theme.display(21))
                                Text(programme.lifts.isEmpty ? "Race a half Hyrox on your Watch; the report compares every split to your plan"
                                     : "PR attempts: " + programme.lifts.map { Exercise.get($0).name }.joined(separator: ", "))
                                    .font(.footnote.weight(.semibold)).opacity(0.9)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(LinearGradient(colors: ProgrammePhaseKind.test.colors, startPoint: .leading, endPoint: .trailing)))
                    }
                    actions
                    if !base.mine { makeItMine }
                }
                .padding(16)
            }
            .onChange(of: weeks.count) { if demoGrid { proxy.scrollTo("grid", anchor: .top) } }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(programme.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: programme) { weeks = previewWeeks() }
        .sheet(isPresented: $lengthSheet) {
            ProgrammeLengthSheet(programme: standard, running: mine != nil ? model.programmeWeek : nil,
                                 current: programme.weeks,
                                 replacing: mine == nil ? model.activeProgramme?.programme?.name : nil) { weeks in
                if mine == nil { model.startProgramme(latest, length: weeks) } else { model.setProgrammeLength(weeks) }
            }
        }
        .sheet(item: $picked) { ProgrammeSessionSheet(programme: programme, picked: $0) }
        .sheet(item: $editing) { prog in ProgrammeEditorView(programme: prog, isNew: !model.myProgrammes.contains { $0.id == prog.id }) }
        .toolbar {
            if base.mine {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = latest }
                }
            }
        }
        .onAppear {
            if base.isHyrox, races.isEmpty {
                races = mine?.races ?? [model.hyroxPlan?.event].compactMap { $0 }.filter { $0 > .now }
            }
            if base.snowRide != nil {
                let sports = model.profile?.sports
                ride = ride ?? SnowRide.from(sports) ?? base.snowRide
                firstDay = firstDay ?? Programme.defaultSnowDay(sports: sports, now: .now)
                snowSeen = Calendar.current.component(.year, from: .now)
            }
            if base.isSeason {
                // Saturday 8 weeks out: the standard length.
                firstDay = firstDay ?? Programme.defaultSnowDay(sports: nil, now: .now)
            }
            if demoLength { lengthSheet = true }
            if demoEdit { editing = base.copy() }
        }
        .confirmationDialog("Leave \(programme.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave programme", role: .destructive) { model.leaveProgramme() }
        } message: {
            Text("Your own plan comes back. Progress keeps what you trained.")
        }
    }

    /// Hyrox ready (#431, A + C): division, race days (one season block per race), goal pace; running, the next race.
    private var hyroxSetup: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let list = (mine?.races ?? races).sorted()
        let next = list.first { $0 >= today }
        return VStack(alignment: .leading, spacing: 10) {
            if mine == nil {
                Text("DIVISION").font(Theme.label(11)).tracking(1.2).opacity(0.85)
                HStack(spacing: 6) {
                    ForEach(HyroxDivision.Category.allCases, id: \.self) { c in
                        let on = model.hyroxDivision.category == c
                        Button {
                            var p = model.hyroxProfile
                            p.category = c.rawValue
                            model.saveHyroxProfile(p)
                        } label: {
                            Text(c.rawValue.capitalized).font(Theme.label(13))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(on ? Color(hex: 0xFFD400) : .black)
                                .background(Capsule().fill(on ? Color.black : Color.white.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Text("RACE DAYS").font(Theme.label(11)).tracking(1.2).opacity(0.85)
            if let next {
                let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: next)).day ?? 0
                Text(next.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(Theme.display(40)).lineLimit(1).minimumScaleFactor(0.6)
                Text(days == 0 ? "Race day. Go get it 🏁" : "\(days) day\(days == 1 ? "" : "s") to go").font(.footnote.weight(.semibold))
            }
            ForEach(list, id: \.self) { d in
                HStack {
                    Image(systemName: "flag.checkered").font(.caption.bold())
                    Text(d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())).font(Theme.label(14))
                    Spacer()
                    if mine == nil {
                        Button { races.removeAll { $0 == d } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove race")
                    }
                }
            }
            if mine == nil {
                HStack {
                    DatePicker("Race day", selection: $newRace, in: cal.date(byAdding: .day, value: 7, to: .now)!..., displayedComponents: .date)
                        .labelsHidden()
                    Spacer()
                    Button {
                        if !races.contains(where: { cal.isDate($0, inSameDayAs: newRace) }) { races.append(newRace) }
                    } label: {
                        Label("Add race", systemImage: "plus").font(Theme.label(13))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(Color(hex: 0xFFD400))
                            .background(Capsule().fill(Color.black))
                    }
                    .buttonStyle(.plain)
                }
                Text(model.hyroxGoalSeconds.map { "Goal \(HyroxTime.clock($0)): run, SkiErg and row targets set from it." }
                     ?? "Set a goal time in the Hyrox hub to get race-pace targets.")
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.black)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(programme.gradient))
    }

    /// Snow ready (#428, A + B): ride picker and the first day on snow; running, the countdown.
    private var snowSetup: some View {
        let cal = Calendar.current
        let day = mine?.firstDay ?? firstDay ?? .now
        let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: day)).day ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "mountain.2.fill").font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
                Text("First day on snow").font(Theme.display(20))
                Spacer(minLength: 0)
            }
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(Theme.display(44)).lineLimit(1).minimumScaleFactor(0.6)
            if mine == nil {
                Text("\(days / 7) weeks away · we fit the plan to it").font(.footnote.weight(.semibold)).opacity(0.9)
                DatePicker("First day on snow", selection: Binding(get: { firstDay ?? .now }, set: { firstDay = $0 }),
                           in: cal.date(byAdding: .day, value: 7, to: .now)!..., displayedComponents: .date)
                    .font(Theme.label(14)).tint(.white).colorScheme(.dark)
                HStack(spacing: 8) {
                    ForEach(SnowRide.allCases) { r in
                        let on = (ride ?? base.snowRide) == r
                        Button { ride = r } label: {
                            Text(r.label).font(Theme.label(14))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(on ? Color(hex: 0x2B5CFF) : .white)
                                .background(Capsule().fill(on ? Color.white : Color.white.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            } else {
                Text(days == 0 ? "Today. Have fun out there ❄️" : "\(days) day\(days == 1 ? "" : "s") to go").font(.footnote.weight(.semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Programme.snowReady(.both).gradient))
    }

    /// Sport season block (#620 A): the season's first day (the length is fitted to it); running, the countdown.
    private var seasonSetup: some View {
        let cal = Calendar.current
        let day = mine?.firstDay ?? firstDay ?? .now
        let days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: day)).day ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: base.symbol).font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
                Text("Season starts").font(Theme.display(20))
                Spacer(minLength: 0)
            }
            Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(Theme.display(44)).lineLimit(1).minimumScaleFactor(0.6)
            if mine == nil {
                Text("\(snowWeeks ?? programme.weeks) weeks · we fit the plan to it").font(.footnote.weight(.semibold)).opacity(0.9)
                DatePicker("Season starts", selection: Binding(get: { firstDay ?? .now }, set: { firstDay = $0 }),
                           in: cal.date(byAdding: .day, value: 7, to: .now)!..., displayedComponents: .date)
                    .font(Theme.label(14)).tint(.white).colorScheme(.dark)
            } else {
                Text(days == 0 ? "Today. Have a great season" : "\(days) day\(days == 1 ? "" : "s") to go").font(.footnote.weight(.semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(base.gradient))
    }

    /// Copy to edit ("Make it mine", design A of #269).
    private var makeItMine: some View {
        Button { editing = base.copy() } label: {
            Label("Make it mine", systemImage: "square.on.square")
                .font(Theme.display(16))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func previewWeeks() -> [[Session]] {
        guard let sp = model.state.synced else { return [] }
        let a = mine
        return (1...programme.weeks).map {
            programme.previewWeek($0, member: sp.profile, seed: a?.seed ?? 1, starting: a == nil).sessions
        }
    }

    static func list(_ n: [Int]) -> String {
        n.count < 2 ? n.map(String.init).joined() : n.dropLast().map(String.init).joined(separator: ", ") + " or \(n.last!)"
    }

    /// Running programme: its length, tap to change.
    private var lengthRow: some View {
        Button { lengthSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 14, weight: .bold)).frame(width: 30)
                Text("Length").font(Theme.label(14))
                Spacer(minLength: 6)
                Text("\(programme.weeks) weeks · \(standard.lengths.first { $0.weeks == programme.weeks }?.name ?? "Custom")")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                Text("Change").font(.footnote.weight(.bold)).foregroundStyle(Theme.lime)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: programme.symbol)
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mine.map { $0.paused ? "PAUSED" : "WEEK \(model.programmeWeek ?? 1) OF \(programme.weeks)" } ?? programme.plan.uppercased())
                        .font(Theme.label(11)).tracking(1.4).opacity(0.85)
                    Text(programme.name).font(Theme.display(28)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            Text(programme.summary).font(.subheadline.weight(.semibold)).opacity(0.92)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(programme.gradient))
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("While it runs").eyebrow()
            row("target", "Goal", programme.goal.config.label, locked: true)
            row("rectangle.split.3x1.fill", "Split", programme.split == .auto ? "Built for the goal" : programme.split.title, locked: true)
            row(programme.method.symbol, "Method", programme.method.label, locked: true)
            if !programme.focusMuscles.isEmpty {
                row("scope", "Focus", programme.focusMuscles.map(\.label).joined(separator: ", "), locked: true)
            }
            row("calendar", "Sessions", "\(programme.sessionsPerWeek)× a week to start, your days", locked: false)
            row("building.2.fill", "Gym and time", "Still yours", locked: false)
            Text("Your own plan is saved and comes back when you pause, leave or finish.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func row(_ symbol: String, _ title: String, _ value: String, locked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).frame(width: 30)
            Text(title).font(Theme.label(14))
            Spacer(minLength: 6)
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
            Image(systemName: locked ? "lock.fill" : "checkmark").font(.caption2.bold()).foregroundStyle(locked ? Theme.muted : Theme.lime)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    @ViewBuilder
    private var actions: some View {
        if let a = mine {
            HStack(spacing: 10) {
                if a.paused {
                    bigButton("Resume", "play.fill", fill: Theme.lime) { model.resumeProgramme() }
                } else {
                    bigButton("Pause", "pause.fill", fill: Theme.lime) { model.pauseProgramme() }
                }
                bigButton("Leave", "xmark", fill: Color.white.opacity(0.12), ink: .white) { confirmLeave = true }
            }
            Text(a.paused
                 ? "Paused at week \(model.programmeWeek ?? 1). Resume picks it up there."
                 : "Pause brings your own plan back (holiday, injury) and keeps this programme at week \(model.programmeWeek ?? 1).")
                .font(.caption).foregroundStyle(Theme.muted)
        } else if base.isHyrox {
            bigButton(model.activeProgramme == nil
                      ? (races.isEmpty ? "Start · \(programme.weeks) weeks" : "Start · \(races.count) race\(races.count == 1 ? "" : "s")")
                      : "Switch to this programme", "flag.checkered", fill: Theme.lime) {
                model.startProgramme(latest, races: races)
            }
            Text(races.isEmpty ? "No race set: a standard \(programme.weeks)-week block. Add your race days above to fit it."
                 : "Starts this week. Ends after your last race; your own plan comes back.")
                .font(.caption).foregroundStyle(Theme.muted)
        } else if let weeks = snowWeeks, let day = firstDay {
            let end = Calendar.current.date(byAdding: .day, value: -1, to: Progression.weekStart(day, Progression.calendar()))!
            bigButton(model.activeProgramme == nil ? "Start · ends \(end.formatted(.dateTime.day().month(.abbreviated)))" : "Switch to this programme",
                      "flag.checkered", fill: Theme.lime) {
                model.startProgramme(latest, length: weeks, firstDay: day)
            }
            Text((model.activeProgramme.map { "Leaves \($0.programme?.name ?? "your programme"). " } ?? "")
                 + "Starts this week, \(weeks) weeks: Base and Build stretch or shrink to fit, Peak, Test and an easy week stay.")
                .font(.caption).foregroundStyle(Theme.muted)
        } else {
            bigButton(model.activeProgramme == nil ? "Start programme" : "Switch to this programme", "flag.checkered", fill: Theme.lime) {
                lengthSheet = true
            }
            Text("Starts this week, week 1: \(programme.phases[0].kind.label). Pick \(Self.list(standard.lengths.map(\.weeks))) weeks.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func bigButton(_ title: String, _ symbol: String, fill: Color, ink: Color = Theme.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.display(17))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(ink)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}

/// A signature workout: name, the phases it runs in and its exercises with the first phase's dose.
private struct SignatureCard: View {
    let signature: ProgrammeSignature
    let programme: Programme

    var body: some View {
        let first = programme.phases.first { signature.phases.contains($0.kind) }?.kind ?? .base
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(signature.name).font(Theme.display(20))
                Spacer()
                Text("1× / WEEK").font(Theme.label(10)).tracking(1).opacity(0.85)
            }
            ForEach(signature.items, id: \.exerciseId) { it in
                let d = it.dose(first)
                HStack {
                    Text(Exercise.get(it.exerciseId).name).font(.footnote.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text("\(d.sets) × \(d.reps)").font(Theme.label(13)).monospacedDigit()
                }
            }
            Text(signature.phases.count == programme.phases.count
                 ? "Every week; heavier as the phases go."
                 : "In " + programme.phases.filter { signature.phases.contains($0.kind) }.map(\.kind.label).joined(separator: ", ")
                    + "; heavier as the phases go. Your gym lacks one? The closest exercise it has takes its place.")
                .font(.caption.weight(.medium)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(programme.gradient.opacity(0.9)))
    }
}

/// Train: the running (or paused) programme above the week card. Test week: PR attempt buttons per lift.
struct ProgrammeHeroCard: View {
    @Environment(AppModel.self) private var model
    @State private var attempt: String?

    var body: some View {
        if let a = model.activeProgramme, let p = a.programme, let week = model.programmeWeek {
            let phase = p.phase(week: week)
            NavigationLink(value: ProgrammeRoute(id: p.id)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.paused ? "PROGRAMME PAUSED · WEEK \(week) OF \(p.weeks)" : "PROGRAMME · WEEK \(week) OF \(p.weeks) · \(phase.kind.label.uppercased())")
                        .font(Theme.label(10)).tracking(1.4).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
                    Text(p.name).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(a.paused ? "Your own plan runs. Resume to pick it up at week \(week)." : headline(p, week: week, phase: phase))
                        .font(.footnote.weight(.semibold)).opacity(0.92).lineLimit(2)
                    HStack(spacing: 3) {
                        ForEach(1...p.weeks, id: \.self) { w in
                            let k = p.phase(week: w).kind
                            Capsule()
                                .fill(w == week ? AnyShapeStyle(Theme.lime)
                                      : k == .test ? AnyShapeStyle(LinearGradient(colors: k.colors, startPoint: .leading, endPoint: .trailing))
                                      : AnyShapeStyle(Color.white.opacity(w < week ? 0.95 : 0.3)))
                                .frame(height: 7)
                        }
                    }
                    .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(p.gradient))
                .opacity(a.paused ? 0.75 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the programme")
            if !a.paused, phase.kind == .test {
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.lifts.isEmpty ? "Sim week · race a half Hyrox on your Watch" : "Test week · PR attempts").eyebrow()
                    ForEach(p.lifts, id: \.self) { id in
                        Button { attempt = id } label: {
                            HStack {
                                Image(systemName: "trophy.fill")
                                Text(Exercise.get(id).name).font(Theme.label(15)).lineLimit(1)
                                Spacer()
                                Text("Attempt").font(Theme.label(13))
                                Image(systemName: "chevron.right").font(.caption.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: ProgrammePhaseKind.test.colors, startPoint: .leading, endPoint: .trailing)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fullScreenCover(item: Binding(get: { attempt.map(LiftRoute.init) }, set: { attempt = $0?.id })) { r in
                    PRAttemptView(exerciseId: r.id)
                }
            }
        }
    }

    private func headline(_ p: Programme, week: Int, phase: ProgrammePhase) -> String {
        if phase.kind == .test { return p.lifts.isEmpty ? "Sim week. Race a half on your Watch 🏁" : "Test week. Go for your PRs 🏆" }
        guard p.hasTest, !p.lifts.isEmpty else { return phase.note }
        let test = p.phaseStarts.first { $0.phase.kind == .test }?.week ?? p.weeks
        guard test > week else { return phase.note }
        let toTest = test - week
        return "\(phase.note). \(toTest) week\(toTest == 1 ? "" : "s") to your PR test."
    }
}

private struct LiftRoute: Identifiable {
    let id: String
}

/// Training profile: the programme setting goal, split and method, with pause / resume.
struct ProgrammeProfileCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let a = model.activeProgramme, let p = a.programme {
            HStack(spacing: 12) {
                NavigationLink(value: ProgrammeRoute(id: p.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.paused ? "PROGRAMME PAUSED" : "PROGRAMME · WEEK \(model.programmeWeek ?? 1) OF \(p.weeks)")
                            .font(Theme.label(10)).tracking(1.3).opacity(0.85)
                        Text(p.name).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(a.paused ? "Your own plan runs" : "Sets goal, split and method while it runs")
                            .font(.caption.weight(.semibold)).opacity(0.9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { a.paused ? model.resumeProgramme() : model.pauseProgramme() } label: {
                    Label(a.paused ? "Resume" : "Pause", systemImage: a.paused ? "play.fill" : "pause.fill")
                        .font(Theme.label(13))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Capsule().fill(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(p.gradient))
        }
    }
}

/// Progress → Programmes: the running one with its lifts start vs now, then finished and left ones.
struct ProgrammeProgressSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let a = model.activeProgramme, let p = a.programme {
                let week = model.programmeWeek ?? 1
                NavigationLink(value: ProgrammeRoute(id: p.id)) {
                    HStack(spacing: 14) {
                        Image(systemName: p.symbol).font(.system(size: 24, weight: .bold))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(a.paused ? "Paused at week \(week)" : "Week \(week) of \(p.weeks) · \(p.phase(week: week).kind.label)")
                                .font(.footnote.weight(.semibold)).opacity(0.9)
                        }
                        Spacer(minLength: 4)
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(Int((Double(week - 1) / Double(p.weeks) * 100).rounded()))").font(Theme.display(30)).monospacedDigit()
                            Text("%").font(Theme.label(13))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(p.gradient))
                }
                .buttonStyle(.plain)
                LiftsCompare(lifts: model.programmeLifts(p, start: a.start))
            } else {
                Button { model.openExploreProgrammes() } label: {
                    Text("No programme running. Pick one in Explore → Programmes: phases, signature workouts and a PR test at the end.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Explore → Programmes")
            }
            let done = model.programmeHistory.reversed()
            if !done.isEmpty {
                Text("Finished").eyebrow()
                ForEach(Array(done)) { r in
                    if let p = r.programme {
                        HStack(spacing: 14) {
                            Image(systemName: r.finished ? "trophy.fill" : "flag.fill").font(.system(size: 22, weight: .bold))
                                .frame(width: 48, height: 48)
                                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.2)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name).font(Theme.display(18)).lineLimit(1)
                                Text((r.finished ? "Finished " : "Left after \(r.weeks) week\(r.weeks == 1 ? "" : "s") · ")
                                     + r.end.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .font(.caption.weight(.semibold)).opacity(0.9)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(p.gradient))
                        .opacity(r.finished ? 1 : 0.7)
                    }
                }
            }
        }
    }
}

/// Start → now rows: estimated 1RM before the programme and since.
struct LiftsCompare: View {
    let lifts: [ProgrammeLift]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Start → now").eyebrow()
                Spacer()
                Text("est. 1RM").font(Theme.label(12)).foregroundStyle(Theme.muted)
            }
            ForEach(lifts) { l in
                HStack {
                    Text(Exercise.get(l.exerciseId).name).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Text("\(l.before.map { Format.kg($0.rounded()) } ?? "–") → \(l.now.map { Format.kg($0.rounded()) } ?? "–") kg")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).monospacedDigit()
                    if let c = l.change {
                        Text("\(c >= 0 ? "+" : "−")\(Format.kg(abs(c).rounded()))")
                            .font(Theme.label(15)).monospacedDigit()
                            .foregroundStyle(c >= 0 ? Theme.lime : Color.red)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            }
        }
    }
}

/// Shown once on Train when a programme ends: trophy, lifts start vs end, own plan back.
struct ProgrammeFinishedSheet: View {
    let record: ProgrammeRecord
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let p = record.programme {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(LinearGradient(colors: ProgrammePhaseKind.test.colors, startPoint: .top, endPoint: .bottom))
                        .padding(.top, 30)
                    Text("Programme complete").font(Theme.label(13)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.muted)
                    Text(p.name).font(Theme.display(32)).multilineTextAlignment(.center)
                    Text("\(p.weeks) weeks done. Your own plan is back on Train; pick another programme in Explore whenever you like.")
                        .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                    LiftsCompare(lifts: model.programmeLifts(p, start: record.start, end: record.end))
                    Button { dismiss() } label: {
                        Text("Let's train").font(Theme.display(17)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
        }
    }
}

// MARK: - Every workout and the length (#268)

/// A workout tapped in the programme grid.
struct PickedProgrammeSession: Identifiable {
    let week: Int
    let session: Session
    var id: String { "\(week)-\(session.id)" }
}

/// Every programme workout, one row per week: signature workouts in the programme's colours with a star, the other
/// days in their week's phase colour (#280), the test week in gold. Weeks already done fade.
struct ProgrammeWorkoutGrid: View {
    let programme: Programme
    let weeks: [[Session]]
    var current: Int?
    let open: (Int, Session) -> Void

    var body: some View {
        VStack(spacing: 5) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { i, sessions in
                let week = i + 1
                let kind = programme.phase(week: week).kind
                HStack(spacing: 5) {
                    Text("W\(week)")
                        .font(Theme.label(11))
                        .foregroundStyle(week == current ? Theme.lime : Theme.muted)
                        .frame(width: 28, alignment: .leading)
                    ForEach(sessions) { s in
                        Button { open(week, s) } label: { cell(s, kind) }
                            .buttonStyle(.plain)
                    }
                }
                .opacity(current.map { week < $0 ? 0.45 : 1 } ?? 1)
                .overlay {
                    if week == current {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.lime, lineWidth: 2).padding(-3)
                    }
                }
            }
        }
    }

    private func cell(_ s: Session, _ kind: ProgrammePhaseKind) -> some View {
        let lead = s.isPlanInsert ? s.blocks.first { $0.kind == .strength }?.items.first?.prescription : nil
        let signature = s.isPlanInsert && kind != .test
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 2) {
                Text(s.title).font(.system(size: 11, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
                if signature {
                    Spacer(minLength: 0)
                    Image(systemName: "star.fill").font(.system(size: 8, weight: .black)).accessibilityLabel("Signature")
                }
            }
            Text(kind == .test ? "Test week" : lead.map { "\($0.sets) × \($0.reps)" } ?? "\(s.estMin) min")
                .font(.system(size: 9.5, weight: .bold, design: .rounded)).opacity(0.8)
        }
        .foregroundStyle(kind == .test ? Theme.ink : .white)
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
                signature ? AnyShapeStyle(programme.gradient)
                    : AnyShapeStyle(LinearGradient(colors: kind.colors, startPoint: .leading, endPoint: .trailing)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the workout")
    }
}

/// One programme workout: its blocks and exercises with sets × reps.
struct ProgrammeSessionSheet: View {
    let programme: Programme
    let picked: PickedProgrammeSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let phase = programme.phase(week: picked.week).kind
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEEK \(picked.week) · \(phase.label.uppercased())\(picked.session.isPlanInsert ? " · SIGNATURE" : "")")
                            .font(Theme.label(11)).tracking(1.3).opacity(0.85)
                        Text(picked.session.title).font(Theme.display(26))
                        Text("About \(picked.session.estMin) min").font(.footnote.weight(.semibold)).opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: phase.colors, startPoint: .leading, endPoint: .trailing)))
                    ForEach(picked.session.blocks) { block in
                        if !block.items.isEmpty {
                            Text(block.title).eyebrow()
                            VStack(spacing: 6) {
                                ForEach(block.items) { it in
                                    HStack {
                                        Text(Exercise.get(it.exerciseId).name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Spacer()
                                        Text("\(it.prescription.sets) × \(it.prescription.reps)").font(Theme.label(14)).monospacedDigit()
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                                }
                            }
                        }
                    }
                    if !picked.session.isPlanInsert {
                        Text("Built from your gym, days and focus. When the programme runs, the exercises are picked fresh that week.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
            }
            .glassSheetBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Pick a programme's length (design C): when starting it, or later while it runs (from next week on).
struct ProgrammeLengthSheet: View {
    let programme: Programme
    /// Programme week today while it runs; lengths that would end it now are off.
    let running: Int?
    let current: Int
    /// Name of another programme the start replaces.
    let replacing: String?
    let pick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Int?

    var body: some View {
        let selected = chosen ?? current
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Same programme, more or less time in Base and Build. Peak, Ease and Test stay as they are.")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                    ForEach(programme.lengths) { l in
                        let off = running.map { l.weeks <= $0 } ?? false
                        Button { chosen = l.weeks } label: { card(l, on: l.weeks == selected) }
                            .buttonStyle(.plain)
                            .disabled(off)
                            .opacity(off ? 0.35 : 1)
                    }
                    Text(running != nil
                         ? "This week stays as it is; the new length shapes the weeks from next week."
                         : replacing.map { "It replaces \($0), which you leave. Your own plan is still saved." }
                            ?? "It replaces your plan from this week. Your own plan is saved and comes back when you pause, leave or finish.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Button {
                        pick(selected)
                        dismiss()
                    } label: {
                        Text(running != nil ? "Use \(selected) weeks" : "Start \(selected)-week programme")
                            .font(Theme.display(17))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Theme.ink)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .disabled(running != nil && selected == current)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(running != nil ? "Programme length" : "Pick your length")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func card(_ l: ProgrammeLength, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(on ? Theme.lime : .white.opacity(0.7))
            VStack(alignment: .leading, spacing: 3) {
                Text(l.name).font(Theme.display(19))
                Text(l.phases.map { $0.kind == .base || $0.kind == .build ? "\($0.kind.label) \($0.weeks)" : $0.kind.label }
                    .joined(separator: " · "))
                    .font(.caption.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(l.weeks)").font(Theme.display(32)).monospacedDigit()
                Text("wk").font(Theme.label(11)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(on ? AnyShapeStyle(programme.gradient) : AnyShapeStyle(Theme.card)))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}


/// "Get ready for…" (#620 A): one square tile per sport; each opens its season block (Snow ready, Climber's power or a
/// season programme), where the first day of the season fits the length.
struct SeasonPickerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get ready for…").font(Theme.display(20)).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(SeasonSport.allCases) { s in
                    NavigationLink(value: ProgrammeRoute(id: s.programmeId)) {
                        VStack(spacing: 4) {
                            Text(s.emoji).font(.system(size: 26))
                            Text(s.label.uppercased()).font(Theme.label(11)).tracking(0.8)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.18)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Get ready for \(s.label)")
                }
            }
            // Sport add-on (#620 C): no plan change, 15′ in a few sessions.
            SportAddOnRow()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFF4D8D), Color(hex: 0x8A2BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}
