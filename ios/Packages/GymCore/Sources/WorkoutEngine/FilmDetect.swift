import Foundation

// Better detection for Film my workout (#969). The first version named a move by running every move's form check
// over the frames: it only counted reps when the camera stood on the guide's side, so a phone in front of a squat or
// a curl named nothing. Now reps come from the member's own movement (whichever joint swings most, from wherever it
// stands), the move is named by the body's shape at the start and at the bottom of those reps against each move's
// 3D guide, and the angles come from the phone's 3D body pose when it has one (the same from any camera spot).

// MARK: - Angles from any side

extension FormPose {
    /// Angle at `joint` on one side: from the 3D joints when the frame has them, else from the picture.
    public func bodyAngle(_ joint: PositionJoint, left: Bool) -> Double? {
        guard let world else { return angle(joint, left: left) }
        guard let t = Self.jointsFor(joint, left: left), let a = world[t.0], let j = world[t.1], let b = world[t.2] else { return nil }
        let u = a - j, v = b - j
        let nu = (u * u).sum().squareRoot(), nv = (v * v).sum().squareRoot()
        guard nu > 1e-6, nv > 1e-6 else { return nil }
        return acos(max(-1, min(1, (u * v).sum() / nu / nv))) * 180 / .pi
    }

    /// Both sides averaged when both are seen.
    public func bodyAngle(_ joint: PositionJoint) -> Double? {
        let v = [bodyAngle(joint, left: true), bodyAngle(joint, left: false)].compactMap { $0 }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}

/// The body's shape in one frame: the big joints' angles and how far the trunk leans from upright (0 standing or
/// sitting, 90 lying or in a plank).
public struct BodyShape: Sendable, Hashable {
    public var angles: [PositionJoint: Double]
    public var tilt: Double?

    public static let joints: [PositionJoint] = [.knee, .hip, .elbow, .shoulder]

    public init(angles: [PositionJoint: Double], tilt: Double?) {
        self.angles = angles
        self.tilt = tilt
    }

    public init(_ pose: FormPose) {
        var a: [PositionJoint: Double] = [:]
        for j in Self.joints { a[j] = pose.bodyAngle(j) }
        angles = a
        tilt = pose.torsoLean
    }

    /// A guide key position: both sides averaged, the trunk's lean in 3D.
    public init(key: ExercisePosition.Key) {
        var a: [PositionJoint: Double] = [:]
        for j in Self.joints {
            let v = [key.angle(j, side: "N"), key.angle(j, side: "F"), key.angle(j, side: "")].compactMap { $0 }
            if !v.isEmpty { a[j] = v.reduce(0, +) / Double(v.count) }
        }
        angles = a
        func mid(_ n: String) -> SIMD3<Double>? {
            let v = [key[n + "N"], key[n + "F"], key[n]].compactMap { $0 }
            return v.isEmpty ? nil : v.reduce(SIMD3<Double>(), +) / Double(v.count)
        }
        if let s = mid("shoulder"), let h = mid("hip") {
            let d = s - h
            let n = (d * d).sum().squareRoot()
            tilt = n > 1e-6 ? acos(max(-1, min(1, d.y / n))) * 180 / .pi : nil
        } else {
            tilt = nil
        }
    }

    /// Each angle and the lean averaged over shapes.
    public static func average(_ shapes: [BodyShape]) -> BodyShape {
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        var a: [PositionJoint: Double] = [:]
        for j in joints { a[j] = avg(shapes.compactMap { $0.angles[j] }) }
        return BodyShape(angles: a, tilt: avg(shapes.compactMap(\.tilt)))
    }

    /// Degrees apart: the joints both have, averaged, plus most of the lean's gap (lying vs standing tells most moves
    /// apart). 60 when nothing can be compared.
    public func distance(to o: BodyShape) -> Double {
        let gaps = Self.joints.compactMap { j -> Double? in
            guard let x = angles[j], let y = o.angles[j] else { return nil }
            return abs(x - y)
        }
        var d = gaps.isEmpty ? 60 : gaps.reduce(0, +) / Double(gaps.count)
        if let x = tilt, let y = o.tilt { d += abs(x - y) * 0.8 }
        return d
    }
}

// MARK: - A move's signature

/// What a move looks like from any side: the body's shape at the guide's start and main position, and the joint that
/// moves most (its reps are counted on it).
public struct MoveSignature: Sendable {
    public let exerciseId: String
    public let start: BodyShape
    public let peak: BodyShape
    public let joint: PositionJoint
    public let equipment: [Equipment]

