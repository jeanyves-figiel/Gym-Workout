import SwiftUI
import WatchKit

// Mind on the Watch (#834, designs A + B + C from `mental-health/watch/proposals.png`): A the Calm list and the
// breathing player with wrist taps and heart rate; B the mood check-in and the Mind card; C the done screen with the
// heart-rate drop (the Smart Stack cards live in the complications extension).

/// Mood 1–5 as on the iPhone (`Feel`).
enum WMood {
    static let all: [(level: Int, emoji: String, label: String)] = [
        (1, "😫", "Drained"), (2, "😐", "Meh"), (3, "🙂", "Good"), (4, "😄", "Great"), (5, "🤩", "Amazing"),
    ]
}

/// Home row → Mind: check-in when not done today, else the score card and Coach's pick; then every Calm session.
struct WatchMindView: View {
    @Environment(WatchStore.self) private var store
    @State private var skipped = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let m = store.snapshot.mind {
                    if !m.checkedInToday(), !skipped {
                        WatchCheckIn(onLater: { withAnimation { skipped = true } })
                    } else {
                        MindCard(mind: m)
                        if let b = m.pickBreath {
                            Button { Task { await CalmTracker.shared.begin(b, minutes: b.lengths.first ?? 3) } } label: {
                                Text("▶ \(b.label) · \(b.lengthShort(b.lengths.first ?? 3))").font(W.label(14)).foregroundStyle(W.ink)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.lime))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start \(b.label), Coach pick, \(m.pickWhy)")
                        }
                    }
                    Eyebrow(text: "Calm · \(m.weekMinutes) min this week", color: W.lime).padding(.top, 4)
                    ForEach(m.breaths) { b in CalmRow(breath: b) }
                } else {
                    ScreenTitle(text: "Mind")
                    Text("Open MonkeyWorkout on iPhone once to bring Mind and Calm here.").font(W.label(11)).opacity(0.8)
                }
            }
            .watchMargins()
        }
    }
}

