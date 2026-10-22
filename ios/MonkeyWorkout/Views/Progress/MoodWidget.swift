import Charts
import SwiftUI
import WorkoutEngine

/// Mood vs training (#614 B): the last workouts' effort as bars and the face picked after each as dots, with the
/// average feeling on the right. Faces come from the finish screen (also saved to Apple Health as State of Mind).
struct MoodWidget: View {
    let widget: ProgressWidget
    @Environment(AppModel.self) private var model

    private struct Point: Identifiable {
        let id: UUID
        let index: Int
        let effort: Int
        let feel: Feel
    }

    /// Up to 10 most recent workouts with a face, oldest first.
    private var points: [Point] {
        let recent = model.history.filter { model.feel(of: $0.id) != nil }.prefix(10).reversed()
        return recent.enumerated().compactMap { i, r in
            model.feel(of: r.id).map { Point(id: r.id, index: i, effort: model.effort(of: r).value, feel: $0) }
        }
    }

    var body: some View {
        let pts = points
        if pts.count < 2 {
            ProgressWidgetPlaceholder(widget: widget, note: "Pick a face after two workouts to see mood against effort")
        } else {
            let avg = Double(pts.map(\.feel.rawValue).reduce(0, +)) / Double(pts.count)
            let face = Feel(rawValue: Int(avg.rounded())) ?? .good
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: widget.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(widget.title).font(Theme.display(18))
                        Text("Bars: effort · faces: how you felt").font(.caption.weight(.semibold)).opacity(0.9)
                    }
                    Spacer(minLength: 4)
                    Text(face.emoji).font(.system(size: 30))
                        .accessibilityLabel("Usually \(face.label.lowercased())")
                }
                Chart(pts) { p in
                    BarMark(x: .value("Workout", p.index), y: .value("Effort", p.effort), width: .ratio(0.6))
                        .foregroundStyle(.white.opacity(0.35))
                        .cornerRadius(4)
                    // Faces on the same 1–10 scale: drained 2 … amazing 10.
                    PointMark(x: .value("Workout", p.index), y: .value("Mood", p.feel.rawValue * 2))
                        .symbol { Text(p.feel.emoji).font(.system(size: 16)) }
                }
                .chartYScale(domain: 0...11)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 96)
                .accessibilityLabel("Mood against effort for the last \(pts.count) workouts")
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: TrainWidgetMetrics.corner, style: .continuous).fill(widget.gradient))
        }
    }
}
