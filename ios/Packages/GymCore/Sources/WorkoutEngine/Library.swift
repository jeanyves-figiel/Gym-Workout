import Foundation

// MARK: - Workout library (#62)

/// Who can see a custom workout besides its owner. Same values as community posts (#61).
public enum WorkoutVisibility: String, Codable, CaseIterable, Sendable, Identifiable {
    case `private`, members, `public`

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .private: "Only me"
        case .members: "Members"
        case .public: "Public"
        }
    }

    public var symbol: String {
        switch self {
        case .private: "lock.fill"
        case .members: "person.2.fill"
        case .public: "globe"
        }
    }

    /// Unknown values from newer servers read as private.
    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .private
    }
}

/// A custom workout another member shared, as listed by `GET /v1/library/shared`.
public struct SharedWorkout: Codable, Hashable, Sendable, Identifiable {
    public struct Author: Codable, Hashable, Sendable {
        public var userId: String
        public var nickname: String
        public var avatarUrl: String?

        public init(userId: String, nickname: String, avatarUrl: String? = nil) {
            self.userId = userId
            self.nickname = nickname
            self.avatarUrl = avatarUrl
        }
    }

    public var id: UUID
    public var name: String
    public var items: [CustomWorkout.Item]
    public var visibility: WorkoutVisibility
    public var saves: Int
    public var author: Author

    public init(id: UUID = UUID(), name: String, items: [CustomWorkout.Item], visibility: WorkoutVisibility = .members, saves: Int = 0, author: Author) {
        self.id = id
        self.name = name
        self.items = items
        self.visibility = visibility
        self.saves = saves
        self.author = author
    }

    enum CodingKeys: String, CodingKey { case id, name, items, visibility, saves, author }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Workout"
        items = try c.decodeIfPresent([CustomWorkout.Item].self, forKey: .items) ?? []
        visibility = try c.decodeIfPresent(WorkoutVisibility.self, forKey: .visibility) ?? .members
        saves = try c.decodeIfPresent(Int.self, forKey: .saves) ?? 0
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? Author(userId: "", nickname: "member")
    }

    /// Read-only view as a custom workout (same id, so its session id is stable), for the session view and player.
    public var workout: CustomWorkout { CustomWorkout(id: id, name: name, items: items, createdAt: Date(timeIntervalSince1970: 0)).sanitized }

    /// Editable copy for "My workouts": fresh ids, private, original name.
    public func copy(createdAt: Date = Date()) -> CustomWorkout {
        CustomWorkout(
            name: name,
            items: items.map { CustomWorkout.Item(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps, restSec: $0.restSec, kcal: $0.kcal) },
            createdAt: createdAt
        ).sanitized
    }
}

// MARK: - Inserting a library workout into the week plan

/// A library workout placed into one week of the plan: replaces a generated session or adds an extra one.
/// Keeps a snapshot of the workout, so later edits or deletion of the source never change a planned day.
public struct PlanInsert: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Plan week (1…4) it belongs to.
    public var week: Int
    /// Index of the generated session it replaces; nil = extra session.
    public var replacing: Int?
    /// 1 = Monday … 7 = Sunday for an extra session; a replacement keeps the replaced day's weekday.
    public var weekday: Int?
    public var workout: CustomWorkout

    public init(id: UUID = UUID(), week: Int, replacing: Int? = nil, weekday: Int? = nil, workout: CustomWorkout) {
        self.id = id
        self.week = week
        self.replacing = replacing
        self.weekday = weekday
        self.workout = workout
    }

    static let marker = "~plan-"

    /// Own session id per insert, so ticks, "done" and logs never mix with the library copy or another week.
    public var sessionId: String { workout.sessionId + Self.marker + id.uuidString.lowercased() }

    /// The workout as a plan session at `index`.
    public func session(index: Int, weekday: Int?) -> Session {
        var s = workout.session
        let base = s.id
        s.id = sessionId
        s.index = index
        s.weekday = weekday
        for b in s.blocks.indices {
            for i in s.blocks[b].items.indices {
                let uid = s.blocks[b].items[i].uid
                s.blocks[b].items[i].uid = uid.hasPrefix(base) ? sessionId + uid.dropFirst(base.count) : sessionId + "-" + uid
            }
        }
        return s
    }
}

extension WeekPlan {
    /// The plan with this week's inserts applied: replacements in place (out-of-range ones ignored), extras appended.
    public func applying(_ inserts: [PlanInsert]) -> WeekPlan {
        let mine = inserts.filter { $0.week == week }
        guard !mine.isEmpty else { return self }
        var p = self
        let generated = sessions.count
        for ins in mine {
            guard let r = ins.replacing, r >= 0, r < generated else { continue }
            p.sessions[r] = ins.session(index: r, weekday: sessions[r].weekday)
        }
        for ins in mine where ins.replacing == nil {
            p.sessions.append(ins.session(index: p.sessions.count, weekday: ins.weekday))
        }
        return p
    }
}

extension Session {
    /// A library workout placed into the week plan (see `PlanInsert`).
    public var isPlanInsert: Bool { id.contains(PlanInsert.marker) }

    /// Id of the `PlanInsert` this session came from.
    public var planInsertId: UUID? {
        guard let r = id.range(of: PlanInsert.marker) else { return nil }
        return UUID(uuidString: String(id[r.upperBound...]))
    }
}
