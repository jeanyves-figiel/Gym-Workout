import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct MonkeyWorkoutWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        HomeScreenWidget()
    }
}

private let lime = Color(red: 0.80, green: 1.0, blue: 0.24)
private let ink = Color(red: 0.04, green: 0.05, blue: 0.06)

private func color(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// Lock screen banner + Dynamic Island: log the coming set without unlocking, rest countdown, session progress (#371),
/// and a summary card once the workout is finished.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { ctx in
            LockScreenView(state: ctx.state, attributes: ctx.attributes)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(lime)
        } dynamicIsland: { ctx in
            let s = ctx.state
            let tint = color(s.tint)
            let resting = s.restEnd.map { $0 > .now } ?? false
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resting ? "REST" : s.setLabel.uppercased())
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(resting ? lime : tint)
                        Text(s.exercise).font(.system(size: 15, weight: .black, design: .rounded)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = s.countdownEnd {
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
                    VStack(alignment: .leading, spacing: 7) {
                        if resting {
                            RestButtons()
                        } else if s.loggable == true {
                            EffortTiles(height: 36)
                        } else if let action = s.action {
                            ActionButton(title: action)
                        } else {
                            Text("Next: \(s.next)").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                        }
                        SessionStrip(state: s, startedAt: ctx.attributes.startedAt)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: resting ? "timer" : "dumbbell.fill")
                    if !resting, let short = s.shortSet { Text(short).monospacedDigit() }
                }
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(resting ? lime : tint)
            } compactTrailing: {
                if let end = s.countdownEnd {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(lime)
                        .frame(maxWidth: 44)
                } else if let hr = s.heartRate {
                    Text("♥\(hr)").foregroundStyle(heart)
                } else if let p = s.position, let n = s.count {
                    Text("\(p)/\(n)").monospacedDigit().foregroundStyle(tint)
                }
            } minimal: {
                Image(systemName: resting ? "timer" : "dumbbell.fill").foregroundStyle(resting ? lime : tint)
            }
            .keylineTint(tint)
        }
    }
}

private let heart = Color(red: 1.0, green: 0.35, blue: 0.46)

extension WorkoutActivityAttributes.ContentState {
    /// Rest, timed work or "Next in": whichever countdown runs.
    var countdownEnd: Date? {
        [restEnd, workEnd, autoNextEnd].compactMap { $0 }.first { $0 > .now }
    }

    /// "2/4" from "Set 2 of 4".
    var shortSet: String? {
        let parts = setLabel.split(separator: " ")
        guard parts.count == 4, parts[0] == "Set" else { return nil }
        return "\(parts[1])/\(parts[3])"
    }
}

private struct LockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState
    let attributes: WorkoutActivityAttributes

    var body: some View {
        if let summary = state.summary {
            FinishedCard(summary: summary, title: attributes.sessionTitle)
        } else {
            live
        }
    }

    private var live: some View {
        let tint = color(state.tint)
        let resting = state.restEnd.map { $0 > .now } ?? false
        let logging = !resting && state.loggable == true
        // Lock screen cards are capped at 160 pt: strip, header, one row of buttons, next.
        return VStack(alignment: .leading, spacing: 6) {
            SessionStrip(state: state, startedAt: attributes.startedAt)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resting ? "RESTING · \(state.setLabel.uppercased())" : state.setLabel.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(resting ? lime : tint)
                    Text(state.exercise).font(.system(size: 17, weight: .black, design: .rounded)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let end = state.countdownEnd {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100, alignment: .trailing)
                } else if logging, !state.detail.isEmpty {
                    HStack(spacing: 6) {
                        KgButton(sign: -1)
                        Text(state.detail).font(.system(size: 18, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                        KgButton(sign: 1)
                    }
                } else if !state.detail.isEmpty {
                    Text(state.detail).font(.system(size: 20, weight: .black, design: .rounded))
                }
            }
            if resting {
                RestButtons()
            } else if logging {
                EffortTiles(height: 36)
            } else if let action = state.action {
                ActionButton(title: action)
            }
            Text("Next: \(state.next)").font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(12)
    }
}

/// Session at a glance (#371): one bar per exercise, where we are, time, heart rate, kg lifted, done-by time.
private struct SessionStrip: View {
    let state: WorkoutActivityAttributes.ContentState
    let startedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let segs = state.segments, !segs.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { _, s in
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.18))
                                Capsule().fill(color(s.tint)).frame(width: g.size.width * min(1, max(0, s.done)))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
            HStack(spacing: 8) {
                if let p = state.position, let n = state.count { Text("\(p)/\(n)").monospacedDigit() }
                Text(startedAt, style: .timer).monospacedDigit().frame(maxWidth: 56, alignment: .leading)
                if let hr = state.heartRate { Text("♥ \(hr)").foregroundStyle(heart) }
                Spacer(minLength: 0)
                if let kg = state.volumeKg, kg > 0 { Text(volumeText(kg)) }
                if let by = state.doneBy { Text("done ~\(by.formatted(date: .omitted, time: .shortened))") }
            }
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
        }
    }
}

