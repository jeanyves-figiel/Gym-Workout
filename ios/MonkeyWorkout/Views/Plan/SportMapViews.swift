import Charts
import MapKit
import SwiftUI
import WorkoutEngine

// Sport maps (#445, design A + B): ski day with runs vs lifts, route profile for hikes / rides / runs.
// Routes come from Apple Health and stay on this iPhone; nothing here is sent anywhere.

extension Sport {
    /// Runs split at lifts, vertical counted down.
    var downhill: Bool { self == .snowboard || self == .ski }
    /// Speed reads better than pace.
    var showsSpeed: Bool { [.roadBike, .mountainBike, .snowboard, .ski].contains(self) }
}

/// What colours the route of a hike, ride or run (design B).
enum RouteColour: String, CaseIterable, Identifiable {
    case speed = "Speed", climb = "Climb", heart = "HR"
    var id: String { rawValue }
}

enum SportMapStyle {
    /// One colour per run, cycled (design A).
    static let runColors = [0xFF3D8B, 0x00C7FF, 0xFFB800, 0x7DFFB0, 0xB36BFF].map { Color(hex: $0) }
    static let bands = [Color(hex: 0x7DFFB0), Color(hex: 0xFFB800), Color(hex: 0xFF3D3D)]
    static let descent = Color(hex: 0x3D9BFF)
    static let lift = Color(hex: 0xA0A8B8)
    static let rest = Color(hex: 0xFFB800)

    static func runColor(_ i: Int) -> Color { runColors[i % runColors.count] }

    /// Climb colour: blue going down, green flat, amber steady, red steep.
    static func climb(_ grade: Double) -> Color {
        grade < -4 ? descent : grade < 4 ? bands[0] : grade < 10 ? bands[1] : bands[2]
    }

    static func clock(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d", t / 3600, t / 60 % 60) : "\(t / 60)′"
    }

    static func pace(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d /km", t / 60, t % 60)
    }
}

/// The route: ski runs each in their own colour with lifts dashed, or a hike / ride coloured by speed, climb or heart rate.
/// Tapping a run zooms to it; the dot follows the elevation chart's scrub.
struct SportRouteMap: View {
    let track: SportTrack
    let sport: Sport
    let source: String
    let minutes: Int
    let scrub: Int?
    let runs: [SportTrack.Run]
    let selected: Int?
    @Binding var colour: RouteColour
    @State private var camera: MapCameraPosition = .automatic

    private struct Piece: Identifiable {
        let id: Int
        let coords: [CLLocationCoordinate2D]
        let color: Color
        var dashed = false
        var dim = false
    }

