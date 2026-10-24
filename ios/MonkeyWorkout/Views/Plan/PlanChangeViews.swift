import SwiftUI
import WorkoutEngine

// One-off changes to this week (#113): move a session to another day, add an extra workout.

extension Focus {
    /// Vivid tile colours for a session focus (same mapping as session cards).
    var palette: WorkoutEngine.Category {
        switch self {
        case .lower, .fullLower, .legs: .warmup
        case .upper, .fullUpper: .mobility
        case .push, .fullPower: .power
        case .conditioning: .cardio
        case .pull, .backBi: .strength
        case .chestTri: .power
        case .shouldersArms, .chestBack: .mobility
        case .posterior: .warmup
        }
    }

    /// Short name for quick-session tiles.
    var quickLabel: String {
        switch self {
        case .fullUpper, .upper: "Upper body"
        case .fullLower, .lower: "Lower body"
        case .fullPower: "Full-body power"
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .conditioning: "Conditioning"
        case .chestTri, .backBi, .shouldersArms, .chestBack, .posterior: label
        }
    }
}

private let dayFormat: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.abbreviated)

/// Pick another day of this week for one session; a session already there swaps days.
struct MoveSessionSheet: View {
    let sessionId: String
    /// A later week's session (#671); nil = this week.
    var later: PlanCalendar.Week? = nil
    var onMoved: (Int) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init(sessionId: String, later: PlanCalendar.Week? = nil, onMoved: @escaping (Int) -> Void = { _ in }) {
        self.sessionId = sessionId
        self.later = later
        self.onMoved = onMoved
    }

