import AudioToolbox
import LiftSensor
import SwiftUI
import UIKit

// WOD and combat timers (#622, design A + B + C from `apple-tech-radar/x5.png`): A timer builder with square kind
// tiles and saved WODs, B boxing rounds (bell, 10″ clap, punches counted on the Watch), C big screen mode for a
// propped-up iPhone, started by a double tap on the Watch. One engine (`WodTimer`) for all three.

/// Workout library entry.
struct TimersCard: View {
    var body: some View {
        NavigationLink { WodTimersView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.system(size: 22, weight: .heavy))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timers").font(Theme.display(20))
                    Text("Tabata, EMOM, AMRAP, boxing rounds").font(Theme.label(12)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Text("\(WodTimer.presets.count + WodStore.shared.timers.count)").font(Theme.display(26))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient.wod(.tabata)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.timers")
    }
}

extension LinearGradient {
    static func wod(_ kind: WodTimer.Kind) -> LinearGradient {
        LinearGradient(colors: [Color(hex: kind.tint.0), Color(hex: kind.tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Timers: build one from a kind tile (A), saved timers, boxing (B), and every timer runs on the big screen (C).
struct WodTimersView: View {
    @State private var store = WodStore.shared
    @State private var editing: WodTimer?
    @State private var running: WodTimer?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ContentTitle(title: "Timers")
                Text("Build").eyebrow()
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(WodTimer.Kind.allCases) { k in
                        Button { editing = .starting(k) } label: { KindTile(kind: k) }
                            .buttonStyle(.plain)
                    }
                    Button { editing = .boxing } label: {
                        KindTile(kind: .rounds, title: "BOXING", symbol: "figure.boxing")
                    }
                    .buttonStyle(.plain)
                }
                // B: boxing rounds with the Watch counting punches.
                Button { running = .boxing } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.boxing").font(.system(size: 24, weight: .heavy))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Boxing rounds").font(Theme.display(20))
                            Text("6 × 3′ / 1′ · bell, clap at 10″, punches on your Watch").font(Theme.label(12)).opacity(0.9)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gradientCard(.wod(.rounds), padding: 14)
                }
                .buttonStyle(.plain)
                if !store.timers.isEmpty {
                    Text("Saved").eyebrow().padding(.top, 6)
                    ForEach(store.timers) { t in
                        SavedTimerRow(timer: t) { running = t }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = t }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(t) }
                            }
                    }
                }
                Text("On Apple Watch: Timers on the home screen, with your saved timers. Double tap starts and pauses.")
                    .font(Theme.label(12)).foregroundStyle(Theme.muted).padding(.top, 4)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .titleInContent("Timers")
        .sheet(item: $editing) { t in WodBuilderSheet(initial: t) { running = $0 } }
        .fullScreenCover(item: $running) { t in BigScreenTimerView(timer: t) }
    }

    private func delete(_ t: WodTimer) {
        let i = store.timers.firstIndex(of: t) ?? 0
        store.delete(t)
        UndoCloseCenter.shared.deleted("Timer deleted", detail: t.name) { WodStore.shared.restore(t, at: i) }
    }
}

/// Square gradient tile of a timer kind.
private struct KindTile: View {
    let kind: WodTimer.Kind
    var title: String?
    var symbol: String?
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol ?? Self.symbol(kind)).font(.system(size: 18, weight: .heavy))
            Spacer(minLength: 0)
            Text(title ?? kind.label.uppercased()).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .selectableGradient(LinearGradient.wod(kind), selected: selected, cornerRadius: 18)
    }

    static func symbol(_ k: WodTimer.Kind) -> String {
        switch k {
        case .tabata: "bolt.fill"
        case .emom: "clock.arrow.circlepath"
        case .amrap: "repeat"
        case .forTime: "stopwatch.fill"
        case .rounds: "bell.fill"
        }
    }
}

private struct SavedTimerRow: View {
    let timer: WodTimer
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Image(systemName: KindTile.symbol(timer.kind)).font(.system(size: 18, weight: .heavy))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.name).font(Theme.display(18)).lineLimit(1)
                    Text(timer.summary + (timer.moves.isEmpty ? "" : " · \(timer.moves.count) moves")).font(Theme.label(12)).opacity(0.9)
                }
                Spacer(minLength: 4)
                Text(WodTimer.clock(timer.totalSeconds)).font(Theme.display(22)).monospacedDigit()
                Image(systemName: "play.fill").font(.system(size: 14, weight: .heavy))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
                    .foregroundStyle(Theme.ink)
            }
            .gradientCard(.wod(timer.kind), padding: 12)
        }
        .buttonStyle(.plain)
    }
}

