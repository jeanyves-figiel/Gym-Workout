import SwiftUI
import WorkoutEngine

/// "Explore" tab: exercises by body map / muscle group or training category, and the workout library.
struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case muscles = "Muscles", machines = "Machines", categories = "Categories", workouts = "Workouts", programmes = "Programmes"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode

    /// Muscle group scrolled to on appear (CI screenshots of the muscle cards).
    private let scrollTo: MuscleGroup?

    init(mode: Mode = .muscles, scrollTo: MuscleGroup? = nil) {
        _mode = State(initialValue: mode)
        self.scrollTo = scrollTo
    }
    /// Muscle tapped on the body map; pushes its page.
    @State private var tapped: Muscle?
    /// Machine chip on Muscles (#456), shared with the muscle page.
    @AppStorage(MachineFilterStore.key) private var machineFilter = MachineFilter.all.key

    var body: some View {
        // Reading the model's list re-renders counts and lists when custom exercises change.
        let _ = model.customExercises.count
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Live hero + colour dock (#459).
                ExploreMenu(mode: $mode)

                switch mode {
                case .muscles: muscles
                case .machines: MachinesSection()
                case .categories: categories
                case .workouts: WorkoutLibrarySection()
                case .programmes: ProgrammeLibrarySection()
                }
            }
            .padding(16)
        }
        .onAppear {
            if let scrollTo { DispatchQueue.main.async { proxy.scrollTo(scrollTo, anchor: .top) } }
        }
        // Opened from another tab (#345): show the asked mode.
        .task(id: model.exploreJump) {
            guard let jump = model.exploreJump else { return }
            mode = jump
            model.exploreJump = nil
        }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Explore")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: Muscle.self) { MuscleDetailView(muscle: $0) }
        .navigationDestination(for: Equipment.self) { MachineDetailView(item: $0) }
        .navigationDestination(for: WorkoutEngine.Category.self) { CategoryDetailView(category: $0) }
        .navigationDestination(for: ClimbingRoute.self) { _ in ClimbingCategoryView() }
        .navigationDestination(for: String.self) { SessionView(sessionId: $0) }
        .navigationDestination(for: ProgrammeRoute.self) { r in model.findProgramme(r.id).map { ProgrammeDetailView(programme: $0) } }
        .navigationDestination(item: $tapped) { MuscleDetailView(muscle: $0) }
    }

    private var muscles: some View {
        VStack(alignment: .leading, spacing: 20) {
            BodyMapCard(heat: model.weekHeat) { tapped = $0 }
            // Machine chips (#456): muscle cards count only exercises on the picked kit; muscles with none hide.
            MachineChips()
            NewExerciseButton()

            let heat = model.weekHeat, hard = model.weeklyHardSets, last = model.lastTrained, planned = model.plan != nil
            let filter = MachineFilter(key: machineFilter), gym = model.exploreGym
            let counts = Dictionary(uniqueKeysWithValues: Muscle.allCases.map { m in
                (m, Exercise.working(m, filter: filter, gym: gym).reduce(0) { $0 + $1.1.count })
            })
            ForEach(MuscleGroup.allCases) { g in
                let shown = g.muscles.filter { filter == .all || counts[$0, default: 0] > 0 }
                if !shown.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(g.label).eyebrow()
                        ForEach(shown) { m in
                            let target = model.volumeTarget(for: m)
                            NavigationLink(value: m) {
                                MuscleCard(
                                    muscle: m, heat: heat[m] ?? 0,
                                    sets: !planned ? nil : target != nil ? Int((hard[m] ?? 0).rounded()) : model.weeklySets(for: m),
                                    target: target,
                                    exercises: counts[m, default: 0],
                                    last: last[m])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .id(g)
                }
            }
        }
    }

    private var categories: some View {
        VStack(spacing: 12) {
            ForEach(WorkoutEngine.Category.allCases) { c in
                NavigationLink(value: c) { CategoryCard(category: c, count: Exercise.inCategory(c).count) }
                    .buttonStyle(.plain)
            }
            // Climbing gym exercises (#366).
            NavigationLink(value: ClimbingRoute()) { ClimbingCategoryCard() }
                .buttonStyle(.plain)
            // Hyrox for everyone (#439): race mode, pacing, sims.
            HyroxExploreCard()
            NewExerciseButton()
        }
    }
}

