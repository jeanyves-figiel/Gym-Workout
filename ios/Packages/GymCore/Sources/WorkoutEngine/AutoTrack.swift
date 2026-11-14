import Foundation

// MARK: - Invisible Monkey (#1087, Direction A from `auto-tracking/direction-a.png`)
//
// Water, meals and gym visits found by the Watch, the iPhone's photos and the home gym's location, so the member
// doesn't type them. Each find has a confidence; the ladder decides: sure → logged at once (with Undo), fair → a
// one-tap card (Keep / Fix / Bin), weak → dropped. Everything stays on the device.

/// What Monkey noticed.
public enum AutoKind: String, Codable, Sendable { case water, meal, gym }

/// Where it came from.
public enum AutoSource: String, Codable, Sendable {
    /// Wrist tilts on the Watch.
    case sips
    /// A run of bites on the Watch.
    case bites
    /// A food photo in the member's library.
    case photo
    /// Arrived at the home gym.
    case place
}

/// Where a find stands.
public enum AutoState: String, Codable, Sendable {
    /// Logged by itself (sure); Undo puts it back.
    case logged
    /// Waiting for a tap.
    case pending
    /// The member kept or fixed it.
    case kept
    /// Binned or undone.
    case dismissed
}

public struct AutoEvent: Codable, Hashable, Sendable, Identifiable {
    /// Stable for the same find, so a second report of it is not counted twice.
    public var id: String
    public var kind: AutoKind
    public var source: AutoSource
    public var start: Date
    public var end: Date
    /// 0–1.
    public var confidence: Double
    public var state: AutoState
    /// Water: millilitres.
    public var ml: Int?
    /// Meal from the Watch: bites counted. Water: sips.
    public var count: Int?
    /// Photo: the Photos library's local id (never copied out of the library).
    public var photoId: String?
    /// Photo: what the on-device classifier saw ("Croissant").
    public var title: String?

    public init(id: String, kind: AutoKind, source: AutoSource, start: Date, end: Date, confidence: Double,
                state: AutoState = .pending, ml: Int? = nil, count: Int? = nil, photoId: String? = nil, title: String? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
        self.start = start
        self.end = end
        self.confidence = max(0, min(1, confidence))
        self.state = state
        self.ml = ml
        self.count = count
        self.photoId = photoId
        self.title = title
    }

    /// Percent shown on the card ("92%").
    public var percent: Int { Int((confidence * 100).rounded()) }
}

/// Which senses are on. All off until the member turns them on.
public struct AutoTrackPrefs: Codable, Hashable, Sendable {
    /// Watch: sips → water.
    public var sips = false
    /// Watch: runs of bites → meal times.
    public var bites = false
    /// iPhone: new food photos → meals.
    public var photos = false
    /// iPhone: arriving at the home gym → start prompt.
    public var gym = false
    /// Millilitres one sip counts for.
    public var mlPerSip = AutoTrack.defaultSip

    public init() {}

    public var anyOn: Bool { sips || bites || photos || gym }
    /// The Watch records wrist motion only when one of its senses is on.
    public var watchOn: Bool { sips || bites }
}

public enum AutoTrack {
    /// At or above: logged at once, with Undo.
    public static let sure = 0.85
    /// At or above (and under `sure`): a one-tap card. Below: dropped.
    public static let fair = 0.6
    public static let defaultSip = 30
    public static let sipRange = 15...60
    /// Sips closer than this are one drink.
    public static let drinkGap: TimeInterval = 15 * 60
    /// Finds kept on the device this long.
    public static let keepDays = 14

    public enum Step: Equatable, Sendable { case log, ask, drop }

    public static func step(_ confidence: Double) -> Step {
        confidence >= sure ? .log : confidence >= fair ? .ask : .drop
    }

    /// One sip from the Watch.
    public struct Sip: Equatable, Sendable {
        public var date: Date
        public var confidence: Double
        public init(date: Date, confidence: Double) {
            self.date = date
            self.confidence = confidence
        }
    }

    /// Sips grouped into drinks: each drink is more certain than its surest sip, a little per extra sip (one tilt can be
    /// a yawn, five in ten minutes is a glass).
    public static func drinks(_ sips: [Sip], mlPerSip: Int) -> [AutoEvent] {
        let sorted = sips.sorted { $0.date < $1.date }
        var out: [AutoEvent] = []
        var run: [Sip] = []
        func close() {
            defer { run = [] }
            guard let a = run.first, let b = run.last else { return }
            let best = run.map(\.confidence).max() ?? 0
            let c = min(0.97, best + 0.04 * Double(run.count - 1))
            let e = AutoEvent(id: "water|\(Int(a.date.timeIntervalSince1970))", kind: .water, source: .sips, start: a.date, end: b.date,
                              confidence: c, ml: run.count * mlPerSip, count: run.count)
            out.append(e)
        }
        for s in sorted {
            if let last = run.last, s.date.timeIntervalSince(last.date) > drinkGap { close() }
            run.append(s)
        }
        close()
        return out
    }

