import Foundation

/// A sport session's GPS track from Apple Health (#416, session page A + C): route, elevation, speed, laps.
public struct SportTrack: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var lat: Double
        public var lon: Double
        /// Metres above sea level.
        public var alt: Double
        /// Metres per second.
        public var speed: Double
        public var time: Date
        /// Heart rate (bpm) nearest this point, when Health has one (#445 map colour).
        public var hr: Double?

        public init(lat: Double, lon: Double, alt: Double, speed: Double, time: Date, hr: Double? = nil) {
            self.lat = lat
            self.lon = lon
            self.alt = alt
            self.speed = speed
            self.time = time
            self.hr = hr
        }
    }

    /// A lap or segment the recording app saved (Hyrox stations, intervals).
    public struct Lap: Equatable, Sendable {
        public var start: Date
        public var end: Date
        public var minutes: Double { end.timeIntervalSince(start) / 60 }

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    /// One downhill run (ski / snowboard), as indexes into `points`.
    public struct Run: Equatable, Sendable {
        public var from: Int
        public var to: Int
        /// Metres dropped.
        public var drop: Double
        /// Fastest speed, km/h.
        public var topKmh: Double
        /// Length along the ground and time on it (#445).
        public var meters: Double = 0
        public var seconds: TimeInterval = 0
        public var avgKmh: Double { seconds > 0 ? meters / seconds * 3.6 : 0 }
    }

    public var points: [Point]
    public var laps: [Lap]

    public init(points: [Point], laps: [Lap] = []) {
        self.points = points
        self.laps = laps
    }

    /// At most `max` points, evenly picked (first and last kept), so maps and charts stay light.
    public func thinned(max: Int = 600) -> SportTrack {
        guard points.count > max, max > 1 else { return self }
        let step = Double(points.count - 1) / Double(max - 1)
        return SportTrack(points: (0..<max).map { points[Int((Double($0) * step).rounded())] }, laps: laps)
    }

    /// Fastest speed in km/h, as the median of 3 neighbours so a single GPS jump doesn't count.
    public var topKmh: Double? {
        guard points.count >= 3 else { return points.map(\.speed).max().map { $0 * 3.6 } }
        return (1..<(points.count - 1)).map { i in
            [points[i - 1].speed, points[i].speed, points[i + 1].speed].sorted()[1]
        }.max().map { $0 * 3.6 }
    }

    /// Metres climbed and dropped, ignoring changes under `noise` metres (GPS altitude wobbles).
    public func vertical(noise: Double = 3) -> (up: Double, down: Double) {
        guard var ref = points.first?.alt else { return (0, 0) }
        var up = 0.0, down = 0.0
        for p in points.dropFirst() {
            let d = p.alt - ref
            if abs(d) >= noise {
                if d > 0 { up += d } else { down -= d }
                ref = p.alt
            }
        }
        return (up, down)
    }

    public var highest: Double? { points.map(\.alt).max() }

    /// Downhill runs: a drop of at least `minDrop` metres ends when the track climbs `lift` metres again (a lift).
    public func runs(minDrop: Double = 40, lift: Double = 25) -> [Run] {
        guard !points.isEmpty else { return [] }
        let dist = distances
        var out: [Run] = []
        var top = 0, low = 0
        func close(_ end: Int) {
            let drop = points[top].alt - points[end].alt
            guard drop >= minDrop, end > top else { return }
            // The run starts when the descent does, not while waiting at the top (#445 day parts).
            var start = top
            while start < end - 1 && points[start + 1].alt >= points[top].alt - 2 { start += 1 }
            let fastest = points[start...end].map(\.speed).max() ?? 0
            out.append(Run(from: start, to: end, drop: drop, topKmh: fastest * 3.6, meters: dist[end] - dist[start],
                           seconds: points[end].time.timeIntervalSince(points[start].time)))
        }
        for i in points.indices.dropFirst() {
            if points[i].alt < points[low].alt { low = i }
            if points[i].alt - points[low].alt >= lift {
                // Climbing again: the run (if any) ended at the low point.
                if low > top { close(low) }
                top = i
                low = i
            } else if points[i].alt > points[top].alt && low == top {
                top = i
                low = i
            }
        }
        if low > top { close(low) }
        return out
    }

    /// Index of the point nearest `time`.
    public func index(near time: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.indices.min { abs(points[$0].time.timeIntervalSince(time)) < abs(points[$1].time.timeIntervalSince(time)) }
    }
}

// MARK: - Maps (#445): ski day parts, route profile, splits

