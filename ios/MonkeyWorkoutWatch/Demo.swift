#if DEBUG
import LiftSensor
import SwiftUI

/// DEBUG-only Watch demo data for CI screenshots (#219):
/// `-demo [-homeStyle coach|deck|rings] [-watchScreen list|missed|detail|progress|summary|levelup|mirror|phone-start|pro|lift|lift-stop|lift-log|strap|testrep]`.
enum Demo {
    static let on = ProcessInfo.processInfo.arguments.contains("-demo")

    static var homeStyle: WatchHomeStyle? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-homeStyle"), args.indices.contains(i + 1) else { return nil }
        return WatchHomeStyle(rawValue: args[i + 1])
    }

    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard on, let i = args.firstIndex(of: "-watchScreen"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static let reward = WReward(xp: 340, levelUp: 8, weekCleared: true, badges: [catalog[6]])

    /// Some of the iPhone's badges (#227), as the phone sends them.
    static let catalog: [WBadge] = [
        WBadge(id: "first", title: "First rep", symbol: "figure.walk", tier: 1),
        WBadge(id: "w10", title: "Committed", symbol: "10.circle.fill", tier: 1),
        WBadge(id: "w25", title: "Regular", symbol: "25.circle.fill", tier: 2),
        WBadge(id: "w50", title: "Dedicated", symbol: "50.circle.fill", tier: 2),
        WBadge(id: "w100", title: "Centurion", symbol: "crown.fill", tier: 3),
        WBadge(id: "s2", title: "On a roll", symbol: "flame", tier: 1),
        WBadge(id: "s4", title: "Consistent", symbol: "flame.fill", tier: 2),
        WBadge(id: "s8", title: "Unbreakable", symbol: "bolt.shield.fill", tier: 3),
        WBadge(id: "v10", title: "Ten tonnes", symbol: "scalemass", tier: 1),
        WBadge(id: "pr1", title: "New best", symbol: "arrow.up.right.circle.fill", tier: 1),
        WBadge(id: "pr10", title: "PR hunter", symbol: "chart.line.uptrend.xyaxis", tier: 2),
        WBadge(id: "early", title: "Early bird", symbol: "sunrise.fill", tier: 1),
    ]

    @MainActor @ViewBuilder static func view(_ screen: String) -> some View {
        let s = snapshot
        switch screen {
        case "list", "missed": NavigationStack { SessionListView(title: "This week", sessions: s.sessions) }
        case "detail": NavigationStack { SessionDetailView(session: s.sessions[1], onStart: { _ in }) }
        case "progress": NavigationStack { ProgressScreen() }
        case "phone-start": PhoneStartView()
        case "levelup": LevelUpCelebration(level: 8, compact: true)
        case "summary": SummaryView(player: player(s.sessions[1]), kcal: 410, avgHR: 128, saved: true, onDone: {})
        case "mirror":
            MirrorView(live: WLive(sessionTitle: "Upper Strength", exercise: "Bench Press", setLabel: "Set 2 of 4", detail: "80 kg × 8",
                                   restEnd: nil, next: "Pull-up · 3×8–10", tint: 0xFF2D55, effortPending: false, action: "SET 2 DONE"))
        case "lift", "lift-stop", "lift-log": LiftDemo(stop: screen == "lift-stop", logging: screen == "lift-log")
        case "strap":
            StrapPrompt(exercise: "Leg Extension", spot: MachineSpot.for(name: "Leg Extension")!, onReady: {}, onSkip: {})
        case "testrep": TestRepView(calibrated: false, onSkip: {})
        default: ProLockView()
        }
    }

    /// Lift sensor (#383) during a bench set: panel, then the automatic log.
    struct LiftDemo: View {
        let stop: Bool
        let logging: Bool
        @State private var lift = LiftTracker()

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bench Press").font(W.display(18))
                Text("80 kg · set 2 of 4").font(W.label(10)).opacity(0.85)
                LiftPanel(lift: lift, reps: stop ? 6 : 5, tint: 0x7B2FF7)
                if logging {
                    AutoLogBanner(title: "80 × 8 logging", end: Date().addingTimeInterval(3), onUndo: {})
                } else {
                    LimeButton(title: "SET 2 DONE") {}
                }
            }
            .foregroundStyle(.white)
            .watchMargins()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [W.color(0x7B2FF7).opacity(0.85), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .onAppear {
                lift.demo(stop ? [0.71, 0.69, 0.64, 0.62, 0.57, 0.55] : logging ? [0.7, 0.68, 0.66, 0.63, 0.6, 0.59, 0.58, 0.57] : [0.71, 0.69, 0.66, 0.64, 0.62],
                          stop: stop)
            }
        }
    }

    @MainActor private static func player(_ session: WSession) -> WatchPlayer {
        let p = WatchPlayer(session: session)
        for it in session.items { p.setsDone[it.uid] = it.sets }
        p.endedAt = Date().addingTimeInterval(52 * 60)
        p.phase = .finished
        return p
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
        if screen == "missed" {
            // Missed sessions (#266): Monday not done, next up Tuesday.
            s.sessions[0].done = false
            s.sessions[0].missed = true
        }
        s.extras = [session("ex", "Quick Pump", "Example", 25, done: false, 0x3D5AFF, 0x7B3DFF)]
        s.nextSessionId = "tue"
        s.readiness = "Ready to push"
        s.pro = true
        s.game = WGame(xp: 3620, workouts: 42, totalSets: 760, badges: ["first", "w10", "w25", "s2", "s4", "v10", "pr1", "early"],
                       weeksCleared: 6, catalog: catalog)
        s.progress = WProgress(streakWeeks: 5, bestStreakWeeks: 5, thisWeek: 1, target: 4,
                               records: [WRecord(name: "Bench Press", kg: 92.5), WRecord(name: "Squat", kg: 130)],
                               recent: [WRecent(title: "Lower Power", date: Date().addingTimeInterval(-86400), minutes: 47, sets: 18)])
        return s
    }
}
#endif
