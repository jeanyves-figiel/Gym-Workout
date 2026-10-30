import Foundation

/// Film my workout (#952, design B "Show · Lift · Review" with A's sets that log themselves): the member shows the
/// weight to the camera, lifts, and the phone names the move, counts the reps, scores the form and logs each set when
/// they rack. Everything here is pure: the camera, the text reader and the clip live in the app. Moves and reps come
/// from the form check's models (`FormCheck.swift`), so only exercises with a position guide can be named.
public enum FilmWorkout {
    /// One camera frame: seconds since the camera started and the body seen (nil = nobody).
    public typealias Frame = (time: Double, pose: FormPose?)

    /// A move the frames look like.
    public struct Guess: Sendable, Hashable {
        public let exerciseId: String
        /// Share of the top guesses' scores, 0–100: high only when one move stands out.
        public let confidence: Int
        /// Reps this move's model counted on the frames.
        public let reps: Int
    }

    /// Every move the camera can name: the catalog exercises with a form check model.
    public static let models: [FormModel] = Exercise.catalog.compactMap { FormModel(exercise: $0) }

    /// Extra score for a move planned today and for one logged lately (moves that look alike: the likely one wins).
    public static let planBoost = 0.25
    public static let recentBoost = 0.12
    public static let sameMoveBoost = 0.2
    /// Reps seen before the screen names the move.
    public static let repsToGuess = 2
    /// The top guess is taken without a tap after this many reps.
    public static let repsToAccept = 4

    /// The moves `frames` look like, best first. Each model counts reps over the same frames; a move scores by how close
    /// the bottom of its reps came to its guide (70 %) and how much of its range was reached (30 %).
    /// `current`: the move done just before (whole session, #957): a set after a rest is most likely the same move.
    public static func guess(_ frames: [Frame], models: [FormModel], planned: Set<String> = [], recent: [String] = [],
                             current: String? = nil, limit: Int = 3) -> [Guess] {
        let recentSet = Set(recent.prefix(10))
        var scored: [(id: String, reps: Int, score: Double)] = []
        for m in models {
            var an = FormAnalyzer(model: m)
            for f in frames { an.add(f.pose, at: f.time) }
            let reps = an.reps
            guard !reps.isEmpty else { continue }
            let n = Double(reps.count)
            let match = Double(reps.map(\.match).reduce(0, +)) / n / 100
            let depth = reps.map { min(1, $0.depth) }.reduce(0, +) / n
            var s = match * 0.7 + depth * 0.3
            if planned.contains(m.exerciseId) { s += planBoost }
            if recentSet.contains(m.exerciseId) { s += recentBoost }
            if m.exerciseId == current { s += sameMoveBoost }
            scored.append((m.exerciseId, reps.count, s))
        }
        let top = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }.prefix(max(1, limit))
        let total = top.map(\.score).reduce(0, +)
        guard total > 0 else { return [] }
        return top.map { Guess(exerciseId: $0.id, confidence: Int(($0.score / total * 100).rounded()), reps: $0.reps) }
    }

    /// Seconds without a new rep (racked, resting, out of view) after which the set logs itself.
    public static let restAfter = 6.0

    /// The set is over: at least one rep and none for `restAfter` seconds.
    public static func setEnded(reps: Int, lastRepAt: Double?, now: Double) -> Bool {
        guard reps > 0, let lastRepAt else { return false }
        return now - lastRepAt >= restAfter
    }
}

/// A set the camera logged.
public struct FilmedSet: Sendable, Hashable, Codable {
    public var reps: Int
    public var kg: Double
    /// Form score 0–100; nil when the form check had nothing to say.
    public var form: Int?

    public init(reps: Int, kg: Double, form: Int? = nil) {
        self.reps = reps
        self.kg = kg
        self.form = form
    }
}

/// One exercise filmed: its sets in order.
public struct FilmedMove: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var exerciseId: String
    public var sets: [FilmedSet]

    public init(id: UUID = UUID(), exerciseId: String, sets: [FilmedSet] = []) {
        self.id = id
        self.exerciseId = exerciseId
        self.sets = sets
    }

    /// "3×8 · 60 kg"; mixed reps show the top set's.
    public var summary: String {
        guard let top = sets.max(by: { $0.kg != $1.kg ? $0.kg < $1.kg : $0.reps < $1.reps }) else { return "No sets" }
        let reps = Set(sets.map(\.reps)).count == 1 ? "\(top.reps)" : "\(sets.map(\.reps).max() ?? top.reps)"
        let kg = top.kg > 0 ? " · \(LoadAdvisor.formatKg(top.kg)) kg" : ""
        return "\(sets.count)×\(reps)\(kg)"
    }

    /// Average form of the sets that have one.
    public var form: Int? {
        let f = sets.compactMap(\.form)
        return f.isEmpty ? nil : Int((Double(f.reduce(0, +)) / Double(f.count)).rounded())
    }
}

