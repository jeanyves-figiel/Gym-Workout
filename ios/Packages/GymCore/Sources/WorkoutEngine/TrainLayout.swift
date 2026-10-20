import Foundation

// Customisable Train screen (#260, designs A + B from `train-widgets/proposals-full.png`): the member's widgets
// in order, each with a size (A: small / wide / large on a 2-column grid) and a look (B: e.g. calendar as week,
// month or agenda). Synced with the profile; nil = the default layout, which is today's Train screen.

/// What a Train widget shows.
public enum TrainWidgetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case actions, coach, week, level, nextUp, climbing, calendar, streak, volume, records, body, muscles, lastWorkout, thisWeek
    /// Training programme in progress (#255); last so the stable ids of the others stay put.
    case programme
    /// Daily Move (#454): steps and floors from Health.
    case move
    /// Fuel (#496): today's food pointers from the day's training.
    case fuel

    public var id: String { rawValue }

    /// Stable widget id for this kind.
    public var stableId: UUID {
        let n = (Self.allCases.firstIndex(of: self) ?? 0) + 1
        return UUID(uuidString: String(format: "7A1E0000-0000-4000-8000-%012d", n))!
    }

    public var title: String {
        switch self {
        case .actions: "Quick actions"
        case .coach: "Coach monkey"
        case .week: "Week + readiness"
        case .level: "Level"
        case .nextUp: "Next up"
        case .climbing: "Climbing"
        case .calendar: "Calendar"
        case .streak: "Streak"
        case .volume: "Training load"
        case .records: "Records"
        case .body: "Body weight"
        case .muscles: "Muscles worked"
        case .lastWorkout: "Last workout"
        case .thisWeek: "This week's sessions"
        case .programme: "Programme"
        case .move: "Daily Move"
        case .fuel: "Fuel"
        }
    }

    public var detail: String {
        switch self {
        case .actions: "Calendar, Variation and Edit plan buttons"
        case .coach: "Your monkey's mood and a tip, tap for the next"
        case .week: "Sessions done, cycle week and today's readiness"
        case .level: "Level, rank and XP to the next level"
        case .nextUp: "Your next session with Start"
        case .climbing: "Log a climb, climbing days and recent climbs"
        case .calendar: "Planned, done and climbing days"
        case .streak: "Weeks in a row at your goal"
        case .volume: "Kg lifted, minutes or sets with the trend"
        case .records: "Your best lifts"
        case .body: "Latest weight and the change"
        case .muscles: "What you trained in the last 28 days"
        case .lastWorkout: "When, how long and how much"
        case .thisWeek: "Every session of the week, move or add one"
        case .programme: "Your programme's week, phase and test week"
        case .move: "Steps and floors today against your usual, and the XP they earn"
        case .fuel: "Today's food pointers from your training: protein, water, next meal"
        }
    }

    /// Sizes the widget offers, smallest first.
    public var sizes: [TrainWidgetSize] {
        switch self {
        case .actions, .programme: [.wide]
        case .coach, .week, .level, .climbing, .streak, .records, .body, .lastWorkout, .move, .fuel: [.small, .wide]
        case .nextUp, .calendar, .volume: [.small, .wide, .large]
        case .muscles: [.wide, .large]
        case .thisWeek: [.large]
        }
    }

    /// Looks the widget offers (B). Empty = one look.
    public var looks: [TrainWidgetLook] {
        switch self {
        case .calendar: [.week, .month, .agenda]
        case .volume: [.kg, .minutes, .sets]
        case .thisWeek: [.list, .quest]
        default: []
        }
    }

    public var defaultSize: TrainWidgetSize {
        switch self {
        case .actions, .coach, .week, .level, .climbing, .calendar, .muscles, .programme, .move, .fuel: .wide
        case .nextUp, .thisWeek: .large
        default: .small
        }
    }
}

public enum TrainWidgetSize: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Half the width (two side by side).
    case small
    /// Full width, compact.
    case wide
    /// Full width, the most detail.
    case large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "Small"
        case .wide: "Wide"
        case .large: "Large"
        }
    }

    /// One-letter badge on the resize handle.
    public var letter: String {
        switch self {
        case .small: "S"
        case .wide: "W"
        case .large: "L"
        }
    }
}

