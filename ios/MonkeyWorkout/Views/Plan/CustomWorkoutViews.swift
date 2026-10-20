import SwiftUI
import WorkoutEngine

// MARK: - Session view hook

extension View {
    /// Toolbar actions for example (duplicate) and custom (edit, duplicate, delete) workouts.
    func standaloneWorkoutActions(_ session: Session) -> some View {
        modifier(StandaloneWorkoutActions(session: session))
    }
}

private struct StandaloneWorkoutActions: ViewModifier {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CustomWorkout?
    @State private var gate: ProGate?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { actions }
            }
            .sheet(item: $editing) { w in CustomWorkoutEditor(initial: w) }
            .proPaywall($gate)
    }

    /// Deleted at once (#539); Undo saves it back. Past sessions stay in history either way.
    private func delete(_ w: CustomWorkout) {
        dismiss()
        model.deleteCustomWorkout(w.id)
        UndoCloseCenter.shared.deleted("\(w.name) deleted", detail: "Past sessions stay in your history", symbol: "dumbbell.fill") { [model] in
            model.saveCustomWorkout(w)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let w = model.customWorkout(sessionId: session.id) {
            Menu {
                Button("Edit", systemImage: "pencil") { editing = w }
                Button("Duplicate", systemImage: "plus.square.on.square") { ProStore.shared.run(.buildWorkout, $gate) { editing = w.duplicated() } }
                Button("Delete", systemImage: "trash", role: .destructive) { delete(w) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Workout actions")
        } else if let t = WorkoutTemplate.find(sessionId: session.id) {
            Button { ProStore.shared.run(.buildWorkout, $gate) { editing = CustomWorkout(duplicating: t) } } label: {
                Label("Duplicate & edit", systemImage: "plus.square.on.square")
            }
        }
    }
}

// MARK: - Builder

/// Create or edit a custom workout: name, exercises (add, reorder, remove) and each one's sets × reps, rest and calories.
struct CustomWorkoutEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomWorkout
    @State private var picking = false
    @State private var editMode: EditMode = .inactive
    @State private var closeGuard = CloseGuard()
    @State private var generating = false
    /// Last generator choices (#119), kept so "Generate again" starts from them.
    @State private var generated: MuscleWorkoutOptions?
    @State private var gate: ProGate?
    /// Quick start of a generated workout: saved first, then played now or placed on a day of this week.
    @State private var saved = false
    @State private var playing = false
    @State private var planning = false
    @State private var planned = false
    /// Session flow (#198): minutes of the blocks played around the exercises.
    @State private var flowMinutes: [BlockKind: Int]
    /// Warm-up / cool-down style or exact moves (#293).
    @State private var tweaks: FlowTweaks
    @State private var tweaking: FlowTweakTarget?
    /// Editing a saved workout (not a new one, not one for a day): saves on its own (#437). Fixed on appear.
    @State private var autoSaving: Bool?
    /// A blank new workout's typing kept on the device until saved (#437).
    @State private var draftKey: String?
    @State private var draftRestored = false
    private let initial: CustomWorkout
    /// Set when building a workout for a day (#178): Save saves it and hands it over (the caller places it).
    private let onSave: ((CustomWorkout) -> Void)?

    /// What's entered, brought back by Undo (#285).
    struct Restore {
        var draft: CustomWorkout
        var generated: MuscleWorkoutOptions?
        var flowMinutes: [BlockKind: Int]
        var tweaks: FlowTweaks? = nil
    }

    /// `generated`: the generator choices behind `initial`, when it was just generated (shows the quick start).
    init(initial: CustomWorkout, generated: MuscleWorkoutOptions? = nil, restoring: Restore? = nil,
         onSave: ((CustomWorkout) -> Void)? = nil) {
        self.initial = initial
        self.onSave = onSave
        _draft = State(initialValue: restoring?.draft ?? initial)
        _generated = State(initialValue: restoring?.generated ?? generated)
        // New workouts start with a warm-up and a cool-down; saved ones keep theirs.
        let fresh = initial.flow.isEmpty && (initial.items.isEmpty || generated != nil)
        _flowMinutes = State(initialValue: restoring?.flowMinutes ?? (fresh ? [.warmup: 6, .cooldown: 5] : initial.flowMinutes))
        _tweaks = State(initialValue: restoring?.tweaks ?? initial.flowTweaks ?? FlowTweaks())
    }

    private var isNew: Bool { model.customWorkout(initial.id) == nil }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !draft.playableItems.isEmpty }

    var body: some View {
        NavigationStack {
            // A plain List keeps swipe-to-delete and reorder; each row is drawn as an Explore-style card.
            List {
                if draftRestored {
                    DraftRestoredStrip {
                        if let draftKey { DraftStore.clear(draftKey) }
                        draft = initial
                        draftRestored = false
                    }
                    .cardRow()
                }
                AccountField(label: "Name") {
                    TextField("e.g. Push day", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .font(Theme.display(22))
                        .onChange(of: draft.name) { _, v in
                            if v.count > CustomWorkout.maxNameLength { draft.name = String(v.prefix(CustomWorkout.maxNameLength)) }
                        }
                }
                .cardRow()

                HStack {
                    Text("Exercises · \(draft.items.count)").eyebrow()
                    Spacer()
                    if !draft.items.isEmpty {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.lime)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.top, 8)
                .cardRow()

                if model.profile != nil {
                    GenerateWorkoutCard(regenerate: !draft.items.isEmpty) {
                        ProStore.shared.run(.generateWorkout, $gate) { generating = true }
                    }
                        .cardRow()
                }

                let labels = draft.groupLabels
                ForEach($draft.items) { $item in
                    ZStack {
                        // Hidden link: the card draws its own chevron instead of the List's disclosure.
                        NavigationLink { CustomItemForm(item: $item) } label: { EmptyView() }.opacity(0)
                        CustomItemRow(item: item, group: labels[item.id])
                    }
                    .cardRow()
                }
                .onDelete { draft.items.remove(atOffsets: $0) }
                .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }

                if draft.items.count < CustomWorkout.maxItems {
                    Button { picking = true } label: {
                        Label("Add exercises", systemImage: "plus.circle.fill")
                            .font(Theme.label(15))
                            .foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }
                    .buttonStyle(.borderless)
                    .cardRow()
                }

                AccountNote(text: draft.items.isEmpty
                            ? "Add at least one exercise from the catalog."
                            : draft.groupLabels.isEmpty
                                ? "Tap an exercise to set sets × reps, rest and calories. Swipe to remove."
                                : "Same letter = back to back (A1 → A2), rest after the round. Tap an exercise to edit, swipe to remove.")
                    .cardRow()

                if !draft.items.isEmpty {
                    Text("Session flow").eyebrow().padding(.top, 8).cardRow()
                    CustomFlowEditor(minutes: $flowMinutes, yours: draft.ownMinutes) { tweaking = FlowTweakTarget(kind: $0) }.cardRow()
                    AccountNote(text: "Tap Warm-up or Cool-down to pick a style or your own moves. Mobility and cardio are picked to match your exercises and gym. Drag the bar to resize.")
                        .cardRow()
                    AccountCard(symbol: "stopwatch.fill", title: "Estimated duration",
                                subtitle: draft.kcal.map { "\($0) kcal" }, gradient: WorkoutEngine.Category.cardio.gradient) {
                        AccountValue(value: "\(draft.session.estMin)", unit: "min")
                    }
                    .cardRow()
                }

                if generated != nil && canSave && onSave == nil {
                    HStack(spacing: 10) {
                        QuickActionCard(title: "Start now", symbol: "play.fill", gradient: WorkoutEngine.Category.strength.gradient) {
                            ProStore.shared.run(.generateWorkout, $gate) { saveThen { playing = true } }
                        }
                        QuickActionCard(title: "Add to a day", symbol: "calendar.badge.plus", gradient: WorkoutEngine.Category.mobility.gradient) {
                            ProStore.shared.run(.generateWorkout, $gate) { saveThen { planning = true } }
                        }
                    }
                    .cardRow()
                    AccountNote(text: "Saves it to your workouts. Your plan stays as it is: Add to a day places it in this week only.")
                        .cardRow()
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .themedForm()
            .navigationTitle(isNew ? "New workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Closes at once; with unsaved changes the Undo bar brings them back (#285). The old "Discard changes?"
                // dialog didn't show on iOS 26, so Cancel did nothing and swipe-down was blocked.
                // Standard chrome (#539): a new workout has Save (Add) beside the X; a saved one saves on its own.
                if autoSaving != true {
                    SaveToolbarItem(title: onSave == nil ? "Save" : "Add", disabled: !canSave) {
                        if let draftKey { DraftStore.clear(draftKey) }
                        closeGuard.done()
                        model.saveCustomWorkout(draft)
                        onSave?(draft)
                        dismiss()
                    }
                }
                CloseToolbarItem { dismiss() }
            }
            // Edits to a saved workout save on their own (#437); an empty name or no exercises waits.
            .autoSave(autoSaving == true && canSave ? draft : nil, title: "Workout", symbol: "dumbbell.fill",
                      detail: { w in undoDetail(w.name, "\(w.items.count) exercise\(w.items.count == 1 ? "" : "s")") },
                      save: { [model] in model.saveCustomWorkout($0) })
            .sheet(item: $tweaking) { t in
                FlowTweakSheet(kind: t.kind, tweaks: $tweaks, preview: { previewFlow($0, t.kind) }) {
                    flowMinutes[t.kind] = nil
                    tweaks.setMoves(nil, for: t.kind)
                }
            }
            .sheet(isPresented: $picking) {
                ExercisePickerView(limit: CustomWorkout.maxItems - draft.items.count) { picked in
                    draft.items += picked.map { CustomWorkout.Item(adding: $0) }
                }
            }
            .proPaywall($gate)
            .fullScreenCover(isPresented: $playing, onDismiss: { dismiss() }) {
                WorkoutPlayerView(sessionId: draft.sessionId)
            }
            .sheet(isPresented: $planning, onDismiss: { if planned { dismiss() } }) {
                AddToPlanSheet(workout: draft) { _ in planned = true }
            }
            .sheet(isPresented: $generating) {
                if let profile = model.profile {
                    MuscleWorkoutGeneratorSheet(profile: profile, options: generated, replacing: !draft.items.isEmpty) { w, options in
                        // The name follows the muscles unless the user typed their own.
                        let previous = generated.map { CustomWorkout.generatedName($0.groups) }
                        if trimmedName.isEmpty || trimmedName == previous { draft.name = w.name }
                        draft.items = w.items
                        generated = options
                    }
                }
            }
        }
        .undoableClose(closeGuard, offer: undoOffer)
        .onChange(of: draft) { _, d in
            guard let draftKey else { return }
            if d.items.isEmpty && d.name.trimmingCharacters(in: .whitespaces).isEmpty { DraftStore.clear(draftKey) } else { DraftStore.save(draftKey, d) }
        }
        .onAppear {
            if autoSaving == nil {
                autoSaving = !isNew && onSave == nil
                // Blank new workout: bring back what was typed last time.
                if isNew, onSave == nil, generated == nil, initial.items.isEmpty, initial.name.isEmpty, draft == initial {
                    draftKey = "custom-workout"
                    if let d = DraftStore.load("custom-workout", as: CustomWorkout.self), !d.items.isEmpty || !d.name.isEmpty {
                        draft = d
                        draftRestored = true
                    }
                }
            }
            if initial.flow.isEmpty { rebuildFlow() }
        }
        .onChange(of: flowMinutes) { rebuildFlow() }
        .onChange(of: tweaks) { rebuildFlow() }
        .onChange(of: draft.items) { rebuildFlow() }
    }

    /// Undo bar when the workout was changed and not saved (#285).
    private var undoOffer: UndoOffer? {
        guard autoSaving != true, !saved, draft != initial, !(isNew && draft.items.isEmpty && trimmedName.isEmpty) else { return nil }
        let kept = Restore(draft: draft, generated: generated, flowMinutes: flowMinutes, tweaks: tweaks)
        let original = self.initial, save = self.onSave
        let n = draft.items.count
        return UndoOffer(title: isNew ? "New workout closed" : "Edit closed",
                         detail: undoDetail(trimmedName, "\(n) exercise\(n == 1 ? "" : "s")"), symbol: "dumbbell.fill",
                         colors: WorkoutEngine.Category.strength.colors) {
            AnyView(CustomWorkoutEditor(initial: original, restoring: kept, onSave: save))
        }
    }

    /// Picks the flow blocks again for the current minutes and exercises.
    private func rebuildFlow() {
        guard let profile = model.profile else { return }
        // Exact moves set their block's time (#293).
        for k in FlowTweaks.kinds {
            if let m = tweaks.movesMinutes(k), let cur = flowMinutes[k], cur != m { flowMinutes[k] = m }
        }
        let kept = tweaks.isEmpty ? nil : tweaks
        if draft.flowTweaks != kept { draft.flowTweaks = kept }
        let next = draft.withFlow(flowMinutes, profile: profile.applying(tweaks))
        if next.flow != draft.flow { draft.flow = next.flow }
    }

    /// Moves `kind` gets with `t` (the warm-up / cool-down sheet's list).
    private func previewFlow(_ t: FlowTweaks, _ kind: BlockKind) -> [PlannedExercise] {
        guard let profile = model.profile else { return [] }
        var m = flowMinutes
        if m[kind] == nil { m[kind] = CustomFlowEditor.defaults[kind] }
        return draft.withFlow(m, profile: profile.applying(t)).flow.first { $0.kind == kind }?.items ?? []
    }

    /// Saves the draft (once per change), then runs `next`.
    private func saveThen(_ next: () -> Void) {
        if let draftKey { DraftStore.clear(draftKey) }
        model.saveCustomWorkout(draft)
        saved = true
        closeGuard.done()
        next()
    }
}

/// Half-width vivid action card (icon tile over a heavy label) for the builder's quick start.
private struct QuickActionCard: View {
    let title: String
    let symbol: String
    let gradient: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    IconTile(symbol: symbol, size: 40)
                    Spacer(minLength: 4)
                    ProBadge()
                }
                Text(title).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gradientCard(gradient, padding: 14)
        }
        .buttonStyle(.borderless)
    }
}

