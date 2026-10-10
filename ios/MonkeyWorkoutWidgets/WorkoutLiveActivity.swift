import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct MonkeyWorkoutWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

private let lime = Color(red: 0.80, green: 1.0, blue: 0.24)
private let ink = Color(red: 0.04, green: 0.05, blue: 0.06)

private func color(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// Lock screen banner + Dynamic Island: current set or rest countdown, and what's next.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { ctx in
            LockScreenView(state: ctx.state)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(lime)
        } dynamicIsland: { ctx in
            let s = ctx.state
            let tint = color(s.tint)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.restEnd != nil ? "REST" : s.setLabel.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(tint)
                        Text(s.exercise).font(.system(size: 15, weight: .black, design: .rounded)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = s.restEnd, end > .now {
                        Text(timerInterval: Date.now...end, countsDown: true)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(lime)
                            .frame(maxWidth: 80, alignment: .trailing)
                    } else if !s.detail.isEmpty {
                        Text(s.detail).font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next: \(s.next)").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                        if s.restEnd != nil { RestButtons() }
                    }
                }
            } compactLeading: {
                Image(systemName: s.restEnd != nil ? "timer" : "dumbbell.fill").foregroundStyle(tint)
            } compactTrailing: {
                if let end = s.restEnd, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(lime)
                        .frame(maxWidth: 44)
                } else {
                    Text(s.setLabel.replacingOccurrences(of: "Set ", with: "")).foregroundStyle(tint)
                }
            } minimal: {
                Image(systemName: s.restEnd != nil ? "timer" : "dumbbell.fill").foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

private struct LockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let tint = color(state.tint)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.restEnd != nil ? "RESTING · \(state.setLabel.uppercased())" : state.setLabel.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(state.restEnd != nil ? lime : tint)
                    Text(state.exercise).font(.system(size: 17, weight: .black, design: .rounded)).lineLimit(1)
                }
                Spacer()
                if let end = state.restEnd, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                } else if !state.detail.isEmpty {
                    Text(state.detail).font(.system(size: 20, weight: .black, design: .rounded))
                }
            }
            if let start = state.restStart, let end = state.restEnd, end > start {
                ProgressView(timerInterval: start...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(lime)
            }
            Text("Next: \(state.next)").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
            if state.restEnd != nil { RestButtons() }
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}

private struct RestButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: AddRestIntent()) {
                Text("+15 s").frame(maxWidth: .infinity)
            }
            .tint(.white.opacity(0.2))
            Button(intent: SkipRestIntent()) {
                Text("Skip rest").frame(maxWidth: .infinity).foregroundStyle(ink)
            }
            .tint(lime)
        }
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }
}
