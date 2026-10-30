import AVFoundation
import SwiftUI
import Vision
import WorkoutEngine

// Form check (#833, designs A + B + C from `form-check/proposals.png`): the member props the phone up, the camera
// finds their joints (Apple's body pose, on the iPhone: no picture leaves the phone or is saved) and the screen counts
// reps, colours joints that drift, says one cue at a time (A), can lay the 3D guide's lime ghost over them (B) and ends
// on a set report kept in the exercise's history (C). Rules live in `WorkoutEngine/FormCheck.swift`.

// MARK: - Camera

/// Camera frames → body pose. Joints only: frames are dropped as soon as Vision has read them.
final class FormCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "monkeyworkout.form-check", qos: .userInitiated)
    private let request = VNDetectHumanBodyPoseRequest()
    private var startTime: Double?
    /// On the main thread: the frame's pose (nil = nobody in view), its time in seconds and its width ÷ height.
    var onPose: ((FormPose?, Double, Double) -> Void)?
    /// Film my workout (#952): while set, frames go to the text reader (twice a second) instead of the body pose, to
    /// read the weight shown to the camera. On the main thread.
    var onText: (([WeightReading.Seen]) -> Void)?
    /// Film whole session (#957): the text reader runs once a second alongside the body pose instead of replacing it.
    var textWithPose = false
    /// Film my workout's review clip (#952): frames are also written here while set.
    var clip: ClipRecorder?
    private let textRequest: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .fast
        r.usesLanguageCorrection = false
        return r
    }()
    private var lastText: Double = -1
    /// Front camera frames are mirrored like the preview: the text reader flips them back.
    private var mirrored = false

    static func allowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(front: Bool) {
        queue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            for i in session.inputs { session.removeInput(i) }
            for o in session.outputs { session.removeOutput(o) }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            if let c = output.connection(with: .video) {
                // Upright frames, mirrored like the preview on the front camera, so the joints sit on the picture.
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                if front, c.isVideoMirroringSupported {
                    c.automaticallyAdjustsVideoMirroring = false
                    c.isVideoMirrored = true
                }
            }
            session.commitConfiguration()
            mirrored = front
            startTime = nil
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let t0 = startTime ?? t
        startTime = t0
        let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(max(1, CVPixelBufferGetHeight(buffer)))
        clip?.append(sampleBuffer)
        if let onText {
            if t - lastText >= (textWithPose ? 1 : 0.5) {
                lastText = t
                try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: mirrored ? .upMirrored : .up).perform([textRequest])
                let seen = (textRequest.results ?? []).compactMap { o in
                    o.topCandidates(1).first.map { WeightReading.Seen($0.string, size: Double(o.boundingBox.height)) }
                }
                DispatchQueue.main.async { onText(seen) }
            }
            if !textWithPose { return }
        }
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        // The person filling the frame most.
        let best = (request.results ?? []).max { Self.seen($0) < Self.seen($1) }
        let pose = best.flatMap { Self.pose($0, aspect: aspect) }
        DispatchQueue.main.async { [weak self] in self?.onPose?(pose, t - t0, aspect) }
    }

    private static let names: [(VNHumanBodyPoseObservation.JointName, FormJoint)] = [
        (.nose, .nose), (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip), (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]

    private static func seen(_ o: VNHumanBodyPoseObservation) -> Int {
        ((try? o.recognizedPoints(.all)) ?? [:]).values.filter { $0.confidence > 0.3 }.count
    }

    /// Vision's points (0–1, y up) in frame-height units, low-confidence points left out.
    static func pose(_ o: VNHumanBodyPoseObservation, aspect: Double) -> FormPose? {
        guard let pts = try? o.recognizedPoints(.all) else { return nil }
        var out: [FormJoint: SIMD2<Double>] = [:]
        for (vn, j) in names {
            if let p = pts[vn], p.confidence > 0.3 { out[j] = SIMD2(Double(p.location.x) * aspect, Double(p.location.y)) }
        }
        return out.count >= 6 ? FormPose(out) : nil
    }
}

struct FormCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: PreviewView, context: Context) {}
}

// MARK: - Drawing

enum FormColors {
    static let good = Color(hex: 0x2BD67B)
    static let warn = Color(hex: 0xFFB02E)
    static let bad = Color(hex: 0xFF4D6D)

    static func score(_ s: Int) -> Color { s >= 85 ? good : s >= 70 ? warn : bad }

