import CoreLocation
import LiftSensor
import SwiftUI
import WatchKit

// Sport tracking (#418, design B + C from `other-sports/watch-proposals.png`): pick a sport and a battery mode,
// one dashboard per sport, summary with battery used.

/// Home row → sports list.
struct SportPickerView: View {
    @State private var picked: TrackedSport?
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Eyebrow(text: "Track a sport", color: W.lime)
                // Today's planned run (#618): starts the run player with its steps.
                if let run = store.snapshot.run, let sport = TrackedSport(rawValue: run.sport) {
                    Button {
                        Task { await SportTracker.shared.start(sport, power: .full, run: run) }
                    } label: {
                        HomeRow(symbol: sport.symbol, title: run.title, value: "▶", tint: (0xFF3D8B, 0xFF9A5E), unit: "TODAY")
                    }
                    .buttonStyle(.plain)
                }
                // Hyrox race mode (#426): runs and stations recorded by themselves.
                NavigationLink { HyroxSetupView() } label: {
                    HomeRow(symbol: "figure.cross.training", title: "Hyrox", value: "›", tint: HyroxLook.station)
                }
                .buttonStyle(.plain)
                ForEach(TrackedSport.allCases) { s in
                    Button { picked = s } label: {
                        HomeRow(symbol: s.symbol, title: s.label, value: "›", tint: s.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .watchMargins()
        }
        .sheet(item: $picked) { SportPowerView(sport: $0) }
    }
}

/// Battery mode before the start (design C): Full or Saver, with how long each lasts.
struct SportPowerView: View {
    let sport: TrackedSport
    @Environment(\.dismiss) private var dismiss
    /// Target zone (#609, design B); nil = none.
    @State private var target: Int?
    @State private var sensors = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: sport.label, color: W.color(sport.tint.1))
                if sport.usesGPS {
                    ForEach(TrackPower.allCases) { p in
                        Button { start(p) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(p.label, systemImage: p == .full ? "bolt.fill" : "battery.75percent").font(W.label(14))
                                Text(p.detail).font(W.label(10)).opacity(0.8)
                            }
                            .foregroundStyle(p == .full ? W.ink : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(p == .full ? AnyShapeStyle(W.lime) : AnyShapeStyle(W.card)))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    LimeButton(title: "Start") { start(.full) }
                }
                Eyebrow(text: "Target zone")
                HStack(spacing: 4) {
                    ForEach([nil, 2, 3, 4] as [Int?], id: \.self) { z in
                        Button { target = z } label: {
                            Text(z.map { "Z\($0)" } ?? "Off").font(W.label(12))
                                .foregroundStyle(target == z ? W.ink : .white)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(RoundedRectangle(cornerRadius: 8).fill(target == z ? AnyShapeStyle(W.lime) : AnyShapeStyle(W.card)))
                        }
                        .buttonStyle(.plain)
                    }
                if sport.bike {
                    // Bike sensors and the FTP test (#623 A + C).
                    Button { sensors = true } label: {
                        HomeRow(symbol: "sensor.fill", title: "Sensors", value: "\(BikeSensors.shared.paired.count) ›", tint: sport.tint)
                    }
                    .buttonStyle(.plain)
                    Button { start(.full, test: true) } label: {
                        HomeRow(symbol: "bolt.heart.fill", title: "FTP test · 45′", value: BikeSensors.shared.ftp.map { "\($0) W" } ?? "›",
                                tint: (0xFF8A00, 0xFFD400))
                    }
                    .buttonStyle(.plain)
                    .disabled(!BikeSensors.shared.hasPower)
                }
            }
            .watchMargins()
        }
        .sheet(isPresented: $sensors) { BikeSensorsPage() }
    }

    private func start(_ p: TrackPower) {
        Task { await SportTracker.shared.start(sport, power: p, target: target) }
    private func start(_ p: TrackPower, test: Bool = false) {
        Task { await SportTracker.shared.start(sport, power: p) }
        if test { BikeSensors.shared.startTest() }
        dismiss()
    }
}