    var body: some View {
        NavigationStack {
            ScrollView { MoveDayPicker(sessionId: sessionId, later: later) { wd in onMoved(wd); dismiss() }.padding(16) }
                .readableWidth()
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle("Move to…")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

/// The days of this week as vivid rows: what's planned there, today marked, days off and the session's own day locked.
struct MoveDayPicker: View {
    let sessionId: String
    /// A later week's session (#671): its days, that week only; nil = this week.
    var later: PlanCalendar.Week? = nil
    let onMoved: (Int) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.planCalendar
        let week = later ?? model.calendarWeeks(count: 1).first
        let session = week?.plan.sessions.first { $0.id == sessionId }
        let targets = Set(later.flatMap { w in session.map { model.moveTargets($0, in: w) } } ?? model.moveTargets(sessionId))
        let today = PlanCalendar.key(Date(), cal)
        VStack(alignment: .leading, spacing: 10) {
            if let session, let week {
                header(session)
                ForEach(WeekSchedule.weekdays, id: \.self) { wd in
                    let others = week.plan.sessions.filter { $0.weekday == wd && $0.id != sessionId }
                    let row = dayRow(wd, week: week, own: session.weekday == wd, others: others, enabled: targets.contains(wd),
                                     today: week.days[wd - 1] == today, cal: cal)
                    if targets.contains(wd) {
                        Button {
                            if let later { model.moveSession(sessionId, to: wd, in: later) } else { model.moveSession(sessionId, to: wd) }
                            onMoved(wd)
                        } label: { row }
                        .buttonStyle(.plain)
                    } else {
                        row
                    }
                }
                Text(later == nil ? "This week only: next week follows your plan again. A day with a session swaps with it."
                     : "That week only: the weeks after follow your plan again. A day with a session swaps with it.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                ContentUnavailableView("Not in this week", systemImage: "calendar.badge.exclamationmark")
            }
        }
    }

    private func header(_ s: Session) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 22, weight: .heavy))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text(s.displayTitle).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.8)
                Text(s.weekday.map { "Planned \(WeekSchedule.name($0))" } ?? "No day yet").font(.footnote.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(s.palette.gradient))
    }

    private func dayRow(_ wd: Int, week: PlanCalendar.Week, own: Bool, others: [Session], enabled: Bool, today: Bool, cal: Calendar) -> some View {
        let off = week.off[wd] != nil
        let detail: String = {
            if own { return "Planned here" }
            if off { return week.off[wd]?.title ?? "Can't train" }
            if let o = others.first { return "Swap with \(o.displayTitle)" + (others.count > 1 ? " +\(others.count - 1)" : "") }
            if week.climbing.contains(wd) { return "Climbing day" }
            return "Free"
        }()
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(WeekSchedule.shortName(wd).uppercased()).font(Theme.label(10))
                Text(week.date(wd, cal).map { "\(cal.component(.day, from: $0))" } ?? "").font(Theme.display(20)).monospacedDigit()
            }
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(WeekSchedule.name(wd) + (today ? " · Today" : "")).font(.system(.headline, design: .rounded).weight(.heavy))
                Text(detail).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 4)
            if enabled {
                Image(systemName: others.isEmpty ? "arrow.down.to.line" : "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
            } else if own {
                Image(systemName: "mappin.circle.fill").font(.system(size: 24))
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(off ? AnyShapeStyle(WorkoutEngine.Category.power.color.opacity(0.35))
                      : others.first.map { AnyShapeStyle($0.palette.gradient) } ?? AnyShapeStyle(Theme.card))
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.lime, lineWidth: own ? 2 : 0))
        .opacity(enabled || own ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Add an unplanned workout to a day of this week: quick generated session (with duration and muscle focus),
/// a custom workout built now, a library workout, or a climb.
struct AddWorkoutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var weekday: Int
    @State private var logging: ClimbLog?
    @State private var climbsBefore = 0
    /// Quick session whose options step is shown (#178).
    @State private var quick: Focus?
    @State private var building: CustomWorkout?
    @State private var built = false
    @State private var browsing = false
    @State private var picked: LibraryEntry?

    /// Library workouts shown on the sheet; the rest are one tap away in Browse library (#178).
    static let libraryPreview = 3

    init(weekday: Int? = nil, quick: Focus? = nil) {
        let today = WeekSchedule.fromCalendar(Calendar.current.component(.weekday, from: Date()))
        // Never an earlier day: a workout added there could only be logged (#537).
        _weekday = State(initialValue: max(weekday ?? today, today))
        _quick = State(initialValue: quick)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    dayPicker
                    Text("Quick session").eyebrow().padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Generator.quickFoci, id: \.self) { f in
                            Button { quick = f } label: { focusTile(f) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Add now · \(Generator.quickDefaultMinutes) min", systemImage: "bolt.fill") {
                                        addQuick(f, minutes: Generator.quickDefaultMinutes)
                                    }
                                }
                        }
                    }
                    Text("Pick duration and muscle focus next. Built for your equipment and this week's phase; counts in your week and history.")
                        .font(.caption).foregroundStyle(Theme.muted)

                    Text("Your own").eyebrow().padding(.top, 8)
                    Button { building = CustomWorkout(name: "") } label: { customRow }
                        .buttonStyle(.plain)

                    Text("From your library").eyebrow().padding(.top, 8)
                    let library = Self.libraryOrder(mine: model.customWorkouts, builtIn: model.builtInLibrary)
                    ForEach(library.prefix(Self.libraryPreview)) { e in
                        Button { addLibrary(e) } label: { LibraryCard(entry: e) }.buttonStyle(.plain)
                    }
                    Button { browsing = true } label: { browseRow(count: library.count) }
                        .buttonStyle(.plain)

                    Text("Climbing").eyebrow().padding(.top, 8)
                    Button {
                        climbsBefore = model.climbLogs.count
                        logging = ClimbLog(start: climbStart)
                    } label: { climbRow }.buttonStyle(.plain)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .navigationDestination(item: $quick) { f in
                QuickSessionOptionsView(focus: f, day: dayDate.formatted(.dateTime.weekday(.wide))) { minutes, groups, tweaks in
                    addQuick(f, minutes: minutes, groups: groups, tweaks: tweaks)
                }
            }
            .sheet(item: $logging, onDismiss: { if model.climbLogs.count > climbsBefore { dismiss() } }) {
                LogClimbView(initial: $0)
            }
            .sheet(item: $building, onDismiss: { if built { dismiss() } }) { w in
                CustomWorkoutEditor(initial: w) { saved in
                    model.addExtra(saved, weekday: weekday)
                    built = true
                }
            }
            .sheet(isPresented: $browsing, onDismiss: { if let e = picked { addLibrary(e) } }) {
                NavigationStack {
                    WorkoutLibraryView { e in
                        picked = e
                        browsing = false
                    }
                    .toolbar { CloseToolbarItem { browsing = false } }
                }
                .preferredColorScheme(.dark)
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    /// My workouts newest first, then built-in ones.
    static func libraryOrder(mine: [CustomWorkout], builtIn: [LibraryEntry]) -> [LibraryEntry] {
        mine.sorted { $0.createdAt > $1.createdAt }.map { LibraryEntry(source: .mine($0)) } + builtIn
    }

    private var dayDate: Date {
        let cal = model.planCalendar
        return cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
    }

    /// 18:00 that day, or 90 min ago today.
    private var climbStart: Date {
        let cal = model.planCalendar
        if cal.isDateInToday(dayDate) { return Date().addingTimeInterval(-90 * 60).rounded(minutes: 5) }
        return cal.date(bySettingHour: 18, minute: 0, second: 0, of: dayDate) ?? dayDate
    }

    private var dayPicker: some View {
        let cal = model.planCalendar
        let week = model.calendarWeeks(count: 1).first
        return VStack(alignment: .leading, spacing: 8) {
            Text(dayDate.formatted(dayFormat)).font(Theme.display(26))
            HStack(spacing: 4) {
                ForEach(WeekSchedule.weekdays, id: \.self) { wd in
                    // An earlier day can't take a new workout (#537): log it from Train instead.
                    let off = week?.off[wd] != nil || wd < model.todayWeekday
                    let past = wd < model.todayWeekday
                    let busy = week?.plan.sessions.contains { $0.weekday == wd } ?? false
                    Button { weekday = wd } label: {
                        VStack(spacing: 1) {
                            Text(WeekSchedule.shortName(wd).uppercased()).font(Theme.label(9))
                            Text(week?.date(wd, cal).map { "\(cal.component(.day, from: $0))" } ?? "").font(Theme.display(17)).monospacedDigit()
                            Circle().fill(busy ? Color.white : .clear).frame(width: 5, height: 5)
                        }
                        .foregroundStyle(weekday == wd ? Theme.ink : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(weekday == wd ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(off ? 0.03 : 0.08))))
                        .opacity(off ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(off)
                    .accessibilityLabel(WeekSchedule.name(wd) + (past ? ", past day, log it from Train" : off ? ", can't train" : busy ? ", has a session" : ""))
                }
            }
        }
    }

    private func focusTile(_ f: Focus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: f == .conditioning ? "heart.circle.fill" : "bolt.fill").font(.system(size: 20, weight: .bold))
            Text(f.quickLabel).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
            Text("Options").font(Theme.label(11)).tracking(1).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(f.palette.gradient))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick \(f.quickLabel) session")
        .accessibilityHint("Pick duration and muscle focus")
    }

    private var climbRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.climbing")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Log a climb").font(Theme.display(21))
                Text("Boulder, lead, top rope or outdoor, saved to Apple Health").font(.footnote.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.warmup.gradient))
    }

    private var customRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Custom workout").font(Theme.display(21))
                }
                Text("Pick exercises, or generate from muscles. Saved to your workouts too.").font(.footnote.weight(.semibold)).opacity(0.88)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Build a custom workout")
    }

    private func browseRow(count: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.lime)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.lime.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Browse library").font(.system(.headline, design: .rounded).weight(.heavy))
                Text("Search all \(count) workouts, plus members' shared ones").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    /// Generated for the focus (preset muscles) or for the chosen muscles; false when nothing fits.
    @discardableResult
    private func addQuick(_ f: Focus, minutes: Int, groups: Set<MuscleGroup>? = nil, tweaks: FlowTweaks? = nil) -> Bool {
        if let groups, groups != f.muscleGroups, !groups.isEmpty {
            guard var w = model.quickWorkout(groups, minutes: minutes, tweaks: tweaks) else { return false }
            w.name = "Extra · " + CustomWorkout.generatedName(groups)
            model.addExtra(w, weekday: weekday)
        } else {
            guard let s = model.quickSession(f, minutes: minutes, tweaks: tweaks) else { return false }
            model.addExtra(CustomWorkout(name: "Extra · \(f.quickLabel)"), generated: s, weekday: weekday)
        }
        dismiss()
        return true
    }

    private func addLibrary(_ e: LibraryEntry) {
        guard let w = model.libraryWorkout(for: e.session) else { return }
        model.addExtra(w, weekday: weekday)
        dismiss()
    }
}

