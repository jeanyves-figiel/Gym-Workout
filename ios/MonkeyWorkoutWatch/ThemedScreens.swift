import LiftSensor
import SwiftUI
import WatchKit

// Watch screens in the three looks (#219), picked with the home style (WatchStore.theme):
// Crown deck → full colour (screen in the workout's colour, white glass cards, huge numbers),
// Charge & go → tiles (black, Explore gradient tiles: icon tile left, big number right),
// Monkey coach → game (quest path, XP, level, badges, monkey celebrations).
// XP, level and badges show in all three, matching the iPhone's look for the same pick (#227).
// Since #389 the shared screens (week list, workout, progress, done) use Explore cards in all three looks;
// the looks differ on the home screen and in the iPhone mirror.

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
                Text(title).font(W.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(detail).font(W.label(10)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8) }
            }
            Spacer(minLength: 2)
            Text(value).font(W.display(18)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint))
    }
}

// MARK: - Plan days and workouts

/// Plan days or other workouts: Explore cards in every look (#389), quest XP in the game look.
struct SessionListView: View {
    @Environment(WatchStore.self) private var store
    let title: String
    let sessions: [WSession]

    var body: some View {
        let game = store.theme == .game
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ScreenTitle(text: title)
                ForEach(sessions) { s in
                    NavigationLink(value: s) {
                        TileRow(symbol: s.done ? "checkmark" : s.isMissed ? "exclamationmark" : "calendar", title: s.title,
                                detail: s.isMissed ? "\(s.dayLabel) · missed" : s.done ? "\(s.dayLabel) · cleared"
                                    : game ? "\(s.dayLabel) · +\(W.xp(s)) XP" : s.dayLabel,
                                value: "\(s.estMin)′", tint: s.isMissed ? W.gradient(0xFF3D6E, 0xFF8A3D) : W.gradient(s))
                            .opacity(s.done ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .watchMargins()
        }
    }
}

// MARK: - Workout

/// Exercises of a session with suggested loads, as Explore cards (#389); tap one for its form cues. START stays pinned.
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
            VStack(alignment: .leading, spacing: 5) {
                header(theme)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Button { cues = row.item } label: {
                        TileRow(symbol: W.symbol(row.block), title: row.item.name, detail: load(row.item) ?? row.block.title,
                                value: W.dose(row.item), tint: W.gradient(row.block.tint, row.block.tint2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .watchMargins()
        }
        .pinnedButton(theme == .game ? "▶ GO!" : "▶ START", when: session.startsToday) { onStart(session) }
        .sheet(item: $cues) { it in CuesSheet(item: it, block: rows.first { $0.item.uid == it.uid }?.block, theme: theme) }
    }

    private func header(_ theme: WTheme) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ScreenTitle(text: session.title)
            Text(theme == .game ? "+\(W.xp(session)) XP · \(session.items.count) bosses".uppercased()
                 : "\(session.estMin)′ · \(session.blocks.count) blocks · \(session.items.count) ex".uppercased())
                .font(W.label(10)).tracking(1).foregroundStyle(theme == .game ? W.lime : .white.opacity(0.85))
            if !session.startsToday { PlannedTag(day: session.dayLabel).padding(.top, 4) }
        }
        .padding(.bottom, 3)
    }

    private func load(_ it: WItem) -> String? {
        guard let kg = it.kg, it.loggable else { return nil }
        return "↑ \(WatchPlayer.kg(kg)) kg\(it.targetReps.map { " × \($0)" } ?? "")"
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
            .watchMargins()
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

/// Streak, week, best lifts, recent sessions, level and badges: Explore cards in every look (#389).
struct ProgressScreen: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let p = store.snapshot.progress
        ScrollView {
            VStack(spacing: 5) {
                ScreenTitle(text: store.theme == .game ? "Level \(store.snapshot.game?.level ?? 1)" : "Progress")
                tiles(p)
            }
            .watchMargins()
        }
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
                TileRow(symbol: "medal.fill", title: "Badges", detail: g.earned.last?.title, value: "\(g.earned.count)/\(g.catalog?.count ?? 0)",
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
                Text(title).font(W.label(10)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text(value).font(W.display(20)).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint))
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
            Text("\(game.rank.title) · \(game.xpInLevel)/\(WGame.perLevel) XP → LV \(game.level + 1)").font(W.label(10))
                .lineLimit(1).minimumScaleFactor(0.7)
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
                    ScreenTitle(text: "Levels")
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
                .watchMargins()
            }
            .onAppear { proxy.scrollTo(game.rank, anchor: .center) }
        }
    }
}

