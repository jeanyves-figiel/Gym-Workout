import SwiftUI
import WorkoutEngine

/// Catalog browser for the builder, in the Explore look: gradient category tiles and muscle chips as
/// filters, a two-column grid of picture cards, multi-select in tap order, sticky Add button.
struct ExercisePickerView: View {
    let limit: Int
    let onAdd: ([Exercise]) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: WorkoutEngine.Category?
    @State private var group: MuscleGroup?
    @State private var muscle: Muscle?
    @State private var selected: [String]
    @State private var builder: BuilderSheet?
    @State private var gate: ProGate?
    /// Bases whose variations are shown (#174).
    @State private var expanded: Set<String> = []
    @State private var closeGuard = CloseGuard()
    /// Selection the picker opened with, the Undo baseline (#285).
    private let initialSelection: [String]

    /// Custom exercise builder (#52): new, or edit one of the user's own.
    private enum BuilderSheet: Identifiable {
        case new
        case edit(CustomExercise)
        var id: String {
            switch self {
            case .new: "new"
            case let .edit(e): e.id.uuidString
            }
        }
    }

    /// `restoring`: the selection brought back by Undo (#285). `category`: filter the grid starts on (e.g. warm-up
    /// drills when adding a warm-up move, #293). `group`: muscle chip it starts on (Build as I go's muscle tiles, #490).
    init(limit: Int, selected: [String] = [], restoring: [String]? = nil, category: WorkoutEngine.Category? = nil,
         group: MuscleGroup? = nil, onAdd: @escaping ([Exercise]) -> Void) {
        self.limit = limit
        self.onAdd = onAdd
        _category = State(initialValue: category)
        _group = State(initialValue: group)
        let first = Array(selected.prefix(max(0, limit)))
        initialSelection = first
        _selected = State(initialValue: restoring ?? first)
    }

    /// Undo bar when the selection changed since the picker opened (#285).
    private var undoOffer: UndoOffer? {
        guard selected != initialSelection else { return nil }
        let kept = selected, first = initialSelection, cap = limit, add = onAdd, filter = category
        let detail = undoDetail(selected.count == 1 ? "1 exercise" : "\(selected.count) exercises",
                                selected.first.flatMap { Exercise.find($0)?.name })
        return UndoOffer(title: "Picker closed", detail: detail, symbol: "dumbbell.fill",
                         colors: WorkoutEngine.Category.strength.colors) {
            AnyView(ExercisePickerView(limit: cap, selected: first, restoring: kept, category: filter, onAdd: add))
        }
    }

    private static let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// Search + muscle/group filters, optionally for one category.
    private func matches(_ c: WorkoutEngine.Category?) -> [Exercise] {
        let found = Exercise.search(query, category: c, muscle: muscle)
        guard muscle == nil, let group else { return found }
        return found.filter { $0.muscles.contains { $0.group == group } }
    }

