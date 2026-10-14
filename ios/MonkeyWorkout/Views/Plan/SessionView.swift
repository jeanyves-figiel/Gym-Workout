import SwiftUI
import UIKit
import WorkoutEngine

/// Session overview: muscle heat map, what each part of the session targets, and every exercise with its muscles.
struct SessionView: View {
    let sessionId: String
    @Environment(AppModel.self) private var model
    @State private var playing = false
    @State private var detail: ExerciseRef?
    @State private var muscle: Muscle?
    @State private var swapping: ExerciseRef?
    @State private var undoing: WorkoutRecord?
    @State private var editingFlow = false
    @State private var editingCustom: CustomWorkout?
    @State private var editingExercises = false
    /// Swap from a card that changes this workout's own list (#295) rather than the plan.
    @State private var pickingSwap: ExerciseRef?

    private var session: Session? { model.session(sessionId) }

    var body: some View {
        if let session {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(session)
                    FlowOverview(session: session, onEdit: flowEdit(session))
                    exercisesHeader(session)
                    ForEach(session.blocks) { block in
                        BlockSection(block: block, sessionId: session.id,
                                     canSwap: { model.swapsThroughPlan(session, uid: $0.uid) || model.canEditExercises(session) }) { item in
                            // Example and custom workouts are fixed lists: no planned item behind them.
                            detail = ExerciseRef(exerciseId: item.exerciseId, uid: session.isStandalone ? nil : item.uid)
                        } onSwap: { item in
                            let ref = ExerciseRef(exerciseId: item.exerciseId, uid: item.uid)
                            if model.swapsThroughPlan(session, uid: item.uid) { swapping = ref } else { pickingSwap = ref }
                        }
                    }
                    finishButton(session)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            // The big display title below is the page's one title (#88); the bar stays clear.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { playing = true } label: {
                    Label(model.activeWorkout(session.id) == nil ? "Start workout" : "Resume workout", systemImage: "play.fill")
                }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(session.blocks.allSatisfy { $0.items.isEmpty })
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .readableColumn()
                    // Opaque bar (as on the profile form): content ends above the button instead of sliding under it.
                    .background(Theme.bg.ignoresSafeArea())
            }
            .standaloneWorkoutActions(session)
            .fullScreenCover(isPresented: $playing) { WorkoutPlayerView(sessionId: session.id) }
            .sheet(item: $detail) { ref in
                NavigationStack { ExerciseDetailView(exerciseId: ref.exerciseId, plannedUid: ref.uid) }
                    .presentationDetents([.large])
            }
            .sheet(item: $muscle) { m in
                NavigationStack { MuscleDetailView(muscle: m) }
            }
            .sheet(isPresented: $editingFlow) {
                SessionFlowSheet(session: session).presentationDetents([.large])
            }
            .sheet(item: $editingCustom) { w in CustomWorkoutEditor(initial: w) }
            .sheet(item: $swapping) { ref in
                if let uid = ref.uid { SwapExerciseSheet(exerciseId: ref.exerciseId, uid: uid) }
            }
            .sheet(item: $pickingSwap) { ref in
                if let uid = ref.uid {
                    SwapExerciseSheet(exerciseId: ref.exerciseId, uid: uid, onPick: { model.swapInSession(session.id, uid: uid, to: $0) })
                }
            }
            .sheet(isPresented: $editingExercises) {
                if let base = model.uneditedSession(session.id), let blocks = model.editableBlocks(session.id) {
                    EditExercisesSheet(sessionId: session.id, base: base, blocks: blocks)
                }
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark")
        }
    }

    /// Exercise count tile; until the workout starts it opens the exercise editor (#295).
    @ViewBuilder
    private func exercisesStat(_ s: Session) -> some View {
        let stat = GradientStat(symbol: "figure.strengthtraining.traditional", value: "\(s.blocks.reduce(0) { $0 + $1.items.count })", label: "Exercises",
                                gradient: WorkoutEngine.Category.mobility.gradient)
        if model.canEditExercises(s) {
            Button { editingExercises = true } label: {
                stat.overlay(alignment: .topTrailing) {
                    Image(systemName: "pencil").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).padding(12)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit exercises")
        } else {
            stat
        }
    }

    /// Exercises title with Edit (#295); an edited workout says so and can go back to the plan.
    @ViewBuilder
    private func exercisesHeader(_ s: Session) -> some View {
        let editable = model.canEditExercises(s)
        let edited = model.isEdited(s.id)
        if editable || edited {
            HStack(spacing: 8) {
                Text("Exercises").eyebrow()
                if edited {
                    Text("Edited").font(Theme.label(11)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(WorkoutEngine.Category.cardio.gradient))
                    if editable {
                        Button { withAnimation { model.resetSessionEdit(s.id) } } label: {
                            Label("Reset", systemImage: "arrow.uturn.backward").font(Theme.label(12)).foregroundStyle(Theme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to the workout as planned")
                    }
                }
                Spacer()
                if editable {
                    Button { editingExercises = true } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(Theme.label(13))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit exercises")
                }
            }
        }
    }

    /// Session flow (#198): plan workouts open the flow sheet, the member's own workouts their builder.
    private func flowEdit(_ s: Session) -> (() -> Void)? {
        if model.canEditFlow(s) { return { editingFlow = true } }
        if s.isCustom, model.activeWorkout(s.id) == nil, let w = model.customWorkout(sessionId: s.id) { return { editingCustom = w } }
        return nil
    }

    @ViewBuilder
    private func header(_ s: Session) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let day = s.weekday {
                SessionDayLine(weekday: day, climbing: model.profile?.climbingDays ?? [])
            }
            VStack(alignment: .leading, spacing: 6) {
                if s.weekday == nil, let context = model.libraryTitle(s) { Text(context).eyebrow() }
                Text(s.displayTitle).font(Theme.display(38)).fixedSize(horizontal: false, vertical: true)
            }
            // What finishing it earns, in the member's game look (#227).
            if !s.blocks.allSatisfy({ $0.items.isEmpty }) { SessionGameBanner(session: s) }
            LibraryActionsPanel(session: s)
            if let t = WorkoutTemplate.find(sessionId: s.id) {
                Text(([t.goal.label, t.kit, t.levelLabel] + [t.kcal.map { "\($0) kcal" }, t.activityPoints.map { "\($0) activity points" }].compactMap { $0 })
                    .joined(separator: " · "))
                    .font(Theme.label(14)).foregroundStyle(Theme.lime)
            } else if let kcal = model.customWorkout(sessionId: s.id)?.kcal {
                Text("\(kcal) kcal").font(Theme.label(14)).foregroundStyle(Theme.lime)
            }
            HStack(spacing: 10) {
                GradientStat(symbol: "stopwatch.fill", value: "\(s.estMin)′", label: "Duration",
                             gradient: WorkoutEngine.Category.cardio.gradient)
                exercisesStat(s)
                GradientStat(symbol: "square.stack.3d.up.fill", value: "\(s.blocks.filter { [BlockKind.power, .strength].contains($0.kind) }.flatMap(\.items).reduce(0) { $0 + $1.prescription.sets })", label: "Work sets",
                             gradient: WorkoutEngine.Category.strength.gradient)
            }
            WorkoutStyleCard(session: s)
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

    /// Exercises complete only in the player (#57); a finished session can still be reopened.
    @ViewBuilder
    private func finishButton(_ s: Session) -> some View {
        if model.state.done[s.id] ?? false {
            // Recorded this week: undo it completely (#133); otherwise only the done mark.
            if let r = model.recordThisWeek(s.id) {
                Button("Undo workout") { undoing = r }
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .confirmationDialog("Undo this workout?", isPresented: Binding { undoing != nil } set: { if !$0 { undoing = nil } },
                                        titleVisibility: .visible, presenting: undoing) { r in
                        Button("Undo workout", role: .destructive) { model.undoWorkout(r.id) }
                    } message: { _ in
                        Text("Removes it from history with its sets, PRs and progress, as if it never happened, so you can do it again.")
                    }
            } else {
                Button("Mark as not done") { model.toggleDone(s.id) }
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
        }
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
    var onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Session flow").eyebrow()
                Spacer()
                if let onEdit {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "slider.horizontal.3")
                            .font(Theme.label(13))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit session flow")
                }
            }
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
    let canSwap: (PlannedExercise) -> Bool
    let onOpen: (PlannedExercise) -> Void
    let onSwap: (PlannedExercise) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryPill(category: block.kind.category, title: block.title)
                Spacer()
                Text("\(block.targetMin) min").font(Theme.label(13)).foregroundStyle(Theme.muted)
            }
            if let note = block.note { Text(note).font(.footnote).foregroundStyle(Theme.muted) }
            ForEach(block.items) { item in
                ExerciseCard(item: item, block: block, sessionId: sessionId,
                             onOpen: { onOpen(item) }, onSwap: canSwap(item) ? { onSwap(item) } : nil)
            }
        }
    }
}