    /// A meal window from the Watch.
    public static func meal(start: Date, end: Date, bites: Int, confidence: Double) -> AutoEvent {
        AutoEvent(id: "meal|\(Int(start.timeIntervalSince1970))", kind: .meal, source: .bites, start: start, end: end,
                  confidence: confidence, count: bites)
    }

    /// A food photo. Grams need the plate scan, so a photo is always a card, never logged by itself.
    public static func photo(id: String, date: Date, title: String, confidence: Double) -> AutoEvent {
        AutoEvent(id: "photo|\(id)", kind: .meal, source: .photo, start: date, end: date, confidence: max(fair, min(sure - 0.01, confidence)),
                  photoId: id, title: title)
    }

    /// Arrived at the home gym (once a day).
    public static func gym(at date: Date, calendar: Calendar) -> AutoEvent {
        let day = calendar.startOfDay(for: date)
        return AutoEvent(id: "gym|\(Int(day.timeIntervalSince1970))", kind: .gym, source: .place, start: date, end: date, confidence: 0.9, state: .logged)
    }

    /// Wrist movement during a workout is lifting, not drinking or eating.
    public static func outside(_ e: AutoEvent, workouts: [DateInterval]) -> Bool {
        !workouts.contains { $0.intersects(DateInterval(start: e.start, end: max(e.start, e.end))) }
    }

    /// Adds new finds: the ladder sets their state; one already known keeps the member's answer. A Watch meal that
    /// overlaps a photo meal is the same meal: the photo (it can be scanned) wins. Old finds are dropped.
    public static func merge(_ existing: [AutoEvent], new: [AutoEvent], now: Date = Date(), calendar: Calendar = .current) -> [AutoEvent] {
        var byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for var e in new where byId[e.id] == nil {
            switch step(e.confidence) {
            case .drop: continue
            case .ask: e.state = e.kind == .gym ? .logged : .pending
            case .log: e.state = e.source == .photo || e.source == .bites ? .pending : .logged
            }
            byId[e.id] = e
        }
        var out = Array(byId.values)
        let photos = out.filter { $0.source == .photo && $0.state != .dismissed }
        out.removeAll { e in
            e.source == .bites && e.state == .pending && photos.contains { p in
                p.start >= e.start.addingTimeInterval(-30 * 60) && p.start <= e.end.addingTimeInterval(30 * 60)
            }
        }
        let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: now) ?? now
        return out.filter { $0.start >= cutoff }.sorted { $0.start > $1.start }
    }

    /// Millilitres of water logged by itself on that day.
    public static func loggedMl(_ events: [AutoEvent], on day: Date, calendar: Calendar) -> Int {
        events.filter { $0.kind == .water && ($0.state == .logged || $0.state == .kept) && calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0) { $0 + ($1.ml ?? 0) }
    }

    /// Whole glasses the auto water is worth; Fuel counts glasses, so the rest waits for the next sips.
    public static func glasses(ml: Int, glassMl: Int) -> Int { glassMl > 0 ? max(0, ml / glassMl) : 0 }

    /// Today's finds the card shows: newest first, binned ones hidden.
    public static func today(_ events: [AutoEvent], now: Date = Date(), calendar: Calendar) -> [AutoEvent] {
        events.filter { $0.state != .dismissed && calendar.isDate($0.start, inSameDayAs: now) }
    }

    /// "Monkey logged 4 things today" line under the card.
    public static func summary(_ events: [AutoEvent]) -> String {
        let n = events.filter { $0.state == .logged || $0.state == .kept }.count
        let ask = events.filter { $0.state == .pending }.count
        switch (n, ask) {
        case (0, 0): return "Nothing caught yet today"
        case (_, 0): return "Monkey logged \(n) \(n == 1 ? "thing" : "things") today · Undo any"
        case (0, _): return "\(ask) to check · one tap each"
        default: return "Logged \(n) · \(ask) to check"
        }
    }

    /// The meal slot nearest a time (photo or Watch meal → the meal it most likely was).
    public static func slot(_ slots: [FuelSlot], at date: Date, calendar: Calendar) -> FuelSlot? {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return slots.min { abs($0.minute - m) < abs($1.minute - m) }
    }
}
