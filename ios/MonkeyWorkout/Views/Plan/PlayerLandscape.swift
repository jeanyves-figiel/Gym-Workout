import SwiftUI
import UIKit
import WorkoutEngine

// Landscape workout player (#362, design C "cockpit" from landscape-player/proposals.png): the phone lies on its side
// on a machine or rack. Left: what's coming; middle: the exercise and its one input; right: the rest/set ring and buttons.

/// What's on now and next, top to bottom. Tap a row for that exercise's setup and technique.
struct ComingUpColumn: View {
    struct Row: Identifiable {
        let id: String
        let next: WorkoutPlayerView.UpNext
        var current = false
    }

    let rows: [Row]
    /// Mobility drill paired with the exercise, shown while resting.
    var drill: Exercise?
    let onTap: (Exercise) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let drill {
                row(UpNextCard(title: drill.name, eyebrow: "During rest", detail: "5–6 slow reps", exercise: drill,
                               colors: WorkoutEngine.Category.mobility.colors, compact: true), exercise: drill)
            }
            ForEach(rows.prefix(drill == nil ? 5 : 4)) { r in
                row(UpNextCard(title: r.next.title, eyebrow: r.next.eyebrow, detail: r.next.detail, exercise: r.next.exercise,
                               colors: r.next.colors, compact: true)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Theme.lime, lineWidth: r.current ? 2 : 0)),
                    exercise: r.next.exercise)
            }
            Spacer(minLength: 0)
        }
        .clipped()
    }

    @ViewBuilder
    private func row(_ card: some View, exercise: Exercise?) -> some View {
        if let exercise {
            Button { onTap(exercise) } label: { card }
                .buttonStyle(.plain)
                .accessibilityHint("Shows setup and technique")
        } else {
            card
        }
    }
}

/// Rest countdown with a buzz at zero (the upright player shows it in its rest overlay).
struct RestRing: View {
    let end: Date
    let total: Int
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let left = max(0, end.timeIntervalSince(ctx.date))
            ZStack {
                ProgressRing(progress: left / Double(max(1, total)), lineWidth: 12, colors: [color, Theme.lime])
                VStack(spacing: 0) {
                    Text(left > 0 ? "Rest" : "Go!").eyebrow()
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
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
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