    static func tone(_ t: FormCue.Tone) -> [Color] {
        switch t {
        case .good: [Color(hex: 0x2BD67B), Color(hex: 0x1FB5C9)]
        case .warn: [Color(hex: 0xFFB02E), Color(hex: 0xFFD23A)]
        case .bad: [Color(hex: 0xFF4D6D), Color(hex: 0xFF9A3C)]
        case .info: [Color(hex: 0x3B7BFF), Color(hex: 0x3BE3C4)]
        }
    }
}

/// Frame units (height 1, y up) → points of a view showing the frame aspect-filled.
struct FormFrameMap {
    let size: CGSize
    let aspect: Double

    func point(_ p: SIMD2<Double>) -> CGPoint {
        let k = max(size.width / aspect, size.height)
        let ox = (size.width - aspect * k) / 2, oy = (size.height - k) / 2
        return CGPoint(x: ox + p.x * k, y: oy + (1 - p.y) * k)
    }

    var scale: Double { max(size.width / aspect, size.height) }
}

/// The member's skeleton (white, joints green / amber / red) and the guide's lime ghost behind it.
struct FormSkeleton: View {
    var pose: FormPose?
    var ghost: FormPose?
    var aspect: Double
    var warn: Set<FormJoint> = []
    var bad: Set<FormJoint> = []
    var lineScale: Double = 1

    var body: some View {
        Canvas { ctx, size in
            let map = FormFrameMap(size: size, aspect: aspect)
            let unit = max(1.5, map.scale / 260) * lineScale
            if let ghost { draw(ghost, in: &ctx, map: map, color: Theme.lime.opacity(0.5), width: 9 * unit, joints: false) }
            if let pose { draw(pose, in: &ctx, map: map, color: .white.opacity(0.95), width: 3.5 * unit, joints: true) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ p: FormPose, in ctx: inout GraphicsContext, map: FormFrameMap, color: Color, width: Double, joints: Bool) {
        var path = Path()
        for (a, b) in FormPose.bones {
            guard let pa = p[a], let pb = p[b] else { continue }
            path.move(to: map.point(pa))
            path.addLine(to: map.point(pb))
        }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        if let n = p[.nose] {
            let c = map.point(n), r = width * 3.2
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color),
                       lineWidth: width * 0.8)
        }
        guard joints else { return }
        for (j, q) in p.points where j != .nose {
            let c = map.point(q)
            let off = bad.contains(j) || warn.contains(j)
            let r = width * (off ? 2.1 : 1.4)
            let fill = bad.contains(j) ? FormColors.bad : warn.contains(j) ? FormColors.warn : FormColors.good
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(fill))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
    }
}

// MARK: - Live screen (A + B)

/// Demo screens (simulator: no camera): a made-up member drives the same screen.
enum FormCheckDemo: String {
    case live, ghost, report
}

struct FormCheckView: View {
    let exercise: Exercise
    /// From the player: "Use N reps" puts the count in the current set.
    var onReps: ((Int) -> Void)?
    var demo: FormCheckDemo?