public enum TrainWidgetLook: String, Codable, CaseIterable, Sendable, Identifiable {
    // Calendar
    case week, month, agenda
    // Training load
    case kg, minutes, sets
    // This week's sessions; `quest` = the Quest map trail (#227).
    case list, quest

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .week: "Week strip"
        case .month: "Month grid"
        case .agenda: "Agenda"
        case .kg: "Kg lifted"
        case .minutes: "Minutes"
        case .sets: "Sets"
        case .list: "List"
        case .quest: "Quest map"
        }
    }
}

public struct TrainWidget: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: TrainWidgetKind
    public var size: TrainWidgetSize
    /// Nil = the kind's first look (or, for This week, the game look's pick).
    public var look: TrainWidgetLook?

    /// Ids default to one per kind (each kind is on Train at most once), so the default layout, built fresh each
    /// time, keeps its views' identity.
    public init(_ kind: TrainWidgetKind, size: TrainWidgetSize? = nil, look: TrainWidgetLook? = nil, id: UUID? = nil) {
        self.id = id ?? kind.stableId
        self.kind = kind
        self.size = size.flatMap { kind.sizes.contains($0) ? $0 : nil } ?? kind.defaultSize
        self.look = look.flatMap { kind.looks.contains($0) ? $0 : nil }
    }

    /// Next size the widget offers, wrapping around (the resize handle).
    public var nextSize: TrainWidgetSize {
        let s = kind.sizes
        guard let i = s.firstIndex(of: size) else { return kind.defaultSize }
        return s[(i + 1) % s.count]
    }

    public var resolvedLook: TrainWidgetLook? { look ?? kind.looks.first }

    private enum CodingKeys: String, CodingKey { case id, kind, size, look }

    /// Unknown sizes and looks (written by a newer app) fall back to the defaults; an unknown kind throws and
    /// `TrainLayout` skips that widget.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(TrainWidgetKind.self, forKey: .kind)
        self.init(kind,
                  size: (try? c.decode(String.self, forKey: .size)).flatMap(TrainWidgetSize.init(rawValue:)),
                  look: (try? c.decode(String.self, forKey: .look)).flatMap(TrainWidgetLook.init(rawValue:)),
                  id: try? c.decode(UUID.self, forKey: .id))
    }
}

/// A row of the 2-column grid: one full-width widget, or up to two small ones side by side.
public enum TrainRow: Equatable, Sendable, Identifiable {
    case full(TrainWidget)
    case pair(TrainWidget, TrainWidget?)

    public var id: UUID {
        switch self {
        case .full(let w): w.id
        case .pair(let a, _): a.id
        }
    }
}

public struct TrainLayout: Codable, Equatable, Sendable {
    public var widgets: [TrainWidget]

    public init(_ widgets: [TrainWidget]) { self.widgets = widgets }

    private enum CodingKeys: String, CodingKey { case widgets }

