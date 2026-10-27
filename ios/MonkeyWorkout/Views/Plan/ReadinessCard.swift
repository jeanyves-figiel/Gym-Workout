import SwiftUI
import WorkoutEngine

extension Readiness {
    /// Key markers on one line, e.g. "HRV 49 ms · RHR 50 · Sleep 5.9 h".
    func markers(_ s: HealthSnapshot) -> String {
        [
            s.hrv.map { "HRV \(Int($0)) ms" },
            s.restingHR.map { "RHR \(Int($0))" },
            s.sleepHours.map { String(format: "Sleep %.1f h", $0) },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var colors: [Color] {
        switch self {
        case .ready: [Theme.lime, Color(red: 0.2, green: 0.85, blue: 0.5)]
        case .normal: [.yellow, .orange]
        case .easy: [.orange, Color(red: 0.95, green: 0.25, blue: 0.3)]
        }
    }

    var symbol: String {
        switch self {
        case .ready: "bolt.fill"
        case .normal: "checkmark"
        case .easy: "tortoise.fill"
        }
    }

    var rule: String {
        switch self {
        case .ready: "No marker off"
        case .normal: "1 marker off"
        case .easy: "2 or more markers off"
        }
    }
}

/// Explains the verdict, where the numbers come from and every term.
struct ReadinessSheet: View {
    let snapshot: HealthSnapshot
    let readiness: Readiness
    let flags: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    Text("Where the numbers come from").eyebrow()
                    Text("Your Apple Watch records these into Apple Health. MonkeyWorkout reads them on this phone (they never leave it) and compares your latest reading with your own 30-day average. No made-up numbers: a marker only shows when Health has it.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.muted)
                    Text("How the verdict works").eyebrow()
                    ForEach([Readiness.ready, .normal, .easy], id: \.self) { verdictRow($0) }
                    Text("The markers").eyebrow()
                    marker(
                        "HRV", "Heart rate variability", "waveform.path.ecg",
                        value: snapshot.hrv.map { "\(Int($0)) ms" }, avg: snapshot.hrvBaseline.map { "\(Int($0)) ms" },
                        what: "Tiny changes in time between heartbeats, in milliseconds. Higher than your normal = well recovered. Lower = stress, poor sleep, illness or hard training is still in your body.",
                        rule: "Counts as off when more than \(Int((1 - Readiness.hrvFloor) * 100)) % below your 30-day average.",
                        off: flags.contains("HRV below your baseline"), gradient: WorkoutEngine.Category.mobility.gradient)
                    marker(
                        "Rest HR", "Resting heart rate", "heart.fill",
                        value: snapshot.restingHR.map { "\(Int($0)) bpm" }, avg: snapshot.restingHRBaseline.map { "\(Int($0)) bpm" },
                        what: "Heartbeats per minute when you're calm. A few beats above your normal often means you're tired, dehydrated or getting sick.",
                        rule: "Counts as off when more than \(Int(Readiness.restHRRise)) bpm above your 30-day average.",
                        off: flags.contains("Resting HR elevated"), gradient: WorkoutEngine.Category.power.gradient)
                    marker(
                        "Sleep", "Last night's sleep", "bed.double.fill",
                        value: snapshot.sleepHours.map { String(format: "%.1f h", $0) }, avg: nil,
                        what: "Time asleep since 6 pm yesterday, from your watch or sleep app.",
                        rule: "Counts as off under \(Int(Readiness.minSleep)) h. Hidden when Health has no sleep data.",
                        off: flags.contains("Short sleep"), gradient: WorkoutEngine.Category.strength.gradient)
                    marker(
                        "VO₂max", "Cardio fitness", "lungs.fill",
                        value: snapshot.vo2Max.map { String(format: "%.0f", $0) }, avg: nil,
                        what: "How much oxygen your body can use at full effort (ml per kg per minute). A long-term fitness score that moves over weeks, so it is shown for context only.",
                        rule: "Not used for today's verdict.",
                        off: false, gradient: WorkoutEngine.Category.cardio.gradient)
                    Text("Effort words").eyebrow()
                    RPEExplainer()
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Readiness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: readiness.symbol)
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.85)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Today").font(Theme.label(12)).tracking(1.4).foregroundStyle(Theme.ink.opacity(0.7)).textCase(.uppercase)
                Text(readiness.title).font(Theme.display(28)).foregroundStyle(Theme.ink)
                Text(flags.isEmpty ? "All markers in your normal range." : flags.joined(separator: " · "))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(LinearGradient(colors: readiness.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func verdictRow(_ r: Readiness) -> some View {
        let current = r == readiness
        return HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: r.symbol, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(r.title).font(Theme.display(18))
                    if current {
                        Text("TODAY").font(Theme.label(9)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.ink.opacity(0.15)))
                    }
                    Spacer()
                    Text(r.rule).font(Theme.label(11)).opacity(0.75)
                }
                Text(r.advice).font(.footnote.weight(.semibold)).opacity(0.8)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: r.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white, lineWidth: current ? 3 : 0))
    }

    private func marker(_ short: String, _ name: String, _ icon: String, value: String?, avg: String?,
                        what: String, rule: String, off: Bool, gradient: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(symbol: icon, size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(short).font(Theme.display(19))
                    Text(name).font(.caption.weight(.semibold)).opacity(0.85)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value ?? "—").font(Theme.display(24)).monospacedDigit()
                    if let avg { Text("AVG \(avg)".uppercased()).font(Theme.label(9)).tracking(1).opacity(0.8) }
                    else if value == nil { Text("NO DATA").font(Theme.label(9)).tracking(1).opacity(0.8) }
                }
            }
            Text(what).font(.footnote.weight(.medium)).opacity(0.9)
            Label(rule, systemImage: off ? "exclamationmark.triangle.fill" : "ruler")
                .font(.caption.weight(.bold))
                .padding(.horizontal, off ? 10 : 0)
                .padding(.vertical, off ? 6 : 0)
                .background { if off { Capsule().fill(.black.opacity(0.3)) } }
                .opacity(off ? 1 : 0.85)
        }
        .gradientCard(gradient, padding: 14)
    }
}

