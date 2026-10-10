import SwiftUI
import WorkoutEngine

// MARK: - Train tab section

/// "My workouts" on the Train tab: the user's own workouts, plus entry points to build one.
struct MyWorkoutsSection: View {
    @Environment(AppModel.self) private var model
    @State private var editing: CustomWorkout?
    @State private var confirmDelete: CustomWorkout?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My workouts").eyebrow()
                Spacer()
                Button { editing = CustomWorkout(name: "") } label: {
                    Label("New", systemImage: "plus")
                }
                .font(Theme.label(13))
                .foregroundStyle(Theme.lime)
            }
            if model.customWorkouts.isEmpty {
                Button { editing = CustomWorkout(name: "") } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.pencil").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.lime)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Build your own workout").font(.system(.headline, design: .rounded).weight(.heavy))
                            Text("Pick exercises, sets × reps and rest — or duplicate an example below.")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            } else {
                ForEach(model.customWorkouts) { w in
                    NavigationLink(value: w.sessionId) {
                        CustomWorkoutRowCard(workout: w, done: model.state.done[w.sessionId] ?? false)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = w }
                        Button("Duplicate", systemImage: "plus.square.on.square") { _ = model.saveCustomWorkout(w.duplicated()) }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = w }
                    }
                }
            }
        }
        .sheet(item: $editing) { w in CustomWorkoutEditor(initial: w) }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible,
            presenting: confirmDelete
        ) { w in
            Button("Delete “\(w.name)”", role: .destructive) { model.deleteCustomWorkout(w.id) }
        } message: { _ in
            Text("Past sessions stay in your history.")
        }
    }
}

/// Custom workout row: name, duration, exercise count, calories and main muscles.
struct CustomWorkoutRowCard: View {
    let workout: CustomWorkout
    let done: Bool

