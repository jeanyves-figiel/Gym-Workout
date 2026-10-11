import SwiftUI
import WorkoutEngine

extension VaryPart {
    var title: String {
        switch self {
        case .accessories: "Accessories"
        case .mainLifts: "Main lifts"
        case .warmup: "Warm-up & mobility"
        case .power: "Explosive"
        case .cardio: "Cardio machine"
        }
    }

    func subtitle(on: Bool) -> String {
        guard on else { return self == .mainLifts ? "Kept for progression" : "Kept" }
        return switch self {
        case .accessories: "Same movement, new pick"
        case .mainLifts: "New lift, same pattern"
        case .warmup: "Same joints and regions"
        case .power: "Same jump or throw type"
        case .cardio: "Same intervals, other machine"
        }
    }

    var symbol: String {
        switch self {
        case .accessories: "dumbbell.fill"
        case .mainLifts: "figure.strengthtraining.traditional"
        case .warmup: "figure.flexibility"
        case .power: "bolt.fill"
        case .cardio: "heart.fill"
        }
    }

    var gradient: LinearGradient {
        let c: WorkoutEngine.Category = switch self {
        case .accessories: .warmup
        case .mainLifts: .power
        case .warmup: .mobility
        case .power: .stretch
        case .cardio: .cardio
        }
        return c.gradient
    }
}

/// One preview row: `from` → `to`, or `kept` (member locked it).
private struct Change: Identifiable {
    let uid: String
    let from: String
    let to: String
    let kept: Bool
    var id: String { uid }
}

