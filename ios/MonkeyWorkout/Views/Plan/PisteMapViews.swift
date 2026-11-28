import APIClient
import MapKit
import SwiftUI
import WorkoutEngine

// Runs & lifts on the resort map (#1132, design C): Apple Maps under the ski day by default; a Pistes toggle adds the
// resort's pistes (by colour) and named lifts from OpenStreetMap, asked once. The request carries the area around the
// day, never the track, and goes through our server so OpenStreetMap never sees the member's address.

/// Loads and keeps piste maps by area, for the session page and the live page.
@MainActor @Observable
final class PisteMaps {
    static let shared = PisteMaps()

    /// Said yes to downloading piste maps (asked once).
    static let consentKey = "pisteMapOK"

    private(set) var loading = false
    private(set) var failed = false
    private var cache: [String: PisteMap] = [:]

    private static func key(_ b: (s: Double, w: Double, n: Double, e: Double)) -> String {
        // Same 0.01° steps as the server's tiles round to, so a re-open hits the cache.
        [b.s, b.w, b.n, b.e].map { String(format: "%.2f", $0) }.joined(separator: ",")
    }

    func cached(_ box: (s: Double, w: Double, n: Double, e: Double)) -> PisteMap? { cache[Self.key(box)] }

    func load(_ box: (s: Double, w: Double, n: Double, e: Double), api: APIClient) async -> PisteMap? {
        if let hit = cached(box) { return hit }
        loading = true
        failed = false
        defer { loading = false }
        guard let data = try? await api.pisteMap(south: box.s, west: box.w, north: box.n, east: box.e),
              let map = try? PisteMap.decode(data) else {
            failed = true
            return nil
        }
        cache[Self.key(box)] = map
        return map
    }
}

extension PisteMap.Line {
    var mapCoordinates: [CLLocationCoordinate2D] { coordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) } }

    var tint: Color {
        switch colour {
        case .blue: Color(hex: 0x2F6BFF)
        case .red: Color(hex: 0xE5142B)
        case .black: Color(hex: 0x111111)
        case .orange: Color(hex: 0xFF8A00)
        case .unknown: Color(hex: 0x8E9BB0)
        }
    }

    var middle: CLLocationCoordinate2D? {
        let c = mapCoordinates
        return c.isEmpty ? nil : c[c.count / 2]
    }
}

/// Pistes and lifts drawn under the day's track (inside a `Map`).
struct PisteLayer: MapContent {
    let map: PisteMap

    var body: some MapContent {
        ForEach(Array(map.pistes.enumerated()), id: \.offset) { _, p in
            MapPolyline(coordinates: p.mapCoordinates)
                .stroke(p.tint.opacity(0.75), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round,
                                                                 dash: p.colour == .orange ? [4, 3] : []))
        }
        ForEach(Array(map.lifts.enumerated()), id: \.offset) { _, l in
            MapPolyline(coordinates: l.mapCoordinates).stroke(Color(hex: 0x333A48), lineWidth: 2)
            if l.name != nil, let mid = l.middle {
                Annotation("", coordinate: mid) {
                    Text(l.label).font(Theme.label(9)).foregroundStyle(.white).lineLimit(1)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.7)))
                }
            }
        }
    }
}

/// "Map | Pistes" switch over the map, and the once-only question before the first download.
struct PisteToggle: View {
    @Binding var on: Bool
    let loading: Bool

    var body: some View {
        HStack(spacing: 2) {
            seg("Map", !on) { on = false }
            seg(loading ? "Pistes…" : "Pistes", on) { on = true }
        }
        .padding(3)
        .background(Capsule().fill(.black.opacity(0.55)))
    }

    private func seg(_ title: String, _ selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(Theme.label(11)).foregroundStyle(selected ? Theme.ink : .white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(selected ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.clear)))
        }
        .buttonStyle(.plain)
    }
}

/// Owns the Pistes switch for one screen: asks once, loads the area around `track`, falls back to Map on failure.
struct PisteSwitch: ViewModifier {
    let track: SportTrack?
    @Binding var on: Bool
    @Binding var map: PisteMap?
    @Environment(AppModel.self) private var model
    @AppStorage(PisteMaps.consentKey) private var consent = false
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .onChange(of: on) { _, wanted in
                guard wanted else { return }
                if consent { load() } else { asking = true }
            }
            .confirmationDialog("Show the resort's pistes?", isPresented: $asking, titleVisibility: .visible) {
                Button("Download piste map") { consent = true; load() }
                Button("Not now", role: .cancel) { on = false }
            } message: {
                Text("MonkeyWorkout asks OpenStreetMap for the pistes and lifts around this day. Only the area is sent, never your track or your address.")
            }
    }

    private func load() {
        guard let track, let box = PisteMap.box(track) else { on = false; return }
        Task {
            map = await PisteMaps.shared.load(box, api: model.api)
            if map == nil { on = false }
        }
    }
}

extension View {
    func pisteSwitch(track: SportTrack?, on: Binding<Bool>, map: Binding<PisteMap?>) -> some View {
        modifier(PisteSwitch(track: track, on: on, map: map))
    }
}

/// Lifts the day took, by name and count, from the Watch's lift rides (#1129) and the piste map.
func liftsTaken(_ track: SportTrack, _ map: PisteMap) -> String? {
    var counts: [String: Int] = [:]
    var order: [String] = []
    for l in track.lifts {
        guard let a = track.index(near: l.start), let b = track.index(near: l.end),
              let lift = map.lift(from: track.points[a], to: track.points[b]) else { continue }
        if counts[lift.label] == nil { order.append(lift.label) }
        counts[lift.label, default: 0] += 1
    }
    guard !order.isEmpty else { return nil }
    return order.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }.joined(separator: " · ")
}
