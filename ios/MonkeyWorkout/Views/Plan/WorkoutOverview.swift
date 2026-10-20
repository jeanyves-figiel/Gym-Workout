import SwiftUI
import WorkoutEngine

// What's left in the workout without leaving the player (#361): a read-only Workout map behind the progress dots and,
// since #373, the smart Up next bar (the Coming up strip it replaces moved with the free space). Nothing here edits.

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

/// Up next, always in the same place above the controls (#373, design C from `player-layout/portrait.png`): the next
/// set or exercise, the two after it, and what's left with the end time. Tap or swipe up for the Workout map.
/// Walk between two zones of the home gym's floor plan (#406).
struct GymWalk {
    let layout: GymLayout
    let from: String?
    let to: String
}

struct SmartUpNextBar: View {
    /// nil on the last item: the workout finishes next.
    let next: WorkoutPlayerView.UpNext?
    /// The next exercises after `next`, in the map's order (two are shown).
    let then: [OverviewItem]
    let left: Int
    let doneBy: Date
    let fallback: [Color]
    /// Walk to the next zone (#406): a mini floor plan on the right.
    var walk: GymWalk? = nil
    let onMap: () -> Void

    var body: some View {
        Button(action: onMap) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    thumb(next?.exercise, symbol: next == nil ? "flag.checkered" : "arrow.right", size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(next?.eyebrow ?? "Up next").font(Theme.label(10)).tracking(1.2).textCase(.uppercase)
                            .opacity(0.85).lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(next?.title ?? "Finish workout").font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.7)
                            if let d = next?.detail, !d.isEmpty {
                                Text(d).font(Theme.label(11)).opacity(0.9).lineLimit(1).layoutPriority(-1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if let walk {
                        GymMiniMap(layout: walk.layout, from: walk.from, to: walk.to).frame(height: 34)
                    }
                }
                HStack(spacing: 5) {
                    if !then.isEmpty {
                        Text("then").font(Theme.label(10)).opacity(0.8)
                        ForEach(then.prefix(2)) { o in
                            HStack(spacing: 3) {
                                thumb(o.exercise, symbol: o.category.symbol, size: 16)
                                Text(o.exercise.name).font(Theme.label(10)).lineLimit(1)
                            }
                            .layoutPriority(-1)
                        }
                    }
                    Spacer(minLength: 4)
                    Label(left == 0 ? "done ~\(time)" : "\(left) left · ~\(time)", systemImage: "chevron.up")
                        .labelStyle(TrailingIcon())
                        .font(Theme.label(10)).monospacedDigit()
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.28)))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: next?.colors ?? fallback, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { v in
            if v.translation.height < -30 { onMap() }
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(next.map { "\($0.eyebrow): \($0.title)" } ?? "Finish workout next"). \(left) exercises left. Open workout map")
        .accessibilityIdentifier("player.upNext")
    }

    private var time: String { doneBy.formatted(date: .omitted, time: .shortened) }

    @ViewBuilder
    private func thumb(_ exercise: Exercise?, symbol: String, size: CGFloat) -> some View {
        if let exercise, ExerciseImage.hasMedia(exercise) {
            ExerciseThumbnail(exercise: exercise, size: size)
        } else {
            Image(systemName: exercise?.category.symbol ?? symbol)
                .font(.system(size: size * 0.42, weight: .heavy))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(.white.opacity(0.2)))
        }
    }

    /// The items after `next` that are still to do (skipped and finished-early ones are left out).
    static func after(_ items: [OverviewItem], current: String, next: Exercise?) -> [OverviewItem] {
        Array(items.filter { $0.state == .left && $0.id != current && $0.exercise.id != next?.id }.prefix(2))
    }
}

/// "14 left · ~7:30 ⌃": title first, icon after.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.title; configuration.icon.imageScale(.small) }
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
        .readableWidth()
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
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
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
