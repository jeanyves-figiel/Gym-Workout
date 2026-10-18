import Foundation

// Place search suggestions (#447): what "Find a gym → Near a place" offers before and while typing,
// and the spelling help ("Did you mean …?") that works without the network.

/// A place offered before the member types.
public struct PlaceSuggestion: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// An upcoming or current trip (calendar travel period).
        case trip
        /// A place searched before (kept on the device).
        case recent
        /// Where one of the member's saved gyms is.
        case gym
        /// The town the member is in now.
        case here
    }

    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var latitude: Double?
    public var longitude: Double?

    public var id: String { kind.rawValue + ":" + PlaceSuggest.fold(title) }

    public init(kind: Kind, title: String, subtitle: String = "", latitude: Double? = nil, longitude: Double? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }

    public var hasCoordinate: Bool { latitude != nil && longitude != nil }
}

public enum PlaceSuggest {
    /// Most recent places kept.
    public static let recentLimit = 8
    /// Most cards shown before typing.
    public static let initialLimit = 6

    /// Lowercased, accents and punctuation dropped: "Zürich-Oerlikon " → "zurich oerlikon".
    public static func fold(_ s: String) -> String {
        let plain = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
        let mapped = plain.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Place part of a saved gym's address: "Badenerstrasse 1, 8952 Schlieren, Switzerland" → "Schlieren".
    public static func town(fromAddress address: String) -> String? {
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // A part with a postcode is the town ("8952 Schlieren", "10117 Berlin").
        for p in parts {
            let words = p.split(separator: " ")
            if words.count >= 2, words[0].allSatisfy(\.isNumber) {
                return words.dropFirst().joined(separator: " ")
            }
        }
        if parts.count >= 2 { return parts[parts.count >= 3 ? parts.count - 2 : 1] }
        return nil
    }

    /// Cards before typing: trips ahead (soonest first), recent places, saved gyms' towns, then where you are.
    /// The same place shows once, under its first kind.
    public static func initial(
        trips: [AwayPeriod], recents: [PlaceSuggestion], gyms: [GymRef], here: PlaceSuggestion?,
        today: String, limit: Int = initialLimit
    ) -> [PlaceSuggestion] {
        var out: [PlaceSuggestion] = []
        var seen = Set<String>()
        func add(_ s: PlaceSuggestion) {
            let key = fold(s.title)
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            out.append(s)
        }
        for t in trips where t.kind == .travel && t.end >= today {
            guard let place = t.note?.trimmingCharacters(in: .whitespaces), !place.isEmpty else { continue }
            add(PlaceSuggestion(kind: .trip, title: place, subtitle: tripDates(t)))
        }
        recents.forEach(add)
        for g in gyms {
            guard let town = town(fromAddress: g.address) else { continue }
            add(PlaceSuggestion(kind: .gym, title: town, subtitle: g.name, latitude: g.latitude, longitude: g.longitude))
        }
        if let here { add(here) }
        return Array(out.prefix(limit))
    }

    /// "24–28 Oct" / "30 Oct – 2 Nov" from day keys.
    static func tripDates(_ t: AwayPeriod) -> String {
        let a = t.start.split(separator: "-").compactMap { Int($0) }
        let b = t.end.split(separator: "-").compactMap { Int($0) }
        guard a.count == 3, b.count == 3 else { return "" }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let ma = months[max(0, min(11, a[1] - 1))], mb = months[max(0, min(11, b[1] - 1))]
        if t.start == t.end { return "\(a[2]) \(ma)" }
        return a[1] == b[1] ? "\(a[2])–\(b[2]) \(ma)" : "\(a[2]) \(ma) – \(b[2]) \(mb)"
    }

    /// Adds a searched place on top of the recent list (same place moves up), keeps `recentLimit`.
    public static func remember(_ place: PlaceSuggestion, in list: [PlaceSuggestion]) -> [PlaceSuggestion] {
        var p = place
        p.kind = .recent
        let key = fold(p.title)
        return Array(([p] + list.filter { fold($0.title) != key }).prefix(recentLimit))
    }

    // MARK: Spelling

    /// Edit distance with swapped neighbours counting as one edit ("barcleona" → "barcelona" = 1).
    public static func distance(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var d = Array(repeating: Array(repeating: 0, count: t.count + 1), count: s.count + 1)
        for i in 0...s.count { d[i][0] = i }
        for j in 0...t.count { d[0][j] = j }
        for i in 1...s.count {
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[s.count][t.count]
    }

    /// Edits allowed for a typed word of this length: 1 up to 5 letters, 2 up to 8, then 3.
    static func allowed(_ length: Int) -> Int { length <= 2 ? 0 : length <= 5 ? 1 : length <= 8 ? 2 : 3 }

    /// How well a typed query matches a name; nil = no match. Lower is better.
    /// Exact prefix scores 0; a near prefix (typos within `allowed`) scores its edit count.
    public static func score(_ query: String, _ name: String) -> Int? {
        let q = fold(query), n = fold(name)
        guard q.count >= 2, !n.isEmpty else { return nil }
        if n.hasPrefix(q) { return 0 }
        if n.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 0 }
        let budget = allowed(q.count)
        guard budget > 0 else { return nil }
        // Compare against the name's start of similar length, and each word's start.
        var best = Int.max
        for candidate in [n] + n.split(separator: " ").map(String.init) {
            let lo = max(1, q.count - budget), hi = min(candidate.count, q.count + budget)
            guard lo <= hi else { continue }
            for len in lo...hi {
                best = min(best, distance(q, String(candidate.prefix(len))))
            }
        }
        return best <= budget ? best : nil
    }

    /// Known places matching what's typed, typos allowed, best first.
    public static func matches(_ query: String, in places: [PlaceSuggestion], limit: Int = 3) -> [PlaceSuggestion] {
        places.enumerated().compactMap { i, p in score(query, p.title).map { (p, $0, i) } }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .prefix(limit)
            .map(\.0)
    }

    /// "Did you mean …?": the closest name that isn't what was typed, or nil when the typing already matches.
    public static func correction(for query: String, among names: [String]) -> String? {
        let q = fold(query)
        guard q.count >= 3 else { return nil }
        if names.contains(where: { fold($0).hasPrefix(q) }) { return nil }
        let scored = names.compactMap { n -> (String, Int)? in
            guard let s = score(query, n), s > 0 else { return nil }
            return (n, s)
        }
        return scored.min { $0.1 < $1.1 }?.0
    }

    /// Ranges of `name` to light up: the start of each word that matches the start of a typed word.
    public static func highlight(_ query: String, in name: String) -> [Range<String.Index>] {
        let words = fold(query).split(separator: " ").map { Array($0) }
        guard !words.isEmpty else { return [] }
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        var out: [Range<String.Index>] = []
        var i = name.startIndex
        while i < name.endIndex {
            guard isWord(name[i]) else {
                i = name.index(after: i)
                continue
            }
            let start = i
            var letters: [(Character, String.Index)] = []
            while i < name.endIndex, isWord(name[i]) {
                letters.append((fold(String(name[i])).first ?? name[i], name.index(after: i)))
                i = name.index(after: i)
            }
            var best = 0, bestEnd = start
            for w in words {
                let n = zip(letters, w).prefix { $0.0.0 == $0.1 }.count
                if n > best, n >= min(2, w.count) {
                    best = n
                    bestEnd = letters[n - 1].1
                }
            }
            if best > 0 { out.append(start..<bestEnd) }
        }
        return out
    }
}
