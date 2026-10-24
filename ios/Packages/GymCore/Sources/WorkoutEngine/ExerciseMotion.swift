/// How an illustrated exercise moves (#229): the path of the point that carries the movement (bar / hand,
/// foot, hips…) across the illustration frames, and what each half of a repetition is called. Generated per
/// exercise by ios/Tools/illustrations (`ExerciseMotion.table`); the app draws the path, a dot following it
/// and the tempo chip over the picture while the movement plays.
public struct ExerciseMotion: Sendable, Equatable {
    /// Label of start → end ("UP", "DOWN", "PUSH", "PULL", "IN", "OUT").
    public let first: String
    /// Label of end → start.
    public let second: String
    /// True when start → end is the working (concentric) half.
    public let effortFirst: Bool
    /// One point per frame, normalised to the picture (0…1, origin top-left), flattened x, y, x, y…
    /// Empty when nothing travels far enough to draw (holds, stretches).
    public let path: [Double]
    /// One whole cycle per play (#719): a gait, a carry or a machine that turns, drawn so the last frame is the first
    /// again. Played forward and wrapped, never backwards; `first` is half a cycle ("STEP"), `second` the whole
    /// one ("STRIDE"), and there is no working half.
    public let cyclic: Bool

    public init(_ first: String, _ second: String, effortFirst: Bool, path: [Double], cyclic: Bool = false) {
        self.first = first
        self.second = second
        self.effortFirst = effortFirst
        self.path = path
        self.cyclic = cyclic
    }

    /// The path as points, one per frame.
    public var points: [(x: Double, y: Double)] {
        stride(from: 0, to: path.count - 1, by: 2).map { (path[$0], path[$0 + 1]) }
    }

    /// Point at a fractional frame position (0 … frames - 1), straight between neighbouring frames.
    public func point(at frame: Double) -> (x: Double, y: Double)? {
        let pts = points
        guard !pts.isEmpty else { return nil }
        let f = min(max(frame, 0), Double(pts.count - 1))
        let i = min(Int(f), pts.count - 1)
        let j = min(i + 1, pts.count - 1)
        let k = f - Double(i)
        return (pts[i].x + (pts[j].x - pts[i].x) * k, pts[i].y + (pts[j].y - pts[i].y) * k)
    }

    /// One half of a repetition as shown on the tempo chip.
    public struct Phase: Sendable, Equatable {
        public let label: String
        /// Seconds the half takes.
        public let seconds: Double
        /// The working (concentric) half.
        public let effort: Bool
        /// Chip text, e.g. "UP 1s", "DOWN 2s", "UP FAST".
        public let text: String
    }

    /// Start → end and end → start for an exercise of `category`. Strength: work 1 s, return 2 s; power: fast
    /// work (0.6 s), 1.4 s return. Other categories move evenly (1.5 s each way) and show no tempo (`showsTempo`).
    /// A cyclic movement: the two halves of one cycle at an even pace (a stride 0.9 s, a walking step 1.2 s), both
    /// labelled with the whole cycle.
    public func phases(_ category: Category) -> (Phase, Phase) {
        if cyclic {
            let half = (category == .cardio || category == .power ? 0.9 : 1.2) / 2
            let p = Phase(label: second, seconds: half, effort: true, text: second)
            return (p, p)
        }
        let (work, back, fast): (Double, Double, Bool) = switch category {
        case .strength: (1, 2, false)
        case .power: (0.6, 1.4, true)
        default: (1.5, 1.5, false)
        }
        func phase(_ label: String, _ effort: Bool) -> Phase {
            let s = effort ? work : back
            let text = effort && fast ? "\(label) FAST" : "\(label) \(Self.seconds(s))"
            return Phase(label: label, seconds: s, effort: effort, text: text)
        }
        return (phase(first, effortFirst), phase(second, !effortFirst))
    }

    /// Whether the tempo chip shows for `category` (lifting only; mobility, stretches, cardio and warm-ups just move).
    public static func showsTempo(_ category: Category) -> Bool {
        category == .strength || category == .power
    }

