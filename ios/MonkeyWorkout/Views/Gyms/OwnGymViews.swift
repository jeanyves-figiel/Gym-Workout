import CoreLocation
import MapKit
import SwiftUI
import WorkoutEngine

// Your own gym (#680): one Apple Maps doesn't know. A name, and if you like an address or a pin; then the usual setup.

/// "Add "Kraftwerk"" at the end of a gym list (design A): opens the form with the search text as the name.
struct AddOwnGymRow: View {
    var name: String = ""
    let action: () -> Void

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .heavy))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(trimmed.isEmpty ? "Add your own gym" : "Add \"\(trimmed)\"")
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(2)
                    Text("Not on the map · your own gym").font(.caption.weight(.semibold)).opacity(0.85)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WorkoutEngine.Category.power.gradient))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Name it, add an address or a pin, then set up its machines")
    }
}

/// Name (required), address and pin (optional) for a gym without a map place. Tap the map to move the pin;
/// an address typed moves it, a pin dropped fills the address.
struct OwnGymSheet: View {
    var name: String = ""
    /// A pin already dropped on the finder's map (design B).
    var pin: CLLocationCoordinate2D?
    let onDone: (GymRef) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var gymName: String
    @State private var address = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var locating = false
    @State private var closeGuard = CloseGuard()
    @FocusState private var focus: Field?

    enum Field { case name, address }

    /// `address`: brought back by Undo (#717) with the name and pin.
    init(name: String = "", pin: CLLocationCoordinate2D? = nil, address: String = "", onDone: @escaping (GymRef) -> Void) {
        self.name = name
        self.pin = pin
        self.onDone = onDone
        _gymName = State(initialValue: name.trimmingCharacters(in: .whitespaces))
        _address = State(initialValue: address)
        _coordinate = State(initialValue: pin)
        if let pin {
            _camera = State(initialValue: .region(MKCoordinateRegion(center: pin, latitudinalMeters: 800, longitudinalMeters: 800)))
        }
    }

    private var trimmedName: String { gymName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Name").eyebrow()
                    field("dumbbell.fill", "Gym name", text: $gymName, focus: .name)
                    Text("Where · optional").eyebrow().padding(.top, 4)
                    field("mappin.and.ellipse", "Address", text: $address, focus: .address)
                    map
                    HStack(spacing: 10) {
                        Button { Task { await useMyLocation() } } label: {
                            Label(locating ? "Locating…" : "Use my location", systemImage: "location.fill")
                                .font(Theme.label(13)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(WorkoutEngine.Category.cardio.gradient))
                        }
                        .buttonStyle(.plain)
                        .disabled(locating)
                        if coordinate != nil {
                            Button {
                                coordinate = nil
                            } label: {
                                Label("Remove pin", systemImage: "mappin.slash")
                                    .font(Theme.label(13)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("NEXT · SET UP MACHINES") {
                        closeGuard.done()
                        onDone(SavedGym.customRef(name: trimmedName, address: address.trimmingCharacters(in: .whitespaces),
                                                  latitude: coordinate?.latitude, longitude: coordinate?.longitude))
                        dismiss()
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(trimmedName.isEmpty)
                    .opacity(trimmedName.isEmpty ? 0.5 : 1)
                    .padding(.top, 4)
                    Text("Tap the map to put the pin on your gym. Your own gyms stay private.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add your gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .task {
                if let pin, address.isEmpty { address = await Self.address(at: pin) ?? "" }
                if pin == nil && trimmedName.isEmpty { focus = .name }
            }
        }
        .preferredColorScheme(.dark)
        .undoableClose(closeGuard, offer: undoOffer)
    }

    /// Undo bar when a name, address or pin was entered (#717): reopens the form with them.
    private var undoOffer: UndoOffer? {
        let typedAddress = address.trimmingCharacters(in: .whitespaces)
        let moved = coordinate?.latitude != pin?.latitude || coordinate?.longitude != pin?.longitude
        guard trimmedName != name.trimmingCharacters(in: .whitespaces) || moved || pin == nil && !typedAddress.isEmpty
        else { return nil }
        let kept = (gymName, coordinate, address)
        let done = onDone
        return UndoOffer(title: "Gym closed", detail: undoDetail(trimmedName, typedAddress), symbol: "dumbbell.fill",
                         colors: WorkoutEngine.Category.power.colors) {
            AnyView(OwnGymSheet(name: kept.0, pin: kept.1, address: kept.2, onDone: done))
        }
    }

    private func field(_ symbol: String, _ prompt: String, text: Binding<String>, focus f: Field) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.muted)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(f == .address ? .search : .next)
                .focused($focus, equals: f)
                .onSubmit {
                    if f == .address { Task { await findAddress() } } else { focus = .address }
                }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.lime, lineWidth: focus == f ? 2 : 0))
        )
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if let coordinate {
                    Marker(trimmedName.isEmpty ? "Your gym" : trimmedName, systemImage: "dumbbell.fill", coordinate: coordinate)
                        .tint(Theme.lime)
                }
            }
            .onTapGesture { point in
                guard let c = proxy.convert(point, from: .local) else { return }
                focus = nil
                coordinate = c
                Task { if let a = await Self.address(at: c) { address = a } }
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityLabel(coordinate == nil ? "Map, tap to put a pin on your gym" : "Map with your gym's pin")
    }

    private func move(to c: CLLocationCoordinate2D) {
        coordinate = c
        withAnimation(.snappy) {
            camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 800, longitudinalMeters: 800))
        }
    }

    private func findAddress() async {
        let q = address.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3, let location = await GymFinder.locate(q) else { return }
        move(to: location.coordinate)
    }

    private func useMyLocation() async {
        locating = true
        defer { locating = false }
        guard let location = await OneShotLocation().current() else { return }
        move(to: location.coordinate)
        if let a = await Self.address(at: location.coordinate) { address = a }
    }

    /// Street and town at a pin.
    static func address(at c: CLLocationCoordinate2D) async -> String? {
        guard let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        else { return nil }
        let street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, p.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// What opens the own-gym form: a name typed in a search, or a pin dropped on the map.
struct OwnGymDraft: Identifiable {
    let id = UUID()
    var name = ""
    var pin: CLLocationCoordinate2D?
}
