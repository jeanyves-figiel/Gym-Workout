import AVFoundation
import AVKit
import SwiftUI
import WorkoutEngine

// Film my workout (#952, design B "Show · Lift · Review" with A's sets that log themselves, from
// `record-workout/proposals.png`): the member props the phone up, shows the weight (the text reader reads its print),
// lifts (the form check's body pose names the move, counts reps, scores form; a set logs itself after a few seconds
// without a rep) and ends each exercise on a review with an optional clip of the last set. Everything runs on the
// iPhone: no frame leaves it, and the clip is a temp file deleted on Next, on close and at launch.

// MARK: - Clip

/// The last set's video for the review: a temp file, never uploaded, deleted as soon as the member moves on.
final class ClipRecorder: @unchecked Sendable {
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("film-clips", isDirectory: true)
    /// Longest clip kept; later frames of a very long set are dropped.
    static let maxSeconds = 120.0

    let url: URL
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startedAt: CMTime?
    private var closed = false

    init() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        url = Self.folder.appendingPathComponent(UUID().uuidString + ".mp4")
    }

    /// On the camera queue.
    func append(_ sample: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sample)
        if writer == nil {
            guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
                closed = true
                return
            }
            let i = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: CVPixelBufferGetWidth(buffer),
                AVVideoHeightKey: CVPixelBufferGetHeight(buffer),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000],
            ])
            i.expectsMediaDataInRealTime = true
            guard w.canAdd(i) else {
                closed = true
                return
            }
            w.add(i)
            w.startWriting()
            w.startSession(atSourceTime: t)
            writer = w
            input = i
            startedAt = t
        }
        if let s = startedAt, (t - s).seconds > Self.maxSeconds { return }
        if input?.isReadyForMoreMediaData == true { input?.append(sample) }
    }

    /// Stops writing; `done` (main thread) gets the file once it plays, nil when nothing was written.
    func finish(_ done: @escaping (URL?) -> Void) {
        lock.lock()
        closed = true
        let w = writer, i = input
        lock.unlock()
        guard let w, w.status == .writing else {
            DispatchQueue.main.async { done(nil) }
            return
        }
        i?.markAsFinished()
        let url = url
        w.finishWriting { DispatchQueue.main.async { done(w.status == .completed ? url : nil) } }
    }

    func discard() {
        lock.lock()
        closed = true
        let w = writer
        lock.unlock()
        if w?.status == .writing { w?.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }

    /// At launch and when the film screen closes: no clip outlives it.
    static func wipeAll() {
        try? FileManager.default.removeItem(at: folder)
    }
}

// MARK: - Screen

struct FilmWorkoutView: View {
    /// The move is known (player "Film this set"): no naming.
    var exercise: Exercise? = nil
    /// One move only (player, custom session): its review ends with Done instead of Next exercise.
    var oneMove = false
    /// Starting weight for a known move (the player's current set).
    var startKg: Double? = nil
    /// The filmed moves and when filming began, on Done (one move) or Log workout (whole workout).
    let onDone: ([FilmedMove], Date) -> Void

    enum Step { case show, lift, review, built }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @AppStorage("formCheck.front") private var front = true
    @State private var step = Step.show
    @State private var camera = FormCamera()
    @State private var denied = false
    @State private var started = Date()
    // Weight
    @State private var kg: Double?
    @State private var kgRead = false
    @State private var readings: [Double] = []
    // Lift
    @State private var frames: [FilmWorkout.Frame] = []
    @State private var guesses: [FilmWorkout.Guess] = []
    @State private var guessing = false
    @State private var move: Exercise?
    @State private var analyzer: MoveCounter?
    @State private var depthSeen: Double = -10
    @State private var live = FormLive()
    @State private var pose: FormPose?
    @State private var aspect = 9.0 / 16
    @State private var lastRepAt: Double?
    @State private var clock: Double = 0
    @State private var sets: [FilmedSet] = []
    @State private var undoShown = false
    @State private var clip: ClipRecorder?
    @State private var clipURL: URL?
    @State private var watching = false
    @State private var clipPlayer: AVPlayer?
    // Workout
    @State private var moves: [FilmedMove] = []
    @State private var saveAsWorkout = false