// MARK: - Done

/// After a workout on the Watch: time, sets, HR, kcal, XP as Explore cards in every look (#389); level-up and new badges.
struct SummaryView: View {
    @Environment(WatchStore.self) private var store
    let player: WatchPlayer
    let kcal: Double
    let avgHR: Double?
    let saved: Bool
    let onDone: () -> Void
    @State private var celebrated = false
    @State private var effort: Double = 7

    private var demo: Bool {
        #if DEBUG
        Demo.on
        #else
        false
        #endif
    }

    private var minutes: Int { Int((player.endedAt ?? Date()).timeIntervalSince(player.started)) / 60 }
    private var hr: String { avgHR.map { "♥\(Int($0))" } ?? "--" }
    private var xp: Int { store.reward?.xp ?? WGame.xp(sets: player.totalSets) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ScreenTitle(text: store.reward?.weekCleared == true ? "Chest opened 🎁" : "Done 🏆")
                TileRow(symbol: "star.fill", title: "XP", detail: store.reward?.weekCleared == true ? "+\(WGame.weekBonus) week chest" : nil,
                        value: "+\(xp)", tint: W.gradient(0xB23DFF, 0xFF3DA8))
                TileRow(symbol: "stopwatch.fill", title: "Time", value: "\(minutes)′", tint: W.gradient(0x3DFFB0, 0x1E9BFF))
                TileRow(symbol: "dumbbell.fill", title: "Sets", value: "\(player.totalSets)", tint: W.gradient(0xFF7A3D, 0xFF3D5A))
                TileRow(symbol: "heart.fill", title: "Avg HR", value: hr, tint: W.gradient(0xFF3D6E, 0xB0105A))
                TileRow(symbol: "flame.fill", title: "kcal", value: "\(Int(kcal))", tint: W.gradient(0xFFC23D, 0xFF7A3D))
                rewardLines
                // Effort + mood to Apple Health (#614 C): Crown for effort, tap a face.
                if saved { WatchEffortAsk(effort: $effort) }
                WatchMoodAsk()
                if let g = store.snapshot.game { XPBar(game: g) }
                if saved { Label("Saved to Health", systemImage: "heart.fill").font(W.label(10)).foregroundStyle(.pink) }
            }
            .watchMargins()
        }
        .pinnedButton("DONE") {
            if saved { let e = Int(effort); Task { await WorkoutManager.shared.saveEffort(e) } }
            onDone()
        }
        // Level ladder (#242): full-screen level-up with the rank's effect, same as the iPhone.
        .overlay {
            if let level = store.reward?.levelUp, !celebrated, !demo {
                LevelUpCelebration(level: level, compact: true) { celebrated = true }
            }
        }
        .onAppear { WKInterfaceDevice.current().play(.success) }
    }

    /// Level-up and new badges, in every look (#227).
    @ViewBuilder private var rewardLines: some View {
        if let level = store.reward?.levelUp {
            Text("⬆️ Level \(level) · \(GameRank.of(level: level).title)").font(W.label(12)).foregroundStyle(W.ink)
                .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(W.lime))
        }
        ForEach(store.reward?.badges ?? []) { b in
            Label("New badge: \(b.title)", systemImage: b.symbol).font(W.label(11)).foregroundStyle(W.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(W.gradient(b.tint.0, b.tint.1)))
        }
    }
}

/// Effort 1–10 (#614 C): turn the Crown on the tile, saved with the workout on Done.
struct WatchEffortAsk: View {
    @Binding var effort: Double

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("EFFORT").font(W.label(9)).tracking(1).opacity(0.9)
                Text("⟳ Crown").font(W.label(9)).opacity(0.75)
            }
            Spacer(minLength: 2)
            Text("\(Int(effort))").font(.system(size: 30, weight: .black, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.gradient(0xFF9E1C, 0xFF3D5A)))
        .focusable()
        .digitalCrownRotation($effort, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityLabel("Effort")
        .accessibilityValue("\(Int(effort)) of 10")
    }
}