    /// Widgets this app doesn't know (added by a newer version) are skipped instead of failing the whole profile.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var list = try c.nestedUnkeyedContainer(forKey: .widgets)
        var out: [TrainWidget] = []
        while !list.isAtEnd {
            if let w = try? list.decode(TrainWidget.self) {
                if !out.contains(where: { $0.kind == w.kind }) { out.append(w) }
            } else if (try? list.decode(Skip.self)) == nil {
                break
            }
        }
        widgets = out
    }

    private struct Skip: Decodable {}

    /// Small widgets pair up in order; a small one followed by a wide one sits alone on the left.
    public var rows: [TrainRow] {
        var out: [TrainRow] = []
        var pending: TrainWidget?
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

    public func contains(_ kind: TrainWidgetKind) -> Bool { widgets.contains { $0.kind == kind } }

    /// Kinds not on the screen yet (the Add widget gallery). Every kind can be added once.
    public var addable: [TrainWidgetKind] { TrainWidgetKind.allCases.filter { !contains($0) } }

    public mutating func add(_ kind: TrainWidgetKind, at index: Int = 0) {
        guard !contains(kind) else { return }
        widgets.insert(TrainWidget(kind), at: min(max(0, index), widgets.count))
    }

    public mutating func remove(_ id: UUID) { widgets.removeAll { $0.id == id } }

    public mutating func update(_ id: UUID, _ change: (inout TrainWidget) -> Void) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        change(&widgets[i])
        let w = widgets[i]
        widgets[i] = TrainWidget(w.kind, size: w.size, look: w.look, id: w.id) // keeps size and look valid for the kind
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

    // MARK: Presets (B)

    public enum Preset: String, CaseIterable, Sendable, Identifiable {
        case classic, minimal, data, climber

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .classic: "Classic"
            case .minimal: "Minimal"
            case .data: "Data nerd"
            case .climber: "Climber"
            }
        }

        public var detail: String {
            switch self {
            case .classic: "Today's Train screen"
            case .minimal: "Readiness, next session and the week, nothing else"
            case .data: "Numbers first: load, streak, records, body, muscles"
            case .climber: "Climbing up top with the agenda"
            }
        }
    }

    /// The default Train screen for a game look (#227): coach monkey with Monkey coach, level bar with
    /// Charge & go (This week follows the look itself: quest map with Crown deck). Climbing only for climbers.
    /// One coach card, then Next up (#538): its Start workout stays on the first screen. With the coach monkey the
    /// week card moves under Next up; the level bar always sits under it.
    public static func classic(coach: Bool, levelBar: Bool, climber: Bool) -> TrainLayout {
        var w: [TrainWidget] = [TrainWidget(.actions)]
        if coach { w.append(TrainWidget(.coach)) }
        // Shows only while a programme runs (#255).
        w.append(TrainWidget(.programme))
        if !coach { w.append(TrainWidget(.week)) }
        w.append(TrainWidget(.nextUp, size: .large))
        if coach { w.append(TrainWidget(.week)) }
        if levelBar { w.append(TrainWidget(.level, size: .wide)) }
        // Below Next up so Start stays on the first screen; shows only with steps from Health (#454).
        w.append(TrainWidget(.move))
        w.append(TrainWidget(.fuel))
        if climber { w.append(TrainWidget(.climbing)) }
        w.append(TrainWidget(.thisWeek))
        return TrainLayout(w)
    }

    public static func preset(_ p: Preset, coach: Bool, levelBar: Bool, climber: Bool) -> TrainLayout {
        switch p {
        case .classic:
            return classic(coach: coach, levelBar: levelBar, climber: climber)
        case .minimal:
            return TrainLayout([TrainWidget(.programme), TrainWidget(.week), TrainWidget(.nextUp, size: .large), TrainWidget(.calendar, size: .wide, look: .week)])
        case .data:
            return TrainLayout([
                TrainWidget(.programme), TrainWidget(.nextUp, size: .wide), TrainWidget(.week, size: .small), TrainWidget(.streak),
                TrainWidget(.volume, size: .small, look: .kg), TrainWidget(.records), TrainWidget(.body), TrainWidget(.level, size: .small),
                TrainWidget(.move, size: .wide),
                TrainWidget(.muscles, size: .wide), TrainWidget(.calendar, size: .wide, look: .month), TrainWidget(.actions),
            ])
        case .climber:
            return TrainLayout([
                TrainWidget(.climbing, size: .wide), TrainWidget(.programme), TrainWidget(.week), TrainWidget(.nextUp, size: .wide),
                TrainWidget(.calendar, size: .wide, look: .agenda), TrainWidget(.streak), TrainWidget(.lastWorkout), TrainWidget(.actions),
            ])
        }
    }

    /// Same widgets, sizes and looks in the same order (ids ignored): which preset a layout matches.
    public func matches(_ other: TrainLayout) -> Bool {
        widgets.map { [$0.kind.rawValue, $0.size.rawValue, $0.resolvedLook?.rawValue ?? ""] }
            == other.widgets.map { [$0.kind.rawValue, $0.size.rawValue, $0.resolvedLook?.rawValue ?? ""] }
    }
}
