import SwiftUI
import WorkoutEngine

// Own daily routines (#732, `daily-routines/v2/builder.png`): name, colour, icon and moves. Saved as a custom workout
// with a `RoutineLook`, so it syncs, plays and lands in history like one; shown in Explore → Daily → Mine and on Train.

/// Create or edit one of the member's own routines.
struct MyRoutineEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RoutinePrefs.tilesKey) private var tilesRaw = ""
    @State private var draft: CustomWorkout
    @State private var picking = false
    @State private var editMode: EditMode = .inactive
    /// Editing a saved routine saves on its own (#437); a new one keeps Save and a draft. Fixed on appear.
    @State private var autoSaving: Bool?
    @State private var draftRestored = false
    private let initial: CustomWorkout
    /// Save also puts it on Train's Daily row.
    private let addsToDaily: Bool
    private let onSave: ((CustomWorkout) -> Void)?

    private static let draftKey = "my-routine"

    init(initial: CustomWorkout, addsToDaily: Bool = false, onSave: ((CustomWorkout) -> Void)? = nil) {
        var w = initial
        if w.routine == nil { w.routine = RoutineLook() }
        self.initial = w
        self.addsToDaily = addsToDaily
        self.onSave = onSave
        _draft = State(initialValue: w)
    }

    private var isNew: Bool { model.customWorkout(initial.id) == nil }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && !draft.playableItems.isEmpty }
    private var look: RoutineLook { draft.routine ?? RoutineLook() }

    var body: some View {
        NavigationStack {
            List {
                if draftRestored {
                    DraftRestoredStrip {
                        DraftStore.clear(Self.draftKey)
                        draft = initial
                        draftRestored = false
                    }
                    .cardRow()
                }
                preview.cardRow()
                AccountField(label: "Name") {
                    TextField("e.g. Morning climb prep", text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                        .font(Theme.display(22))
                        .onChange(of: draft.name) { _, v in
                            if v.count > CustomWorkout.maxNameLength { draft.name = String(v.prefix(CustomWorkout.maxNameLength)) }
                        }
                }
                .cardRow()

                Text("Colour").eyebrow().padding(.top, 8).cardRow()
                HStack(spacing: 8) {
                    ForEach(Array(RoutineLook.colors), id: \.self) { i in
                        Button { draft.routine?.color = i } label: {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.routineGradient(i))
                                .frame(height: 44)
                                .overlay {
                                    if look.color == i {
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                                    }
                                }
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white, lineWidth: look.color == i ? 2.5 : 0))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Colour \(i + 1)")
                        .accessibilityAddTraits(look.color == i ? .isSelected : [])
                    }
                }
                .cardRow()

                Text("Icon").eyebrow().padding(.top, 8).cardRow()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(RoutineLook.symbols, id: \.self) { s in
                        Button { draft.routine?.symbol = s } label: {
                            Image(systemName: s).font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(look.symbol == s ? AnyShapeStyle(Theme.routineGradient(look.color)) : AnyShapeStyle(Theme.card)))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(s)
                        .accessibilityAddTraits(look.symbol == s ? .isSelected : [])
                    }
                }
                .cardRow()

                HStack {
                    Text("Moves · \(draft.items.count)").eyebrow()
                    Spacer()
                    if draft.items.count > 1 {
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
                        NavigationLink { CustomItemForm(item: $item) } label: { EmptyView() }.opacity(0)
                        CustomItemRow(item: item)
                    }
                    .cardRow()
                }
                .onDelete { draft.items.remove(atOffsets: $0) }
                .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }

                if draft.items.count < CustomWorkout.maxItems {
                    Button { picking = true } label: {
                        Label("Add moves", systemImage: "plus.circle.fill")
                            .font(Theme.label(15))
                            .foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("routine.add-moves")
                    .cardRow()
                }

                AccountNote(text: draft.items.isEmpty
                            ? "Add stretches or mobility drills. Tap one to set reps or seconds, swipe to remove."
                            : "Tap a move to set reps or seconds and rounds. Swipe to remove.")
                    .cardRow()
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
            .themedForm()
            .navigationTitle(isNew ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if autoSaving != true {
                    SaveToolbarItem(title: addsToDaily ? "Add" : "Save", disabled: !canSave) { save() }
                }
                CloseToolbarItem { dismiss() }
            }
            // Edits to a saved routine save on their own (#437); an empty name or no moves waits.
            .autoSave(autoSaving == true && canSave ? draft : nil, title: "Routine", symbol: look.symbol,
                      detail: { w in undoDetail(w.name, "\(w.items.count) move\(w.items.count == 1 ? "" : "s")") },
                      save: { [model] in model.saveCustomWorkout($0) })
            .sheet(isPresented: $picking) {
                ExercisePickerView(limit: CustomWorkout.maxItems - draft.items.count, category: .stretch) { picked in
                    draft.items += picked.map(RoutineLook.item(adding:))
                }
            }
        }
        .keepsDraft(autoSaving == false ? Self.draftKey : nil, draft, blank: initial)
        .onAppear {
            guard autoSaving == nil else { return }
            autoSaving = !isNew
            // Blank new routine: bring back what was typed last time.
            if isNew, initial.items.isEmpty, initial.name.isEmpty,
               let d = DraftStore.load(Self.draftKey, as: CustomWorkout.self), !d.items.isEmpty || !d.name.isEmpty {
                var d = d
                d.id = initial.id
                if d.routine == nil { d.routine = RoutineLook() }
                draft = d
                draftRestored = true
            }
        }
    }

    /// The card as it will look in Explore and on Train.
    private var preview: some View {
        HStack(spacing: 12) {
            RoutineIcon(symbol: look.symbol, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(trimmedName.isEmpty ? "My routine" : trimmedName).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                Text("Mine · \(draft.items.count) move\(draft.items.count == 1 ? "" : "s")")
                    .font(Theme.label(10)).tracking(1.1).textCase(.uppercase).opacity(0.85)
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(draft.items.isEmpty ? 0 : draft.session.estMin)").font(Theme.display(30)).monospacedDigit()
                Text("′").font(Theme.label(14))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.routineGradient(look.color)))
        .accessibilityElement(children: .combine)
    }

    private func save() {
        DraftStore.clear(Self.draftKey)
        let saved = model.saveCustomWorkout(draft)
        if addsToDaily { tilesRaw = RoutinePrefs.pinning(tilesRaw, saved.sessionId) }
        onSave?(saved)
        dismiss()
    }
}
