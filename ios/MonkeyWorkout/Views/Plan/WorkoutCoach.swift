import AVFoundation
import Observation
import SwiftUI
import UIKit
import WorkoutEngine

/// Settings → Workout coach (#379).
enum CoachPref {
    static let onKey = "coach.on"
    static let styleKey = "coach.style"
    static let voiceKey = "coach.voice"
    static let hapticsKey = "coach.haptics"
    static let watchKey = "coach.watch"

    static var on: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }
    static var style: CoachStyle { UserDefaults.standard.string(forKey: styleKey).flatMap(CoachStyle.init) ?? .hype }
    static var voice: CoachVoiceLevel { UserDefaults.standard.string(forKey: voiceKey).flatMap(CoachVoiceLevel.init) ?? .keyMoments }
    static var haptics: Bool { UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true }
    static var watch: Bool { UserDefaults.standard.object(forKey: watchKey) as? Bool ?? true }

    static var summary: String {
        guard on else { return "Off" }
        let studio = CoachVoicePref.studio
        return "\(style.emoji) \(style.title) · voice " + voice.title.lowercased() + (studio.isEmpty || voice == .off ? "" : " · \(studio)")
    }
}

/// The in-workout coach (#379, design A + C from `workout-coach/proposals.png`): Coach Monkey from Train follows the member
/// into the player. Lines come from `CoachLines` (on the device, from the member's own sets). A: spoken over the music,
/// with a short subtitle bubble over the picture and the 🐵 pill in the header (tap = mute this workout). C: the big
/// moments only (record burst over the exercise card, Final set badge, finish), each said once per exercise.
@MainActor @Observable
final class WorkoutCoach {
    struct Call: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let at = Date()
    }

    struct Record: Equatable, Identifiable {
        let id = UUID()
        let exercise: String
        let kg: Double
        let reps: Int
        let heavierBy: Double?
        let text: String
    }

    /// Subtitle bubble (A), about 3.5 s.
    private(set) var bubble: Call?
    /// Record burst over the exercise card (C), about 3 s; tap closes it.
    var record: Record?
    /// Muted for this workout from the header pill.
    var muted = false
    /// Last line for the Watch mirror (with a tap on the wrist).
    private(set) var watchLine: Call?
    var speaking: Bool { voice.speaking }
    var enabled: Bool { CoachPref.on }
    /// The pill shows when the coach speaks (voice not off).
    var hasVoice: Bool { CoachPref.on && CoachPref.voice != .off }

    private let voice = CoachVoice()
    private var said: Set<String> = []
    private var count = 0
    /// Demo screens keep the bubble and the burst on screen.
    var hold = false

    /// `once`: a key that makes the line one-off for this workout (e.g. "final-<uid>").
    func say(_ m: CoachMoment, once: String? = nil) {
        guard CoachPref.on else { return }
        let level = CoachPref.voice
        // Rare by design (C): set-by-set lines only when the member asks for every set.
        guard m.isKey || level == .everySet else { return }
        if let once {
            guard !said.contains(once) else { return }
            said.insert(once)
        }
        count += 1
        let seed = count &* 7 &+ said.count
        // Studio voice (#395): the recorded line for this moment (its words in the bubble too); else the iPhone voice
        // reads the full line, numbers included.
        let clip = CoachVoiceStore.shared.clip(style: CoachPref.style, kind: m.studioKind, seed: seed)
        let text = clip?.text ?? CoachLines.line(m, style: CoachPref.style, seed: seed)
        deliver(text, key: m.isKey, clip: clip?.url)
        if case let .record(e, kg, reps, more) = m {
            record = Record(exercise: e, kg: kg, reps: reps, heavierBy: more, text: text)
            bubble = nil
            clear(after: 3.2) { [weak self] in self?.record = nil }
        }
    }

    func stop() { voice.stop() }

    /// A resumed workout: what was already said before (e.g. "half") stays unsaid.
    func markSaid(_ key: String) { said.insert(key) }

    private func deliver(_ text: String, key: Bool, clip: URL?) {
        let call = Call(text: text)
        bubble = call
        watchLine = CoachPref.watch ? call : nil
        clear(after: 3.5) { [weak self] in if self?.bubble == call { self?.bubble = nil } }
        #if DEBUG
        let quiet = Demo.enabled  // no speech in demo/screenshot runs
        #else
        let quiet = false
        #endif
        if CoachPref.voice != .off, !muted, !quiet {
            if let clip { voice.play(clip) } else { voice.speak(text, style: CoachPref.style) }
        }
        if CoachPref.haptics, key { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func clear(after sec: Double, _ action: @escaping @MainActor () -> Void) {
        guard !hold else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(sec))
            action()
        }
    }
}

