import AVFoundation
import AVKit
import CoreMotion
import SwiftUI
import WorkoutEngine

// Film whole session (#957, A + B + C from `record-workout/session/proposals.png`): one tap to start, the camera runs for
// the whole workout and finds every set and move on its own (`FilmSession`). A live screen (A) or a dark one that saves
// battery (B, the Coach says each move and set out loud), the Watch's ✓ / ✗ on each new move (C), the phone being
// picked up pauses it, and a review of every move at the end before Save. On the iPhone only; one clip per move (its
// last set), deleted on Save or Discard.

/// Film my workout's two ways (#957): step by step (#952) or the whole session. The last pick is remembered.
enum FilmMode: String, Identifiable {
    case steps, session
    var id: String { rawValue }
}

/// Start sheet: two big tiles.
struct FilmModeSheet: View {
    let onPick: (FilmMode) -> Void
    @AppStorage("film.mode") private var last = FilmMode.steps.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Film my workout").font(Theme.display(24))
            tile(.steps, title: "Step by step", detail: "Show the weight, lift, review each move", symbol: "shoeprints.fill",
                 colors: [Color(hex: 0x7B4DFF), Color(hex: 0xE04FE0)])
            tile(.session, title: "Whole session", detail: "Hands-free: every move found, saved at the end", symbol: "video.fill",
                 colors: [Color(hex: 0xFF3B5C), Color(hex: 0xFF9A3C)])
            Text("Read on this iPhone, nothing sent. Clips are deleted when you move on.")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(16)
        .presentationDetents([.height(270)])
        .presentationBackground(Theme.bg)
    }

    private func tile(_ mode: FilmMode, title: String, detail: String, symbol: String, colors: [Color]) -> some View {
        Button {
            last = mode.rawValue
            onPick(mode)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .heavy))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.label(16))
                    Text(detail).font(Theme.label(11)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if last == mode.rawValue {
                    Text("LAST").font(Theme.label(9)).tracking(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.25)))
                }
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("film.mode.\(mode.rawValue)")
    }
}

/// The phone being picked up or carried (#957): detection pauses until it lies still again.
@MainActor final class FilmMotion {
    private let manager = CMMotionManager()
    private var stillSince: Date?
    /// Called with true when the phone starts moving, false once it has been still for `settle` seconds.
    var onMoving: ((Bool) -> Void)?
    private(set) var moving = false

