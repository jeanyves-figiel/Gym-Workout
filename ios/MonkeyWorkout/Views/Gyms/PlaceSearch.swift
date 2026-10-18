import CoreLocation
import MapKit
import SwiftUI
import WorkoutEngine

// Near a place search (#447): bold cards before typing, Apple Maps suggestions with lit letters
// and "Did you mean …?" while typing. The gym finder shows the top match's gyms on its map live.

/// Apple Maps autocomplete for the place field.
@MainActor
@Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    /// The fragment the current results answer (results can arrive after the field changed again).
    private(set) var answered = ""
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    var query: String {
        get { completer.queryFragment }
        set {
            let q = newValue.trimmingCharacters(in: .whitespaces)
            if q.isEmpty {
                completer.cancel()
                results = []
                answered = ""
            } else {
                completer.queryFragment = q
            }
        }
    }

    /// Suggestions near here come first.
    func bias(_ location: CLLocation) {
        completer.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            results = completer.results
            answered = completer.queryFragment
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            results = []
            answered = completer.queryFragment
        }
    }
}

/// Places searched before, on this device only.
enum RecentPlaces {
    private static let key = "placeSearch.recents"

    static func load() -> [PlaceSuggestion] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PlaceSuggestion].self, from: data)) ?? []
    }

    static func remember(_ place: PlaceSuggestion) -> [PlaceSuggestion] {
        let list = PlaceSuggest.remember(place, in: load())
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
        return list
    }
}

/// One row in the suggestion list: a known place or an Apple Maps completion.
struct PlaceOption: Identifiable {
    var title: String
    var subtitle: String
    var symbol: String
    var known: PlaceSuggestion?
    var completion: MKLocalSearchCompletion?
    var id: String { PlaceSuggest.fold(title + " " + subtitle) }

    /// Known places first (typos allowed), then Apple Maps, same place once.
    static func list(query: String, known: [PlaceSuggestion], completions: [MKLocalSearchCompletion], limit: Int = 4) -> [PlaceOption] {
        var out: [PlaceOption] = PlaceSuggest.matches(query, in: known, limit: 2).map {
            PlaceOption(title: $0.title, subtitle: $0.subtitle, symbol: $0.kind.symbol, known: $0)
        }
        let knownTitles = Set(out.map { PlaceSuggest.fold($0.title) })
        var seen = Set<String>()
        for c in completions where out.count < limit {
            guard !knownTitles.contains(PlaceSuggest.fold(c.title)),
                  seen.insert(PlaceSuggest.fold(c.title + " " + c.subtitle)).inserted else { continue }
            out.append(PlaceOption(title: c.title, subtitle: c.subtitle, symbol: c.subtitle.isEmpty ? "building.2.fill" : "mappin.circle.fill",
                                   completion: c))
        }
        return out
    }
}

extension PlaceSuggestion.Kind {
    var symbol: String {
        switch self {
        case .trip: "airplane"
        case .recent: "clock.arrow.circlepath"
        case .gym: "dumbbell.fill"
        case .here: "location.fill"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .trip: WorkoutEngine.Category.warmup.gradient
        case .recent: WorkoutEngine.Category.strength.gradient
        case .gym: WorkoutEngine.Category.cardio.gradient
        case .here: WorkoutEngine.Category.mobility.gradient
        }
    }

    var label: String {
        switch self {
        case .trip: "Trip"
        case .recent: "Searched before"
        case .gym: "Your gym"
        case .here: "You're here"
        }
    }
}

/// Before typing: bold cards for trips, recent places, your gyms' towns and where you are.
struct PlaceCards: View {
    let places: [PlaceSuggestion]
    /// Gyms found around each place, filled in as they load.
    let counts: [String: Int]
    let onPick: (PlaceSuggestion) -> Void
    let onAppear: (PlaceSuggestion) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(places) { p in
                Button { onPick(p) } label: { card(p) }
                    .buttonStyle(.plain)
                    .onAppear { onAppear(p) }
            }
        }
    }

    private func card(_ p: PlaceSuggestion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: p.kind.symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.system(size: 17, weight: .heavy, design: .rounded)).lineLimit(1)
                Text(p.subtitle.isEmpty ? p.kind.label : "\(p.kind.label) · \(p.subtitle)")
                    .font(.caption.weight(.medium)).opacity(0.88).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let n = counts[p.id] {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(n)").font(Theme.display(22)).monospacedDigit()
                    Text(n == 1 ? "gym" : "gyms").font(.system(size: 10, weight: .bold)).opacity(0.85)
                }
            } else {
                Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .heavy)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(p.kind.gradient))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Finds gyms near \(p.title)")
    }
}

/// While typing: suggestions with the matching letters lit, floating over the live map.
struct PlaceOptionList: View {
    let query: String
    let options: [PlaceOption]
    let onPick: (PlaceOption) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { i, o in
                Button { onPick(o) } label: { row(o) }.buttonStyle(.plain)
                if i < options.count - 1 { Divider().overlay(.white.opacity(0.08)).padding(.leading, 48) }
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.bg.opacity(0.93)))
    }

    private func row(_ o: PlaceOption) -> some View {
        HStack(spacing: 10) {
            Image(systemName: o.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardStrong))
            VStack(alignment: .leading, spacing: 1) {
                Text(lit(o.title)).font(.subheadline.weight(.bold)).lineLimit(1)
                if !o.subtitle.isEmpty {
                    Text(o.subtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func lit(_ title: String) -> AttributedString {
        var s = AttributedString(title)
        for r in PlaceSuggest.highlight(query, in: title) {
            guard let lo = AttributedString.Index(r.lowerBound, within: s),
                  let hi = AttributedString.Index(r.upperBound, within: s) else { continue }
            s[lo..<hi].foregroundColor = Theme.lime
        }
        return s
    }
}

/// "Did you mean Barcelona?" when the spelling looks off.
struct DidYouMean: View {
    let name: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Did you mean ") + Text(name).underline().bold() + Text("?")
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.lime)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.lime.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.lime.opacity(0.35)))
            )
        }
        .buttonStyle(.plain)
    }
}

extension GymFinder {
    /// The place behind an Apple Maps suggestion.
    static func locate(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
    }

    /// What Apple Maps thinks a misspelt place is ("barcleona" → "Barcelona"), nil when it reads the same.
    static func spellingGuess(_ query: String) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let name = item.placemark.locality.flatMap { loc in
            PlaceSuggest.score(query, loc) != nil ? loc : nil
        } ?? item.name ?? item.placemark.locality
        guard let name, !PlaceSuggest.fold(name).hasPrefix(PlaceSuggest.fold(query)) else { return nil }
        return name
    }

    /// The town at a point, for the "You're here" card.
    static func town(at location: CLLocation) async -> String? {
        try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality
    }
}
