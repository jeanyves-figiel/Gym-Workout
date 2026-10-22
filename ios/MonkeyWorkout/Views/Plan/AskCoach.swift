import AVFoundation
import Speech
import SwiftUI
import WorkoutEngine

/// Ask Coach everywhere (#412, design A + C from `ask-coach-everywhere/proposals.png`). A: the lime 🐵 bubble floats on
/// every tab (drag it to either edge); tap = the chat as a sheet that knows the screen, hold = talk. C: "✨ question"
/// sparks on key cards, and the hands-free mic in the player. Questions go by voice too: on-device speech-to-text in,
/// the coach voice out.
enum AskCoachPref {
    static let bubbleKey = "askCoach.bubble"
    static let playerMicKey = "askCoach.playerMic"
    static let speakKey = "askCoach.speak"
    static let bubbleRightKey = "askCoach.bubble.right"
    static let bubbleYKey = "askCoach.bubble.y"

    enum Speak: String, CaseIterable, Identifiable {
        case whenTalking, always, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .whenTalking: "When I talk"
            case .always: "Always"
            case .never: "Never"
            }
        }
    }

    static var speak: Speak { UserDefaults.standard.string(forKey: speakKey).flatMap(Speak.init) ?? .whenTalking }
    static var playerMic: Bool { UserDefaults.standard.object(forKey: playerMicKey) as? Bool ?? true }
}

/// What the member is looking at, sent with the question (`screen` + `focus` on the server).
struct CoachFocus: Equatable {
    var screen: String
    /// Shown on the chip: "Looking at: Bench press".
    var title: String
    /// Numbers or facts for the coach (not shown).
    var detail: String?
    /// Starter questions for this screen.
    var starters: [String] = []

    var text: String { String((detail.map { "\(title) · \($0)" } ?? title).prefix(300)) }

    static func tab(_ t: MainTab) -> CoachFocus {
        switch t {
        case .train: CoachFocus(screen: "train", title: "Train", starters: ["45 min full body", "Quick 20 min, I'm tired", "What should I train today?"])
        case .explore: CoachFocus(screen: "explore", title: "Explore", starters: ["Best exercises for my back", "A programme for my goal?"])
        case .progress: CoachFocus(screen: "progress", title: "Progress", starters: ["How am I doing?", "What should I improve?"])
        case .fuel: CoachFocus(screen: "fuel", title: "Fuel", starters: ["What should I eat after training?", "High-protein breakfast ideas", "What can I cook with eggs and rice?"])
        case .community: CoachFocus(screen: "community", title: "Community", starters: ["How do I stay motivated?"])
        }
    }
}

struct AskCoachRequest: Identifiable {
    let id = UUID()
    var focus: CoachFocus?
    /// Sent at once when set (a spark, or a question said in the player).
    var question: String?
    /// Start listening at once (hold on the bubble).
    var listen = false
    /// The question was spoken: the answer is read aloud (unless Settings says never).
    var spoken = false
}

/// Which screen is on top, for the bubble's chat.
@MainActor @Observable final class CoachAsk {
    static let shared = CoachAsk()

    private struct Entry {
        let id: UUID
        let focus: CoachFocus
    }

    private var stack: [Entry] = []
    var request: AskCoachRequest?

    var current: CoachFocus? { stack.last?.focus }

    func push(_ id: UUID, _ f: CoachFocus) {
        stack.removeAll { $0.id == id }
        stack.append(Entry(id: id, focus: f))
    }

    func pop(_ id: UUID) { stack.removeAll { $0.id == id } }

    func open(tab: MainTab, listen: Bool = false) {
        request = AskCoachRequest(focus: current ?? .tab(tab), listen: listen)
    }
}

private struct CoachFocusModifier: ViewModifier {
    let focus: CoachFocus
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { CoachAsk.shared.push(id, focus) }
            .onChange(of: focus) { CoachAsk.shared.push(id, focus) }
            .onDisappear { CoachAsk.shared.pop(id) }
    }
}