    enum Mode: String { case mirror, ghost }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("formCheck.mode") private var modeRaw = Mode.mirror.rawValue
    @AppStorage("formCheck.front") private var front = true
    @AppStorage("formCheck.voice") private var voiceOn = true
    @State private var analyzer: FormAnalyzer?
    @State private var live = FormLive()
    @State private var pose: FormPose?
    @State private var aspect = 9.0 / 16
    @State private var camera = FormCamera()
    @State private var denied = false
    @State private var report: FormReport?
    @State private var voice = CoachVoice()
    @State private var saidAt = Date.distantPast
    @State private var landscapeWas = false

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .mirror }

    var body: some View {
        Group {
            if let report {
                FormReportView(report: report, exercise: exercise, onReps: onReps, onAgain: again) { dismiss() }
            } else {
                liveScreen
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(report == nil)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            landscapeWas = OrientationLock.landscapeAllowed
            OrientationLock.allowLandscape(false)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            camera.stop()
            voice.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            if landscapeWas { OrientationLock.allowLandscape(true) }
        }
        .task { await begin() }
    }

    private var liveScreen: some View {
        ZStack {
            if demo == nil && !denied {
                FormCameraPreview(session: camera.session).ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(hex: 0x2D3440), Color(hex: 0x1B1F27), Color(hex: 0x2A241D)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            FormSkeleton(pose: pose, ghost: mode == .ghost ? live.ghost : nil, aspect: aspect, warn: live.warn, bad: live.bad)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                topBar
                HStack(alignment: .top) {
                    if mode == .ghost { angleChips } else { scoreTile }
                    Spacer()
                    mode == .ghost ? AnyView(matchTile) : AnyView(repsTile)
                }
                Spacer()
                if denied { deniedCard } else if live.reps.isEmpty && !live.visible { setupCard }
                if let cue = live.cue, !denied { cueBar(cue) }
                repSquares
                Button { finish() } label: {
                    Label(live.reps.isEmpty ? "Close" : "Done · see report", systemImage: live.reps.isEmpty ? "xmark" : "chart.bar.doc.horizontal.fill")
                }
                .buttonStyle(LimeButtonStyle())
                .accessibilityIdentifier("formCheck.done")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack(spacing: 8) {
            Text(exercise.name)
                .font(Theme.label(14)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.55)))
            Spacer(minLength: 4)
            modeSwitch
            squareButton(voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill", label: voiceOn ? "Mute cues" : "Say cues") { voiceOn.toggle() }
            if demo == nil && !denied {
                squareButton("arrow.triangle.2.circlepath.camera.fill", label: "Switch camera") {
                    front.toggle()
                    camera.start(front: front)
                }
            }
            squareButton("xmark", label: "Close") { dismiss() }
        }
        .foregroundStyle(.white)
        .padding(.top, 6)
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach([Mode.mirror, .ghost], id: \.rawValue) { m in
                Button { modeRaw = m.rawValue } label: {
                    Image(systemName: m == .mirror ? "figure.stand" : "figure.stand.line.dotted.figure.stand")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(mode == m ? Theme.ink : .white)
                        .frame(width: 36, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(mode == m ? Theme.lime : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m == .mirror ? "Live mirror" : "Ghost of the right position")
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.black.opacity(0.55)))
    }

    private func squareButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .black))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func tile(_ title: String, _ value: String, colors: [Color], ink: Color = .white, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(title).font(Theme.label(10)).tracking(1.4).opacity(0.85)
            Text(value).font(Theme.display(40)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(ink)
        .frame(width: 104, alignment: trailing ? .trailing : .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }

    private var scoreTile: some View {
        tile("FORM", live.score.map(String.init) ?? "–", colors: FormColors.tone(live.score.map { s -> FormCue.Tone in s >= 85 ? .good : s >= 70 ? .warn : .bad } ?? .info))
    }

    private var repsTile: some View {
        tile("REPS", "\(live.reps.count)", colors: [Color(hex: 0x7B4DFF), Color(hex: 0xE04FE0)], trailing: true)
            .accessibilityIdentifier("formCheck.reps")
    }

    private var matchTile: some View {
        tile("MATCH", live.match.map { "\($0)%" } ?? "–", colors: [Theme.lime, Color(hex: 0x3BE3C4)], ink: Theme.ink, trailing: true)
    }

    private var angleChips: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(live.checks, id: \.joint) { c in
                let color = c.status == .good ? FormColors.good : c.status == .close ? FormColors.warn : FormColors.bad
                HStack(spacing: 4) {
                    Text(c.label)
                    Image(systemName: c.status == .good ? "checkmark" : "arrow.right")
                    if c.status != .good { Text("\(c.target)°") }
                }
                .font(Theme.label(12))
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.6)))
            }
            Text("REPS \(live.reps.count)")
                .font(Theme.label(12)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.6)))
        }
    }

    private func cueBar(_ cue: FormCue) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cue.symbol)
                .font(.system(size: 17, weight: .black))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.28)))
            Text(cue.text).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(cue.tone == .warn ? Theme.ink : .white)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: FormColors.tone(cue.tone), startPoint: .leading, endPoint: .trailing)))
        .animation(.snappy, value: cue.text)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// One square per rep: score (mirror) or match % (ghost); empty slots up to the set's reps.
    private var repSquares: some View {
        HStack(spacing: 5) {
            ForEach(live.reps, id: \.number) { r in
                let v = mode == .ghost ? r.match : r.score
                Text(mode == .ghost ? "\(r.match)" : "\(r.number)")
                    .font(Theme.label(12)).monospacedDigit()
                    .foregroundStyle(FormColors.score(v) == FormColors.warn ? Theme.ink : .white)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(FormColors.score(v)))
            }
            ForEach(0..<max(0, 8 - live.reps.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.12)).frame(maxWidth: .infinity, minHeight: 30)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(live.reps.isEmpty ? "No reps yet" : "Rep scores: " + live.reps.map { "\($0.score)" }.joined(separator: ", "))
    }

    private var setupCard: some View {
        let side = analyzer?.model.view == .side
        return HStack(spacing: 12) {
            Image(systemName: side ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                .font(.system(size: 22, weight: .black))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(side ? "Phone to your side" : "Phone in front of you").font(Theme.display(18))
                Text("Prop it 2–3 m away at hip height, your whole body in frame. Only your joints are read, on this iPhone.")
                    .font(.caption.weight(.semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x5B6BFF), Color(hex: 0xA64DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera is off for MonkeyWorkout").font(Theme.display(18))
            Text("Form check needs the camera to see your joints. Nothing is recorded or sent.").font(.caption.weight(.semibold))
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

    // MARK: Flow

    private func begin() async {
        guard analyzer == nil else { return }
        analyzer = FormAnalyzer(exercise: exercise)
        guard let model = analyzer?.model else { return }
        if let demo {
            if demo == .ghost { modeRaw = Mode.ghost.rawValue }
            if demo == .live { modeRaw = Mode.mirror.rawValue }
            await playDemo(model, demo)
            return
        }
        guard await FormCamera.allowed() else {
            denied = true
            return
        }
        camera.onPose = { p, t, a in feed(p, at: t, aspect: a) }
        camera.start(front: front)
    }

    private func feed(_ p: FormPose?, at t: Double, aspect a: Double) {
        guard report == nil, var an = analyzer else { return }
        aspect = a
        let before = an.reps.count
        live = an.add(p, at: t)
        analyzer = an
        pose = p
        if an.reps.count > before, let rep = an.reps.last { repDone(rep, model: an.model) }
    }

    /// Haptic each rep; the cue said aloud when the rep had a fault (one line every 3 s at most).
    private func repDone(_ rep: FormRep, model: FormModel) {
        UIImpactFeedbackGenerator(style: rep.faults.isEmpty ? .light : .heavy).impactOccurred()
        guard voiceOn, demo == nil, Date().timeIntervalSince(saidAt) > 3,
              let f = rep.faults.max(by: { $0.penalty < $1.penalty }) else { return }
        saidAt = .now
        voice.speak(model.cue(f).text, style: CoachPref.style)
    }

    private func finish() {
        guard let an = analyzer, !an.reps.isEmpty else {
            dismiss()
            return
        }
        camera.stop()
        voice.stop()
        let r = an.report()
        if demo == nil { FormReportStore.shared.add(r) }
        withAnimation(.snappy) { report = r }
    }

    private func again() {
        report = nil
        live = FormLive()
        pose = nil
        analyzer = FormAnalyzer(exercise: exercise)
        if demo == nil && !denied { camera.start(front: front) }
    }

    /// The made-up member: three reps done at once, then the set plays on in real time.
    private func playDemo(_ model: FormModel, _ demo: FormCheckDemo) async {
        aspect = 9.0 / 16
        let frames = FormDemo.frames(model, reps: 8, shallow: [3], lean: [2, 6, 7])
        if demo == .report {
            var an = FormAnalyzer(model: model)
            for (t, p) in frames { an.add(p, at: t) }
            analyzer = an
            report = an.report()
            return
        }
        let head = 7.9
        for (t, p) in frames where t < head { feed(p, at: t, aspect: aspect) }
        for (t, p) in frames where t >= head {
            try? await Task.sleep(for: .milliseconds(33))
            guard !Task.isCancelled else { return }
            feed(p, at: t, aspect: aspect)
        }
    }
}

// MARK: - Report (C)

struct FormReportView: View {
    let report: FormReport
    let exercise: Exercise
    var onReps: ((Int) -> Void)?
    var onAgain: (() -> Void)?
    let onClose: () -> Void

    @State private var shown: Int?
    @State private var replayStart = Date()
    @State private var ask: AskCoachRequest?
    @State private var gate: ProGate?

    private var replayRep: Int? { shown ?? report.worst ?? report.reps.last?.number }

    private func frames(_ rep: Int?) -> [FormPose] {
        guard let rep else { return [] }
        if let f = report.replays[rep], !f.isEmpty { return f }
        return rep == report.worst ? report.worstReplay : []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    Text("Rep by rep").eyebrow()
                    repTiles
                    replayBox
                    if !report.fixes.isEmpty {
                        Text("Fix next set").eyebrow()
                        ForEach(report.fixes, id: \.fault) { fixTile($0) }
                    } else {
                        cleanTile
                    }
                    buttons
                    Text("Scored on your joints only, on this iPhone. Kept in this exercise's history on this device.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Form report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { onClose() } }
            .proPaywall($gate)
            .sheet(item: $ask) { r in CoachChatView(ask: r).remotePaused(.askCoach) }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 22, weight: .black))
                .frame(width: 50, height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.25)))
            VStack(alignment: .leading, spacing: 3) {
                Text("FORM REPORT").font(Theme.label(10)).tracking(1.6).opacity(0.85)
                Text("\(exercise.name) · \(report.reps.count) reps").font(Theme.display(19)).lineLimit(2).minimumScaleFactor(0.7)
                Text(subtitle).font(.caption.weight(.bold)).opacity(0.9)
            }
            Spacer(minLength: 4)
            Text("\(report.score)").font(Theme.display(58)).monospacedDigit()
                .accessibilityLabel("Score \(report.score) out of 100")
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x7B4DFF), Color(hex: 0xE04FE0)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var subtitle: String {
        var parts: [String] = []
        if let b = report.best { parts.append("Best rep \(b)") }
        if let f = report.fadeFrom { parts.append("faded from rep \(f)") }
        parts.append("match \(report.match)%")
        return parts.joined(separator: " · ")
    }

    private var repTiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
            ForEach(report.reps, id: \.number) { r in
                Button {
                    shown = r.number
                    replayStart = .now
                } label: {
                    Text("\(r.number)")
                        .font(Theme.label(13)).monospacedDigit()
                        .foregroundStyle(FormColors.score(r.score) == FormColors.warn ? Theme.ink : .white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(FormColors.score(r.score)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: replayRep == r.number ? 2.5 : 0))
                }
                .buttonStyle(.plain)
                .disabled(frames(r.number).isEmpty)
                .accessibilityLabel("Rep \(r.number), score \(r.score)" + (r.faults.isEmpty ? "" : ", " + r.faults.map(\.title).joined(separator: ", ")))
            }
        }
    }

    @ViewBuilder private var replayBox: some View {
        let f = frames(replayRep)
        if let n = replayRep, !f.isEmpty, let rep = report.reps.first(where: { $0.number == n }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(rep.number == report.worst ? "Worst rep · \(n)" : "Rep \(n)").eyebrow()
                ZStack(alignment: .topTrailing) {
                    TimelineView(.animation) { ctx in
                        let i = Int(max(0, ctx.date.timeIntervalSince(replayStart)) * 15) % f.count
                        FormSkeleton(pose: Self.fitted(f[i], all: f), ghost: nil, aspect: 1.6,
                                     bad: Set(rep.faults.flatMap(Self.joints)), lineScale: 0.8)
                    }
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(rep.faults, id: \.self) { fault in
                            Text(Self.note(fault, rep)).font(Theme.label(12))
                                .foregroundStyle(fault.penalty >= 20 ? FormColors.bad : FormColors.warn)
                        }
                        if rep.faults.isEmpty { Text("Clean rep").font(Theme.label(12)).foregroundStyle(FormColors.good) }
                        Text("tap a rep to replay it").font(.caption2).foregroundStyle(Theme.muted)
                    }
                    .padding(10)
                }
                .frame(height: 170)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2D3440), Color(hex: 0x1B1F27)], startPoint: .top, endPoint: .bottom)))
                .contentShape(Rectangle())
                .onTapGesture { replayStart = .now }
            }
        }
    }

    /// The replay's frames moved to the left of a wide box, feet near the bottom, same scale for every frame.
    static func fitted(_ p: FormPose, all: [FormPose]) -> FormPose {
        let pts = all.flatMap { $0.points.values }
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(), let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return p }
        let s = 0.82 / max(0.05, max(maxY - minY, (maxX - minX) / 1.0))
        return FormPose(p.points.mapValues { q in SIMD2(0.12 + (q.x - minX) * s, 0.08 + (q.y - minY) * s) })
    }

    static func joints(_ f: FormFault) -> [FormJoint] {
        switch f {
        case .kneesIn: [.leftKnee, .rightKnee]
        case .torsoLean: [.leftShoulder, .rightShoulder, .neck]
        case .hipsSag: [.leftHip, .rightHip]
        case .shallow, .noLockout: [.leftHip, .rightHip, .leftKnee, .rightKnee]
        case .uneven: [.leftElbow, .rightElbow, .leftKnee, .rightKnee]
        case .tooFast: []
        }
    }

    static func note(_ f: FormFault, _ r: FormRep) -> String {
        switch f {
        case .torsoLean: "torso +\(Int((r.torsoExtra ?? 0).rounded()))°"
        case .kneesIn: "knees −\(Int(((1 - (r.kneeWidth ?? 1)) * 100).rounded()))%"
        case .shallow: "depth \(Int((r.depth * 100).rounded()))%"
        case .hipsSag: "hips sag"
        case .uneven: "sides \(Int((r.sideGap ?? 0).rounded()))° apart"
        case .tooFast: String(format: "%.1f s rep", r.seconds)
        case .noLockout: "not finished"
        }
    }

    private func fixTile(_ fix: FormFix) -> some View {
        let colors: [Color] = fix.fault.penalty >= 20 ? FormColors.tone(.bad) : FormColors.tone(.warn)
        let ink: Color = fix.fault.penalty >= 20 ? .white : Theme.ink
        return HStack(spacing: 10) {
            Image(systemName: fix.fault.symbol)
                .font(.system(size: 15, weight: .black))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.25)))
            VStack(alignment: .leading, spacing: 1) {
                Text(fix.fault.title + " " + FormReport.repsText(fix.reps)).font(Theme.label(14)).lineLimit(2)
                Text(cue(fix.fault)).font(.caption.weight(.bold)).opacity(0.9)
            }
            Spacer(minLength: 4)
            Text(fix.detail).font(Theme.display(20)).monospacedDigit()
        }
        .foregroundStyle(ink)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
    }

    private func cue(_ f: FormFault) -> String {
        FormModel(exercise: exercise)?.cue(f).text ?? f.title
    }

    private var cleanTile: some View {
        Label("Clean set: nothing to fix", systemImage: "checkmark.seal.fill")
            .font(Theme.label(15))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: FormColors.tone(.good), startPoint: .leading, endPoint: .trailing)))
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            if let onReps {
                Button {
                    onReps(report.reps.count)
                    onClose()
                } label: { Label("Use \(report.reps.count) reps for this set", systemImage: "checkmark") }
                    .buttonStyle(LimeButtonStyle())
            }
            HStack(spacing: 8) {
                if let onAgain {
                    smallButton("Film again", "video.fill", fill: .white.opacity(0.12)) { onAgain() }
                }
                smallButton("Ask Coach", "sparkles", fill: Color(hex: 0x9B4DFF)) {
                    ProStore.shared.run(.askCoach, $gate) { ask = AskCoachRequest(focus: focus, question: question) }
                }
            }
        }
    }

    private func smallButton(_ title: String, _ symbol: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.label(14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
    }

    private var focus: CoachFocus {
        CoachFocus(screen: "exercise", title: exercise.name, detail: "form check score \(report.score)/100, \(report.reps.count) reps")
    }

    /// What the camera saw, for Coach.
    private var question: String {
        let fixes = report.fixes.map { "\($0.fault.title.lowercased()) on \(FormReport.repsText($0.reps)) (\($0.detail))" }
        let seen = fixes.isEmpty ? "no faults" : fixes.joined(separator: "; ")
        return "My form check on \(exercise.name): \(report.score)/100 over \(report.reps.count) reps, \(seen). How do I fix it?"
    }
}

