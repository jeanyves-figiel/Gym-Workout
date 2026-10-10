import CoreLocation
import MapKit
import SwiftUI
import WorkoutEngine

// Gym finder (#70): gyms near you or near a place you're travelling to, with details before the website.

/// One-shot "where am I" with the when-in-use permission.
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current() async -> CLLocation? {
        if let c = continuation {
            continuation = nil
            c.resume(returning: nil)
        }
        return await withCheckedContinuation { c in
            continuation = c
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            default: finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: self.manager.requestLocation()
            case .notDetermined: break
            default: self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

/// A gym found by MapKit.
struct FoundGym: Identifiable {
    let item: MKMapItem
    let distance: CLLocationDistance?
    var id: String { GymFinder.id(item) }
    var name: String { item.name ?? "Gym" }
    var coordinate: CLLocationCoordinate2D { item.placemark.coordinate }
    var address: String { item.placemark.title ?? "" }
    var ref: GymRef {
        GymRef(id: id, name: name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

enum GymFinder {
    static func id(_ item: MKMapItem) -> String {
        let c = item.placemark.coordinate
        return "map:" + String(format: "%.5f,%.5f", c.latitude, c.longitude)
    }

    /// Centre of a typed place ("Berlin", "Hotel Adlon", an address).
    static func locate(_ place: String) async -> CLLocation? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place
        request.resultTypes = [.address, .pointOfInterest]
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let c = item.placemark.coordinate
        return CLLocation(latitude: c.latitude, longitude: c.longitude)
    }

    /// Fitness centres around a point, nearest first.
    static func gyms(near center: CLLocation, radius: CLLocationDistance = 4_000, text: String = "gym") async -> [FoundGym] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        request.region = MKCoordinateRegion(center: center.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        var seen = Set<String>()
        return items.compactMap { item -> FoundGym? in
            guard seen.insert(id(item)).inserted else { return nil }
            let c = item.placemark.coordinate
            return FoundGym(item: item, distance: CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: center))
        }
        .sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    static func distance(_ meters: CLLocationDistance?) -> String? {
        guard let m = meters else { return nil }
        return Measurement(value: m, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

/// Map + list of gyms near you or near a place; tap one for details.
struct GymFinderView: View {
    /// Search near this place instead of the current location (e.g. a trip's city).
    var place: String = ""
    /// When set, the detail screen offers "Use this gym".
    var onPick: ((GymRef) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .nearMe
    @State private var placeText = ""
    @State private var center: CLLocation?
    @State private var gyms: [FoundGym] = []
    @State private var loading = false
    @State private var failure: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: FoundGym?
    @State private var locator: OneShotLocation?

    enum Mode: Hashable { case nearMe, place }

    init(place: String = "", onPick: ((GymRef) -> Void)? = nil) {
        self.place = place
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    modePicker
                    if mode == .place {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.muted)
                            TextField("City, hotel or address", text: $placeText)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { Task { await search() } }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                    }
                    Map(position: $camera) {
                        if mode == .nearMe { UserAnnotation() }
                        ForEach(gyms) { g in
                            Marker(g.name, systemImage: "dumbbell.fill", coordinate: g.coordinate).tint(Theme.lime)
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if let failure {
                        Text(failure).font(.subheadline).foregroundStyle(Theme.muted)
                    } else if !gyms.isEmpty {
                        Text("\(gyms.count) gyms").eyebrow()
                    }
                    ForEach(gyms) { g in
                        Button { selected = g } label: { GymRow(gym: g) }.buttonStyle(.plain)
                    }
                    Text("Results from Apple Maps. Check opening hours and day passes with the gym.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Find a gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(item: $selected) { g in
                GymDetailView(gym: g, onPick: onPick == nil ? nil : { ref in
                    onPick?(ref)
                    dismiss()
                })
            }
            .task {
                if !place.trimmingCharacters(in: .whitespaces).isEmpty {
                    placeText = place
                    mode = .place
                }
                await search()
            }
            .onChange(of: mode) { _, _ in Task { await search() } }
        }
        .preferredColorScheme(.dark)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach([Mode.nearMe, .place], id: \.self) { m in
                Button { mode = m } label: {
                    Label(m == .nearMe ? "Near me" : "Near a place", systemImage: m == .nearMe ? "location.fill" : "mappin")
                        .font(Theme.label(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(mode == m ? Theme.ink : .white)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(mode == m ? Theme.lime : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
    }

    private func search() async {
        failure = nil
        loading = true
        defer { loading = false }
        let origin: CLLocation?
        switch mode {
        case .nearMe:
            let l = locator ?? OneShotLocation()
            locator = l
            origin = await l.current()
            if origin == nil { failure = "Location unavailable. Allow location for MonkeyWorkout in Settings, or search near a place." }
        case .place:
            let q = placeText.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else {
                gyms = []
                return
            }
            origin = await GymFinder.locate(q)
            if origin == nil { failure = "Couldn't find \"\(q)\"." }
        }
        guard let origin else {
            gyms = []
            return
        }
        center = origin
        gyms = await GymFinder.gyms(near: origin)
        if gyms.isEmpty && failure == nil { failure = "No gyms found nearby." }
        camera = .region(MKCoordinateRegion(center: origin.coordinate, latitudinalMeters: 6_000, longitudinalMeters: 6_000))
    }
}

extension FoundGym: Hashable {
    static func == (a: FoundGym, b: FoundGym) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

private struct GymRow: View {
    let gym: FoundGym

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(gym.name).font(.system(size: 16, weight: .heavy, design: .rounded)).lineLimit(1)
                Text(gym.address).font(.caption.weight(.medium)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let d = GymFinder.distance(gym.distance) {
                Text(d).font(Theme.display(17)).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
    }
}

/// What Apple Maps knows about a gym, shown in the app before any website.
struct GymDetailView: View {
    let gym: FoundGym
    var onPick: ((GymRef) -> Void)?
    @Environment(\.openURL) private var openURL

    init(gym: FoundGym, onPick: ((GymRef) -> Void)? = nil) {
        self.gym = gym
        self.onPick = onPick
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(gym.name).font(Theme.display(28)).fixedSize(horizontal: false, vertical: true)
                    if let d = GymFinder.distance(gym.distance) {
                        Label("\(d) away", systemImage: "location.fill").font(Theme.label(14)).opacity(0.9)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))

                Map(initialPosition: .region(MKCoordinateRegion(center: gym.coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                    Marker(gym.name, systemImage: "dumbbell.fill", coordinate: gym.coordinate).tint(Theme.lime)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    if !gym.address.isEmpty { info("mappin.and.ellipse", "Address", gym.address) }
                    if let phone = gym.item.phoneNumber, !phone.isEmpty {
                        Button {
                            let digits = phone.filter { $0.isNumber || $0 == "+" }
                            if let url = URL(string: "tel:\(digits)") { openURL(url) }
                        } label: { info("phone.fill", "Phone", phone) }
                        .buttonStyle(.plain)
                    }
                    if let host = gym.item.url?.host() { info("globe", "Website", host) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if let onPick {
                    Button { onPick(gym.ref) } label: { Label("Use this gym", systemImage: "checkmark") }
                        .buttonStyle(LimeButtonStyle())
                }
                HStack(spacing: 10) {
                    action("Directions", "arrow.triangle.turn.up.right.diamond.fill", .cardio) {
                        _ = gym.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                    }
                    action("Hours & photos", "clock.fill", .warmup) {
                        _ = gym.item.openInMaps()
                    }
                }
                if let url = gym.item.url {
                    action("Open website", "safari.fill", .mobility) { openURL(url) }
                }
                Text("Details from Apple Maps. Hours & photos opens the gym's Apple Maps place card.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func info(_ symbol: String, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.lime).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).eyebrow()
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
    }

    private func action(_ title: String, _ symbol: String, _ category: WorkoutEngine.Category, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(Theme.label(14)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(category.gradient))
        }
        .buttonStyle(.plain)
    }
}