/// Timer builder (A): kind tiles, the numbers, moves; Save keeps it (and sends it to the Watch), Start runs it.
struct WodBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var t: WodTimer
    @State private var movesText: String
    private let isNew: Bool
    private let onStart: (WodTimer) -> Void

    init(initial: WodTimer, onStart: @escaping (WodTimer) -> Void) {
        var first = initial
        // A preset opened in the builder becomes the member's own timer.
        if first.id.hasPrefix("preset-") { first.id = UUID().uuidString }
        _t = State(initialValue: first)
        _movesText = State(initialValue: initial.moves.joined(separator: "\n"))
        isNew = !WodStore.shared.timers.contains { $0.id == initial.id }
        self.onStart = onStart
    }

    private var built: WodTimer {
        var b = WodTimer(id: t.id, name: t.name.isEmpty ? t.kind.label : t.name,
                         kind: t.kind, work: t.work, rest: t.rest, rounds: t.rounds,
                         moves: movesText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                         punches: t.kind == .rounds && t.punches, prep: t.prep)
        if b.kind.capped { b.rest = 0 }
        return b
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(WodTimer.Kind.allCases) { k in
                            Button { switchKind(k) } label: { KindTile(kind: k, selected: t.kind == k) }
                                .buttonStyle(.plain)
                        }
                    }
                    TextField("Name", text: $t.name).font(Theme.display(22)).textInputAutocapitalization(.words)
                        .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardStrong))
                    numbers
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Moves").eyebrow()
                        TextField("10 KB swings\n10 push-ups", text: $movesText, axis: .vertical).lineLimit(2...8)
                            .font(Theme.label(15))
                            .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardStrong))
                    }
                    if t.kind == .rounds {
                        Toggle(isOn: $t.punches) {
                            Label("Count punches on Apple Watch", systemImage: "figure.boxing").font(Theme.label(15))
                        }
                        .tint(Theme.lime)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(built.summary).font(Theme.display(20))
                            Text("Total \(WodTimer.clock(built.totalSeconds)) with \(WodTimer.short(built.prep)) to get ready").font(Theme.label(12))
                                .opacity(0.9)
                        }
                        Spacer()
                    }
                    .gradientCard(.wod(t.kind))
                    Button { start() } label: {
                        Label("Start on big screen", systemImage: "play.fill").font(Theme.label(17)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isNew ? "New timer" : "Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isNew {
                    SaveToolbarItem { WodStore.shared.save(built); dismiss() }
                }
                CloseToolbarItem { dismiss() }
            }
            .onChange(of: built) { _, b in
                // Saved timers auto-save (#539).
                if !isNew { WodStore.shared.save(b) }
            }
        }
    }

    @ViewBuilder private var numbers: some View {
        VStack(spacing: 10) {
            if t.kind.capped {
                StepperRow(title: t.kind == .amrap ? "Time" : "Time cap", value: WodTimer.short(t.work)) { t.work = max(60, t.work + $0 * 60) }
            } else {
                StepperRow(title: t.kind == .emom ? "Every" : "Work", value: WodTimer.short(t.work)) { t.work = max(5, t.work + $0 * step(t.work)) }
                if t.kind != .emom {
                    StepperRow(title: "Rest", value: t.rest == 0 ? "none" : WodTimer.short(t.rest)) { t.rest = max(0, t.rest + $0 * step(t.rest)) }
                }
                StepperRow(title: "Rounds", value: "\(t.rounds)") { t.rounds = min(99, max(1, t.rounds + $0)) }
            }
            StepperRow(title: "Get ready", value: WodTimer.short(t.prep)) { t.prep = min(60, max(0, t.prep + $0 * 5)) }
        }
    }

    /// 5 s steps under a minute, 15 s under 3 minutes, then 30 s.
    private func step(_ s: Int) -> Int { s < 60 ? 5 : s < 180 ? 15 : 30 }

    private func switchKind(_ k: WodTimer.Kind) {
        guard k != t.kind else { return }
        let fresh = WodTimer.starting(k)
        t.kind = k
        t.work = fresh.work
        t.rest = fresh.rest
        t.rounds = fresh.rounds
        t.punches = fresh.punches
        if t.name.isEmpty || WodTimer.Kind.allCases.contains(where: { $0.label == t.name }) { t.name = k.label }
    }

    private func start() {
        let b = built
        if isNew { WodStore.shared.save(b) }
        dismiss()
        onStart(b)
    }
}

/// − value + row.
private struct StepperRow: View {
    let title: String
    let value: String
    let change: (Int) -> Void

    var body: some View {
        HStack {
            Text(title).font(Theme.label(15))
            Spacer()
            Button { change(-1) } label: { Image(systemName: "minus").frame(width: 40, height: 40) }
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardStrong))
            Text(value).font(Theme.display(22)).monospacedDigit().frame(minWidth: 76)
            Button { change(1) } label: { Image(systemName: "plus").frame(width: 40, height: 40) }
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardStrong))
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .heavy))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }
}

/// Big screen mode (C): iPhone propped up, huge countdown, round, next move. Turns sideways, keeps the screen on,
/// rings with sound and a buzz; the Watch shows a Start button that double tap presses.
struct BigScreenTimerView: View {
    let timer: WodTimer
    @Environment(\.dismiss) private var dismiss
    @State private var banked: TimeInterval = 0
    @State private var since: Date?
    @State private var cuedTo: TimeInterval = 0
    @State private var rounds = 0
    @State private var stoppedAt: TimeInterval?