// MARK: - History

/// Form reports on this device, newest first (joints of the worst rep only, no pictures).
@MainActor @Observable final class FormReportStore {
    static let shared = FormReportStore()
    static let keep = 60

    private(set) var reports: [FormReport] = []

    private var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("form-reports.json")
    }

    init() {
        if let url, let data = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([FormReport].self, from: data) { reports = r }
    }

    func add(_ r: FormReport) {
        reports.removeAll { $0.id == r.id }
        reports.insert(r, at: 0)
        reports = Array(reports.prefix(Self.keep))
        save()
    }

    func remove(_ id: UUID) {
        reports.removeAll { $0.id == id }
        save()
    }

    func reports(for exerciseId: String) -> [FormReport] { reports.filter { $0.exerciseId == exerciseId } }

    /// Sign-out and account switch.
    func wipe() {
        reports = []
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func save() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(reports).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - Ways in

/// "Check my form" on the exercise page (Explore).
struct FormCheckLink: View {
    let exercise: Exercise
    @State private var open = false

    var body: some View {
        if FormModel.supports(exercise) {
            Button { open = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.title3.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Check my form").font(Theme.display(19))
                        Text("Camera counts reps, checks range and position · \(exercise.position?.view == .side ? "side view" : "front view")")
                            .font(.caption.weight(.semibold)).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.body.weight(.heavy))
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(
                    LinearGradient(colors: [Color(hex: 0xFF4D6D), Color(hex: 0xFF9A3C)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("form-check")
            .fullScreenCover(isPresented: $open) { FormCheckView(exercise: exercise) }
        }
    }
}

/// Last form checks of the exercise: latest score and the trend, tap for the report.
struct FormHistoryCard: View {
    let exerciseId: String
    @State private var store = FormReportStore.shared
    @State private var opened: FormReport?

    var body: some View {
        let list = store.reports(for: exerciseId)
        if let last = list.first {
            Button { opened = last } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Form checks").eyebrow()
                        Spacer()
                        Text(last.date.formatted(date: .abbreviated, time: .omitted)).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        Text("\(last.score)").font(Theme.display(44)).monospacedDigit().foregroundStyle(FormColors.score(last.score))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(last.fixes.first.map { "Fix: \($0.fault.title.lowercased())" } ?? "Clean set").font(Theme.label(14))
                            Text("\(last.reps.count) reps · match \(last.match)%").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(list.prefix(6).reversed()), id: \.id) { r in
                                RoundedRectangle(cornerRadius: 3).fill(FormColors.score(r.score))
                                    .frame(width: 10, height: max(6, Double(r.score) * 0.4))
                            }
                        }
                    }
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Last form check \(last.score) out of 100")
            .sheet(item: $opened) { r in
                FormReportView(report: r, exercise: Exercise.get(r.exerciseId)) { opened = nil }
            }
        }
    }
}

/// Coach's "Watch my form" tile: the exercise on screen, or a pick from today's workout and the catalog.
struct FormCheckCoachTile: View {
    var exercise: Exercise?
    @Binding var picking: Bool
    @Binding var filming: Exercise?

    var body: some View {
        Button { if let exercise { filming = exercise } else { picking = true } } label: {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watch my form").font(Theme.display(17))
                    Text(exercise.map { "Camera check · \($0.name)" } ?? "Camera check · pick an exercise").font(.caption.weight(.semibold)).opacity(0.9)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.body.weight(.heavy))
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
                LinearGradient(colors: [Color(hex: 0x7B4DFF), Color(hex: 0xE04FE0)], startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
        .padding(.leading, 42)
        .accessibilityIdentifier("askCoach.formCheck")
    }

    /// A short "check my form", "watch my form", "film me"… (not a question about a report).
    static func asks(_ text: String) -> Bool {
        let t = text.lowercased()
        guard t.count <= 60 else { return false }
        return ["check my form", "watch my form", "film my form", "look at my form", "analyse my form", "analyze my form",
                "record my form", "film me"].contains { t.contains($0) }
    }
}

/// Which exercise to film: today's workout first, then every exercise the camera can check.
struct FormCheckPicker: View {
    let onPick: (Exercise) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let today = (model.todaySession?.blocks.flatMap(\.items).map(\.exerciseId) ?? [])
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .compactMap { Exercise.find($0) }.filter(FormModel.supports)
        let all = Exercise.search(query).filter(FormModel.supports)
        NavigationStack {
            List {
                if query.isEmpty && !today.isEmpty {
                    Section("In today's workout") { ForEach(today) { row($0) } }
                }
                Section(query.isEmpty ? "All exercises" : "Results") { ForEach(all) { row($0) } }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .themedForm()
            .navigationTitle("Watch my form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ e: Exercise) -> some View {
        Button {
            dismiss()
            onPick(e)
        } label: {
            HStack(spacing: 12) {
                ExerciseThumbnail(exercise: e, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(.body.weight(.bold))
                    Text(e.position?.view == .side ? "Side view" : "Front view").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "video.fill").foregroundStyle(Theme.lime)
            }
        }
        .buttonStyle(.plain)
    }
}
