import SwiftUI
import UIKit
import WorkoutEngine

/// Exercise picture: the app's own illustration (#170, bundled PNG drawn on the category gradient), or a
/// custom exercise's photo / pose drawing. The gradient + icon is the placeholder without media.
/// Shows one still frame: 0 = start, 1 = middle, 2 = end position. Never animates by itself.
struct ExerciseImage: View {
    let exercise: Exercise
    var frame = 0
    var contentMode: ContentMode = .fill

    /// The user's own exercise (#52): photo or pose drawing from its record.
    private var custom: CustomExercise? {
        CustomExercise.isCustom(exercise.id) ? CustomExercises.shared.record(exercise.id) : nil
    }

    /// Frames this exercise has (3 for catalog art, 1–2 for a custom exercise, 0 without media).
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

/// The movement as a smooth, one-shot sequence: shows the start frame; a tap (or `playTrigger`) dissolves
/// through the middle to the end position, holds, and returns. No endless loop. With Reduce Motion it
/// switches frames without the dissolve. Shared by the exercise page and the workout player.
struct ExerciseMotionView: View {
    let exercise: Exercise
    var contentMode: ContentMode = .fit
    /// Change to replay from outside (e.g. when the player moves to a new set).
    var playTrigger = 0
    /// Frame shown while not playing (the exercise page lets you pick one).
    var restingFrame = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int?
    @State private var playing = false

    private var frames: Int { ExerciseImage.frameCount(exercise) }
    private var canPlay: Bool { frames > 1 }
    private var current: Int { shown ?? restingFrame }

    var body: some View {
        ZStack {
            ForEach(0..<max(frames, 1), id: \.self) { f in
                ExerciseImage(exercise: exercise, frame: f, contentMode: contentMode)
                    .opacity(f <= current ? 1 : 0)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if canPlay {
                Label(playing ? Self.label(current, of: frames) : "Play movement",
                      systemImage: playing ? "figure.walk.motion" : "play.fill")
                    .font(Theme.label(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.ink.opacity(0.55)))
                    .padding(10)
                    .animation(nil, value: current)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if canPlay { playing = true } }
        .task(id: playing) {
            guard playing else { return }
            await play()
            playing = false
        }
        .onChange(of: playTrigger) { _, _ in if canPlay { playing = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name), movement from start to end position")
        .accessibilityAddTraits(canPlay ? .isButton : [])
        .accessibilityHint(canPlay ? "Shows the movement once" : "")
    }

    /// "Start" / "Middle" / "End" for frame `f` of `count`.
    static func label(_ f: Int, of count: Int) -> String {
        if f == 0 { return "Start" }
        return f == count - 1 ? "End" : "Middle"
    }

    @MainActor
    private func play() async {
        let dissolve: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.7)
        let last = frames - 1
        // Start → … → end, hold, then back to start: twice, then rest.
        let path = Array(0...last) + Array((0..<last).reversed())
        for _ in 0..<2 {
            for (i, f) in path.enumerated() where i > 0 || f != current {
                try? await Task.sleep(for: .seconds(f == last ? 0.9 : (f == 0 ? 0.6 : 0.45)))
                guard !Task.isCancelled else { break }
                withAnimation(dissolve) { shown = f }
            }
        }
        try? await Task.sleep(for: .seconds(0.4))
        withAnimation(dissolve) { shown = nil }
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
/// the movement (default). `.motion`: one picture, tap to play the movement once (`ExerciseMotionView`).
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
                        ForEach(0..<frames, id: \.self) { f in strip(f, of: frames) }
                    }
                }
            }
        }
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
