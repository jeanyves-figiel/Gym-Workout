import AppIntents
import SwiftUI
import WidgetKit

// Controls (#607, designs A + B + C from `apple-tech-radar/t5.png`): one-tap actions for Control Center, the Lock
// Screen and the iPhone Action button. Start today and Smart next open the app on Train; +1 glass counts without
// opening it (`AddWaterIntent`, as the Water widget); Just ate opens Fuel's Just ate sheet.

struct StartTodayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.monkeyworkout.control.start") {
            ControlWidgetButton(action: OpenURLIntent(HomeWidgetLink.tab("today"))) {
                Label("Start today", systemImage: "play.fill")
            }
        }
        .displayName("Start today's workout")
        .description("Opens today's workout in the player.")
    }
}

/// Like the Ultra's Action button (#349, Smart): starts today's workout, or during one logs the set / skips the rest.
struct SmartNextControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.monkeyworkout.control.next") {
            ControlWidgetButton(action: OpenURLIntent(HomeWidgetLink.tab("next"))) {
                Label("Smart next", systemImage: "forward.fill")
            }
        }
        .displayName("Smart next")
        .description("Starts today's workout, or logs the set and skips the rest during one.")
    }
}

struct WaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.monkeyworkout.control.water") {
            ControlWidgetButton(action: AddWaterIntent()) {
                Label("+1 glass", systemImage: "drop.fill")
            }
        }
        .displayName("+1 glass of water")
        .description("Counts a glass in Fuel without opening the app.")
    }
}

struct JustAteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.monkeyworkout.control.justate") {
            ControlWidgetButton(action: OpenURLIntent(HomeWidgetLink.tab("justate"))) {
                Label("Just ate", systemImage: "fork.knife")
            }
        }
        .displayName("Just ate")
        .description("Log a meal in Fuel.")
    }
}