/// The weight printed on a dumbbell, kettlebell, plate or machine label, read by the phone's text reader (#952).
public enum WeightReading {
    /// One piece of text the reader found and its height as a share of the frame (bigger print wins).
    public struct Seen: Sendable, Hashable {
        public let text: String
        public let size: Double
        public init(_ text: String, size: Double = 0.05) {
            self.text = text
            self.size = size
        }
    }

    public static let kgPerLb = 0.45359237

    /// The weight in kg, or nil when nothing looks like one. Pounds are converted and rounded to 0.5 kg. A number with
    /// a unit beats a bare one; then the biggest print; bare numbers must look like gym weights (0.5 steps, 1–200).
    public static func kg(from seen: [Seen]) -> Double? {
        var best: (kg: Double, score: Double)?
        for s in seen {
            for c in candidates(s.text) {
                var score = s.size * 10
                if c.unit != nil { score += 2 } else {
                    guard c.value >= 1, c.value <= 200, (c.value * 2).rounded() == c.value * 2 else { continue }
                }
                let kg = c.unit == .lb ? ((c.value * kgPerLb) * 2).rounded() / 2 : c.value
                guard kg >= 0.5, kg <= 400 else { continue }
                if best == nil || score > best!.score { best = (kg, score) }
            }
        }
        return best?.kg
    }

    enum Unit { case kg, lb }

    private static var pattern: NSRegularExpression { try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3}(?:[.,]\d{1,2})?)\s*(kgs?|lbs?|kilos?|pounds?)?(?![.,]?\d)"#, options: [.caseInsensitive]) }

    static func candidates(_ text: String) -> [(value: Double, unit: Unit?)] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let v = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")) else { return nil }
            let u = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2)).lowercased()
            let unit: Unit? = u.map { $0.hasPrefix("l") || $0.hasPrefix("p") ? .lb : .kg }
            return (v, unit)
        }
    }
}

/// Film whole session (#957, designs A + B + C from `record-workout/session/proposals.png`): the camera runs for the
/// whole workout with no tap between exercises. Frames of a set wait in `pending` until the app names the move
/// (`FilmWorkout.guess`, then `accept`); a set ends after `FilmWorkout.restAfter` without a rep; the next set is the
/// same move or a new one. A weight read during a rest goes to the next set; the phone being moved pauses it all.
public struct FilmSession: Sendable {
    public struct Move: Sendable, Hashable, Identifiable {
        public var id = UUID()
        public var exerciseId: String
        /// Other moves the frames looked like, best first (the Watch's ✗ and the review offer them).
        public var alternatives: [String]
        /// The top guess stood out, or the member confirmed it.
        public var sure: Bool
        public var sets: [FilmedSet] = []
        /// Weight of the coming sets; nil until read or filled from history.
        public var kg: Double?
        /// The weight was read off its print (not last time's).
        public var kgRead = false

        public init(exerciseId: String, alternatives: [String] = [], sure: Bool = true, kg: Double? = nil, kgRead: Bool = false) {
            self.exerciseId = exerciseId
            self.alternatives = alternatives
            self.sure = sure
            self.kg = kg
            self.kgRead = kgRead
        }
    }

    public enum Event: Sendable, Equatable {
        /// A move not done just before started (index in `moves`).
        case newMove(Int)
        /// Another set of the move done just before.
        case sameMove(Int)
        /// A set ended: its move, its number (1-based) and reps.
        case setLogged(move: Int, set: Int, reps: Int)
    }

    /// Share of the top guesses above which a move counts as sure.
    public static let sureShare = 50
    /// Frames kept while a move is unknown (about 40 s).
    public static let maxPending = 1200
    /// Frames needed before naming is tried.
    public static let minPending = 60

    /// Editable in the review.
    public var moves: [Move] = []
    public private(set) var pending: [FilmWorkout.Frame] = []
    /// The move of the set in progress, once named.
    public private(set) var current: Int?
    public private(set) var live = FormLive()
    public private(set) var paused = false
    private var analyzer: FormAnalyzer?
    private var lastRepAt: Double?
    private var nextKg: Double?

    public init() {}

