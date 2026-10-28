import AVFoundation
import SwiftUI
import UIKit
import WorkoutEngine

/// Full-screen breathing / relax session (#834 B): a square that fills on the breath in and empties on the breath out,
/// the phase and its countdown, spoken cues (system Coach voice, switchable) and a soft tap on every phase. Ends on a
/// breath out and saves mindful minutes; ✕ after a minute saves what was done with Undo.
struct BreathingPlayer: View {
    let breath: Breath
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mindVoice") private var voice = true
    @State private var minutes: Int
    /// First Start; nil = not started.
    @State private var startedAt: Date?
    /// Running since; nil = paused or not started.
    @State private var runningSince: Date?
    /// Seconds breathed before the last pause.
    @State private var banked: Double = 0
    @State private var finished = false
    @State private var speech = MindSpeech()

    init(breath: Breath) {
        self.breath = breath
        _minutes = State(initialValue: breath.defaultMinutes)
    }

    private var total: Double { breath.totalSeconds(minutes: minutes) }

    private func elapsed(_ now: Date) -> Double { banked + (runningSince.map { now.timeIntervalSince($0) } ?? 0) }

    var body: some View {
        ZStack {
            breath.gradient.ignoresSafeArea()
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 16) {
                header
                if finished {
                    done
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: runningSince == nil)) { ctx in
                        let t = elapsed(ctx.date)
                        let at = breath.at(t, minutes: minutes)
                        session(t: t, at: at)
                            .onChange(of: at.cycle * breath.phases.count + at.index) { _, step in
                                guard runningSince != nil else { return }
                                phaseChanged(at.phase, step: step)
                            }
                            .onChange(of: at.cue) { _, cue in
                                if let cue, voice, runningSince != nil { speech.say(cue) }
                            }
                            .onChange(of: t >= total) { _, over in
                                if over { finish() }
                            }
                    }
                }
            }
            .padding(20)
        }
        .foregroundStyle(breath.ink)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            speech.stop()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(breath.purpose).font(Theme.label(11)).tracking(1.4).textCase(.uppercase).opacity(0.85)
                Text(breath.label).font(Theme.display(30)).lineLimit(1).minimumScaleFactor(0.6)
                Text(breath.how).font(.subheadline.weight(.semibold)).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .heavy))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.3)))
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("breath.close")
        }
    }

    private func session(t: Double, at: (phase: Breath.Phase, index: Int, into: Double, cycle: Int, cue: String?)) -> some View {
        let n = breath.phases.count
        let from = t < breath.phases[0].seconds && at.cycle == 0 ? 0 : breath.phases[(at.index - 1 + n) % n].fill
        let p = at.phase.seconds > 0 ? at.into / at.phase.seconds : 1
        let eased = p * p * (3 - 2 * p)
        let fill = startedAt == nil ? 0.35 : from + (at.phase.fill - from) * eased
        let left = max(0, Int((total - t).rounded(.up)))
        return VStack(spacing: 18) {
            Spacer(minLength: 0)
            GeometryReader { g in
                let side = min(g.size.width, g.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: side * 0.14, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 3)
                        .frame(width: side * 0.92, height: side * 0.92)
                    RoundedRectangle(cornerRadius: side * 0.12, style: .continuous)
                        .fill(.white.opacity(0.9))
                        .frame(width: side * (0.25 + 0.67 * fill), height: side * (0.25 + 0.67 * fill))
                    VStack(spacing: 4) {
                        Text(startedAt == nil ? "Ready" : at.phase.label).font(Theme.display(26))
                        if startedAt != nil {
                            Text("\(max(1, Int((at.phase.seconds - at.into).rounded(.up))))").font(Theme.display(40)).monospacedDigit()
                        }
                    }
                    .foregroundStyle(Color(hex: breath.colors[1]))
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(startedAt == nil ? "Ready" : at.phase.label)
            Text(at.cue ?? " ").font(.title3.weight(.bold)).multilineTextAlignment(.center).frame(minHeight: 56)
                .opacity(startedAt == nil ? 0 : 1)
            Spacer(minLength: 0)
            controls(left: left)
        }
    }

    private func controls(left: Int) -> some View {
        VStack(spacing: 12) {
            if startedAt == nil {
                RoutineLengthChips(lengths: breath.lengths, selected: minutes) { minutes = $0 }
            } else {
                Text("\(left / 60):\(String(format: "%02d", left % 60)) left").font(Theme.label(15)).monospacedDigit().opacity(0.9)
            }
            HStack(spacing: 10) {
                Button { voice.toggle() } label: {
                    Image(systemName: voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.25)))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(voice ? "Voice on" : "Voice off")
                Button(action: toggleRun) {
                    Label(startedAt == nil ? "Start" : runningSince == nil ? "Resume" : "Pause",
                          systemImage: runningSince == nil ? "play.fill" : "pause.fill")
                        .font(Theme.label(17))
                        .foregroundStyle(Color(hex: breath.colors[1]))
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("breath.start")
            }
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark").font(.system(size: 40, weight: .black))
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white.opacity(0.25)))
            Text("Done · \(Int((total / 60).rounded())) min").font(Theme.display(30))
            Text("Saved as mindful minutes. \(MindStore.shared.weekMinutes) calm minutes this week.")
                .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).opacity(0.9)
            Spacer()
            HStack(spacing: 10) {
                Button(action: again) {
                    Label("Again", systemImage: "arrow.counterclockwise")
                        .font(Theme.label(16)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.25)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { dismiss() } label: {
                    Text("Done").font(Theme.label(17)).foregroundStyle(Color(hex: breath.colors[1]))
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("breath.done")
            }
        }
    }

    private func toggleRun() {
        let now = Date()
        if let since = runningSince {
            banked += now.timeIntervalSince(since)
            runningSince = nil
            speech.stop()
        } else {
            if startedAt == nil {
                startedAt = now
                Haptics.start()
                phaseChanged(breath.phases[0], step: 0)
            }
            runningSince = now
        }
    }

    /// Soft tap on each phase; the phase is spoken for the first two cycles, then only guided cues are.
    private func phaseChanged(_ phase: Breath.Phase, step: Int) {
        UIImpactFeedbackGenerator(style: phase.kind == .inhale ? .medium : .soft).impactOccurred()
        guard voice, step < 2 * breath.phases.count, breath.cues.isEmpty || phase.kind != .exhale else { return }
        speech.say(phase.label)
    }

    private func finish() {
        guard !finished, let startedAt else { return }
        runningSince = nil
        banked = total
        Haptics.success()
        if voice { speech.say("Well done") }
        model.finishCalm(breath, from: startedAt, to: startedAt.addingTimeInterval(total))
        withAnimation(.snappy) { finished = true }
    }

    private func again() {
        startedAt = nil
        runningSince = nil
        banked = 0
        withAnimation(.snappy) { finished = false }
    }

    /// ✕: a minute or more breathed is saved (Undo takes it back); less closes silently.
    private func close() {
        defer { dismiss() }
        guard !finished, let startedAt else { return }
        let done = elapsed(Date())
        guard let m = model.finishCalm(breath, from: startedAt, to: startedAt.addingTimeInterval(done), healthAfter: UndoCloseCenter.seconds)
        else { return }
        UndoCloseCenter.shared.show(UndoOffer(
            title: "\(breath.label) saved", detail: "\(Int(done) / 60) min · mindful minutes", symbol: breath.symbol,
            colors: breath.colors.map { Color(hex: $0) }, reopen: { AnyView(EmptyView()) },
            revert: { MindStore.shared.removeSession(m) }))
    }
}

/// Speaks breathing cues with the best system voice for the member's Coach voice picks, ducking other audio.
@MainActor
final class MindSpeech {
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: text)
        u.voice = CoachVoicePref.bestSystemVoice()
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