    static let settle = 2.0

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            let a = m.userAcceleration, r = m.rotationRate
            let shaking = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() > 0.08 || (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot() > 0.6
            if shaking {
                stillSince = nil
                if !moving {
                    moving = true
                    onMoving?(true)
                }
            } else if moving {
                let since = stillSince ?? Date()
                stillSince = since
                if Date().timeIntervalSince(since) >= Self.settle {
                    moving = false
                    onMoving?(false)
                }
            }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

struct FilmSessionView: View {
    let onSave: ([FilmedMove], Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @AppStorage("formCheck.front") private var front = true
    @AppStorage("film.dark") private var dark = false
    @AppStorage("film.voice") private var voiceOn = true
    @State private var camera = FormCamera()
    @State private var motion = FilmMotion()
    @State private var voice = CoachVoice()
    @State private var session = FilmSession()
    @State private var denied = false
    @State private var started = Date()
    @State private var pose: FormPose?
    @State private var aspect = 9.0 / 16
    @State private var guessing = false
    @State private var reviewing = false
    // Better detection (#969): last frame with 3D joints, kit seen while resting, a set left without a weight.
    @State private var depthSeen: Double = -10
    @State private var scene: Set<String> = []
    @State private var askKg: Int?
    // In frame (#969, design B + C from `record-workout/detect/proposals.png`): a setup shape until the member holds
    // still in view, then the screen's edge light (green / amber / red), what to move and the Coach saying it.
    @State private var setup = true
    @State private var clock: Double = 0
    @State private var readySince: Double?
    @State private var rawIssue: FrameCheck.Issue? = .nobody
    @State private var rawSince: Double = 0
    @State private var issue: FrameCheck.Issue? = .nobody
    @State private var saidIssue: FrameCheck.Issue?
    @State private var saidAt: Double = -100
    @State private var brightnessWas: CGFloat?
    // Clips: the last set of each move.
    @State private var clip: ClipRecorder?
    @State private var clips: [UUID: URL] = [:]
    @State private var playing: AVPlayer?
    @State private var open: UUID?

    private var planned: Set<String> {
        Set((model.todaySession?.blocks ?? []).flatMap(\.items).map(\.exerciseId))
    }

    var body: some View {
        Group {
            if reviewing { reviewScreen } else { liveScreen }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!reviewing)
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            camera.stop()
            motion.stop()
            voice.stop()
            dropClips()
            ClipRecorder.wipeAll()
            dim(false)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task { await begin() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if !reviewing { guessIfDue() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchFilmAnswer)) { n in
            guard let a = n.object as? FilmAnswer else { return }
            if a.ok { session.confirm(a.move) } else {
                session.reject(a.move)
                if voiceOn, session.moves.indices.contains(a.move) { say(Exercise.get(session.moves[a.move].exerciseId).name) }
            }
        }
    }

    // MARK: Live (A) / dark (B)

    private var liveScreen: some View {
        ZStack {
            if dark && !setup {
                Color.black.ignoresSafeArea()
            } else if !denied {
                FormCameraPreview(session: camera.session).ignoresSafeArea()
                FormSkeleton(pose: pose, aspect: aspect, warn: session.live.warn, bad: session.live.bad).ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(hex: 0x2D3440), Color(hex: 0x1B1F27)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }
            if setup && !denied { setupShape }
            VStack(spacing: 10) {
                topBar
                if denied {
                    deniedCard
                } else if setup {
                    Spacer()
                    setupCard
                } else if dark {
                    Spacer()
                    if let issue { issueCard(issue) } else { darkNow }
                    Spacer()
                } else {
                    nowCard
                    Spacer()
                    if let issue { issueCard(issue) }
                    Spacer()
                }
                if session.paused { pausedCard }
                if let i = askKg, session.moves.indices.contains(i) { weightCard(i) }
                timeline
                Button { stop() } label: { Label("Stop · review", systemImage: "stop.fill").lineLimit(1) }
                    .buttonStyle(LimeButtonStyle(fill: Color(hex: 0xFF3B5C), text: .white))
                    .accessibilityIdentifier("film.session.stop")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .overlay {
            if !denied {
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .strokeBorder(edgeColor, lineWidth: 10)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.3), value: issue)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: In frame (B + C)

    /// Green in frame, amber part of the body off, red nobody: readable from across the room, and on the dark screen.
    private var edgeColor: Color {
        switch issue {
        case nil: Color(hex: 0x2BD67B)
        case .nobody?: Color(hex: 0xFF4D6D)
        default: Color(hex: 0xFFB02E)
        }
    }

    private var setupShape: some View {
        Image(systemName: "figure.stand")
            .resizable()
            .scaledToFit()
            .fontWeight(.ultraLight)
            .foregroundStyle((issue == nil ? Color(hex: 0x2BD67B) : Theme.lime).opacity(0.35))
            .shadow(color: Theme.lime.opacity(0.8), radius: 6)
            .padding(.vertical, 120)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var countdown: Int? {
        guard let r = readySince else { return nil }
        return max(1, Int((Self.setupHold - (clock - r)).rounded(.up)))
    }

    private static let setupHold = 3.0

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(countdown != nil ? "READY IN" : "STEP INTO THE SHAPE").font(Theme.label(10)).tracking(1.3).opacity(0.85)
            if let n = countdown {
                Text("\(n)").font(Theme.display(44)).monospacedDigit()
                Text("Hold still · starts by itself").font(Theme.label(13))
            } else {
                Label(issue?.title ?? "Whole body in the picture", systemImage: issue?.symbol ?? "figure.stand")
                    .font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.6)
                Text(issue?.detail ?? "Any side: front, side or 45°").font(Theme.label(13))
            }
            Button { endSetup() } label: { Text("Start now").lineLimit(1) }
                .buttonStyle(LimeButtonStyle(fill: .white))
                .accessibilityIdentifier("film.session.startNow")
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: countdown != nil ? [Color(hex: 0x2B6CFF), Color(hex: 0x7B4DFF)] : [Color(hex: 0xFF4D6D), Color(hex: 0xFF9A3C)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }

    private func issueCard(_ i: FrameCheck.Issue) -> some View {
        VStack(spacing: 4) {
            Image(systemName: i.symbol).font(.system(size: 44, weight: .black))
                .foregroundStyle(i == .nobody ? Color(hex: 0xFF4D6D) : Color(hex: 0xFFB02E))
            Text(i.title).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.6)
            Text(i.detail).font(Theme.label(12)).opacity(0.85).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: 260)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.7)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("film.session.frame")
    }

    /// The picture's check, steadied: a change shows (and is said) after 1 s, so the edge doesn't flicker.
    private func frame(_ p: FormPose?, at t: Double, aspect a: Double) {
        clock = t
        let now = FrameCheck.issue(p, aspect: a, mirrored: front)
        if now != rawIssue {
            rawIssue = now
            rawSince = t
        }
        if t - rawSince >= 1, issue != rawIssue {
            issue = rawIssue
            framed(issue)
        }
        guard setup else { return }
        if rawIssue == nil {
            let r = readySince ?? t
            readySince = r
            if t - r >= Self.setupHold { endSetup() }
        } else {
            readySince = nil
        }
    }

    private func framed(_ i: FrameCheck.Issue?) {
        guard voiceOn else { return }
        if let i {
            guard i != saidIssue || clock - saidAt > 10 else { return }
            say(i.spoken)
            saidIssue = i
            saidAt = clock
        } else if saidIssue != nil {
            if !setup { say(FrameCheck.inFrame) }
            saidIssue = nil
        }
    }

    /// In frame long enough (or Start now): filming starts.
    private func endSetup() {
        guard setup else { return }
        setup = false
        readySince = nil
        saidIssue = nil
        started = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if voiceOn { say("\(FrameCheck.inFrame). Start when ready") }
        if dark { dim(true) }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: started, by: 1)) { ctx in
                let s = Int(ctx.date.timeIntervalSince(started))
                Label(String(format: "%d:%02d", s / 60, s % 60), systemImage: "record.circle")
                    .font(Theme.label(14)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.55)))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 4)
            square(voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill", label: voiceOn ? "Mute Coach" : "Coach says each set") { voiceOn.toggle() }
            square(dark ? "sun.max.fill" : "moon.fill", label: dark ? "Show the camera" : "Dark screen, saves battery") {
                dark.toggle()
                if !setup { dim(dark) }
            }
            if !denied && !dark {
                square("arrow.triangle.2.circlepath.camera.fill", label: "Switch camera") {
                    front.toggle()
                    camera.start(front: front)
                }
            }
        }
        .padding(.top, 6)
    }

