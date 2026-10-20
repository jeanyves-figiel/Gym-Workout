import SwiftUI
import WorkoutEngine

/// Finish early (#300, designs A + C from `finish-early/proposals.png`): Coach Monkey's three ready plans, or the
/// member's own minutes / end time, with every change listed (kept, shorter, skipped) before the workout is re-fitted.
struct FinishEarlySheet: View {
    /// The full workout (never an earlier fit), so a member can also give time back.
    let blocks: [Block]
    let setsDone: [String: Int]
    let current: String
    /// A fit is already on: offer the way back to the full workout.
    let fitted: Bool
    let onFit: (Int) -> Void
    let onUndo: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int?
    @State private var doneBy = Date()

    private static let ownMinutes = [10, 15, 20, 30, 45]

    private var fullSec: Int {
        FinishEarly.remainingSec(blocks, setsDone: FinishEarly.behind(blocks, setsDone: setsDone, current: current))
    }

    private func plan(_ p: FinishEarly.Plan) -> Int? { FinishEarly.minutes(for: p, blocks, setsDone: setsDone, current: current) }

    var body: some View {
        let plans = FinishEarly.Plan.allCases.compactMap { p in plan(p).map { (p, $0) } }
        let picked = minutes ?? plans.first?.1
        let fit = picked.map { FinishEarly.fit(blocks, setsDone: setsDone, current: current, minutes: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if plans.isEmpty {
                    Text("Almost done: nothing left to squeeze.").font(Theme.label(15)).foregroundStyle(Theme.muted)
                }
                ForEach(Array(plans.enumerated()), id: \.offset) { _, e in planCard(e.0, minutes: e.1, on: picked == e.1) }
                own(picked: picked)
                if let fit { changes(fit) }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let fit, let picked {
                    Button {
                        onFit(picked)
                        dismiss()
                    } label: {
                        Text(fitLabel(fit, minutes: picked)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .buttonStyle(LimeButtonStyle())
                }
                if fitted {
                    Button("Back to the full workout") {
                        onUndo()
                        dismiss()
                    }
                    .font(Theme.label(15))
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.bg.opacity(0.95))
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onAppear { doneBy = Date().addingTimeInterval(TimeInterval((picked ?? 15) * 60)) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            MonkeyFace(mood: .fired, scale: 1.1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Finish early").eyebrow()
                Text("Short on time? Pick one, I'll squeeze the rest. Cool-down stays.")
                    .font(Theme.display(19)).fixedSize(horizontal: false, vertical: true)
                Text("\(Self.mins(fullSec)) min left as planned").font(Theme.label(12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
            }
            .accessibilityLabel("Close")
        }
    }

    private func planCard(_ p: FinishEarly.Plan, minutes m: Int, on: Bool) -> some View {
        let (symbol, title, detail, colors): (String, String, String, [Color]) = switch p {
        case .express: ("bolt.fill", "Express", "Main lift + short cool-down", WorkoutEngine.Category.power.colors)
        case .balanced: ("scalemass.fill", "Balanced", "Main + accessories, fewer sets", WorkoutEngine.Category.strength.colors)
        case .wrapUp: ("figure.cooldown", "Wrap up now", "Finish this one, then cool-down", WorkoutEngine.Category.cardio.colors)
        }
        return Button { minutes = m } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20, weight: .heavy))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.display(20))
                    Text("\(detail) · done \(Self.clock(m))").font(Theme.label(12)).opacity(0.9)
                }
                Spacer(minLength: 0)
                Text(m == 0 ? "Now" : "\(m)′").font(Theme.display(28)).monospacedDigit()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.lime, lineWidth: on ? 3 : 0).padding(-2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// "I need to stop in…" chips, or the time to be done by.
    private func own(picked: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or I need to stop in…").eyebrow()
            HStack(spacing: 6) {
                ForEach(Self.ownMinutes.filter { $0 * 60 < fullSec }, id: \.self) { m in
                    Button("\(m)′") {
                        minutes = m
                        doneBy = Date().addingTimeInterval(TimeInterval(m * 60))
                    }
                    .font(Theme.label(14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(picked == m ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
                    .foregroundStyle(picked == m ? Theme.ink : .white)
                }
            }
            DatePicker("Done by", selection: $doneBy, in: Date()..., displayedComponents: .hourAndMinute)
                .font(Theme.label(14))
                .onChange(of: doneBy) { _, d in
                    minutes = max(0, Int((d.timeIntervalSinceNow / 60).rounded()))
                }
        }
        .card()
    }

    private func changes(_ fit: FinishEarly.Fit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What changes").eyebrow()
                Spacer()
                Text("\(Self.mins(fit.beforeSec))′ → \(Self.mins(fit.leftSec))′").font(Theme.label(13)).monospacedDigit()
            }
            ForEach(fit.lines) { line in row(line) }
            if !fit.fits {
                Text("Still a little over: what's left is the minimum (this exercise and the cool-down).")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }

    private func row(_ l: FinishEarly.Line) -> some View {
        let skipped = l.change == .skipped
        let (tag, detail, color): (String, String, Color) = switch l.change {
        case .kept: ("KEPT", "", Theme.lime)
        case let .fewerSets(a, b): ("SHORTER", "\(a) → \(b) sets", .orange)
        case let .shorter(a, b): ("SHORTER", "\(Self.mins(a)) → \(Self.mins(b)) min", .orange)
        case let .restTighter(a, b): ("LESS REST", "rest \(Format.rest(a)) → \(Format.rest(b))", .yellow)
        case .skipped: ("SKIP", "", .red)
        }
        return HStack(spacing: 10) {
            Image(systemName: l.kind.symbol).font(.system(size: 12, weight: .heavy))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(l.kind.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(Exercise.get(l.exerciseId).name).font(Theme.label(14)).strikethrough(skipped).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(Theme.label(11)).foregroundStyle(Theme.muted) }
            }
            .opacity(skipped ? 0.5 : 1)
            Spacer(minLength: 0)
            Text(tag).font(Theme.label(10))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(color))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func fitLabel(_ fit: FinishEarly.Fit, minutes m: Int) -> String {
        let left = max(1, Self.mins(fit.leftSec))
        return m == 0 ? "WRAP UP · \(left) MIN" : "FIT TO \(m) MIN · DONE \(Self.clock(m))"
    }

    static func mins(_ sec: Int) -> Int { (sec + 59) / 60 }

    static func clock(_ minutes: Int) -> String {
        Date().addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}

/// Over the player after a fit: what changed, with Undo, for a few seconds.
struct FinishEarlyBanner: View {
    let text: String
    var symbol = "timer"
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .heavy))
            Text(text).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .font(Theme.label(13))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.lime))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(LinearGradient(colors: UndoOffer.warm, startPoint: .leading, endPoint: .trailing)))
        .foregroundStyle(.white)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
