import SwiftUI
import UIKit
import WorkoutEngine

/// Exercise picture: the app's own illustration (#170, bundled PNG drawn on the category gradient), or a
/// custom exercise's photo / pose drawing. The gradient + icon is the placeholder without media.
/// Shows one still frame: 0 = start, frame count / 2 = middle, last = end position (in-betweens
/// between them, #229). Never animates by itself.
struct ExerciseImage: View {
    let exercise: Exercise
    var frame = 0
    var contentMode: ContentMode = .fill

    /// The user's own exercise (#52): photo or pose drawing from its record.
    private var custom: CustomExercise? {
        CustomExercise.isCustom(exercise.id) ? CustomExercises.shared.record(exercise.id) : nil
    }

    /// Frames this exercise has (catalog art: 17–49 with the HD pack, #256, else the 3 bundled light frames, #932, #944;
    /// 1–2 for a custom exercise; 0 without media).
    static func frameCount(_ e: Exercise) -> Int {
        if CustomExercise.isCustom(e.id) { return CustomExercises.shared.record(e.id)?.frameCount ?? 0 }
        guard e.hasIllustration else { return 0 }
        return HDAnimations.shared.has(e.id) ? ExerciseIllustrations.frameCount(of: e.id) : ExerciseIllustrations.liteFrameCount
    }

    /// Has a picture: catalog illustration or a custom exercise's photo/pose.
    static func hasMedia(_ e: Exercise) -> Bool { frameCount(e) > 0 }

    private var image: UIImage? {
        guard frame >= 0, frame < Self.frameCount(exercise) else { return nil }
        return IllustrationImages.image(exercise.id, frame: frame, hd: HDAnimations.shared.has(exercise.id))
    }