extension View {
    /// List row without system chrome, so the content's own card shows. Shared by the gradient-row lists (#539).
    func cardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}

/// Exercise in the builder: category gradient card, icon tile, name, prescription.
private struct CustomItemRow: View {
    let item: CustomWorkout.Item
    /// Superset / circuit label ("A1"), when grouped.
    var group: String?

    var body: some View {
        if let e = item.exercise {
            let measure = CustomWorkout.Measure(e)
            HStack(spacing: 14) {
                IconTile(symbol: e.category.symbol, size: 44, ink: e.category.isLight)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let group {
                            Text(group)
                                .font(Theme.label(11))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.lime))
                                .accessibilityLabel("Group \(group)")
                        }
                        Text(e.name).font(Theme.display(17)).lineLimit(2).minimumScaleFactor(0.8)
                    }
                    Text(([
                        item.sets > 1 ? "\(item.sets) × \(measure.text(item.reps))" : measure.text(item.reps),
                        item.restSec > 0 ? "rest \(Format.rest(item.restSec))" : nil,
                        item.kcal.map { "\($0) kcal" },
                    ] as [String?]).compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote.weight(.semibold))
                        .opacity(0.88)
                }
                Spacer(minLength: 4)
                AccountChevron()
            }
            .gradientCard(e.category.gradient, padding: 14, ink: e.category.ink)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Unavailable exercise").font(.body.weight(.semibold)).foregroundStyle(Theme.muted)
                Text("Update the app to use \u{201C}\(item.exerciseId)\u{201D}.").font(.caption).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
    }
}