/// B: six squares, five moods and Later.
struct WatchCheckIn: View {
    @Environment(WatchStore.self) private var store
    var onLater: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScreenTitle(text: "How do you feel?")
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(WMood.all, id: \.level) { m in
                    Button {
                        WKInterfaceDevice.current().play(.success)
                        withAnimation { store.checkIn(mood: m.level) }
                    } label: {
                        VStack(spacing: 1) {
                            Text(m.emoji).font(.system(size: 20))
                            Text(m.label.uppercased()).font(W.label(7)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(W.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m.label)
                }
                Button(action: onLater) {
                    Text("Later").font(W.label(12)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(W.card))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Mind score, level and the last 7 days.
struct MindCard: View {
    let mind: WMind

    var body: some View {
        let score = mind.today() ? mind.score : nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mind").font(W.label(12))
                    Text((score == nil ? "No data" : mind.level ?? "").uppercased()).font(W.label(8)).tracking(0.6).opacity(0.85)
                }
                Spacer(minLength: 2)
                Text(score.map { "\($0)" } ?? "–").font(W.display(34)).monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(mind.week.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(v == nil ? 0.2 : (v ?? 0) < 55 ? 0.45 : 0.9))
                        .frame(height: max(3, 24 * CGFloat(v ?? 6) / 100))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 24, alignment: .bottom)
        }
        .foregroundStyle(.white)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(W.gradient(0x3B3F8F, 0x7A2CFF)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mind score \(score.map { "\($0)" } ?? "not known")")
    }
}

/// A: one session on its gradient, default length on the right.
struct CalmRow: View {
    let breath: WBreath

    var body: some View {
        let m = breath.lengths.first ?? 3
        Button { Task { await CalmTracker.shared.begin(breath, minutes: m) } } label: {
            HStack(spacing: 7) {
                Image(systemName: breath.symbol).font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(breath.label).font(W.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(breath.purpose).font(W.label(8)).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 2)
                Text(breath.lengthShort(m)).font(W.display(19))
            }
            .foregroundStyle(.white)
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(breath.tint, breath.tint2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(breath.label), \(breath.purpose), \(m) \(breath.byBreaths == true ? "breaths" : "minutes")")
    }
}

/// A: the square fills on the breath in and empties on the breath out; phase, seconds, heart rate and time left.
/// Tap (or double tap) pauses; scroll down for End.
struct CalmRunView: View {
    @State private var tracker = CalmTracker.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TabView {
            TimelineView(.animation(minimumInterval: dimmed ? 1 : 1 / 20, paused: tracker.paused)) { ctx in breathing(ctx.date) }
            controls
        }
        .tabViewStyle(.verticalPage)
    }

    @ViewBuilder private func breathing(_ now: Date) -> some View {
        if let b = tracker.breath, !b.phases.isEmpty {
            let t = tracker.elapsed(now)
            let at = b.at(t, minutes: tracker.minutes)
            let n = b.phases.count
            let phase = b.phases[at.index]
            let from = at.cycle == 0 && at.index == 0 ? 0 : b.phases[(at.index - 1 + n) % n].fill
            let p = phase.seconds > 0 ? at.into / phase.seconds : 1
            let fill = from + (phase.fill - from) * p * p * (3 - 2 * p)
            let left = max(0, Int((b.totalSeconds(minutes: tracker.minutes) - t).rounded(.up)))
            VStack(spacing: 4) {
                GeometryReader { g in
                    let side = min(g.size.width, g.size.height)
                    ZStack {
                        RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                            .stroke(.white.opacity(0.35), lineWidth: 2)
                            .frame(width: side * 0.92, height: side * 0.92)
                        RoundedRectangle(cornerRadius: side * 0.13, style: .continuous)
                            .fill(.white)
                            .frame(width: side * (0.3 + 0.62 * fill), height: side * (0.3 + 0.62 * fill))
                        VStack(spacing: 0) {
                            Text(tracker.paused ? "Paused" : phase.label).font(W.label(12)).lineLimit(1).minimumScaleFactor(0.6)
                            Text("\(max(1, Int((phase.seconds - at.into).rounded(.up))))").font(W.display(24)).monospacedDigit()
                        }
                        .foregroundStyle(W.color(b.tint2))
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
                HStack {
                    Text(tracker.heartRate.map { "♥ \(Int($0.rounded()))" } ?? "♥ –").font(W.label(11))
                    Spacer()
                    Text("\(left / 60):\(String(format: "%02d", left % 60)) left").font(W.label(11)).monospacedDigit()
                }
                .foregroundStyle(.white)
            }
            .watchMargins()
            .contentShape(Rectangle())
            .onTapGesture { tracker.togglePause() }
            .handGestureShortcut(.primaryAction)
            .background(W.gradient(b.tint, b.tint2).opacity(dimmed ? 0.3 : 1).ignoresSafeArea())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(phase.label), \(left) seconds left")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Pauses")
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            Text(tracker.breath?.label ?? "").font(W.display(16)).lineLimit(1).minimumScaleFactor(0.7)
            Button { tracker.togglePause() } label: {
                Text(tracker.paused ? "▶ Resume" : "Pause").font(W.label(14)).foregroundStyle(W.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.lime))
            }
            .buttonStyle(.plain)
            Button { tracker.finish() } label: {
                Text("End").font(W.label(14)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.card))
            }
            .buttonStyle(.plain)
        }
        .watchMargins()
    }
}

/// C: done, minutes, heart rate start → end and the calm bonus on the Mind score.
struct CalmSummaryView: View {
    let summary: CalmTracker.Summary

    var body: some View {
        let minutes = summary.seconds / 60
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ScreenTitle(text: "Done · \(minutes) min")
                HStack(spacing: 4) {
                    tile(summary.hrStart.flatMap { a in summary.hrEnd.map { "\(a)→\($0)" } } ?? "–", "HEART RATE")
                    // Same rule as the iPhone's Mind score: +1 a calm minute today, max +5.
                    tile("+\(min(5, minutes))", "MIND")
                }
                Text("Saved as mindful minutes on your iPhone.").font(W.label(9)).opacity(0.75)
                Button { CalmTracker.shared.closeSummary() } label: {
                    Text("Done").font(W.label(14)).foregroundStyle(W.color(summary.breath.tint2))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
                }
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction)
            }
            .watchMargins()
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(W.display(16)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(W.label(7)).opacity(0.75)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(W.card))
    }
}
