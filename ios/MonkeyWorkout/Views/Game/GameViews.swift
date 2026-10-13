import SwiftUI
import WorkoutEngine

// iPhone game looks (#227), tied to the Watch style pick (#219) so both devices match:
// Monkey coach → the monkey on Train, dances when you finish, trophy shelf;
// Crown deck → Quest map: days are stages, a chest opens when the week's goal is met;
// Charge & go → Level bar: level chip, XP bar, level card.
// XP, level and badges are the same numbers in every look and on the Watch (`GameProgress`, `Achievements`).

extension WatchHomeStyle {
    /// Name of the iPhone look for this pick.
    var phoneTitle: String {
        switch self {
        case .coach: "Monkey coach"
        case .deck: "Quest map"
        case .rings: "Level bar"
        }
    }

    var phoneDetail: String {
        switch self {
        case .coach: "Your monkey on Train with tips and moods, a dance when you finish, a trophy shelf in Progress."
        case .deck: "Your week as a quest: each day is a stage, exercises are bosses, a chest opens when you hit your goal."
        case .rings: "Level chip, XP bar and a level card. Clean numbers, no fuss."
        }
    }

    var phoneSymbol: String {
        switch self {
        case .coach: "face.smiling.inverse"
        case .deck: "map.fill"
        case .rings: "chart.bar.fill"
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: tint.0), Color(hex: tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex v: UInt32) {
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum GameTint {
    static let level = LinearGradient(colors: [Color(hex: 0xB23DFF), Color(hex: 0xFF3DA8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let quest = LinearGradient(colors: [Color(hex: 0xFFC23D), Color(hex: 0xFF3D5A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let shelf = LinearGradient(colors: [Color(hex: 0x3D5AFF), Color(hex: 0x7B3DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let xp = LinearGradient(colors: [Theme.lime, Color(hex: 0x3DDC84)], startPoint: .leading, endPoint: .trailing)
}

extension MonkeyFace.Mood {
    var word: String {
        switch self {
        case .happy: "happy"
        case .fired: "fired up"
        case .sleepy: "sleepy"
        case .party: "partying"
        }
    }
}

// MARK: - Shared pieces

/// "LV 7" lime capsule next to the Train title (all looks).
struct LevelChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let g = model.game
        Text("LV \(g.level)")
            .font(Theme.label(14)).tracking(1)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(GameTint.xp))
            .accessibilityLabel("Level \(g.level), \(g.xpToNext) XP to the next level")
    }
}

/// XP progress capsule.
struct XPBarView: View {
    let progress: Double
    var height: CGFloat = 10
    var track: Color = .white.opacity(0.15)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(GameTint.xp)
                    .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.8), value: progress)
    }
}

private func gameChip(_ text: String, fill: Color = Theme.ink.opacity(0.85), ink: Color = .white) -> some View {
    Text(text).font(Theme.label(12)).foregroundStyle(ink).lineLimit(1)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(fill))
}

// MARK: - Charge & go → Level bar

/// Train: level, XP bar and what the next session adds.
struct LevelBarCard: View {
    let next: Session?
    @Environment(AppModel.self) private var model

    var body: some View {
        let g = model.game
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Level \(g.level) · \(g.rank)").font(Theme.label(12)).tracking(1.3).textCase(.uppercase).foregroundStyle(Theme.lime)
                Spacer()
                Text("\(g.xpInLevel) / \(GameProgress.perLevel) XP").font(Theme.label(12)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            XPBarView(progress: g.levelProgress)
            if let next {
                let gain = model.xp(for: next)
                let after = g.xpInLevel + gain
                (Text("Next session ") + Text("+\(gain) XP").foregroundStyle(Theme.lime)
                    + Text(after >= GameProgress.perLevel ? " → Level \(g.level + 1)!" : " → \(after)"))
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Monkey coach

/// Train: the monkey with a mood from the week, streak and readiness; tap it for the next tip.
struct MonkeyCoachCard: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tip = 0
    @State private var hop = false
    @State private var bob = false

    private struct Tip {
        var text: String
        var tint: (UInt32, UInt32)
    }

    var body: some View {
        let target = model.gameTarget
        let stats = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: target)
        let next = model.nextSession
        let mood = MonkeyFace.Mood.from(weekDone: next == nil || stats.thisWeek >= target,
                                        readiness: Readiness.assess(health.snapshot)?.0.title, streakWeeks: stats.currentStreakWeeks)
        let all = tips(mood: mood, next: next, stats: stats, target: target)
        let current = all[tip % all.count]
        Button { poke(count: all.count) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    MonkeyFace(mood: mood, scale: 1.45)
                        .scaleEffect(hop ? 1.12 : 1)
                        .rotationEffect(.degrees(hop ? -12 : 0))
                        .offset(y: hop ? -8 : (bob ? -2 : 0))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coach Monkey · \(mood.word)").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                        Text(current.text)
                            .font(Theme.display(21)).lineLimit(3).minimumScaleFactor(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(tip)
                            .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    gameChip("🔥 \(stats.currentStreakWeeks) wk")
                    gameChip("\(stats.thisWeek)/\(target) this week")
                    Spacer(minLength: 0)
                    gameChip("tap me", fill: .white.opacity(0.25))
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: current.tint.0), Color(hex: current.tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.35), value: tip)
        .sensoryFeedback(.impact(weight: .light), trigger: tip)
        .accessibilityLabel("Monkey coach: \(current.text)")
        .accessibilityHint("Shows another tip")
        .onAppear {
            guard !reduceMotion else { return }
            poke(count: 0)
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private func poke(count: Int) {
        if count > 0 { tip = (tip + 1) % count }
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.35)) { hop = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { hop = false }
        }
    }

    /// Same tips as the Watch's Monkey coach home.
    private func tips(mood: MonkeyFace.Mood, next: Session?, stats: ProgressStats, target: Int) -> [Tip] {
        let title = next?.displayTitle ?? "it"
        var out: [Tip] = switch mood {
        case .party: [Tip(text: "Week done! You legend 🏆", tint: (0x3DFFB0, 0x1E9BFF))]
        case .sleepy: [Tip(text: "Easy does it today. Quality reps 😴", tint: (0x3D5AFF, 0x7B3DFF))]
        case .fired: [Tip(text: "Let's crush \(title)! 💥", tint: (0xB23DFF, 0xFF3DA8))]
        case .happy: [Tip(text: "Ready for \(title)? 💪", tint: (0xFFC23D, 0xFF7A3D))]
        }
        if stats.currentStreakWeeks > 0 {
            let best = stats.currentStreakWeeks >= stats.bestStreakWeeks && stats.currentStreakWeeks > 1
            out.append(Tip(text: "🔥 \(stats.currentStreakWeeks)-week streak\(best ? ". Best ever!" : "")", tint: (0xFFC23D, 0xFF7A3D)))
        }
        if let r = stats.personalRecords.first {
            out.append(Tip(text: "🏅 Best \(Exercise.get(r.exerciseId).name): \(Format.kg(r.kg)) kg. Beat it!", tint: (0x3D5AFF, 0x1E9BFF)))
        }
        let g = model.game
        out.append(Tip(text: "⭐ Level \(g.level): \(g.xpToNext) XP to level \(g.level + 1)", tint: (0x3DFFB0, 0x1E9BFF)))
        let left = max(0, target - stats.thisWeek)
        out.append(Tip(text: left == 0 ? "\(stats.thisWeek)/\(target) this week. Bonus round?" : "\(stats.thisWeek)/\(target) this week. \(left) to go!",
                       tint: (0xFF7A3D, 0xFF3D5A)))
        return out
    }
}

// MARK: - Crown deck → Quest map

/// Train: the week as a trail of stages (one per session) ending in the week's chest.
struct QuestMap<Menu: View>: View {
    let sessions: [Session]
    let days: [String: Int]
    @ViewBuilder let menu: (Session, Int?) -> Menu
    @Environment(AppModel.self) private var model

    private var rowHeight: CGFloat { 104 }
    private var chestHeight: CGFloat { 130 }

    var body: some View {
        let target = model.gameTarget
        let thisWeek = Progression.stats(records: model.state.history, weights: [], targetPerWeek: target).thisWeek
        let nextId = model.nextSession?.id
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                QuestTrail(points: points(w))
                    .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [1, 12]))
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    let day = s.weekday ?? days[s.id]
                    NavigationLink(value: s.id) {
                        QuestStage(session: s, number: i + 1, weekday: day, done: model.state.done[s.id] ?? false,
                                   current: s.id == nextId, xp: model.xp(for: s), left: i.isMultiple(of: 2), width: w)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(s, day) }
                    .frame(width: w, height: rowHeight)
                    .offset(y: CGFloat(i) * rowHeight)
                }
                QuestChestView(done: thisWeek, target: target)
                    .frame(width: w, height: chestHeight)
                    .offset(y: CGFloat(sessions.count) * rowHeight)
            }
        }
        .frame(height: CGFloat(sessions.count) * rowHeight + chestHeight)
    }

    private func nodeX(_ i: Int, _ w: CGFloat) -> CGFloat { i.isMultiple(of: 2) ? w * 0.22 : w * 0.78 }

    private func points(_ w: CGFloat) -> [CGPoint] {
        sessions.indices.map { CGPoint(x: nodeX($0, w), y: CGFloat($0) * rowHeight + rowHeight / 2) }
            + [CGPoint(x: w / 2, y: CGFloat(sessions.count) * rowHeight + 46)]
    }
}

/// Dotted trail through the stage nodes.
private struct QuestTrail: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for (a, b) in zip(points, points.dropFirst()) {
            let mid = (a.y + b.y) / 2
            p.addCurve(to: b, control1: CGPoint(x: a.x, y: mid), control2: CGPoint(x: b.x, y: mid))
        }
        return p
    }
}

