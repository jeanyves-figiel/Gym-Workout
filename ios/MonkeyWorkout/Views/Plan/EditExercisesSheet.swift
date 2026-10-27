import SwiftUI
import WorkoutEngine

/// Edit a workout's exercises before starting it (#295, design B): compact rows per block with drag ≡, swap, remove,
/// a sets stepper and Add per block; Save shows the new length. This workout only; Reset goes back to the plan.
struct EditExercisesSheet: View {
    let sessionId: String
    /// The workout as planned (or as the library has it), before any edit.
    let base: Session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var blocks: [Block]
    @State private var swapping: PlannedExercise?
    @State private var adding: Block?
    @State private var closeGuard = CloseGuard()
    /// The list as it was when the sheet first opened: closing with changes offers Undo (#285).
    private let start: [Block]

    /// `start`: the list before this round of edits, when reopened by Undo with `blocks` kept.
    init(sessionId: String, base: Session, blocks: [Block], start: [Block]? = nil) {
        self.sessionId = sessionId
        self.base = base
        self.start = start ?? blocks
        _blocks = State(initialValue: blocks)
    }

    /// Undo bar when the list changed and the sheet closed without Save.
    private var undoOffer: UndoOffer? {
        guard blocks != start else { return nil }
        let kept = blocks, first = start, id = sessionId, b = base
        return UndoOffer(title: "Exercise edits closed", detail: undoDetail(b.displayTitle, "\(kept.itemCount) exercises"),
                         symbol: "pencil", colors: WorkoutEngine.Category.mobility.colors) {
            AnyView(EditExercisesSheet(sessionId: id, base: b, blocks: kept, start: first))
        }
    }

    private var minutes: Int { max(1, base.estMin + Int((Double(blocks.estSec - base.blocks.estSec) / 60).rounded())) }

    var body: some View {
        NavigationStack {
            // Explore-style gradient rows per block (#539).
            List {
                ContentTitle(title: "Edit exercises", subtitle: "This workout only · drag ≡ to reorder, swipe to remove")
                    .cardRow()
                ForEach(blocks) { block in
                    Section {
                        ForEach(block.items) { item in
                            row(item, block: block).gradientRow(block.kind.gradient, ink: block.kind.category.ink)
                        }
                        .onMove { from, to in withAnimation { blocks.move(in: block.kind, from: from, to: to) } }
                        .onDelete { idx in
                            let uids = idx.map { block.items[$0].uid }
                            withAnimation { uids.forEach { blocks.remove($0) } }
                        }
                        Button { adding = block } label: {
                            Label("Add to \(block.title)", systemImage: "plus")
                                .font(Theme.label(14))
                                .foregroundStyle(Theme.lime)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.lime, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add exercise to \(block.title)")
                        .cardRow()
                    } header: {
                        HStack {
                            CategoryPill(category: block.kind.category, title: block.title, compact: true)
                            Spacer()
                            Text("\(block.items.count)").font(Theme.label(12)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if blocks != base.blocks {
                    Section {
                        Button("Back to the workout as planned") { withAnimation { blocks = base.blocks } }
                            .foregroundStyle(Theme.lime)
                    } footer: {
                        Text("Changes apply to this workout only.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .themedForm()
            .titleInContent("Edit exercises")
            .toolbar { CloseToolbarItem { dismiss() } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.saveSessionEdit(sessionId, blocks: blocks)
                    closeGuard.done()
                    dismiss()
                } label: {
                    Text("Save · \(minutes)′ · \(blocks.itemCount) exercise\(blocks.itemCount == 1 ? "" : "s")")
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(blocks.itemCount == 0)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.bg.ignoresSafeArea())
            }
            .sheet(item: $swapping) { item in
                SwapExerciseSheet(exerciseId: item.exerciseId, uid: item.uid, onPick: { id in
                    withAnimation { blocks.swap(item.uid, to: id) }
                })
            }
            .sheet(item: $adding) { block in
                ExercisePickerView(limit: 10) { list in
                    withAnimation { for e in list { blocks.add(e, to: block.kind, sessionId: sessionId) } }
                }
            }
        }
        .presentationDetents([.large])
        .undoableClose(closeGuard, offer: undoOffer)
    }

    private func row(_ item: PlannedExercise, block: Block) -> some View {
        let e = Exercise.get(item.exerciseId)
        return HStack(spacing: 10) {
            ExerciseThumbnail(exercise: e, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let g = item.group {
                        Text(g).font(Theme.label(10)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.lime))
                    }
                    // Two lines that shrink a little, ahead of the fixed controls (#823): names were cut to "Wal…".
                    Text(e.name).font(Theme.label(14)).lineLimit(2).minimumScaleFactor(0.75)
                }
                HStack(spacing: 6) {
                    Text(item.prescription.reps).font(.caption.weight(.semibold)).opacity(0.85)
                    // Split a superset / circuit into straight sets (#352), on its first member.
                    if item.group?.hasSuffix("1") == true, item.supersetWith == nil {
                        Button { withAnimation { blocks.split(item.uid) } } label: {
                            Label("Split", systemImage: "scissors")
                                .font(Theme.label(10))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Split \(item.group?.first.map(String.init) ?? "") into straight sets")
                    }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            SetsStepper(sets: item.prescription.sets) { n in withAnimation { blocks.setSets(item.uid, n) } }
            Button { swapping = item } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.lime))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Swap \(e.name)")
        }
        .padding(.leading, item.supersetWith == nil ? 0 : 14)
    }
}

/// − sets + in one capsule.
private struct SetsStepper: View {
    let sets: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            step("minus", sets - 1, enabled: sets > CustomWorkout.setsRange.lowerBound)
            Text("\(sets)").font(Theme.label(14)).monospacedDigit().frame(minWidth: 18)
            step("plus", sets + 1, enabled: sets < CustomWorkout.setsRange.upperBound)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(HierarchicalShapeStyle.primary.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sets) sets")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: if sets < CustomWorkout.setsRange.upperBound { onChange(sets + 1) }
            case .decrement: if sets > CustomWorkout.setsRange.lowerBound { onChange(sets - 1) }
            @unknown default: break
            }
        }
    }

    private func step(_ symbol: String, _ value: Int, enabled: Bool) -> some View {
        Button { onChange(value) } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .heavy)).frame(width: 24, height: 24)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "One set fewer" : "One set more")
    }
}
