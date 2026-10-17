import SwiftUI
import WatchKit

// Watch home styles (#219). Each keeps START one tap (or hold) away and the Hero card rows below (HomeStatRows).

/// Readiness headline from the phone (`Readiness.title` in HealthManager) as a level.
enum WReady {
    case ready, normal, easy

    init?(_ title: String?) {
        switch title ?? "" {
        case "Ready to push": self = .ready
        case "Train as planned": self = .normal
        case "Take it easier": self = .easy
        default: return nil
        }
    }

    var progress: Double {
        switch self {
        case .ready: 1
        case .normal: 0.66
        case .easy: 0.33
        }
    }

    var word: String {
        switch self {
        case .ready: "Push"
        case .normal: "Steady"
        case .easy: "Easy"
        }
    }
}

// MARK: - C · Monkey coach (default)

/// A monkey on a full-screen gradient: its mood follows the week, streak and readiness; tap it to hop and cycle tips.
struct CoachHome: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onStart: (WSession) -> Void
    @State private var tip = 0
    @State private var hop = false
    @State private var bob = false

    private struct Tip {
        var text: String
        var tint: (UInt32, UInt32)
    }

    var body: some View {
        let snap = store.snapshot
        let p = snap.progress
        let next = store.next
        let mood = Self.mood(store)
        let allTips = tips(mood: mood, next: next, progress: p)
        let current = allTips[tip % allTips.count]
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 2) {
                    MonkeyFace(mood: mood, gear: snap.game?.rank.gear)
                        .scaleEffect(hop ? 1.15 : 1)
                        .rotationEffect(.degrees(hop ? -14 : 0))
                        .offset(y: hop ? -7 : (bob ? -2 : 0))
                        .contentShape(Rectangle())
                        .onTapGesture { poke(count: allTips.count) }
                        .accessibilityLabel("Monkey coach")
                        .accessibilityHint("Shows another tip")
                        .accessibilityAddTraits(.isButton)
                    Text(current.text)
                        .font(W.label(11)).foregroundStyle(W.ink)
                        .lineLimit(3).minimumScaleFactor(0.8)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 3, bottomTrailingRadius: 11,
                                                           topTrailingRadius: 11, style: .continuous).fill(.white))
                        .id(tip)
                        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
                if let next {
                    NavigationLink(value: next) {
                        VStack(alignment: .leading, spacing: 1) {
                            Eyebrow(text: "\(next.dayLabel) · \(next.estMin)′ · \(next.items.count) ex", color: .white.opacity(0.9))
                            Text(next.title).font(W.display(22)).lineLimit(2).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    LimeButton(title: "▶ START") { onStart(next) }
                } else {
                    Text("Week complete 🏆").font(W.display(20)).foregroundStyle(.white)
                }
                HomeStatRows().padding(.top, 6)
            }
            .watchMargins()
        }
        .containerBackground(W.gradient(current.tint.0, current.tint.1), for: .navigation)
        .animation(.easeInOut(duration: 0.35), value: tip)
        .onAppear {
            guard !reduceMotion else { return }
            poke(count: 0)
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    /// Hop; with tips, show the next one.
    private func poke(count: Int) {
        if count > 0 {
            tip = (tip + 1) % count
            WKInterfaceDevice.current().play(.click)
        }
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.35)) { hop = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { hop = false }
        }
    }

    @MainActor static func mood(_ store: WatchStore) -> MonkeyFace.Mood {
        let p = store.snapshot.progress
        // Not "week done" while a session is missed (#266).
        let weekDone = p.thisWeek >= p.target || (store.next == nil && !store.snapshot.sessions.contains(where: \.isMissed))
        return .from(weekDone: weekDone, readiness: store.snapshot.readiness, streakWeeks: p.streakWeeks)
    }

    private func tips(mood: MonkeyFace.Mood, next: WSession?, progress p: WProgress) -> [Tip] {
        let title = next?.title ?? "it"
        var tips: [Tip] = switch mood {
        case .party: [Tip(text: "Week done! You legend 🏆", tint: (0x3DFFB0, 0x1E9BFF))]
        case .sleepy: [Tip(text: "Easy does it today. Quality reps 😴", tint: (0x3D5AFF, 0x7B3DFF))]
        case .fired: [Tip(text: "Let's crush \(title)! 💥", tint: (0xB23DFF, 0xFF3DA8))]
        case .happy: [Tip(text: "Ready for \(title)? 💪", tint: (0xB23DFF, 0xFF3DA8))]
        }
        if p.streakWeeks > 0 {
            let best = p.streakWeeks >= p.bestStreakWeeks && p.streakWeeks > 1
            tips.append(Tip(text: "🔥 \(p.streakWeeks)-week streak\(best ? ". Best ever!" : "")", tint: (0xFFC23D, 0xFF7A3D)))
        }
        if let r = p.records.first {
            tips.append(Tip(text: "🏅 Best \(r.name): \(WatchPlayer.kg(r.kg)) kg. Beat it!", tint: (0x3D5AFF, 0x1E9BFF)))
        }
        if let g = store.snapshot.game {
            tips.append(Tip(text: "⭐ Level \(g.level): \(WGame.perLevel - g.xpInLevel) XP to level \(g.level + 1)", tint: (0x3DFFB0, 0x1E9BFF)))
        }
        let left = max(0, p.target - p.thisWeek)
        tips.append(Tip(text: left == 0 ? "\(p.thisWeek)/\(p.target) this week. Bonus round?" : "\(p.thisWeek)/\(p.target) this week. \(left) to go!",
                        tint: (0xFF7A3D, 0xFF3D5A)))
        return tips
    }
}

