import SwiftUI
import WorkoutEngine

// What's left in the workout without leaving the player (#361, designs A + C from `workout-overview/proposals.png`):
// a "Coming up" strip in the player's free space and a read-only Workout map behind the progress dots. Nothing here edits.

/// One item of the workout as the overview shows it.
struct OverviewItem: Identifiable {
    enum Status { case done, skipped, now, left }

    let item: PlannedExercise
    let block: Block
    let state: Status
    let done: Int
    var id: String { item.uid }
    var exercise: Exercise { Exercise.get(item.exerciseId) }
    var sets: Int { max(1, item.prescription.sets) }
    var category: WorkoutEngine.Category { ExerciseHeroCard.category(exercise, in: block) }
    var setsLeft: Int { state == .done || state == .skipped ? 0 : sets - min(done, sets) }

    /// Every item of `blocks` with its state. Items behind `current` (outside its superset / circuit) with sets
    /// still open were skipped, as Finish early counts them.
    static func list(_ blocks: [Block], setsDone: [String: Int], current: String?) -> [OverviewItem] {
        let behind = FinishEarly.behind(blocks, setsDone: setsDone, current: current)
        return blocks.flatMap { b in
            b.items.map { it in
                let sets = max(1, it.prescription.sets)
                let done = setsDone[it.uid] ?? 0
                let state: Status = it.uid == current ? .now
                    : done >= sets ? .done
                    : (behind[it.uid] ?? 0) >= sets ? .skipped
                    : .left
                return OverviewItem(item: it, block: b, state: state, done: done)
            }
        }
    }

    /// Estimated end of what's left, from now.
    static func doneBy(_ blocks: [Block], setsDone: [String: Int], current: String?) -> Date {
        let sec = FinishEarly.remainingSec(blocks, setsDone: FinishEarly.behind(blocks, setsDone: setsDone, current: current))
        return Date().addingTimeInterval(TimeInterval(sec))
    }
}

private func blockLabel(_ b: Block) -> String {
    b.title.isEmpty ? (b.kind.category == .warmup ? "Warm-up" : b.kind.category.rawValue.capitalized) : b.title
}

private func target(_ p: Prescription) -> String { p.sets > 1 ? "\(p.sets) × \(p.reps)" : p.reps }

/// Design C: the exercises still to do as bold tiles in the block's colours. Swipe sideways; a tap shows the exercise.
struct ComingUpStrip: View {
    let items: [OverviewItem]
    let doneBy: Date
    let onPeek: (Exercise) -> Void
    let onMap: () -> Void

    var body: some View {
        let left = items.filter { $0.state == .left }
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onMap) {
                HStack(spacing: 6) {
                    Text("Coming up · \(left.count) left · done ~\(doneBy.formatted(date: .omitted, time: .shortened))")
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Label("Map", systemImage: "list.bullet").labelStyle(.titleAndIcon)
                }
                .font(Theme.label(11)).tracking(1).textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(left.count) exercises left. Open workout map")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(left) { o in
                        Button { onPeek(o.exercise) } label: { tile(o) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
        .foregroundStyle(.white)
    }

    /// Compact (78 pt) so the strip fits the free space under the exercise card on most phones.
    private func tile(_ o: OverviewItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if ExerciseImage.hasMedia(o.exercise) {
                ExerciseThumbnail(exercise: o.exercise, size: 30)
            } else {
                Image(systemName: o.category.symbol).font(.system(size: 13, weight: .heavy))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.22)))
            }
            Spacer(minLength: 0)
            Text(o.exercise.name).font(Theme.display(13)).lineLimit(1).minimumScaleFactor(0.7)
            Text(target(o.item.prescription)).font(Theme.label(10)).opacity(0.9).lineLimit(1)
        }
        .padding(8)
        .frame(width: 124, height: 78, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(o.category.gradient))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the exercise")
    }
}

/// Design A: the whole workout, block by block — done, now and still to do — with what's left and the end time.
struct WorkoutMapSheet: View {
    let blocks: [Block]
    let setsDone: [String: Int]
    let current: String
    @Environment(\.dismiss) private var dismiss
    @State private var peek: Exercise?

    var body: some View {
        let items = OverviewItem.list(blocks, setsDone: setsDone, current: current)
        let left = items.filter { $0.state == .left || $0.state == .now }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    HStack(spacing: 8) {
                        stat("\(left.count)", "Exercises left")
                        stat("\(items.reduce(0) { $0 + $1.setsLeft })", "Sets left")
                        stat("~" + OverviewItem.doneBy(blocks, setsDone: setsDone, current: current)
                                .formatted(date: .omitted, time: .shortened), "Done by")
                    }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                        let rows = items.filter { r in b.items.contains { $0.uid == r.id } }
                        if !rows.isEmpty {
                            blockCard(b, rows: rows)
                            ForEach(rows) { r in row(r).id(r.id) }
                        }
                    }
                }
                .padding(20)
            }
            .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .sheet(item: $peek) { FormSheet(exercise: $0) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout map").eyebrow()
                Text("What's left").font(Theme.display(26))
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.cardStrong))
            }
            .accessibilityLabel("Close")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(22)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.label(9)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.muted).lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .accessibilityElement(children: .combine)
    }

    private func blockCard(_ b: Block, rows: [OverviewItem]) -> some View {
        let finished = rows.filter { $0.state == .done || $0.state == .skipped }.count
        let status = finished == rows.count ? "✓ \(rows.count)/\(rows.count)"
            : rows.contains { $0.state == .now } ? "\(finished + 1) of \(rows.count)"
            : "\(rows.count) · ~\(max(1, Int(b.estMin.rounded()))) min"
        return HStack(spacing: 10) {
            Image(systemName: b.kind.category.symbol).font(.system(size: 15, weight: .heavy))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.22)))
            Text(blockLabel(b).uppercased()).font(Theme.label(13)).tracking(1.1).lineLimit(1)
            Spacer(minLength: 4)
            Text(status).font(Theme.display(15)).monospacedDigit()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(b.kind.category.gradient))
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private func row(_ r: OverviewItem) -> some View {
        Button { peek = r.exercise } label: {
            HStack(spacing: 10) {
                if ExerciseImage.hasMedia(r.exercise) {
                    ExerciseThumbnail(exercise: r.exercise, size: 36)
                } else {
                    Image(systemName: r.category.symbol).font(.system(size: 14, weight: .heavy))
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(r.category.color.opacity(0.35)))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.exercise.name).font(Theme.label(15)).lineLimit(1)
                        .strikethrough(r.state == .skipped)
                    Text(detail(r)).font(Theme.label(11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                tag(r.state)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.lime, lineWidth: r.state == .now ? 2 : 0))
            .opacity(r.state == .done || r.state == .skipped ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the exercise")
    }

    private func detail(_ r: OverviewItem) -> String {
        let t = target(r.item.prescription)
        switch r.state {
        case .now: return r.sets > 1 ? "\(t) · set \(min(r.done + 1, r.sets)) of \(r.sets)" : t
        case .done: return t
        case .skipped: return r.done > 0 ? "\(t) · \(r.done) done" : t
        case .left: return r.item.group.map { "\(t) · \($0)" } ?? t
        }
    }

    @ViewBuilder
    private func tag(_ s: OverviewItem.Status) -> some View {
        switch s {
        case .now:
            Text("NOW").font(Theme.label(10)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.lime))
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.lime)
                .accessibilityLabel("Done")
        case .skipped:
            Text("SKIPPED").font(Theme.label(9)).padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Theme.cardStrong))
        case .left:
            EmptyView()
        }
    }
}
