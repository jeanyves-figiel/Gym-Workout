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

    public init(_ first: String, _ second: String, effortFirst: Bool, path: [Double]) {
        self.first = first
        self.second = second
        self.effortFirst = effortFirst
        self.path = path
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
    public func phases(_ category: Category) -> (Phase, Phase) {
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