    public init?(exercise e: Exercise) {
        guard let pos = e.position, pos.keys.count >= 2 else { return nil }
        let main = pos.mainKey
        guard main > 0 else { return nil }
        let s = BodyShape(key: pos.keys[0]), p = BodyShape(key: pos.keys[main])
        let moved = BodyShape.joints.compactMap { j -> (PositionJoint, Double)? in
            guard let a = s.angles[j], let b = p.angles[j] else { return nil }
            return (j, abs(b - a))
        }
        guard let top = moved.max(by: { $0.1 < $1.1 }), top.1 >= 20 else { return nil }
        exerciseId = e.id
        start = s
        peak = p
        joint = top.0
        equipment = e.equipment
    }

    /// Every move the camera can name.
    public static let all: [String: MoveSignature] = Dictionary(
        FilmWorkout.models.compactMap { MoveSignature(exercise: Exercise.get($0.exerciseId)) }.map { ($0.exerciseId, $0) },
        uniquingKeysWith: { a, _ in a })

    /// 0–1: how much the member's start and bottom shapes look like this move's. Shapes are also tried the other way
    /// round (the camera can't always tell which end is the start), at a small cost.
    public func similarity(start s: BodyShape, peak p: BodyShape) -> Double {
        func range(_ a: BodyShape, _ b: BodyShape, _ j: PositionJoint) -> Double? {
            guard let x = a.angles[j], let y = b.angles[j] else { return nil }
            return abs(y - x)
        }
        // Which joints move and how much: a curl moves the elbow, a squat the knee and hip.
        let gaps = BodyShape.joints.compactMap { j -> Double? in
            guard let m = range(s, p, j), let g = range(start, peak, j) else { return nil }
            return abs(m - g)
        }
        let moving = gaps.isEmpty ? 40 : gaps.reduce(0, +) / Double(gaps.count)
        let straight = (s.distance(to: start) + p.distance(to: peak)) / 2
        let swapped = (s.distance(to: peak) + p.distance(to: start)) / 2 + 8
        return exp(-(min(straight, swapped) + moving) / 30)
    }
}

// MARK: - Reps from the member's own movement

/// Counts reps on one joint without knowing the move: the joint's own lowest and highest angle so far set the range,
/// the side it rests on is where the frames began, and a rep is going most of the way out and coming back.
public struct RepTracker: Sendable {
    /// A swing smaller than this is not a rep (breathing, the camera's jitter).
    public static let minRange = 25.0
    /// Share of the range that counts as out, and as back.
    public static let out = 0.6
    public static let back = 0.3
    /// Faster than this is a step or a twitch, not a rep.
    public static let minSeconds = 0.6

    public let joint: PositionJoint
    public private(set) var count = 0
    /// Body shape at the start and at the far end of each rep.
    public private(set) var starts: [BodyShape] = []
    public private(set) var peaks: [BodyShape] = []
    public private(set) var lastRepAt: Double?

    private var smooth: Double?
    private var first: Double?
    private var lo = Double.infinity
    private var hi = -Double.infinity
    private var isOut = false
    /// Closest to the rest position since the last rep, and furthest from it during this one.
    private var near: (shape: BodyShape, time: Double, share: Double)?
    private var far: (shape: BodyShape, share: Double)?

    public init(joint: PositionJoint) { self.joint = joint }

    /// Degrees between the lowest and highest angle seen.
    public var range: Double { hi >= lo ? hi - lo : 0 }

    /// Feed one frame; true when it finished a rep.
    @discardableResult
    public mutating func add(_ pose: FormPose?, at time: Double) -> Bool {
        guard let pose, let v = pose.bodyAngle(joint) else { return false }
        let s = smooth.map { $0 + (v - $0) * 0.5 } ?? v
        smooth = s
        guard let first else {
            self.first = s
            lo = s
            hi = s
            near = (BodyShape(pose), time, 0)
            return false
        }
        lo = min(lo, s)
        hi = max(hi, s)
        let r = hi - lo
        guard r >= Self.minRange else { return false }
        let restHigh = abs(first - hi) < abs(first - lo)
        let share = restHigh ? (hi - s) / r : (s - lo) / r
        if !isOut {
            if share <= Self.back, share <= near?.share ?? 1 { near = (BodyShape(pose), time, share) }
            if share >= Self.out, near != nil {
                isOut = true
                far = (BodyShape(pose), share)
            }
            return false
        }
        if share > far?.share ?? 0 { far = (BodyShape(pose), share) }
        guard share <= Self.back else { return false }
        isOut = false
        defer { near = (BodyShape(pose), time, share) }
        guard let n = near, let f = far, time - n.time >= Self.minSeconds else { return false }
        count += 1
        starts.append(n.shape)
        peaks.append(f.shape)
        lastRepAt = time
        return true
    }
}

/// Reps of a known move: the form check counts and scores them when the camera is on the guide's side; otherwise
/// the member's own movement counts them, unscored (`FormLive.formless`).
public struct MoveCounter: Sendable {
    public let exerciseId: String
    private var form: FormAnalyzer?
    private var tracker: RepTracker
    public private(set) var live = FormLive()

