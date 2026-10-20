import SwiftUI
import WorkoutEngine

/// "Not here?" (#162): the gym doesn't have what this exercise needs. Pick the missing item; it's removed from that
/// gym and this week's remaining exercises there that need it are swapped for the best match.
struct NotHereSheet: View {
    let exerciseId: String
    let uid: String
    var onDone: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<Equipment> = []

    private var exercise: Exercise { Exercise.get(exerciseId) }
    private var gymEquipment: [Equipment] { model.gymEquipment(forItem: uid) }
    /// What the exercise needs that the gym's list says is there.
    private var candidates: [Equipment] { exercise.equipment.filter { gymEquipment.contains($0) } }

    private var replacement: Exercise? {
        guard var p = model.profile, !picked.isEmpty else { return nil }
        p.equipment = gymEquipment.filter { !picked.contains($0) }
        return exercise.swapOptions(for: p).first { $0.missing(from: p.equipment).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ExerciseThumbnail(exercise: exercise, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Not at \(model.gymName(forItem: uid))?").font(Theme.label(12)).opacity(0.85).lineLimit(2)
                            Text(exercise.name).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .gradientCard(exercise.category.gradient, ink: exercise.category.ink)

                    Text(candidates.count > 1 ? "What's missing?" : "Missing here").eyebrow()
                    EquipmentPickGrid(items: candidates, picked: $picked)

                    if let r = replacement {
                        HStack(spacing: 12) {
                            ExerciseThumbnail(exercise: r, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Swaps to").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                                Text(r.name).font(.body.weight(.bold))
                            }
                            Spacer()
                        }
                        .card(padding: 14)
                    }
                    Text("Removed from this gym's list, so it isn't planned here again. Other exercises this week that need it get another pick too.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Button("REMOVE & SWAP") {
                        model.notHere(Array(picked), uid: uid)
                        onDone?()
                        dismiss()
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(picked.isEmpty)
                    .opacity(picked.isEmpty ? 0.5 : 1)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Not here?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear { if candidates.count == 1 { picked = Set(candidates) } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

/// Picture tiles where a tap marks the item as missing.
private struct EquipmentPickGrid: View {
    let items: [Equipment]
    @Binding var picked: Set<Equipment>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 12) {
            ForEach(items) { e in
                EquipmentTile(item: e, on: picked.contains(e)) {
                    if picked.contains(e) { picked.remove(e) } else { picked.insert(e) }
                }
            }
        }
    }
}