/// Explore → Muscles body map (#110): front/back anatomical figures on a soft glow. Tap a muscle to open it.
/// This week's sets and top muscles live in the Explore hero above (#459).
private struct BodyMapCard: View {
    let heat: [Muscle: Double]
    let onTap: (Muscle) -> Void
    @AppStorage(BodyMapMode.storageKey) private var storedMode = BodyMapMode.flat
    @Environment(\.bodyMapDemo) private var demo

    private var mode: BodyMapMode { demo?.mode ?? storedMode }

    /// 2D | 3D pill on the map (same setting as Account → Body & Health → Body map).
    private var modeToggle: some View {
        BodyMapModeToggle(selection: $storedMode, current: mode)
    }

    var body: some View {
        VStack(spacing: 0) {
            if mode == .solid {
                BodyMap3DPanel(heat: heat, modeToggle: AnyView(modeToggle), onOpen: onTap)
            } else {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ForEach(BodySide.allCases) { s in
                            BodyMapView(side: s, heat: heat, onTap: onTap)
                        }
                    }
                    .frame(height: 340)
                    .padding(.bottom, 18)
                    HeatLegend()
                    Text("Tap a muscle to see its exercises").font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
                .padding(.top, 30)
                .background(
                    RadialGradient(colors: [WorkoutEngine.Category.strength.colors[1].opacity(0.22), .clear],
                                   center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 220)
                )
                .overlay(alignment: .topTrailing) { modeToggle.padding(12) }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Explore muscle card: close-up of the muscle on the figure (lit in its load colour), exercise count and
/// last trained, and this week's sets on the right, against the Volume target when the plan has one.
private struct MuscleCard: View {
    let muscle: Muscle
    let heat: Double
    /// Nil without a plan.
    let sets: Int?
    let target: Int?
    let exercises: Int
    let last: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                MuscleThumbnail(muscle: muscle, heat: heat)
                    .frame(width: 58, height: 58)
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.2)))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(muscle.name).font(Theme.display(20)).lineLimit(2).minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            chip("dumbbell.fill", exercises == 1 ? "1 exercise" : "\(exercises) exercises")
                            if let last { chip("clock.fill", Self.ago(last)) }
                        }
                        HStack(spacing: 6) {
                            chip("dumbbell.fill", "\(exercises)")
                            if let last { chip("clock.fill", Self.ago(last)) }
                        }
                        chip("dumbbell.fill", "\(exercises)")
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                if let sets {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(sets)").font(Theme.display(30)).monospacedDigit()
                            if let target { Text("/\(target)").font(Theme.display(16)).opacity(0.75) }
                        }
                        Text("sets / wk").font(Theme.label(10)).opacity(0.85)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(sets == 0 ? 0.55 : 1)
                }
            }
            if let sets, let target, target > 0 {
                Capsule().fill(.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white).scaleEffect(x: min(1, CGFloat(sets) / CGFloat(target)), anchor: .leading)
                    }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(muscle.group.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(Theme.label(11))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.22)))
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case ..<14: return "\(days)d ago"
        default: return "\(days / 7)w ago"
        }
    }
}

private struct CategoryCard: View {
    let category: WorkoutEngine.Category
    let count: Int

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
            Text("\(count)").font(Theme.display(22)).opacity(0.8)
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
    @AppStorage(MachineFilterStore.key) private var machineFilter = MachineFilter.all.key

