import Foundation

// Form check (#833, designs A + B + C from `form-check/proposals.png`): the phone films the member doing an exercise,
// Apple's body pose (Vision, on the iPhone) finds the joints in every frame, and this file turns them into reps,
// faults, a score per rep, a lime "ghost" of the right position (the 3D position guide's poses) and the set report.
// Nothing here knows about the camera: the app feeds `FormPose`s, so the rules run in tests on made-up frames.

// MARK: - Pose

/// Body points the camera finds, named for the member's own left and right.
public enum FormJoint: String, CaseIterable, Sendable {
    case nose, neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist,
         leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// One frame's joints. Units are equal on both axes (the frame's height is 1, its width the aspect ratio), y up.
public struct FormPose: Sendable, Hashable {
    public var points: [FormJoint: SIMD2<Double>]
    /// The same joints in 3D (metres, any axes) when the phone's 3D body pose found them (#969): angles measured on
    /// them are the same wherever the camera stands. Not saved in replays.
    public var world: [FormJoint: SIMD3<Double>]?

    public init(_ points: [FormJoint: SIMD2<Double>], world: [FormJoint: SIMD3<Double>]? = nil) {
        self.points = points
        self.world = world
    }

    public subscript(_ j: FormJoint) -> SIMD2<Double>? { points[j] }

