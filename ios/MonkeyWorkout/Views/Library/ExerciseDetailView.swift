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

    private var e: Exercise { Exercise.get(exerciseId) }

    /// The user's own exercise (#52), editable from here.
    private var custom: CustomExercise? {
        // Reading the model's list keeps this page current after an edit.
        _ = model.state.customExerciseList?.count
        return CustomExercise.isCustom(exerciseId) ? CustomExercises.shared.record(exerciseId) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ExerciseImageHeader(exercise: e)
                VStack(alignment: .leading, spacing: 10) {
                    CategoryPill(category: e.category)
                    Text(e.name).font(Theme.display(34)).fixedSize(horizontal: false, vertical: true)
                    if let machine = custom?.machine {
                        Label(machine, systemImage: "gearshape.2.fill").font(.subheadline.weight(.semibold))
                    }
                    Text(e.category.blurb).font(.subheadline).foregroundStyle(Theme.muted)
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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Muscles").eyebrow()
                    BodyMapPair(heat: e.heat, selected: muscle) { muscle = $0 }
                        .frame(height: 260)
                    muscleRows
                }
                .card()

                variationsSection

                if plannedUid != nil && e.category == .strength && !e.equipment.isEmpty && e.unit != .sec {
                    weightLog
                }
                ExerciseProgressCard(exerciseId: e.id, plannedUid: plannedUid)
                PRCard(exerciseId: e.id)
                BarSpeedSection(exercise: e)

                EquipmentSection(equipment: e.equipment)
                MySetupsSection(exercise: e, plannedUid: plannedUid)
                TechniqueView(exercise: e)

                alternativesSection
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
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
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(item: $muscle) { m in NavigationStack { MuscleDetailView(muscle: m) } }
        .sheet(item: $editing) { c in CustomExerciseBuilderView(existing: c) }
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
                            gradient: e.category.gradient) {
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
            GradientSection(symbol: "square.grid.2x2.fill", title: "Similar exercises", gradient: e.category.gradient) {
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
