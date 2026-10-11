import SwiftUI
import WorkoutEngine

/// Swap a planned exercise (#101): best matches for the same muscles with the member's equipment, or any
/// exercise from the full library (custom ones included). This session only, or kept for that day in future weeks.
struct SwapExerciseSheet: View {
    let exerciseId: String
    let uid: String
    /// Called after a swap or a kept swap removed, before the sheet closes.
    var onDone: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var keep = false
    @State private var searching = false
    @State private var picked: String?
    @State private var gate: ProGate?

    private var exercise: Exercise { Exercise.get(exerciseId) }

    private var session: Session? {
        model.plannedItem(uid: uid).flatMap { model.session($0.sessionId) }
    }

    private var dayName: String {
        session?.weekday.map(WeekSchedule.name) ?? "this day"
    }

    private var options: [Exercise] {
        guard let profile = model.profile else { return [] }
        return Array(exercise.swapOptions(for: profile).prefix(12))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    current
                    keepToggle
                    if let rule = model.keptSwap(uid: uid), let original = Exercise.find(rule.from) {
                        Button {
                            model.removeKeptSwap(rule)
                            onDone?()
                            dismiss()
                        } label: {
                            Label("Back to \(original.name) every \(dayName)", systemImage: "arrow.uturn.backward")
                                .font(Theme.label(14))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .card(padding: 0)
                        }
                        .buttonStyle(.plain)
                    }
                    if !options.isEmpty {
                        GradientSection(symbol: "arrow.triangle.2.circlepath", title: "Best matches", gradient: exercise.category.gradient) {
                            ForEach(options) { e in
                                Button { apply(e.id) } label: { OptionRow(exercise: e) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    Button { searching = true } label: {
                        Label("Search all exercises", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(LimeButtonStyle())
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Swap exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            .sheet(isPresented: $searching, onDismiss: {
                if let picked { apply(picked) }
            }) {
                ExercisePickerView(limit: 1) { list in
                    picked = list.first { $0.id != exerciseId }?.id
                }
            }
        }
        .presentationDetents([.large])
    }

    private var current: some View {
        HStack(spacing: 14) {
            ExerciseThumbnail(exercise: exercise, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Replacing").font(Theme.label(12)).opacity(0.8)
                Text(exercise.name).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.8)
                Text(exercise.primary.map(\.name).joined(separator: " · ")).font(.caption.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(exercise.category.gradient)
    }

    private var keepToggle: some View {
        Toggle(isOn: Binding(get: { keep }, set: { on in
            if on { ProStore.shared.run(.keepSwap, $gate) { keep = true } } else { keep = false }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Keep for \(dayName) in future weeks").font(.body.weight(.bold))
                    ProBadge()
                }
                Text(keep ? "Replaces it every week it comes up on \(dayName)." : "Only this session.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.lime)
        .card(padding: 14)
        .proPaywall($gate)
    }

    private func apply(_ id: String) {
        model.swap(uid: uid, to: id, keep: keep)
        onDone?()
        dismiss()
    }
}

private struct OptionRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.body.weight(.bold)).multilineTextAlignment(.leading)
                Text(exercise.primary.map(\.name).joined(separator: " · ")).font(.caption.weight(.medium)).opacity(0.85)
                Text(exercise.equipment.isEmpty ? "Bodyweight" : exercise.equipment.map(\.label).joined(separator: " · "))
                    .font(.caption2.weight(.semibold)).opacity(0.7)
            }
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath").font(.body.weight(.bold))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
        .contentShape(Rectangle())
    }
}