    var body: some View {
        // The placeholder sets the size; the picture is laid over it so `.fill` never grows the view.
        placeholder
            .overlay {
                if let custom {
                    CustomExerciseArt(record: custom, frame: frame, contentMode: contentMode)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipped()
            // Decorative: the exercise name is always shown next to it.
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(exercise.category.gradient)
                if !exercise.hasIllustration && !(custom?.hasArt ?? false) {
                    Image(systemName: exercise.category.symbol)
                        .font(.system(size: max(12, min(geo.size.width, geo.size.height) * 0.36), weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Illustration frames decoded ahead of playback: the movement swaps frames many times a second, so the frames of the
/// exercise on show are decoded once in the background instead of on the main thread as they first draw.
enum IllustrationImages {
    /// About the frames of the exercise on show and the next one (#720: the player decodes the next move ahead);
    /// the system also empties it under memory pressure.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 150 * 1024 * 1024
        return c
    }()

    private static func key(_ exerciseId: String, _ frame: Int, hd: Bool) -> NSString {
        "\(hd ? "hd-" : "")\(ExerciseIllustrations.assetName(exerciseId, frame: frame))" as NSString
    }

    /// Frame from the HD pack (#932) or the bundled light frame, undecoded.
    private static func load(_ exerciseId: String, frame: Int, hd: Bool) -> UIImage? {
        hd ? HDFrames.image(exerciseId, frame: frame) : UIImage(named: ExerciseIllustrations.assetName(exerciseId, frame: frame))
    }

    /// The decoded frame when ready, else loaded as before (decoded as it draws). A missing HD frame falls back to
    /// the light frame at the same point of the movement.
    static func image(_ exerciseId: String, frame: Int, hd: Bool) -> UIImage? {
        if let decoded = cache.object(forKey: key(exerciseId, frame, hd: hd)) { return decoded }
        if hd, let image = load(exerciseId, frame: frame, hd: true) { return image }
        let n = ExerciseIllustrations.frameCount(of: exerciseId)
        let lite = hd ? (ExerciseIllustrations.liteFrames(n).lastIndex { $0 <= frame } ?? 0) : frame
        return load(exerciseId, frame: lite, hd: false)
    }

    /// Decodes the exercise's illustration frames (`frames` of them, HD or light) in the background.
    static func prepare(_ exerciseId: String, frames: Int, hd: Bool) {
        guard frames > 0 else { return }
        Task.detached(priority: .userInitiated) {
            for f in 0..<frames where IllustrationImages.cache.object(forKey: key(exerciseId, f, hd: hd)) == nil {
                guard let decoded = load(exerciseId, frame: f, hd: hd)?.preparingForDisplay() else { continue }
                let cost = Int(decoded.size.width * decoded.scale * decoded.size.height * decoded.scale) * 4
                IllustrationImages.cache.setObject(decoded, forKey: key(exerciseId, f, hd: hd), cost: cost)
            }
        }
    }

    /// The catalog exercise's frames as shown now (HD or light).
    @MainActor static func prepare(_ exerciseId: String) {
        guard ExerciseIllustrations.ids.contains(exerciseId) else { return }
        let hd = HDAnimations.shared.has(exerciseId)
        prepare(exerciseId, frames: hd ? ExerciseIllustrations.frameCount(of: exerciseId) : ExerciseIllustrations.liteFrameCount, hd: hd)
    }

    /// HD pack removed: its decoded frames go too.
    static func forgetHD() { cache.removeAllObjects() }
}

/// The movement, played a few times then at rest (never an endless loop), #188 / #229. Catalog art plays from its
/// 60 fps clip (#944, `MotionClipPlayer`; its start / middle / end frames at rest), at the exercise's
/// tempo: lifting work 1 s, the return 2 s (power: fast work), other categories evenly. Playback is one continuous
/// position on a display-linked timeline, the next frame blended over the lower one (#236). While playing, a chip
/// shows the half being played (e.g. "UP 1s", green for the working half, yellow for the return) with a bar
/// filling over it and the rep; a dotted line traces the path of the bar / hand / foot with a dot riding it.
/// Reduce Motion: no auto-play and no clip, a tap still steps through the frames without fades. Custom exercises (1–2
/// frames) play the same way without path or tempo. Shared by the exercise page and the workout player.
struct ExerciseMotionView: View {
    let exercise: Exercise
    var contentMode: ContentMode = .fit
    /// Change to replay from outside (e.g. when the player moves to a new set).
    var playTrigger = 0
    /// Frame shown while not playing (the exercise page lets you pick a key frame).
    var restingFrame = 0
    /// Start → end → start cycles played on its own each time a new exercise shows, then it rests on
    /// `restingFrame` (never an endless loop). 0 = only on tap. Reduce Motion turns auto-play off.
    var autoPlayCycles = Self.autoPlayCycles
    /// HIIT (#719): plays for about this many seconds (the interval) instead of `autoPlayCycles` reps, and each
    /// new `playTrigger` does too.
    var playFor: Double? = nil
    /// Tempo multiplier: HIIT moves are quicker than lifting reps (no tempo chip then).
    var speed = 1.0

    /// Default number of automatic cycles in the player and on the exercise page.
    static let autoPlayCycles = 3
    /// Cycles played by a tap on the picture ("Play movement").
    static let tapCycles = 2
    /// Pause on the end pose and back on the start pose between reps.
    static let hold = 0.35

    /// Working half: green; return: yellow.
    static let effortColor = Color(red: 0.0, green: 0.9, blue: 0.63)
    static let returnColor = Color(red: 1.0, green: 0.9, blue: 0.0)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The running play and when it started; nil = resting.
    @State private var playback: MotionPlayback?
    @State private var started = Date.distantPast
    /// Bumped for every play request so a tap restarts a running play.
    @State private var run = 0
    /// The exercise's 60 fps clip (#944), loaded as it shows; nil = the movement plays from its frames.
    @State private var clip: MotionClipPlayer?

    /// Still frames (start, middle, end of catalog art without the HD pack).
    private var frames: Int { ExerciseImage.frameCount(exercise) }
    private var canPlay: Bool { frames > 1 }
    /// The clip plays the movement, except with Reduce Motion (whole frames then).
    private var playingClip: MotionClipPlayer? { reduceMotion ? nil : clip }
    /// Frames a play's position counts: with the clip, the exercise's HD frames (path and tempo are drawn on them).
    private var playFrames: Int {
        playingClip != nil ? max(ExerciseIllustrations.frameCount(of: exercise.id), 2) : frames
    }
    /// The still frame shown at rest, as a play position.
    private var restPosition: Double {
        let n = ExerciseIllustrations.frameCount(of: exercise.id)
        guard playingClip != nil, frames != n else { return Double(restingFrame) }
        let lite = ExerciseIllustrations.liteFrames(n)
        return Double(lite[min(max(restingFrame, 0), lite.count - 1)])
    }
    /// Path and phase labels; only for catalog art drawn with in-betweens (the light frames: their points, #932).
    private var motion: ExerciseMotion? {
        guard exercise.hasIllustration, let m = exercise.motion else { return nil }
        let n = ExerciseIllustrations.frameCount(of: exercise.id)
        return playFrames == n ? m : m.sampled(ExerciseIllustrations.liteFrames(n))
    }
    private var phases: (ExerciseMotion.Phase, ExerciseMotion.Phase)? { motion?.phases(exercise.category) }

    var body: some View {
        // One continuous frame position drawn on the display's clock (#236): no per-step state changes,
        // so nothing can flash between frames.
        TimelineView(.animation(paused: playback == nil)) { context in
            let time = context.date.timeIntervalSince(started)
            picture(playback?.state(at: time), time: time)
        }
        .contentShape(Rectangle())
        .onTapGesture { start(Self.tapCycles) }
        // A new exercise (first appearance, or the player moving on): play the movement a few times.
        .task(id: exercise.id) {
            playback = nil
            clip?.stop()
            clip = nil
            // Frames decoded before they are needed mid-play.
            if canPlay { IllustrationImages.prepare(exercise.id) }
            if exercise.hasIllustration, let url = MotionClips.url(exercise.id) {
                clip = await MotionClipPlayer.load(url)
            }
            guard Self.autoPlays(cycles: autoPlayCycles, frames: frames, reduceMotion: reduceMotion) else { return }
            start(autoPlayCycles)
        }
        // Back to rest once the play has run its course.
        .task(id: run) {
            guard let playback else { return }
            try? await Task.sleep(for: .seconds(playback.duration))
            if !Task.isCancelled {
                self.playback = nil
                clip?.stop()
            }
        }
        .onDisappear { clip?.stop() }
        // The player moving on replays it, but never with Reduce Motion (#719): only a tap plays then.
        .onChange(of: playTrigger) { _, _ in
            guard !reduceMotion else { return }
            start(playFor != nil ? autoPlayCycles : Self.tapCycles)
        }
        // Picking a frame on the exercise page stops a running play and shows that frame.
        .onChange(of: restingFrame) { _, _ in
            playback = nil
            clip?.stop()
            run += 1
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name), movement from start to end position")
        .accessibilityValue(playback != nil ? "Playing" : "")
        .accessibilityAddTraits(canPlay ? .isButton : [])
        .accessibilityHint(canPlay ? "Shows the movement again" : "")
    }

    /// The frames at `state`'s position (or the resting frame): the lower frame fully opaque, the next one
    /// switched in quickly over it (#241: a short dissolve, no long double-exposed poses). Only those two are drawn
    /// (every other frame would be invisible); both always stay in the stack, and the exercise's frames are decoded
    /// ahead (`IllustrationImages`), so nothing loads mid-play. Reduce Motion: whole frames.
    /// While the clip plays (#944), its picture over the category gradient instead (the resting frame until its first
    /// picture is decoded).
    private func picture(_ state: MotionPlayback.State?, time: Double) -> some View {
        let raw = state?.position ?? restPosition
        let position = reduceMotion ? raw.rounded() : raw
        let count = max(frames, 1)
        let video = state != nil ? playingClip?.image(at: time) : nil
        // Frames: the play's position; with the clip, the resting frame.
        let still = playingClip == nil ? position : Double(restingFrame)
        let (lower, upper) = MotionPlayback.blend(still, frames: count, window: MotionPlayback.switchWindow)
        return ZStack {
            if let video {
                // No frame: the gradient alone, the clip's picture laid over it as ExerciseImage lays out a frame.
                ExerciseImage(exercise: exercise, frame: -1, contentMode: contentMode)
                    .overlay {
                        Image(decorative: video, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .clipped()
            } else {
                ExerciseImage(exercise: exercise, frame: lower, contentMode: contentMode)
                ExerciseImage(exercise: exercise, frame: min(lower + 1, count - 1), contentMode: contentMode)
                    .opacity(lower + 1 < count ? upper : 0)
            }
            if let motion, !motion.path.isEmpty {
                MotionPathOverlay(motion: motion, position: position, contentMode: contentMode,
                                  emphasised: state != nil)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if canPlay {
                Group {
                    if let state, let phases, let playback {
                        tempoChip(state.outbound ? phases.0 : phases.1, state: state, cycles: playback.cycles)
                    } else {
                        Label(state != nil ? Self.label(Int(position.rounded()), of: playFrames) : "Play movement",
                              systemImage: state != nil ? "figure.walk.motion" : "play.fill")
                            .font(Theme.label(11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.ink.opacity(0.55)))
                    }
                }
                .padding(10)
            }
        }
    }

    /// "UP 1s" chip in the half's colour, a bar filling over the half, and the rep ("2/3"). A gait or a machine
    /// that turns (#719) shows its cycle ("STRIDE") in white, no tempo, as does a faster play (HIIT).
    private func tempoChip(_ phase: ExerciseMotion.Phase, state: MotionPlayback.State, cycles: Int) -> some View {
        let tempo = ExerciseMotion.showsTempo(exercise.category) && motion?.cyclic != true && speed == 1
        let color = !tempo ? Color.white : (phase.effort ? Self.effortColor : Self.returnColor)
        return HStack(spacing: 8) {
            Text(tempo ? phase.text : phase.label)
                .font(Theme.label(11))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(color))
                .fixedSize()
            Capsule().fill(.white.opacity(0.3))
                .frame(width: 44, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: max(6, 44 * state.halfProgress), height: 6)
                }
            Text("\(state.rep)/\(cycles)")
                .font(Theme.label(11))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize()
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.ink.opacity(0.55)))
    }

    /// Whether a new exercise starts playing on its own.
    static func autoPlays(cycles: Int, frames: Int, reduceMotion: Bool) -> Bool {
        cycles > 0 && frames > 1 && !reduceMotion
    }

    /// "Start" / "Middle" / "End" for frame `f` of `count`.
    static func label(_ f: Int, of count: Int) -> String {
        if f == 0 { return "Start" }
        return f == count - 1 ? "End" : "Middle"
    }

    /// Seconds for start → end and end → start.
    private var halfSeconds: (Double, Double) {
        if let phases { return (phases.0.seconds, phases.1.seconds) }
        return (1.2, 1.2)  // custom exercises: 2 frames, an even dissolve
    }

    private func start(_ n: Int) {
        guard canPlay, n > 0 else { return }
        let now = Date()
        // A restart mid-play glides from where the picture is now.
        let from = playback?.state(at: now.timeIntervalSince(started))?.position ?? restPosition
        let cyclic = motion?.cyclic == true
        let out = halfSeconds.0 / speed, back = halfSeconds.1 / speed, hold = Self.hold / speed
        // HIIT: as many reps as fit the interval.
        let cycles = playFor.map { max(1, Int($0 / max(0.1, out + back + (cyclic ? 0 : 2 * hold)))) } ?? n
        let play = MotionPlayback(frames: playFrames, cycles: cycles, out: out, back: back, hold: hold,
                                  from: from, rest: restPosition, cyclic: cyclic)
        playback = play
        started = now
        playingClip?.play(play.clipPieces(frames: playFrames))
        run += 1
    }
}

/// Dotted path of the point carrying the movement, with a dot riding it at the shown position (#229, #236). Mapped onto the
/// picture as `ExerciseImage` lays it out (4:3, fit or fill, centred).
private struct MotionPathOverlay: View {
    let motion: ExerciseMotion
    /// Fractional frame the dot sits at.
    let position: Double
    let contentMode: ContentMode
    /// Stronger while the movement plays.
    var emphasised: Bool

    var body: some View {
        GeometryReader { geo in
            let rect = Self.pictureRect(in: geo.size, contentMode: contentMode)
            let pts = motion.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
            ZStack {
                Path { p in p.addLines(pts) }
                    .stroke(.white.opacity(emphasised ? 0.8 : 0.45),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [0.5, 7]))
                if let p = motion.point(at: position) {
                    let dot = CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
                    Circle()
                        .fill(ExerciseMotionView.returnColor)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .frame(width: emphasised ? 14 : 10, height: emphasised ? 14 : 10)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .position(dot)
                }
            }
        }
    }

    /// Where a 4:3 picture sits in `size`.
    static func pictureRect(in size: CGSize, contentMode: ContentMode) -> CGRect {
        let aspect = 4.0 / 3.0
        guard size.width > 0, size.height > 0 else { return .zero }
        let byWidth = CGSize(width: size.width, height: size.width / aspect)
        let byHeight = CGSize(width: size.height * aspect, height: size.height)
        let fitsWidth = byWidth.height <= size.height
        let s = (contentMode == .fit) == fitsWidth ? byWidth : byHeight
        return CGRect(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2, width: s.width, height: s.height)
    }
}

/// Small rounded thumbnail for lists and cards.
struct ExerciseThumbnail: View {
    let exercise: Exercise
    var size: CGFloat = 56

    var body: some View {
        ExerciseImage(exercise: exercise)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Large picture for the exercise page and the player. Renders nothing without media.
/// `.sequence`: the picked frame large, with a Start / Middle / End strip below to pick a frame or play
/// the movement (default). `.motion`: one picture. Both play the movement a few times on their own, then on tap (`ExerciseMotionView`).
struct ExerciseImageHeader: View {
    enum Style { case sequence, motion }

    let exercise: Exercise
    var height: CGFloat = 220
    var style: Style = .sequence

    @State private var picked = 0
    @State private var replay = 0

    var body: some View {
        if ExerciseImage.hasMedia(exercise) {
            let frames = ExerciseImage.frameCount(exercise)
            VStack(spacing: 8) {
                ExerciseMotionView(exercise: exercise, playTrigger: replay, restingFrame: style == .sequence ? picked : 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke))
                if style == .sequence && frames > 1 {
                    HStack(spacing: 6) {
                        ForEach(Self.keyFrames(exercise, frames), id: \.self) { f in strip(f, of: frames) }
                    }
                }
            }
        }
    }

    /// Start / Middle / End of catalog art (its in-betweens only play), every frame of a custom exercise.
    static func keyFrames(_ e: Exercise, _ count: Int) -> [Int] {
        e.hasIllustration ? ExerciseIllustrations.keyFrames(count) : Array(0..<count)
    }

    private func strip(_ f: Int, of count: Int) -> some View {
        Button {
            picked = f
        } label: {
            ExerciseImage(exercise: exercise, frame: f)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(f == picked ? Theme.lime : Theme.stroke, lineWidth: f == picked ? 2.5 : 1))
                .overlay(alignment: .bottomLeading) {
                    Text(ExerciseMotionView.label(f, of: count).uppercased())
                        .font(Theme.label(9))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.ink.opacity(0.6)))
                        .padding(5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ExerciseMotionView.label(f, of: count)) position")
        .accessibilityAddTraits(f == picked ? .isSelected : [])
    }
}