// MARK: - A · Crown deck

/// One full-screen card per plan day; the Digital Crown flips through them (vertical pages), the last page holds the stats.
struct DeckHome: View {
    @Environment(WatchStore.self) private var store
    let onStart: (WSession) -> Void
    @State private var page = ""

    var body: some View {
        let snap = store.snapshot
        TabView(selection: $page) {
            ForEach(snap.sessions) { s in
                DayCard(session: s, week: snap.week, isNext: s.id == store.next?.id, onStart: onStart)
                    .tag(s.id)
                    .containerBackground(W.gradient(s.tint, s.blocks.first { $0.tint == s.tint }?.tint2), for: .tabView)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Your week", color: W.lime)
                    QuestChest()
                    HomeStatRows()
                }
                .watchMargins()
            }
            .tag("stats")
            .containerBackground(W.ink.gradient, for: .tabView)
        }
        .tabViewStyle(.verticalPage)
        .sensoryFeedback(.selection, trigger: page)
        .onAppear { if page.isEmpty { page = store.next?.id ?? snap.sessions.first?.id ?? "stats" } }
    }
}

private struct DayCard: View {
    let session: WSession
    let week: Int
    let isNext: Bool
    let onStart: (WSession) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationLink(value: session) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "\(isNext ? "Next up · \(session.dayLabel)" : session.isMissed ? "Missed · \(session.dayLabel)" : session.dayLabel) · W\(week)",
                            color: .white.opacity(0.9))
                    Text(session.title).font(W.display(26)).lineLimit(2).minimumScaleFactor(0.55)
                    Text("\(session.estMin)′ · \(session.items.count) exercises").font(W.label(11)).opacity(0.9)
                    // Quest map on the iPhone (#227): every day is a stage worth XP.
                    Text(session.done ? "Stage cleared" : session.isMissed ? "Log it on iPhone" : "+\(W.xp(session)) XP")
                        .font(W.label(11)).foregroundStyle(session.isMissed ? W.color(0xFF8A3D) : W.lime)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(session.done ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            if session.done {
                Text("CLEARED ✓")
                    .font(W.display(17)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 3))
                    .rotationEffect(.degrees(-14))
                    .scaleEffect(stamped ? 1 : 2.2)
                    .opacity(stamped ? 1 : 0)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            } else {
                if session.isMissed {
                    // Missed (#266): same red tag as on the iPhone.
                    Text("MISSED")
                        .font(W.label(11)).tracking(1).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(W.gradient(0xFF3D6E, 0xFF8A3D)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .allowsHitTesting(false)
                }
                Button { onStart(session) } label: {
                    Image(systemName: "play.fill").font(.system(size: 22, weight: .black)).foregroundStyle(W.ink)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(W.lime))
                        .shadow(color: W.lime.opacity(0.6), radius: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(session.title)")
            }
        }
        .watchMargins()
        .onAppear {
            guard session.done else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.5).delay(0.15)) { stamped = true }
        }
        .onDisappear { stamped = false }
    }
}

// MARK: - B · Charge & go