    var body: some View {
        let _ = model.customExercises.count
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
                        GradientStat(symbol: "square.stack.3d.up.fill", value: "\(model.weeklySets(for: muscle))", label: "Sets / week",
                                     gradient: WorkoutEngine.Category.strength.gradient)
                        GradientStat(symbol: "list.bullet", value: "\(Exercise.working(muscle).reduce(0) { $0 + $1.1.count })", label: "Exercises",
                                     gradient: WorkoutEngine.Category.cardio.gradient)
                    }
                    .frame(width: 130)
                }
                MachineChips()
                NewExerciseButton(prefill: CustomExercise(primary: [muscle]))
                let filtered = Exercise.working(muscle, filter: MachineFilter(key: machineFilter), gym: model.exploreGym)
                if filtered.isEmpty {
                    Text("No \(muscle.name.lowercased()) exercise with \(MachineFilter(key: machineFilter).label.lowercased()). Pick another chip.")
                        .font(.body.weight(.medium)).foregroundStyle(Theme.muted)
                }
                ForEach(filtered, id: \.0) { category, hits in
                    let main = Set(hits.filter(\.primary).map(\.exercise.id))
                    GradientSection(symbol: category.symbol, title: category.label, gradient: category.gradient) {
                        // Variations fold under their base (#174); the exercise page lists them.
                        ForEach(Exercise.folded(hits.map(\.exercise)), id: \.exercise.id) { family in
                            let ex = family.exercise
                            let isMain = main.contains(ex.id)
                            Button { open = ExerciseRef(exerciseId: ex.id) } label: {
                                HStack(spacing: 12) {
                                    Text(isMain ? "MAIN" : "ASSIST")
                                        .font(Theme.label(9))
                                        .tracking(1)
                                        .foregroundStyle(isMain ? Theme.ink : .white)
                                        .frame(width: 52)
                                        .padding(.vertical, 4)
                                        .background {
                                            if isMain { Capsule().fill(.white) } else { Capsule().strokeBorder(Color.white.opacity(0.6)) }
                                        }
                                    ExerciseThumbnail(exercise: ex, size: 48)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                                        VariationCount(count: family.variations.count, color: .white.opacity(0.85))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).opacity(0.8)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Muscle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { ref in NavigationStack { ExerciseDetailView(exerciseId: ref.exerciseId) } }
    }
}

/// Category page: what the category is for, and its exercises with muscles.
struct CategoryDetailView: View {
    let category: WorkoutEngine.Category
    @Environment(AppModel.self) private var model
    @State private var open: ExerciseRef?

    var body: some View {
        let _ = model.customExercises.count
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

                NewExerciseButton(prefill: CustomExercise(category: category))

                ForEach(Exercise.folded(Exercise.inCategory(category)), id: \.exercise.id) { family in
                    let e = family.exercise
                    Button { open = ExerciseRef(exerciseId: e.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name).font(.system(.headline, design: .rounded).weight(.heavy)).multilineTextAlignment(.leading)
                                    VariationCount(count: family.variations.count)
                                }
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
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { ref in NavigationStack { ExerciseDetailView(exerciseId: ref.exerciseId) } }
    }
}

/// "+N variations" under a base exercise's name (#174); nothing for exercises without variations.
struct VariationCount: View {
    let count: Int
    var color: Color = Theme.lime

    var body: some View {
        if count > 0 {
            Label("+\(count) variation\(count == 1 ? "" : "s")", systemImage: "square.stack.3d.down.right.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .labelStyle(.titleAndIcon)
        }
    }
}

/// Explore (#142): "New exercise" card opening the custom exercise builder (#52), prefilled with the
/// muscle or category it is added from; the saved exercise then shows in that list.
struct NewExerciseButton: View {
    var prefill: CustomExercise?
    @State private var building = false
    @State private var gate: ProGate?

    var body: some View {
        Button { ProStore.shared.run(.customExercise, $gate) { building = true } } label: {
            HStack(spacing: 16) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.lime))
                VStack(alignment: .leading, spacing: 3) {
                    Text("New exercise").font(Theme.display(20))
                    Text("Your own machine, photo or pose").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                ProBadge()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.lime.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New exercise")
        .sheet(isPresented: $building) { CustomExerciseBuilderView(prefill: prefill) }
        .proPaywall($gate)
    }
}
