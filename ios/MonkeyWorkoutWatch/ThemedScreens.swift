import SwiftUI
import WatchKit

// Watch screens in the three looks (#219), picked with the home style (WatchStore.theme):
// Crown deck → full colour (screen in the workout's colour, white glass cards, huge numbers),
// Charge & go → tiles (black, Explore gradient tiles: icon tile left, big number right),
// Monkey coach → game (quest path, XP, level, badges, monkey celebrations).
// XP, level and badges show in all three, matching the iPhone's look for the same pick (#227).

extension W {
    /// "4×6" from 4 sets of "6–8"; timed or single prescriptions as written ("5 min").
    static func dose(_ it: WItem) -> String {
        let lead = it.reps.split(separator: "–").first.map(String.init) ?? it.reps
        return it.sets > 1 ? "\(it.sets)×\(lead)" : it.reps
    }

    /// XP the session would earn with every set done.
    static func xp(_ s: WSession) -> Int {
        WGame.xp(sets: s.items.reduce(0) { $0 + $1.sets })
    }

    /// Icon of a block from its title.
    static func symbol(_ block: WBlock?) -> String {
        let t = block?.title.lowercased() ?? ""
        if t.contains("warm") { return "flame.fill" }
        if t.contains("mobil") || t.contains("stretch") { return "figure.flexibility" }
        if t.contains("cardio") || t.contains("condition") { return "heart.fill" }
        if t.contains("cool") { return "snowflake" }
        if t.contains("power") || t.contains("explos") { return "bolt.fill" }
        return "dumbbell.fill"
    }

    /// The session's own gradient (strength block second colour when there is one).
    static func gradient(_ s: WSession) -> LinearGradient {
        gradient(s.tint, s.blocks.first { $0.tint == s.tint }?.tint2)
    }

    /// Dark glow behind game screens.
    static func glow(_ v: UInt32) -> RadialGradient {
        RadialGradient(colors: [color(v).opacity(0.55), .black], center: .top, startRadius: 0, endRadius: 190)
    }
}

/// White glass card on colour screens.
private struct Glass: ViewModifier {
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white.opacity(0.2)))
    }
}

extension View {
    fileprivate func glass(_ radius: CGFloat = 12) -> some View { modifier(Glass(radius: radius)) }
}

/// Explore tile row: icon tile left, label (and detail), big value right, on a gradient.
struct TileRow: View {
    let symbol: String
    let title: String
    var detail: String?
    let value: String
    let tint: LinearGradient

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.28)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(W.label(11)).lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(detail).font(W.label(9)).opacity(0.85).lineLimit(1) }
            }
            Spacer(minLength: 2)
            Text(value).font(W.display(18)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint))
    }
}

/// Numbered quest step (game look); done steps show a check.
private struct QuestNode: View {
    let number: Int
    let tint: UInt32
    var done = false
    var last = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(W.color(tint))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black))
                } else {
                    Text("\(number)").font(W.label(10))
                }
            }
            .frame(width: 22, height: 22)
            .foregroundStyle(.white)
            if !last { Rectangle().fill(.white.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity) }
        }
        .frame(width: 22)
    }
}

// MARK: - Plan days and workouts

/// Plan days or other workouts.
struct SessionListView: View {
    @Environment(WatchStore.self) private var store
    let title: String
    let sessions: [WSession]

