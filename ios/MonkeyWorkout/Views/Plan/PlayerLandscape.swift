import SwiftUI
import UIKit
import WorkoutEngine

// Landscape workout player (#362; layout #373, A + C mix from `player-layout/landscape-mix.png`): the phone lies on
// its side on a machine or rack. Left: the exercise card with its picture; right: the one input, the controls and the
// smart Up next bar. The rings below show rest and timed work there.

/// Rest countdown: 3-2-1 taps, then it closes by itself (#357), as the upright player's rest overlay does.
struct RestRing: View {
    let end: Date
    let total: Int
    let color: Color
    let onDone: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let left = max(0, end.timeIntervalSince(ctx.date))
            ZStack {
                ProgressRing(progress: left / Double(max(1, total)), lineWidth: 12, colors: [color, Theme.lime])
                VStack(spacing: 0) {
                    Text(left > 3 ? "Rest" : "Get ready").eyebrow()
                    Text(Format.rest(Int(left.rounded(.up)))).font(Theme.display(40)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                .padding(14)
            }
        }
        .foregroundStyle(.white)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .task(id: end) {
            for tick in [3.0, 2.0, 1.0] {
                let wait = end.timeIntervalSinceNow - tick
                guard wait > -0.5 else { continue }
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            onDone()
        }
    }
}

/// Between rests: sets done as the arc, time on the current set in the middle.
struct SetRing: View {
    let since: Date
    let done: Int
    let sets: Int
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { ctx in
            ZStack {
                ProgressRing(progress: Double(done) / Double(max(1, sets)), lineWidth: 12, colors: [color, Theme.lime])
                VStack(spacing: 0) {
                    Text(done >= sets ? "All done" : "Set \(done + 1) of \(sets)").eyebrow()
                    Text(Format.elapsed(ctx.date.timeIntervalSince(since))).font(Theme.display(34)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                .padding(14)
            }
        }
        .foregroundStyle(.white)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
    }
}