    /// Lines of the skeleton.
    public static let bones: [(FormJoint, FormJoint)] = [
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    /// The joints of a `PositionJoint` angle on one side: (a, joint, b). Nil for the ankle (the camera finds no toes).
    static func jointsFor(_ joint: PositionJoint, left: Bool) -> (FormJoint, FormJoint, FormJoint)? {
        switch joint {
        case .knee: left ? (.leftHip, .leftKnee, .leftAnkle) : (.rightHip, .rightKnee, .rightAnkle)
        case .hip: left ? (.leftShoulder, .leftHip, .leftKnee) : (.rightShoulder, .rightHip, .rightKnee)
        case .elbow: left ? (.leftShoulder, .leftElbow, .leftWrist) : (.rightShoulder, .rightElbow, .rightWrist)
        case .shoulder: left ? (.leftHip, .leftShoulder, .leftElbow) : (.rightHip, .rightShoulder, .rightElbow)
        case .ankle: nil
        }
    }

    /// Angle at `joint` on one side in degrees (180 = straight).
    public func angle(_ joint: PositionJoint, left: Bool) -> Double? {
        guard let t = Self.jointsFor(joint, left: left), let pa = self[t.0], let pj = self[t.1], let pb = self[t.2] else { return nil }
        return Self.angle(pa, pj, pb)
    }

    /// Angle at `joint`, both sides averaged when both are seen.
    public func angle(_ joint: PositionJoint) -> Double? {
        let v = [angle(joint, left: true), angle(joint, left: false)].compactMap { $0 }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    static func angle(_ a: SIMD2<Double>, _ j: SIMD2<Double>, _ b: SIMD2<Double>) -> Double? {
        let u = a - j, v = b - j
        let nu = (u * u).sum().squareRoot(), nv = (v * v).sum().squareRoot()
        guard nu > 1e-6, nv > 1e-6 else { return nil }
        return acos(max(-1, min(1, (u * v).sum() / nu / nv))) * 180 / .pi
    }

    static func mid(_ a: SIMD2<Double>?, _ b: SIMD2<Double>?) -> SIMD2<Double>? {
        switch (a, b) {
        case let (a?, b?): (a + b) / 2
        case let (a?, nil): a
        case let (nil, b?): b
        default: nil
        }
    }

    var shoulders: SIMD2<Double>? { Self.mid(self[.leftShoulder], self[.rightShoulder]) }
    var hips: SIMD2<Double>? { Self.mid(self[.leftHip], self[.rightHip]) }
    var ankles: SIMD2<Double>? { Self.mid(self[.leftAnkle], self[.rightAnkle]) }

    /// Lean of the trunk (hips → shoulders) away from upright, in degrees.
    public var torsoLean: Double? {
        guard let s = shoulders, let h = hips else { return nil }
        let d = s - h
        let n = (d * d).sum().squareRoot()
        guard n > 1e-6 else { return nil }
        return acos(max(-1, min(1, d.y / n))) * 180 / .pi
    }

    /// Head to feet: the body's length on screen.
    var length: Double? {
        guard let top = self[.nose] ?? self[.neck], let a = ankles else { return nil }
        let d = top - a
        return (d * d).sum().squareRoot()
    }

    /// Every point moved by `f`.
    func mapped(_ f: (SIMD2<Double>) -> SIMD2<Double>) -> FormPose { FormPose(points.mapValues(f)) }

    /// Between two poses (joints both have).
    static func lerp(_ a: FormPose, _ b: FormPose, _ t: Double) -> FormPose {
        var out: [FormJoint: SIMD2<Double>] = [:]
        for (j, p) in a.points { if let q = b[j] { out[j] = p + (q - p) * t } }
        return FormPose(out)
    }
}

extension FormPose: Codable {
    /// Flat [x, y, …] in `FormJoint` order, −1 for a point not seen (a replay stays small).
    public init(from decoder: Decoder) throws {
        let flat = try decoder.singleValueContainer().decode([Double].self)
        var p: [FormJoint: SIMD2<Double>] = [:]
        for (i, j) in FormJoint.allCases.enumerated() where flat.count >= i * 2 + 2 && flat[i * 2] > -0.5 {
            p[j] = SIMD2(flat[i * 2], flat[i * 2 + 1])
        }
        points = p
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(FormJoint.allCases.flatMap { j -> [Double] in
            guard let v = points[j] else { return [-1, -1] }
            return [(v.x * 1000).rounded() / 1000, (v.y * 1000).rounded() / 1000]
        })
    }
}

// MARK: - Faults

/// What the check catches. Only the ones the camera can see from the exercise's side are checked.
public enum FormFault: String, Codable, CaseIterable, Sendable {
    case shallow, noLockout, kneesIn, torsoLean, hipsSag, uneven, tooFast

    /// Points taken off a rep's 100.
    public var penalty: Int {
        switch self {
        case .shallow, .kneesIn, .hipsSag: 25
        case .torsoLean: 20
        case .uneven: 15
        case .noLockout, .tooFast: 10
        }
    }

    public var title: String {
        switch self {
        case .shallow: "Short range"
        case .noLockout: "Didn't finish the rep"
        case .kneesIn: "Knees caved"
        case .torsoLean: "Torso lean grew"
        case .hipsSag: "Hips sagged"
        case .uneven: "One side ahead"
        case .tooFast: "Too fast"
        }
    }

    public var symbol: String {
        switch self {
        case .shallow: "arrow.down.to.line"
        case .noLockout: "arrow.up.to.line"
        case .kneesIn: "arrow.left.and.right"
        case .torsoLean: "arrow.up.right"
        case .hipsSag: "arrow.up"
        case .uneven: "scalemass.fill"
        case .tooFast: "tortoise.fill"
        }
    }
}

/// The one line shown (and said) during the set.
public struct FormCue: Sendable, Hashable {
    public enum Tone: Sendable { case good, warn, bad, info }
    public let text: String
    public let symbol: String
    public let tone: Tone
    /// The fault behind it (nil for "Good rep" and "Step into view").
    public let fault: FormFault?
}

// MARK: - Model of an exercise

/// What the check measures for one exercise, from its 3D position guide: the start and the main position seen from
/// the guide's side, the joint that moves most (reps are counted on it) and the faults that side can show.
public struct FormModel: Sendable {
    public let exerciseId: String
    public let view: ExercisePosition.View
    /// The guide's start and main position as the camera sees them (guide units, y up, facing +x).
    public let start: FormPose
    public let peak: FormPose
    /// Reps are counted on this joint; the chips show `watched`.
    public let primary: PositionJoint
    public let watched: [PositionJoint]
    public let faults: Set<FormFault>
    /// Unilateral moves follow the side that moves most, not both averaged.
    public let unilateral: Bool
    /// Seconds per rep below which a rep is "too fast"; nil for jumps and throws.
    public let minRepSeconds: Double?

    /// Rep thresholds on the way from the start (0) to the main position (1), and the fault limits.
    public enum Limit {
        /// A rep starts past this share of the way down…
        public static let repStart = 0.5
        /// …and ends back under this one.
        public static let repEnd = 0.3
        /// Reaching less of the way is a short rep.
        public static let fullRange = 0.8
        /// Staying further than this from the start between reps is a rep not finished.
        public static let lockout = 0.2
        /// Trunk leaning this many degrees more than the guide at the bottom.
        public static let torsoLean = 15.0
        /// Knees (vs the ankles' width) closer than this share of the guide's at the same point (front view).
        public static let kneeWidth = 0.85
        /// Hips this share of the body's length under the shoulder–ankle line.
        public static let hipSag = 0.07
        /// Left and right this many degrees apart.
        public static let uneven = 15.0
        /// Within this many degrees of the guide = right (green), twice = close (amber).
        public static let angleOK = 10.0
        /// A joint this far off the guide scores 0 % match.
        public static let matchZero = 45.0
        public static let minRepSeconds = 0.8
    }

    public init?(exercise e: Exercise) {
        guard e.unit != .sec, e.category != .stretch, let pos = e.position, pos.keys.count >= 2 else { return nil }
        let main = pos.mainKey
        guard main > 0 else { return nil }
        let start = Self.project(pos.keys[0], view: pos.view)
        let peak = Self.project(pos.keys[main], view: pos.view)
        var unilateral = e.unilateral
        let ranges: [(PositionJoint, Double)] = [PositionJoint.knee, .hip, .elbow, .shoulder].compactMap { j -> (PositionJoint, Double)? in
            if e.unilateral {
                let l = Self.range(j, left: true, start, peak), r = Self.range(j, left: false, start, peak)
                return (l ?? r).map { _ in (j, max(l ?? 0, r ?? 0)) }
            }
            guard let a = start.angle(j), let b = peak.angle(j) else { return nil }
            return (j, abs(b - a))
        }.sorted { $0.1 > $1.1 }
        guard let first = ranges.first, first.1 >= 25 else { return nil }
        if !e.unilateral, let l = Self.range(first.0, left: true, start, peak), let r = Self.range(first.0, left: false, start, peak),
           abs(l - r) > 30 { unilateral = true }
        exerciseId = e.id
        view = pos.view
        self.start = start
        self.peak = peak
        primary = first.0
        let watched = ranges.prefix(2).filter { $0.1 >= 15 }.map { $0.0 }
        self.watched = watched
        self.unilateral = unilateral
        let explosive = e.category == .power || [Pattern.jump, .`throw`, .ballistic, .upperPlyo].contains(e.pattern)
        minRepSeconds = explosive ? nil : Limit.minRepSeconds

        var f: Set<FormFault> = [.shallow, .noLockout]
        if !explosive { f.insert(.tooFast) }
        let lower = watched.contains(.knee) || watched.contains(.hip)
        if pos.view == .side {
            if lower && [.squat, .hinge, .singleLeg].contains(e.pattern) { f.insert(.torsoLean) }
            if e.pattern == .coreAntiExt || (e.pattern == .hPush && e.equipment.isEmpty) { f.insert(.hipsSag) }
        } else {
            if watched.contains(.knee) { f.insert(.kneesIn) }
            if !unilateral { f.insert(.uneven) }
        }
        // The exercise's own "Avoid" list adds what it warns about when the camera can see it.
        if let m = PositionMistake.pick(e.technique?.mistakes ?? []) {
            switch m.kind {
            case .kneesIn where pos.view != .side: f.insert(.kneesIn)
            case .hipsSag where pos.view == .side: f.insert(.hipsSag)
            case .roundedBack where pos.view == .side && lower: f.insert(.torsoLean)
            default: break
            }
        }
        faults = f
    }

    /// Exercises the camera can check (reps, a 3D guide, one joint moving at least 25°).
    public static func supports(_ e: Exercise) -> Bool { supportedIds.contains(e.id) }

    static let supportedIds: Set<String> = Set(Exercise.catalog.filter { FormModel(exercise: $0) != nil }.map(\.id))

    /// The guide's key position seen from its side: x forward (side) or across (front, back), y up.
    static func project(_ key: ExercisePosition.Key, view: ExercisePosition.View) -> FormPose {
        func p(_ name: String) -> SIMD2<Double>? {
            guard let v = key[name] else { return nil }
            switch view {
            case .side: return SIMD2(v.x, v.y)
            case .front: return SIMD2(v.z, v.y)
            case .back: return SIMD2(-v.z, v.y)
            }
        }
        var out: [FormJoint: SIMD2<Double>] = [:]
        let names: [(FormJoint, String)] = [
            (.nose, "head"), (.neck, "neck"), (.leftShoulder, "shoulderN"), (.rightShoulder, "shoulderF"),
            (.leftElbow, "elbowN"), (.rightElbow, "elbowF"), (.leftWrist, "wristN"), (.rightWrist, "wristF"),
            (.leftHip, "hipN"), (.rightHip, "hipF"), (.leftKnee, "kneeN"), (.rightKnee, "kneeF"),
            (.leftAnkle, "ankleN"), (.rightAnkle, "ankleF"),
        ]
        for (j, n) in names { out[j] = p(n) }
        if out[.neck] == nil { out[.neck] = p("shoulder") ?? FormPose.mid(out[.leftShoulder], out[.rightShoulder]) }
        if out[.leftHip] == nil, let h = p("hip") { out[.leftHip] = h; out[.rightHip] = h }
        return FormPose(out)
    }

    private static func range(_ j: PositionJoint, left: Bool, _ a: FormPose, _ b: FormPose) -> Double? {
        guard let x = a.angle(j, left: left), let y = b.angle(j, left: left) else { return nil }
        return abs(y - x)
    }

    /// The guide's angle at `joint` at `progress` (0 start → 1 main position).
    public func target(_ joint: PositionJoint, at progress: Double) -> Double? {
        guard let a = start.angle(joint), let b = peak.angle(joint) else { return nil }
        return a + (b - a) * min(1, max(0, progress))
    }

    /// The guide's pose at `progress`.
    public func guidePose(at progress: Double) -> FormPose { FormPose.lerp(start, peak, min(1, max(0, progress))) }

    var primaryFlexes: Bool { (peak.angle(primary) ?? 0) < (start.angle(primary) ?? 0) }

    /// The line for a fault, worded for this exercise.
    public func cue(_ f: FormFault) -> FormCue {
        let lower = primary == .knee || primary == .hip
        let text: String = switch f {
        case .shallow: lower && primaryFlexes ? "Go deeper" : "Full range"
        case .noLockout: lower ? "Finish tall" : "Lock it out"
        case .kneesIn: "Push knees out"
        case .torsoLean: "Chest up"
        case .hipsSag: "Hips up, squeeze glutes"
        case .uneven: "Even out both sides"
        case .tooFast: "Slow down, 2 s down"
        }
        return FormCue(text: text, symbol: f.symbol, tone: f.penalty >= 20 ? .bad : .warn, fault: f)
    }
}

// MARK: - Reps and report

/// One counted rep.
public struct FormRep: Codable, Sendable, Hashable {
    /// 1-based.
    public var number: Int
    public var score: Int
    /// How close the bottom of the rep was to the guide, 0–100.
    public var match: Int
    /// Share of the way to the guide's main position reached, 0–1+.
    public var depth: Double
    public var seconds: Double
    public var faults: [FormFault]
    /// Degrees more trunk lean than the guide at the bottom.
    public var torsoExtra: Double?
    /// Knee width ÷ ankle width at the bottom, as a share of the guide's (front view).
    public var kneeWidth: Double?
    /// Hips under the shoulder–ankle line, share of body length.
    public var sag: Double?
    /// Left vs right, degrees.
    public var sideGap: Double?

    mutating func add(_ f: FormFault) {
        guard !faults.contains(f) else { return }
        faults.append(f)
        score = FormRep.score(faults)
    }

    static func score(_ faults: [FormFault]) -> Int { max(0, 100 - faults.reduce(0) { $0 + $1.penalty }) }
}

/// What to fix next set: a fault, the reps it showed on and its size.
public struct FormFix: Sendable, Hashable {
    public let fault: FormFault
    public let reps: [Int]
    public let detail: String
}

/// The set report (design C), kept in the exercise's history.
public struct FormReport: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var exerciseId: String
    public var date: Date
    public var reps: [FormRep]
    /// The worst rep's frames for the replay (about 15 a second).
    public var worstReplay: [FormPose]
    /// Every rep's frames while the report is open (not saved).
    public var replays: [Int: [FormPose]] = [:]

    enum CodingKeys: String, CodingKey { case id, exerciseId, date, reps, worstReplay }

    public init(id: UUID = UUID(), exerciseId: String, date: Date, reps: [FormRep], worstReplay: [FormPose], replays: [Int: [FormPose]] = [:]) {
        self.id = id
        self.exerciseId = exerciseId
        self.date = date
        self.reps = reps
        self.worstReplay = worstReplay
        self.replays = replays
    }

    /// Average rep score; 0 without reps.
    public var score: Int { reps.isEmpty ? 0 : Int((Double(reps.map(\.score).reduce(0, +)) / Double(reps.count)).rounded()) }

    public var match: Int { reps.isEmpty ? 0 : Int((Double(reps.map(\.match).reduce(0, +)) / Double(reps.count)).rounded()) }

    /// Best rep (highest score, then best match), 1-based.
    public var best: Int? { reps.max { ($0.score, $0.match) < ($1.score, $1.match) }?.number }

    public static let fadeScore = 80

    /// Lowest rep, 1-based (the one replayed).
    public var worst: Int? {
        guard reps.contains(where: { !$0.faults.isEmpty }) else { return nil }
        return reps.min { ($0.score, $0.match) < ($1.score, $1.match) }?.number
    }

    /// The rep form fell off from: every rep from it scores `fadeScore` or less after at least one that scored more.
    public var fadeFrom: Int? {
        guard reps.count >= 3 else { return nil }
        for i in 1..<reps.count where reps[i...].allSatisfy({ $0.score <= Self.fadeScore }) && reps[..<i].contains(where: { $0.score > Self.fadeScore }) {
            return reps[i].number
        }
        return nil
    }

    /// Up to two things to fix, the most frequent (then the costliest) first.
    public var fixes: [FormFix] {
        let found = FormFault.allCases.compactMap { f -> (FormFault, [FormRep])? in
            let r = reps.filter { $0.faults.contains(f) }
            return r.isEmpty ? nil : (f, r)
        }
        return found.sorted { ($0.1.count, $0.0.penalty) > ($1.1.count, $1.0.penalty) }.prefix(2).map { f, r in
            FormFix(fault: f, reps: r.map(\.number), detail: Self.detail(f, r))
        }
    }

    private static func detail(_ f: FormFault, _ r: [FormRep]) -> String {
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        switch f {
        case .shallow: return avg(r.map(\.depth)).map { "\(Int(($0 * 100).rounded())) %" } ?? ""
        case .torsoLean: return avg(r.compactMap(\.torsoExtra)).map { "+\(Int($0.rounded()))°" } ?? ""
        case .kneesIn: return avg(r.compactMap(\.kneeWidth)).map { "−\(Int(((1 - $0) * 100).rounded())) %" } ?? ""
        case .hipsSag: return avg(r.compactMap(\.sag)).map { "\(Int(($0 * 100).rounded())) %" } ?? ""
        case .uneven: return avg(r.compactMap(\.sideGap)).map { "\(Int($0.rounded()))°" } ?? ""
        case .tooFast: return avg(r.map(\.seconds)).map { String(format: "%.1f s", $0) } ?? ""
        case .noLockout: return "×\(r.count)"
        }
    }

    /// "Reps 6–7", "Rep 4", "Reps 2, 5, 8".
    public static func repsText(_ reps: [Int]) -> String {
        guard let first = reps.first, let last = reps.last else { return "" }
        if reps.count == 1 { return "rep \(first)" }
        if last - first == reps.count - 1 { return "reps \(first)–\(last)" }
        return "reps " + reps.map(String.init).joined(separator: ", ")
    }
}

// MARK: - Analyzer

/// How a joint looks against the guide right now.
public struct FormAngleCheck: Sendable, Hashable {
    public enum Status: Sendable { case good, close, off }
    public let joint: PositionJoint
    public let degrees: Int
    public let target: Int
    public let status: Status