    static func seconds(_ s: Double) -> String {
        let tenths = Int((s * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)s" : "\(tenths / 10).\(tenths % 10)s"
    }
}

extension Exercise {
    /// The movement data of the exercise's illustration; nil without one (custom exercises).
    public var motion: ExerciseMotion? { ExerciseMotion.table[id] }
}

/// Timeline of one play of the movement (#236): a continuous frame position over time, so the app can draw
/// it on a display-linked timeline (the lower frame opaque, the next one blended over it by the fraction) with
/// no per-step state changes that could flash. Each rep runs start → end at `out`, holds, end → start at
/// `back`, holds. A play starting away from frame 0 first glides there (`lead`), and one ending away from
/// `rest` glides back (`settle`). `cyclic` (#719): each rep runs start → end in `out + back` without holds and the
/// next one starts over at frame 0 (the same picture as the last), so a gait keeps going forward.
public struct MotionPlayback: Sendable, Equatable {
    public struct State: Sendable, Equatable {
        /// Fractional frame (0 … frames - 1).
        public let position: Double
        /// Rep being played (1-based).
        public let rep: Int
        /// True while in (or holding after) the start → end half.
        public let outbound: Bool
        /// Progress through the current half (0 … 1).
        public let halfProgress: Double
    }

    struct Segment: Sendable, Equatable {
        let from: Double, to: Double, duration: Double
        let rep: Int, outbound: Bool
        /// Moving half of a rep (progress follows time); holds show 1, lead / settle 0.
        let half: Bool
        let held: Bool
    }

    public let cycles: Int
    let segments: [Segment]
    /// Seconds the whole play takes.
    public let duration: Double

    public init(frames: Int, cycles: Int, out: Double, back: Double, hold: Double, from start: Double = 0,
                rest: Double = 0, lead: Double = 0.25, settle: Double = 0.3, cyclic: Bool = false) {
        let last = Double(max(frames - 1, 0))
        var s: [Segment] = []
        // A cycle glides on forward to its end, which is its start.
        if start != 0 {
            s.append(Segment(from: start, to: cyclic ? last : 0, duration: lead, rep: 1, outbound: true, half: false, held: false))
        }
        for r in 1...max(cycles, 1) {
            if cyclic {
                s.append(Segment(from: 0, to: last, duration: out + back, rep: r, outbound: true, half: true, held: false))
                continue
            }
            s.append(Segment(from: 0, to: last, duration: out, rep: r, outbound: true, half: true, held: false))
            s.append(Segment(from: last, to: last, duration: hold, rep: r, outbound: true, half: false, held: true))
            s.append(Segment(from: last, to: 0, duration: back, rep: r, outbound: false, half: true, held: false))
            s.append(Segment(from: 0, to: 0, duration: hold, rep: r, outbound: false, half: false, held: true))
        }
        if rest != 0 {
            s.append(Segment(from: 0, to: rest, duration: settle, rep: max(cycles, 1), outbound: false, half: false, held: false))
        }
        self.cycles = max(cycles, 1)
        segments = s
        duration = s.reduce(0) { $0 + $1.duration }
    }

    /// State `t` seconds after the play started; nil once it has finished (or before it starts).
    public func state(at t: Double) -> State? {
        guard t >= 0, t < duration else { return nil }
        var t0 = 0.0
        for seg in segments {
            if t < t0 + seg.duration {
                let k = seg.duration > 0 ? (t - t0) / seg.duration : 1
                return State(position: seg.from + (seg.to - seg.from) * k, rep: seg.rep, outbound: seg.outbound,
                             halfProgress: seg.half ? k : (seg.held ? 1 : 0))
            }
            t0 += seg.duration
        }
        return nil
    }

    /// Lower frame and how much of the next frame is blended over it at `position` (`frames` frames). With
    /// `window` < 1 (#241) each step holds the lower frame and only dissolves to the next one over the last
    /// `window` of the step (smoothstep), so two poses are rarely seen half-transparent on top of each other.
    public static func blend(_ position: Double, frames: Int, window: Double = 1) -> (lower: Int, upper: Double) {
        let last = max(frames - 1, 0)
        let p = min(max(position, 0), Double(last))
        let lower = min(Int(p.rounded(.down)), last)
        guard lower < last else { return (lower, 0) }
        var w = p - Double(lower)
        if window < 1 {
            w = max(0, (w - (1 - window)) / max(window, 1e-6))
            w = w * w * (3 - 2 * w)
        }
        return (lower, w)
    }

    /// Part of each frame step spent dissolving to the next frame in the app (#241): a quick switch.
    public static let switchWindow = 0.2
}
