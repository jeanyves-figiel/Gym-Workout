#if DEBUG
import APIClient
import Foundation
import WorkoutEngine

/// DEBUG-only: `-demo [-demoScreen week|session|player|explore|muscle|exercise|welcome]`
/// launches with sample data and no network — used by CI screenshots and previews.
enum Demo {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), args.indices.contains(i + 1) else { return "week" }
        return args[i + 1]
    }

    static let user: User? = {
        let json = #"{"id":"demo","email":"climber@example.com","name":"JY","emailVerified":true,"hasPassword":true,"appleLinked":false,"createdAt":"2026-10-07T10:00:00Z"}"#
        return try? JSONDecoder().decode(User.self, from: Data(json.utf8))
    }()

    static let profile = Profile(goal: .balanced, sessionsPerWeek: 4, experience: .intermediate, climbingDaysPerWeek: 2)
}
#endif