/// "New variation" (#98): the member picks the days and what changes, previews every swap, keeps any
/// single exercise, reshuffles the rest and applies. Done sessions never change.
struct VariationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<String>
    @State private var parts = VaryPart.defaults
    @State private var keep: Set<String> = []
    @State private var seed = UInt32.random(in: 0...UInt32.max)
    @State private var confirmReset = false

    /// `keep`: items locked at start (exercises the member swapped and kept, #101).
    init(days: Set<String>, keep: Set<String> = []) {
        _days = State(initialValue: days)
        _keep = State(initialValue: keep)
    }

    private var request: VaryRequest { VaryRequest(sessions: days, parts: parts, keep: keep, seed: seed) }
    private var swaps: [String: String] { model.previewVariation(request) }

    /// Per picked day: swaps the preview would make, plus exercises the member chose to keep.
    private func changes(_ swaps: [String: String]) -> [(Session, [Change])] {
        guard let before = model.plan(with: model.currentSwaps), let after = model.plan(with: swaps) else { return [] }
        return zip(before.sessions, after.sessions).compactMap { b, a in
            guard days.contains(b.id) else { return nil }
            let rows = zip(b.blocks.flatMap(\.items), a.blocks.flatMap(\.items)).compactMap { x, y -> Change? in
                if keep.contains(x.uid) { return Change(uid: x.uid, from: x.exerciseId, to: x.exerciseId, kept: true) }
                return x.exerciseId == y.exerciseId ? nil : Change(uid: x.uid, from: x.exerciseId, to: y.exerciseId, kept: false)
            }
            return rows.isEmpty ? nil : (b, rows)
        }
    }

    var body: some View {
        let preview = self.swaps
        let list = changes(preview)
        let changed = list.filter { $0.1.contains { !$0.kept } }.count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick what changes. Each swap uses the same movement, so every day keeps its muscle focus.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)

                    Text("Days").eyebrow().padding(.top, 6)
                    dayTiles

                    Text("What changes").eyebrow().padding(.top, 10)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(VaryPart.allCases) { part in
                            PartCard(part: part, on: parts.contains(part)) {
                                if parts.contains(part) { parts.remove(part) } else { parts.insert(part) }
                            }
                        }
                    }

                    HStack {
                        Text("Preview").eyebrow()
                        Spacer()
                        if !list.isEmpty {
                            Text("Tap \(Image(systemName: "lock.fill")) to keep").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.top, 10)
                    if list.isEmpty {
                        Text(days.isEmpty ? "Pick at least one day." : parts.isEmpty ? "Pick at least one thing to change." : "Nothing to swap with these choices.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                    ForEach(list, id: \.0.id) { session, rows in
                        DayPreview(session: session, rows: rows) { uid in
                            if keep.contains(uid) { keep.remove(uid) } else { keep.insert(uid) }
                        }
                    }
                    Text("Done sessions never change. Undo from Train after applying.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("New variation")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !model.currentSwaps.isEmpty {
                    ToolbarItem(placement: .primaryAction) { Button("Reset") { confirmReset = true } }
                }
            }
            .confirmationDialog("Back to the original plan?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset all swaps", role: .destructive) {
                    model.resetVariation()
                    dismiss()
                }
            } message: {
                Text("Removes every variation swap of this week. Done sessions keep what you did.")
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Button {
                        seed = UInt32.random(in: 0...UInt32.max)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(LimeButtonStyle(fill: Theme.cardStrong, text: .white))
                    .frame(maxWidth: 140)
                    .disabled(list.isEmpty)

                    Button {
                        model.applyVariation(preview, days: changed)
                        dismiss()
                    } label: {
                        Text(changed == 0 ? "APPLY" : "APPLY TO \(changed) DAY\(changed == 1 ? "" : "S")")
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(changed == 0)
                    .opacity(changed == 0 ? 0.5 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.bg.opacity(0.92).ignoresSafeArea())
            }
            .animation(.spring(duration: 0.3), value: parts)
            .animation(.spring(duration: 0.3), value: days)
        }
        .preferredColorScheme(.dark)
    }

    private var dayTiles: some View {
        let open = Set(model.variableSessions.map(\.id))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.plan?.sessions ?? []) { s in
                    let enabled = open.contains(s.id)
                    let on = enabled && days.contains(s.id)
                    Button {
                        if on { days.remove(s.id) } else { days.insert(s.id) }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(s.index + 1)").font(Theme.display(22))
                            Text(enabled ? s.focus.label : (s.isPlanInsert ? "Library" : "Done"))
                                .font(Theme.label(10))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if !enabled {
                                Image(systemName: s.isPlanInsert ? "books.vertical.fill" : "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 74, height: 74)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(on ? AnyShapeStyle(WorkoutEngine.Category.strength.gradient) : AnyShapeStyle(Theme.cardStrong)))
                        .opacity(enabled ? 1 : 0.35)
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .accessibilityLabel("Day \(s.index + 1), \(s.focus.label)\(enabled ? "" : ", locked")")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// Explore-style toggle card for one `VaryPart`.
private struct PartCard: View {
    let part: VaryPart
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: part.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(part.title).font(.system(size: 14, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(part.subtitle(on: on)).font(.system(size: 10, weight: .semibold)).opacity(0.8).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(on ? AnyShapeStyle(part.gradient) : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(part.title), \(on ? "changes" : "kept")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One day of the preview: old → new rows with a keep lock.
private struct DayPreview: View {
    let session: Session
    let rows: [Change]
    let toggle: (String) -> Void

    var body: some View {
        let swapped = rows.filter { !$0.kept }.count
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Day \(session.index + 1) · \(session.focus.label)").font(.system(size: 15, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(swapped) change\(swapped == 1 ? "" : "s")").font(Theme.label(11)).foregroundStyle(Theme.lime)
            }
            .padding(.bottom, 6)
            ForEach(rows) { row in
                let from = Exercise.find(row.from), to = Exercise.find(row.to)
                HStack(spacing: 10) {
                    if let to { ExerciseThumbnail(exercise: to, size: 36) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(to?.name ?? row.to)
                            .font(.system(size: 14, weight: row.kept ? .semibold : .bold))
                            .foregroundStyle(row.kept ? Theme.muted : .white)
                            .lineLimit(1)
                        Text(row.kept ? "Kept" : "was \(from?.name ?? row.from)")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button { toggle(row.uid) } label: {
                        Image(systemName: row.kept ? "lock.fill" : "lock.open")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(row.kept ? Theme.ink : .white)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(row.kept ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.kept ? "Kept \(from?.name ?? ""), tap to vary" : "Keep \(from?.name ?? "")")
                }
                .padding(.vertical, 6)
                .overlay(alignment: .top) { Divider().overlay(Theme.stroke) }
            }
        }
        .card(padding: 14)
    }
}
