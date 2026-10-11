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
            // A plain List keeps swipe-to-delete and reorder; each row is drawn as an Explore-style card.
            List {
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

                ForEach($draft.items) { $item in
                    ZStack {
                        // Hidden link: the card draws its own chevron instead of the List's disclosure.
                        NavigationLink { CustomItemForm(item: $item) } label: { EmptyView() }.opacity(0)
                        CustomItemRow(item: item)
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
                            : "Tap an exercise to set sets × reps, rest and calories. Swipe to remove.")
                    .cardRow()

                if !draft.items.isEmpty {
                    AccountCard(symbol: "stopwatch.fill", title: "Estimated duration",
                                subtitle: draft.kcal.map { "\($0) kcal" }, gradient: WorkoutEngine.Category.cardio.gradient) {
                        AccountValue(value: "\(draft.session.estMin)", unit: "min")
                    }
                    .cardRow()
                }
            }
            .listStyle(.plain)
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

private extension View {
    /// List row without system chrome, so the content's own card shows.
    func cardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}

/// Exercise in the builder: category gradient card, icon tile, name, prescription.
private struct CustomItemRow: View {
    let item: CustomWorkout.Item

    var body: some View {
        if let e = item.exercise {
            let measure = CustomWorkout.Measure(e)
            HStack(spacing: 14) {
                IconTile(symbol: e.category.symbol, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.name).font(Theme.display(17)).lineLimit(2).minimumScaleFactor(0.8)
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
            .gradientCard(e.category.gradient, padding: 14)
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