    var body: some View {
        let theme = store.theme
        ScrollView {
            VStack(alignment: .leading, spacing: theme == .game ? 0 : 6) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    NavigationLink(value: s) {
                        switch theme {
                        case .colour: colourRow(s)
                        case .tiles:
                            TileRow(symbol: s.done ? "checkmark" : s.isMissed ? "exclamationmark" : "calendar", title: s.title,
                                    detail: s.isMissed ? "\(s.dayLabel) · missed" : s.dayLabel,
                                    value: "\(s.estMin)′", tint: W.gradient(s)).opacity(s.done ? 0.6 : 1)
                        case .game: questRow(s, number: i + 1, last: i == sessions.count - 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background { if theme == .game { W.glow(0x7B3DFF).ignoresSafeArea() } }
        .navigationTitle(title)
    }

    private func colourRow(_ s: WSession) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(s.dayLabel.uppercased()).font(W.label(9)).tracking(1).opacity(0.85)
                Text(s.title).font(W.display(17)).lineLimit(2).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 2)
            if s.done {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 20, weight: .bold))
            } else if s.isMissed {
                Text("MISSED").font(W.label(10)).tracking(1)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(W.gradient(0xFF3D6E, 0xFF8A3D)))
            } else {
                Text("\(s.estMin)′").font(W.display(22))
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(W.gradient(s)))
        .opacity(s.done ? 0.65 : 1)
    }

    private func questRow(_ s: WSession, number: Int, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 7) {
            QuestNode(number: number, tint: s.tint, done: s.done, last: last)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.dayLabel.uppercased()).font(W.label(8)).tracking(1).foregroundStyle(.secondary)
                Text(s.title).font(W.label(13)).lineLimit(1)
                Text(s.done ? "Cleared" : s.isMissed ? "Missed" : "\(s.estMin)′ · +\(W.xp(s)) XP")
                    .font(W.label(9)).foregroundStyle(s.done ? W.color(0x3DFFB0) : s.isMissed ? W.color(0xFF8A3D) : W.lime)
            }
            .padding(.bottom, 8)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Workout

/// Exercises of a session with suggested loads; tap one for its form cues.
struct SessionDetailView: View {
    @Environment(WatchStore.self) private var store
    let session: WSession
    let onStart: (WSession) -> Void
    @State private var cues: WItem?

    private var rows: [(item: WItem, block: WBlock)] {
        session.blocks.flatMap { b in b.items.map { (item: $0, block: b) } }
    }

    var body: some View {
        let theme = store.theme
        ScrollView {
            VStack(alignment: .leading, spacing: theme == .game ? 0 : 5) {
                header(theme)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    Button { cues = row.item } label: {
                        switch theme {
                        case .colour: colourRow(row.item)
                        case .tiles:
                            TileRow(symbol: W.symbol(row.block), title: row.item.name, detail: load(row.item),
                                    value: W.dose(row.item), tint: W.gradient(row.block.tint, row.block.tint2))
                        case .game: questRow(row.item, block: row.block, number: i + 1, last: i == rows.count - 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                LimeButton(title: theme == .game ? "▶ GO!" : "▶ START") { onStart(session) }.padding(.top, 4)
            }
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(session), glow: 0x7B3DFF))
        .sheet(item: $cues) { it in CuesSheet(item: it, block: rows.first { $0.item.uid == it.uid }?.block, theme: theme) }
    }

    @ViewBuilder private func header(_ theme: WTheme) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(session.title).font(W.display(theme == .colour ? 20 : 17)).lineLimit(2).minimumScaleFactor(0.7)
            if theme == .game {
                Text("+\(W.xp(session)) XP · \(session.items.count) bosses".uppercased())
                    .font(W.label(9)).tracking(1).foregroundStyle(W.lime)
            } else {
                Text("\(session.estMin)′ · \(session.blocks.count) blocks · \(session.items.count) ex".uppercased())
                    .font(W.label(9)).tracking(1).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.bottom, 4)
    }

    private func load(_ it: WItem) -> String? {
        guard let kg = it.kg, it.loggable else { return nil }
        return "↑ \(WatchPlayer.kg(kg)) kg\(it.targetReps.map { " × \($0)" } ?? "")"
    }

    private func colourRow(_ it: WItem) -> some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(it.name).font(W.label(12)).lineLimit(2).minimumScaleFactor(0.8)
                if let l = load(it) { Text(l).font(W.label(10)).foregroundStyle(W.light(0xCCFF3D, 0.3)) }
            }
            Spacer(minLength: 2)
            Text(W.dose(it)).font(W.display(18)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .glass()
    }

