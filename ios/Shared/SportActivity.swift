import ActivityKit
import Foundation

/// Live Activity of a sport session tracked on the Apple Watch (#1130, design B): lock screen + Dynamic Island, so a
/// snowboard day can be followed with the phone in a pocket. Compiled into the app and the widget extension.
struct SportActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var downhill: Bool
        var paused: Bool
        var onLift: Bool
        var runs: Int
        /// Downhill: metres down; others: metres up.
        var vertical: Int
        var km: Double
        var topKmh: Int
        var heartRate: Int?
        var lastRunDrop: Int?
        /// Set once the Watch ended: the card stays a little as a summary.
        var finished: Bool
    }

    var label: String
    var symbol: String
    var tint: UInt32
    var tint2: UInt32
    var startedAt: Date
}