private struct QuestStage: View {
    let session: Session
    let number: Int
    let weekday: Int?
    let done: Bool
    let current: Bool
    let xp: Int
    /// Node on the left (label right) or on the right (label left).
    let left: Bool
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    private var lead: WorkoutEngine.Category { session.blocks.first { $0.kind == .strength }?.kind.category ?? .strength }
    private var size: CGFloat { current ? 74 : 60 }

    var body: some View {
        HStack(spacing: 12) {
            if !left { label(.trailing) }
            node
            if left { label(.leading) }
        }
        .padding(left ? Edge.Set.leading : Edge.Set.trailing, max(0, width * 0.22 - size / 2))
        .frame(width: width, alignment: left ? .leading : .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stage \(number), \(session.displayTitle), \(done ? "cleared" : "\(xp) XP")")
        .onAppear {
            guard current, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    private var node: some View {
        ZStack {
            Circle().fill(done ? AnyShapeStyle(GameTint.xp) : AnyShapeStyle(lead.gradient))
                .opacity(done || current ? 1 : 0.45)
            Circle().strokeBorder(current ? Theme.lime : .white.opacity(0.25), lineWidth: current ? 4 : 3)
            Image(systemName: done ? "checkmark" : current ? "bolt.fill" : lead.symbol)
                .font(.system(size: size * 0.38, weight: .black))
                .foregroundStyle(done ? Theme.ink : .white)
        }
        .frame(width: size, height: size)
        .shadow(color: current ? lead.color.opacity(glow ? 0.9 : 0.4) : .clear, radius: glow ? 18 : 8)
        .scaleEffect(current && glow ? 1.05 : 1)
    }

    private func label(_ align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 2) {
            Text(weekday.map { WeekSchedule.name($0) } ?? "Stage \(number)").font(Theme.label(11)).tracking(1).textCase(.uppercase)
                .foregroundStyle(current ? Theme.lime : Theme.muted)
            Text(current ? "Today · \(session.displayTitle)" : session.displayTitle)
                .font(.system(size: current ? 17 : 15, weight: .heavy, design: .rounded)).lineLimit(2)
                .multilineTextAlignment(align == .leading ? .leading : .trailing)
            Text(done ? "Cleared · +\(xp) XP" : "\(session.blocks.reduce(0) { $0 + $1.items.count }) bosses · +\(xp) XP")
                .font(Theme.label(12)).foregroundStyle(done ? Theme.lime : .white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: width * 0.5, alignment: align == .leading ? .leading : .trailing)
    }
}

/// The week's chest: opens (+200 XP) when the session goal is met.
private struct QuestChestView: View {
    let done: Int
    let target: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = false

    var body: some View {
        let open = done >= target
        VStack(spacing: 6) {
            Image(systemName: open ? "gift.fill" : "shippingbox.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 76, height: 76)
                .background(Circle().fill(GameTint.quest))
                .shadow(color: Color(hex: 0xFFC23D).opacity(open ? 0.8 : 0.3), radius: open ? 18 : 8)
                .rotationEffect(.degrees(wiggle ? 6 : -6))
            Text(open ? "Chest opened · +\(GameProgress.weekBonus) XP" : "Week chest · \(done)/\(target) stages")
                .font(Theme.label(13)).foregroundStyle(open ? Theme.lime : .white.opacity(0.75))
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !open, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { wiggle = true }
        }
    }
}

// MARK: - Session page

/// Top of a session page, in the member's look: what finishing it earns.
struct SessionGameBanner: View {
    let session: Session
    @Environment(AppModel.self) private var model

    var body: some View {
        let style = WatchHomePref.shared.style
        let g = model.game
        let gain = model.xp(for: session)
        let bosses = session.blocks.reduce(0) { $0 + $1.items.count }
        HStack(spacing: 12) {
            switch style {
            case .coach: MonkeyFace(mood: .fired, scale: 0.8)
            case .deck: IconTile(symbol: "bolt.fill", size: 44)
            case .rings: IconTile(symbol: "star.fill", size: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                switch style {
                case .coach:
                    Text("Let's crush it! +\(gain) XP").font(Theme.display(17))
                    Text("Your monkey dances when you finish.").font(.footnote.weight(.semibold)).opacity(0.85)
                case .deck:
                    Text("\(bosses) bosses · loot +\(gain) XP").font(Theme.display(17))
                    Text("Clear every set to beat the stage.").font(.footnote.weight(.semibold)).opacity(0.85)
                case .rings:
                    Text("+\(gain) XP · Level \(g.level)").font(Theme.display(17))
                    XPBarView(progress: g.levelProgress, height: 8, track: .white.opacity(0.25))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(style == .deck ? GameTint.quest : style == .coach ? GameTint.level : GameTint.shelf))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Finish

/// Session complete, in the member's look: XP, level-up, week chest, new badges.
struct GameRewardView: View {
    let reward: GameReward
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dance = false
    @State private var shown = false

    private static let confetti: [(emoji: String, x: CGFloat, y: CGFloat)] =
        [("🎉", -120, -40), ("✨", 118, -52), ("⭐", -104, 40), ("🍌", 112, 34), ("🎊", 0, -78)]

    var body: some View {
        let style = WatchHomePref.shared.style
        VStack(spacing: 14) {
            switch style {
            case .coach:
                ZStack {
                    ForEach(Array(Self.confetti.enumerated()), id: \.offset) { _, c in
                        Text(c.emoji).font(.system(size: 26)).offset(x: c.x, y: c.y + (dance ? -8 : 8))
                    }
                    MonkeyFace(mood: .party, scale: 2.2)
                        .rotationEffect(.degrees(dance ? 10 : -10))
                        .offset(y: dance ? -6 : 4)
                }
                .frame(height: 150)
                Text("Victory!").font(Theme.display(44))
            case .deck:
                Image(systemName: reward.weekCleared ? "gift.fill" : "flag.checkered")
                    .font(.system(size: 60, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 120, height: 120)
                    .background(Circle().fill(GameTint.quest))
                    .rotationEffect(.degrees(dance ? 8 : -8))
                Text(reward.weekCleared ? "Chest opened!" : "Stage cleared!").font(Theme.display(40)).multilineTextAlignment(.center)
            case .rings:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient(colors: [Theme.lime, .yellow], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.bounce, value: shown)
                Text("Session complete").font(Theme.display(40)).multilineTextAlignment(.center)
            }
            Text("+\(shown ? reward.xp : 0) XP")
                .font(Theme.display(54)).foregroundStyle(Theme.lime)
                .contentTransition(.numericText())
                .monospacedDigit()
            if reward.weekCleared {
                gameChip("🎁 Week goal met · +\(GameProgress.weekBonus) XP bonus", fill: Color(hex: 0xFFC23D), ink: Theme.ink)
            }
            levelCard
            ForEach(reward.badges) { b in
                HStack(spacing: 12) {
                    Image(systemName: b.symbol)
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(LinearGradient(colors: b.tier.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New badge").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                        Text(b.title).font(Theme.display(20))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.ink)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GameTint.quest))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 1.2).delay(0.2)) { shown = true }
            guard !reduceMotion, style != .rings else { return }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { dance = true }
        }
    }

    private var levelCard: some View {
        let g = model.game
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reward.levelUp.map { "⬆️ Level \($0)!" } ?? "Level \(g.level) · \(g.rank)").font(Theme.display(18))
                Spacer()
                Text("\(g.xpInLevel) / \(GameProgress.perLevel) XP").font(Theme.label(12)).opacity(0.85).monospacedDigit()
            }
            XPBarView(progress: shown ? g.levelProgress : 0, track: .white.opacity(0.2))
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(reward.levelUp == nil ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(GameTint.level)))
    }
}

// MARK: - Progress

/// Top of Progress, in the member's look: level card, trophy shelf or quest log.
struct GameProgressCard: View {
    let badges: [Badge]
    @Environment(AppModel.self) private var model

    var body: some View {
        let style = WatchHomePref.shared.style
        let g = model.game
        let earned = badges.filter(\.unlocked)
        switch style {
        case .rings:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Level · \(g.rank)").font(Theme.label(12)).tracking(1.3).textCase(.uppercase).opacity(0.8)
                        Text("\(g.level)").font(Theme.display(64)).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Total XP").font(Theme.label(12)).tracking(1.3).textCase(.uppercase).opacity(0.8)
                        Text(g.xp.formatted()).font(Theme.display(28)).monospacedDigit()
                        Text("\(earned.count)/\(badges.count) badges").font(Theme.label(12)).opacity(0.85)
                    }
                }
                XPBarView(progress: g.levelProgress, track: .black.opacity(0.25))
                Text("\(g.xpToNext) XP to Level \(g.level + 1)").font(.footnote.weight(.semibold)).opacity(0.85)
            }
            .gradientCard(GameTint.level, padding: 20)
            .accessibilityElement(children: .combine)
        case .coach:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monkey's trophy shelf").font(Theme.label(12)).tracking(1.3).textCase(.uppercase).opacity(0.8)
                        Text("Level \(g.level)").font(Theme.display(34))
                        Text("\(earned.count) of \(badges.count) badges").font(.footnote.weight(.semibold)).opacity(0.85)
                    }
                    Spacer()
                    MonkeyFace(mood: .party, scale: 1.3)
                }
                XPBarView(progress: g.levelProgress, track: .black.opacity(0.25))
                let shelf = Array(earned.suffix(8))
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack {
                            ForEach(0..<4, id: \.self) { col in
                                let i = row * 4 + col
                                Group {
                                    if shelf.indices.contains(i) {
                                        Image(systemName: shelf[i].symbol).foregroundStyle(
                                            LinearGradient(colors: shelf[i].tier.colors, startPoint: .top, endPoint: .bottom))
                                    } else {
                                        Image(systemName: "lock.fill").opacity(0.3)
                                    }
                                }
                                .font(.system(size: 24, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                        Rectangle().fill(Color(hex: 0x8A5A2B)).frame(height: 5).clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.25)))
            }
            .gradientCard(GameTint.shelf, padding: 18)
        case .deck:
            let stats = Progression.stats(records: model.state.history, weights: [], targetPerWeek: model.gameTarget)
            HStack(spacing: 14) {
                Image(systemName: "map.fill").font(.system(size: 26, weight: .bold))
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quest log · Level \(g.level)").font(Theme.display(20))
                    Text("\(stats.thisWeek)/\(model.gameTarget) stages this week · \(earned.count) badges").font(.footnote.weight(.semibold)).opacity(0.9)
                    XPBarView(progress: g.levelProgress, height: 8, track: .black.opacity(0.25))
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("\(g.weeksCleared)").font(Theme.display(36)).monospacedDigit()
                    Text("🎁 chests").font(Theme.label(11))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(GameTint.quest))
            .accessibilityElement(children: .combine)
        }
    }
}