    public var label: String { "\(joint.label.uppercased()) \(degrees)°" }
}

/// What the live screen shows after each frame.
public struct FormLive: Sendable {
    public var reps: [FormRep] = []
    /// The whole body is in view.
    public var visible = false
    /// 0 at the start position, 1 at the guide's main position.
    public var progress: Double = 0
    public var checks: [FormAngleCheck] = []
    /// Joints to colour amber / red.
    public var warn: Set<FormJoint> = []
    public var bad: Set<FormJoint> = []
    public var cue: FormCue?
    /// The guide's pose fitted over the member, in frame units (design B).
    public var ghost: FormPose?

    /// Reps counted on the member's own movement (#969) where the form check couldn't follow (camera not on the
    /// guide's side): no score.
    public var formless = false

    public init() {}

    /// Average of the reps so far.
    public var score: Int? { reps.isEmpty || formless ? nil : Int((Double(reps.map(\.score).reduce(0, +)) / Double(reps.count)).rounded()) }
    public var match: Int? { reps.last?.match }
}

public struct FormAnalyzer: Sendable {
    public let model: FormModel
    public private(set) var live = FormLive()

    private var smooth: Double?
    private var moving = false
    private var current: FormRep?
    private var repStarted: Double = 0
    /// Last time the member was at the start position.
    private var lastAtStart: Double?
    /// Furthest from the start since the last rep ended (lockout check).
    private var topMin: Double = 0
    private var lastSeen: Double = -.infinity
    private var facing: Double = 1
    private var bodyLength: Double = 0
    private var sideRange: [Bool: ClosedRange<Double>] = [:]
    private var frames: [FormPose] = []
    private var replays: [Int: [FormPose]] = [:]
    private var lastKept: Double = -.infinity

