import APIClient
import SwiftUI
import WorkoutEngine

/// Composer: pick a workout, personal best or badge, add a caption, choose who sees it.
struct ShareWinView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var wins: [WinCard] = []
    @State private var selected: String?
    @State private var caption = ""
    @State private var visibility: CommunityVisibility = .onlyMe
    @State private var task = FormTask()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if wins.isEmpty {
                        Text("Finish a workout to share your first win.")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                    section("Workouts", kind: "workout")
                    section("Personal bests", kind: "record")
                    section("Badges", kind: "badge")

                    Text("Say something").eyebrow()
                    TextField("Optional caption", text: $caption, axis: .vertical)
                        .lineLimit(1...4)
                        .card(padding: 14)
                        .onChange(of: caption) { _, v in if v.count > 280 { caption = String(v.prefix(280)) } }

                    Text("Who can see it").eyebrow()
                    VisibilityPicker(selection: $visibility)

                    ErrorText(message: task.error)
                    Button(task.busy ? "SHARING…" : "SHARE") { share() }
                        .buttonStyle(LimeButtonStyle(fill: selected == nil ? Theme.cardStrong : Theme.lime,
                                                     text: selected == nil ? Color.white.opacity(0.6) : Theme.ink))
                        .disabled(selected == nil || task.busy)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Share a win")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear(perform: buildWins)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func section(_ title: String, kind: String) -> some View {
        let items = wins.filter { $0.kind == kind }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).eyebrow()
                ForEach(items) { w in
                    WinRow(win: w, selected: selected == w.id) { selected = w.id }
                }
            }
        }
    }

    private func buildWins() {
        guard wins.isEmpty else { return }
        visibility = Community.shared.profile?.defaultVisibility ?? .onlyMe
        let history = model.state.history
        let target = model.profile?.sessionsPerWeek ?? 3
        let workouts = history.filter { $0.totalSets > 0 }.sorted { $0.startedAt > $1.startedAt }.prefix(6).map(WinCard.workout)
        let bests = Progression.stats(records: history, weights: model.weightEntries, targetPerWeek: target)
            .personalRecords.prefix(5).map(WinCard.best)
        let badges = Achievements.evaluate(records: history, weights: model.weightEntries, targetPerWeek: target)
            .filter(\.unlocked)
            .sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }
            .prefix(5).map(WinCard.badge)
        wins = Array(workouts) + Array(bests) + Array(badges)
        selected = wins.first?.id
    }

    private func share() {
        guard let w = wins.first(where: { $0.id == selected }) else { return }
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        task.run {
            #if DEBUG
            if model.demo {
                dismiss()
                return
            }
            #endif
            let post = try await model.api.sharePost(
                kind: w.kind, refId: w.refId, visibility: visibility, caption: text.isEmpty ? nil : text, card: w.card)
            Community.shared.insert(post)
            dismiss()
        }
    }
}

private struct WinRow: View {
    let win: WinCard
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 14) {
                IconTile(symbol: win.symbol, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(win.card.title).font(Theme.display(18)).lineLimit(2).minimumScaleFactor(0.75)
                        .multilineTextAlignment(.leading)
                    Text(detail).font(.footnote.weight(.medium)).opacity(0.85).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                if let m = win.card.metric {
                    AccountValue(value: m.value, unit: m.unit)
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2.weight(.bold))
                    .opacity(selected ? 1 : 0.7)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(win.card.gradient))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var detail: String {
        if let s = win.card.subtitle { return s }
        return win.date?.formatted(date: .abbreviated, time: .omitted) ?? ""
    }
}
