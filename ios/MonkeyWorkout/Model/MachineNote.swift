import Foundation
import WorkoutEngine

/// A member's setup for one exercise at one gym (#355): quick fields (Seat 4, Pad 2), free text and one photo.
/// Private: never shared with other members. Synced like climbs; the photo goes up and down on its own.
struct MachineNote: Codable, Identifiable, Hashable, Sendable {
    struct Field: Codable, Hashable, Sendable, Identifiable {
        var id = UUID()
        var label: String
        var value: String

        enum CodingKeys: String, CodingKey { case label, value }

        init(label: String, value: String) {
            self.label = label
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = try c.decode(String.self, forKey: .label)
            value = try c.decode(String.self, forKey: .value)
        }
    }

    static let maxFields = 8
    static let maxLabel = 24
    static let maxText = 1000
    /// Suggested field names, most machines need two or three.
    static let presets = ["Seat", "Pin", "Pad", "Back", "Handle", "Foot plate", "ROM", "Height", "Notch"]

    var id = UUID()
    var gymId: String
    var gymName: String
    var exerciseId: String
    /// The machine (first equipment of the exercise), so notes can be found per machine.
    var equipment: String?
    var fields: [Field] = []
    var text: String?
    /// The machine sets push and lowering loads apart (eGym style, #792): the player shows both.
    var splitLoad: Bool?
    /// Server id of the photo; nil = none on the server.
    var photoId: String?
    /// Server version this copy was pulled or saved as (`ServerVersioned`); nil until the server has it.
    var updatedAt: String?

    var machine: Equipment? { equipment.flatMap(Equipment.init(rawValue:)) }
    var filledFields: [Field] { fields.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty } }
    var trimmedText: String? {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    var isEmpty: Bool { filledFields.isEmpty && trimmedText == nil && splitLoad != true }

    /// One line: "Seat 4 · Pad 2 · ROM off", else the start of the text.
    var summary: String {
        let f = (filledFields.map { "\($0.label) \($0.value)" } + (splitLoad == true ? ["Push ≠ lower"] : []))
            .joined(separator: " · ")
        return f.isEmpty ? (trimmedText ?? "") : f
    }

    /// Server-safe copy: trimmed, capped.
    var cleaned: MachineNote {
        var n = self
        // A value typed in a field left unnamed is kept under "Setting" (#817), never dropped.
        n.fields = Array(filledFields.prefix(Self.maxFields)).map {
            let label = $0.label.trimmingCharacters(in: .whitespaces)
            return Field(label: String((label.isEmpty ? "Setting" : label).prefix(Self.maxLabel)),
                         value: String($0.value.trimmingCharacters(in: .whitespaces).prefix(Self.maxLabel)))
        }
        n.text = trimmedText.map { String($0.prefix(Self.maxText)) }
        n.gymName = String(gymName.prefix(120))
        return n
    }
}

/// Photos of machine notes, one JPEG per note in Application Support, encrypted at rest by data protection.
/// Not in state.json so the state file stays small; wiped with it.
enum MachineNotePhotos {
    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("machine-notes", isDirectory: true)
    }

    private static func url(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).jpg") }

    static func load(_ id: UUID) -> Data? { try? Data(contentsOf: url(id)) }

    static func save(_ data: Data, for id: UUID) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(_ id: UUID) { try? FileManager.default.removeItem(at: url(id)) }

    static func wipe() { try? FileManager.default.removeItem(at: dir) }
}