    /// Seconds without the whole body before the screen asks to step back.
    public static let lostAfter = 1.0
    /// Replay frames kept per second.
    static let replayRate = 15.0

    public init(model: FormModel) { self.model = model }

    public init?(exercise: Exercise) {
        guard let m = FormModel(exercise: exercise) else { return nil }
        self.init(model: m)
    }

    public var reps: [FormRep] { live.reps }

    /// Feed one frame (`time` in seconds). Nil pose = nobody found.
    @discardableResult
    public mutating func add(_ pose: FormPose?, at time: Double) -> FormLive {
        guard let pose, let angle = primaryAngle(pose) else {
            live.visible = time - lastSeen < Self.lostAfter
            if !live.visible {
                live.cue = FormCue(text: "Step into view, whole body in frame", symbol: "figure.stand", tone: .info, fault: nil)
                live.ghost = nil
            }
            return live
        }
        lastSeen = time
        live.visible = true
        if model.view == .side, let n = pose[.nose], let k = pose[.neck], abs(n.x - k.x) > 0.01 { facing = n.x > k.x ? 1 : -1 }
        if let l = pose.length { bodyLength = max(bodyLength, l) }

        let a0 = primaryTarget(0), a1 = primaryTarget(1)
        let raw = abs(a1 - a0) < 1 ? 0 : (angle - a0) / (a1 - a0)
        let p = smooth.map { $0 + (raw - $0) * 0.45 } ?? raw
        smooth = p
        live.progress = p

        if time - lastKept >= 1 / Self.replayRate {
            frames.append(pose)
            lastKept = time
        }
        let liveFaults = faults(in: pose, progress: p)
        if !moving {
            topMin = min(topMin, p)
            if p <= 0.15 { lastAtStart = time }
            // A rep starts from the start position: stepping into view half-way down (or, filming a whole session, the
            // move before) is not a rep (#957).
            if p > FormModel.Limit.repStart, lastAtStart != nil {
                if !live.reps.isEmpty && topMin > FormModel.Limit.lockout { live.reps[live.reps.count - 1].add(.noLockout) }
                moving = true
                repStarted = lastAtStart ?? time
                // Frames from the start of the move.
                frames = Array(frames.suffix(Int(max(1, (time - repStarted) * Self.replayRate) + 1)))
                current = FormRep(number: live.reps.count + 1, score: 100, match: 0, depth: p, seconds: 0, faults: [])
                peakPose = pose
            }
        }
        if moving, var r = current {
            if p >= r.depth {
                r.depth = p
                peakPose = pose
            }
            for (f, v) in liveFaults {
                r.add(f)
                switch f {
                case .torsoLean: r.torsoExtra = max(r.torsoExtra ?? 0, v)
                case .kneesIn: r.kneeWidth = min(r.kneeWidth ?? 1, v)
                case .hipsSag: r.sag = max(r.sag ?? 0, v)
                case .uneven: r.sideGap = max(r.sideGap ?? 0, v)
                default: break
                }
            }
            current = r
            if p < FormModel.Limit.repEnd { finishRep(at: time) }
        }

        live.checks = checks(pose, progress: p)
        live.warn = []
        live.bad = []
        for c in live.checks where c.status != .good {
            guard let l = FormPose.jointsFor(c.joint, left: true), let r = FormPose.jointsFor(c.joint, left: false) else { continue }
            if c.status == .off { live.bad.formUnion([l.1, r.1]) } else { live.warn.formUnion([l.1, r.1]) }
        }
        for (f, _) in liveFaults { live.bad.formUnion(Self.joints(of: f)) }
        live.cue = cue(liveFaults.map { $0.0 })
        live.ghost = ghost(over: pose, progress: p)
        return live
    }