    /// Grid cards: without a search, variations fold under their base (#174) until the base's chip opens
    /// them; selected variations always show.
    private func entries(_ found: [Exercise]) -> [(exercise: Exercise, variations: Int)] {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return found.map { ($0, 0) } }
        return Exercise.folded(found).flatMap { family -> [(exercise: Exercise, variations: Int)] in
            let head = family.exercise
            let shown = expanded.contains(head.id) ? family.variations : family.variations.filter { selected.contains($0.id) }
            return [(head, family.variations.count)] + shown.map { ($0, 0) }
        }
    }

    var body: some View {
        // Reading the model's list re-renders the grid when custom exercises change.
        let _ = model.customExercises.count
        let results = matches(category)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ContentTitle(title: "Add exercises").padding(.horizontal, 16)
                    categoryTiles
                    muscleChips
                    Text("\(results.count) exercises").eyebrow().padding(.horizontal, 16).padding(.top, 4)
                    LazyVGrid(columns: Self.columns, spacing: 12) {
                        Button { ProStore.shared.run(.customExercise, $gate) { builder = .new } } label: {
                            NewExerciseCard().overlay(alignment: .topTrailing) { ProBadge().padding(8) }
                        }
                        .buttonStyle(.plain)
                        ForEach(entries(results), id: \.exercise.id) { entry in
                            let e = entry.exercise
                            VStack(spacing: 6) {
                                Button { toggle(e) } label: { PickerCard(exercise: e, order: selected.firstIndex(of: e.id)) }
                                    .buttonStyle(.plain)
                                    .contextMenu { customMenu(e) }
                                if entry.variations > 0 {
                                    Button {
                                        withAnimation(.snappy) {
                                            if expanded.contains(e.id) { expanded.remove(e.id) } else { expanded.insert(e.id) }
                                        }
                                    } label: {
                                        VariationsChip(count: entry.variations, open: expanded.contains(e.id))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
            .readableWidth()
            .sheet(item: $builder) { sheet in
                switch sheet {
                case .new:
                    CustomExerciseBuilderView { saved in
                        if selected.count < limit { selected.append(saved.exerciseId) }
                    }
                case let .edit(e):
                    CustomExerciseBuilderView(existing: e)
                }
            }
            .proPaywall($gate)
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty { addBar }
            }
            .animation(.snappy, value: selected.isEmpty)
            .sensoryFeedback(.selection, trigger: selected)
            .background(Theme.bg.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, muscle or equipment")
            // Title in the content (#539), not under the toolbar's glass buttons.
            .titleInContent("Add exercises")
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
        .undoableClose(closeGuard, offer: undoOffer)
    }

    @ViewBuilder private func customMenu(_ e: Exercise) -> some View {
        if CustomExercise.isCustom(e.id), let record = CustomExercises.shared.record(e.id) {
            Button { builder = .edit(record) } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) {
                selected.removeAll { $0 == e.id }
                model.archiveCustomExercise(record.id)
            } label: { Label("Remove", systemImage: "trash") }
        }
    }

    // MARK: Filters

    private var categoryTiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { category = nil } label: {
                    CategoryTile(title: "All", symbol: "square.grid.2x2.fill", count: matches(nil).count,
                                 fill: AnyShapeStyle(Theme.cardStrong), iconColor: Theme.lime,
                                 selected: category == nil, dimmed: false)
                }
                ForEach(WorkoutEngine.Category.allCases) { c in
                    Button { category = category == c ? nil : c } label: {
                        CategoryTile(title: c.label, symbol: c.symbol, count: matches(c).count,
                                     fill: AnyShapeStyle(c.gradient), iconColor: category != nil && category != c ? .white : c.ink,
                                     selected: category == c, dimmed: category != nil && category != c, ink: c.ink)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .animation(.snappy, value: category)
    }

    private var muscleChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            chipRow {
                FilterChip(title: "All muscles", on: group == nil) { group = nil; muscle = nil }
                ForEach(MuscleGroup.allCases) { g in
                    FilterChip(title: g.label, on: group == g) {
                        group = group == g ? nil : g
                        muscle = nil
                    }
                }
            }
            if let group {
                chipRow {
                    FilterChip(title: "Any", on: muscle == nil, small: true) { muscle = nil }
                    ForEach(group.muscles) { m in
                        FilterChip(title: m.name, on: muscle == m, small: true) { muscle = muscle == m ? nil : m }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: group)
    }

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }.padding(.horizontal, 16)
        }
    }

    // MARK: Selection

    private var addBar: some View {
        VStack(spacing: 6) {
            if selected.count >= limit {
                Text("Max \(limit) more in this workout").font(Theme.label(11)).foregroundStyle(Theme.muted)
            }
            Button {
                onAdd(selected.compactMap { Exercise.find($0) })
                closeGuard.done()
                dismiss()
            } label: {
                Text(selected.count == 1 ? "Add 1 exercise" : "Add \(selected.count) exercises")
                    .font(Theme.display(18))
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .foregroundStyle(Theme.ink)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.lime))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .readableColumn()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func toggle(_ e: Exercise) {
        withAnimation(.snappy) {
            if let i = selected.firstIndex(of: e.id) {
                selected.remove(at: i)
            } else if selected.count < limit {
                selected.append(e.id)
            }
        }
    }
}

/// Explore-style category tile: icon tile left, big count right, heavy label.
struct CategoryTile: View {
    let title: String
    let symbol: String
    let count: Int?
    let fill: AnyShapeStyle
    let iconColor: Color
    let selected: Bool
    let dimmed: Bool
    /// Type on the full fill (#540): dark on light gradients. Dimmed tiles keep white over the dark canvas.
    var ink: Color = .white

    var body: some View {
        let dark = !dimmed && ink != .white
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(dark ? Theme.ink.opacity(0.12) : .white.opacity(0.2)))
                Spacer(minLength: 6)
                if let count {
                    Text("\(count)")
                        .font(Theme.display(22))
                        .opacity(0.85)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 8)
            Text(title).font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(dark ? ink : .white)
        .padding(12)
        .frame(width: 118, height: 100)
        // Dimmed tiles dim only the fill (#88): the title stays full white so every category reads.
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill)
            .saturation(dimmed ? 0.6 : 1)
            .opacity(dimmed ? 0.42 : 1))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.lime, lineWidth: 3)
            } else if dimmed {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(title), \($0) exercises" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct FilterChip: View {
    let title: String
    let on: Bool
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: small ? 12 : 13, weight: .heavy, design: .rounded))
                .padding(.horizontal, small ? 10 : 12)
                .padding(.vertical, small ? 5 : 7)
                .foregroundStyle(on ? Theme.ink : .white)
                .background {
                    if on {
                        Capsule().fill(Theme.lime)
                    } else {
                        Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// First grid cell: opens the custom exercise builder.
private struct NewExerciseCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Theme.lime))
            Text("New exercise").font(.system(size: 15, weight: .heavy, design: .rounded))
            Text("Your own machine,\nphoto or pose").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 196)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.lime.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New exercise")
        .accessibilityAddTraits(.isButton)
    }
}

