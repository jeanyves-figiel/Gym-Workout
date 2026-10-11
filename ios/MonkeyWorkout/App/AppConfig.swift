import Foundation

enum AppConfig {
    /// From the build configuration's xcconfig (DEV → http://localhost:7443).
    static let apiBaseURL: URL = {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String, let url = URL(string: s) else {
            preconditionFailure("API_BASE_URL missing from Info.plist")
        }
        return url
    }()

    /// Public legal + support pages served by the backend (#125); same URLs as App Store Connect.
    static let privacyURL = apiBaseURL.appendingPathComponent("privacy")
    static let termsURL = apiBaseURL.appendingPathComponent("terms")
    static let supportURL = apiBaseURL.appendingPathComponent("support")

    static let keychainService = (Bundle.main.bundleIdentifier ?? "Com.app.MonkeyWorkout") + ".auth"
}
