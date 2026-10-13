import SwiftUI
import UIKit
import WorkoutEngine

/// Exercise picture: the app's own illustration (#170, bundled PNG drawn on the category gradient), or a
/// custom exercise's photo / pose drawing. The gradient + icon is the placeholder without media.
/// Shows one still frame: 0 = start, `ExerciseIllustrations.middleFrame` = middle, last = end position (in-betweens
/// between them, #229). Never animates by itself.
struct ExerciseImage: View {
    let exercise: Exercise
    var frame = 0
    var contentMode: ContentMode = .fill

    /// The user's own exercise (#52): photo or pose drawing from its record.
    private var custom: CustomExercise? {
        CustomExercise.isCustom(exercise.id) ? CustomExercises.shared.record(exercise.id) : nil
    }

    /// Frames this exercise has (`ExerciseIllustrations.frameCount` for catalog art, 1–2 for a custom exercise, 0 without media).
    static func frameCount(_ e: Exercise) -> Int {
        if CustomExercise.isCustom(e.id) { return CustomExercises.shared.record(e.id)?.frameCount ?? 0 }
        return e.illustrationAssets.count
    }

    /// Has a picture: catalog illustration or a custom exercise's photo/pose.
    static func hasMedia(_ e: Exercise) -> Bool { frameCount(e) > 0 }

    private var image: UIImage? {
        let names = exercise.illustrationAssets
        return names.indices.contains(frame) ? UIImage(named: names[frame]) : nil
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

/// The movement, played a few times then at rest (never an endless loop), #188 / #229. Catalog art has 9 frames
/// (start, eased in-betweens, end); played at the exercise's
/// tempo: lifting work 1 s, the return 2 s (power: fast work), other categories evenly. Playback is one continuous
/// position on a display-linked timeline, the next frame blended over the lower one (#236). While playing, a chip
/// shows the half being played (e.g. "UP 1s", green for the working half, yellow for the return) with a bar
/// filling over it and the rep; a dotted line traces the path of the bar / hand / foot with a dot riding it.
/// Reduce Motion: no auto-play, a tap still steps through the frames without fades. Custom exercises (1–2
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

    private var frames: Int { ExerciseImage.frameCount(exercise) }
    private var canPlay: Bool { frames > 1 }
    /// Path and phase labels; only for catalog art drawn with in-betweens.
    private var motion: ExerciseMotion? {
        frames == ExerciseIllustrations.frameCount ? exercise.motion : nil
    }
    private var phases: (ExerciseMotion.Phase, ExerciseMotion.Phase)? { motion?.phases(exercise.category) }

    var body: some View {
        // One continuous frame position drawn on the display's clock (#236): no per-step state changes,
        // so nothing can flash between frames.
        TimelineView(.animation(paused: playback == nil)) { context in
            let state = playback?.state(at: context.date.timeIntervalSince(started))
            picture(state)
        }
        .contentShape(Rectangle())
        .onTapGesture { start(Self.tapCycles) }
        // A new exercise (first appearance, or the player moving on): play the movement a few times.
        .task(id: exercise.id) {
            playback = nil
            guard Self.autoPlays(cycles: autoPlayCycles, frames: frames, reduceMotion: reduceMotion) else { return }
            start(autoPlayCycles)
        }
        // Back to rest once the play has run its course.
        .task(id: run) {
            guard let playback else { return }
            try? await Task.sleep(for: .seconds(playback.duration))
            if !Task.isCancelled { self.playback = nil }
        }
        .onChange(of: playTrigger) { _, _ in start(Self.tapCycles) }
        // Picking a frame on the exercise page stops a running play and shows that frame.
        .onChange(of: restingFrame) { _, _ in
            playback = nil
            run += 1
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name), movement from start to end position")
        .accessibilityValue(playback != nil ? "Playing" : "")
        .accessibilityAddTraits(canPlay ? .isButton : [])
        .accessibilityHint(canPlay ? "Shows the movement again" : "")
    }

    /// The frames at `state`'s position (or the resting frame): the lower frame fully opaque, the next one
    /// switched in quickly over it (#241: a short dissolve, no long double-exposed poses). Every frame stays in the stack so none is ever loaded mid-play. Reduce Motion: whole frames.
    private func picture(_ state: MotionPlayback.State?) -> some View {
        let raw = state?.position ?? Double(restingFrame)
        let position = reduceMotion ? raw.rounded() : raw
        let (lower, upper) = MotionPlayback.blend(position, frames: max(frames, 1), window: MotionPlayback.switchWindow)
        return ZStack {
            ForEach(0..<max(frames, 1), id: \.self) { f in
                ExerciseImage(exercise: exercise, frame: f, contentMode: contentMode)
                    .opacity(f == lower ? 1 : (f == lower + 1 ? upper : 0))
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
                        Label(state != nil ? Self.label(Int(position.rounded()), of: frames) : "Play movement",
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

    /// "UP 1s" chip in the half's colour, a bar filling over the half, and the rep ("2/3").
    private func tempoChip(_ phase: ExerciseMotion.Phase, state: MotionPlayback.State, cycles: Int) -> some View {
        let tempo = ExerciseMotion.showsTempo(exercise.category)
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
        let from = playback?.state(at: now.timeIntervalSince(started))?.position ?? Double(restingFrame)
        let (out, back) = halfSeconds
        playback = MotionPlayback(frames: frames, cycles: n, out: out, back: back, hold: Self.hold,
                                  from: from, rest: Double(restingFrame))
        started = now
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
                        ForEach(Self.keyFrames(frames), id: \.self) { f in strip(f, of: frames) }
                    }
                }
            }
        }
    }

    /// Start / Middle / End of catalog art (its in-betweens only play), every frame of a custom exercise.
    static func keyFrames(_ count: Int) -> [Int] {
        count == ExerciseIllustrations.frameCount ? ExerciseIllustrations.keyFrames : Array(0..<count)
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
