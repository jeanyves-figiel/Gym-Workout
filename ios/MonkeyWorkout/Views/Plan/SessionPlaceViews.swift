import CoreLocation
import MapKit
import SwiftUI
import WorkoutEngine

// Where a climb or sport session happened (#832, design A + B): chips in the log card, last place first;
// + opens a sheet with Apple Maps search and bold tiles; the session page shows the place on a map.

extension AppModel {
    /// Every place a climb or sport session was logged at, for the chips.
    var placeUses: [SessionPlaces.Use] {
        climbLogs.compactMap { c in c.place.map { SessionPlaces.Use(sport: .climbing, place: $0, start: c.start) } }
            + sportLogs.compactMap { s in s.place.map { SessionPlaces.Use(sport: s.sport, place: $0, start: s.start) } }
    }

    /// Where a new log of this sport starts: where it was done last time.
    func lastPlace(for sport: Sport) -> SessionPlace? { SessionPlaces.last(for: sport, used: placeUses) }
}

extension SessionPlace {
    func symbol(for sport: Sport) -> String {
        gymId != nil ? "dumbbell.fill" : id.hasPrefix("map:") ? sport.symbol : "mappin"
    }
}

/// "Where" in the log card (design A): bold chips, the picked one white; tap it again for no place; + searches.
struct PlaceChips: View {
    @Environment(AppModel.self) private var model
    @Binding var place: SessionPlace?
    let sport: Sport
    @State private var searching = false

    var body: some View {
        let places = SessionPlaces.chips(for: sport, current: place, used: model.placeUses, gyms: model.savedGyms)
        VStack(alignment: .leading, spacing: 8) {
            Text("Where").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(places) { p in
                        chip(p, on: place?.id == p.id)
                    }
                    Button { searching = true } label: {
                        Label(places.isEmpty ? "Add place" : "", systemImage: "plus")
                            .labelStyle(PlusLabelStyle(iconOnly: !places.isEmpty))
                            .font(Theme.label(14))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, places.isEmpty ? 14 : 0)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a place")
                    .accessibilityIdentifier("log.place.add")
                }
            }
            .scrollClipDisabled()
        }
        .sheet(isPresented: $searching) {
            SessionPlaceSheet(sport: sport) { place = $0 }
        }
    }

    private func chip(_ p: SessionPlace, on: Bool) -> some View {
        Button { place = on ? nil : p } label: {
            HStack(spacing: 6) {
                Image(systemName: p.symbol(for: sport))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(sport.gradient))
                Text(p.name).font(Theme.label(14)).lineLimit(1)
            }
            .padding(.leading, 6).padding(.trailing, 12)
            .frame(minHeight: 44)
            .foregroundStyle(on ? Theme.ink : .white)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.25))))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? "Tap again for no place" : "")
    }
}

private struct PlusLabelStyle: LabelStyle {
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            if !iconOnly { configuration.title }
        }
    }
}

/// Pick a place (design B): search Apple Maps (gyms, crags, ski resorts, trails) or tap a tile: you're here,
/// places used before, your gyms. Typing a name Apple Maps doesn't know keeps it as typed.
struct SessionPlaceSheet: View {
    let sport: Sport
    let onPick: (SessionPlace) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var completer = PlaceCompleter()
    @State private var here: SessionPlace?
    @State private var locating = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField(sport.outdoorOnly ? "Resort, spot, trail…" : "Gym, crag, spot…", text: $query)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit { if let t = typed { pick(t) } }
                            .accessibilityIdentifier("log.place.search")
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))

                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        tiles
                    } else {
                        results
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Where")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .onChange(of: query) { _, q in completer.query = q }
        .task { await locateHere() }
    }

    /// Before typing: you're here, used before, your gyms.
    private var tiles: some View {
        let used = SessionPlaces.chips(for: sport, used: model.placeUses, gyms: model.savedGyms, limit: 7)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            if let here {
                tile(here.name, detail: "You're here", symbol: "location.fill", gradient: WorkoutEngine.Category.mobility.gradient) { pick(here) }
            } else if locating {
                tile("Locating…", detail: "You're here", symbol: "location", gradient: WorkoutEngine.Category.mobility.gradient) {}
            }
            ForEach(used) { p in
                let n = model.placeUses.filter { $0.place.id == p.id }.count
                tile(p.name, detail: p.gymId != nil && n == 0 ? "Your gym" : n == 1 ? "Used once" : "Used \(n)×",
                     symbol: p.symbol(for: sport), gradient: p.gymId != nil ? WorkoutEngine.Category.cardio.gradient : sport.gradient) { pick(p) }
            }
        }
    }

    private func tile(_ title: String, detail: String, symbol: String, gradient: LinearGradient, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(title).font(.system(size: 16, weight: .heavy, design: .rounded)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                }
                Spacer(minLength: 0)
                Text(detail).font(.caption.weight(.semibold)).opacity(0.88).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient))
        }
        .buttonStyle(.plain)
    }

    private var typed: SessionPlace? {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : SessionPlace.typed(String(t.prefix(120)))
    }

    /// While typing: Apple Maps suggestions, then the name as typed.
    private var results: some View {
        let options = PlaceOption.list(query: query, known: [], completions: completer.results, limit: 6)
        return VStack(spacing: 8) {
            if !options.isEmpty {
                PlaceOptionList(query: query, options: options) { o in
                    guard let c = o.completion else { return }
                    Task {
                        let item = await GymFinder.locate(c)
                        let at = item?.placemark.coordinate
                        pick(SessionPlace.map(name: item?.name ?? c.title, address: c.subtitle.isEmpty ? item?.placemark.locality : c.subtitle,
                                  latitude: at?.latitude, longitude: at?.longitude))
                    }
                }
            }
            if let t = typed {
                Button { pick(t) } label: {
                    Label("Use “\(t.name)”", systemImage: "pencil")
                        .font(Theme.label(15))
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 12)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pick(_ p: SessionPlace) {
        onPick(p)
        dismiss()
    }

    /// "You're here" only when location is already allowed (never asks here), as in the gym finder.
    private func locateHere() async {
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        locating = true
        defer { locating = false }
        let l = OneShotLocation()
        guard let location = await l.current() else { return }
        completer.bias(location)
        let c = location.coordinate
        let name = await GymFinder.town(at: location) ?? "Here"
        here = SessionPlace.map(name: name, address: nil, latitude: c.latitude, longitude: c.longitude)
    }
}

/// Session page (design B): the place on a map, name and address under it. No map without a position.
struct SessionPlaceTile: View {
    let place: SessionPlace
    let sport: Sport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lat = place.latitude, let lon = place.longitude {
                let at = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                Map(initialPosition: .region(MKCoordinateRegion(center: at, latitudinalMeters: 3_000, longitudinalMeters: 3_000)),
                    interactionModes: []) {
                    Marker(place.name, systemImage: place.symbol(for: sport), coordinate: at).tint(sport.colors[0])
                }
                .frame(height: 130)
                .allowsHitTesting(false)
            }
            HStack(spacing: 10) {
                Image(systemName: place.symbol(for: sport)).font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name).font(.system(size: 17, weight: .heavy, design: .rounded)).lineLimit(1)
                    if let a = place.address { Text(a).font(.caption.weight(.medium)).opacity(0.88).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .foregroundStyle(.white)
        .background(sport.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Where: \(place.name)")
    }
}