    private func questRow(_ it: WItem, block: WBlock, number: Int, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 7) {
            QuestNode(number: number, tint: block.tint, last: last)
            VStack(alignment: .leading, spacing: 0) {
                Text(it.name).font(W.label(12)).lineLimit(2)
                HStack(spacing: 4) {
                    Text(W.dose(it)).font(W.label(10)).foregroundStyle(.secondary)
                    if let kg = it.kg, it.loggable { Text("\(WatchPlayer.kg(kg)) kg").font(W.label(10)).foregroundStyle(W.lime) }
                }
            }
            .padding(.bottom, 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
}

/// Form cues of one exercise, in the theme's look.
private struct CuesSheet: View {
    let item: WItem
    let block: WBlock?
    let theme: WTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: W.symbol(block)).font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.28)))
                    Text(theme == .game ? "Boss tips" : "Form cues").font(W.label(10)).tracking(1).textCase(.uppercase)
                }
                Text(item.name).font(W.display(17))
                ForEach(item.cues, id: \.self) { c in
                    Text("• \(c)").font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(theme == .tiles ? 0 : 6)
                        .background { if theme != .tiles { RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.18)) } }
                }
                if let i = item.intensity { Text(i).font(.footnote).opacity(0.8) }
            }
            .foregroundStyle(.white)
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(block?.tint ?? 0xB23DFF, block?.tint2), glow: block?.tint ?? 0x7B3DFF))
    }
}

/// Full-bleed colour, black, or a dark glow behind a screen.
struct ThemeBackground: ViewModifier {
    let theme: WTheme
    let colour: LinearGradient
    let glow: UInt32

    @ViewBuilder func body(content: Content) -> some View {
        switch theme {
        case .colour: content.containerBackground(colour, for: .navigation).background(colour.ignoresSafeArea())
        case .tiles: content
        case .game: content.background(W.glow(glow).ignoresSafeArea())
        }
    }
}

// MARK: - Progress