    private func coord(_ i: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: track.points[i].lat, longitude: track.points[i].lon)
    }

    private var hasHeart: Bool { track.points.contains { $0.hr != nil } }

    /// Consecutive points of the same colour become one polyline (sharing the joint point).
    private func merged(_ colors: [Color]) -> [Piece] {
        var out: [Piece] = []
        var current: [CLLocationCoordinate2D] = []
        var currentColor = colors.first ?? .white
        for i in track.points.indices {
            current.append(coord(i))
            if colors[i] != currentColor && current.count > 1 {
                out.append(Piece(id: out.count, coords: current, color: currentColor))
                current = [coord(i)]
                currentColor = colors[i]
            }
        }
        if current.count > 1 { out.append(Piece(id: out.count, coords: current, color: currentColor)) }
        return out
    }

    private var pieces: [Piece] {
        if sport.downhill && !runs.isEmpty {
            // Runs in colour, everything between (lifts, walks, breaks) dashed grey.
            var out: [Piece] = []
            var cursor = 0
            for (n, r) in runs.enumerated() {
                if r.from > cursor {
                    out.append(Piece(id: out.count, coords: (cursor...r.from).map(coord), color: SportMapStyle.lift, dashed: true, dim: selected != nil))
                }
                out.append(Piece(id: out.count, coords: (r.from...r.to).map(coord), color: SportMapStyle.runColor(n), dim: selected.map { $0 != n } ?? false))
                cursor = r.to
            }
            if cursor < track.points.count - 1 {
                out.append(Piece(id: out.count, coords: (cursor..<track.points.count).map(coord), color: SportMapStyle.lift, dashed: true, dim: selected != nil))
            }
            return out
        }
        switch colour {
        case .climb:
            return merged(track.grades().map(SportMapStyle.climb))
        case .heart where hasHeart:
            let top = max(track.points.compactMap(\.hr).max() ?? 1, 1)
            return merged(track.points.map { p in
                let f = (p.hr ?? 0) / top
                return SportMapStyle.bands[f < 0.75 ? 0 : f < 0.88 ? 1 : 2]
            })
        default:
            let top = max(track.points.map(\.speed).max() ?? 1, 0.1)
            return merged(track.points.map { SportMapStyle.bands[min(2, Int($0.speed / top * 3))] })
        }
    }

    /// Region around points `from...to`, with a margin.
    private func region(_ from: Int, _ to: Int) -> MapCameraPosition {
        let pts = track.points[from...to]
        guard let minLat = pts.map(\.lat).min(), let maxLat = pts.map(\.lat).max(),
              let minLon = pts.map(\.lon).min(), let maxLon = pts.map(\.lon).max() else { return .automatic }
        let span = MKCoordinateSpan(latitudeDelta: max(0.004, (maxLat - minLat) * 1.5), longitudeDelta: max(0.004, (maxLon - minLon) * 1.5))
        return .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2), span: span))
    }

    var body: some View {
        Map(position: $camera) {
            ForEach(pieces) { p in
                MapPolyline(coordinates: p.coords)
                    .stroke(p.color.opacity(p.dim ? 0.3 : 1),
                            style: StrokeStyle(lineWidth: p.dashed ? 2.5 : 5, lineCap: .round, lineJoin: .round, dash: p.dashed ? [5, 4] : []))
            }
            if !track.points.isEmpty {
                Annotation("Start", coordinate: coord(0)) {
                    Circle().fill(Theme.lime).frame(width: 12, height: 12)
                }
            }
            if !sport.downhill, let top = track.points.indices.max(by: { track.points[$0].alt < track.points[$1].alt }),
               track.vertical().up >= 50 {
                Annotation("", coordinate: coord(top)) { Text("🚩").font(.system(size: 16)) }
            }
            if let i = scrub, track.points.indices.contains(i) {
                Annotation("", coordinate: coord(i)) {
                    Circle().fill(Theme.lime).frame(width: 16, height: 16).overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            Label("\(sport.short) · \(Climbs.duration(minutes)) · \(source)", systemImage: sport.symbol)
                .font(Theme.label(11)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(10)
        }
        .overlay(alignment: .bottomLeading) { legend.padding(10) }
        .overlay(alignment: .bottomTrailing) {
            if !sport.downhill {
                HStack(spacing: 4) {
                    ForEach(RouteColour.allCases.filter { $0 != .heart || hasHeart }) { c in
                        Button { colour = c } label: {
                            Text(c.rawValue).font(Theme.label(11))
                                .foregroundStyle(colour == c ? Theme.ink : .white)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(colour == c ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.black.opacity(0.55))))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .onChange(of: selected) { _, n in
            withAnimation(.easeInOut(duration: 0.4)) {
                camera = n.flatMap { runs.indices.contains($0) ? region(runs[$0].from, runs[$0].to) : nil } ?? .automatic
            }
        }
    }

    @ViewBuilder private var legend: some View {
        if sport.downhill, let n = selected, runs.indices.contains(n) {
            Text("Run \(n + 1) · \(Int(runs[n].drop.rounded())) m ↓").font(Theme.label(11)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(SportMapStyle.runColor(n)))
        } else if sport.downhill {
            HStack(spacing: 5) {
                Capsule().fill(LinearGradient(colors: SportMapStyle.runColors, startPoint: .leading, endPoint: .trailing)).frame(width: 22, height: 5)
                Text("runs").font(Theme.label(9))
                Capsule().stroke(SportMapStyle.lift, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 18, height: 3)
                Text("lifts").font(Theme.label(9))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.55)))
        } else {
            let (lo, hi, colors) = legendScale
            HStack(spacing: 4) {
                Text(lo).font(Theme.label(9))
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)).frame(width: 36, height: 5)
                Text(hi).font(Theme.label(9))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.55)))
        }
    }

    private var legendScale: (String, String, [Color]) {
        switch colour {
        case .climb: ("down", "steep", [SportMapStyle.descent] + SportMapStyle.bands)
        case .heart where hasHeart: ("easy", "max", SportMapStyle.bands)
        default: ("slow", "fast", SportMapStyle.bands)
        }
    }
}