/// The coach's voice, ducking the member's music while it talks (#379): a studio recording (#395) or iOS speech with the
/// best installed voice for the member's pick.
@MainActor @Observable
final class CoachVoice: NSObject {
    private(set) var speaking = false
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var player: AVAudioPlayer?

    /// Opens the audio session for one line; false = stay quiet (#402).
    /// Music playing: talk over it and duck it (the member chose to hear audio). No music: `.ambient`, which follows the
    /// Ring/Silent switch. Never at zero volume.
    private func duck() -> Bool {
        let session = AVAudioSession.sharedInstance()
        if session.isOtherAudioPlaying {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } else {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        guard session.outputVolume > 0.01 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return false
        }
        return true
    }

    /// Plays a studio recording.
    func play(_ url: URL) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        guard let p = try? AVAudioPlayer(contentsOf: url), duck() else {
            speaking = false
            return
        }
        p.delegate = self
        player = p
        speaking = p.play()
        if !speaking { done() }
    }

    override init() {
        super.init()
        synth.delegate = self
        // Speech goes through the session set in duck(), so it follows the silent switch too.
        synth.usesApplicationAudioSession = true
    }

    /// iOS speech (#395: the best installed voice for the pick, premium first, not the basic one for the language).
    func speak(_ text: String, style: CoachStyle, voice: AVSpeechSynthesisVoice? = CoachVoicePref.bestSystemVoice()) {
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        guard duck() else {
            speaking = false
            return
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")
        // Natural voices sound wrong with a pitch shift; only the pace follows the style.
        switch style {
        case .chill: u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.97
        case .hype: u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.04
        case .drill: u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.06
        }
        u.postUtteranceDelay = 0.1
        speaking = true
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        done()
    }

    fileprivate func done() {
        guard !synth.isSpeaking, player?.isPlaying != true else { return }
        speaking = false
        // Music back to full volume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension CoachVoice: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.done() }
    }
}

extension CoachVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.done() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.done() }
    }
}

// MARK: - Views

/// Header pill (A): the monkey glows while it talks; tap mutes the voice for this workout.
struct CoachPill: View {
    let coach: WorkoutCoach

    var body: some View {
        Button { coach.muted.toggle(); if coach.muted { coach.stop() } } label: {
            HStack(spacing: 3) {
                MonkeyFace(mood: coach.muted ? .sleepy : .fired, scale: 0.34)
                    .frame(width: 24, height: 21)
                if coach.muted {
                    Image(systemName: "speaker.slash.fill").font(.system(size: 10, weight: .heavy))
                } else {
                    SoundBars(active: coach.speaking)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(Capsule().stroke(coach.muted ? Theme.stroke : Theme.lime, lineWidth: 1.5))
            .foregroundStyle(coach.muted ? Theme.muted : Theme.lime)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(coach.muted ? "Coach muted. Unmute" : "Coach voice on. Mute for this workout")
        .accessibilityIdentifier("player.coach")
    }
}

private struct SoundBars: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 1.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().frame(width: 2, height: active ? 4 + 6 * abs(sin(t * 7 + Double(i) * 1.3)) : 4)
                }
            }
            .frame(height: 12)
        }
    }
}

/// Subtitle bubble (A) over the picture: what the coach just said, about 3.5 s. Doesn't take layout space.
struct CoachBubble: View {
    let call: WorkoutCoach.Call

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 11, weight: .heavy))
            Text(call.text).font(Theme.label(14)).lineLimit(3).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.lime, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .frame(maxWidth: 300)
        .allowsHitTesting(false)
        .accessibilityIdentifier("player.coachBubble")
        .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
    }
}

/// Record burst (C) over the exercise card: monkey, the set, the coach's line. Tap or 3 s closes it.
struct CoachRecordBurst: View {
    let record: WorkoutCoach.Record
    let onClose: () -> Void
    @State private var pop = false