/// Per-exercise settings: sets, reps (or seconds / minutes), rest and optional calories.
private struct CustomItemForm: View {
    @Binding var item: CustomWorkout.Item
    @State private var info = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let e = item.exercise {
                    let measure = CustomWorkout.Measure(e)
                    AccountHeader(symbol: e.category.symbol, title: e.name,
                                  subtitle: e.muscles.prefix(4).map(\.name).joined(separator: " · "), gradient: e.category.gradient) {
                        Button { info = true } label: { Image(systemName: "info.circle.fill").font(.title2) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Exercise details")
                    }
                    Text("Prescription").eyebrow().padding(.top, 6)
                    stepperCard(symbol: "square.stack.3d.up.fill", title: "Sets", value: "\(item.sets)",
                                gradient: WorkoutEngine.Category.strength.gradient) {
                        Stepper("Sets", value: $item.sets, in: CustomWorkout.setsRange)
                    }
                    stepperCard(symbol: "repeat", title: "\(measure.label) per set", value: "\(item.reps)",
                                gradient: WorkoutEngine.Category.power.gradient) {
                        Stepper("\(measure.label) per set", value: $item.reps, in: CustomWorkout.repsRange, step: measure.step)
                    }
                    stepperCard(symbol: "timer", title: "Rest", value: item.restSec > 0 ? Format.rest(item.restSec) : "None",
                                gradient: WorkoutEngine.Category.cardio.gradient) {
                        Stepper("Rest", value: $item.restSec, in: CustomWorkout.restRange, step: 15)
                    }
                    AccountField(label: "Calories") {
                        TextField("optional", value: $item.kcal, format: .number)
                            .keyboardType(.numberPad)
                    }
                    .padding(.top, 6)
                    AccountNote(text: "Optional — e.g. what your machine or tracker shows for this exercise.")
                } else {
                    Text("This exercise isn't in this version of the app.").foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
        }
        .readableWidth()
        .sheet(isPresented: $info) {
            if let e = item.exercise {
                NavigationStack { ExerciseDetailView(exerciseId: e.id) }
            }
        }
        .themedForm()
        .navigationTitle("Sets & reps")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Explore-style card: icon tile, label, big value and a stepper on the right.
    private func stepperCard<S: View>(symbol: String, title: String, value: String, gradient: LinearGradient,
                                      @ViewBuilder stepper: () -> S) -> some View {
        let control = stepper()
        return AccountCard(symbol: symbol, title: title, gradient: gradient) {
            HStack(spacing: 10) {
                Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                control.labelsHidden().fixedSize()
            }
        }
    }
}