extension View {
    /// Tells the floating coach what this screen shows (#412).
    func coachFocus(_ focus: CoachFocus) -> some View { modifier(CoachFocusModifier(focus: focus)) }
}

// MARK: - Bubble (A)

/// The floating 🐵: drag to the left or right edge (kept), tap to ask, hold to talk.
struct AskCoachBubble: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AskCoachPref.bubbleRightKey) private var right = true
    @AppStorage(AskCoachPref.bubbleYKey) private var y = 0.78
    @State private var drag: CGSize = .zero
    @State private var gate: ProGate?
    private let size: CGFloat = 56

    var body: some View {
        GeometryReader { g in
            if g.safeAreaInsets.trailing >= size, g.size.width < g.size.height {
                // iPhone Duo outer screen (#594 design A): iOS keeps a column on the right for the status bar and the
                // tab rail, and the cards fill the rest. The 🐵 docks in that column, on top of the tab rail, so it
                // never covers a card.
                face
                    .position(x: g.size.width + g.safeAreaInsets.trailing / 2,
                              y: max(size, g.size.height + g.safeAreaInsets.bottom - Self.railHeight - size / 2 - 12))
            } else {
                floating(g)
            }
        }
        .proPaywall($gate)
    }

    /// The system tab rail on the Duo outer screen: five tab icons plus its margin above the bottom edge.
    private static let railHeight: CGFloat = 286

    private func floating(_ g: GeometryProxy) -> some View {
        let minY = size / 2 + 60
        // Above the tab bar.
        let maxY = max(minY + 1, g.size.height - size / 2 - 64)
        let cy = minY + (maxY - minY) * y
        let cx = right ? g.size.width - size / 2 - 12 : size / 2 + 12
        return face
            .position(x: cx + drag.width, y: cy + drag.height)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { drag = $0.translation }
                    .onEnded { v in
                        right = cx + v.translation.width > g.size.width / 2
                        y = min(1, max(0, (cy + v.translation.height - minY) / (maxY - minY)))
                        withAnimation(.spring(duration: 0.3)) { drag = .zero }
                    })
    }

    private var face: some View {
        MonkeyFace(mood: .fired, scale: 0.6, gear: model.rank.gear)
            .frame(width: 40, height: 36)
            .frame(width: size, height: size)
            .background(Circle().fill(RadialGradient(colors: [Color(hex: 0xEDFF7A), Theme.lime], center: .init(x: 0.3, y: 0.3), startRadius: 2, endRadius: 40)))
            .overlay(Circle().stroke(Theme.lime.opacity(0.35), lineWidth: 5).padding(-4))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
            .contentShape(Circle())
            .onTapGesture { ask(listen: false) }
            .onLongPressGesture(minimumDuration: 0.4) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                ask(listen: true)
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Ask Coach")
            .accessibilityHint("Hold to talk")
            .accessibilityAction { ask(listen: false) }
            .accessibilityAction(named: "Talk to Coach") { ask(listen: true) }
            .accessibilityIdentifier("askCoach.bubble")
    }

    private func ask(listen: Bool) {
        ProStore.shared.run(.generateWorkout, $gate) { CoachAsk.shared.open(tab: model.tab, listen: listen) }
    }
}

// MARK: - Sparks (C)

/// "✨ Why is it down?" on a card: opens the coach with that question about the card.
struct CoachSpark: View {
    let question: String
    let focus: CoachFocus
    @State private var request: AskCoachRequest?
    @State private var gate: ProGate?

    var body: some View {
        Button {
            ProStore.shared.run(.generateWorkout, $gate) { request = AskCoachRequest(focus: focus, question: question) }
        } label: {
            Label(question, systemImage: "sparkles")
                .font(Theme.label(12))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.28)))
                .overlay(Capsule().stroke(Theme.lime.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Coach: \(question)")
        .proPaywall($gate)
        .sheet(item: $request) { r in CoachChatView(ask: r).remotePaused(.askCoach) }
    }
}

// MARK: - Voice in

