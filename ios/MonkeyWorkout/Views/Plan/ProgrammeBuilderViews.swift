import SwiftUI
import WorkoutEngine

// MARK: - Member-made programmes (#269): "Make it mine" editor (design A) and the 4-step builder (design B)

/// A workout a member can pin as a signature: one of theirs or a built-in library workout.
struct ProgrammeWorkoutSource: Identifiable, Hashable {
    struct Exercise: Hashable {
        let exerciseId: String
        let sets: Int
        let reps: Int
        let restSec: Int
    }

    let id: String
    let name: String
    let focus: Focus?
    let exercises: [Exercise]
    /// "My workouts" or "Library".
    let mine: Bool

    init(_ w: CustomWorkout) {
        id = "custom-\(w.id.uuidString.lowercased())"
        name = w.name
        focus = nil
        exercises = w.items.map { Exercise(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps, restSec: $0.restSec) }
        mine = true
    }

    init(_ t: WorkoutTemplate) {
        id = "template-\(t.id)"
        name = t.name
        focus = t.focus
        exercises = t.items.map { Exercise(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps, restSec: $0.restSec) }
        mine = false
    }

    func signature(progression: Bool) -> ProgrammeSignature {
        ProgrammeSignature.from(
            id: "sig-" + UUID().uuidString.prefix(8).lowercased(), name: name, focus: focus,
            items: exercises.map { ($0.exerciseId, $0.sets, $0.reps, $0.restSec) }, progression: progression)
    }

    /// Strength or power exercises: what a signature keeps.
    var mainCount: Int {
        exercises.filter { WorkoutEngine.Exercise.find($0.exerciseId).map { $0.category == .strength || $0.category == .power } ?? false }
            .count
    }
}

/// Lifts a member can test at the end: the rep exercises of the programme's signature workouts.
private func testableLifts(_ signatures: [ProgrammeSignature]) -> [String] {
    var out: [String] = []
    for s in signatures {
        for it in s.items where !out.contains(it.exerciseId) {
            guard let e = Exercise.find(it.exerciseId), CustomWorkout.Measure(e) == .reps, e.category == .strength else { continue }
            out.append(e.id)
        }
    }
    return out
}

/// Pick a workout to pin: a new one built on the spot (#282), My workouts, then the library.
struct ProgrammeWorkoutPicker: View {
    let pick: (ProgrammeWorkoutSource) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var building: CustomWorkout?
    @State private var built = false
    @State private var noMain = false
    @State private var gate: ProGate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    newCard
                    let mine = model.customWorkouts.map(ProgrammeWorkoutSource.init).filter { $0.mainCount > 0 }
                    if !mine.isEmpty {
                        Text("My workouts").eyebrow()
                        ForEach(mine) { row($0, colors: WorkoutEngine.Category.power.colors) }
                    }
                    Text("Library").eyebrow()
                    ForEach(WorkoutTemplate.all.map(ProgrammeWorkoutSource.init).filter { $0.mainCount > 0 }) {
                        row($0, colors: WorkoutEngine.Category.strength.colors)
                    }
                    Text("Its strength and power exercises become the signature workout; your warm-up and cool-down stay.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Pick a workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            // Saved to My workouts and pinned to the programme in one go.
            .sheet(item: $building, onDismiss: { if built { dismiss() } }) { w in
                CustomWorkoutEditor(initial: w) { saved in
                    let source = ProgrammeWorkoutSource(saved)
                    if source.mainCount > 0 {
                        pick(source)
                        built = true
                    } else {
                        noMain = true
                    }
                }
            }
            .alert("Saved to My workouts", isPresented: $noMain) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("A programme workout needs at least one strength or power exercise, so it was not added.")
            }
            .proPaywall($gate)
        }
    }

    private var newCard: some View {
        Button { ProStore.shared.run(.buildWorkout, $gate) { building = CustomWorkout(name: "") } } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 20, weight: .black))
                VStack(alignment: .leading, spacing: 2) {
                    Text("New workout").font(Theme.display(20))
                    Text("Build it now, it joins this programme").font(.caption.weight(.semibold)).opacity(0.75)
                }
                Spacer()
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Theme.lime, Color(red: 0.2, green: 0.9, blue: 0.6)],
                                     startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the workout builder; the saved workout is added to the programme")
    }

    private func row(_ w: ProgrammeWorkoutSource, colors: [Color]) -> some View {
        Button {
            pick(w)
            dismiss()
        } label: {
            HStack {
                Text(w.name).font(Theme.display(18)).lineLimit(1)
                Spacer()
                Text("\(w.mainCount) ex").font(Theme.label(13)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
    }
}

/// Bold settings row used by the editor and the builder.
private struct ProgrammeFieldRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(Theme.label(14))
            Spacer(minLength: 8)
            value
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }
}

