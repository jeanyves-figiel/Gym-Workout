import Foundation
import WorkoutEngine

/// "What's new" page (#183): shown once per release on first open after an update, from the bundled
/// `Resources/WhatsNew.json`. Every release bumps its `id` (the TestFlight workflow enforces it).
struct WhatsNew: Decodable, Identifiable {
    struct Item: Decodable, Identifiable {
        let symbol: String
        let tint: WorkoutEngine.Category
        let title: String
        let body: String
        var id: String { title }
    }

    let id: String
    let items: [Item]

    static let current: WhatsNew? = Bundle.main.url(forResource: "WhatsNew", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(WhatsNew.self, from: $0) }

    private static let seenKey = "whatsNew.seen"

    /// Notes not seen yet on this device. New accounts mark them seen at onboarding.
    static var pending: WhatsNew? {
        #if DEBUG
        if Demo.enabled { return nil }
        #endif
        guard let n = current, !n.items.isEmpty, UserDefaults.standard.string(forKey: seenKey) != n.id else { return nil }
        return n
    }

    static func markSeen() {
        if let id = current?.id { UserDefaults.standard.set(id, forKey: seenKey) }
    }
}
