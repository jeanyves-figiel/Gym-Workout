#if DEBUG
import Foundation

/// DEBUG-only Watch demo data for CI screenshots (#219): `-demo [-homeStyle coach|deck|rings]`.
enum Demo {
    static let on = ProcessInfo.processInfo.arguments.contains("-demo")

    static var homeStyle: WatchHomeStyle? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-homeStyle"), args.indices.contains(i + 1) else { return nil }
        return WatchHomeStyle(rawValue: args[i + 1])
    }

    static var snapshot: WatchSnapshot {
        func item(_ name: String, _ sets: Int, _ reps: String, kg: Double? = nil) -> WItem {
            WItem(uid: name, exerciseId: name, name: name, sets: sets, reps: reps, restSec: 90, intensity: nil, cues: [],
                  loggable: kg != nil, timedSec: nil, easySec: nil, kg: kg, targetReps: kg == nil ? nil : 8, kgStep: 2.5, pairedName: nil)
        }
        func session(_ id: String, _ title: String, _ day: String, _ min: Int, done: Bool, _ tint: UInt32, _ tint2: UInt32) -> WSession {
            WSession(id: id, title: title, dayLabel: day, estMin: min, done: done, tint: tint, blocks: [
                WBlock(title: "Warm-up", tint: 0xFF8A00, tint2: 0xFFC93D, items: [item("Bike", 1, "5 min")]),
                WBlock(title: "Strength", tint: tint, tint2: tint2,
                       items: [item("Bench Press", 4, "6–8", kg: 80), item("Pull-up", 3, "8–10"), item("Overhead Press", 3, "8–10", kg: 45)]),
            ])
        }
        var s = WatchSnapshot()
        s.week = 2
        s.sessions = [
            session("mon", "Lower Power", "Mon", 48, done: true, 0xFF2D55, 0xFF6FB5),
            session("tue", "Upper Strength", "Tue", 52, done: false, 0xB23DFF, 0xFF3DA8),
            session("thu", "Full Body", "Thu", 45, done: false, 0x1E9BFF, 0x3DFFB0),
            session("sat", "Conditioning", "Sat", 30, done: false, 0xFFC23D, 0xFF7A3D),
        ]
        s.extras = [session("ex", "Quick Pump", "Example", 25, done: false, 0x3D5AFF, 0x7B3DFF)]
        s.nextSessionId = "tue"
        s.readiness = "Ready to push"
        s.pro = true
        s.progress = WProgress(streakWeeks: 5, bestStreakWeeks: 5, thisWeek: 1, target: 4,
                               records: [WRecord(name: "Bench Press", kg: 92.5), WRecord(name: "Squat", kg: 130)],
                               recent: [WRecent(title: "Lower Power", date: Date().addingTimeInterval(-86400), minutes: 47, sets: 18)])
        return s
    }
}
#endif