    private var planned: Set<String> {
        Set((model.todaySession?.blocks ?? []).flatMap(\.items).map(\.exerciseId))
    }

    var body: some View {
        ZStack {
            switch step {
            case .show, .lift: cameraScreen
            case .review: reviewScreen
            case .built: builtScreen
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(step == .show || step == .lift)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            move = exercise
            kg = startKg
        }
        .onDisappear {
            camera.stop()
            camera.clip?.discard()
            camera.clip = nil
            ClipRecorder.wipeAll()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task { await begin() }
        .task {
            // Sets log themselves; the move is named once enough reps are seen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                tick()
            }
        }
    }

    // MARK: Camera (show + lift)

    private var cameraScreen: some View {
        ZStack {
            if !denied {
                FormCameraPreview(session: camera.session).ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(hex: 0x2D3440), Color(hex: 0x1B1F27), Color(hex: 0x2A241D)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            if step == .lift {
                FormSkeleton(pose: pose, aspect: aspect, warn: live.warn, bad: live.bad).ignoresSafeArea()
            }
            VStack(spacing: 10) {
                topBar
                stepsBar
                if step == .lift { liftTiles }
                Spacer()
                if denied { deniedCard } else if step == .show { showCard } else { liftBottom }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text(move?.name ?? (step == .show ? "Show the weight" : "Start lifting"))
                .font(Theme.label(14)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.55)))
            if !moves.isEmpty {
                Text("\(moves.count) done")
                    .font(Theme.label(12))
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime.opacity(0.9)))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 4)
            if !denied {
                square("arrow.triangle.2.circlepath.camera.fill", label: "Switch camera") {
                    front.toggle()
                    camera.start(front: front)
                }
            }
            square("xmark", label: "Close") { discard() }
        }
        .foregroundStyle(.white)
        .padding(.top, 6)
    }

    private var stepsBar: some View {
        HStack(spacing: 5) {
            stepChip("1 Show", on: step == .show)
            stepChip("2 Lift", on: step == .lift)
            stepChip("3 Review", on: step == .review)
        }
    }

    private func stepChip(_ title: String, on: Bool) -> some View {
        Text(title.uppercased())
            .font(Theme.label(11)).tracking(1)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.lime : .black.opacity(0.6)))
            .foregroundStyle(on ? Theme.ink : .white)
    }

    private func square(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .black))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Show

    private var showCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kgRead ? "WEIGHT READ" : "HOLD THE WEIGHT'S NUMBER TO THE CAMERA")
                .font(Theme.label(10)).tracking(1.3).opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(kg.map { LoadAdvisor.formatKg($0) } ?? "–").font(Theme.display(44)).monospacedDigit()
                Text("kg").font(Theme.display(20)).opacity(0.85)
                Spacer()
                kgStepper
            }
            // Hands-free (#969): the first rep starts the set; bodyweight moves need no weight.
            Label("Or just start lifting: the set starts on its own", systemImage: "figure.strengthtraining.traditional")
                .font(Theme.label(13))
                .accessibilityIdentifier("film.lift")
            Text("Dumbbells, kettlebells, plates and machine labels. Read on this iPhone, nothing saved.")
                .font(.caption.weight(.semibold)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x7B4DFF), Color(hex: 0xE04FE0)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var kgStepper: some View {
        HStack(spacing: 6) {
            ForEach([-2.5, 2.5], id: \.self) { d in
                Button {
                    kg = max(0, (kg ?? 0) + d)
                    kgRead = false
                } label: {
                    Image(systemName: d < 0 ? "minus" : "plus")
                        .font(.system(size: 15, weight: .black))
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d < 0 ? "2.5 kg less" : "2.5 kg more")
            }
        }
    }

    // MARK: Lift

    private var liftTiles: some View {
        HStack(alignment: .top, spacing: 8) {
            tile("REPS", "\(live.reps.count)", [Color(hex: 0x7B4DFF), Color(hex: 0xE04FE0)])
            Button { step = .show; startReading() } label: {
                tile(kgRead ? "KG · READ" : "KG", kg.map { LoadAdvisor.formatKg($0) } ?? "–", [Color(hex: 0xFF9A3C), Color(hex: 0xFF4D6D)])
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change the weight")
            tile("FORM", live.score.map(String.init) ?? "–", [Color(hex: 0x2BD67B), Color(hex: 0x1FB5C9)])
        }
    }

    private func tile(_ k: String, _ v: String, _ colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(Theme.label(9)).tracking(1.2).opacity(0.85)
            Text(v).font(Theme.display(30)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var liftBottom: some View {
        if move == nil {
            if let top = guesses.first { guessCard(top) } else { hintCard }
        } else if let cue = live.cue, analyzer != nil {
            Label(cue.text, systemImage: cue.symbol)
                .font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .foregroundStyle(cue.tone == .warn ? Theme.ink : .white)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: FormColors.tone(cue.tone), startPoint: .leading, endPoint: .trailing)))
        }
        setStrip
        Button { endMove() } label: {
            Label(sets.isEmpty && live.reps.isEmpty ? "Skip this move" : "Done · review", systemImage: "checkmark")
        }
        .buttonStyle(LimeButtonStyle())
        .accessibilityIdentifier("film.review")
    }

    private var hintCard: some View {
        Text("Prop the phone 2–3 m away, side on, whole body in frame. The move is named after 2 reps.")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x5B6BFF), Color(hex: 0xA64DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func guessCard(_ top: FilmWorkout.Guess) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOOKS LIKE · \(top.confidence)%").font(Theme.label(10)).tracking(1.3).opacity(0.85)
            Button { pick(top.exerciseId) } label: {
                HStack {
                    Text(Exercise.get(top.exerciseId).name).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Image(systemName: "checkmark.square.fill").font(.system(size: 22, weight: .black))
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Confirms the move")
            HStack(spacing: 6) {
                ForEach(guesses.dropFirst(), id: \.exerciseId) { g in
                    Button { pick(g.exerciseId) } label: {
                        Text(Exercise.get(g.exerciseId).name)
                            .font(Theme.label(11)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x7B4DFF), Color(hex: 0xE04FE0)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    /// Sets logged so far; the last one can be taken back while its Undo shows.
    private var setStrip: some View {
        HStack(spacing: 5) {
            ForEach(Array(sets.enumerated()), id: \.offset) { i, s in
                Text("\(s.reps)×\(LoadAdvisor.formatKg(s.kg))")
                    .font(Theme.label(12)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x2B6CFF)))
                    .accessibilityLabel("Set \(i + 1): \(s.reps) reps at \(LoadAdvisor.formatKg(s.kg)) kg")
            }
            if undoShown {
                Button { undoSet() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(Theme.label(12)).lineLimit(1)
                        .frame(minHeight: 30).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0xFF2D55), Color(hex: 0xA64DFF)], startPoint: .leading, endPoint: .trailing)))
                }
                .buttonStyle(.plain)
            }
            if sets.isEmpty && !undoShown {
                Text("Sets log themselves when you rack")
                    .font(Theme.label(11)).opacity(0.8)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.5)))
            }
        }
        .foregroundStyle(.white)
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera is off for MonkeyWorkout").font(Theme.display(18))
            Text("Filming needs the camera to see the weight and your joints. Nothing is sent.").font(.caption.weight(.semibold))
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(move?.name ?? "Review").font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    square("xmark", label: "Close") { discard() }
                }
                clipBox
                HStack(spacing: 8) {
                    tile("SETS", setsText, [Color(hex: 0x2B6CFF), Color(hex: 0x7B4DFF)])
                    tile("KG", sets.last.map { LoadAdvisor.formatKg($0.kg) } ?? "–", [Color(hex: 0xFF9A3C), Color(hex: 0xFF4D6D)])
                    tile("FORM", FilmedMove(exerciseId: move?.id ?? "", sets: sets).form.map(String.init) ?? "–",
                         [Color(hex: 0x2BD67B), Color(hex: 0x1FB5C9)])
                }
                ForEach(sets.indices, id: \.self) { i in setRow(i) }
                HStack(spacing: 8) {
                    Button { anotherSet() } label: { Label("Another set", systemImage: "plus").lineLimit(1) }
                        .buttonStyle(LimeButtonStyle(fill: .white))
                    Button { nextMove() } label: {
                        Label(oneMove ? "Done" : "Next exercise", systemImage: oneMove ? "checkmark" : "forward.fill").lineLimit(1)
                    }
                    .buttonStyle(LimeButtonStyle())
                    .accessibilityIdentifier("film.next")
                }
                if !oneMove {
                    Button { finishWorkout() } label: { Label("Finish workout", systemImage: "flag.checkered").lineLimit(1) }
                        .buttonStyle(LimeButtonStyle(fill: Color(hex: 0x2A2A30), text: .white))
                }
                Text("The clip is optional and deleted when you move on. Never saved or uploaded.")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var setsText: String {
        guard !sets.isEmpty else { return "0" }
        let reps = Set(sets.map(\.reps))
        return reps.count == 1 ? "\(sets.count)×\(sets[0].reps)" : "\(sets.count)"
    }

    @ViewBuilder
    private var clipBox: some View {
        if let clipURL {
            if watching, let clipPlayer {
                VideoPlayer(player: clipPlayer)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Button {
                    let p = AVPlayer(url: clipURL)
                    clipPlayer = p
                    watching = true
                    p.play()
                } label: {
                    Label("Watch last set", systemImage: "play.rectangle.fill")
                        .font(Theme.label(15))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x2D3440), Color(hex: 0x1B1F27)], startPoint: .top, endPoint: .bottom)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func setRow(_ i: Int) -> some View {
        HStack(spacing: 8) {
            Text("SET \(i + 1)").font(Theme.label(11)).tracking(1).opacity(0.8).frame(width: 46, alignment: .leading)
            stepper("\(sets[i].reps) reps", minus: { sets[i].reps = max(1, sets[i].reps - 1) }, plus: { sets[i].reps += 1 })
            stepper("\(LoadAdvisor.formatKg(sets[i].kg)) kg", minus: { sets[i].kg = max(0, sets[i].kg - 2.5) }, plus: { sets[i].kg += 2.5 })
            Button { sets.remove(at: i) } label: {
                Image(systemName: "trash").font(.system(size: 13, weight: .bold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove set \(i + 1)")
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
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

    // MARK: Built

    private var builtScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Workout built").font(Theme.display(28))
                    Spacer()
                    square("xmark", label: "Close") { discard() }
                }
                ForEach(Array(moves.enumerated()), id: \.element.id) { i, m in
                    HStack(spacing: 10) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 14, weight: .black))
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.25)))
                        Text(Exercise.get(m.exerciseId).name).font(Theme.label(15)).lineLimit(1)
                        Spacer()
                        Text(m.summary).font(Theme.label(14)).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: Self.rowColors[i % Self.rowColors.count], startPoint: .leading, endPoint: .trailing)))
                }
                Toggle(isOn: $saveAsWorkout) {
                    Text("Also save as one of my workouts").font(Theme.label(14))
                }
                .tint(Theme.lime)
                .padding(.vertical, 4)
                Button { logWorkout() } label: { Label("Log workout", systemImage: "checkmark").lineLimit(1) }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(moves.isEmpty)
                    .accessibilityIdentifier("film.log")
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private static let rowColors: [[Color]] = [
        [Color(hex: 0x2B6CFF), Color(hex: 0x7B4DFF)], [Color(hex: 0xE04FE0), Color(hex: 0xFF4D6D)],
        [Color(hex: 0xFF9A3C), Color(hex: 0xFFB02E)], [Color(hex: 0x2BD67B), Color(hex: 0x1FB5C9)],
    ]

    // MARK: Flow

    private func begin() async {
        guard await FormCamera.allowed() else {
            denied = true
            return
        }
        camera.onPose = { p, t, a in feed(p, at: t, aspect: a) }
        camera.depth = true
        // The body is followed while the weight is read, so the first rep can start the set (#969).
        camera.textWithPose = true
        startReading()
        camera.start(front: front)
    }

    /// Show: frames go to the text reader; the same weight read three times in a row is taken and lifting starts.
    private func startReading() {
        readings = []
        camera.onText = { seen in
            guard step == .show, let v = WeightReading.kg(from: seen) else { return }
            readings = Array((readings + [v]).suffix(3))
            kg = v
            kgRead = true
            if readings.count == 3, Set(readings).count == 1 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                goLift()
            }
        }
    }

    private func goLift() {
        camera.onText = nil
        readings = []
        // Frames seen while showing the weight stay: the set may already have started (#969).
        if let move, analyzer == nil { analyzer = MoveCounter(exercise: move) }
        // Back from fixing the weight mid-set: the set's clip goes on.
        if clip == nil { startClip() }
        withAnimation(.snappy) { step = .lift }
    }

    private func feed(_ p: FormPose?, at t: Double, aspect a: Double) {
        guard step == .show || step == .lift else { return }
        clock = t
        aspect = a
        pose = p
        if p?.world != nil { depthSeen = t }
        // With the 3D pose found, only its frames are counted: angles from the picture and from 3D don't mix.
        if p != nil, p?.world == nil, t - depthSeen < 2 { return }
        if move == nil {
            frames.append((time: t, pose: p))
            // About the last 40 s.
            if frames.count > 1200 { frames.removeFirst(frames.count - 1200) }
        }
        if let move, analyzer == nil { analyzer = MoveCounter(exercise: move) }
        guard var an = analyzer else { return }
        let before = an.reps.count
        live = an.add(p, at: t)
        analyzer = an
        if an.reps.count > before {
            lastRepAt = t
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func tick() {
        guard step == .show || step == .lift else { return }
        if move == nil { guessMove() }
        if step == .show {
            // Hands-free (#969): a rep starts the set, no button.
            if !live.reps.isEmpty { goLift() }
            return
        }
        if move != nil, FilmWorkout.setEnded(reps: live.reps.count, lastRepAt: lastRepAt, now: clock) { logSet() }
    }

    /// Names the move off the main thread; the top guess is taken without a tap after `repsToAccept` reps.
    private func guessMove() {
        guard !guessing, let a = frames.first?.time, let b = frames.last?.time, b - a >= 2 else { return }
        guessing = true
        let f = frames, plan = planned, recent = model.recentExerciseIds()
        Task.detached(priority: .userInitiated) {
            let g = FilmWorkout.guess(f, models: FilmWorkout.models, planned: plan, recent: recent)
            await MainActor.run {
                guessing = false
                guard move == nil, let top = g.first else { return }
                if step == .show { goLift() }
                guard top.reps >= FilmWorkout.repsToGuess else { return }
                guesses = g
                if top.reps >= FilmWorkout.repsToAccept { pick(top.exerciseId) }
            }
        }
    }

    /// The move is known: its reps so far are counted again on the frames kept, so none are lost.
    private func pick(_ id: String) {
        let e = Exercise.get(id)
        guard var an = MoveCounter(exercise: e) else { return }
        for f in frames { an.add(f.pose, at: f.time) }
        live = an.live
        analyzer = an
        lastRepAt = an.reps.isEmpty ? nil : clock
        move = e
        guesses = []
        frames = []
        if kg == nil || !kgRead, let last = model.lastWeight(id) { kg = last }
        if !kgRead, PRPlanner.isBodyweight(e) { kg = 0 }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func logSet() {
        guard let move, !live.reps.isEmpty else { return }
        sets.append(FilmedSet(reps: live.reps.count, kg: kg ?? 0, form: live.score))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        analyzer = MoveCounter(exercise: move)
        live = FormLive()
        lastRepAt = nil
        undoShown = true
        // The next set gets its own clip; the review shows the last one.
        finishClip()
        startClip()
        let count = sets.count
        Task {
            try? await Task.sleep(for: .seconds(5))
            if sets.count == count { undoShown = false }
        }
    }

    private func undoSet() {
        guard !sets.isEmpty else { return }
        sets.removeLast()
        undoShown = false
    }

    private func endMove() {
        if move != nil, !live.reps.isEmpty { logSet() }
        undoShown = false
        guard move != nil, !sets.isEmpty else {
            // Nothing done: back to Show for another move (or out, for a single one).
            if oneMove { return close() }
            resetMove()
            return
        }
        camera.stop()
        camera.clip?.discard()
        camera.clip = nil
        withAnimation(.snappy) { step = .review }
    }

    private func anotherSet() {
        watching = false
        dropClip()
        live = FormLive()
        lastRepAt = nil
        camera.start(front: front)
        goLift()
    }

    private func nextMove() {
        if let move, !sets.isEmpty { moves.append(FilmedMove(exerciseId: move.id, sets: sets)) }
        if oneMove {
            onDone(moves, started)
            return close()
        }
        resetMove()
        camera.start(front: front)
    }

    private func resetMove() {
        watching = false
        dropClip()
        move = nil
        analyzer = nil
        live = FormLive()
        pose = nil
        sets = []
        kg = nil
        kgRead = false
        lastRepAt = nil
        frames = []
        guesses = []
        step = .show
        startReading()
    }

    private func finishWorkout() {
        if let move, !sets.isEmpty { moves.append(FilmedMove(exerciseId: move.id, sets: sets)) }
        sets = []
        self.move = nil
        watching = false
        dropClip()
        withAnimation(.snappy) { step = .built }
    }

    private func logWorkout() {
        if saveAsWorkout {
            let items = moves.map { m in
                CustomWorkout.Item(exerciseId: m.exerciseId, sets: m.sets.count, reps: m.sets.map(\.reps).max() ?? 10)
            }
            model.saveCustomWorkout(CustomWorkout(name: "Filmed \(started.formatted(.dateTime.day().month()))", items: items))
        }
        onDone(moves, started)
        close()
    }

    private func close() {
        dropClip()
        dismiss()
    }

    /// X with filmed sets (#988): closes at once, the Undo bar keeps them (logged as on Log workout / Done).
    private func discard() {
        var kept = moves
        if let move, !sets.isEmpty { kept.append(FilmedMove(exerciseId: move.id, sets: sets)) }
        close()
        guard !kept.isEmpty else { return }
        let at = started
        UndoCloseCenter.shared.deleted("Filmed sets discarded", detail: "\(kept.count) move\(kept.count == 1 ? "" : "s")",
                                       symbol: "video.slash.fill") { [onDone] in onDone(kept, at) }
    }

    // MARK: Clip

    private func startClip() {
        let c = ClipRecorder()
        camera.clip = c
        clip = c
    }

    /// The set's clip becomes the one to review; the one before is deleted.
    private func finishClip() {
        guard let c = clip else { return }
        camera.clip = nil
        clip = nil
        c.finish { url in
            if let old = clipURL, old != url { try? FileManager.default.removeItem(at: old) }
            clipURL = url
        }
    }

    private func dropClip() {
        clipPlayer?.pause()
        clipPlayer = nil
        clip?.discard()
        clip = nil
        camera.clip = nil
        if let old = clipURL { try? FileManager.default.removeItem(at: old) }
        clipURL = nil
    }
}
