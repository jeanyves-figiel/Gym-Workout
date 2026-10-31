import SwiftUI
import WorkoutEngine

// Add any workout to a day (#851, design A + B from `add-workout-any/proposals.png`): not only a quick session.

private let addDayFormat: Date.FormatStyle = .dateTime.weekday(.abbreviated).day()

/// "What will you do?" (#851, design A): the Coach's pick, this week's workouts to move here, then Explore-style
/// squares for my workouts, the library, Generate (any length, design B), Build my own, HIIT and a climb. The day's
/// sport stays; whatever is picked is added next to it. Pushed in Train so the tab bar stays and swipe back closes it
/// (#1005); `AddWorkoutSheet` wraps it for sheets.
struct AddWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The day tapped on Train (#1005: no day chips here, the tap picked it); today from *Add workout*.
    private let weekday: Int
    @State private var logging: ClimbLog?
    @State private var climbsBefore = 0
    /// Generate step (design B) open on this focus.
    @State private var generating: Focus?
    @State private var building: CustomWorkout?
    @State private var built = false
    @State private var library: WorkoutLibraryView.Filter?
    /// Picked in the library; added once that sheet is down.
    @State private var picked: LibraryEntry?
    /// Save from a video (#909) for this day.
    @State private var fromVideo = false

    private static let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    init(weekday: Int? = nil, quick: Focus? = nil) {
        let today = WeekSchedule.fromCalendar(Calendar.current.component(.weekday, from: Date()))
        // Never an earlier day: a workout added there could only be logged (#537).
        self.weekday = max(weekday ?? today, today)
        _generating = State(initialValue: quick)
    }

    var body: some View {
        let coach = Generator.coachExtraFocus(heat: model.weekHeat)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(weekday == model.todayWeekday ? "Add to today · \(dayDate.formatted(addDayFormat))" : "Add to \(dayDate.formatted(addDayFormat))")
                    .font(Theme.label(12)).tracking(1.4).textCase(.uppercase).opacity(0.75)
                Text("What will you do?").font(Theme.display(30))
                if let sport = daySport { sportStays(sport) }

                heading("Coach pick · fits your week")
                Button { addQuick(coach, minutes: defaultMinutes) } label: { coachRow(coach) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Length and focus…", systemImage: "slider.horizontal.3") { generating = coach }
                    }

                let moves = movable
                if !moves.isEmpty {
                    heading("This week's plan · move here")
                    ForEach(moves) { s in
                        Button { move(s) } label: { moveRow(s) }.buttonStyle(.plain)
                    }
                }

                heading("Any other workout")
                LazyVGrid(columns: Self.columns, spacing: 10) {
                    Button { library = .mine } label: {
                        AddCategoryCard(title: "My workouts", detail: "your own", symbol: "star.fill",
                                        value: "\(model.myLibrary.count)", colors: [Color(hex: 0xA43DFF), Color(hex: 0xFF4FD8)])
                    }
                    Button { library = .all } label: {
                        AddCategoryCard(title: "Library", detail: "examples · members", symbol: "books.vertical.fill",
                                        value: "\(model.builtInLibrary.count + model.memberLibrary.count)",
                                        colors: [Color(hex: 0xFF5F8F), Color(hex: 0xFF9A5C)])
                    }
                    Button { generating = coach } label: {
                        AddCategoryCard(title: "Generate", detail: "focus · any length", symbol: "wand.and.stars",
                                        value: "2h", colors: [Color(hex: 0x3D5AFF), Color(hex: 0x8A4FFF)])
                    }
                    .accessibilityIdentifier("addWorkout.generate")
                    Button { building = CustomWorkout(name: "") } label: {
                        AddCategoryCard(title: "Build my own", detail: "pick exercises", symbol: "square.and.pencil",
                                        value: "+", colors: [Color(hex: 0x7A5CFF), Color(hex: 0x3DC7FF)])
                    }
                    Menu {
                        ForEach(HiitFormat.allCases) { f in
                            Menu(f.label, systemImage: f.symbol) {
                                ForEach(HiitSpec.lengths, id: \.self) { m in
                                    Button("\(m) min") { addHiit(f, minutes: m) }
                                }
                            }
                        }
                    } label: {
                        AddCategoryCard(title: "HIIT", detail: "format · timer", symbol: "bolt.fill",
                                        value: "\(HiitFormat.allCases.count)", colors: [Color(hex: 0xFF3D6B), Color(hex: 0xFFB03D)])
                    }
                    Button {
                        climbsBefore = model.climbLogs.count
                        logging = ClimbLog(start: climbStart)
                    } label: {
                        AddCategoryCard(title: "Log a climb", detail: "boulder, lead, outdoor", symbol: "figure.climbing",
                                        value: "🧗", colors: [Color(hex: 0x1FC8A0), Color(hex: 0x3AA0F0)])
                    }
                    Button { fromVideo = true } label: {
                        AddCategoryCard(title: "From a video", detail: "TikTok · Instagram", symbol: "play.rectangle.on.rectangle.fill",
                                        value: "▶", colors: [Color(hex: 0x7B4DFF), Color(hex: 0x3D7BFF)])
                    }
                    .accessibilityIdentifier("addWorkout.fromVideo")
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $generating) { f in
            GenerateWorkoutView(focus: f, minutes: defaultMinutes, day: dayDate.formatted(addDayFormat)) { focus, minutes, groups, tweaks in
                addQuick(focus, minutes: minutes, groups: groups, tweaks: tweaks)
            }
        }
        .sheet(isPresented: $fromVideo) {
            VideoImportSheet(weekday: weekday) { built = true }
        }
        .onChange(of: fromVideo) { if !fromVideo && built { dismiss() } }
        .sheet(item: $logging, onDismiss: { if model.climbLogs.count > climbsBefore { dismiss() } }) {
            LogClimbView(initial: $0)
        }
        .sheet(item: $building, onDismiss: { if built { dismiss() } }) { w in
            CustomWorkoutEditor(initial: w) { saved in
                model.addExtra(saved, weekday: weekday)
                built = true
            }
        }
        .sheet(item: $library, onDismiss: { if let e = picked { addLibrary(e) } }) { f in
            NavigationStack {
                WorkoutLibraryView(filter: f) { e in
                    picked = e
                    library = nil
                }
                .toolbar { CloseToolbarItem { library = nil } }
            }
            .preferredColorScheme(.dark)
        }
        .preferredColorScheme(.dark)
    }

    /// The plan's session length, as the closest offered length.
    private var defaultMinutes: Int {
        Generator.quickDuration(near: model.profile.map(Generator.sessionMinutes) ?? 60)
    }

    private var dayDate: Date {
        let cal = model.planCalendar
        return cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
    }

    private var daySport: Sport? {
        model.daySport(onWeekday: weekday, key: PlanCalendar.key(dayDate, model.planCalendar), date: dayDate)
    }

    /// This week's workouts that can come to this day: not done, not skipped (#849), not already on it.
    private var movable: [Session] {
        (model.plan?.sessions ?? []).filter { s in
            s.weekday != nil && s.weekday != weekday && !model.doneIds.contains(s.id) && !model.skippedOff(s)
                && model.moveTargets(s.id).contains(weekday)
        }
    }

    /// 18:00 that day, or 90 min ago today.
    private var climbStart: Date {
        let cal = model.planCalendar
        if cal.isDateInToday(dayDate) { return Date().addingTimeInterval(-90 * 60).rounded(minutes: 5) }
        return cal.date(bySettingHour: 18, minute: 0, second: 0, of: dayDate) ?? dayDate
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(Theme.label(12)).tracking(1.4).textCase(.uppercase).opacity(0.75).padding(.top, 8)
    }

    /// "Climbing stays on Wed" (#851): adding a workout never takes the day's sport away.
    private func sportStays(_ sport: Sport) -> some View {
        Label("\(sport.label) stays on \(WeekSchedule.shortName(weekday)) · this adds a workout", systemImage: sport.symbol)
            .font(Theme.label(12)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xFF9A3C).opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(hex: 0xFF9A3C).opacity(0.6)))
    }

    private func coachRow(_ f: Focus) -> some View {
        AddRow(title: f.quickLabel, detail: "generated for your kit · least trained this week", symbol: "sparkles",
               value: "\(defaultMinutes)′", action: "ADD ›", colors: [Theme.lime, Color(hex: 0x7BE07B)], ink: Theme.ink)
            .accessibilityLabel("Coach pick: \(f.quickLabel), \(defaultMinutes) minutes")
            .accessibilityHint("Adds it. Long press for length and focus")
    }

    private func moveRow(_ s: Session) -> some View {
        let from = s.weekday.map { $0 < model.todayWeekday ? "missed \(WeekSchedule.shortName($0))" : "from \(WeekSchedule.shortName($0))" } ?? ""
        return AddRow(title: s.displayTitle, detail: from, symbol: "arrow.left.arrow.right", value: "\(s.estMin)′", action: "MOVE ›",
                      colors: [Color(hex: 0x3D5AFF), Color(hex: 0x8A4FFF)])
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
        picked = nil
        guard let w = model.libraryWorkout(for: e.session) else { return }
        model.addExtra(w, weekday: weekday)
        dismiss()
    }

    private func addHiit(_ f: HiitFormat, minutes: Int) {
        let spec = HiitSpec(format: f, minutes: minutes, kit: .gym)
        let g = Hiit.build(spec, gym: model.profile?.equipment ?? []).session(id: spec.sessionId)
        model.addExtra(CustomWorkout(name: g.title), generated: g, weekday: weekday)
        dismiss()
    }

    /// Moves a workout of this week here, next to what the day already has; Undo puts it back.
    private func move(_ s: Session) {
        guard let from = s.weekday else { return }
        withAnimation(.snappy) { model.moveSession(s.id, to: weekday, swap: false) }
        UndoCloseCenter.shared.deleted("\(s.displayTitle) moved to \(WeekSchedule.name(weekday))", detail: "This week only",
                                       symbol: "arrow.left.arrow.right") { [model] in
            withAnimation(.snappy) { model.moveSession(s.id, to: from, swap: false) }
        }
        dismiss()
    }
}