/// Length chips 4…12 weeks.
private struct ProgrammeWeeksChips: View {
    @Binding var weeks: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(4...12, id: \.self) { w in
                    Button { weeks = w } label: {
                        Text("\(w)")
                            .font(Theme.display(17)).monospacedDigit()
                            .frame(width: 44, height: 44)
                            .foregroundStyle(w == weeks ? Theme.ink : .white)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(w == weeks ? Theme.lime : Theme.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(w) weeks")
                    .accessibilityAddTraits(w == weeks ? .isSelected : [])
                }
            }
        }
    }
}

/// Lifts tested in the last week, as toggle chips.
private struct ProgrammeLiftChips: View {
    let candidates: [String]
    @Binding var lifts: [String]

    var body: some View {
        if candidates.isEmpty {
            Text("Pin a workout with strength exercises to test a lift at the end.").font(.caption).foregroundStyle(Theme.muted)
        } else {
            ProgrammeChipFlow(items: candidates) { id in
                let on = lifts.contains(id)
                Button {
                    if on { lifts.removeAll { $0 == id } } else if lifts.count < 4 { lifts.append(id) }
                } label: {
                    Label(Exercise.get(id).name, systemImage: on ? "checkmark" : "plus")
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(on ? .white : .white.opacity(0.8))
                        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient(colors: ProgrammePhaseKind.test.colors,
                                                                                         startPoint: .leading, endPoint: .trailing))
                                                      : AnyShapeStyle(Theme.card)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Wrapping row of chips.
private struct ProgrammeChipFlow<Item: Hashable, Chip: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> Chip

    var body: some View {
        ProgrammeChipLayout(spacing: 6) { ForEach(items, id: \.self) { chip($0) } }
    }
}

private struct ProgrammeChipLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var cur: [Int] = [], x: CGFloat = 0, h: CGFloat = 0, y: CGFloat = 0
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !cur.isEmpty, x + s.width > width {
                rows.append((cur, y, x - spacing, h))
                y += h + spacing
                cur = []; x = 0; h = 0
            }
            cur.append(i)
            x += s.width + spacing
            h = max(h, s.height)
        }
        if !cur.isEmpty { rows.append((cur, y, x - spacing, h)) }
        return rows
    }
}

// MARK: Editor (design A)

