import MapKit
import SwiftUI
import WorkoutEngine

/// A Watch sport session followed live on the iPhone (#1130, design A): lift / riding state, last run, runs, vertical,
/// top speed, ride vs lift time and the trail. Opens from the Train banner; the Live Activity covers the lock screen.
struct SportLiveView: View {
    let live: WSportLive
    @Environment(\.dismiss) private var dismiss
    /// Piste map (#1132, design C): Apple Maps, Pistes on request.
    @State private var pisteOn = false
    @State private var pistes: PisteMap?
    private var mirror: MirroredWorkout { .shared }

    /// The trail as a track, for the piste map's area.
    private var trailTrack: SportTrack {
        SportTrack(points: stride(from: 0, to: live.trail.count - 1, by: 2).map {
            SportTrack.Point(lat: live.trail[$0], lon: live.trail[$0 + 1], alt: 0, speed: 0, time: live.started)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Label("LIVE FROM WATCH · \(Self.clock(ctx.date.timeIntervalSince(live.started)))"
                              + (mirror.heartRate.map { " · ♥ \($0)" } ?? ""), systemImage: "applewatch")
                            .font(Theme.label(12)).foregroundStyle(Theme.lime).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.cardStrong))
                    }
                    .accessibilityLabel("Close, the Watch keeps going")
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(live.label).font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Text(stateLabel).font(Theme.label(13)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.lime))
                }
                hero
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    if live.downhill {
                        tile("RUNS", "\(live.runs)", 0xFF2D55, 0xFF8A00)
                        tile("VERTICAL", "\(Int(live.vertical.rounded())) m", 0x0F9D6A, 0x2F9BFF)
                        tile("TOP SPEED", "\(Int(live.topKmh.rounded())) km/h", 0xD1239A, 0xFF5A5A)
                        tile("RIDE / LIFT", "\(Int(live.rideSeconds / 60))′ / \(Int(live.liftSeconds / 60))′", 0x2F6BFF, 0x8A4DFF)
                    } else {
                        tile("DISTANCE", String(format: "%.1f km", live.km), 0xFF2D55, 0xFF8A00)
                        tile("CLIMB", "+\(Int(live.vertical.rounded())) m", 0x0F9D6A, 0x2F9BFF)
                        tile("SPEED", "\(Int(live.kmh.rounded())) km/h", 0xD1239A, 0xFF5A5A)
                        tile("TOP SPEED", "\(Int(live.topKmh.rounded())) km/h", 0x2F6BFF, 0x8A4DFF)
                    }
                }
                if live.trail.count >= 4 {
                    SportLiveMap(flat: live.trail, pistes: pisteOn ? pistes : nil)
                        .frame(height: 220)
                        .overlay(alignment: .topTrailing) {
                            if let sport = Sport(rawValue: live.sport), sport.trailKind != nil {
                                PisteToggle(on: $pisteOn, loading: PisteMaps.shared.loading, word: sport.trailWord,
                                            attribution: pistes?.attribution).padding(8)
                            }
                        }
                }
                Button { mirror.endSportOnWatch() } label: {
                    Text("End & save on Watch").font(Theme.label(15)).frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                }
                .accessibilityHint("Ends the session on the Watch, which saves it to Health")
            }
            .padding(20)
        }
        .foregroundStyle(.white)
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: mirror.sportLive) { _, on in if !on { dismiss() } }
        .pisteSwitch(track: live.trail.count >= 4 ? trailTrack : nil, kind: Sport(rawValue: live.sport)?.trailKind, on: $pisteOn, map: $pistes)
    }

    private var stateLabel: String {
        if live.paused { return "PAUSED" }
        guard live.downhill else { return "LIVE" }
        return live.onLift ? "ON LIFT" : "RIDING"
    }

    /// Run in progress or the last one (downhill), else speed now.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            if live.downhill {
                Text(live.onLift ? "ON LIFT · LAST RUN" : "RUN \(live.runs + 1)").font(Theme.label(12)).opacity(0.9)
                if let d = live.lastRunDrop {
                    Text("\(Int(d.rounded())) m ↓").font(Theme.display(42)).monospacedDigit()
                    Text("last run · top \(Int((live.lastRunTopKmh ?? 0).rounded())) km/h").font(Theme.label(15)).opacity(0.9)
                } else {
                    Text("\(Int(live.kmh.rounded())) km/h").font(Theme.display(42)).monospacedDigit()
                    Text("first run").font(Theme.label(15)).opacity(0.9)
                }
            } else {
                Text("SPEED NOW").font(Theme.label(12)).opacity(0.9)
                Text("\(Int(live.kmh.rounded())) km/h").font(Theme.display(42)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [Color(hex: live.tint), Color(hex: live.tint2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func tile(_ label: String, _ value: String, _ a: UInt32, _ b: UInt32) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.label(10)).opacity(0.9)
            Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func clock(_ s: TimeInterval) -> String {
        let t = Int(max(0, s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// The Watch's breadcrumb on Apple Maps (terrain), the current spot as a dot; the resort's pistes under it when on.
struct SportLiveMap: View {
    /// lat, lon pairs.
    let flat: [Double]
    var pistes: PisteMap?

    private var coords: [CLLocationCoordinate2D] {
        stride(from: 0, to: flat.count - 1, by: 2).map { CLLocationCoordinate2D(latitude: flat[$0], longitude: flat[$0 + 1]) }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            if let pistes { PisteLayer(map: pistes) }
            MapPolyline(coordinates: coords).stroke(Color(hex: 0xFF5A5A), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            if let last = coords.last {
                Annotation("", coordinate: last) {
                    Circle().fill(Theme.lime).frame(width: 14, height: 14).overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Trail so far")
    }
}

/// On Train while the Watch tracks a sport (#1130 A): state, run and vertical, Open into the live page.
struct SportLiveBanner: View {
    let live: WSportLive

    var body: some View {
        Button { MirroredWorkout.shared.presented = true } label: {
            HStack(spacing: 10) {
                Image(systemName: live.symbol).font(.system(size: 20, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("LIVE ON WATCH" + (MirroredWorkout.shared.heartRate.map { " · ♥ \($0)" } ?? "")).font(Theme.label(11))
                    Text(line).font(Theme.label(15)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("Open").font(Theme.label(13)).foregroundStyle(Theme.ink).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.lime))
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(LinearGradient(colors: [Color(hex: live.tint), Color(hex: live.tint2)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the session running on your Watch")
    }

    private var line: String {
        if live.downhill {
            let state = live.onLift ? "on lift" : "run \(live.runs + 1)"
            return "\(live.label) · \(state) · \(Int(live.vertical.rounded())) m ↓"
        }
        return "\(live.label) · " + String(format: "%.1f km", live.km)
    }
}