/// Generate a workout to add (#851, design B): length 20 min to 2 h, focus chips or own muscles, warm-up and
/// cool-down, and the exercises it will have before adding.
struct GenerateWorkoutView: View {
    let day: String
    /// Returns false when nothing fits the equipment.
    let onAdd: (Focus, Int, Set<MuscleGroup>, FlowTweaks) -> Bool
    @Environment(AppModel.self) private var model
    @State private var focus: Focus
    @State private var minutes: Int
    /// Warm-up / cool-down style or exact moves (#293).
    @State private var tweaks = FlowTweaks()
    @State private var tweaking: FlowTweakTarget?
    @State private var groups: Set<MuscleGroup>
    /// Own muscles picked instead of a focus.
    @State private var ownMuscles = false
    @State private var nothingFits = false
    @State private var preview: Session?

    init(focus: Focus, minutes: Int, day: String, onAdd: @escaping (Focus, Int, Set<MuscleGroup>, FlowTweaks) -> Bool) {
        self.day = day
        self.onAdd = onAdd
        _focus = State(initialValue: focus)
        _minutes = State(initialValue: minutes)
        _groups = State(initialValue: focus.muscleGroups)
    }

    private var preset: Bool { !ownMuscles || groups == focus.muscleGroups }
    private var title: String { preset ? focus.quickLabel : CustomWorkout.generatedName(groups) }
    private var canAdd: Bool { preset || !groups.isEmpty }

