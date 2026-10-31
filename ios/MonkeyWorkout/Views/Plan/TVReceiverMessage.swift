import Foundation
import WorkoutEngine

/// Messages to our Chromecast receiver (#1008, backend `src/routes/cast.ts`): what `TVPlayerView` shows, as plain JSON.
/// Timers go as seconds left at sending; the TV counts them down itself, so nothing is sent every second.
enum TVReceiverMessage {
    static func state(_ live: TVLive, now: Date = Date()) -> [String: Any] {
        var m: [String: Any] = [
            "title": live.title,
            "label": live.label,
            "name": live.exercise.name,
            "category": live.category.rawValue,
            "set": live.set,
            "sets": live.sets,
            "kg": live.kg.map { LoadAdvisor.formatKg($0) } ?? "–",
            "reps": live.reps,
            "next": live.next,
            "position": live.position,
            "count": live.count,
            "progress": min(1, max(0, live.progress)),
            "elapsed": max(0, now.timeIntervalSince(live.startedAt)),
        ]
        if let end = live.restEnd { m["restLeft"] = max(0, end.timeIntervalSince(now)) }
        if let end = live.workEnd { m["workLeft"] = max(0, end.timeIntervalSince(now)) }
        if let hr = live.heartRate { m["heartRate"] = hr }
        return m
    }

    /// Plays the movement on the TV as `ExerciseMotionView` does on the phone: the same tempo and holds, cut from the
    /// exercise's 60 fps clip (`[start frame, frames, seconds]` per piece). A new exercise plays `autoPlayCycles` reps,
    /// a new set `tapCycles`. No clip (custom exercises): no `exerciseId`, the TV shows the layout without a movement.
    static func play(_ live: TVLive, newExercise: Bool = true) -> [String: Any] {
        guard let pieces = pieces(live.exercise, cycles: newExercise ? ExerciseMotionView.autoPlayCycles : ExerciseMotionView.tapCycles)
        else { return ["type": "play"] }
        return ["type": "play", "exerciseId": live.exercise.id, "pieces": pieces.map { [$0.start, $0.length, $0.duration] }]
    }

    /// The clip pieces of one play; nil without a bundled clip (the server has the same files).
    static func pieces(_ exercise: Exercise, cycles: Int) -> [MotionPlayback.ClipPiece]? {
        guard exercise.hasIllustration,
              Bundle.main.url(forResource: "motion-\(exercise.id)", withExtension: "mp4") != nil else { return nil }
        let frames = max(ExerciseIllustrations.frameCount(of: exercise.id), 2)
        let motion = exercise.motion
        let (out, back) = motion.map { m in m.phases(exercise.category) }.map { ($0.0.seconds, $0.1.seconds) } ?? (1.2, 1.2)
        let play = MotionPlayback(frames: frames, cycles: cycles, out: out, back: back, hold: ExerciseMotionView.hold,
                                  cyclic: motion?.cyclic == true)
        return play.clipPieces(frames: frames)
    }
}
