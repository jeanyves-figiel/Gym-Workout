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

    /// Web base for links members send to others (invites, shared posts) (#823): the API base when it is a public
    /// https host, never the DEV http://localhost one, which nobody else can open.
    static let publicWebURL: URL = {
        if apiBaseURL.scheme == "https", let host = apiBaseURL.host(), host != "localhost", host != "127.0.0.1" { return apiBaseURL }
        return URL(string: "https://workout.monkeygrade.cloud")!
    }()

    /// Absolute public link for a server-relative path such as "/i/CODE" (#823).
    static func publicLink(_ path: String) -> URL? { URL(string: path, relativeTo: publicWebURL)?.absoluteURL }

    static let keychainService = (Bundle.main.bundleIdentifier ?? "Com.app.MonkeyWorkout") + ".auth"
}