    /// What the preview is generated from.
    private struct Spec: Equatable {
        let focus: Focus
        let minutes: Int
        let groups: Set<MuscleGroup>
        let preset: Bool
        let tweaks: FlowTweaks
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                Text("Length").eyebrow().padding(.top, 6)
                HStack(spacing: 6) {
                    ForEach(Generator.quickDurations, id: \.self) { m in
                        Button { minutes = m; nothingFits = false } label: {
                            Text(m >= 120 ? "\(m / 60)h" : "\(m)′").font(Theme.label(14)).monospacedDigit()
                                .foregroundStyle(minutes == m ? Theme.ink : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(minutes == m ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.08))))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(m) minutes")
                        .accessibilityAddTraits(minutes == m ? .isSelected : [])
                    }
                }

                Text("Focus").eyebrow().padding(.top, 6)
                FlowLayout(spacing: 6) {
                    ForEach(Generator.quickFoci, id: \.self) { f in
                        chip(f.quickLabel, on: !ownMuscles && focus == f) {
                            focus = f
                            groups = f.muscleGroups
                            ownMuscles = false
                            nothingFits = false
                        }
                    }
                    chip("Muscles…", on: ownMuscles) {
                        ownMuscles = true
                        nothingFits = false
                    }
                }
                if ownMuscles {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(MuscleGroup.allCases) { g in
                            MuscleGroupTile(group: g, on: groups.contains(g)) {
                                if groups.contains(g) { groups.remove(g) } else { groups.insert(g) }
                                nothingFits = false
                            }
                        }
                    }
                    if groups.isEmpty {
                        Text("Pick at least one muscle group.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }

                if canAdd {
                    Text("Exercises").eyebrow().padding(.top, 6)
                    exercises
                    Text("Warm-up & cool-down").eyebrow().padding(.top, 6)
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
                    Label("Add to \(day) · \(minutes)′", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.5)
                .padding(.top, 8)
                .accessibilityIdentifier("addWorkout.add")
            }
            .padding(16)
            .animation(.spring(duration: 0.3), value: ownMuscles)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Generate")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Spec(focus: focus, minutes: minutes, groups: groups, preset: preset, tweaks: tweaks)) { preview = generate() }
        .sheet(item: $tweaking) { t in
            FlowTweakSheet(kind: t.kind, tweaks: $tweaks, preview: { flowPreview($0, t.kind) })
        }
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Theme.label(13))
                .foregroundStyle(on ? Theme.ink : .white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.08))))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The workout as it would be added now; nil when nothing fits.
    private func generate(_ t: FlowTweaks? = nil) -> Session? {
        preset ? model.quickSession(focus, minutes: minutes, tweaks: t ?? tweaks)
            : model.quickWorkout(groups, minutes: minutes, tweaks: t ?? tweaks)?.session
    }

    /// Main exercises of the preview with sets × reps; the warm-up and cool-down have their own cards.
    @ViewBuilder private var exercises: some View {
        let items = (preview?.blocks ?? []).filter { $0.kind != .warmup && $0.kind != .cooldown }.flatMap(\.items)
        if items.isEmpty {
            Text(preview == nil ? "Nothing fits your equipment for this yet." : "Intervals with warm-up and cool-down.")
                .font(.footnote).foregroundStyle(Theme.muted)
        } else {
            VStack(spacing: 0) {
                ForEach(items.prefix(8)) { it in
                    HStack {
                        Text(Exercise.find(it.exerciseId)?.name ?? it.exerciseId).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(it.prescription.sets)×\(it.prescription.reps)").font(Theme.label(13)).foregroundStyle(Theme.lime)
                    }
                    .padding(.vertical, 7)
                    Divider().overlay(Color.white.opacity(0.08))
                }
                if items.count > 8 {
                    Text("+ \(items.count - 8) more · edit after adding").font(Theme.label(12)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
                }
            }
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

    /// Moves `kind` gets with `t` for the current length and muscles.
    private func flowPreview(_ t: FlowTweaks, _ kind: BlockKind) -> [PlannedExercise] {
        generate(t)?.blocks.first { $0.kind == kind }?.items ?? []
    }

    private var header: some View {
        let lead = preset ? nil : MuscleGroup.allCases.first { groups.contains($0) }
        let gradient: LinearGradient = lead?.gradient ?? focus.palette.gradient
        let count = (preview?.blocks ?? []).filter { $0.kind != .warmup && $0.kind != .cooldown }.flatMap(\.items).count
        return HStack(spacing: 14) {
            Image(systemName: preset ? (focus == .conditioning ? "heart.circle.fill" : "bolt.fill") : "wand.and.stars")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.7)
                Text("\(day.uppercased()) · \(count) EXERCISES" + (preview.map { " · +\(model.xp(for: $0)) XP" } ?? ""))
                    .font(Theme.label(11)).tracking(1).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
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
        nothingFits = !onAdd(focus, minutes, ownMuscles ? groups : focus.muscleGroups, tweaks)
    }
}

/// One square of the add sheet (#851), the past-day sheet's look (#800): title over a detail line, icon tile bottom
/// left, big value bottom right.
private struct AddCategoryCard: View {
    let title: String
    let detail: String
    let symbol: String
    let value: String
    let colors: [Color]
    var ink: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(Theme.label(10)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            HStack(alignment: .bottom) {
                Image(systemName: symbol).font(.system(size: 14, weight: .heavy))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.18)))
                Spacer(minLength: 4)
                Text(value).font(Theme.display(30)).monospacedDigit().lineLimit(1)
            }
        }
        .foregroundStyle(ink)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A wide row of the add sheet (#851): icon tile, title over a detail line, big minutes and the action on the right.
private struct AddRow: View {
    let title: String
    let detail: String
    let symbol: String
    let value: String
    let action: String
    let colors: [Color]
    var ink: Color = .white

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .heavy))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(Theme.label(10)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).font(Theme.display(22)).monospacedDigit()
                Text(action).font(Theme.label(9)).opacity(0.85)
            }
        }
        .foregroundStyle(ink)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private extension Date {
    func rounded(minutes: Int) -> Date {
        let step = Double(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / step).rounded(.down) * step)
    }
}

/// Add workout from a sheet (Calendar day sheet, demo screens): own stack, X top right, swipe down closes (#1005).
struct AddWorkoutSheet: View {
    var weekday: Int?
    var quick: Focus?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AddWorkoutView(weekday: weekday, quick: quick)
                .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}