/// On-device speech-to-text for the chat and the player mic: listens until a short silence, then hands over the words.
@MainActor @Observable final class CoachListener {
    private(set) var listening = false
    private(set) var text = ""
    /// Why listening can't start (no permission, no recognizer).
    var problem: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silence: Task<Void, Never>?
    @ObservationIgnored private var onDone: ((String) -> Void)?

    func start(_ onDone: @escaping (String) -> Void) {
        guard !listening else { return }
        self.onDone = onDone
        text = ""
        problem = nil
        #if DEBUG
        if Demo.enabled { return }
        #endif
        Task {
            guard await Self.authorize() else {
                problem = "Allow the microphone and speech recognition in Settings to talk to Coach."
                return
            }
            begin()
        }
    }

    /// Stops and sends what was heard.
    func finish() { stop(send: true) }

    /// Stops without sending.
    func cancel() { stop(send: false) }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            problem = "Speech recognition isn't available right now."
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            // Music keeps playing, quieter, while Coach listens.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .mixWithOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            problem = "The microphone is busy."
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        // Offline and private when the device can.
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        Self.tap(engine.inputNode, into: req)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            request = nil
            problem = "The microphone is busy."
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        listening = true
        task = Self.recognize(recognizer, req) { [weak self] said, final in
            Task { @MainActor in self?.heard(said, final: final) }
        }
        // Nothing said at all: stop after a while.
        armSilence(after: 7)
    }

    /// Off the main actor: the tap runs on the audio thread.
    nonisolated private static func tap(_ input: AVAudioInputNode, into req: SFSpeechAudioBufferRecognitionRequest) {
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
    }

    nonisolated private static func recognize(_ r: SFSpeechRecognizer, _ req: SFSpeechAudioBufferRecognitionRequest,
                                              _ handle: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        r.recognitionTask(with: req) { result, error in
            handle(result?.bestTranscription.formattedString, result?.isFinal == true || error != nil)
        }
    }

    private func heard(_ said: String?, final: Bool) {
        guard listening else { return }
        if let said, !said.isEmpty {
            text = said
            armSilence(after: 1.4)
        }
        if final { finish() }
    }

    private func armSilence(after sec: Double) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(sec))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func stop(send: Bool) {
        let done = onDone
        onDone = nil
        guard listening else { return }
        listening = false
        silence?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if send, !said.isEmpty { done?(said) }
    }
}

/// Listening state: pulsing bars and the words so far.
struct ListeningBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(Theme.lime)
                        .frame(width: 4, height: 6 + 12 * abs(sin(t * 5 + Double(i) * 1.3)))
                }
            }
            .frame(height: 20)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Settings

/// Settings → Workout coach → Ask Coach card.
struct AskCoachSettingsCard: View {
    @AppStorage(AskCoachPref.bubbleKey) private var bubble = true
    @AppStorage(AskCoachPref.playerMicKey) private var playerMic = true
    @AppStorage(AskCoachPref.speakKey) private var speak = AskCoachPref.Speak.whenTalking.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 22, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Coach").font(Theme.display(22))
                    Text("Ask from any screen, by text or voice").font(.caption).opacity(0.9)
                }
            }
            Toggle("🐵 bubble on every screen", isOn: $bubble).tint(Theme.lime).font(Theme.label(14))
                .accessibilityIdentifier("askCoach.bubbleToggle")
            Toggle("Hey Coach mic in the player", isOn: $playerMic).tint(Theme.lime).font(Theme.label(14))
            VStack(alignment: .leading, spacing: 6) {
                Text("Read answers aloud").eyebrow()
                HStack(spacing: 6) {
                    ForEach(AskCoachPref.Speak.allCases) { s in
                        Button { speak = s.rawValue } label: {
                            Text(s.title).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Capsule().fill(speak == s.rawValue ? Theme.lime : .white.opacity(0.2)))
                                .foregroundStyle(speak == s.rawValue ? Theme.ink : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Voice is turned into text on your iPhone. Only the words are sent to Coach.").font(.caption).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x11998E), Color(hex: 0x38B6FF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}