    private var peakPose: FormPose?

    private mutating func finishRep(at time: Double) {
        guard var r = current else { return }
        moving = false
        current = nil
        topMin = smooth ?? 0
        r.seconds = time - repStarted
        if r.depth < FormModel.Limit.fullRange { r.add(.shallow) }
        if let min = model.minRepSeconds, r.seconds < min, model.faults.contains(.tooFast) { r.add(.tooFast) }
        r.match = peakPose.map { match($0) } ?? 0
        replays[r.number] = frames
        frames = []
        live.reps.append(r)
    }

    /// The set so far as a report.
    public func report(date: Date = .now) -> FormReport {
        let r = FormReport(exerciseId: model.exerciseId, date: date, reps: live.reps, worstReplay: [], replays: replays)
        var out = r
        if let w = r.worst { out.worstReplay = replays[w] ?? [] }
        return out
    }

    // MARK: Measures

    private func primaryTarget(_ progress: Double) -> Double {
        if model.unilateral, let side = refSide, let a = model.start.angle(model.primary, left: side), let b = model.peak.angle(model.primary, left: side) {
            return a + (b - a) * progress
        }
        return model.target(model.primary, at: progress) ?? 0
    }

    /// The guide side whose primary joint moves most (unilateral moves).
    private var refSide: Bool? {
        let l = model.start.angle(model.primary, left: true).flatMap { a in model.peak.angle(model.primary, left: true).map { abs($0 - a) } }
        let r = model.start.angle(model.primary, left: false).flatMap { a in model.peak.angle(model.primary, left: false).map { abs($0 - a) } }
        switch (l, r) {
        case let (l?, r?): return l >= r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return nil
        }
    }