private func volumeText(_ kg: Double) -> String {
    kg >= 10_000 ? String(format: "%.1f t", kg / 1000) : "\(Int(kg.rounded())) kg"
}

/// Same five tiles as the player's SET DONE strip (#357): one tap logs the set with its reps left.
private struct EffortTiles: View {
    let height: CGFloat
    private struct Tile {
        let rir: Int, title: String, caption: String, color: UInt32
    }

    private static let tiles = [
        Tile(rir: 0, title: "0", caption: "FAIL", color: 0xFF3D5A), Tile(rir: 1, title: "1", caption: "1 LEFT", color: 0xFF7A3D),
        Tile(rir: 2, title: "2", caption: "2 LEFT", color: 0xFFC23D), Tile(rir: 3, title: "3", caption: "3 LEFT", color: 0xCCFF3D),
        Tile(rir: 4, title: "4+", caption: "EASY", color: 0x3DFFB0),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.tiles, id: \.rir) { t in
                Button(intent: LogSetIntent(rir: t.rir)) {
                    VStack(spacing: 0) {
                        Text(t.title).font(.system(size: 16, weight: .black, design: .rounded))
                        Text(t.caption).font(.system(size: 7, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color(t.color)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.rir == 0 ? "Set done, failure" : t.rir == 4 ? "Set done, easy" : "Set done, \(t.rir) reps left")
            }
        }
    }
}

private struct KgButton: View {
    let sign: Int

    var body: some View {
        Button(intent: StepKgIntent(sign: sign)) {
            Image(systemName: sign < 0 ? "minus" : "plus")
                .font(.system(size: 12, weight: .black))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sign < 0 ? "Less weight" : "More weight")
    }
}

private struct ActionButton: View {
    let title: String

    var body: some View {
        Button(intent: MainActionIntent()) {
            Text(title).frame(maxWidth: .infinity).foregroundStyle(ink)
        }
        .tint(lime)
        .font(.system(size: 14, weight: .heavy, design: .rounded))
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }
}

/// Left on the lock screen for a while after the finish (#371).
private struct FinishedCard: View {
    let summary: WorkoutActivityAttributes.Summary
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKOUT DONE · \(summary.minutes) MIN").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.9)
            Text("\(title) 🎉").font(.system(size: 20, weight: .black, design: .rounded)).lineLimit(1)
            HStack(spacing: 6) {
                stat("\(summary.exercises)/\(summary.of)", "EXERCISES", fill: .black.opacity(0.25))
                stat(summary.volumeKg > 0 ? volumeText(summary.volumeKg) : "\(summary.sets)", summary.volumeKg > 0 ? "LIFTED" : "SETS",
                     fill: .black.opacity(0.25))
                stat("\(summary.prs)", summary.prs == 1 ? "NEW PR" : "NEW PRs", fill: summary.prs > 0 ? lime : .black.opacity(0.25),
                     dark: summary.prs > 0)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(LinearGradient(colors: [color(0xFF2D55), color(0xFF6FB5), color(0xA64DFF)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func stat(_ value: String, _ label: String, fill: Color, dark: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 19, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(dark ? ink : .white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
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