/// One planned exercise. The whole card opens the exercise page (#101); Swap and the long-press menu replace it.
struct ExerciseCard: View {
    let item: PlannedExercise
    let block: Block
    let sessionId: String
    let onOpen: () -> Void
    var onSwap: (() -> Void)? = nil
    @Environment(AppModel.self) private var model

    private var exercise: Exercise { Exercise.get(item.exerciseId) }
    private var ticked: Bool { model.state.ticked[item.uid] ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status only: set by the workout player (#57).
            Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(ticked ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.15)))
                .accessibilityLabel(ticked ? "Done" : "Not done yet")

            ExerciseThumbnail(exercise: exercise, size: 52)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        if let group = item.group {
                            // Superset / circuit label (#78): same letter = back to back.
                            Text(group)
                                .font(Theme.label(11))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.lime))
                                .accessibilityLabel("Group \(group)")
                        }
                        Text(exercise.name)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .strikethrough(ticked)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 6) {
                        Text(Format.prescription(item.prescription)).font(.subheadline.weight(.semibold)).foregroundStyle(block.kind.category.color)
                        // Gym zone it's done in (#274), when the member set zones up.
                        if let zone = model.gymZone(item.exerciseId) { ZoneTag(zone: zone) }
                    }
                    let meta = [item.prescription.intensity, item.prescription.note].compactMap { $0 }
                    if !meta.isEmpty {
                        Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                    }
                }
                MuscleChips(primary: exercise.primary, secondary: exercise.secondary)
                HStack(alignment: .center) {
                    EquipmentLine(equipment: exercise.equipment)
                    Spacer(minLength: 8)
                    if let onSwap {
                        // A real button inside the tappable card: it wins over the card's tap.
                        Button(action: onSwap) {
                            Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                                .font(Theme.label(13))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Theme.lime))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Swap \(exercise.name)")
                    }
                }
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
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(action: onOpen) { Label("Exercise details", systemImage: "info.circle") }
            if let onSwap {
                Button(action: onSwap) { Label("Swap exercise", systemImage: "arrow.triangle.2.circlepath") }
            }
            // My picks (#204): keep this exercise in every workout's block, or stop.
            if model.canPick(block.kind) {
                let picked = model.isPicked(item.exerciseId, in: block.kind)
                Button {
                    model.togglePick(item.exerciseId, in: block.kind, minutes: max(1, item.estSec / 60))
                } label: {
                    Label(picked ? "Remove from my \(block.kind.flowLabel) picks" : "Always use in \(block.kind.flowLabel)",
                          systemImage: picked ? "pin.slash" : "pin.fill")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Exercise details", onOpen)
        .accessibilityActions {
            if let onSwap { Button("Swap exercise", action: onSwap) }
        }
    }
}