    /// A set's move is known and being counted.
    public var inSet: Bool { analyzer != nil }
    /// Frames of an unknown move wait for `accept`.
    public var needsGuess: Bool { !paused && analyzer == nil && pending.count >= Self.minPending }
    /// The moves with at least one set, for logging.
    public var filmed: [FilmedMove] {
        moves.filter { !$0.sets.isEmpty }.map { FilmedMove(id: $0.id, exerciseId: $0.exerciseId, sets: $0.sets) }
    }

    /// One camera frame. Returns `setLogged` when the set in progress ends.
    @discardableResult
    public mutating func add(_ pose: FormPose?, at time: Double) -> Event? {
        guard !paused else { return nil }
        guard var an = analyzer else {
            pending.append((time: time, pose: pose))
            if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
            return nil
        }
        let before = live.reps.count
        live = an.add(pose, at: time)
        analyzer = an
        if live.reps.count > before { lastRepAt = time }
        return FilmWorkout.setEnded(reps: live.reps.count, lastRepAt: lastRepAt, now: time) ? endSet() : nil
    }

    /// Names the waiting set from `guesses` (best first) once the top one counted `repsToGuess` reps; its reps so far
    /// are counted again on the waiting frames.
    @discardableResult
    public mutating func accept(_ guesses: [FilmWorkout.Guess]) -> Event? {
        guard analyzer == nil, !paused, let top = guesses.first, top.reps >= FilmWorkout.repsToGuess,
              let model = FormModel(exercise: Exercise.get(top.exerciseId)) else { return nil }
        var an = FormAnalyzer(model: model)
        for f in pending { an.add(f.pose, at: f.time) }
        analyzer = an
        live = an.live
        lastRepAt = pending.last?.time
        pending = []
        let read = nextKg
        nextKg = nil
        if let i = moves.indices.last, moves[i].exerciseId == top.exerciseId {
            if let read {
                moves[i].kg = read
                moves[i].kgRead = true
            }
            current = i
            return .sameMove(i)
        }
        moves.append(Move(exerciseId: top.exerciseId, alternatives: guesses.dropFirst().map(\.exerciseId),
                          sure: top.confidence >= Self.sureShare, kg: read, kgRead: read != nil))
        current = moves.count - 1
        return .newMove(moves.count - 1)
    }

    /// A weight read off its print: between sets it goes to the next set, during a set to this move.
    public mutating func read(kg: Double) {
        if let i = current {
            moves[i].kg = kg
            moves[i].kgRead = true
        } else {
            nextKg = kg
        }
    }

    /// Last time's weight for a new move with none read.
    public mutating func fill(kg: Double, move i: Int) {
        guard moves.indices.contains(i), moves[i].kg == nil else { return }
        moves[i].kg = kg
    }

    /// The move was changed (Watch ✗ or an alternative picked, #988): a weight not read off the plates was the old
    /// move's last time, so it becomes the new move's (`lastKg`, nil = none) on the move and its sets.
    public mutating func moveChanged(_ i: Int, lastKg: Double?) {
        guard moves.indices.contains(i), !moves[i].kgRead else { return }
        moves[i].kg = lastKg
        for k in moves[i].sets.indices { moves[i].sets[k].kg = lastKg ?? 0 }
    }

    /// The member confirmed the move (Watch ✓).
    public mutating func confirm(_ i: Int) {
        guard moves.indices.contains(i) else { return }
        moves[i].sure = true
    }

    /// Not this move (Watch ✗): the next alternative takes its place; the rejected one goes last.
    public mutating func reject(_ i: Int) {
        guard moves.indices.contains(i), !moves[i].alternatives.isEmpty else { return }
        let old = moves[i].exerciseId
        let next = moves[i].alternatives.removeFirst()
        moves[i].exerciseId = next
        moves[i].alternatives.append(old)
        moves[i].sure = true
    }

    /// The phone is being moved: the set in progress ends (if it had reps) and nothing is counted until `resume`.
    @discardableResult
    public mutating func pause() -> Event? {
        guard !paused else { return nil }
        let e = endSet()
        pending = []
        paused = true
        return e
    }

    public mutating func resume() { paused = false }

    /// Stop: the set in progress is kept.
    @discardableResult
    public mutating func end() -> Event? { endSet() }

    private mutating func endSet() -> Event? {
        defer {
            analyzer = nil
            live = FormLive()
            lastRepAt = nil
            current = nil
        }
        guard let i = current, !live.reps.isEmpty else { return nil }
        moves[i].sets.append(FilmedSet(reps: live.reps.count, kg: moves[i].kg ?? 0, form: live.score))
        return .setLogged(move: i, set: moves[i].sets.count, reps: live.reps.count)
    }
}
