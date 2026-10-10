import Foundation

/// An exercise the user built (#52), e.g. for a machine in their own gym. Synced as an opaque record.
/// Picture: an optional photo (JPEG) and/or a pose drawing in the app's illustration style.
/// Never deleted, only archived, so workouts and history that use it keep resolving.
public struct CustomExercise: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var category: Category
    public var primary: [Muscle]
    public var secondary: [Muscle]
    public var equipment: [Equipment]
    /// Free-text machine name ("Technogym hip abductor").
    public var machine: String?
    public var unit: Unit
    public var cues: [String]
    /// JPEG, at most `maxPhotoBytes` (base64 in JSON).
    public var photo: Data?
    public var drawing: ExerciseDrawing?
    public var archived: Bool

    public static let idPrefix = "user-"
    public static let maxPhotoBytes = 300_000
    public static let nameLimit = 60

    public init(
        id: UUID = UUID(), name: String = "", createdAt: Date = Date(), category: Category = .strength,
        primary: [Muscle] = [], secondary: [Muscle] = [], equipment: [Equipment] = [], machine: String? = nil,
        unit: Unit = .reps, cues: [String] = [], photo: Data? = nil, drawing: ExerciseDrawing? = nil, archived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.category = category
        self.primary = primary
        self.secondary = secondary
        self.equipment = equipment
        self.machine = machine
        self.unit = unit
        self.cues = cues
        self.photo = photo
        self.drawing = drawing
        self.archived = archived
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, category, primary, secondary, equipment, machine, unit, cues, photo, drawing, archived
    }

    /// Lenient: records from other app versions may miss fields or carry unknown enum values.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date(timeIntervalSince1970: 0)
        category = (try? c.decodeIfPresent(Category.self, forKey: .category)) ?? .strength
        primary = Self.lenient(c, .primary)
        secondary = Self.lenient(c, .secondary)
        equipment = ((try? c.decodeIfPresent([String].self, forKey: .equipment)) ?? []).compactMap(Equipment.init(rawValue:))
        machine = try? c.decodeIfPresent(String.self, forKey: .machine)
        unit = (try? c.decodeIfPresent(Unit.self, forKey: .unit)) ?? .reps
        cues = (try? c.decodeIfPresent([String].self, forKey: .cues)) ?? []
        photo = try? c.decodeIfPresent(Data.self, forKey: .photo)
        drawing = try? c.decodeIfPresent(ExerciseDrawing.self, forKey: .drawing)
        archived = (try? c.decodeIfPresent(Bool.self, forKey: .archived)) ?? false
    }

    private static func lenient(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [Muscle] {
        ((try? c.decodeIfPresent([String].self, forKey: key)) ?? []).compactMap(Muscle.init(rawValue:))
    }

    /// Id used wherever exercises are referenced (custom workouts, logs, history).
    public var exerciseId: String { Self.idPrefix + id.uuidString.lowercased() }

    public static func isCustom(_ exerciseId: String) -> Bool { exerciseId.hasPrefix(idPrefix) }

    /// Trimmed and de-duplicated; secondary never repeats a primary muscle.
    public var sanitized: CustomExercise {
        var e = self
        e.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.nameLimit))
        e.primary = primary.uniqued()
        e.secondary = secondary.uniqued().filter { !e.primary.contains($0) }
        e.equipment = equipment.uniqued()
        let m = machine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        e.machine = m.isEmpty ? nil : String(m.prefix(80))
        e.cues = cues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { String($0.prefix(120)) }
        if let p = photo, p.count > Self.maxPhotoBytes { e.photo = nil }
        return e
    }

    /// Has a photo or a pose drawing.
    public var hasArt: Bool { photo != nil || drawing != nil }

    /// Ready to save: a name and at least one primary muscle.
    public var isComplete: Bool { !sanitized.name.isEmpty && !primary.isEmpty }

    /// The catalog-shaped exercise; never picked by the plan generator.
    public var exercise: Exercise {
        Exercise(
            id: exerciseId, name: name, category: category, pattern: .general, primary: primary, secondary: secondary,
            equipment: equipment, level: 1, secPerRep: unit == .reps ? 3 : nil, unit: unit == .sec ? .sec : nil,
            cues: cues, generator: false)
    }
}

extension Array where Element: Hashable {
    fileprivate func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// The signed-in user's custom exercises, visible to `Exercise.find` / `get` / `search`.
/// The app replaces the contents whenever its stored list changes.
public final class CustomExercises: @unchecked Sendable {
    public static let shared = CustomExercises()

    private let lock = NSLock()
    private var records: [String: CustomExercise] = [:]
    private var exercises: [String: Exercise] = [:]

    public init() {}

    public func replaceAll(_ list: [CustomExercise]) {
        let recs = Dictionary(list.map { ($0.exerciseId, $0) }, uniquingKeysWith: { _, b in b })
        let exs = recs.mapValues(\.exercise)
        lock.withLock {
            records = recs
            exercises = exs
        }
    }

    /// The stored record (photo, drawing, machine) behind a custom exercise id.
    public func record(_ exerciseId: String) -> CustomExercise? { lock.withLock { records[exerciseId] } }

    public func exercise(_ exerciseId: String) -> Exercise? { lock.withLock { exercises[exerciseId] } }

    /// Not archived, for pickers and search.
    public var active: [Exercise] {
        lock.withLock { records.values.filter { !$0.archived }.compactMap { exercises[$0.exerciseId] } }
    }
}