/// Four bold tiles. Ski: vertical, runs, top speed, distance. Others: distance, ascent, moving time, heart rate or top speed.
struct SportStatTiles: View {
    let entry: SportEntry
    let track: SportTrack
    let runs: Int

    var body: some View {
        let v = track.vertical()
        let km = entry.distanceKm ?? track.meters / 1000
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            if entry.sport.downhill {
                tile("Vertical", "\(Int(v.down.rounded()).formatted())", "m", [0x3D59FF, 0x00C7FF])
                tile("Runs", "\(runs)", "", [0xFF3D8B, 0xFF9A5E])
                if let top = track.topKmh, top > 1 { tile("Top speed", "\(Int(top.rounded()))", "km/h", [0x00B86B, 0x7DFFB0]) }
                if km > 0 { tile("Distance", Self.km(km), "km", [0x00A3C4, 0x7DF9FF]) }
            } else {
                if km > 0 { tile("Distance", Self.km(km), "km", [0x00A3C4, 0x7DF9FF]) }
                tile("Ascent", "\(Int((entry.elevationM ?? v.up).rounded()).formatted())", "m", [0x3D59FF, 0x00C7FF])
                let moving = track.movingSeconds()
                if moving > 0 { tile("Moving", SportMapStyle.clock(moving), moving >= 3600 ? "h" : "", [0xFF5E3A, 0xFFB03D]) }
                if let hr = entry.avgHR {
                    tile("Avg HR", "\(Int(hr.rounded()))", "bpm", [0xFF3D8B, 0xFF9A5E])
                } else if let top = track.topKmh, top > 1 {
                    tile("Top speed", "\(Int(top.rounded()))", "km/h", [0xFF3D8B, 0xFF9A5E])
                }
            }
        }
    }

    static func km(_ d: Double) -> String { d >= 10 ? "\(Int(d.rounded()))" : String(format: "%.1f", d) }

    private func tile(_ label: String, _ value: String, _ unit: String, _ hex: [UInt32]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(Theme.label(10)).tracking(1.2).opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.display(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(Theme.label(11)).opacity(0.85) }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: hex.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

/// Your day (design A): a bar of riding, lifts and breaks in order, with the totals.
struct SkiDayCard: View {
    let track: SportTrack

    var body: some View {
        let parts = track.dayParts()
        let totals = track.dayTotals()
        let all = max(1, totals.ride + totals.lift + totals.rest)
        VStack(alignment: .leading, spacing: 8) {
            Text("Your day").eyebrow()
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        Rectangle().fill(color(p.kind)).frame(width: max(1, geo.size.width * p.seconds / all))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            HStack(spacing: 6) {
                chip("Riding \(SportMapStyle.clock(totals.ride))", color(.ride), dark: false)
                chip("Lifts \(SportMapStyle.clock(totals.lift))", color(.lift), dark: true)
                if totals.rest >= 60 { chip("Breaks \(SportMapStyle.clock(totals.rest))", color(.rest), dark: true) }
            }
        }
        .card(padding: 14)
    }

    private func color(_ k: SportTrack.Part.Kind) -> Color {
        switch k {
        case .ride: SportMapStyle.runColors[0]
        case .lift: SportMapStyle.lift.opacity(0.6)
        case .rest: SportMapStyle.rest
        }
    }

    private func chip(_ text: String, _ c: Color, dark: Bool) -> some View {
        Text(text).font(Theme.label(11)).foregroundStyle(dark ? Theme.ink : .white)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(c))
    }
}