    private mutating func primaryAngle(_ pose: FormPose) -> Double? {
        guard model.unilateral else { return pose.angle(model.primary) }
        // The working side is the one that has moved most so far.
        for left in [true, false] {
            if let a = pose.angle(model.primary, left: left) {
                let r = sideRange[left].map { min($0.lowerBound, a)...max($0.upperBound, a) } ?? a...a
                sideRange[left] = r
            }
        }
        let wl = sideRange[true].map { $0.upperBound - $0.lowerBound } ?? -1
        let wr = sideRange[false].map { $0.upperBound - $0.lowerBound } ?? -1
        let side = wl >= wr
        return pose.angle(model.primary, left: side) ?? pose.angle(model.primary)
    }

    /// Faults visible in this frame with their size.
    func faults(in pose: FormPose, progress p: Double) -> [(FormFault, Double)] {
        var out: [(FormFault, Double)] = []
        let f = model.faults
        if f.contains(.torsoLean), p > 0.5, let lean = pose.torsoLean, let ref = model.guidePose(at: p).torsoLean,
           lean - ref > FormModel.Limit.torsoLean {
            out.append((.torsoLean, lean - ref))
        }
        // Knee width against ankle width, compared with the guide's at the same point: a wide stance has its knees
        // inside the feet by design.
        if f.contains(.kneesIn), p > 0.5, let ratio = Self.kneeRatio(pose), let ref = Self.kneeRatio(model.guidePose(at: p)), ref > 0.05 {
            let share = ratio / ref
            if share < FormModel.Limit.kneeWidth { out.append((.kneesIn, share)) }
        }
        if f.contains(.hipsSag), let s = pose.shoulders, let h = pose.hips, let a = pose.ankles, abs(a.x - s.x) > 0.05 {
            let t = (h.x - s.x) / (a.x - s.x)
            let lineY = s.y + (a.y - s.y) * t
            let len = ((a - s) * (a - s)).sum().squareRoot()
            let sag = (lineY - h.y) / len
            if sag > FormModel.Limit.hipSag { out.append((.hipsSag, sag)) }
        }
        if f.contains(.uneven), let l = pose.angle(model.primary, left: true), let r = pose.angle(model.primary, left: false),
           abs(l - r) > FormModel.Limit.uneven {
            out.append((.uneven, abs(l - r)))
        }
        return out
    }