    public init?(exercise e: Exercise) {
        guard let sig = MoveSignature.all[e.id] ?? MoveSignature(exercise: e) else { return nil }
        exerciseId = e.id
        form = FormAnalyzer(exercise: e)
        tracker = RepTracker(joint: sig.joint)
    }

    public var reps: [FormRep] { live.reps }

    @discardableResult
    public mutating func add(_ pose: FormPose?, at time: Double) -> FormLive {
        tracker.add(pose, at: time)
        var l = FormLive()
        if var f = form {
            l = f.add(pose, at: time)
            form = f
        } else {
            l.visible = pose != nil
        }
        if tracker.count > l.reps.count {
            l.reps = (1...tracker.count).map { FormRep(number: $0, score: 0, match: 0, depth: 1, seconds: 0, faults: []) }
            l.formless = true
            l.warn = []
            l.bad = []
            if l.cue?.fault != nil { l.cue = nil }
        }
        live = l
        return l
    }
}

// MARK: - The member's movement

/// What the frames show: reps on the joint that swings most, and the body's shape at their start and far end.
public struct SeenMotion: Sendable {
    public let joint: PositionJoint
    public let reps: Int
    public let start: BodyShape
    public let peak: BodyShape
    public let lastRepAt: Double?

    /// Nil until a rep is seen.
    public init?(_ frames: [FilmWorkout.Frame]) {
        var trackers = BodyShape.joints.map { RepTracker(joint: $0) }
        for f in frames {
            for i in trackers.indices { trackers[i].add(f.pose, at: f.time) }
        }
        guard let best = trackers.filter({ $0.count > 0 }).max(by: { ($0.range, $0.count) < ($1.range, $1.count) }) else { return nil }
        joint = best.joint
        reps = best.count
        start = BodyShape.average(best.starts)
        peak = BodyShape.average(best.peaks)
        lastRepAt = best.lastRepAt
    }
}

/// How the hands hold the weight: a bar keeps the wrists the same distance apart, dumbbells and kettlebells let it
/// change. A small nudge between moves that look alike (barbell vs dumbbell curl).
public enum KitHint: Sendable, Equatable {
    case bar, free, unknown

    public init(_ frames: [FilmWorkout.Frame]) {
        let ratios = frames.compactMap { f -> Double? in
            guard let p = f.pose else { return nil }
            func dist(_ a: FormJoint, _ b: FormJoint) -> Double? {
                if let w = p.world, let x = w[a], let y = w[b] { return ((x - y) * (x - y)).sum().squareRoot() }
                guard p.world == nil, let x = p[a], let y = p[b] else { return nil }
                return ((x - y) * (x - y)).sum().squareRoot()
            }
            guard let hands = dist(.leftWrist, .rightWrist), let shoulders = dist(.leftShoulder, .rightShoulder),
                  shoulders > 1e-3 else { return nil }
            return hands / shoulders
        }
        guard ratios.count >= 15 else {
            self = .unknown
            return
        }
        let mean = ratios.reduce(0, +) / Double(ratios.count)
        let sd = (ratios.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(ratios.count)).squareRoot()
        let cv = mean > 1e-6 ? sd / mean : 1
        self = cv < 0.07 ? .bar : cv > 0.18 ? .free : .unknown
    }

    static let barKit: Set<Equipment> = [.barbell, .trapBar, .smith, .landmine]
    static let freeKit: Set<Equipment> = [.dumbbells, .kettlebells]

    /// Score added for a move with this equipment.
    func nudge(_ equipment: [Equipment]) -> Double {
        let e = Set(equipment)
        switch self {
        case .bar: return !e.isDisjoint(with: Self.barKit) ? 0.08 : !e.isDisjoint(with: Self.freeKit) ? -0.08 : 0
        case .free: return !e.isDisjoint(with: Self.freeKit) ? 0.08 : !e.isDisjoint(with: Self.barKit) ? -0.08 : 0
        case .unknown: return 0
        }
    }

