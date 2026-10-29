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

    /// Mind (#834) as the phone sends it: box breathing and 4-7-8, score 74.
    static func mind(checkedIn: Bool) -> WMind {
        let box = WBreath(id: "box", label: "Box 4-4-4-4", purpose: "Focus", symbol: "square", tint: 0xFF3D9A, tint2: 0x7A2CFF, lengths: [5, 3, 10],
                          phases: [WBreathPhase(label: "Breathe in", seconds: 4, fill: 0.85, inhale: true),
                                   WBreathPhase(label: "Hold", seconds: 4, fill: 1, inhale: false),
                                   WBreathPhase(label: "Breathe out", seconds: 4, fill: 0, inhale: false),
                                   WBreathPhase(label: "Hold empty", seconds: 4, fill: 0, inhale: false)], cues: [])
        let sleep = WBreath(id: "sleep478", label: "4-7-8", purpose: "Sleep", symbol: "moon.stars.fill", tint: 0x3B3F8F, tint2: 0x7A2CFF, lengths: [4, 8],
                            phases: [WBreathPhase(label: "Breathe in", seconds: 4, fill: 0.85, inhale: true),
                                     WBreathPhase(label: "Hold", seconds: 7, fill: 1, inhale: false),
                                     WBreathPhase(label: "Breathe out", seconds: 8, fill: 0, inhale: false)], cues: [], byBreaths: true)
        let sigh = WBreath(id: "sigh", label: "Physio sigh", purpose: "Stress", symbol: "wind", tint: 0xFFB23C, tint2: 0xFF3D6E, lengths: [5, 1, 3],
                           phases: [WBreathPhase(label: "Breathe in", seconds: 2, fill: 0.85, inhale: true),
                                    WBreathPhase(label: "In a little more", seconds: 1, fill: 1, inhale: true),
                                    WBreathPhase(label: "Breathe out", seconds: 6, fill: 0, inhale: false)], cues: [])
        return WMind(day: WWater.key(Date()), score: checkedIn ? 74 : 61, level: checkedIn ? "Steady" : "Steady",
                     week: [66, 74, 41, 60, 80, 69, checkedIn ? 74 : 61], checkedIn: checkedIn, pick: "box", pickWhy: "Stay sharp",
                     weekMinutes: 18, breaths: [box, sleep, sigh])
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
        case "lift", "lift-stop", "lift-log", "lift-confirm":
            LiftDemo(stop: screen == "lift-stop", logging: screen == "lift-log", confirm: screen == "lift-confirm")
        case "practice": PracticeView(level: 0, demo: [0.62, 0.6, 0.64])
        case "strap":
            StrapPrompt(exercise: "Leg Extension", spot: MachineSpot.for(name: "Leg Extension")!, onReady: {}, onSkip: {})
        case "testrep": TestRepView(calibrated: false, onSkip: {})
        // Motion, timers and swimming (#611, #615, #622, #624).
        case "timers": NavigationStack { TimerPickerView() }
        case "boxing": MotionDemo(screen: screen)
        case "swings": MotionDemo(screen: screen)
        case "swim", "swim-sets", "open-water": MotionDemo(screen: screen)
        // Mind (#834): check-in, Mind card and Calm list, breathing, done.
        case "mind-checkin", "mind": NavigationStack { WatchMindView() }
        case "calm-breathe", "calm-done": MotionDemo(screen: screen)
        default: ProLockView()
        }
    }

    /// Timers, swing counter and swim player with made-up numbers (#611, #615, #622, #624).
    struct MotionDemo: View {
        let screen: String
        @State private var ready = false

        var body: some View {
            // A ZStack with a real child: onAppear on an empty Group never fires, so the screen stayed black (#824).
            ZStack {
                Color.clear
                if ready {
                    switch screen {
                    case "boxing": TimerRunView()
                    case "swings": SportTrackView()
                    case "calm-breathe": CalmRunView()
                    case "calm-done": CalmTracker.shared.summary.map { CalmSummaryView(summary: $0) }
                    default: SwimRunView()
                    }
                }
            }
            .onAppear {
                switch screen {
                case "boxing":
                    WodTracker.shared.demo(.boxing, at: Double(WodTimer.boxing.prep + 3 * 240 + 46))
                case "swings":
                    SportTracker.shared.demo(.padel, minutes: 42)
                case "swim-sets":
                    let w = SwimWorkout(name: "Week 3 · swim 1", sets: [SwimSet(reps: 1, meters: 200, stroke: .easy, sendOff: 330),
                                                                        SwimSet(reps: 4, meters: 100, stroke: .free, sendOff: 120)])
                    SwimTracker.shared.demo(.pool(25), workout: w, minutes: (330 + 2 * 120 + 102) / 60)
                case "open-water":
                    SwimTracker.shared.demo(.openWater, minutes: 28)
                case "calm-breathe", "calm-done":
                    if let b = Demo.mind(checkedIn: true).breaths.first {
                        CalmTracker.shared.demo(b, at: 176 - 134 - 1, done: screen == "calm-done")
                    }
                default:
                    SwimTracker.shared.demo(.pool(25), minutes: 15)
                }
                ready = true
            }
        }
    }

    /// Lift sensor (#383) during a bench set: panel, then the automatic log.
    struct LiftDemo: View {
        let stop: Bool
        let logging: Bool
        var confirm = false
        @State private var lift = LiftTracker()

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bench Press").font(W.display(18))
                Text("80 kg · set 2 of 4").font(W.label(10)).opacity(0.85)
                LiftPanel(lift: lift, reps: stop ? 6 : confirm ? 8 : 5, tint: 0x7B2FF7, waiting: confirm)
                if logging {
                    // Still counting when CI captures ~5 s after launch; at 0 it shows Logged (#824).
                    AutoLogBanner(title: "80 kg × 8", end: Date().addingTimeInterval(9.2), onUndo: {})
                } else if confirm {
                    LimeButton(title: "✓ LOG 8 REPS") {}
                } else {
                    LimeButton(title: "SET 2 DONE") {}
                }
            }
            .foregroundStyle(.white)
            .watchMargins()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [W.color(0x7B2FF7).opacity(0.85), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .onAppear {
                lift.demo(stop ? [0.71, 0.69, 0.64, 0.62, 0.57, 0.55] : logging || confirm ? [0.7, 0.68, 0.66, 0.63, 0.6, 0.59, 0.58, 0.57] : [0.71, 0.69, 0.66, 0.64, 0.62],
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
        s.water = WWater(day: WWater.key(Date()), glasses: 6, target: 12, glassMl: 250)
        s.mind = mind(checkedIn: screen != "mind-checkin")
        return s
    }
}
#endif