/// Elevation by distance (hikes, rides, runs: steep parts hot) or by time (ski day). Drag to scrub; the map dot follows.
struct SportElevationChart: View {
    let track: SportTrack
    let byDistance: Bool
    @Binding var scrub: Int?
    @State private var pickedTime: Date?
    @State private var pickedKm: Double?

    var body: some View {
        let dist = track.distances
        let grades = track.grades()
        let distance = byDistance && (dist.last ?? 0) >= 200
        let low = (track.points.map(\.alt).min() ?? 0) - 10
        let picked = scrub.flatMap { track.points.indices.contains($0) ? $0 : nil }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let i = picked {
                    Text(distance ? String(format: "km %.1f", dist[i] / 1000) : track.points[i].time.formatted(date: .omitted, time: .shortened)).eyebrow()
                    Spacer()
                    Text(readout(i, grades[i], distance)).font(Theme.label(13)).foregroundStyle(Theme.lime)
                } else {
                    Text(distance ? "Elevation · by km" : "Elevation").eyebrow()
                    Spacer()
                    Text("Drag to replay").font(Theme.label(11)).foregroundStyle(Theme.muted)
                }
            }
            chart(distance: distance, dist: dist, grades: grades, low: low, picked: picked)
                .chartYScale(domain: low...((track.highest ?? low) + 10))
                .frame(height: 130)
        }
        .card(padding: 14)
        .onChange(of: pickedTime) { _, t in scrub = t.flatMap { track.index(near: $0) } }
        .onChange(of: pickedKm) { _, km in
            scrub = km.map { k in dist.indices.min { abs(dist[$0] - k * 1000) < abs(dist[$1] - k * 1000) } ?? 0 }
        }
    }

    private func readout(_ i: Int, _ grade: Double, _ distance: Bool) -> String {
        let p = track.points[i]
        let alt = "\(Int(p.alt.rounded()).formatted()) m"
        return distance ? "\(alt) · \(Int(grade.rounded())) %" : "\(alt) · \(Int((p.speed * 3.6).rounded())) km/h"
    }

    @ViewBuilder
    private func chart(distance: Bool, dist: [Double], grades: [Double], low: Double, picked: Int?) -> some View {
        if distance {
            // Steep parts hot: the line and area take the climb colour along the way.
            let total = max(dist.last ?? 1, 1)
            let step = max(1, track.points.count / 40)
            let stops = stride(from: 0, to: track.points.count, by: step).map {
                Gradient.Stop(color: SportMapStyle.climb(grades[$0]), location: dist[$0] / total)
            }
            let line = LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
            let area = LinearGradient(stops: stops.map { Gradient.Stop(color: $0.color.opacity(0.4), location: $0.location) },
                                      startPoint: .leading, endPoint: .trailing)
            Chart {
                ForEach(track.points.indices, id: \.self) { i in
                    AreaMark(x: .value("km", dist[i] / 1000), yStart: .value("Base", low), yEnd: .value("Altitude", track.points[i].alt))
                        .foregroundStyle(area)
                    LineMark(x: .value("km", dist[i] / 1000), y: .value("Altitude", track.points[i].alt))
                        .foregroundStyle(line)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                if let i = picked {
                    RuleMark(x: .value("km", dist[i] / 1000)).foregroundStyle(Theme.lime).lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXScale(domain: 0...(total / 1000))
            .chartXSelection(value: $pickedKm)
        } else {
            Chart {
                ForEach(track.points.indices, id: \.self) { i in
                    let p = track.points[i]
                    AreaMark(x: .value("Time", p.time), yStart: .value("Base", low), yEnd: .value("Altitude", p.alt))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0x3D59FF).opacity(0.8), Color(hex: 0x3D59FF).opacity(0.05)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", p.time), y: .value("Altitude", p.alt))
                        .foregroundStyle(Color(hex: 0x7DF9FF))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let i = picked {
                    RuleMark(x: .value("Time", track.points[i].time)).foregroundStyle(Theme.lime).lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXAxis(.hidden)
            .chartXSelection(value: $pickedTime)
        }
    }
}

/// What matters for this sport: runs you tap to see on the map (ski, snowboard), laps (Hyrox, intervals),
/// km splits with moving time and steepest climb (hike, ride, run), summit.
struct SportSection: View {
    let entry: SportEntry
    let track: SportTrack?
    let runs: [SportTrack.Run]
    @Binding var selected: Int?

    var body: some View {
        if let track {
            if !runs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runs · \(runs.count) · tap to see one").eyebrow()
                    let best = runs.indices.max { runs[$0].topKmh < runs[$1].topKmh }
                    ForEach(Array(runs.enumerated()), id: \.offset) { i, r in
                        Button { selected = selected == i ? nil : i } label: {
                            HStack(spacing: 8) {
                                Circle().fill(SportMapStyle.runColor(i)).frame(width: 9, height: 9)
                                Text("\(i + 1)").font(Theme.label(13)).foregroundStyle(Theme.lime).frame(width: 20, alignment: .leading)
                                Text("\(Int(r.drop.rounded())) m ↓ · \(String(format: "%.1f", r.meters / 1000)) km\(i == best ? " 🔥" : "")")
                                    .font(Theme.label(14))
                                Spacer()
                                Text("\(Int(r.topKmh.rounded())) · \(Int(r.avgKmh.rounded())) km/h").font(Theme.label(13)).foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(selected == i ? SportMapStyle.runColor(i).opacity(0.22) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Top · average speed").font(Theme.label(10)).foregroundStyle(Theme.muted)
                }
                .card(padding: 14)
            } else if !track.laps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.sport == .hyrox ? "Splits · \(track.laps.count)" : "Laps · \(track.laps.count)").eyebrow()
                    ForEach(Array(track.laps.enumerated()), id: \.offset) { i, l in
                        row("\(i + 1)", Self.clock(l.minutes), l.start.formatted(date: .omitted, time: .shortened))
                    }
                }
                .card(padding: 14)
            } else if !entry.sport.downhill, track.meters >= 1000 {
                splits(track)
            }
            if [Sport.hike, .mountaineering, .trailRun].contains(entry.sport), let top = track.highest {
                HStack {
                    Label("Summit", systemImage: "flag.fill").font(Theme.label(14))
                    Spacer()
                    Text("\(Int(top.rounded()).formatted()) m").font(Theme.display(22))
                }
                .card(padding: 14)
            }
        }
    }

    private func splits(_ track: SportTrack) -> some View {
        // Long rides split every 5 km so the list stays short.
        let s = track.splits(every: entry.sport.showsSpeed && track.meters > 30_000 ? 5000 : 1000)
        let stopped = max(0, track.seconds - track.movingSeconds())
        var facts: [String] = []
        if stopped >= 60 { facts.append("Stopped \(SportMapStyle.clock(stopped))") }
        if let g = track.maxGrade { facts.append("Max grade \(Int(g.rounded())) %") }
        return VStack(alignment: .leading, spacing: 8) {
            Text((["Splits"] + facts).joined(separator: " · ")).eyebrow()
            ForEach(s, id: \.index) { sp in
                let speed = sp.seconds > 0 ? sp.meters / sp.seconds * 3.6 : 0
                row(s.count > 1 && s[0].meters == 5000 ? "\(sp.index * 5)" : "\(sp.index)", entry.sport.showsSpeed ? String(format: "%.1f km/h", speed) : SportMapStyle.pace(sp.pace),
                    sp.climb >= 1 ? "+\(Int(sp.climb.rounded())) m" : "flat")
            }
        }
        .card(padding: 14)
    }

    private func row(_ n: String, _ main: String, _ trailing: String) -> some View {
        HStack {
            Text(n).font(Theme.label(13)).foregroundStyle(Theme.lime).frame(width: 24, alignment: .leading)
            Text(main).font(Theme.label(14))
            Spacer()
            Text(trailing).font(Theme.label(13)).foregroundStyle(Theme.muted)
        }
    }

    static func clock(_ minutes: Double) -> String {
        let s = Int((minutes * 60).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