    /// Words the phone's scene labels use for kit, and the equipment they mean.
    static let sceneWords: [(String, Set<Equipment>)] = [
        ("dumbbell", [.dumbbells]), ("barbell", [.barbell, .smith]), ("kettlebell", [.kettlebells]),
        ("bench", [.bench]), ("treadmill", [.treadmill]), ("bicycle", [.bike]), ("rowing", [.rower, .seatedRow]),
    ]

    /// Score added for kit seen in the scene (labels from the phone's image classifier, lowercased).
    static func sceneNudge(_ equipment: [Equipment], scene: Set<String>) -> Double {
        guard !scene.isEmpty else { return 0 }
        let e = Set(equipment)
        let hit = sceneWords.contains { word, kit in !e.isDisjoint(with: kit) && scene.contains { $0.contains(word) } }
        return hit ? 0.1 : 0
    }
}

// MARK: - In frame

/// Is the member in the picture, and what to move if not (#969). Points are in frame units (height 1, width the
/// aspect ratio, y up).
public enum FrameCheck {
    public enum Issue: String, Sendable, CaseIterable {
        case nobody, tooClose, headCut, feetCut, moveLeft, moveRight, tooFar

        public var title: String {
            switch self {
            case .nobody: "Step into view"
            case .tooClose: "Too close"
            case .headCut: "Head cut off"
            case .feetCut: "Feet cut off"
            case .moveLeft: "Move left"
            case .moveRight: "Move right"
            case .tooFar: "Too far"
            }
        }

        public var detail: String {
            switch self {
            case .nobody: "Whole body in the picture"
            case .tooClose: "Step back or move the phone back"
            case .headCut: "Tilt the phone up or step back"
            case .feetCut: "Tilt the phone down or step back 1 m"
            case .moveLeft, .moveRight: "Part of you is off screen"
            case .tooFar: "Come a bit closer"
            }
        }

        /// What the Coach says.
        public var spoken: String {
            switch self {
            case .nobody: "Step into view"
            case .tooClose: "Step back a little"
            case .headCut: "Your head is cut off. Tilt the phone up"
            case .feetCut: "Your feet are cut off. Tilt the phone down or step back"
            case .moveLeft: "Move a little to your left"
            case .moveRight: "Move a little to your right"
            case .tooFar: "Come a bit closer"
            }
        }

        public var symbol: String {
            switch self {
            case .nobody: "figure.stand"
            case .tooClose: "arrow.down.backward.and.arrow.up.forward"
            case .headCut: "arrow.up"
            case .feetCut: "arrow.down"
            case .moveLeft: "arrow.left"
            case .moveRight: "arrow.right"
            case .tooFar: "arrow.up.left.and.arrow.down.right"
            }
        }
    }

    /// Spoken once the member is in frame again.
    public static let inFrame = "Got you"
    /// Share of the frame kept clear at the edges.
    static let edge = 0.025
    /// Body (head to feet, or end to end lying down) taller than this share of the frame is too close, shorter than
    /// this one too far.
    static let tooBig = 0.97
    static let tooSmall = 0.3

    /// Nil when the whole body is in view. `mirrored`: the picture is shown like a mirror (front camera), so the
    /// member's left is the picture's left.
    public static func issue(_ pose: FormPose?, aspect: Double, mirrored: Bool) -> Issue? {
        guard let pose, pose.points.count >= 6 else { return .nobody }
        let xs = pose.points.values.map(\.x), ys = pose.points.values.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .nobody }
        let headless = (pose[.nose] == nil && pose[.neck] == nil) || maxY > 1 - edge
        let feetless = (pose[.leftAnkle] == nil && pose[.rightAnkle] == nil) || minY < edge
        let span = max(maxY - minY, maxX - minX)
        if (headless && feetless) || span > tooBig { return .tooClose }
        if headless { return .headCut }
        if feetless { return .feetCut }
        let atLeft = minX < edge * aspect, atRight = maxX > aspect * (1 - edge)
        if atLeft != atRight {
            // Off the picture's left: the member is too far to that side and moves the other way.
            let pictureLeft = atLeft
            return pictureLeft == mirrored ? .moveRight : .moveLeft
        }
        if span < tooSmall { return .tooFar }
        return nil
    }
}