/// Week, streak and readiness rings. Tap the middle to cycle stats; press and hold it: the rings charge, 3-2-1, the workout starts.
struct RingsHome: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onStart: (WSession) -> Void
    @State private var shown = false
    @State private var lap = false
    @State private var charge = 0.0
    @State private var pressedAt: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var stat = 0

    var body: some View {
        let snap = store.snapshot
        let p = snap.progress
        let next = store.next
        let ready = WReady(snap.readiness)
        let values = [
            min(1, Double(p.thisWeek) / Double(max(1, p.target))),
            min(1, Double(p.streakWeeks) / Double(max(4, p.bestStreakWeeks))),
            ready?.progress ?? 0,
        ]
        ScrollView {
            VStack(spacing: 6) {
                ZStack {
                    RingTrack(value: fill(values[0]), colors: [W.lime, W.color(0x3DFFB0)])
                        .rotationEffect(.degrees(lap ? 360 : 0))
                        .padding(6)
                    RingTrack(value: fill(values[1]), colors: [W.color(0xFFC23D), W.color(0xFF3D5A)]).padding(19)
                    RingTrack(value: fill(values[2]), colors: [W.color(0x1E9BFF), W.color(0xB23DFF)]).padding(32)
                    center(next: next, progress: p, ready: ready).padding(41)
                }
                .frame(width: 156, height: 156)
                HStack {
                    Text("\(p.thisWeek)/\(p.target)").foregroundStyle(W.lime)
                    Spacer()
                    Text("🔥\(p.streakWeeks)w").foregroundStyle(W.color(0xFF7A3D))
                    Spacer()
                    Text(ready?.word ?? "–").foregroundStyle(W.color(0x5AA8FF))
                }
                .font(W.label(12))
                .padding(.horizontal, 6)
                // Level bar on the iPhone (#227).
                if let g = snap.game { XPBar(game: g).padding(.top, 2) }
                if next != nil {
                    Text(charge > 0 ? "Keep holding…" : "Hold to start · tap for stats")
                        .font(W.label(9)).foregroundStyle(.secondary)
                }
                HomeStatRows().padding(.top, 6)
            }
            .watchMargins()
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { shown = true }
            if values[0] >= 1, !reduceMotion {
                withAnimation(.easeInOut(duration: 1.2).delay(0.9)) { lap = true }
            }
        }
        .onDisappear {
            holdTask?.cancel()
            charge = 0
        }
    }

    /// Ring fill: sweeps in on open, charges to full while holding.
    private func fill(_ v: Double) -> Double {
        shown ? v + (1 - v) * charge : 0
    }

    private func center(next: WSession?, progress p: WProgress, ready: WReady?) -> some View {
        ZStack {
            Circle().fill(charge > 0 ? AnyShapeStyle(W.lime) : AnyShapeStyle(W.gradient(next?.tint ?? 0x3DFFB0, 0xFF3DA8)))
                .shadow(color: W.lime.opacity(charge), radius: 12)
            if charge > 0 {
                Text("\(max(1, 3 - Int(charge * 3)))")
                    .font(W.display(40)).foregroundStyle(W.ink)
                    .contentTransition(.numericText(countsDown: true))
            } else {
                Group {
                    switch stat {
                    case 0:
                        VStack(spacing: 0) {
                            Text(next == nil ? "WEEK DONE" : "HOLD TO GO").font(W.label(7)).tracking(1)
                            Text(next?.title ?? "🏆").font(W.display(13)).lineLimit(2).minimumScaleFactor(0.6)
                            if let next { Text("\(next.estMin)′").font(W.label(9)) }
                        }
                    case 1: statText("\(p.thisWeek)/\(p.target)", "this week")
                    case 2: statText("\(p.streakWeeks)w", "streak")
                    case 3: statText("LV \(store.snapshot.game?.level ?? 1)", "level")
                    default: statText(ready?.word ?? "–", "readiness")
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(1 + charge * 0.12)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 3) {
            go(next)
        } onPressingChanged: { pressing in
            if pressing { beginHold(next) } else { endHold() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Start") { if let next { onStart(next) } }
    }

    private func statText(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(W.display(20)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(W.label(7)).tracking(1)
        }
    }

    private func beginHold(_ next: WSession?) {
        pressedAt = Date()
        guard next != nil else { return }
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            // A short press is a tap (cycles stats); charging starts after it.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.click)
            for i in 1...27 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.1)) { charge = Double(i) / 27 }
                if i % 9 == 0, i < 27 { WKInterfaceDevice.current().play(.click) }
            }
        }
    }

    private func endHold() {
        let tap = pressedAt.map { Date().timeIntervalSince($0) < 0.3 } ?? false
        pressedAt = nil
        holdTask?.cancel()
        if charge < 1 { withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { charge = 0 } }
        if tap {
            WKInterfaceDevice.current().play(.click)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { stat = (stat + 1) % 5 }
        }
    }

    private func go(_ next: WSession?) {
        holdTask?.cancel()
        guard let next else { return }
        WKInterfaceDevice.current().play(.start)
        charge = 0
        onStart(next)
    }
}

private struct RingTrack: View {
    let value: Double
    let colors: [Color]

    var body: some View {
        ZStack {
            Circle().stroke(colors[0].opacity(0.2), lineWidth: 11)
            Circle().trim(from: 0, to: max(0.0001, value))
                .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(value > 0 ? 1 : 0)
        }
    }
}

/// Crown deck stats page (#227): the week's quest chest, as on the iPhone's Quest map.
private struct QuestChest: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let p = store.snapshot.progress
        let open = p.thisWeek >= p.target
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(open ? "🎁 Chest opened" : "🎁 Week chest").font(W.label(12))
                Spacer(minLength: 2)
                Text(open ? "+\(WGame.weekBonus)" : "\(p.thisWeek)/\(p.target)").font(W.display(15)).foregroundStyle(W.lime)
            }
            if let g = store.snapshot.game {
                Text("Level \(g.level) · \(g.weeksCleared ?? 0) weeks cleared").font(W.label(9)).opacity(0.85)
                XPBar(game: g)
            }
        }
        .foregroundStyle(.white)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.12)))
    }
}
