import SwiftUI

/// Settings → Apple Watch → Lift sensor (#410, design A + C from `watch-gpath/control-proposals.png`):
/// on / off, how strict counting is, how a racked set is logged, the stop buzz, and Try it (practice mode).
struct LiftSensorCard: View {
    @State private var practicing = false

    private var pref: WatchLiftPref { .shared }

    var body: some View {
        let on = pref.mode.on
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 18, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lift sensor (beta)").font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.8)
                    Text("Counts reps and bar speed from your wrist").font(.caption.weight(.medium)).opacity(0.85)
                }
                Spacer(minLength: 0)
                Toggle("Lift sensor", isOn: Binding(get: { on }, set: { pref.setOn($0) }))
                    .labelsHidden()
                    .tint(Theme.lime)
                    .accessibilityIdentifier("lift.on")
            }
            if on {
                row("Counting", options: WatchLiftCounting.allCases, selected: pref.counting, title: \.title) { pref.set($0) }
                info(pref.counting.hint)
                row("Logging the set", options: WatchLiftLogging.allCases, selected: pref.logging, title: \.title) { pref.set($0) }
                info(pref.logging.hint)
                row("Stop buzz", options: [WatchLiftMode.noCue, .loss10, .loss20, .loss30], selected: pref.mode, title: \.buzzTitle) { pref.set($0) }
                info(pref.mode.buzzHint)
                Label("Fix a count with the Digital Crown: that exercise learns to count stricter or looser.", systemImage: "digitalcrown.arrow.clockwise.fill")
                    .font(.caption.weight(.semibold)).opacity(0.9)
                Button { practicing = true } label: {
                    Label("Try it with your Watch", systemImage: "waveform.path")
                        .font(Theme.label(14)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lift.tryIt")
            } else {
                info("The Watch doesn't count reps. Log your sets as usual.")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x7B2FF7), Color(hex: 0x00C6FF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .animation(.snappy, value: on)
        .sheet(isPresented: $practicing) { LiftPracticeView() }
    }

    private func row<T: Hashable>(_ label: String, options: [T], selected: T, title: KeyPath<T, String>,
                                  pick: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Theme.label(13))
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { o in
                    let picked = o == selected
                    Button { withAnimation(.snappy) { pick(o) } } label: {
                        Text(o[keyPath: title]).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(picked ? Theme.ink : .white)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(picked ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(.white.opacity(0.18))))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label): \(o[keyPath: title])")
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
    }

    private func info(_ text: String) -> some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.footnote.weight(.semibold))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.18)))
    }
}

extension WatchLiftCounting {
    var hint: String {
        switch self {
        case .relaxed: "Counts short pushes too (from about 7 cm). For small movements like raises."
        case .normal: "A rep is a push of 8 cm or more. Moves much shorter than your other reps don't count."
        case .strict: "A rep needs 10 cm and a full push like your other reps. Unracking and fidgeting don't count."
        }
    }
}

extension WatchLiftLogging {
    var hint: String {
        switch self {
        case .auto: "Rack the bar and stay still: the set logs itself after a 6 s countdown. Undo keeps the set going."
        case .confirm: "Rack the bar: the Watch buzzes and asks \"8 reps?\". Nothing logs until you tap ✓. Turn the Crown first to fix the count."
        case .manual: "The Watch only counts and fills in your reps. You log the set as usual."
        }
    }
}

extension WatchLiftMode {
    var buzzTitle: String {
        switch self {
        case .off, .noCue: "Off"
        case .loss10: "−10 %"
        case .loss20: "−20 %"
        case .loss30: "−30 %"
        }
    }

    var buzzHint: String {
        switch self {
        case .off, .noCue: "No stop buzz: the Watch counts reps and bar speed only."
        case .loss10: "Buzzes when the bar slows 10 %. Fast, fresh reps for power."
        case .loss20: "Buzzes when the bar slows 20 %. The strength sweet spot."
        case .loss30: "Buzzes when the bar slows 30 %. Closer to failure for muscle."
        }
    }
}

/// Try it (#410, design C): do a few reps with the Watch on; every push shows on the graph and the counting
/// level can be changed to recount the same reps, then saved as the setting.
struct LiftPracticeView: View {
    /// CI screenshots: a practice without a Watch.
    var demo: WLiftPracticeState? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var counting = WatchLiftPref.shared.counting
    @State private var state: WLiftPracticeState?
    @State private var reachable = WatchSync.shared.watchReachable

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Wear the Watch, open MonkeyWorkout on it and do a few reps with a light weight. Every push shows here.")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    if state == nil && !reachable {
                        Label("Open MonkeyWorkout on your Watch to start.", systemImage: "applewatch")
                            .font(Theme.label(14))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                    }
                    graphCard
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Counting").font(Theme.label(13))
                        Picker("Counting", selection: $counting) {
                            ForEach(WatchLiftCounting.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(counting.hint).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        WatchLiftPref.shared.set(counting)
                        dismiss()
                    } label: {
                        Text("Use \(counting.title)").font(Theme.label(16)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("liftPractice.save")
                }
                .padding(16)
                .readableWidth()
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Try the lift sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .onChange(of: counting) { _, c in WatchSync.shared.practice(c.level) }
        .onReceive(NotificationCenter.default.publisher(for: .watchPractice)) { n in
            if let s = n.object as? WLiftPracticeState { state = s }
        }
        .task {
            if let demo {
                state = demo
                return
            }
            // Start, and start again while the Watch app isn't open yet.
            while !Task.isCancelled {
                reachable = WatchSync.shared.watchReachable
                if state == nil { WatchSync.shared.practice(counting.level) }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        .onDisappear { if demo == nil { WatchSync.shared.practice(nil) } }
    }

    private var graphCard: some View {
        let reps = state?.reps ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(reps)").font(Theme.display(44)).monospacedDigit().contentTransition(.numericText())
                Text(reps == 1 ? "rep" : "reps").font(Theme.label(15))
                Spacer()
                Text("LIVE").font(Theme.label(11)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.25)))
            }
            PracticeTrace(trace: state?.trace ?? [], marks: state?.marks ?? [])
                .frame(height: 110)
            if let s = state, !s.ranges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(zip(s.ranges, s.velocities).enumerated()), id: \.offset) { i, rv in
                            Text("#\(i + 1) \(Int((rv.0 * 100).rounded())) cm · \(String(format: "%.2f", rv.1)) m/s")
                                .font(Theme.label(11)).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.22)))
                        }
                    }
                }
            } else {
                Text("Waiting for your first rep…").font(.footnote.weight(.semibold)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFF3D6E), Color(hex: 0xFF8A00)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .animation(.snappy, value: reps)
    }
}

/// The movement the Watch sees (acceleration along the lift, last 6 s) with a dot where each counted rep ends.
struct PracticeTrace: View {
    let trace: [Double]
    let marks: [Int]

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: mid))
            zero.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(zero, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            guard trace.count > 1 else { return }
            let peak = max(0.15, trace.map { abs($0) }.max() ?? 0.15)
            let step = size.width / CGFloat(max(1, 119))
            let offset = CGFloat(120 - trace.count) * step
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: offset + CGFloat(i) * step, y: mid - CGFloat(trace[i] / peak) * (mid - 6))
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<trace.count { line.addLine(to: point(i)) }
            ctx.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for m in marks where trace.indices.contains(m) {
                let p = point(m)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(Theme.lime))
            }
        }
        .accessibilityLabel("Movement graph, \(marks.count) reps marked")
    }
}
