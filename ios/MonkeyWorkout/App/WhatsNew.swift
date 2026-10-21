import Foundation
import WorkoutEngine

/// "What's new" page (#183): shown once per release on first open after an update, from the bundled
/// `Resources/WhatsNew.json`. Every release bumps its `id` (the TestFlight workflow enforces it) and moves
/// the previous notes to the top of `Resources/WhatsNewHistory.json`, listed in Account → What's new (#245).
struct WhatsNew: Decodable, Identifiable {
    struct Item: Decodable, Identifiable {
        let symbol: String
        let tint: WorkoutEngine.Category
        let title: String
        let body: String
        var id: String { title }
    }

    let id: String
    /// TestFlight build that shipped these notes (history only).
    var build: Int?
    /// Release day, `yyyy-MM-dd` (history only; the latest notes take it from `id`).
    var date: String?
    let items: [Item]

    private struct History: Decodable { let releases: [WhatsNew] }

    private static let bundled: WhatsNew? = load("WhatsNew", as: WhatsNew.self)

    /// The `whats-new` content pack (#583) when the server sent one for this build: notes without a new build.
    static let current: WhatsNew? = ContentPacks.shared.load(
        "whats-new", bundled: Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
        decode: { try JSONDecoder().decode(WhatsNew.self, from: $0) }, valid: { !$0.items.isEmpty })

    /// Earlier releases, newest first; never repeats the latest notes (a rebuild keeps the same id).
    /// Under server notes, the build's own notes come first.
    static let history: [WhatsNew] = ([bundled].compactMap { $0 } + (load("WhatsNewHistory", as: History.self)?.releases ?? []))
        .filter { $0.id != current?.id && !$0.items.isEmpty }

    /// "13 Oct" from `date`, else from the `yyyy-MM-dd` start of `id`.
    var day: String? {
        guard let d = Self.dayFormatter().date(from: date ?? String(id.prefix(10))) else { return nil }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Made once per time zone (a formatter is slow to make, and the release list makes one per row).
    private static let dayFormatters = NSCache<NSString, DateFormatter>()

    private static func dayFormatter() -> DateFormatter {
        let zone = TimeZone.current
        if let f = dayFormatters.object(forKey: zone.identifier as NSString) { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd"
        dayFormatters.setObject(f, forKey: zone.identifier as NSString)
        return f
    }

    private static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        Bundle.main.url(forResource: name, withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

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
