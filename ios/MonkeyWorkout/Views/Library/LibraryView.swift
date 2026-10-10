import SwiftUI
import WorkoutEngine

/// "Muscles" tab: explore by body map / muscle group, or by training category.
struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case muscles = "Muscles", categories = "Categories"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .muscles
    /// Muscle tapped on the body map; pushes its page.
    @State private var tapped: Muscle?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Browse", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .muscles: muscles
                case .categories: categories
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Explore")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: Muscle.self) { MuscleDetailView(muscle: $0) }
        .navigationDestination(for: WorkoutEngine.Category.self) { CategoryDetailView(category: $0) }
        .navigationDestination(item: $tapped) { MuscleDetailView(muscle: $0) }
    }

    private var muscles: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 14) {
                Text("This week's load · tap a muscle").eyebrow()
                HStack(spacing: 12) {
                    ForEach(BodySide.allCases) { s in
                        BodyMapView(side: s, heat: model.weekHeat) { tapped = $0 }
                    }
                }
                .frame(height: 320)
                .padding(.bottom, 18)
                HeatLegend()
            }
            .card()

            ForEach(MuscleGroup.allCases) { g in
                VStack(alignment: .leading, spacing: 8) {
                    Text(g.label).eyebrow()
                    ForEach(g.muscles) { m in
                        NavigationLink(value: m) { MuscleRow(muscle: m, heat: model.weekHeat[m] ?? 0, sets: model.weeklySets(for: m)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var categories: some View {
        VStack(spacing: 12) {
            ForEach(WorkoutEngine.Category.allCases) { c in
                NavigationLink(value: c) { CategoryCard(category: c) }
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct MuscleRow: View {
    let muscle: Muscle
    let heat: Double
    let sets: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(heat > 0 ? Theme.heat(heat) : Color.white.opacity(0.15)).frame(width: 12, height: 12)
            Text(muscle.name).font(.system(.body, design: .rounded).weight(.bold))
            Spacer()
            if sets > 0 {
                Text("\(sets) sets / wk").font(Theme.label(12)).foregroundStyle(Theme.muted)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
        }
        .card(padding: 14)
    }
}

private struct CategoryCard: View {
    let category: WorkoutEngine.Category

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: category.symbol)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(category.label).font(Theme.display(24))
                Text(category.blurb).font(.footnote.weight(.medium)).opacity(0.85).multilineTextAlignment(.leading)
            }
            Spacer()
            Text("\(Exercise.inCategory(category).count)").font(Theme.display(22)).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(category.gradient))
    }
}

/// Muscle page: role, map, weekly volume, and every exercise working it — grouped by category.
struct MuscleDetailView: View {
    let muscle: Muscle
    @Environment(AppModel.self) private var model
    @State private var open: ExerciseRef?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(muscle.group.label).eyebrow()
                    Text(muscle.name).font(Theme.display(40))
                    Text(muscle.role).font(.body.weight(.medium)).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 12) {
                    BodyMapPair(heat: [muscle: 1], selected: muscle)
                        .frame(height: 220)
                    VStack(spacing: 10) {
                        StatTile(value: "\(model.weeklySets(for: muscle))", label: "Sets / week")
                        StatTile(value: "\(Exercise.working(muscle).reduce(0) { $0 + $1.1.count })", label: "Exercises")
                    }
                    .frame(width: 130)
                }
                ForEach(Exercise.working(muscle), id: \.0) { category, hits in
                    VStack(alignment: .leading, spacing: 10) {
                        CategoryPill(category: category)
                        ForEach(hits, id: \.exercise.id) { hit in
                            Button { open = ExerciseRef(exerciseId: hit.exercise.id) } label: {
                                HStack(spacing: 12) {
                                    Text(hit.primary ? "MAIN" : "ASSIST")
                                        .font(Theme.label(9))
                                        .tracking(1)
                                        .foregroundStyle(hit.primary ? Theme.ink : .white)
                                        .frame(width: 52)
                                        .padding(.vertical, 4)
                                        .background {
                                            if hit.primary { Capsule().fill(Theme.lime) } else { Capsule().strokeBorder(Color.white.opacity(0.35)) }
                                        }
                                    ExerciseThumbnail(exercise: hit.exercise, size: 48)
                                    Text(hit.exercise.name).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card()
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { ref in NavigationStack { ExerciseDetailView(exerciseId: ref.exerciseId) } }
    }
}

/// Category page: what the category is for, and its exercises with muscles.
struct CategoryDetailView: View {
    let category: WorkoutEngine.Category
    @State private var open: ExerciseRef?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: category.symbol).font(.system(size: 40, weight: .bold))
                    Text(category.label).font(Theme.display(40))
                    Text(category.blurb).font(.body.weight(.medium)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(category.gradient))

                ForEach(Exercise.inCategory(category)) { e in
                    Button { open = ExerciseRef(exerciseId: e.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(e.name).font(.system(.headline, design: .rounded).weight(.heavy)).multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
                            }
                            MuscleChips(primary: e.primary, secondary: e.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { ref in NavigationStack { ExerciseDetailView(exerciseId: ref.exerciseId) } }
    }
}