/// RPE / reps-in-reserve in plain words.
struct RPEExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RPE = Rate of Perceived Exertion").font(.system(.headline, design: .rounded).weight(.heavy))
            Text("How hard a set felt, from 1 to 10. Count the reps you could still have done with good form:")
                .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
            ForEach([(10, "0 left · absolute max"), (9, "1 rep left"), (8, "2 reps left"), (7, "3 reps left"), (6, "4 reps left"), (5, "easy · could chat")], id: \.0) { n, text in
                HStack(spacing: 10) {
                    Text("\(n)").font(Theme.display(18)).monospacedDigit().foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 28)
                        .background(Capsule().fill(Theme.heat(Double(n) / 10)))
                    Text(text).font(.subheadline.weight(.semibold))
                }
            }
            Text("\"Keep RPE honest\" = stop each set at the RPE written in the workout, not earlier, not to failure. \"Drop 1 RPE\" = stop one rep sooner than written.")
                .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
            Label {
                Text("Log it during the workout: after each set, type the reps you had left in the **RIR** box (reps in reserve) next to kg × reps. RIR 2 = RPE 8. Optional, but it tunes your next load suggestion.")
            } icon: {
                Image(systemName: "square.and.pencil")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.lime)
        }
        .card(padding: 14)
    }
}

/// Explains the 4-week cycle chip ("Base · RPE −1" etc.).
struct WeekPhaseSheet: View {
    let week: Int
    @Environment(\.dismiss) private var dismiss

    private let phases: [(String, String, String)] = [
        ("Base", "RPE −1", "Ease in: every set one rep further from failure than its target (e.g. RPE 7 instead of 8). Lets you learn the loads."),
        ("Build", "Target RPE", "Train at the RPE written in each exercise."),
        ("Peak", "+1 set", "Hardest week: one extra set on main lifts at target RPE."),
        ("Deload", "−40% volume", "Recovery week: fewer sets, RPE 2 lower, shorter sessions. You come back stronger."),
    ]

    /// Base, Build, Peak, Deload (#823).
    private static let fills: [(gradient: LinearGradient, ink: Color)] = [
        (WorkoutEngine.Category.cardio.gradient, Color.white), (WorkoutEngine.Category.mobility.gradient, Color.white),
        (LinearGradient.hiit, Color.white), (WorkoutEngine.Category.stretch.gradient, WorkoutEngine.Category.stretch.ink),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your plan runs in 4-week cycles. Each week has a job; the chip on Train shows this week's.")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                    // Gradient tiles, number left (#823): this week ringed in lime.
                    ForEach(Array(phases.enumerated()), id: \.offset) { i, p in
                        let current = i == Generator.phaseIndex(week)
                        let fill = Self.fills[i % Self.fills.count]
                        GradientTile(gradient: fill.gradient, number: "\(i + 1)", title: current ? "\(p.0) · this week" : p.0,
                                     detail: "\(p.1) · \(p.2)", ink: fill.ink, outlined: current)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(current ? .isSelected : [])
                    }
                    RPEExplainer()
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Training cycle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}
