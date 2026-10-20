import SwiftUI
import WorkoutEngine

/// Change (#391, design C): the player's one place to swap, remove or report missing equipment for the exercise on
/// screen. Options that don't apply stay visible but off, with the reason, so the sheet always looks the same.
struct ChangeExerciseSheet: View {
    enum Choice { case swap, remove, notHere, taken }

    let exercise: Exercise
    /// Sets already logged on it: swap and remove are then off (Skip moves on instead).
    let setsDone: Int
    let canSwap: Bool
    let canRemove: Bool
    let canNotHere: Bool
    /// Zone it's done in (#406): offers "Taken?", a swap to the same muscles in a free zone.
    var takenZone: String? = nil
    let onPick: (Choice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ExerciseThumbnail(exercise: exercise, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Change").eyebrow()
                    Text(exercise.name).font(Theme.display(20)).lineLimit(2).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .heavy))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
                }
                .accessibilityLabel("Close")
            }
            option("Swap for similar", symbol: "arrow.triangle.2.circlepath", fill: Theme.lime, ink: Theme.ink,
                   enabled: canSwap, id: "change.swap") { pick(.swap) }
            if let takenZone {
                option("Taken? Free zone instead of \(takenZone)", symbol: "person.3.fill",
                       fill: Color(red: 1, green: 0.54, blue: 0.24), ink: .white, enabled: canSwap, id: "change.taken") { pick(.taken) }
            }
            option("Remove from workout", symbol: "trash", fill: Color(red: 1, green: 0.24, blue: 0.35), ink: .white,
                   enabled: canRemove, id: "change.remove") { pick(.remove) }
            if canNotHere {
                option("Not at this gym", symbol: "questionmark.circle", fill: Theme.cardStrong, ink: .white,
                       enabled: true, id: "change.notHere") { pick(.notHere) }
            }
            if setsDone > 0 {
                Label("Sets logged on it: Skip ⏭ moves on.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .presentationDetents([.height((setsDone > 0 ? 330 : 300) + (takenZone == nil ? 0 : 62))])
    }

    private func pick(_ c: Choice) {
        onPick(c)
        dismiss()
    }

    private func option(_ title: String, symbol: String, fill: Color, ink: Color, enabled: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.label(16))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityIdentifier(id)
    }
}
