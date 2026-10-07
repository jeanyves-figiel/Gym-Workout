import Foundation

enum AppConfig {
    /// From the build configuration's xcconfig (DEV → http://localhost:7443).
    static let apiBaseURL: URL = {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String, let url = URL(string: s) else {
            preconditionFailure("API_BASE_URL missing from Info.plist")
        }
        return url
    }()

    static let keychainService = (Bundle.main.bundleIdentifier ?? "ch.figiel.gymworkout") + ".auth"
}
