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

        public init(lat: Double, lon: Double, alt: Double, speed: Double, time: Date) {
            self.lat = lat
            self.lon = lon
            self.alt = alt
            self.speed = speed
            self.time = time
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
        var out: [Run] = []
        var top = 0, low = 0
        func close(_ end: Int) {
            let drop = points[top].alt - points[end].alt
            guard drop >= minDrop, end > top else { return }
            let fastest = points[top...end].map(\.speed).max() ?? 0
            out.append(Run(from: top, to: end, drop: drop, topKmh: fastest * 3.6))
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
