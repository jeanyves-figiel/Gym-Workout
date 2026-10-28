import AppIntents
import SwiftUI
import WorkoutEngine

/// Exercise page: body map, primary/secondary muscles, equipment, cues, swap (when planned), similar exercises.
struct ExerciseDetailView: View {
    let exerciseId: String
    /// Set when opened from a planned session item → enables swap + weight log.
    var plannedUid: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var muscle: Muscle?
    @State private var kgText = ""
    @State private var editing: CustomExercise?
    @State private var swapping = false
    @State private var swapped = false
    @State private var partFrames: [ExercisePart: CGRect] = [:]
    @State private var activePart: ExercisePart?
    @State private var jumpedAt: Date?
    /// Scroll view's top inset (y) and height, in its own coordinate space.
    @State private var viewport = CGRect.zero

    private var e: Exercise { Exercise.get(exerciseId) }

    /// The user's own exercise (#52), editable from here.
    private var custom: CustomExercise? {
        // Reading the model's list keeps this page current after an edit.
        _ = model.state.customExerciseList?.count
        return CustomExercise.isCustom(exerciseId) ? CustomExercises.shared.record(exerciseId) : nil
    }

    /// What the floating coach knows about this page (#412).
    private var coachFocus: CoachFocus {
        let muscles = (e.primary + e.secondary).map(\.name).joined(separator: ", ")
        let gear = e.equipment.map(\.label).joined(separator: ", ")
        return CoachFocus(screen: "exercise", title: e.name,
                          detail: "muscles: \(muscles)" + (gear.isEmpty ? "" : "; equipment: \(gear)"),
                          starters: ["Form cues?", "Easier alternative?", "How heavy should I go?"])
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                    intro.padding([.horizontal, .top], 16)
                    // Sticky jump bar (#518): pins under the title once scrolled.
                    Section {
                        parts.padding([.horizontal, .bottom], 16)
                    } header: {
                        ExerciseJumpBar(parts: shownParts, active: activePart) { jump(to: $0, proxy) }
                    }
                }
            }
            .coordinateSpace(name: ExerciseJumpBar.space)
            .onGeometryChange(for: CGRect.self) { CGRect(x: 0, y: $0.safeAreaInsets.top, width: 0, height: $0.size.height) } action: { viewport = $0 }
            .onPreferenceChange(ExercisePartFrames.self) { frames in
                partFrames = frames
                spy(frames)
            }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .solidNavBar()
        .coachFocus(coachFocus)
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $swapping, onDismiss: {
            // The planned item now shows another exercise: back to the session.
            if swapped { dismiss() }
        }) {
            if let uid = plannedUid { SwapExerciseSheet(exerciseId: e.id, uid: uid) { swapped = true } }
        }
        .toolbar {
            if let custom, !custom.archived {
                ToolbarItem(placement: .topBarLeading) { Button("Edit") { editing = custom } }
            }
            CloseToolbarItem { dismiss() }
        }
        .sheet(item: $muscle) { m in NavigationStack { MuscleDetailView(muscle: m, onClose: { muscle = nil }) } }
        .sheet(item: $editing) { c in CustomExerciseBuilderView(existing: c) }
        // Siri sees the open exercise (#605, design C): "my best on this", "something easier?".
        .userActivity("com.monkeyworkout.exercise") { a in
            a.title = e.name
            if #available(iOS 18.2, *) { a.appEntityIdentifier = EntityIdentifier(for: ExerciseEntity(e)) }
        }
    }

    /// Parts that have something to show: a cardio move without history has no stats, a custom one no similar.
    private var shownParts: [ExercisePart] {
        ExercisePart.allCases.filter { (partFrames[$0]?.height ?? 0) > 1 }
    }

    /// Lights the part whose top has passed under the bar; none while the intro is still on screen.
    private func spy(_ frames: [ExercisePart: CGRect]) {
        if let jumpedAt, Date().timeIntervalSince(jumpedAt) < 0.8 { return }
        let line = viewport.minY + ExerciseJumpBar.height + 24
        let passed = shownParts.filter { (frames[$0]?.minY ?? .infinity) <= line }
        var part = passed.last
        // At the end of the page the last part can't reach the bar: light it once it is fully on screen.
        if !passed.isEmpty, let last = shownParts.last, let f = frames[last], f.maxY <= viewport.maxY { part = last }
        if part != activePart { activePart = part }
    }

    private func jump(to part: ExercisePart, _ proxy: ScrollViewProxy) {
        jumpedAt = .now
        activePart = part
        withAnimation(.snappy) { proxy.scrollTo(part, anchor: .top) }
    }

    /// Hero, position guide, name and the actions that belong to the move itself.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            ExerciseImageHeader(exercise: e)
            PositionGuideLink(exercise: e)
            // Form check (#833): the camera watches a set.
            FormCheckLink(exercise: e)
            VStack(alignment: .leading, spacing: 10) {
                CategoryPill(category: e.category)
                Text(e.name).font(Theme.display(34)).fixedSize(horizontal: false, vertical: true)
                if let machine = custom?.machine {
                    Label(machine, systemImage: "gearshape.2.fill").font(.subheadline.weight(.semibold))
                }
                Text(e.category.blurb).font(.subheadline).foregroundStyle(Theme.muted)
                // Ask Coach about this exercise (#412 C).
                CoachSpark(question: "Is this right for me?", focus: coachFocus)
                if let base = e.baseId.flatMap(Exercise.find) {
                    NavigationLink { ExerciseDetailView(exerciseId: base.id) } label: {
                        Label("Variation of \(base.name)", systemImage: "square.stack.3d.down.right.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.lime)
                    }
                    .buttonStyle(.plain)
                }
                // Climbing (#366): same drill and name as in MonkeyGrade's session planner.
                if e.monkeyGradeSlug != nil {
                    Label("Same drill in MonkeyGrade", systemImage: "figure.climbing")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MonkeyGradeTag.color)
                }
            }
            if let uid = plannedUid, model.canSwap(uid: uid) {
                Button { swapping = true } label: {
                    Label("Swap exercise", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(LimeButtonStyle())
            }
        }
    }

    private var parts: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Muscles").eyebrow()
                    BodyMapPair(heat: e.heat, selected: muscle) { muscle = $0 }
                        .frame(height: 260)
                    muscleRows
                }
                .card()

                variationsSection
            }
            .exercisePart(.muscles)

            VStack(alignment: .leading, spacing: 22) {
                if plannedUid != nil && e.category == .strength && !e.equipment.isEmpty && e.unit != .sec {
                    weightLog
                }
                ExerciseProgressCard(exerciseId: e.id, plannedUid: plannedUid)
                PRCard(exerciseId: e.id)
                FormHistoryCard(exerciseId: e.id)
                // Lift Lab and Pro Sets (#499).
                if ProSets.eligible(e) {
                    LiftLabCard(exercise: e)
                    SetStyleCard(exercise: e)
                }
                BarSpeedSection(exercise: e)
            }
            .exercisePart(.stats)

            VStack(alignment: .leading, spacing: 22) {
                EquipmentSection(equipment: e.equipment)
                MySetupsSection(exercise: e, plannedUid: plannedUid)
            }
            .exercisePart(.setup)

            TechniqueView(exercise: e)
                .exercisePart(.form)

            alternativesSection
                .exercisePart(.similar)
        }
    }

    private var muscleRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(e.primary) { m in muscleRow(m, primary: true) }
            ForEach(e.secondary.filter { !e.primary.contains($0) }) { m in muscleRow(m, primary: false) }
        }
    }

    private func muscleRow(_ m: Muscle, primary: Bool) -> some View {
        Button { muscle = m } label: {
            HStack {
                Circle().fill(Theme.heat(primary ? 1 : 0.45)).frame(width: 10, height: 10)
                Text(m.name).font(.body.weight(.bold))
                Spacer()
                Text(primary ? "PRIMARY" : "ASSIST").font(Theme.label(10)).tracking(1).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
            }
        }
        .buttonStyle(.plain)
    }

    private var weightLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log weight").eyebrow()
            HStack(spacing: 10) {
                TextField(model.lastWeight(e.id).map(Format.kg) ?? "kg", text: $kgText)
                    .keyboardType(.decimalPad)
                    .font(Theme.display(24))
                    .frame(width: 110)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardStrong))
                Text("kg").font(Theme.label(16))
                Spacer()
                Button("Log") {
                    if let v = Double(kgText.replacingOccurrences(of: ",", with: ".")), v >= 0, v <= 1000 {
                        model.logWeight(exerciseId: e.id, sessionId: model.plan?.sessions.first { s in s.blocks.contains { $0.items.contains { $0.uid == plannedUid } } }?.id ?? "", kg: v)
                        kgText = ""
                    }
                }
                .font(Theme.label(15))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(Theme.lime))
                .foregroundStyle(Theme.ink)
                .disabled(kgText.isEmpty)
            }
            if let last = model.lastWeight(e.id) {
                Text("Last: \(Format.kg(last)) kg").font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }

    /// The exercise's family (#174): its base and the other variations, each opening its own page.
    @ViewBuilder
    private var variationsSection: some View {
        let family = custom == nil ? e.relatives : []
        if !family.isEmpty {
            GradientSection(symbol: "square.stack.3d.down.right.fill", title: e.baseId == nil ? "Variations" : "Same family",
                            gradient: e.category.gradient, ink: e.category.ink) {
                ForEach(family) { a in
                    NavigationLink { ExerciseDetailView(exerciseId: a.id) } label: { alternativeRow(a) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Related moves; each opens its own page, pushed in this sheet (#129). Planned items swap from the Swap
    /// exercise button (#101).
    @ViewBuilder
    private var alternativesSection: some View {
        let alts = custom != nil || plannedUid.map { model.canSwap(uid: $0) } == true ? [] : (model.profile.map { e.alternatives(for: $0) } ?? [])
        let family = Set(e.family.map(\.id))
        let others = alts.filter { !family.contains($0.id) }
        if !others.isEmpty {
            GradientSection(symbol: "square.grid.2x2.fill", title: "Similar exercises", gradient: e.category.gradient, ink: e.category.ink) {
                ForEach(others.prefix(8)) { a in
                    NavigationLink { ExerciseDetailView(exerciseId: a.id) } label: { alternativeRow(a) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func alternativeRow(_ a: Exercise) -> some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: a, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(a.name).font(.body.weight(.bold)).multilineTextAlignment(.leading)
                Text(a.primary.map(\.name).joined(separator: " · ")).font(.caption.weight(.medium)).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.body.weight(.bold)).opacity(0.85)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
        .contentShape(Rectangle())
    }
}
