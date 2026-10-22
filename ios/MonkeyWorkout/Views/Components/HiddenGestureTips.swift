import SwiftUI
import TipKit

/// TipKit hints for gestures nobody would guess (#617). Each shows once, at most one a day; demo mode hides them so
/// screenshots and UI tests stay as they are.
enum HiddenGestureTips {
    static func configure() {
        #if DEBUG
        if Demo.enabled { Tips.hideAllTipsForTesting() }
        #endif
        try? Tips.configure([.displayFrequency(.daily)])
    }
}

/// 🐵 bubble: tap types, hold talks.
struct HoldToTalkTip: Tip {
    var title: Text { Text("Hold 🐵 to talk") }
    var message: Text? { Text("Tap to type a question, hold to ask out loud.") }
    var image: Image? { Image(systemName: "mic.fill") }
}

/// Player mic: one sentence logs the set.
struct VoiceLogTip: Tip {
    var title: Text { Text("Log a set by voice") }
    var message: Text? { Text("Tap the mic and say \"eight at eighty\": reps, weight, logged.") }
    var image: Image? { Image(systemName: "waveform") }
}

/// Set chips: a done set opens again for a fix. Shown once a set is logged.
struct EditSetTip: Tip {
    @Parameter static var setLogged: Bool = false

    var title: Text { Text("Fix a set") }
    var message: Text? { Text("Tap a done set to change its weight or reps.") }
    var image: Image? { Image(systemName: "hand.tap.fill") }
    var rules: [Rule] { [#Rule(Self.$setLogged) { $0 == true }] }
}