    var body: some View {
        let session = workout.session
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workout.name).font(.system(.headline, design: .rounded).weight(.heavy)).lineLimit(1)
                Spacer()
                if done {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.lime)
                } else {
                    Text("\(session.estMin)′").font(Theme.label(14)).foregroundStyle(Theme.muted)
                }
            }
            Text(([workout.kcal.map { "\($0) kcal" }, "\(workout.playableItems.count) exercises"] as [String?]).compactMap { $0 }.joined(separator: " · "))
                .font(.caption.weight(.semibold))
            Text(session.topMuscles(4).map(\.name).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .card()
    }
}

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
    @State private var confirmDelete = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { actions }
            }
            .sheet(item: $editing) { w in CustomWorkoutEditor(initial: w) }
            .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let w = model.customWorkout(sessionId: session.id) else { return }
                    dismiss()
                    model.deleteCustomWorkout(w.id)
                }
            } message: {
                Text("Past sessions stay in your history.")
            }
    }

    @ViewBuilder
    private var actions: some View {
        if let w = model.customWorkout(sessionId: session.id) {
            Menu {
                Button("Edit", systemImage: "pencil") { editing = w }
                Button("Duplicate", systemImage: "plus.square.on.square") { editing = w.duplicated() }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Workout actions")
        } else if let t = WorkoutTemplate.find(sessionId: session.id) {
            Button { editing = CustomWorkout(duplicating: t) } label: {
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
    @State private var confirmDiscard = false
    private let initial: CustomWorkout

    init(initial: CustomWorkout) {
        self.initial = initial
        _draft = State(initialValue: initial)
    }

    private var isNew: Bool { model.customWorkout(initial.id) == nil }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !draft.playableItems.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Push day", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: draft.name) { _, v in
                            if v.count > CustomWorkout.maxNameLength { draft.name = String(v.prefix(CustomWorkout.maxNameLength)) }
                        }
                }

                Section {
                    ForEach($draft.items) { $item in
                        NavigationLink {
                            CustomItemForm(item: $item)
                        } label: {
                            CustomItemRow(item: item)
                        }
                    }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                    .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }

                    if draft.items.count < CustomWorkout.maxItems {
                        Button { picking = true } label: {
                            Label("Add exercises", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    HStack {
                        Text("Exercises · \(draft.items.count)")
                        Spacer()
                        if !draft.items.isEmpty {
                            Button(editMode.isEditing ? "Done" : "Reorder") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                } footer: {
                    if draft.items.isEmpty {
                        Text("Add at least one exercise from the catalog.")
                    } else {
                        Text("Tap an exercise to set sets × reps, rest and calories. Swipe to remove.")
                    }
                }

                if !draft.items.isEmpty {
                    Section {
                        LabeledContent("Estimated duration", value: "\(draft.session.estMin) min")
                        if let kcal = draft.kcal { LabeledContent("Calories", value: "\(kcal) kcal") }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .themedForm()
            .navigationTitle(isNew ? "New workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if draft != initial && !(isNew && draft.items.isEmpty && trimmedName.isEmpty) { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveCustomWorkout(draft)
                        dismiss()
                    }
                    .bold()
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $picking) {
                ExercisePickerView(limit: CustomWorkout.maxItems - draft.items.count) { picked in
                    draft.items += picked.map { CustomWorkout.Item(adding: $0) }
                }
            }
        }
        .interactiveDismissDisabled(draft != initial)
    }
}

private struct CustomItemRow: View {
    let item: CustomWorkout.Item

    var body: some View {
        if let e = item.exercise {
            let measure = CustomWorkout.Measure(e)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(.body.weight(.semibold))
                Text(([
                    item.sets > 1 ? "\(item.sets) × \(measure.text(item.reps))" : measure.text(item.reps),
                    item.restSec > 0 ? "rest \(Format.rest(item.restSec))" : nil,
                    item.kcal.map { "\($0) kcal" },
                ] as [String?]).compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(e.category.color)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Unavailable exercise").font(.body.weight(.semibold)).foregroundStyle(Theme.muted)
                Text("Update the app to use “\(item.exerciseId)”.").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Per-exercise settings: sets, reps (or seconds / minutes), rest and optional calories.
private struct CustomItemForm: View {
    @Binding var item: CustomWorkout.Item
    @State private var info = false

    var body: some View {
        Form {
            if let e = item.exercise {
                let measure = CustomWorkout.Measure(e)
                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            CategoryPill(category: e.category, compact: true)
                            Text(e.name).font(.headline)
                            Text(e.muscles.prefix(4).map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button { info = true } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Exercise details")
                    }
                }
                Section("Prescription") {
                    Stepper(value: $item.sets, in: CustomWorkout.setsRange) {
                        LabeledContent("Sets", value: "\(item.sets)")
                    }
                    Stepper(value: $item.reps, in: CustomWorkout.repsRange, step: measure.step) {
                        LabeledContent("\(measure.label) per set", value: "\(item.reps)")
                    }
                    Stepper(value: $item.restSec, in: CustomWorkout.restRange, step: 15) {
                        LabeledContent("Rest", value: item.restSec > 0 ? Format.rest(item.restSec) : "None")
                    }
                }
                Section {
                    LabeledContent("Calories") {
                        TextField("optional", value: $item.kcal, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Optional — e.g. what your machine or tracker shows for this exercise.")
                }
            } else {
                Text("This exercise isn't in this version of the app.").foregroundStyle(Theme.muted)
            }
        }
        .sheet(isPresented: $info) {
            if let e = item.exercise {
                NavigationStack { ExerciseDetailView(exerciseId: e.id) }
            }
        }
        .themedForm()
        .navigationTitle(item.exercise?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Exercise picker

/// Catalog browser for the builder: search plus category and muscle filters; multi-select in tap order.
struct ExercisePickerView: View {
    let limit: Int
    let onAdd: ([Exercise]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: WorkoutEngine.Category?
    @State private var muscle: Muscle?
    @State private var selected: [String] = []

    private var results: [Exercise] { Exercise.search(query, category: category, muscle: muscle) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(WorkoutEngine.Category?.none)
                        ForEach(WorkoutEngine.Category.allCases) { c in
                            Text(c.label).tag(WorkoutEngine.Category?.some(c))
                        }
                    }
                    Picker("Muscle", selection: $muscle) {
                        Text("All muscles").tag(Muscle?.none)
                        ForEach(Muscle.allCases) { m in
                            Text(m.name).tag(Muscle?.some(m))
                        }
                    }
                }
                Section {
                    ForEach(results) { e in
                        Button { toggle(e) } label: { row(e) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(results.count) exercises")
                }
            }
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .themedForm()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, muscle or equipment")
            .navigationTitle("Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") {
                        onAdd(selected.compactMap { Exercise.find($0) })
                        dismiss()
                    }
                    .bold()
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func toggle(_ e: Exercise) {
        if let i = selected.firstIndex(of: e.id) {
            selected.remove(at: i)
        } else if selected.count < limit {
            selected.append(e.id)
        }
    }

    private func row(_ e: Exercise) -> some View {
        let order = selected.firstIndex(of: e.id)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(order == nil ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(Theme.lime))
                    .frame(width: 30, height: 30)
                if let order {
                    Text("\(order + 1)").font(Theme.label(13)).foregroundStyle(Theme.ink)
                } else {
                    Image(systemName: e.category.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(e.category.color)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                Text(([e.category.label] + e.primary.map(\.name)).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(order == nil ? [] : .isSelected)
    }
}