/// Streak, week, best lifts, recent sessions (and XP, level, badges in the game look).
struct ProgressScreen: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let theme = store.theme
        let p = store.snapshot.progress
        ScrollView {
            switch theme {
            case .colour: colour(p)
            case .tiles: tiles(p)
            case .game: game(p)
            }
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(0xFFC23D, 0xFF7A3D), glow: 0xFF7A3D))
        .navigationTitle(theme == .game ? "Level \(store.snapshot.game?.level ?? 1)" : "Progress")
    }

    private func week(_ p: WProgress) -> Double { min(1, Double(p.thisWeek) / Double(max(1, p.target))) }

    private func colour(_ p: WProgress) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(p.streakWeeks)").font(W.display(46))
                    Text("week streak · best \(p.bestStreakWeeks)".uppercased()).font(W.label(8)).tracking(1)
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.3), lineWidth: 6)
                    Circle().trim(from: 0, to: week(p)).stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(p.thisWeek)/\(p.target)").font(W.label(12))
                }
                .frame(width: 50, height: 50)
            }
            // Quest map (#227): level, weeks cleared, the week's chest.
            if let g = store.snapshot.game {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        RankMonkey(rank: g.rank, scale: 0.36)
                        Text("Level \(g.level)").font(W.display(16))
                        Spacer(minLength: 2)
                        Text("🎁 \(g.weeksCleared ?? 0)").font(W.label(11))
                    }
                    XPBar(game: g)
                }
                .padding(.horizontal, 8).padding(.vertical, 5).glass()
                BadgeGrid(game: g)
            }
            ForEach(p.records, id: \.name) { r in
                HStack {
                    Text("🏅 \(r.name)").font(W.label(10)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(WatchPlayer.kg(r.kg)).font(W.display(15))
                }
                .padding(.horizontal, 8).padding(.vertical, 5).glass()
            }
            ForEach(p.recent, id: \.date) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.title).font(W.label(10)).lineLimit(1)
                        Text(r.date.formatted(.dateTime.weekday().day())).font(W.label(8)).opacity(0.85)
                    }
                    Spacer(minLength: 2)
                    Text("\(r.minutes)′").font(W.display(15))
                }
                .padding(.horizontal, 8).padding(.vertical, 5).glass()
            }
        }
        .foregroundStyle(.white)
    }

    private func tiles(_ p: WProgress) -> some View {
        VStack(spacing: 5) {
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow {
                    square("flame.fill", "Streak", "\(p.streakWeeks)w", W.gradient(0xFFC23D, 0xFF7A3D))
                    square("calendar", "Week", "\(p.thisWeek)/\(p.target)", W.gradient(0x3DFFB0, 0x1E9BFF))
                }
                GridRow {
                    square("medal.fill", p.records.first?.name ?? "Best", p.records.first.map { WatchPlayer.kg($0.kg) } ?? "–",
                           W.gradient(0x3D5AFF, 0x7B3DFF))
                    square("stopwatch.fill", "Last", p.recent.first.map { "\($0.minutes)′" } ?? "–", W.gradient(0xB23DFF, 0xFF3DA8))
                }
            }
            // Level bar (#227).
            if let g = store.snapshot.game {
                TileRow(symbol: "star.fill", title: "Level", detail: "\(g.xpInLevel)/\(WGame.perLevel) XP", value: "\(g.level)",
                        tint: W.gradient(0xB23DFF, 0xFF3DA8))
                XPBar(game: g)
                TileRow(symbol: "medal.fill", title: "Badges", value: "\(g.earned.count)/\(g.catalog?.count ?? 0)",
                        tint: W.gradient(0xFFC23D, 0xFF7A3D))
            }
            ForEach(p.records.dropFirst(), id: \.name) { r in
                TileRow(symbol: "medal.fill", title: r.name, value: WatchPlayer.kg(r.kg), tint: W.gradient(0x3D5AFF, 0x7B3DFF))
            }
            ForEach(p.recent, id: \.date) { r in
                TileRow(symbol: "clock.fill", title: r.title, detail: "\(r.date.formatted(.dateTime.weekday().day())) · \(r.sets) sets",
                        value: "\(r.minutes)′", tint: W.gradient(0xFF7A3D, 0xFF3D5A))
            }
        }
    }

    private func square(_ symbol: String, _ title: String, _ value: String, _ tint: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.28)))
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(title).font(W.label(8)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text(value).font(W.display(20)).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint))
    }

    @ViewBuilder private func game(_ p: WProgress) -> some View {
        let g = store.snapshot.game
        VStack(spacing: 5) {
            Text("🔥").font(.system(size: 30))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(p.streakWeeks)").font(W.display(30))
                Text("week streak").font(W.label(11))
            }
            if let g {
                XPBar(game: g)
                BadgeGrid(game: g)
            }
            ForEach(p.records, id: \.name) { r in
                HStack {
                    Image(systemName: "medal.fill").foregroundStyle(W.color(0xFFC23D))
                    Text(r.name).font(W.label(10)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(WatchPlayer.kg(r.kg)) kg").font(W.label(10)).foregroundStyle(W.lime)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

/// Level progress bar with XP to the next level.
struct XPBar: View {
    let game: WGame

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(game.accent?.gradient ?? LinearGradient(colors: [W.lime, W.color(0x3DFFB0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * game.levelProgress))
                }
            }
            .frame(height: 8)
            Text("\(game.rank.title) · \(game.xpInLevel)/\(WGame.perLevel) XP → LV \(game.level + 1)").font(W.label(8))
                .foregroundStyle(game.accent?.color ?? W.lime)
        }
        .padding(.horizontal, 4)
        // Level ladder (#242): tap any level bar for what each level brings, like the iPhone.
        .contentShape(Rectangle())
        .onTapGesture { ladder = true }
        .sheet(isPresented: $ladder) { WatchLadderView(game: game) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows what each level brings")
    }

    @State private var ladder = false
}

/// The six ranks on the Watch (#242): current one ringed, unlocks listed, XP to go on locked ones.
struct WatchLadderView: View {
    let game: WGame

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(GameRank.allCases) { rank in
                        let unlocked = rank <= game.rank
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                RankMonkey(rank: rank, scale: 0.42).saturation(unlocked ? 1 : 0.2)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(rank.title).font(W.display(16))
                                    Text(rank.levels).font(W.label(9)).opacity(0.85)
                                }
                                Spacer(minLength: 0)
                                if rank == game.rank {
                                    Text("YOU").font(W.label(9)).foregroundStyle(W.ink)
                                        .padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(.white))
                                } else if !unlocked {
                                    Text("\(rank.minXP - game.xp) XP").font(W.label(9)).opacity(0.85)
                                }
                            }
                            ForEach(rank.perks) { p in
                                Label(p.title, systemImage: p.symbol).font(W.label(9)).lineLimit(2)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? AnyShapeStyle(rank.gradient) : AnyShapeStyle(Color.white.opacity(0.1))))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white, lineWidth: rank == game.rank ? 2 : 0))
                        .id(rank)
                    }
                }
            }
            .onAppear { proxy.scrollTo(game.rank, anchor: .center) }
        }
        .navigationTitle("Levels")
    }
}