    private func square(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var nowTitle: String {
        if let i = session.current { return Exercise.get(session.moves[i].exerciseId).name }
        return session.moves.isEmpty ? "Start your first set" : "Resting"
    }

    private var nowDetail: String {
        guard let i = session.current else {
            return session.moves.isEmpty ? "Whole body in frame, from any side" : "Next set or move is found on its own"
        }
        let m = session.moves[i]
        let kg = m.kg.map { "\(LoadAdvisor.formatKg($0)) kg\(m.kgRead ? " · read" : " · last time")" } ?? "bodyweight"
        return "Set \(m.sets.count + 1) · \(session.live.reps.count) reps · \(kg)"
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NOW").font(Theme.label(10)).tracking(1.3).opacity(0.85)
            Text(nowTitle).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.6)
            Text(nowDetail).font(Theme.label(12)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x2B6CFF), Color(hex: 0x7B4DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }

    private var darkNow: some View {
        VStack(spacing: 4) {
            Text("NOW").font(Theme.label(11)).tracking(1.3).foregroundStyle(.secondary)
            Text(nowTitle).font(Theme.display(30)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
            if let i = session.current {
                Text("Set \(session.moves[i].sets.count + 1) · \(session.live.reps.count)")
                    .font(Theme.display(48)).monospacedDigit().foregroundStyle(Theme.lime)
            }
            Text("\(session.filmed.count) moves · \(session.moves.reduce(0) { $0 + $1.sets.count }) sets so far")
                .font(Theme.label(12)).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    /// A set logged for a move that takes a weight, none read and none from history (#969): tap it in, or carry on and
    /// fix it in the review.
    private func weightCard(_ i: Int) -> some View {
        let m = session.moves[i]
        let kg = m.kg ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("SET \(m.sets.count) LOGGED · \(Exercise.get(m.exerciseId).name.uppercased())")
                .font(Theme.label(10)).tracking(1.3).opacity(0.85).lineLimit(1)
            HStack(spacing: 8) {
                Text("Weight not read").font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Button { askKg = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .black)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fix it in the review")
            }
            HStack(spacing: 8) {
                ForEach([-2.5, 2.5], id: \.self) { d in
                    Button {
                        session.enter(kg: max(0, kg + d), move: i)
                    } label: {
                        Image(systemName: d < 0 ? "minus" : "plus")
                            .font(.system(size: 16, weight: .black))
                            .frame(width: 44, height: 40)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.black.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(d < 0 ? "Less weight" : "More weight")
                    if d < 0 {
                        Text(kg > 0 ? "\(LoadAdvisor.formatKg(kg)) kg" : "– kg")
                            .font(Theme.display(26)).monospacedDigit().frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x2B6CFF), Color(hex: 0x7B4DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityIdentifier("film.session.weight")
    }

    private var pausedCard: some View {
        Label("Phone moving · paused. Set it down with you in frame.", systemImage: "iphone.motion")
            .font(Theme.label(13)).foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFF9A3C), Color(hex: 0xFFB02E)], startPoint: .leading, endPoint: .trailing)))
    }

    private var timeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(session.moves.enumerated()), id: \.element.id) { i, m in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Exercise.get(m.exerciseId).name).lineLimit(1)
                        Text(i == session.current ? "set \(m.sets.count + 1)" : "\(m.sets.count) sets")
                    }
                    .font(Theme.label(10))
                    .foregroundStyle(.white)
                    .frame(width: 84, alignment: .leading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: Self.colors[i % Self.colors.count], startPoint: .leading, endPoint: .trailing)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(m.sure ? .clear : Color(hex: 0xFFB02E), style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                }
            }
        }
        .frame(height: 44)
    }

    private static let colors: [[Color]] = [
        [Color(hex: 0x2B6CFF), Color(hex: 0x7B4DFF)], [Color(hex: 0xE04FE0), Color(hex: 0xFF4D6D)],
        [Color(hex: 0xFF9A3C), Color(hex: 0xFFB02E)], [Color(hex: 0x2BD67B), Color(hex: 0x1FB5C9)],
    ]

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera is off for MonkeyWorkout").font(Theme.display(18))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(Theme.label(14)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Theme.lime))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FormColors.bad.opacity(0.85)))
    }

    // MARK: Review

    private var reviewScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session review").font(Theme.display(28))
                Text("Amber = not sure, tap to fix. * = last time's weight, not read.")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(session.moves.enumerated()), id: \.element.id) { i, m in
                    if !m.sets.isEmpty { moveRow(i, m) }
                }
                if session.filmed.isEmpty {
                    Text("No sets were found.").font(Theme.label(15)).padding(.vertical, 20)
                }
                HStack(spacing: 8) {
                    Button { dismiss() } label: { Text("Discard").lineLimit(1) }
                        .buttonStyle(LimeButtonStyle(fill: Color(hex: 0x2A2A30), text: .white))
                    Button { save() } label: { Label("Save workout · \(session.filmed.count)", systemImage: "checkmark").lineLimit(1) }
                        .buttonStyle(LimeButtonStyle())
                        .disabled(session.filmed.isEmpty)
                        .accessibilityIdentifier("film.session.save")
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func moveRow(_ i: Int, _ m: FilmSession.Move) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy) { open = open == m.id ? nil : m.id } } label: {
                HStack(spacing: 8) {
                    Image(systemName: m.sure ? "figure.strengthtraining.traditional" : "questionmark")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.25)))
                    Text(Exercise.get(m.exerciseId).name + (m.sure ? "" : "?")).font(Theme.label(15)).lineLimit(1)
                    Spacer()
                    Text(FilmedMove(exerciseId: m.exerciseId, sets: m.sets).summary + (m.kgRead || m.kg == nil ? "" : "*"))
                        .font(Theme.label(13)).monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(m.sure ? AnyShapeStyle(LinearGradient(colors: Self.colors[i % Self.colors.count], startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color(hex: 0x2A2A30))))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(m.sure ? .clear : Color(hex: 0xFFB02E), style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            }
            .buttonStyle(.plain)
            if open == m.id { moveDetail(i, m) }
        }
    }

    @ViewBuilder
    private func moveDetail(_ i: Int, _ m: FilmSession.Move) -> some View {
        if !m.alternatives.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(m.alternatives, id: \.self) { alt in
                        Button {
                            if let k = session.moves[i].alternatives.firstIndex(of: alt) {
                                session.moves[i].alternatives[k] = session.moves[i].exerciseId
                            }
                            session.moves[i].exerciseId = alt
                            session.moves[i].sure = true
                        } label: {
                            Text(Exercise.get(alt).name).font(Theme.label(12)).lineLimit(1)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                    if !m.sure {
                        Button { session.confirm(i) } label: {
                            Label("Right", systemImage: "checkmark").font(Theme.label(12))
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(Capsule().fill(Theme.lime)).foregroundStyle(Theme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        if let url = clips[m.id] {
            if let playing, open == m.id {
                VideoPlayer(player: playing).frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Button {
                    let p = AVPlayer(url: url)
                    playing = p
                    p.play()
                } label: {
                    Label("Watch last set", systemImage: "play.rectangle.fill").font(Theme.label(13))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        ForEach(m.sets.indices, id: \.self) { k in
            HStack(spacing: 8) {
                Text("SET \(k + 1)").font(Theme.label(11)).opacity(0.8).frame(width: 46, alignment: .leading)
                stepper("\(m.sets[k].reps) reps",
                        minus: { session.moves[i].sets[k].reps = max(1, session.moves[i].sets[k].reps - 1) },
                        plus: { session.moves[i].sets[k].reps += 1 })
                stepper("\(LoadAdvisor.formatKg(m.sets[k].kg)) kg",
                        minus: { session.moves[i].sets[k].kg = max(0, session.moves[i].sets[k].kg - 2.5) },
                        plus: { session.moves[i].sets[k].kg += 2.5 })
                Button { session.moves[i].sets.remove(at: k) } label: {
                    Image(systemName: "trash").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove set \(k + 1)")
            }
            .foregroundStyle(.white)
        }
    }

    private func stepper(_ text: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: minus) { Image(systemName: "minus").frame(width: 26, height: 30) }.buttonStyle(.plain)
            Text(text).font(Theme.label(13)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
            Button(action: plus) { Image(systemName: "plus").frame(width: 26, height: 30) }.buttonStyle(.plain)
        }
        .font(.system(size: 13, weight: .black))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.1)))
    }

    // MARK: Flow

    private func begin() async {
        guard await FormCamera.allowed() else {
            denied = true
            return
        }
        camera.onPose = { p, t, a in feed(p, at: t, aspect: a) }
        camera.depth = true
        camera.onScene = { labels in
            // Kit in view while resting names the next move.
            if !session.inSet { scene.formUnion(labels) }
        }
        camera.textWithPose = true
        camera.onText = { seen in
            // Between sets only: a number shown or on the kit in view is the next set's weight.
            guard !session.inSet, let kg = WeightReading.kg(from: seen) else { return }
            session.read(kg: kg)
        }
        motion.onMoving = { moving in
            if moving {
                if let e = session.pause() { handle(e) }
            } else {
                session.resume()
            }
        }
        motion.start()
        camera.start(front: front)
        started = Date()
    }

    private func feed(_ p: FormPose?, at t: Double, aspect a: Double) {
        guard !reviewing else { return }
        aspect = a
        pose = p
        frame(p, at: t, aspect: a)
        // Nothing is counted while setting up.
        if setup { return }
        if p?.world != nil { depthSeen = t }
        // With the 3D pose found, only its frames are counted: angles from the picture and from 3D don't mix.
        if p != nil, p?.world == nil, t - depthSeen < 2 { return }
        if let e = session.add(p, at: t) { handle(e) }
    }

    private func guessIfDue() {
        guard session.needsGuess, !guessing else { return }
        guessing = true
        let frames = session.pending, plan = planned, recent = model.recentExerciseIds(), last = session.moves.last?.exerciseId
        let seen = scene, gym = model.profile.map { Set($0.equipment) }
        Task.detached(priority: .userInitiated) {
            let g = FilmWorkout.guess(frames, models: FilmWorkout.models, planned: plan, recent: recent, current: last,
                                      scene: seen, gym: gym)
            await MainActor.run {
                guessing = false
                if let e = session.accept(g) { handle(e) }
            }
        }
    }

    private func handle(_ e: FilmSession.Event) {
        switch e {
        case let .newMove(i):
            askKg = nil
            scene = []
            let m = session.moves[i]
            if let last = model.lastWeight(m.exerciseId) { session.fill(kg: last, move: i) }
            let name = Exercise.get(m.exerciseId).name
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if voiceOn { say(name) }
            WatchSync.shared.sendFilmGuess(WFilmGuess(move: i, name: name,
                                                      alternative: m.alternatives.first.map { Exercise.get($0).name },
                                                      reps: session.live.reps.count))
            startClip()
        case .sameMove:
            askKg = nil
            scene = []
            startClip()
        case let .setLogged(i, n, reps):
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let m = session.moves[i]
            let noKg = FilmWorkout.needsWeight(m.exerciseId, kg: m.kg)
            if noKg { askKg = i }
            if voiceOn { say("\(Exercise.get(m.exerciseId).name), set \(n), \(reps) reps\(noKg ? ". Weight not read, tap it in" : "")") }
            finishClip(for: session.moves[i].id)
        }
    }

    private func say(_ text: String) {
        voice.speak(text, style: CoachPref.style)
    }

    private func stop() {
        if let e = session.end() { handle(e) }
        camera.stop()
        motion.stop()
        voice.stop()
        dim(false)
        clip?.discard()
        clip = nil
        camera.clip = nil
        withAnimation(.snappy) { reviewing = true }
    }

    private func save() {
        onSave(session.filmed, started)
        dismiss()
    }

    /// Dark screen (B): the display down to its lowest; back to what it was on light or close.
    private func dim(_ on: Bool) {
        if on {
            if brightnessWas == nil { brightnessWas = UIScreen.main.brightness }
            UIScreen.main.brightness = 0.05
        } else if let was = brightnessWas {
            UIScreen.main.brightness = was
            brightnessWas = nil
        }
    }

    // MARK: Clips

    private func startClip() {
        clip?.discard()
        let c = ClipRecorder()
        camera.clip = c
        clip = c
    }

    /// The set's clip becomes its move's; the one before is deleted.
    private func finishClip(for move: UUID) {
        guard let c = clip else { return }
        camera.clip = nil
        clip = nil
        c.finish { url in
            if let old = clips[move], old != url { try? FileManager.default.removeItem(at: old) }
            clips[move] = url
        }
    }

    private func dropClips() {
        playing?.pause()
        playing = nil
        clip?.discard()
        clip = nil
        camera.clip = nil
        for url in clips.values { try? FileManager.default.removeItem(at: url) }
        clips = [:]
    }
}