    /// Knee width ÷ ankle width; nil when the feet are together.
    static func kneeRatio(_ pose: FormPose) -> Double? {
        guard let lk = pose[.leftKnee], let rk = pose[.rightKnee], let la = pose[.leftAnkle], let ra = pose[.rightAnkle] else { return nil }
        let ankles = abs(la.x - ra.x), len = pose.length ?? 1
        guard ankles > 0.04 * len else { return nil }
        return abs(lk.x - rk.x) / ankles
    }

    private static func joints(of f: FormFault) -> [FormJoint] {
        switch f {
        case .kneesIn: [.leftKnee, .rightKnee]
        case .torsoLean: [.leftShoulder, .rightShoulder, .neck]
        case .hipsSag: [.leftHip, .rightHip]
        default: []
        }
    }

    private func checks(_ pose: FormPose, progress p: Double) -> [FormAngleCheck] {
        model.watched.compactMap { j -> FormAngleCheck? in
            guard let v = pose.angle(j) else { return nil }
            // The counted joint is measured against where it should get to; the others against the guide at this point.
            guard let t = j == model.primary ? model.target(j, at: 1) : model.target(j, at: p) else { return nil }
            let goneFar = j == model.primary && ((model.primaryFlexes && v <= t) || (!model.primaryFlexes && v >= t))
            let d = goneFar ? 0 : abs(v - t)
            let s: FormAngleCheck.Status = d <= FormModel.Limit.angleOK ? .good : d <= FormModel.Limit.angleOK * 2 ? .close : .off
            // Between reps the counted joint is far from the bottom by design: no colour.
            let status = j == model.primary && p < FormModel.Limit.repStart ? .good : s
            return FormAngleCheck(joint: j, degrees: Int(v.rounded()), target: Int(t.rounded()), status: status)
        }
    }