/// Badges from the phone (#227): earned first in their tier colour, then a few locked ones.
private struct BadgeGrid: View {
    let game: WGame

    var body: some View {
        let all = game.catalog ?? []
        let earned = game.earned
        let shown = earned + all.filter { !game.badges.contains($0.id) }.prefix(max(0, 8 - earned.count))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(shown) { b in
                let on = game.badges.contains(b.id)
                Image(systemName: on ? b.symbol : "lock.fill").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(on ? W.ink : .white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on ? AnyShapeStyle(W.gradient(b.tint.0, b.tint.1)) : AnyShapeStyle(Color.white.opacity(0.1))))
                    .accessibilityLabel(on ? b.title : "\(b.title), locked")
            }
        }
    }
}

// MARK: - Done

/// After a workout on the Watch: time, sets, kcal, heart rate (and XP, level-up, new badges in the game look).
struct SummaryView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let player: WatchPlayer
    let kcal: Double
    let avgHR: Double?
    let saved: Bool
    let onDone: () -> Void
    @State private var dance = false
    @State private var celebrated = false

    private var demo: Bool {
        #if DEBUG
        Demo.on
        #else
        false
        #endif
    }

    private static let confetti: [(emoji: String, x: CGFloat, y: CGFloat)] = [("🎉", -52, -14), ("✨", 50, -22), ("⭐", -44, 18), ("🎊", 46, 12)]

    private var minutes: Int { Int((player.endedAt ?? Date()).timeIntervalSince(player.started)) / 60 }
    private var hr: String { avgHR.map { "♥\(Int($0))" } ?? "--" }

    var body: some View {
        let theme = store.theme
        ScrollView {
            VStack(alignment: theme == .game ? .center : .leading, spacing: 6) {
                switch theme {
                case .colour: colour
                case .tiles: tiles
                case .game: game
                }
                if saved { Label("Saved to Health", systemImage: "heart.fill").font(W.label(10)).foregroundStyle(theme == .colour ? .white : .pink) }
                LimeButton(title: "DONE", action: onDone)
            }
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(0x3DFFB0, 0x1E9BFF), glow: 0xB23DFF))
        // Level ladder (#242): full-screen level-up with the rank's effect, same as the iPhone.
        .overlay {
            if let level = store.reward?.levelUp, !celebrated, !demo {
                LevelUpCelebration(level: level, compact: true) { celebrated = true }
            }
        }
        .onAppear {
            WKInterfaceDevice.current().play(.success)
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { dance = true }
        }
    }

    private var colour: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SESSION COMPLETE").font(W.label(9)).tracking(1)
            Text(store.reward?.weekCleared == true ? "Chest opened 🎁" : "Stage cleared 🏆").font(W.display(20))
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                GridRow { stat("+\(xp)", "xp"); stat("\(player.totalSets)", "sets") }
                GridRow { stat("\(minutes)′", "time"); stat(hr, "avg") }
            }
            rewardLines
        }
        .foregroundStyle(.white)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(W.display(20)).lineLimit(1).minimumScaleFactor(0.6)
            Text(l.uppercased()).font(W.label(8)).tracking(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .glass()
    }

    private var xp: Int { store.reward?.xp ?? WGame.xp(sets: player.totalSets) }

    /// Level-up and new badges, in every look (#227).
    @ViewBuilder private var rewardLines: some View {
        if let level = store.reward?.levelUp {
            Text("⬆️ Level \(level) · \(GameRank.of(level: level).title)").font(W.label(12)).foregroundStyle(W.ink)
                .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(W.lime))
        }
        ForEach(store.reward?.badges ?? []) { b in
            Label("New badge: \(b.title)", systemImage: b.symbol).font(W.label(10)).foregroundStyle(W.ink)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(W.gradient(b.tint.0, b.tint.1)))
        }
    }

    private var tiles: some View {
        VStack(spacing: 5) {
            Text("Done 🏆").font(W.display(18)).frame(maxWidth: .infinity, alignment: .leading)
            TileRow(symbol: "stopwatch.fill", title: "Time", value: "\(minutes)′", tint: W.gradient(0x3DFFB0, 0x1E9BFF))
            TileRow(symbol: "dumbbell.fill", title: "Sets", value: "\(player.totalSets)", tint: W.gradient(0xFF7A3D, 0xFF3D5A))
            TileRow(symbol: "heart.fill", title: "Avg HR", value: hr, tint: W.gradient(0xB23DFF, 0xFF3DA8))
            TileRow(symbol: "flame.fill", title: "kcal", value: "\(Int(kcal))", tint: W.gradient(0xFFC23D, 0xFF7A3D))
            TileRow(symbol: "star.fill", title: "XP", value: "+\(xp)", tint: W.gradient(0xB23DFF, 0xFF3DA8))
            if let g = store.snapshot.game { XPBar(game: g) }
            rewardLines
        }
    }

    private var game: some View {
        let reward = store.reward
        return VStack(spacing: 4) {
            ZStack {
                ForEach(Array(Self.confetti.enumerated()), id: \.offset) { _, c in
                    Text(c.emoji).font(.system(size: 14))
                        .offset(x: c.x, y: c.y + (dance ? -4 : 4))
                }
                MonkeyFace(mood: .party, gear: store.snapshot.game?.rank.gear)
                    .rotationEffect(.degrees(dance ? 10 : -10))
                    .offset(y: dance ? -3 : 2)
            }
            .frame(height: 64)
            Text("+\(xp) XP").font(W.display(24)).foregroundStyle(W.lime)
            if reward?.weekCleared == true { Text("🎁 Week chest +\(WGame.weekBonus)").font(W.label(10)) }
            Text("\(minutes)′ · \(player.totalSets) sets · \(Int(kcal)) kcal · \(hr)").font(W.label(9)).opacity(0.9)
            rewardLines
            if let g = store.snapshot.game { XPBar(game: g).padding(.top, 2) }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - iPhone mirror

/// Workout running on the iPhone: follow it and control it from the wrist.
struct MirrorView: View {
    let live: WLive
    @Environment(WatchStore.self) private var store

    private var resting: Bool { live.restEnd.map { $0 > .now } ?? false }

    var body: some View {
        let theme = store.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                TrackingBar()
                switch theme {
                case .colour: colour
                case .tiles: tiles
                case .game: game
                }
                controls(theme)
                Text("Next: \(live.next)").font(W.label(9)).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(.white.opacity(theme == .colour ? 0.2 : 0.1)))
            }
            .foregroundStyle(.white)
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(live.tint, 0xFF3D5A), glow: live.tint))
    }

    private var eyebrow: String { "📱 \(live.sessionTitle)" }

    private var colour: some View {
        VStack(alignment: .leading, spacing: 1) {
            Eyebrow(text: eyebrow, color: .white.opacity(0.85))
            Text(live.setLabel.uppercased()).font(W.label(9)).tracking(1)
            Text(live.exercise).font(W.display(19)).lineLimit(2).minimumScaleFactor(0.6)
            if resting { restClock(34) } else if !live.detail.isEmpty {
                Text(live.detail).font(W.display(28)).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(live.setLabel.uppercased()).font(W.label(8)).tracking(1).opacity(0.9)
            Text(live.exercise).font(W.display(15)).lineLimit(2).minimumScaleFactor(0.6)
            HStack {
                Spacer(minLength: 0)
                if resting { restClock(26) } else { Text(live.detail).font(W.display(22)).lineLimit(1).minimumScaleFactor(0.5) }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(live.tint, 0xFF3D5A)))
    }

    private var game: some View {
        ZStack {
            Circle().stroke(W.color(live.tint).opacity(0.2), lineWidth: 10)
            Circle().trim(from: 0, to: 0.75)
                .stroke(LinearGradient(colors: [W.color(live.tint), W.color(0xFF7A3D)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(live.exercise) · \(live.setLabel)".uppercased()).font(W.label(7)).tracking(0.5).lineLimit(2)
                    .multilineTextAlignment(.center)
                if resting { restClock(24) } else {
                    Text(live.detail.isEmpty ? live.action : live.detail).font(W.display(20)).lineLimit(2).minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(16)
        }
        .frame(width: 124, height: 124)
        .frame(maxWidth: .infinity)
    }

    private func restClock(_ size: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Text(WatchPlayer.clock(max(0, (live.restEnd ?? ctx.date).timeIntervalSince(ctx.date))))
                .font(W.display(size)).monospacedDigit().foregroundStyle(W.lime)
        }
    }

    @ViewBuilder private func controls(_ theme: WTheme) -> some View {
        if resting {
            HStack(spacing: 5) {
                pill("+15 s", theme == .tiles ? AnyShapeStyle(W.gradient(0x3D5AFF, 0x7B3DFF)) : AnyShapeStyle(Color.white.opacity(0.2)), .white) {
                    store.send(WCommand.addRest)
                }
                pill("Skip", AnyShapeStyle(W.lime), W.ink) { store.send(WCommand.skipRest) }
            }
        }
        if live.effortPending {
            EffortGrid { store.send([WCommand.effort0, .effort1, .effort2, .effort3, .effort4][$0]) }
        } else if !resting {
            LimeButton(title: live.action) { store.send(WCommand.main) }
        }
    }

    private func pill(_ title: String, _ fill: AnyShapeStyle, _ text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(W.label(12)).foregroundStyle(text)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pro lock

/// Starting a workout on the Watch needs Pro (#126); iPhone workouts still mirror for free.
struct ProLockView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let theme = store.theme
        ScrollView {
            VStack(spacing: 6) {
                if theme == .game {
                    MonkeyFace(mood: .sleepy)
                } else {
                    Image(systemName: "crown.fill").font(.system(size: 22, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 13).fill(theme == .tiles ? AnyShapeStyle(W.gradient(0xFFC23D, 0xFF7A3D))
                                                                                           : AnyShapeStyle(Color.white.opacity(0.25))))
                }
                Text("Apple Watch is Pro").font(W.display(17))
                Text(theme == .game ? "Unlock Pro on your iPhone to start quests here. iPhone workouts still show on your Watch."
                     : "Unlock MonkeyWorkout Pro on your iPhone. Workouts started on the iPhone still show here.")
                    .font(.footnote).multilineTextAlignment(.center).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(0xFFC23D, 0xFF7A3D), glow: 0xFFC23D))
    }
}