/// How do you feel now (#614 C): four faces saved to Health as a State of Mind (levels as on the iPhone).
struct WatchMoodAsk: View {
    @State private var picked: Int?
    private static let faces: [(Int, String)] = [(1, "😫"), (2, "😐"), (3, "🙂"), (5, "🤩")]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.faces, id: \.0) { level, face in
                Button {
                    picked = level
                    WKInterfaceDevice.current().play(.click)
                    Task { await WorkoutManager.shared.saveMood(level) }
                } label: {
                    Text(face).font(.system(size: picked == level ? 22 : 18))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(picked == level ? W.lime : Color.white.opacity(0.12)))
                        .opacity(picked == nil || picked == level ? 1 : 0.45)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - iPhone mirror

/// Workout running on the iPhone: follow it and control it from the wrist.
struct MirrorView: View {
    let live: WLive
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    /// Lift sensor (#383): measures the iPhone player's set while the Watch tracks the workout.
    @State private var lift = LiftTracker()
    @State private var tracked: WLive?
    @State private var autoLogAt: Date?
    @State private var byHand: Set<String> = []

    private var resting: Bool { live.restEnd.map { $0 > .now } ?? false }

    private var liftMode: WatchLiftMode { store.snapshot.liftSensor ?? .default }
    private var liftLogging: WatchLiftLogging { store.snapshot.liftLogging ?? .default }

    /// Counting level for an exercise (#410); corrections made on the iPhone teach it through the snapshot.
    private func strictness(_ exerciseId: String) -> Double {
        Strictness.level(setting: (store.snapshot.liftCounting ?? .default).level, learned: store.snapshot.liftLearned?[exerciseId] ?? 0)
    }

    /// Racked, waiting for a tap on SET DONE here or on the iPhone (Tap ✓ logging).
    private var waitingForTap: Bool {
        liftLogging == .confirm && lift.mode == .tracking && lift.endedAt != nil && lift.count > 0
    }

    /// The iPhone set to measure: loaded, being done, while the Watch runs the workout session (keeps it awake).
    private var liftKey: String? {
        guard liftMode.on, LiftTracker.available, workout.running, live.loggable == true, !resting, !live.effortPending,
              let ex = live.exerciseId, let i = live.setIndex, !byHand.contains(ex) else { return nil }
        return "\(live.sessionId ?? "")#\(ex)#\(i)"
    }

    private func syncLift(_ key: String?) {
        // Moving on (set done on the iPhone): the measured reps of the set before go to the iPhone.
        if let t = tracked, lift.mode == .tracking, let ex = t.exerciseId, let i = t.setIndex {
            let machine = lift.machine
            if let set = makeLiftSet(lift.stop(), sessionId: t.sessionId ?? "", exerciseId: ex, setIndex: i, kg: t.kg ?? 0, machine: machine) {
                store.send(.liftSet(set))
            }
        }
        autoLogAt = nil
        tracked = key == nil ? nil : live
        guard let key, let ex = live.exerciseId else {
            if lift.mode != .idle { lift.stop() }
            return
        }
        if let profile = LiftProfile.for(name: live.exercise, exerciseId: ex) {
            lift.track(key: key, profile: profile, lossLimit: liftMode.lossLimit, strictness: strictness(ex))
        } else if let spot = MachineSpot.for(name: live.exercise, exerciseId: ex) {
            lift.trackMachine(key: key, exercise: ex, family: spot.family, lossLimit: liftMode.lossLimit, strictness: strictness(ex))
        } else if lift.mode != .idle {
            lift.stop()
        }
        sendLift()
    }

    private func sendLift() {
        guard let t = tracked, let ex = t.exerciseId, let i = t.setIndex else { return }
        let hint = lift.mode == .strap || lift.mode == .testRep ? MachineSpot.for(name: t.exercise, exerciseId: ex).map { "Strap the Watch on \($0.place)" } : nil
        store.send(WLiftLive(sessionId: t.sessionId ?? "", exerciseId: ex, setIndex: i, reps: lift.count, lastVelocity: lift.lastVelocity,
                             velocityLoss: lift.velocityLoss, machine: lift.machine, ended: autoLogAt != nil || waitingForTap, strapHint: hint))
    }

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
                if lift.mode == .tracking, lift.count > 0 {
                    LiftPanel(lift: lift, reps: lift.count, tint: live.tint, waiting: waitingForTap)
                } else if lift.mode == .tracking {
                    SensingChip(machine: lift.machine)
                }
                if let autoLogAt {
                    AutoLogBanner(title: "\(lift.count) reps", end: autoLogAt) {
                        self.autoLogAt = nil
                        lift.resume()
                        sendLift()
                    }
                } else {
                    controls(theme)
                }
                // Coach line from the phone (#379) for 6 s, in the Next line's place.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    if let line = live.coach, let at = live.coachAt, ctx.date.timeIntervalSince(at) < 6 {
                        Text("🐵 \(line)").font(W.label(11)).lineLimit(2).minimumScaleFactor(0.8)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Capsule().fill(Color(red: 0.80, green: 1.0, blue: 0.24)))
                    } else {
                        Text("Next: \(live.next)").font(W.label(11)).lineLimit(1).minimumScaleFactor(0.8)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Capsule().fill(.white.opacity(theme == .colour ? 0.2 : 0.1)))
                    }
                }
            }
            .foregroundStyle(.white)
            .watchMargins()
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(live.tint, 0xFF3D5A), glow: live.tint))
        .overlay { mirrorLiftOverlay }
        .onChange(of: liftKey, initial: true) { _, key in syncLift(key) }
        .onChange(of: live) { old, new in
            // Same set, new load on the iPhone.
            if old.exerciseId == new.exerciseId, old.setIndex == new.setIndex, tracked != nil { tracked?.kg = new.kg }
        }
        .onChange(of: lift.count) { sendLift() }
        .onChange(of: lift.mode) { sendLift() }
        .onChange(of: lift.endedAt) { _, at in
            guard at != nil, autoLogAt == nil, lift.count > 0 else { return }
            switch liftLogging {
            case .auto: autoLogAt = Date().addingTimeInterval(WatchLiftLogging.countdown)
            case .confirm: WKInterfaceDevice.current().play(.notification)
            case .manual: break
            }
            sendLift()
        }
        .task(id: autoLogAt) {
            // Racked: the set completes on the iPhone (its reps were sent with the live state).
            guard let at = autoLogAt else { return }
            try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow)))
            guard !Task.isCancelled, autoLogAt == at else { return }
            autoLogAt = nil
            WKInterfaceDevice.current().play(.success)
            store.send(WCommand.main)
        }
        .onDisappear { syncLift(nil) }
    }

    @ViewBuilder private var mirrorLiftOverlay: some View {
        if let ex = live.exerciseId, let spot = MachineSpot.for(name: live.exercise, exerciseId: ex) {
            if lift.mode == .strap {
                StrapPrompt(exercise: live.exercise, spot: spot) {
                    lift.strapped(exercise: ex, family: spot.family, lossLimit: liftMode.lossLimit, strictness: strictness(ex))
                } onSkip: {
                    byHand.insert(ex)
                }
            } else if lift.mode == .testRep || lift.calibratedAt != nil {
                TestRepView(calibrated: lift.mode == .tracking) { byHand.insert(ex) }
                    .task(id: lift.calibratedAt) {
                        guard lift.calibratedAt != nil else { return }
                        try? await Task.sleep(for: .seconds(1.6))
                        lift.clearCalibrated()
                    }
            }
        }
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

    /// Ring (#389): exercise and set above it, only the load inside, drawn inside its frame so the button never overlaps it.
    private var game: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(live.setLabel.uppercased()).font(W.label(10)).tracking(1).opacity(0.9)
            Text(live.exercise).font(W.display(16)).lineLimit(1).minimumScaleFactor(0.6)
            ZStack {
                Circle().strokeBorder(W.color(live.tint).opacity(0.2), lineWidth: 9)
                Circle().inset(by: 4.5).trim(from: 0, to: 0.75)
                    .stroke(LinearGradient(colors: [W.color(live.tint), W.color(0xFF7A3D)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Group {
                    if resting { restClock(26) } else {
                        Text(live.detail.isEmpty ? live.action : live.detail).font(W.display(22)).lineLimit(2).minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(14)
            }
            .frame(width: 104, height: 104)
            .frame(maxWidth: .infinity)
        }
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
                pill("Skip", AnyShapeStyle(W.lime), W.ink, pinch: true) { store.send(WCommand.skipRest) }
            }
        }
        if live.effortPending {
            EffortGrid { store.send([WCommand.effort0, .effort1, .effort2, .effort3, .effort4][$0]) }
        } else if !resting {
            LimeButton(title: live.action, pinch: true) { store.send(WCommand.main) }
        }
    }

    private func pill(_ title: String, _ fill: AnyShapeStyle, _ text: Color, pinch: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(W.label(12))
                if pinch { PinchMark() }
            }
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
        .pinch(pinch)
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
            .watchMargins()
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(0xFFC23D, 0xFF7A3D), glow: 0xFFC23D))
    }
}