    /// 0–100: how close the watched joints are to the guide's main position.
    func match(_ pose: FormPose) -> Int {
        let d: [Double] = model.watched.compactMap { j -> Double? in
            guard let v = pose.angle(j), let t = model.target(j, at: 1) else { return nil }
            return max(0, 1 - abs(v - t) / FormModel.Limit.matchZero)
        }
        return d.isEmpty ? 0 : Int((d.reduce(0, +) / Double(d.count) * 100).rounded())
    }

    private func cue(_ now: [FormFault]) -> FormCue? {
        if let f = now.max(by: { $0.penalty < $1.penalty }) { return model.cue(f) }
        guard let last = live.reps.last else {
            return FormCue(text: moving ? "Keep going" : "Start when ready", symbol: "figure.strengthtraining.traditional", tone: .info, fault: nil)
        }
        if let f = last.faults.max(by: { $0.penalty < $1.penalty }) { return model.cue(f) }
        return FormCue(text: "Good rep", symbol: "checkmark", tone: .good, fault: nil)
    }

    /// The guide's pose at this point of the rep, scaled to the member's body, feet on their feet, facing their way.
    func ghost(over pose: FormPose, progress p: Double) -> FormPose? {
        guard let anchor = pose.ankles, bodyLength > 0 else { return nil }
        let guide = model.guidePose(at: p)
        let refLength = [model.start.length, model.peak.length].compactMap { $0 }.max() ?? 0
        guard refLength > 0, let refAnchor = guide.ankles else { return nil }
        let s = bodyLength / refLength
        let flip = model.view == .side ? facing : 1
        return guide.mapped { q in
            let d = q - refAnchor
            return anchor + SIMD2(d.x * s * flip, d.y * s)
        }
    }
}

// MARK: - Made-up member (tests, demo screens)

public enum FormDemo {
    /// A member doing `reps` reps of the exercise in front of a phone, as the camera would see them: the guide's own
    /// poses, scaled into a 9:16 frame, with chosen reps going wrong. `period` seconds a rep, 30 frames a second.
    public static func frames(_ model: FormModel, reps: Int, period: Double = 2.4, shallow: Set<Int> = [], lean: Set<Int> = [],
                              kneesIn: Set<Int> = [], rest: Double = 0.6) -> [(Double, FormPose)] {
        var out: [(Double, FormPose)] = []
        let fps = 30.0
        let total = Double(reps) * (period + rest) + rest
        var t = 0.0
        while t <= total {
            let cycle = period + rest
            let n = Int(t / cycle) + 1
            let inRep = t.truncatingRemainder(dividingBy: cycle) - rest
            var p = 0.0
            if inRep > 0, n <= reps { p = (1 - cos(2 * .pi * inRep / period)) / 2 }
            if shallow.contains(n) { p *= 0.6 }
            out.append((t, pose(model, progress: p, lean: lean.contains(n) ? 28 * p : 0, kneesIn: kneesIn.contains(n) ? p : 0)))
            t += 1 / fps
        }
        return out
    }

    /// One frame of the made-up member.
    public static func pose(_ model: FormModel, progress: Double, lean: Double = 0, kneesIn: Double = 0) -> FormPose {
        var g = model.guidePose(at: progress)
        if lean != 0, let h = g.hips {
            // Fold the trunk forward around the hips.
            let a = -lean * .pi / 180
            let upper: [FormJoint] = [.nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
            for j in upper {
                guard let q = g[j] else { continue }
                let d = q - h
                g.points[j] = h + SIMD2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a))
            }
        }
        if kneesIn > 0, let l = g[.leftKnee], let r = g[.rightKnee] {
            let c = (l + r) / 2
            g.points[.leftKnee] = c + (l - c) * (1 - 0.5 * kneesIn)
            g.points[.rightKnee] = c + (r - c) * (1 - 0.5 * kneesIn)
        }
        let len = [model.start.length, model.peak.length].compactMap { $0 }.max() ?? 190
        let s = 0.62 / len
        let anchor = model.start.ankles ?? .zero
        return g.mapped { q in SIMD2(0.28 + (q.x - anchor.x) * s, 0.12 + (q.y - anchor.y) * s) }
    }
}
