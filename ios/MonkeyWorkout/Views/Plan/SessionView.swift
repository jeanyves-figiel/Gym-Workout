import SwiftUI
import UIKit
import WorkoutEngine

/// Session overview: muscle heat map, what each part of the session targets, and every exercise with its muscles.
struct SessionView: View {
    let sessionId: String
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var playing = false
    @State private var detail: ExerciseRef?
    @State private var muscle: Muscle?

    private var session: Session? { model.plan?.sessions.first { $0.id == sessionId } }

    var body: some View {
        if let session {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(session)
                    FlowOverview(session: session)
                    ForEach(session.blocks) { block in
                        BlockSection(block: block, sessionId: session.id) { item in
                            detail = ExerciseRef(exerciseId: item.exerciseId, uid: item.uid)
                        }
                    }
                    finishButton(session)
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Day \(session.index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { playing = true } label: { Label("Start workout", systemImage: "play.fill") }
                    .buttonStyle(LimeButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .fullScreenCover(isPresented: $playing) { WorkoutPlayerView(sessionId: session.id) }
            .sheet(item: $detail) { ref in
                NavigationStack { ExerciseDetailView(exerciseId: ref.exerciseId, plannedUid: ref.uid) }
                    .presentationDetents([.large])
            }
            .sheet(item: $muscle) { m in
                NavigationStack { MuscleDetailView(muscle: m) }
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark")
        }
    }

    @ViewBuilder
    private func header(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(s.focus.label).font(Theme.display(38)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                StatTile(value: "\(s.estMin)′", label: "Duration")
                StatTile(value: "\(s.blocks.reduce(0) { $0 + $1.items.count })", label: "Exercises")
                StatTile(value: "\(s.blocks.filter { [BlockKind.power, .strength].contains($0.kind) }.flatMap(\.items).reduce(0) { $0 + $1.prescription.sets })", label: "Work sets")
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Muscles worked · tap to explore").eyebrow()
                BodyMapPair(heat: s.muscleHeat) { muscle = $0 }
                    .frame(height: 300)
                HeatLegend()
                FlowLayout(spacing: 6) {
                    ForEach(s.topMuscles(6)) { m in
                        Button { muscle = m } label: { MuscleChip(muscle: m) }
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private func finishButton(_ s: Session) -> some View {
        let done = model.state.done[s.id] ?? false
        Button(done ? "Mark as not done" : "Mark session done (ticked items)") {
            if done {
                model.toggleDone(s.id)
            } else {
                let r = model.recordFromTicks(s, bodyMassKg: health.snapshot.weightKg ?? model.body.weightKg)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task {
                    let hr = await health.save(r)
                    model.attachHeartRate(r.id, avg: hr.avg, max: hr.max)
                }
            }
        }
        .font(Theme.label(14))
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity)
    }
}

struct ExerciseRef: Identifiable, Hashable {
    let exerciseId: String
    var uid: String?
    var id: String { (uid ?? "") + exerciseId }
}

/// Horizontal strip: each part of the session, its minutes and the muscles it hits.
private struct FlowOverview: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session flow").eyebrow()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(session.blocks) { b in
                        VStack(alignment: .leading, spacing: 8) {
                            CategoryPill(category: b.kind.category, compact: true)
                            Text("\(b.targetMin)′").font(Theme.display(28))
                            Text(session.muscles(in: b.kind).prefix(3).map(\.name).joined(separator: "\n"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(3)
                        }
                        .frame(width: 120, alignment: .leading)
                        .card(padding: 12)
                    }
                }
            }
        }
    }
}

private struct BlockSection: View {
    let block: Block
    let sessionId: String
    let onOpen: (PlannedExercise) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryPill(category: block.kind.category, title: block.title)
                Spacer()
                Text("\(block.targetMin) min").font(Theme.label(13)).foregroundStyle(Theme.muted)
            }
            if let note = block.note { Text(note).font(.footnote).foregroundStyle(Theme.muted) }
            ForEach(block.items) { item in
                ExerciseCard(item: item, block: block, sessionId: sessionId) { onOpen(item) }
            }
        }
    }
}

struct ExerciseCard: View {
    let item: PlannedExercise
    let block: Block
    let sessionId: String
    let onOpen: () -> Void
    @Environment(AppModel.self) private var model

    private var exercise: Exercise { Exercise.get(item.exerciseId) }
    private var ticked: Bool { model.state.ticked[item.uid] ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { model.toggleTick(item.uid) } label: {
                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(ticked ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.35)))
            }
            .accessibilityLabel(ticked ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 8) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(exercise.name)
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                                .strikethrough(ticked)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
                        }
                        Text(Format.prescription(item.prescription)).font(.subheadline.weight(.semibold)).foregroundStyle(block.kind.category.color)
                        let meta = [item.prescription.intensity, item.prescription.note].compactMap { $0 }
                        if !meta.isEmpty {
                            Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)
                MuscleChips(primary: exercise.primary, secondary: exercise.secondary)
                EquipmentLine(equipment: exercise.equipment)
                if let paired = item.pairedWith.flatMap(Exercise.find) {
                    Label("During rest: \(paired.name)", systemImage: "figure.flexibility")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(WorkoutEngine.Category.mobility.color.opacity(0.18)))
                }
            }
        }
        .padding(.leading, item.supersetWith == nil ? 0 : 22)
        .overlay(alignment: .leading) {
            if item.supersetWith != nil {
                Rectangle().fill(block.kind.category.color.opacity(0.6)).frame(width: 3).padding(.vertical, 4)
            }
        }
        .card(padding: 14)
    }
}
