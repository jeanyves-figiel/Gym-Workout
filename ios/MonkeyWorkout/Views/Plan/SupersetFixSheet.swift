import SwiftUI
import WorkoutEngine

/// "Machines not next to each other?" (#352, design C): opened from the player's superset chip. Split the group for
/// today, swap the partner for an exercise nearby, or set gym zones so supersets stay in one zone from then on.
struct SupersetFixSheet: View {
    enum Choice { case split, swap, zones }

    /// "Superset A1 + A2" / "Circuit A1 + A2 + A3".
    let title: String
    /// The member that could be swapped (no sets done yet); nil hides that choice.
    let partner: String?
    /// Zones belong to the home gym; a trip's gym hides the choice.
    let canZones: Bool
    let zonesSet: Bool
    let onPick: (Choice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("MACHINES NOT NEXT TO EACH OTHER?")
                    .font(Theme.label(12)).tracking(1).foregroundStyle(Theme.muted)
                option(.split, symbol: "scissors", title: "Split for today",
                       detail: "Straight sets: finish this exercise, then the next", colors: UndoOffer.warm)
                if let partner {
                    option(.swap, symbol: "arrow.triangle.2.circlepath", title: "Swap \(partner)",
                           detail: "Pick one done where you are", colors: WorkoutEngine.Category.cardio.colors)
                }
                if canZones {
                    option(.zones, symbol: "map.fill", title: zonesSet ? "Edit gym zones" : "Set gym zones",
                           detail: "Supersets stay in one zone · plan follows after this workout",
                           colors: WorkoutEngine.Category.mobility.colors)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSheetBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.height(partner == nil || !canZones ? 290 : 370)])
        .preferredColorScheme(.dark)
    }

    private func option(_ choice: Choice, symbol: String, title: String, detail: String, colors: [Color]) -> some View {
        Button {
            onPick(choice)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .heavy))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail).font(.caption.weight(.semibold)).opacity(0.88).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
    }
}