/// One page to edit a member's programme: name, length, sessions, goal / split / method, signature workouts and test lifts.
struct ProgrammeEditorView: View {
    @State var programme: Programme
    let isNew: Bool
    /// The programme as it was when closed, brought back by Undo (#285).
    var restoring: Programme? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var confirmDelete = false
    @State private var start: Programme? = nil
    @State private var closeGuard = CloseGuard()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ProgrammeFieldRow(title: "Name") {
                        TextField("Programme name", text: $programme.name)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                            .submitLabel(.done)
                    }
                    Text("Length").eyebrow()
                    ProgrammeWeeksChips(weeks: Binding(get: { programme.weeks }, set: { setWeeks($0) }))
                    ProgrammePhaseStrip(programme: programme)
                    ProgrammeFieldRow(title: "Sessions a week") {
                        Stepper("\(programme.sessionsPerWeek)", value: $programme.sessionsPerWeek, in: 2...6)
                            .font(Theme.label(15)).fixedSize()
                    }
                    StackedMenuRow(title: "Goal", value: programme.goal.config.label) {
                        Picker("Goal", selection: $programme.goal) {
                            ForEach(Goal.allCases) { Text($0.config.label).tag($0) }
                        }
                    }
                    StackedMenuRow(title: "Split", value: programme.split == .auto ? "Built for the goal" : programme.split.title) {
                        Picker("Split", selection: $programme.split) {
                            ForEach(SplitStyle.allCases) { Text($0 == .auto ? "Built for the goal" : $0.title).tag($0) }
                        }
                    }
                    StackedMenuRow(title: "Method", value: programme.method.label) {
                        Picker("Method", selection: $programme.method) {
                            ForEach(TrainingMethod.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    HStack {
                        Text("Signature workouts").eyebrow()
                        Spacer()
                        Text("\(programme.signatures.count)").font(Theme.label(13)).foregroundStyle(Theme.lime)
                    }
                    ForEach(programme.signatures) { sig in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sig.name).font(Theme.display(17)).lineLimit(1)
                                Text(sig.items.prefix(3).map { Exercise.get($0.exerciseId).name }.joined(separator: " · "))
                                    .font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
                            }
                            Spacer()
                            Button { remove(sig) } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .heavy))
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(.white.opacity(0.2)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(sig.name)")
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(programme.gradient))
                    }
                    if programme.signatures.count < programme.sessionsPerWeek {
                        Button { adding = true } label: {
                            Label("Add a workout", systemImage: "plus")
                                .font(Theme.label(14))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .foregroundStyle(.white.opacity(0.85))
                                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [7, 6])))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Each one is pinned once a week and gets heavier as the phases go. The other days are built from your gym, days and goal.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Text("Test week lifts").eyebrow()
                    ProgrammeLiftChips(candidates: Array(Set(testableLifts(programme.signatures) + programme.lifts)).sorted {
                        Exercise.get($0).name < Exercise.get($1).name
                    }, lifts: Binding(get: { programme.lifts }, set: { setLifts($0) }))
                    Button {
                        save()
                    } label: {
                        Text("Save programme")
                            .font(Theme.display(17))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Theme.ink)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    if !isNew {
                        Button("Delete programme", role: .destructive) { confirmDelete = true }
                            .font(.footnote.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isNew ? "Make it mine" : "Edit programme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $adding) {
                ProgrammeWorkoutPicker { programme.signatures.append($0.signature(progression: true)) }
            }
            .confirmationDialog("Delete \(programme.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete programme", role: .destructive) {
                    closeGuard.done()
                    model.deleteProgramme(programme.id)
                    dismiss()
                }
            } message: {
                Text(model.activeProgramme?.programmeId == programme.id
                     ? "It keeps running until you leave or finish it."
                     : "Your workouts and history stay.")
            }
        }
        .onAppear {
            guard start == nil else { return }
            start = programme
            if let restoring { programme = restoring }
        }
        .undoableClose(closeGuard, offer: undoOffer)
    }

    /// Undo bar when anything changed since the editor opened (#285).
    private var undoOffer: UndoOffer? {
        guard let start, programme != start else { return nil }
        let kept = programme, new = isNew
        let detail = undoDetail(programme.name, programme.plan,
                                programme.signatures.isEmpty ? nil : "\(programme.signatures.count) pinned")
        return UndoOffer(title: new ? "Programme closed" : "Edit closed", detail: detail, symbol: programme.symbol,
                         colors: programme.palette.colors) {
            AnyView(ProgrammeEditorView(programme: start, isNew: new, restoring: kept))
        }
    }

    private func setWeeks(_ w: Int) {
        guard w != programme.weeks else { return }
        programme.phases = Programme.phases(weeks: w, test: !programme.lifts.isEmpty)
    }

    private func setLifts(_ l: [String]) {
        let hadTest = !programme.lifts.isEmpty
        programme.lifts = l
        if hadTest != !l.isEmpty { programme.phases = Programme.phases(weeks: programme.weeks, test: !l.isEmpty) }
    }

    private func remove(_ sig: ProgrammeSignature) {
        programme.signatures.removeAll { $0.id == sig.id }
        let left = Set(testableLifts(programme.signatures) + (programme.basedOn.flatMap { Programme.find($0) }?.lifts ?? []))
        setLifts(programme.lifts.filter { left.contains($0) })
    }

    private func save() {
        var p = programme
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.name.isEmpty { p.name = "My programme" }
        p.tagline = "My programme · \(p.sessionsPerWeek)× a week"
        model.saveProgramme(p)
        closeGuard.done()
        dismiss()
    }
}

