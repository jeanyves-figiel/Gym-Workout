import SwiftUI
import WorkoutEngine

// Mobility & recovery days (#619, designs A + B from `apple-tech-radar/x2.png`).

// A: the rest day card's Recover tile (`RestDayCard`, #671) opens the routine for the area trained hardest this week.

/// B: low readiness on a heavy day; Keep puts the card away for today, Swap moves the session to a free day.
struct RecoverSwapCard: View {
    let swap: AppModel.RecoverSwap
    var onKeep: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Readiness low · \(swap.marker)").font(Theme.label(10)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                    Text("Swap \(swap.session.focus.label) for mobility?").font(.system(size: 16, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text("\(swap.session.focus.label) moves to \(WeekSchedule.name(swap.to)).")
                    .font(Theme.label(11)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("Keep", action: onKeep)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.22)))
                Button("Swap") {
                    Haptics.start()
                    withAnimation(.snappy) { model.takeRecoverSwap(swap) }
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.white))
                .foregroundStyle(Theme.ink)
                .accessibilityHint("Moves \(swap.session.displayTitle) to \(WeekSchedule.name(swap.to)) and makes today a recover day")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x3D4BD6), Color(hex: 0x00B3A6)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}
