import Foundation

/// The post a workout was saved from (#909): platform, the clean link and the creator, credited on the workout.
public struct WorkoutSource: Codable, Hashable, Sendable {
    public var platform: String
    public var url: String
    public var author: String?

    public init(platform: String, url: String, author: String? = nil) {
        self.platform = platform
        self.url = url
        self.author = author
    }

    /// "TikTok", "Instagram", "YouTube" or the site's host.
    public var platformName: String {
        switch platform {
        case "tiktok": "TikTok"
        case "instagram": "Instagram"
        case "youtube": "YouTube"
        default: link?.host()?.replacingOccurrences(of: "www.", with: "") ?? "Web"
        }
    }

    /// "@fitwithlea · TikTok", or the platform alone.
    public var label: String { [author, platformName].compactMap { $0 }.joined(separator: " · ") }

    /// Only http(s) links open.
    public var link: URL? {
        guard let u = URL(string: url), u.scheme == "https" || u.scheme == "http" else { return nil }
        return u
    }

    var sanitized: WorkoutSource? {
        guard link != nil else { return nil }
        return WorkoutSource(platform: String(platform.prefix(16)), url: String(url.prefix(500)),
                             author: author.map { String($0.prefix(60)) })
    }
}

/// One move Coach read from a video (#909): as the post named it, the closest catalog exercise (nil = none) and
/// whether that is the same exercise or only a near one the member should check.
public struct ImportedMove: Hashable, Sendable, Identifiable {
    public enum Unit: String, Sendable { case reps, sec, min }

    public var id = UUID()
    public var said: String
    public var exerciseId: String?
    public var sets: Int
    public var reps: Int
    public var unit: Unit
    public var sure: Bool

    public init(said: String, exerciseId: String?, sets: Int, reps: Int, unit: Unit, sure: Bool) {
        self.said = said
        self.exerciseId = exerciseId?.isEmpty == true ? nil : exerciseId
        self.sets = sets
        self.reps = reps
        self.unit = unit
        self.sure = sure && self.exerciseId != nil
    }

    public var exercise: Exercise? { exerciseId.flatMap { Exercise.find($0) } }

    /// The custom-workout item: the video's sets and reps when they fit how the exercise is counted, else its defaults.
    public var item: CustomWorkout.Item? {
        guard let e = exercise else { return nil }
        var it = CustomWorkout.Item(adding: e)
        it.sets = min(max(1, sets), CustomWorkout.setsRange.upperBound)
        switch (CustomWorkout.Measure(e), unit) {
        case (.reps, .reps), (.seconds, .sec), (.minutes, .min): it.reps = reps
        case (.seconds, .min): it.reps = reps * 60
        case (.minutes, .sec): it.reps = max(1, reps / 60)
        default: break
        }
        it.reps = min(max(1, it.reps), CustomWorkout.repsRange.upperBound)
        return it
    }
}

extension CustomWorkout {
    /// A workout from the moves read from a video (#909): moves without an exercise are left out; the post is kept as
    /// its source.
    public init(importing name: String, moves: [ImportedMove], source: WorkoutSource?, createdAt: Date = Date()) {
        self.init(name: name, items: moves.compactMap(\.item), createdAt: createdAt, source: source)
    }
}
