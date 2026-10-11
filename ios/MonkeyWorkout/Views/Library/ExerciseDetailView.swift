import SwiftUI
import WorkoutEngine

/// Exercise page: body map, primary/secondary muscles, equipment, cues, swap (when planned), related exercises.
struct ExerciseDetailView: View {
    let exerciseId: String
    /// Set when opened from a planned session item → enables swap + weight log.
    var plannedUid: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var muscle: Muscle?
    @State private var kgText = ""
    @State private var editing: CustomExercise?

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
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Muscles").eyebrow()
                    BodyMapPair(heat: e.heat, selected: muscle) { muscle = $0 }
                        .frame(height: 260)
                    muscleRows
                }
                .card()

                if plannedUid != nil && e.category == .strength && !e.equipment.isEmpty && e.unit != .sec {
                    weightLog
                }
                ExerciseProgressCard(exerciseId: e.id, plannedUid: plannedUid)
                PRCard(exerciseId: e.id)

                EquipmentSection(equipment: e.equipment)
                TechniqueView(exercise: e)

                alternativesSection
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private var alternativesSection: some View {
        let alts = custom != nil ? [] : (model.profile.map { e.alternatives(for: $0) } ?? [])
        if !alts.isEmpty {
            GradientSection(symbol: plannedUid == nil ? "square.grid.2x2.fill" : "arrow.triangle.2.circlepath",
                            title: plannedUid == nil ? "Similar exercises" : "Swap for", gradient: e.category.gradient) {
                ForEach(alts.prefix(8)) { a in
                    if let uid = plannedUid {
                        Button {
                            model.swap(uid: uid, to: a.id)
                            dismiss()
                        } label: {
                            alternativeRow(a, swap: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        alternativeRow(a, swap: false)
                    }
                }
            }
        }
    }

    private func alternativeRow(_ a: Exercise, swap: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(a.name).font(.body.weight(.bold)).multilineTextAlignment(.leading)
                Text(a.primary.map(\.name).joined(separator: " · ")).font(.caption.weight(.medium)).opacity(0.85)
            }
            Spacer()
            if swap { Image(systemName: "arrow.triangle.2.circlepath").font(.body.weight(.bold)) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
        .contentShape(Rectangle())
    }
}