extension SportTrack {
    /// Ground distance in metres between two points.
    public static func metres(_ a: Point, _ b: Point) -> Double {
        let r = 6_371_000.0, rad = Double.pi / 180
        let dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * rad) * cos(b.lat * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// Metres from the start at each point.
    public var distances: [Double] {
        var out: [Double] = []
        out.reserveCapacity(points.count)
        for i in points.indices { out.append(i == 0 ? 0 : out[i - 1] + Self.metres(points[i - 1], points[i])) }
        return out
    }

    public var meters: Double { distances.last ?? 0 }

    /// Climb in % at each point, over `window` metres around it (up positive), so GPS wobble doesn't spike.
    public func grades(window: Double = 80) -> [Double] {
        let d = distances
        var lo = 0, hi = 0
        return points.indices.map { i in
            while lo < i && d[i] - d[lo] > window / 2 { lo += 1 }
            if hi < i { hi = i }
            while hi < points.count - 1 && d[hi] - d[i] < window / 2 { hi += 1 }
            let run = d[hi] - d[lo]
            guard run >= 20 else { return 0 }
            return max(-60, min(60, (points[hi].alt - points[lo].alt) / run * 100))
        }
    }

    /// Steepest climb in %, nil on flat or short tracks.
    public var maxGrade: Double? {
        let g = grades().max() ?? 0
        return g >= 1 ? g : nil
    }

    /// Time spent moving faster than `minSpeed` m/s (stops, photos and huts left out).
    public func movingSeconds(minSpeed: Double = 0.5) -> TimeInterval {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in points.indices.dropFirst() {
            let dt = points[i].time.timeIntervalSince(points[i - 1].time)
            guard dt > 0 else { continue }
            if Self.metres(points[i - 1], points[i]) / dt >= minSpeed { total += dt }
        }
        return total
    }

    public var seconds: TimeInterval {
        guard let a = points.first?.time, let b = points.last?.time else { return 0 }
        return b.timeIntervalSince(a)
    }

    /// One split (a kilometre by default): its time and the metres climbed in it.
    public struct Split: Equatable, Sendable {
        public var index: Int
        public var meters: Double
        public var seconds: TimeInterval
        public var climb: Double
        /// Seconds per km.
        public var pace: TimeInterval { meters > 0 ? seconds / meters * 1000 : 0 }
    }

    /// Splits every `every` metres; the last, shorter one is kept when at least 100 m.
    public func splits(every: Double = 1000, noise: Double = 3) -> [Split] {
        guard points.count > 1 else { return [] }
        let d = distances
        var out: [Split] = []
        var startTime = points[0].time, startDist = 0.0, climb = 0.0, ref = points[0].alt
        for i in points.indices.dropFirst() {
            let delta = points[i].alt - ref
            if abs(delta) >= noise {
                if delta > 0 { climb += delta }
                ref = points[i].alt
            }
            while d[i] - startDist >= every {
                // Time where the split line was crossed, between the two fixes.
                let seg = d[i] - d[i - 1]
                let f = seg > 0 ? (startDist + every - d[i - 1]) / seg : 1
                let at = points[i - 1].time.addingTimeInterval(points[i].time.timeIntervalSince(points[i - 1].time) * f)
                out.append(Split(index: out.count + 1, meters: every, seconds: at.timeIntervalSince(startTime), climb: climb))
                startTime = at
                startDist += every
                climb = 0
            }
        }
        let rest = d[d.count - 1] - startDist
        if rest >= 100 {
            out.append(Split(index: out.count + 1, meters: rest, seconds: points[points.count - 1].time.timeIntervalSince(startTime), climb: climb))
        }
        return out
    }

    /// A stretch of a ski day.
    public struct Part: Equatable, Sendable {
        public enum Kind: Sendable { case ride, lift, rest }
        public var kind: Kind
        /// Indexes into `points`.
        public var from: Int
        public var to: Int
        public var seconds: TimeInterval
    }

    /// The day split into riding (the runs), lifts (going up between them) and breaks (stopped `restMin` seconds or more).
    public func dayParts(restSpeed: Double = 0.8, restMin: TimeInterval = 180) -> [Part] {
        guard points.count > 1 else { return [] }
        var kind = [Part.Kind](repeating: .lift, count: points.count - 1)
        for r in runs() { for i in r.from..<r.to { kind[i] = .ride } }
        // Long slow stretches outside the runs are breaks.
        var i = 0
        while i < kind.count {
            guard kind[i] != .ride, segmentSpeed(i) < restSpeed else { i += 1; continue }
            var j = i
            while j < kind.count && kind[j] != .ride && segmentSpeed(j) < restSpeed { j += 1 }
            if points[j].time.timeIntervalSince(points[i].time) >= restMin { for k in i..<j { kind[k] = .rest } }
            i = j
        }
        var out: [Part] = []
        for (i, k) in kind.enumerated() {
            let dt = points[i + 1].time.timeIntervalSince(points[i].time)
            if var last = out.last, last.kind == k {
                last.to = i + 1
                last.seconds += dt
                out[out.count - 1] = last
            } else {
                out.append(Part(kind: k, from: i, to: i + 1, seconds: dt))
            }
        }
        return out
    }

    /// Total seconds riding, on lifts and on breaks.
    public func dayTotals() -> (ride: TimeInterval, lift: TimeInterval, rest: TimeInterval) {
        dayParts().reduce(into: (0.0, 0.0, 0.0)) { t, p in
            switch p.kind {
            case .ride: t.0 += p.seconds
            case .lift: t.1 += p.seconds
            case .rest: t.2 += p.seconds
            }
        }
    }

    /// Metres per second between point `i` and the next.
    private func segmentSpeed(_ i: Int) -> Double {
        let dt = points[i + 1].time.timeIntervalSince(points[i].time)
        return dt > 0 ? Self.metres(points[i], points[i + 1]) / dt : 0
    }
}