    private var running: Bool { since != nil }

    private func elapsed(_ now: Date) -> TimeInterval { stoppedAt ?? banked + (since.map { now.timeIntervalSince($0) } ?? 0) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            GeometryReader { geo in
                let e = elapsed(ctx.date)
                let st = timer.state(at: e)
                let done = st.finished || stoppedAt != nil
                let rest = st.phase?.kind == .rest
                VStack(spacing: 6) {
                    Text(header(st, done: done)).font(Theme.label(geo.size.width > geo.size.height ? 22 : 18)).foregroundStyle(Color(hex: timer.kind.tint.1))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(WodTimer.clock(done && timer.kind != .forTime ? Int(e) - timer.prep : timer.display(at: e)))
                        .font(.system(size: min(geo.size.width * 0.3, geo.size.height * 0.45), weight: .black, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.3)
                        .foregroundStyle(rest ? Color(hex: 0x00C7FF) : .white)
                    if !timer.moves.isEmpty {
                        Text(timer.moves.joined(separator: " · ")).font(Theme.label(18)).multilineTextAlignment(.center).opacity(0.9)
                    }
                    Spacer(minLength: 8)
                    controls(done)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: Int(e * 5)) { _, _ in cue(e, st) }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.12)))
            }
            .foregroundStyle(.white).padding(12)
            .accessibilityLabel("Close")
        }
        .onAppear {
            OrientationLock.allowLandscape(true)
            UIApplication.shared.isIdleTimerDisabled = true
            remote()
        }
        .onDisappear {
            OrientationLock.allowLandscape(false)
            UIApplication.shared.isIdleTimerDisabled = false
            WatchSync.shared.sendWodRemote(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchTimerToggle)) { _ in toggle() }
        .statusBarHidden()
    }

    private func header(_ st: WodTimer.State, done: Bool) -> String {
        if done { return "\(timer.name.uppercased()) · DONE" + (timer.kind == .amrap ? " · \(rounds) ROUNDS" : "") }
        guard running || banked > 0, let p = st.phase else { return "\(timer.name.uppercased()) · \(timer.summary)" }
        switch p.kind {
        case .prep: return "GET READY"
        case .rest: return "REST · NEXT ROUND \(p.round + 1) OF \(timer.rounds)"
        case .work:
            switch timer.kind {
            case .amrap: return "AMRAP \(WodTimer.short(timer.work)) · ROUND \(rounds + 1)"
            case .forTime: return "FOR TIME · CAP \(WodTimer.short(timer.work))"
            default: return "ROUND \(p.round) OF \(timer.rounds)"
            }
        }
    }

    @ViewBuilder private func controls(_ done: Bool) -> some View {
        HStack(spacing: 12) {
            if !done {
                Button { toggle() } label: {
                    Label(running ? "Pause" : banked > 0 ? "Resume" : "Start", systemImage: running ? "pause.fill" : "play.fill")
                        .font(Theme.label(18)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime))
                }
                if running && timer.kind == .amrap {
                    Button { rounds += 1; Haptics.start() } label: {
                        Text("+1 round").font(Theme.label(18)).frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient.wod(.amrap)))
                    }
                }
                if running && timer.kind == .forTime {
                    Button { stoppedAt = elapsed(Date()); since = nil; play(.done); remote() } label: {
                        Text("Done").font(Theme.label(18)).frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient.wod(.forTime)))
                    }
                }
            } else {
                Button { close() } label: {
                    Text("Close").font(Theme.label(18)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(maxWidth: 560)
    }

    private func toggle() {
        guard stoppedAt == nil, !timer.state(at: elapsed(Date())).finished else { return }
        if let s = since {
            banked += Date().timeIntervalSince(s)
            since = nil
        } else {
            if banked == 0 && timer.prep == 0 { play(.bell) }
            since = Date()
        }
        Haptics.start()
        remote()
    }

    private func cue(_ e: TimeInterval, _ st: WodTimer.State) {
        guard running else { return }
        for c in timer.cues(from: cuedTo, to: e) { play(c) }
        cuedTo = e
        if st.finished {
            banked = e
            since = nil
            remote()
        }
    }

    private func play(_ c: WodTimer.Cue) {
        let gen = UINotificationFeedbackGenerator()
        switch c {
        case .bell: AudioServicesPlaySystemSound(1013); gen.notificationOccurred(.success)
        case .rest: AudioServicesPlaySystemSound(1006); gen.notificationOccurred(.warning)
        case .clap: AudioServicesPlaySystemSound(1104); AudioServicesPlaySystemSound(1104)
        case .tick: AudioServicesPlaySystemSound(1057)
        case .done: AudioServicesPlaySystemSound(1025); gen.notificationOccurred(.success)
        }
    }

    private func remote() {
        WatchSync.shared.sendWodRemote(WWodRemote(timer: timer, running: running))
    }

    private func close() {
        since = nil
        dismiss()
    }
}
