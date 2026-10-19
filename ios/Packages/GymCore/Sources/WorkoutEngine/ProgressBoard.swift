import Foundation

// Customisable Progress page (#444, design A + C from `history-page/custom-proposals.png`): the page is a board of
// widgets on Train's system (#260): order, size small / wide / large, presets. A tap opens the widget's detail page.
// C: optional sport widgets, one per sport, for members who focus on one or more sports.
// Synced with the profile; nil = the default board.

/// What a Progress widget shows.
public enum ProgressWidgetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case level, streak, training, body, records, badges, muscles, history, programmes, consistency, weekly
    /// One sport's sessions (C); the widget carries the sport.
    case sport
    /// This week's chest and XP earned, and the last 8 weeks' chests (#476).
    case chest
    /// Growth path (#495): goal with its predicted date, milestones, what Monkey noticed.
    case growth

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .level: "Level"
        case .streak: "Streak"
        case .training: "Training"
        case .body: "Body"
        case .records: "Records"
        case .badges: "Badges"
        case .muscles: "Muscles"
        case .history: "Recent sessions"
        case .programmes: "Programmes"
        case .consistency: "Consistency"
        case .weekly: "Sessions per week"
        case .sport: "Sport"
        case .chest: "Week chest"
        case .growth: "Growth path"
        }
    }

    public var detail: String {
        switch self {
        case .level: "Level, rank and XP to the next level"
        case .streak: "Weeks in a row at your goal"
        case .training: "This week, live tiles, trends and other sports"
        case .body: "Weight, girths, body fat and VO₂ max"
        case .records: "Your best lifts"
        case .badges: "Unlocked badges and the next one"
        case .muscles: "Muscle balance of the last 28 days"
        case .history: "Your last sessions, See all opens History"
        case .programmes: "Your programme's week, lifts start vs now"
        case .consistency: "12 weeks of training days"
        case .weekly: "Sessions per week with your goal"
        case .sport: "One sport: sessions, time and its best"
        case .chest: "This week's chest and XP, and the last 8 weeks"
        case .growth: "Your goal, its predicted date and what Monkey noticed"
        }
    }

    public var sizes: [TrainWidgetSize] {
        switch self {
        case .level, .streak, .consistency, .chest, .growth: [.wide]
        case .training, .body, .records, .badges, .muscles, .programmes: [.small, .wide]
        case .history: [.small, .wide]
        case .weekly: [.wide, .large]
        case .sport: [.small, .wide, .large]
        }
    }

    public var defaultSize: TrainWidgetSize {
        switch self {
        case .level, .streak, .history, .consistency, .weekly, .programmes, .chest, .growth: .wide
        default: .small
        }
    }
}

public struct ProgressWidget: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: ProgressWidgetKind
    public var size: TrainWidgetSize
    /// The sport of a `.sport` widget; nil for every other kind.
    public var sport: Sport?

    public init(_ kind: ProgressWidgetKind, size: TrainWidgetSize? = nil, sport: Sport? = nil, id: UUID? = nil) {
        self.kind = kind
        self.sport = kind == .sport ? (sport ?? .other) : nil
        self.id = id ?? Self.stableId(kind, self.sport)
        self.size = size.flatMap { kind.sizes.contains($0) ? $0 : nil } ?? kind.defaultSize
    }

    public static func sport(_ s: Sport, size: TrainWidgetSize? = nil) -> ProgressWidget { ProgressWidget(.sport, size: size, sport: s) }

    /// One id per kind (and per sport), so a board built fresh keeps its views' identity.
    static func stableId(_ kind: ProgressWidgetKind, _ sport: Sport?) -> UUID {
        let k = (ProgressWidgetKind.allCases.firstIndex(of: kind) ?? 0) + 1
        let s = sport.flatMap { Sport.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        return UUID(uuidString: String(format: "9B0A0000-0000-4000-8000-%06d%06d", k, s))!
    }

    public var title: String { sport?.label ?? kind.title }

    public var nextSize: TrainWidgetSize {
        let s = kind.sizes
        guard let i = s.firstIndex(of: size) else { return kind.defaultSize }
        return s[(i + 1) % s.count]
    }

    private enum CodingKeys: String, CodingKey { case id, kind, size, sport }

    /// Unknown sizes or sports (written by a newer app) fall back; an unknown kind throws and the board skips it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(ProgressWidgetKind.self, forKey: .kind)
        self.init(kind,
                  size: (try? c.decode(String.self, forKey: .size)).flatMap(TrainWidgetSize.init(rawValue:)),
                  sport: (try? c.decode(String.self, forKey: .sport)).flatMap(Sport.init(rawValue:)),
                  id: try? c.decode(UUID.self, forKey: .id))
    }
}

/// A row of the 2-column board: one full-width widget, or up to two small ones side by side.
public enum ProgressRow: Equatable, Sendable, Identifiable {
    case full(ProgressWidget)
    case pair(ProgressWidget, ProgressWidget?)

    public var id: UUID {
        switch self {
        case .full(let w): w.id
        case .pair(let a, _): a.id
        }
    }
}

public struct ProgressBoard: Codable, Equatable, Sendable {
    public var widgets: [ProgressWidget]

    public init(_ widgets: [ProgressWidget]) { self.widgets = widgets }