/// Picture card: photo or illustration on the category gradient, category pill, tap-order badge.
/// "+N variations" under a base exercise's card; opens or folds them (#174).
private struct VariationsChip: View {
    let count: Int
    let open: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: open ? "chevron.up" : "square.stack.3d.down.right.fill").font(.system(size: 11, weight: .heavy))
            Text(open ? "Hide variations" : "+\(count) variation\(count == 1 ? "" : "s")").font(Theme.label(12))
        }
        .foregroundStyle(Theme.lime)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.cardStrong))
        .contentShape(Capsule())
        .accessibilityLabel(open ? "Hide variations" : "Show \(count) variations")
    }
}

private struct PickerCard: View {
    let exercise: Exercise
    let order: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExerciseImage(exercise: exercise)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    CategoryPill(category: exercise.category, compact: true).padding(7)
                }
                .overlay(alignment: .topTrailing) { badge.padding(7) }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                Text(exercise.primary.map(\.name).joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(order == nil ? Theme.stroke : Theme.lime, lineWidth: order == nil ? 1 : 2.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name), \(exercise.category.label), \(exercise.primary.map(\.name).joined(separator: ", "))")
        .accessibilityValue(order.map { "Selected, number \($0 + 1)" } ?? "")
        .accessibilityAddTraits(order == nil ? .isButton : [.isButton, .isSelected])
    }

    @ViewBuilder private var badge: some View {
        ZStack {
            Circle().fill(order == nil ? AnyShapeStyle(Theme.ink.opacity(0.55)) : AnyShapeStyle(Theme.lime))
            if let order {
                Text("\(order + 1)").font(Theme.label(14)).foregroundStyle(Theme.ink)
            } else {
                Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
    }
}