    var body: some View {
        Button(action: onClose) {
            VStack(spacing: 6) {
                Text("🎉 ✨ 🎊").font(.system(size: 26))
                MonkeyFace(mood: .party, scale: 1.3)
                    .frame(width: 92, height: 80)
                    .scaleEffect(pop ? 1 : 0.4)
                Text("NEW PERSONAL RECORD").font(Theme.label(11)).tracking(1.6)
                Text("\(LoadAdvisor.formatKg(record.kg)) kg × \(record.reps)")
                    .font(Theme.display(34)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(record.text).font(Theme.label(14)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    if let more = record.heavierBy {
                        tag("+\(LoadAdvisor.formatKg(more)) kg on your best", lime: true)
                    }
                    tag(record.exercise, lime: false)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.lime, Color(hex: 0x5DFFB0), Color(hex: 0x3BC8FF)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("player.coachRecord")
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.55)) { pop = true }
        }
    }

    private func tag(_ text: String, lime: Bool) -> some View {
        Text(text).font(Theme.label(11)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Theme.ink))
            .foregroundStyle(lime ? Theme.lime : .white)
    }
}

// MARK: - Settings

/// Settings → Workout coach (#379): on/off, style, voice, haptics, Watch taps, and a sample line to hear it.
struct CoachSettingsView: View {
    @AppStorage(CoachPref.onKey) private var on = true
    @AppStorage(CoachPref.styleKey) private var style = CoachStyle.hype.rawValue
    @AppStorage(CoachPref.voiceKey) private var voice = CoachVoiceLevel.keyMoments.rawValue
    @AppStorage(CoachPref.hapticsKey) private var haptics = true
    @AppStorage(CoachPref.watchKey) private var watch = true
    @State private var sample = CoachVoice()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    MonkeyFace(mood: on ? .fired : .sleepy, scale: 0.7)
                        .frame(width: 50, height: 44)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.2)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings · Workout").eyebrow()
                        Text("Workout coach").font(Theme.display(24))
                    }
                    Spacer()
                    Toggle("Workout coach", isOn: $on).labelsHidden().tint(Theme.lime)
                        .accessibilityIdentifier("coach.toggle")
                }
                Text(on ? "Coach Monkey cheers you on in the player: last set, halfway, records and the finish."
                        : "Off: the player stays silent, no coach lines.")
                    .font(.subheadline).opacity(0.9)
                if on {
                    section("Style") {
                        ForEach(CoachStyle.allCases) { s in
                            chip("\(s.emoji) \(s.title)", picked: style == s.rawValue) { style = s.rawValue }
                        }
                    }
                    section("Voice") {
                        ForEach(CoachVoiceLevel.allCases) { v in
                            chip(v.title, picked: voice == v.rawValue) { voice = v.rawValue }
                        }
                    }
                    Text(voiceHint).font(.caption).opacity(0.85)
                    if voice != CoachVoiceLevel.off.rawValue {
                        CoachVoicePicker(style: CoachStyle(rawValue: style) ?? .hype, sample: sample)
                    }
                    Toggle("Haptics on key moments", isOn: $haptics).tint(Theme.lime).font(Theme.label(14))
                    Toggle("Show and tap on Apple Watch", isOn: $watch).tint(Theme.lime).font(Theme.label(14))
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xFF4D8A), Color(hex: 0x8A3DF0)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .padding(20)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Workout coach")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { sample.stop() }
    }

    private var voiceHint: String {
        switch CoachVoiceLevel(rawValue: voice) ?? .keyMoments {
        case .off: "No voice. Lines show on screen at the key moments."
        case .keyMoments: "Speaks at the start, last set, halfway, records and the finish. Ducks your music; quiet in silent mode."
        case .everySet: "Also after each set (vs last time) and 10 s before rest ends."
        }
    }

    private func section<Chips: View>(_ title: String, @ViewBuilder _ chips: () -> Chips) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).eyebrow()
            HStack(spacing: 6) { chips() }
        }
    }

    private func chip(_ title: String, picked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(picked ? Theme.lime : .white.opacity(0.2)))
                .foregroundStyle(picked ? Theme.ink : .white)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}