// MARK: Builder (design B)

/// New programme in 4 steps: what for, length and sessions, the week's workouts, test lifts.
struct ProgrammeBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var goal: Goal?
    @State private var name = ""
    @State private var weeks = 8
    @State private var sessions = 3
    /// Workout per day; nil = built by the app.
    @State private var days: [ProgrammeWorkoutSource?] = Array(repeating: nil, count: 3)
    @State private var progression = true
    @State private var lifts: [String] = []
    @State private var pickingDay: Int?
    @State private var closeGuard = CloseGuard()

    /// Every answer and the step, kept for Undo (#285). `Draft()` is the untouched builder.
    struct Draft: Equatable {
        var step = 0
        var goal: Goal?
        var name = ""
        var weeks = 8
        var sessions = 3
        var days: [ProgrammeWorkoutSource?] = Array(repeating: nil, count: 3)
        var progression = true
        var lifts: [String] = []
    }

    init(restoring: Draft? = nil) {
        let d = restoring ?? Draft()
        _step = State(initialValue: d.step)
        _goal = State(initialValue: d.goal)
        _name = State(initialValue: d.name)
        _weeks = State(initialValue: d.weeks)
        _sessions = State(initialValue: d.sessions)
        _days = State(initialValue: d.days)
        _progression = State(initialValue: d.progression)
        _lifts = State(initialValue: d.lifts)
    }

    private var answers: Draft {
        Draft(step: step, goal: goal, name: name, weeks: weeks, sessions: sessions, days: days, progression: progression, lifts: lifts)
    }

    /// Undo bar once any step was answered (#285).
    private var undoOffer: UndoOffer? {
        let kept = answers
        guard kept != Draft() else { return nil }
        let d = goal.map { Programme.defaults(for: $0) }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = undoDetail("Step \(step + 1) of 4", goal?.config.label, n)
        return UndoOffer(title: "Programme closed", detail: detail, symbol: d?.symbol ?? "calendar",
                         colors: (d?.palette ?? .strength).colors) {
            AnyView(ProgrammeBuilderView(restoring: kept))
        }
    }

    private static let goals: [Goal] = [.strength, .build, .athletic, .climbing, .balanced, .endurance]
    private static let titles = ["What for?", "How long?", "Your week", "Test lifts"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { i in
                            Capsule().fill(i <= step ? Theme.lime : Theme.card).frame(height: 6)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(step + 1) of 4")
                    Text("\(step + 1) · \(Self.titles[step])").eyebrow()
                    switch step {
                    case 0: goalStep
                    case 1: lengthStep
                    case 2: weekStep
                    default: liftsStep
                    }
                    HStack(spacing: 10) {
                        if step > 0 {
                            Button { step -= 1 } label: {
                                Text("Back").font(Theme.display(17)).frame(maxWidth: .infinity, minHeight: 52)
                                    .foregroundStyle(.white).background(Capsule().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                        Button { if step < 3 { step += 1 } else { save() } } label: {
                            Text(step < 3 ? "Next: \(Self.titles[step + 1].lowercased())" : "Save programme")
                                .font(Theme.display(17)).frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.lime))
                        }
                        .buttonStyle(.plain)
                        .disabled(step == 0 && goal == nil)
                        .opacity(step == 0 && goal == nil ? 0.4 : 1)
                    }
                    .padding(.top, 6)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("New programme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .sheet(item: Binding(get: { pickingDay.map(DayIndex.init) }, set: { pickingDay = $0?.id })) { d in
                ProgrammeWorkoutPicker { days[d.id] = $0 }
            }
            .onAppear(perform: demo)
        }
        .undoableClose(closeGuard, offer: undoOffer)
    }

    private struct DayIndex: Identifiable {
        let id: Int
    }

    private var goalStep: some View {
        ForEach(Self.goals) { g in
            let d = Programme.defaults(for: g)
            Button { goal = g } label: {
                HStack(spacing: 12) {
                    Image(systemName: d.symbol).font(.system(size: 20, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.config.label).font(Theme.display(19))
                        Text(g.config.blurb).font(.caption.weight(.semibold)).opacity(0.88).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(d.palette.gradient))
                .overlay { if goal == g { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.lime, lineWidth: 3) } }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(goal == g ? .isSelected : [])
        }
    }

    private var lengthStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgrammeFieldRow(title: "Name") {
                TextField(defaultName, text: $name).multilineTextAlignment(.trailing).font(.body.weight(.semibold))
            }
            Text("Weeks").eyebrow()
            ProgrammeWeeksChips(weeks: $weeks)
            ProgrammePhaseStrip(programme: draft)
            ProgrammeFieldRow(title: "Sessions a week") {
                Stepper("\(sessions)", value: Binding(get: { sessions }, set: { setSessions($0) }), in: 2...6)
                    .font(Theme.label(15)).fixedSize()
            }
            Text("Base and Build take most of it, then a heaviest week, an easy week from 6 weeks on, and a test week if you pick lifts to test.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private var weekStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<sessions, id: \.self) { i in
                Button { pickingDay = i } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Day \(i + 1)").font(Theme.display(18))
                            Text(days[i]?.name ?? "The app builds it from your gym and goal").font(.caption.weight(.semibold)).opacity(0.85)
                        }
                        Spacer()
                        Text(days[i] == nil ? "AUTO" : "SIGNATURE").font(Theme.label(10)).tracking(1).opacity(0.85)
                        if days[i] != nil {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
                                .frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.2)))
                                .onTapGesture { days[i] = nil }
                                .accessibilityLabel("Back to auto")
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background {
                        if days[i] == nil {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(draft.gradient)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Tap a day to pin one of your workouts or a library workout. Auto days follow your goal.")
                .font(.caption).foregroundStyle(Theme.muted)
            Toggle(isOn: $progression) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heavier as the phases go").font(Theme.label(14))
                    Text("Base as written · Build 2 fewer reps · Peak about half · Ease one set less")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.lime)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        }
    }

    private var liftsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgrammeLiftChips(candidates: testableLifts(signatures), lifts: $lifts)
            Text(lifts.isEmpty
                 ? "No lifts: the programme ends with an easy week instead of a test."
                 : "The last week is a test week with a PR attempt for each lift; Progress compares them with your start.")
                .font(.caption).foregroundStyle(Theme.muted)
            ProgrammeCard(programme: draft)
        }
    }

    private var defaultName: String { "My \((goal ?? .balanced).config.label.lowercased()) programme" }

    private var signatures: [ProgrammeSignature] {
        days.prefix(sessions).compactMap { $0 }.enumerated().map { i, w in
            var s = w.signature(progression: progression)
            s.id = "sig-\(i + 1)"
            return s
        }
    }

    private var draft: Programme {
        let g = goal ?? .balanced
        let d = Programme.defaults(for: g)
        let sigs = signatures
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Programme(
            id: Programme.minePrefix + "draft", name: n.isEmpty ? defaultName : n,
            tagline: "My programme · \(sessions)× a week",
            summary: sigs.isEmpty ? "Your own programme: \(g.config.blurb)"
                : "Your own programme with " + sigs.map(\.name).joined(separator: ", ") + " every week.",
            symbol: d.symbol, palette: d.palette, goal: g, sessionsPerWeek: sessions, split: d.split, method: d.method,
            focusMuscles: g == .climbing ? [.back, .core] : [],
            phases: Programme.phases(weeks: weeks, test: !lifts.isEmpty), signatures: sigs, lifts: lifts)
    }

    private func setSessions(_ n: Int) {
        sessions = n
        if days.count < n { days += Array(repeating: nil, count: n - days.count) }
    }

    private func save() {
        var p = draft
        p.id = Programme.minePrefix + UUID().uuidString.lowercased()
        model.saveProgramme(p)
        closeGuard.done()
        dismiss()
    }

    private func demo() {
        #if DEBUG
        guard Demo.enabled, Demo.screen.hasPrefix("programme-builder") else { return }
        goal = .athletic
        if Demo.screen == "programme-builder-week" {
            step = 2
            days[0] = WorkoutTemplate.all.first { $0.id == "posterior-chain" }.map(ProgrammeWorkoutSource.init)
            days[2] = WorkoutTemplate.all.first { $0.id == "push-power" }.map(ProgrammeWorkoutSource.init)
        }
        #endif
    }
}