    private enum CodingKeys: String, CodingKey { case widgets }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var list = try c.nestedUnkeyedContainer(forKey: .widgets)
        var out: [ProgressWidget] = []
        while !list.isAtEnd {
            if let w = try? list.decode(ProgressWidget.self) {
                if !out.contains(where: { $0.kind == w.kind && $0.sport == w.sport }) { out.append(w) }
            } else if (try? list.decode(Skip.self)) == nil {
                break
            }
        }
        widgets = out
    }

    private struct Skip: Decodable {}

    /// Small widgets pair up in order; a small one followed by a full-width one sits alone on the left.
    public var rows: [ProgressRow] {
        var out: [ProgressRow] = []
        var pending: ProgressWidget?
        for w in widgets {
            if w.size == .small {
                if let p = pending {
                    out.append(.pair(p, w))
                    pending = nil
                } else {
                    pending = w
                }
            } else {
                if let p = pending { out.append(.pair(p, nil)) }
                pending = nil
                out.append(.full(w))
            }
        }
        if let p = pending { out.append(.pair(p, nil)) }
        return out
    }

    public func contains(_ kind: ProgressWidgetKind) -> Bool { widgets.contains { $0.kind == kind } }
    public func contains(sport: Sport) -> Bool { widgets.contains { $0.sport == sport } }

    /// Kinds not on the board yet (sport widgets are added per sport).
    public var addable: [ProgressWidgetKind] { ProgressWidgetKind.allCases.filter { $0 != .sport && !contains($0) } }

    public mutating func add(_ w: ProgressWidget, at index: Int? = nil) {
        guard !widgets.contains(where: { $0.kind == w.kind && $0.sport == w.sport }) else { return }
        widgets.insert(w, at: min(max(0, index ?? widgets.count), widgets.count))
    }

    public mutating func remove(_ id: UUID) { widgets.removeAll { $0.id == id } }

    public mutating func update(_ id: UUID, _ change: (inout ProgressWidget) -> Void) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        change(&widgets[i])
        let w = widgets[i]
        widgets[i] = ProgressWidget(w.kind, size: w.size, sport: w.sport, id: w.id)
    }

    /// Moves `id` to where `target` is (drag to reorder).
    public mutating func move(_ id: UUID, to target: UUID) {
        guard id != target, let from = widgets.firstIndex(where: { $0.id == id }),
              let to = widgets.firstIndex(where: { $0.id == target }) else { return }
        let w = widgets.remove(at: from)
        widgets.insert(w, at: to)
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { widgets[$0] }
        var rest = widgets.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(0, insertAt), rest.count))
        widgets = rest
    }

    // MARK: Presets

    public enum Preset: String, CaseIterable, Sendable, Identifiable {
        case classic, lifter, sports, minimal

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .classic: "Classic"
            case .lifter: "Lifter"
            case .sports: "My sports"
            case .minimal: "Minimal"
            }
        }

        public var detail: String {
            switch self {
            case .classic: "Level, streak, every part of Progress and recent sessions"
            case .lifter: "Records, weekly sessions, muscles and body first"
            case .sports: "A big card for each of your sports up top"
            case .minimal: "Streak, this week and recent sessions"
            }
        }
    }

    /// The default board: today's Progress page as widgets.
    public static var classic: ProgressBoard {
        ProgressBoard([
            ProgressWidget(.level), ProgressWidget(.chest), ProgressWidget(.streak), ProgressWidget(.growth),
            ProgressWidget(.training), ProgressWidget(.body), ProgressWidget(.records), ProgressWidget(.badges),
            ProgressWidget(.muscles), ProgressWidget(.programmes, size: .small),
            ProgressWidget(.history), ProgressWidget(.consistency), ProgressWidget(.weekly),
        ])
    }

    /// `sports`: the member's sports, most important first (climbing for climbers).
    public static func preset(_ p: Preset, sports: [Sport]) -> ProgressBoard {
        switch p {
        case .classic:
            return classic
        case .lifter:
            return ProgressBoard([
                ProgressWidget(.streak), ProgressWidget(.growth), ProgressWidget(.records), ProgressWidget(.training), ProgressWidget(.weekly, size: .large),
                ProgressWidget(.muscles), ProgressWidget(.body), ProgressWidget(.history), ProgressWidget(.programmes, size: .small),
                ProgressWidget(.badges),
            ])
        case .sports:
            let own = sports.isEmpty ? [Sport.climbing] : Array(sports.prefix(3))
            return ProgressBoard(own.enumerated().map { i, s in .sport(s, size: i == 0 ? .large : .wide) } + [
                ProgressWidget(.streak), ProgressWidget(.history), ProgressWidget(.training), ProgressWidget(.records),
                ProgressWidget(.consistency),
            ])
        case .minimal:
            return ProgressBoard([ProgressWidget(.streak), ProgressWidget(.training, size: .wide), ProgressWidget(.history)])
        }
    }

    /// Same widgets, sizes and sports in the same order (ids ignored).
    public func matches(_ other: ProgressBoard) -> Bool {
        widgets.map { [$0.kind.rawValue, $0.size.rawValue, $0.sport?.rawValue ?? ""] }
            == other.widgets.map { [$0.kind.rawValue, $0.size.rawValue, $0.sport?.rawValue ?? ""] }
    }
}