/// Quick session options (#178): duration and muscle focus before adding. Preset muscles = the focus's session;
/// other muscles = a workout generated for them.
struct QuickSessionOptionsView: View {
    let focus: Focus
    let day: String
    /// Returns false when nothing fits the equipment.
    let onAdd: (Int, Set<MuscleGroup>, FlowTweaks) -> Bool
    @Environment(AppModel.self) private var model
    @State private var minutes = Generator.quickDefaultMinutes
    /// Warm-up / cool-down style or exact moves (#293).
    @State private var tweaks = FlowTweaks()
    @State private var tweaking: FlowTweakTarget?
    @State private var groups: Set<MuscleGroup>
    @State private var nothingFits = false

    init(focus: Focus, day: String, onAdd: @escaping (Int, Set<MuscleGroup>, FlowTweaks) -> Bool) {
        self.focus = focus
        self.day = day
        self.onAdd = onAdd
        _groups = State(initialValue: focus.muscleGroups)
    }

    private var preset: Bool { groups == focus.muscleGroups }
    private var title: String { preset ? focus.quickLabel : CustomWorkout.generatedName(groups) }
    private var canAdd: Bool { !groups.isEmpty || focus == .conditioning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                Text("Duration").eyebrow().padding(.top, 10)
                HStack(spacing: 8) {
                    ForEach(Generator.quickDurations, id: \.self) { m in
                        Button { minutes = m; nothingFits = false } label: {
                            VStack(spacing: 0) {
                                Text("\(m)").font(Theme.display(20)).monospacedDigit()
                                Text("MIN").font(Theme.label(8)).tracking(1).opacity(0.85)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .selectableGradient(WorkoutEngine.Category.cardio.gradient, selected: minutes == m, cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(m) minutes")
                        .accessibilityAddTraits(minutes == m ? .isSelected : [])
                    }
                }

                HStack {
                    Text("Muscle focus").eyebrow()
                    Spacer()
                    if !preset {
                        Button("Reset") { groups = focus.muscleGroups; nothingFits = false }
                            .font(Theme.label(13)).foregroundStyle(Theme.lime)
                    }
                }
                .padding(.top, 10)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(MuscleGroup.allCases) { g in
                        MuscleGroupTile(group: g, on: groups.contains(g)) {
                            if groups.contains(g) { groups.remove(g) } else { groups.insert(g) }
                            nothingFits = false
                        }
                    }
                }
                Text(note).font(.footnote).foregroundStyle(Theme.muted)

                if canAdd {
                    Text("Warm-up & cool-down").eyebrow().padding(.top, 10)
                    HStack(spacing: 10) {
                        ForEach(FlowTweaks.kinds, id: \.self) { k in flowCard(k) }
                    }
                }

                if nothingFits {
                    Text("Nothing fits your equipment for these muscles. Pick other muscles or update your gym in the training profile.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.lime)
                }

                Button(action: add) {
                    Label("Add to \(day)", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.5)
                .padding(.top, 8)
            }
            .padding(16)
            .animation(.spring(duration: 0.3), value: groups)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Quick session")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tweaking) { t in
            FlowTweakSheet(kind: t.kind, tweaks: $tweaks, preview: { flowPreview($0, t.kind) })
        }
    }

    /// Warm-up or cool-down card: style (or own moves); opens its sheet (#293).
    private func flowCard(_ k: BlockKind) -> some View {
        Button { tweaking = FlowTweakTarget(kind: k) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: k.symbol).font(.system(size: 18, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.8)
                }
                Text(k.flowLabel).font(Theme.display(18))
                Text(tweaks.summary(k, profile: model.profile)).font(Theme.label(12)).opacity(0.9).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gradientCard(k.gradient, padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens its style and moves")
    }

    /// Moves `kind` gets with `t` for the current duration and muscles.
    private func flowPreview(_ t: FlowTweaks, _ kind: BlockKind) -> [PlannedExercise] {
        let blocks = preset || groups.isEmpty
            ? model.quickSession(focus, minutes: minutes, tweaks: t)?.blocks
            : model.quickWorkout(groups, minutes: minutes, tweaks: t)?.flow
        return blocks?.first { $0.kind == kind }?.items ?? []
    }

    private var note: String {
        if preset {
            return focus == .conditioning
                ? "Intervals with warm-up and cool-down. Pick muscles to get a strength workout for them instead."
                : "The \(focus.quickLabel.lowercased()) session with warm-up and cool-down. Pick other muscles to target them instead."
        }
        if groups.isEmpty { return "Pick at least one muscle group." }
        return "Strength work for these muscles with a warm-up and cool-down, sized to \(minutes) min, with your goal's sets and reps. Pro, like Generate from muscles."
    }

    private var header: some View {
        let lead = preset ? nil : MuscleGroup.allCases.first { groups.contains($0) }
        let gradient: LinearGradient = lead?.gradient ?? focus.palette.gradient
        return HStack(spacing: 14) {
            Image(systemName: preset ? (focus == .conditioning ? "heart.circle.fill" : "bolt.fill") : "wand.and.stars")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.7)
                Text("EXTRA · \(day.uppercased())").font(Theme.label(11)).tracking(1).opacity(0.9)
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(minutes)").font(Theme.display(34)).monospacedDigit()
                Text(" min").font(Theme.label(13))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
        .accessibilityElement(children: .combine)
    }

    private func add() {
        nothingFits = !onAdd(minutes, groups, tweaks)
    }
}

private extension Date {
    func rounded(minutes: Int) -> Date {
        let step = Double(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / step).rounded(.down) * step)
    }
}