/// The running session: one screen per sport (design B), controls on the next page.
struct SportTrackView: View {
    @State private var tracker = SportTracker.shared
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TabView {
            // Swing sports open on the swing counter (#611 B).
            if tracker.sport?.swingLever != nil {
                TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { ctx in swingPage(now: ctx.date) }
            }
            // Always on (#418 battery): wrist down redraws once a minute, no animation.
            TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { ctx in
                dashboard(now: ctx.date)
            }
            if tracker.sport?.usesGPS == true { mapPage }
            if tracker.sport?.bike == true { BikeSensorsPage() }
            if let sport = tracker.sport, sport.compass, CLLocationManager.headingAvailable() { compassPage }
            controls
        }
        .tabViewStyle(.verticalPage)
        // FTP test result (#623 C) to the iPhone: zones there follow it.
        .onChange(of: BikeSensors.shared.testResult) { _, ftp in
            if let ftp { store.send(.bikeFTP(watts: ftp, date: Date())) }
        }
    }

    @ViewBuilder private func dashboard(now: Date) -> some View {
        if let sport = tracker.sport, let step = tracker.step {
            runDashboard(sport, step: step, now: now)
        } else if let sport = tracker.sport {
            let elapsed = Self.clock(now.timeIntervalSince(tracker.started ?? now))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(header(sport)) · \(elapsed)").font(W.label(11)).foregroundStyle(W.lime).lineLimit(1)
                if sport.downhill {
                    big("\(Int(tracker.speed.rounded()))", "km/h · top \(Int(tracker.topSpeed.rounded()))", sport)
                    pair(("VERT", "\(Int(tracker.down.rounded()))"), ("HR", hr))
                    if let r = tracker.lastRun, !dimmed {
                        Text("Last run \(Int(r.drop.rounded())) m · \(Int(r.topKmh.rounded())) km/h").font(W.label(10)).opacity(0.85).lineLimit(1)
                    }
                } else if sport.bike, BikeSensors.shared.hasPower {
                    powerPlayer(sport, now: now)
                } else if [TrackedSport.hike, .mountaineering, .trailRun].contains(sport) {
                    big("+\(Int(tracker.up.rounded()))", "m up · \(km) km", sport)
                    pair(("SUMMIT", tracker.highest.map { "\(Int($0.rounded()))" } ?? "–"), ("HR", hr))
                } else if sport.usesGPS {
                    big(km, "km · \(Int(tracker.speed.rounded())) km/h", sport)
                    pair(("UP", "\(Int(tracker.up.rounded()))"), ("HR", hr))
                } else {
                    big(hr, "bpm", sport)
                    pair(("KCAL", "\(Int(tracker.kcal.rounded()))"), ("TIME", elapsed))
                }
                // Heart-rate zones (#609, design A) and the target lock (design B).
                if !dimmed { ZoneTiles(height: 18) }
                ZoneTargetLine()
                if sport.laps && !dimmed && tracker.run == nil {
                    Button { tracker.markLap() } label: {
                        HStack(spacing: 4) { Text("LAP \(tracker.lap + 1) ›").font(W.label(12)); PinchMark() }
                            .foregroundStyle(W.ink).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(W.lime).buttonBorderShape(.capsule)
                    .pinch(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .watchMargins()
            .zoneLockWash()
            .background(RadialGradient(colors: [W.color(sport.tint.0).opacity(dimmed ? 0.25 : 0.8), .black], center: .top, startRadius: 0, endRadius: 160)
                .ignoresSafeArea())
        }
    }

    /// Run player (#618, design B): the step as a big block, pace now vs target, what's left, the next step.
    private func runDashboard(_ sport: TrackedSport, step: WRunStep, now: Date) -> some View {
        let left = tracker.stepLeft(now: now)
        let work = step.kind == "work"
        let tint: (UInt32, UInt32) = work ? (0xFF3D8B, 0xFF9A5E) : step.zone.map { WZones.tints[$0 - 1] } ?? sport.tint
        return VStack(alignment: .leading, spacing: 3) {
            Text(runHeader(step)).font(W.label(11)).foregroundStyle(W.lime).lineLimit(1).minimumScaleFactor(0.7)
            if let target = step.pace {
                let p = tracker.pace
                let ok = p.map { abs($0 - target) <= 8 } ?? false
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.map(Self.pace) ?? "–:––").font(W.display(40)).foregroundStyle(W.light(tint.1, 0.3)).minimumScaleFactor(0.5).lineLimit(1)
                    Text("/km · target \(Self.pace(target))\(ok ? " ✓" : "")").font(W.label(11)).foregroundStyle(ok ? W.lime : .white)
                }
            } else {
                big(hr, "bpm · Zone \(step.zone ?? tracker.run?.zone ?? 2)", sport)
            }
            if let m = left.meters {
                Text("\(Int(tracker.stepMeters)) m · \(m) left").font(W.label(13))
            } else if let s = left.seconds {
                Text("\(Self.clock(Double(s))) left").font(W.label(13))
            }
            if !dimmed { ZoneTiles(height: 16) }
            ZoneTargetLine()
            if !dimmed {
                Button { tracker.nextStep() } label: {
                    Text(tracker.nextUp.map { "NEXT · \($0.title.uppercased()) ›" } ?? "FINISH PLAN ›").font(W.label(11)).foregroundStyle(W.ink)
                        .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(W.lime).buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .watchMargins()
        .zoneLockWash()
        .background(RadialGradient(colors: [W.color(tint.0).opacity(dimmed ? 0.25 : 0.85), .black], center: .top, startRadius: 0, endRadius: 160)
            .ignoresSafeArea())
    }

    private func runHeader(_ step: WRunStep) -> String {
        var head = step.title.uppercased()
        if let m = step.meters { head += " · \(m) M" } else if let s = step.seconds { head += " · \(s >= 60 ? "\(s / 60)′" : "\(s)″")" }
        return head
    }

    static func pace(_ secPerKm: Int) -> String { String(format: "%d:%02d", secPerKm / 60, secPerKm % 60) }

    /// Swing counter (#611 B, `apple-tech-radar/t9.png`): forehand and backhand tiles, smash tile with the top speed.
    @ViewBuilder private func swingPage(now: Date) -> some View {
        if let sport = tracker.sport {
            let s = tracker.impacts.swings
            VStack(alignment: .leading, spacing: 5) {
                Text("\(sport.label.uppercased()) · \(Int(now.timeIntervalSince(tracker.started ?? now) / 60))′").font(W.label(11)).foregroundStyle(W.lime)
                if sport == .golf {
                    SwingTile(title: "SWINGS", value: s.total, tint: (0xFF3D8B, 0xB23DFF))
                    SwingTile(title: "TOP \(Int(s.top.rounded())) KM/H", value: s.last.map { Int($0.kmh.rounded()) } ?? 0,
                              tint: (0xFF7A00, 0xFF3D5A), unit: "last")
                } else {
                    HStack(spacing: 5) {
                        SwingTile(title: "FH", value: s.counts[.forehand] ?? 0, tint: (0xFF3D8B, 0xB23DFF))
                        SwingTile(title: "BH", value: s.counts[.backhand] ?? 0, tint: (0x3D59FF, 0x7D4DFF))
                    }
                    SwingTile(title: "SMASH · TOP \(Int(s.top.rounded())) KM/H", value: s.counts[.smash] ?? 0, tint: (0xFF7A00, 0xFF3D5A))
                }
                if !ImpactTracker.swingsAvailable {
                    Text("Swing counting needs Apple Watch Series 8, Ultra or later").font(W.label(9)).opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .watchMargins()
        }
    }

    /// Power player (#623 B): zone tile, watts big, 3″ average, cadence and heart rate; the FTP test's phase on top.
    @ViewBuilder private func powerPlayer(_ sport: TrackedSport, now: Date) -> some View {
        let bike = BikeSensors.shared
        if let test = bike.testPhase(now: now) {
            HStack(spacing: 4) {
                Text(test.phase == .done ? "FTP TEST DONE" : "FTP · \(test.phase.label.uppercased())").font(W.label(10))
                Spacer(minLength: 0)
                if test.phase != .done { Text(Self.clock(test.left)).font(W.label(12)).monospacedDigit() }
            }
            .foregroundStyle(W.ink)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(W.color(0xFFD400)))
            if let r = bike.testResult {
                big("\(r)", "W · your new FTP", sport)
            }
        } else if let z = bike.zone {
            Text("ZONE \(z.index) · \(z.name.uppercased())").font(W.label(10)).foregroundStyle(W.ink).lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(W.color(Self.zoneTint[z.index - 1])))
        }
        if bike.testResult == nil || bike.testPhase(now: now) == nil {
            big(bike.watts.map { "\($0)" } ?? "–", "W · 3″ \(bike.avg3.map { "\(Int($0.rounded()))" } ?? "–")"
                + (bike.testPhase(now: now)?.phase == .allOut ? " · avg \(bike.testAverage ?? 0)" : ""), sport)
        }
        pair(("RPM", bike.cadence.map { "\(Int($0.rounded()))" } ?? "–"), ("HR", bike.heartRate.map { "\($0)" } ?? hr))
    }

    private static let zoneTint: [UInt32] = [0x8E9BB0, 0x1E9BFF, 0x00C6A7, 0xFFD400, 0xFF8A00, 0xFF3D6E, 0x8A2BFF]

    private func header(_ sport: TrackedSport) -> String {
        // Live run / lift state (#445 C).
        if sport.downhill { return tracker.onLift ? "ON LIFT · \(tracker.runs) RUNS" : "RUN \(tracker.runs + 1)" }
        return sport.label.uppercased()
    }

    private var km: String { String(format: tracker.meters >= 10_000 ? "%.0f" : "%.1f", tracker.meters / 1000) }
    private var hr: String { tracker.heartRate.map { "\(Int($0.rounded()))" } ?? "–" }

    private func big(_ value: String, _ unit: String, _ sport: TrackedSport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(W.display(44)).foregroundStyle(W.light(sport.tint.1, 0.3)).minimumScaleFactor(0.5).lineLimit(1)
            Text(unit).font(W.label(11)).opacity(0.85)
        }
    }

    private func pair(_ a: (String, String), _ b: (String, String)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) { Text(a.0).font(W.label(9)).opacity(0.75); Text(a.1).font(W.label(15)) }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) { Text(b.0).font(W.label(9)).opacity(0.75); Text(b.1).font(W.label(15)) }
        }
    }

    /// Live map (#445 C): breadcrumb, distance and climb, arrow back to the start. Drawn as a line, no map tiles: cheap on battery
    /// and works without signal.
    private var mapPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sport = tracker.sport {
                Text(sport.downhill ? "Riding \(Self.clock(tracker.rideSeconds)) · Lifts \(Self.clock(tracker.liftSeconds))" : sport.label.uppercased())
                    .font(W.label(10)).foregroundStyle(W.lime).lineLimit(1)
            }
            TrailView(trail: tracker.trail, live: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .firstTextBaseline) {
                Text("\(km) km").font(W.label(16))
                Spacer()
                Text(tracker.sport?.downhill == true ? "\(Int(tracker.down.rounded())) m ↓" : "+\(Int(tracker.up.rounded())) m").font(W.label(16))
            }
            if let m = tracker.homeMeters, m >= 50, let b = tracker.homeBearing {
                HStack(spacing: 4) {
                    // Relative to the direction of travel when moving, else to north.
                    Image(systemName: "location.north.fill").rotationEffect(.degrees(b - (tracker.course ?? 0)))
                    Text(String(format: m >= 1000 ? "Start %.1f km" : "Start %.0f m", m >= 1000 ? m / 1000 : m))
                    if tracker.course == nil { Text("· N up").opacity(0.7) }
                }
                .font(W.label(10)).opacity(0.85)
            }
        }
        .watchMargins()
    }

    /// Compass + waypoints (#617): heading, arrow to the waypoint and back to the start, both turned with the watch.
    private var compassPage: some View {
        let h = tracker.heading ?? 0
        let wp = tracker.target.flatMap { tracker.waypoints.indices.contains($0) ? tracker.waypoints[$0] : nil }
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(tracker.heading.map { "\(Self.point($0)) \(Int($0.rounded()) % 360)°" } ?? "Compass…")
                    .font(W.display(24)).foregroundStyle(W.lime).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 2)
                Text("N").font(W.label(11)).foregroundStyle(W.color(0xFF5A75))
                    .offset(y: -34).rotationEffect(.degrees(-h))
                if let wp, let to = tracker.toward(wp.coordinate) {
                    Image(systemName: "location.north.fill").font(.system(size: 26, weight: .black)).foregroundStyle(W.lime)
                        .rotationEffect(.degrees(to.bearing - h))
                } else if let b = tracker.homeBearing {
                    Image(systemName: "house.fill").font(.system(size: 13, weight: .black)).offset(y: -22)
                        .rotationEffect(.degrees(b - h))
                }
            }
            .frame(width: 78, height: 78)
            .accessibilityHidden(true)
            if let wp, let to = tracker.toward(wp.coordinate) {
                Button { tracker.nextTarget() } label: {
                    Text("↗ \(wp.name) \(Self.distance(to.meters))").font(W.label(13)).lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(wp.name), \(Self.distance(to.meters)). Tap for the next waypoint")
            }
            if let m = tracker.homeMeters, m >= 50 {
                Text("⌂ Start \(Self.distance(m))").font(W.label(10)).opacity(0.85)
            }
            Button { tracker.markWaypoint() } label: {
                Label("Mark waypoint", systemImage: "mappin.and.ellipse").font(W.label(12)).foregroundStyle(W.ink).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(W.lime).buttonBorderShape(.capsule)
        }
        .watchMargins()
        .onAppear { tracker.startHeading() }
        .onDisappear { tracker.stopHeading() }
    }

    static func point(_ deg: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int(((deg + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
    }

    static func distance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m.rounded())) m"
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button { tracker.paused ? tracker.resume() : tracker.pause() } label: {
                Label(tracker.paused ? "Resume" : "Pause", systemImage: tracker.paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
            }
            .tint(.yellow)
            Button { Task { await tracker.finish() } } label: {
                Label("End & save", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(W.lime)
            Text(tracker.power == .saver ? "Saver · GPS once a minute" : "Full GPS").font(W.label(10)).opacity(0.7)
        }
        .buttonStyle(.bordered)
        .watchMargins()
    }

    static func clock(_ s: TimeInterval) -> String {
        let t = Int(max(0, s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// One gradient count tile of the swing counter.
struct SwingTile: View {
    let title: String
    let value: Int
    let tint: (UInt32, UInt32)
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(W.label(10)).lineLimit(1).minimumScaleFactor(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)").font(W.display(26)).monospacedDigit().contentTransition(.numericText())
                if let unit { Text(unit).font(W.label(10)).opacity(0.85) }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.gradient(tint.0, tint.1)))
        .animation(.snappy, value: value)
    }
}

/// After End: the main numbers and the battery it used (design C). Rated and shown in full on the iPhone.
struct SportSummaryView: View {
    let summary: SportTracker.Summary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "\(summary.sport.label) · done", color: W.lime)
                Text(SportTrackView.clock(Double(summary.minutes) * 60)).font(W.display(30))
                if summary.km > 0 { Text(String(format: "%.1f km", summary.km)).font(W.label(14)) }
                if summary.vertical > 0 { Text("\(Int(summary.vertical.rounded())) m \(summary.sport.downhill ? "down" : "up")").font(W.label(14)) }
                if summary.sport.downhill { Text("\(summary.runs) runs · top \(Int(summary.topKmh.rounded())) km/h").font(W.label(13)) }
                if summary.sport.downhill && summary.rideSeconds + summary.liftSeconds > 0 {
                    Text("Riding \(SportTrackView.clock(summary.rideSeconds)) · Lifts \(SportTrackView.clock(summary.liftSeconds))").font(W.label(11))
                }
                if !summary.swings.isEmpty {
                    Text(SwingCounter.Shot.allCases.map { "\($0.short) \(summary.swings[$0] ?? 0)" }.joined(separator: " · ")).font(W.label(12))
                    if summary.topSwing > 0 { Text("Top swing \(Int(summary.topSwing.rounded())) km/h").font(W.label(11)) }
                }
                if summary.trail.count >= 2 {
                    TrailView(trail: summary.trail, live: false).frame(height: 70)
                }
                if let b = summary.batteryUsed { Text("Battery used \(b) %").font(W.label(11)).opacity(0.75) }
                Text("Saved to Apple Health. Rate it on your iPhone.").font(.footnote).opacity(0.8)
                LimeButton(title: "Done") { SportTracker.shared.closeSummary() }
            }
            .watchMargins()
        }
    }
}

/// A route drawn as a line fitted to the view (#445 C): start dot, lime dot where you are now (live).
struct TrailView: View {
    let trail: [CLLocationCoordinate2D]
    let live: Bool

    var body: some View {
        Canvas { ctx, size in
            guard trail.count >= 2 else { return }
            let lats = trail.map(\.latitude), lons = trail.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            // Same scale both ways (longitude shrinks with latitude), centred.
            let k = cos((minLat + maxLat) / 2 * .pi / 180)
            let w = max((maxLon - minLon) * k, 1e-5), h = max(maxLat - minLat, 1e-5)
            let scale = min((size.width - 12) / w, (size.height - 12) / h)
            let ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2
            func pt(_ c: CLLocationCoordinate2D) -> CGPoint {
                CGPoint(x: ox + (c.longitude - minLon) * k * scale, y: size.height - oy - (c.latitude - minLat) * scale)
            }
            var path = Path()
            path.move(to: pt(trail[0]))
            for c in trail.dropFirst() { path.addLine(to: pt(c)) }
            ctx.stroke(path, with: .color(W.color(0x7DFFB0)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            let s = pt(trail[0])
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - 3, y: s.y - 3, width: 6, height: 6)), with: .color(.white))
            if live, let last = trail.last {
                let e = pt(last)
                ctx.fill(Path(ellipseIn: CGRect(x: e.x - 5, y: e.y - 5, width: 10, height: 10)), with: .color(W.lime))
            }
        }
    }
}


/// Bike sensors (#623 A): paired ones with battery and connection, the rest found nearby; tap to pair or unpair.
struct BikeSensorsPage: View {
    @State private var bike = BikeSensors.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Bike sensors", color: W.lime)
                if bike.list.isEmpty {
                    Text(bike.scanning ? "Looking… wake your sensors (spin the crank)." : "No sensors yet.")
                        .font(W.label(11)).opacity(0.8)
                }
                ForEach(bike.list) { s in
                    let paired = bike.paired[s.id] != nil
                    Button { paired ? bike.unpair(s) : bike.pair(s) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: s.kind.symbol).font(.system(size: 13, weight: .bold))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.name).font(W.label(13)).lineLimit(1)
                                Text(paired ? (s.connected ? "Connected" : "Paired") : "Tap to pair").font(W.label(9)).opacity(0.8)
                            }
                            Spacer(minLength: 0)
                            if let b = s.battery { Text("\(b) %").font(W.label(11)).monospacedDigit() }
                        }
                        .foregroundStyle(paired ? W.ink : .white)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(paired ? AnyShapeStyle(W.lime) : AnyShapeStyle(W.card)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .watchMargins()
        }
        .onAppear { bike.startScan() }
        .onDisappear { bike.stopScan() }
    }
}
