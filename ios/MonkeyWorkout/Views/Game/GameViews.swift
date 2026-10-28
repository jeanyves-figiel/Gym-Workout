import SwiftUI
import WorkoutEngine

// iPhone game looks (#227), tied to the Watch style pick (#219) so both devices match:
// Monkey coach → the monkey on Train, dances when you finish, trophy shelf;
// Crown deck → Quest map: days are stages, a chest opens when the week's goal is met;
// Charge & go → Level bar: level chip, XP bar, level card.
// Level ladder (#242, WatchShared/GameLadder.swift): six ranks with their unlocks; level row on Progress opens it.
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
        case .coach: "Your monkey on Train with tips and moods, a dance when you finish. Your rank gear on the monkey."
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

enum GameTint {
    static let level = LinearGradient(colors: [Color(hex: 0xB23DFF), Color(hex: 0xFF3DA8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let quest = LinearGradient(colors: [Color(hex: 0xFFC23D), Color(hex: 0xFF3D5A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let shelf = LinearGradient(colors: [Color(hex: 0x3D5AFF), Color(hex: 0x7B3DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Lime, or the colour picked from Steel on (#242).
    @MainActor static var xp: LinearGradient { WatchHomePref.shared.accent.gradient }
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

/// Every level display opens the ladder (#242): LV chip, level bar, banners, finish card.
private struct OpensLevels: ViewModifier {
    @State private var open = false

    func body(content: Content) -> some View {
        Button { open = true } label: { content.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what each level brings")
            .sheet(isPresented: $open) { LevelLadderSheet() }
    }
}

extension View {
    func opensLevels() -> some View { modifier(OpensLevels()) }
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
                Text("Level \(g.level) · \(model.rank.title)").font(Theme.label(12)).tracking(1.3).textCase(.uppercase).foregroundStyle(Theme.lime)
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
        .opensLevels()
    }
}

// MARK: - Monkey coach

/// Train: the monkey with a mood from the week, streak and readiness. Tap or swipe for the next tip; every chip
/// and each tip's button opens its place (#278).
struct MonkeyCoachCard: View {
    /// The week card's tiles inside this card (#564, design D1); the "n/N this week" chip then goes.
    var weekFooter: AnyView? = nil
    /// Starts a session in the player (the Train screen owns it).
    var onStart: (Session) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.trainCompact) private var compact
    @State private var tip = 0
    @State private var hop = false
    @State private var bob = false
    @State private var catchUp: WeekDayStrip.DayPick?
    /// The "N missed" chip: every missed day, not only the first.
    @State private var catchUpAll = false
    @State private var levels = false
    /// Workout chat (#381).
    /// Spotted in Health (#416): a sport session to rate, with a swap for today when it clashes.
    @State private var sportSession: SportEntry?
    /// Snow ready season nudge (#428 C): the programme page as a sheet; opening it marks this season as seen.
    @State private var snowProgramme: ProgrammeRoute?
    @AppStorage("snowNudgeSeen") private var snowSeen = 0

    private enum Action {
        case start(Session), catchUp(Int), progress(ProgressSection), exercise(String), levels, calendar, sport(SportEntry), programme(String)
    }

    private struct Tip {
        var text: String
        var tint: (UInt32, UInt32)
        var cta: String
        var action: Action
    }

    var body: some View {
        let target = model.gameTarget
        let stats = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: target)
        let next = model.nextSession
        let mood = MonkeyFace.Mood.from(weekDone: model.weekDone(thisWeek: stats.thisWeek, target: target),
                                        readiness: Readiness.assess(health.snapshot)?.0.title, streakWeeks: stats.currentStreakWeeks)
        let all = tips(mood: mood, next: next, stats: stats, target: target)
        let current = all[tip % all.count]
        let missed = model.missedSessions
        // Slim (#337, design A): smaller monkey, two-line tip, action as a pill beside the chips, so Next up's
        // Start workout fits above the tab bar.
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                MonkeyFace(mood: mood, scale: 0.95, gear: model.rank.gear)
                    .scaleEffect(hop ? 1.12 : 1)
                    .rotationEffect(.degrees(hop ? -12 : 0))
                    .offset(y: hop ? -8 : (bob ? -2 : 0))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach Monkey · \(mood.word)").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                    Text(current.text)
                        .font(Theme.display(20)).lineLimit(compact ? 1 : 2).minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(tip)
                        .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, compact ? 44 : 28)
            .contentShape(Rectangle())
            .onTapGesture { poke(by: 1, count: all.count) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Monkey coach: \(current.text)")
            .accessibilityHint("Shows another tip")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { poke(by: 1, count: all.count) }
            // Stat chips stay inside the card (#303): full labels when they fit, shorter ones on narrow phones.
            // The tip's action sits on the same row when it fits, else its own row under the chips.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    statChips(stats: stats, target: target, missed: missed, short: false)
                    tipButton(current)
                }
                HStack(spacing: 6) {
                    statChips(stats: stats, target: target, missed: missed, short: true)
                    tipButton(current)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        statChips(stats: stats, target: target, missed: missed, short: false)
                        statChips(stats: stats, target: target, missed: missed, short: true)
                    }
                    tipButton(current, wide: true)
                }
            }
            .buttonStyle(.plain)
            if let weekFooter { weekFooter }
        }
        .foregroundStyle(.white)
        .padding(14)
        .padding(.bottom, all.count > 1 ? 6 : 0)
        .overlay(alignment: .bottom) {
            if all.count > 1 {
                HStack(spacing: 4) {
                    ForEach(all.indices, id: \.self) { i in
                        Circle().fill(.white.opacity(i == tip % all.count ? 1 : 0.4)).frame(width: 5, height: 5)
                    }
                }
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: current.tint.0), Color(hex: current.tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(alignment: .topTrailing) {
            // Next tip (#303) is the card's only corner button: Coach chat opens from the 🐵 header tile (#775).
            Button { poke(by: 1, count: all.count) } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.28)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next tip")
            .padding(12)
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
            poke(by: v.translation.width < 0 ? 1 : -1, count: all.count)
        })
        .animation(.easeInOut(duration: 0.35), value: tip)
        .sensoryFeedback(.impact(weight: .light), trigger: tip)
        .sheet(item: $catchUp) { MissedCatchUpSheet(weekday: $0.id) }
        .sheet(isPresented: $catchUpAll) { MissedCatchUpSheet(weekday: nil) }
        .sheet(isPresented: $levels) { LevelLadderSheet() }
        .sheet(item: $sportSession) { SportSessionSheet(entry: $0) }
        .sheet(item: $snowProgramme) { ProgrammeSheet(id: $0.id) }
        .onAppear {
            guard !reduceMotion else { return }
            poke(by: 0, count: 0)
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private func statChips(stats: ProgressStats, target: Int, missed: [Session], short: Bool) -> some View {
        HStack(spacing: 6) {
            Button { open(.progress(.training)) } label: { gameChip("🔥 \(stats.currentStreakWeeks)\(short ? "" : " wk") ›") }
                .accessibilityLabel("\(stats.currentStreakWeeks)-week streak").accessibilityHint("Opens Training in Progress")
            if weekFooter == nil {
                NavigationLink { CalendarView() } label: { gameChip("\(stats.thisWeek)/\(target) \(short ? "wk" : "this week") ›") }
                    .accessibilityLabel("\(stats.thisWeek) of \(target) this week").accessibilityHint("Opens the calendar")
            }
            if !missed.isEmpty {
                Button { catchUpAll = true } label: {
                    gameChip("\(missed.count) missed ›", fill: Color(hex: 0xFFD23F), ink: Theme.ink)
                }
                .accessibilityHint("Log it, mark it done, do it today or skip")
            }
        }
        .fixedSize()
    }

    /// The current tip's action as a lime pill: fills the rest of the chip row, or a full row when it has its own.
    @ViewBuilder private func tipButton(_ t: Tip, wide: Bool = false) -> some View {
        let label = Text("\(t.cta) ›").font(Theme.label(13)).foregroundStyle(Theme.ink).lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color(hex: 0xD6FF3D)))
            .fixedSize(horizontal: !wide, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            switch t.action {
            case .calendar: NavigationLink { CalendarView() } label: { label }
            case .exercise(let id): NavigationLink { ExerciseDetailView(exerciseId: id) } label: { label }
            default: Button { open(t.action) } label: { label }
            }
        }
        .buttonStyle(.plain)
        .id(tip)
    }

    private func open(_ action: Action) {
        switch action {
        // Only today's session starts (#537); another day's opens its page.
        case .start(let s):
            if model.startableToday(s) { onStart(s) } else { NotificationManager.shared.route = .session(s.id) }
        case .catchUp(let wd): catchUp = .init(id: wd)
        case .progress(let section):
            model.progressJump = section
            model.tab = .progress
        case .levels: levels = true
        case .sport(let e): sportSession = e
        case .programme(let id): snowProgramme = ProgrammeRoute(id: id)
        case .exercise, .calendar: break // NavigationLinks
        }
    }

    private func poke(by step: Int, count: Int) {
        if count > 0 { tip = ((tip + step) % count + count) % count }
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
        let missed = model.missedSessions
        let go: Action = next.map { .start($0) } ?? .progress(.training)
        // Only today's session starts (#537): another day's tip opens its page, so it says See.
        let cta = next.map { "\(model.startableToday($0) ? "Start" : "See") \($0.displayTitle)" } ?? "See progress"
        var out: [Tip] = if next == nil, let m = missed.first, mood != .party {
            // Nothing left this week but a missed session (#266).
            [Tip(text: "Missed \(m.displayTitle)? Log it or do it today 💪", tint: (0xFF3D6E, 0xFF8A3D), cta: "Catch up", action: .catchUp(m.weekday ?? model.todayWeekday))]
        } else {
            switch mood {
            case .party: [Tip(text: "Week done! You legend 🏆", tint: (0x3DFFB0, 0x1E9BFF), cta: "See progress", action: .progress(.training))]
            case .sleepy: [Tip(text: "Easy does it today. Quality reps 😴", tint: (0x3D5AFF, 0x7B3DFF), cta: cta, action: go)]
            case .fired: [Tip(text: "Let's crush \(title)! 💥", tint: (0xB23DFF, 0xFF3DA8), cta: cta, action: go)]
            case .happy: [Tip(text: "Ready for \(title)? 💪", tint: (0xFFC23D, 0xFF7A3D), cta: cta, action: go)]
            }
        }
        // Other sports (#416, design C): a Health session to rate comes first; a hard one that clashes with today
        // offers the swap. Nothing new on Train: it's a tip like the others.
        let sports = Sports.merged(local: model.sportLogs, health: health.snapshot.recentSports)
        if let e = Sports.spotted(sports, rated: Set(model.sportLogs.map(\.id))).first {
            let when = Calendar.current.isDateInToday(e.start) ? "today" : "yesterday"
            out.insert(Tip(text: "Spotted: \(e.sport.short) \(e.durationText) \(when). How was it? \(e.sport == .scubaDiving ? "🤿" : "👀")",
                           tint: (0x7D4DFF, 0xE040FB), cta: "Rate it", action: .sport(e)), at: 0)
        } else if let e = Sports.recentHard(sports), let n = next, n.weekday == model.todayWeekday,
                  let to = Sports.swap(for: n.focus, after: e.sport), model.canChangeFocus(n) {
            out.insert(Tip(text: "\(e.sport.loadLabel.capitalized) loaded by \(e.sport.short). \(n.focus.dayLabel) → \(to.dayLabel)?",
                           tint: (0x00B86B, 0x1EC8A5), cta: "Review & swap", action: .sport(e)), at: 0)
        }
        // Snow ready (#428 C): skiers and snowboarders get the pre-season programme first, each autumn until they look.
        if let ride = Programme.snowNudge(sports: model.profile?.sports, running: model.activeProgramme != nil,
                                          seenSeason: snowSeen, now: .now) {
            let who = ride == .both ? "You ski and ride" : ride == .ski ? "You ski" : "You snowboard"
            out.insert(Tip(text: "Season's coming! \(who): get your legs snow ready ❄️", tint: (0x00C6FF, 0x8A2BFF),
                           cta: "See Snow ready", action: .programme(ride.programmeId)), at: 0)
        }
        if stats.currentStreakWeeks > 0 {
            let best = stats.currentStreakWeeks >= stats.bestStreakWeeks && stats.currentStreakWeeks > 1
            out.append(Tip(text: "🔥 \(stats.currentStreakWeeks)-week streak\(best ? ". Best ever!" : "")", tint: (0xFFC23D, 0xFF7A3D),
                           cta: "See streak", action: .progress(.training)))
        }
        if let r = stats.personalRecords.first {
            out.append(Tip(text: "🏅 Best \(Exercise.get(r.exerciseId).name): \(Format.kg(r.kg)) kg. Beat it!", tint: (0x3D5AFF, 0x1E9BFF),
                           cta: "Open \(Exercise.get(r.exerciseId).name)", action: .exercise(r.exerciseId)))
        }
        let g = model.game
        out.append(Tip(text: "⭐ Level \(g.level): \(g.xpToNext) XP to level \(g.level + 1)", tint: (0x3DFFB0, 0x1E9BFF),
                       cta: "See levels", action: .levels))
        let left = max(0, target - stats.thisWeek)
        let text: String = if left == 0 {
            "\(stats.thisWeek)/\(target) this week. Bonus round?"
        } else if !missed.isEmpty {
            // Missed sessions can't be done on their day any more: "to go" counts what's still planned (#266).
            "\(stats.thisWeek)/\(target) done, \(missed.count) missed. \(min(left, model.remainingCount)) to go!"
        } else {
            "\(stats.thisWeek)/\(target) this week. \(left) to go!"
        }
        out.append(Tip(text: text, tint: (0xFF7A3D, 0xFF3D5A), cta: "Open calendar", action: .calendar))
        // Tips from the server (#583), after the member's own.
        for t in Remote.shared.coachTips {
            let action: Action? = switch t.action {
            case "progress": .progress(.training)
            case "calendar": .calendar
            case "levels": .levels
            default: nil
            }
            if let action { out.append(Tip(text: t.text, tint: t.colors, cta: t.cta, action: action)) }
        }
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
                                   current: s.id == nextId, today: model.todayWeekday, xp: model.xp(for: s),
                                   left: i.isMultiple(of: 2), width: w)
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
    /// Today, 1 = Monday … 7 = Sunday.
    let today: Int
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

    /// The next stage is "Today" only on its own day (#369): an unscheduled one can be done today too.
    private var when: String {
        guard let weekday else { return "Today" }
        return weekday == today ? "Today" : weekday == today + 1 ? "Tomorrow" : "Next"
    }

    private func label(_ align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 2) {
            Text(weekday.map { WeekSchedule.name($0) } ?? "Stage \(number)").font(Theme.label(11)).tracking(1).textCase(.uppercase)
                .foregroundStyle(current ? Theme.lime : Theme.muted)
            Text(current ? "\(when) · \(session.displayTitle)" : session.displayTitle)
                .font(.system(size: current ? 17 : 15, weight: .heavy, design: .rounded)).lineLimit(2)
                .multilineTextAlignment(align == .leading ? .leading : .trailing)
            Text(done ? "Cleared · +\(xp) XP" : "\(session.blocks.reduce(0) { $0 + $1.items.count }) bosses · +\(xp) XP")
                .font(Theme.label(12)).foregroundStyle(done ? Theme.lime : .white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: width * 0.5, alignment: align == .leading ? .leading : .trailing)
    }
}

/// The week's chest: opens (+200 XP) when the session goal is met. Tap an open chest to replay its reveal (#476).
private struct QuestChestView: View {
    let done: Int
    let target: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = false
    @State private var replaying = false

    var body: some View {
        let open = done >= target
        Button { if open { replaying = true } } label: { chest(open) }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $replaying) {
                ChestReveal(sessions: done) { replaying = false }.presentationBackground(.clear)
            }
    }

    private func chest(_ open: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: open ? "gift.fill" : "shippingbox.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 76, height: 76)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GameTint.quest))
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

/// Full-screen week chest opening (#476): the closed chest shakes, bursts open, +200 XP counts up.
/// Shown on Train when the goal-meeting workout came from the Watch or was logged later, and on a chest tap.
struct ChestReveal: View {
    let sessions: Int
    var onDone: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake = false
    @State private var open = false

    private static let burst: [(emoji: String, x: CGFloat, y: CGFloat)] =
        [("✨", -110, -70), ("🎉", 112, -60), ("⭐", -130, 30), ("🍌", 126, 40), ("🎊", 0, -120), ("💰", -60, 100), ("✨", 70, 104)]

    var body: some View {
        // Story poster (#745) under the tap-to-close celebration, so it stays its own button.
        celebration
            .overlay(alignment: .bottom) {
                if open {
                    StoryShareButton(poster: .chest(sessions: sessions), title: "Share my week")
                        .padding(.horizontal, 32).padding(.bottom, 24)
                        .readableColumn()
                        .transition(.opacity)
                }
            }
    }

    private var celebration: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    ForEach(Array(Self.burst.enumerated()), id: \.offset) { _, b in
                        Text(b.emoji).font(.system(size: 30))
                            .offset(x: open ? b.x : 0, y: open ? b.y : 0)
                            .opacity(open ? 1 : 0)
                            .scaleEffect(open ? 1 : 0.2)
                    }
                    Image(systemName: open ? "gift.fill" : "shippingbox.fill")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 150, height: 150)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GameTint.quest))
                        .shadow(color: Color(hex: 0xFFC23D).opacity(open ? 0.9 : 0.4), radius: open ? 40 : 12)
                        .rotationEffect(.degrees(open ? 0 : shake ? 9 : -9))
                        .scaleEffect(open ? 1.08 : 0.92)
                }
                .frame(height: 260)
                Text(open ? "Chest opened!" : "Week chest").font(Theme.display(40))
                Text("+\(open ? GameProgress.weekBonus : 0) XP")
                    .font(Theme.display(54)).foregroundStyle(Theme.lime)
                    .contentTransition(.numericText()).monospacedDigit()
                Text("Week goal met · \(sessions) sessions").font(Theme.label(15)).opacity(0.8)
                Text("Tap to continue").font(.system(size: 13, weight: .semibold)).opacity(0.6).padding(.top, 12)
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .onAppear {
            if reduceMotion { open = true; return }
            withAnimation(.easeInOut(duration: 0.12).repeatCount(7, autoreverses: true)) { shake = true }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.9)) { open = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chest opened. Plus \(GameProgress.weekBonus) XP. Week goal met.")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Closes the celebration")
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
            case .coach: MonkeyFace(mood: .fired, scale: 0.8, gear: model.rank.gear)
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
        .opensLevels()
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
    @State private var celebrating = false

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
                    MonkeyFace(mood: .party, scale: 2.2, gear: model.rank.gear)
                        .rotationEffect(.degrees(dance ? 10 : -10))
                        .offset(y: dance ? -6 : 4)
                }
                .frame(height: 150)
                Text("Victory!").font(Theme.display(44))
            case .deck:
                Image(systemName: reward.weekCleared ? "gift.fill" : "flag.checkered")
                    .font(.system(size: 60, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 120, height: 120)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GameTint.quest))
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
                // Every look shows the chest (#476); the Quest map look already leads with it.
                if style == .deck {
                    gameChip("🎁 Week goal met · +\(GameProgress.weekBonus) XP bonus", fill: Color(hex: 0xFFC23D), ink: Theme.ink)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 26, weight: .bold))
                            .frame(width: 56, height: 56)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.3)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Week goal met").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                            Text("Chest opened · +\(GameProgress.weekBonus) XP").font(Theme.display(20))
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GameTint.quest))
                    .rotationEffect(.degrees(dance ? 1.5 : -1.5))
                }
            }
            levelCard
            ForEach(reward.badges) { b in
                HStack(spacing: 12) {
                    Image(systemName: b.symbol)
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LinearGradient(colors: b.tier.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
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
        .fullScreenCover(isPresented: $celebrating) {
            if let level = reward.levelUp {
                LevelUpCelebration(level: level) { celebrating = false }
                    .presentationBackground(.clear)
            }
        }
        .onAppear {
            var demo = false
            #if DEBUG
            demo = Demo.enabled
            #endif
            if reward.levelUp != nil, !shown, !demo { celebrating = true }
            withAnimation(.spring(duration: 1.2).delay(0.2)) { shown = true }
            guard !reduceMotion, style != .rings else { return }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { dance = true }
        }
    }

    private var levelCard: some View {
        let g = model.game
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reward.levelUp.map { "⬆️ Level \($0)!" } ?? "Level \(g.level) · \(model.rank.title)").font(Theme.display(18))
                Spacer()
                Text("\(g.xpInLevel) / \(GameProgress.perLevel) XP").font(Theme.label(12)).opacity(0.85).monospacedDigit()
            }
            XPBarView(progress: shown ? g.levelProgress : 0, track: .white.opacity(0.2))
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(reward.levelUp == nil ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(GameTint.level)))
        .opensLevels()
    }
}


// MARK: - Progress

/// Week chest card (#476, design A from `week-chest/proposals.png`): this week's chest and the XP earned
/// (workouts, chest, walking), then the last 8 weeks' chests. An open chest replays its opening on tap.
struct WeekChestCard: View {
    /// Tap while the chest is still closed: opens Training.
    var onClosed: () -> Void = {}
    @Environment(AppModel.self) private var model
    @State private var replaying = false

    var body: some View {
        let target = max(1, model.gameTarget)
        let weeks = GameWeek.recent(records: model.state.history, targetPerWeek: target)
        let now = weeks.last ?? GameWeek(weekStart: Date(), sessions: 0, workoutXP: 0, chestOpen: false)
        let move = MoveStore.shared.weekXP
        let total = now.workoutXP + now.chestXP + move
        let left = max(0, target - now.sessions)
        Button { if now.chestOpen { replaying = true } else { onClosed() } } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Week chest").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
                HStack(spacing: 12) {
                    Image(systemName: now.chestOpen ? "gift.fill" : "shippingbox.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 64, height: 64)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GameTint.quest))
                        .shadow(color: Color(hex: 0xFFC23D).opacity(now.chestOpen ? 0.8 : 0.3), radius: now.chestOpen ? 14 : 6)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("+\(total.formatted())").font(Theme.display(40)).monospacedDigit()
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text("XP this week").font(Theme.label(12)).opacity(0.9)
                    }
                }
                Text(now.chestOpen ? "Chest opened · +\(GameProgress.weekBonus) XP"
                     : "\(now.sessions)/\(target) sessions · \(left) to go")
                    .font(Theme.display(18))
                FlowLayout(spacing: 6) {
                    gameChip("🏋️ \(now.sessions) session\(now.sessions == 1 ? "" : "s") +\(now.workoutXP)", fill: .black.opacity(0.28))
                    if now.chestOpen { gameChip("🎁 +\(GameProgress.weekBonus)", fill: Theme.lime, ink: Theme.ink) }
                    if move > 0 { gameChip("👣 +\(move)", fill: .black.opacity(0.28)) }
                }
                HStack(spacing: 4) {
                    ForEach(weeks) { w in
                        Text(w.chestOpen ? "🎁" : "📦")
                            .font(.system(size: 16))
                            .opacity(w.chestOpen ? 1 : 0.4)
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(w.chestOpen ? Theme.lime.opacity(0.25) : .black.opacity(0.22)))
                    }
                }
                HStack {
                    Text(weeks.first.map { "W\(Progression.calendar().component(.weekOfYear, from: $0.weekStart))" } ?? "")
                    Spacer()
                    Text("Now")
                }
                .font(Theme.label(10)).opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFF7A3D), Color(hex: 0xFF3D8A)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(now.chestOpen
            ? "Week chest opened. \(total) XP this week. \(weeks.filter(\.chestOpen).count) of the last \(weeks.count) weeks opened."
            : "Week chest closed. \(now.sessions) of \(target) sessions. \(total) XP this week.")
        .accessibilityHint(now.chestOpen ? "Replays the chest opening" : "Opens Training")
        .fullScreenCover(isPresented: $replaying) {
            ChestReveal(sessions: now.sessions) { replaying = false }.presentationBackground(.clear)
        }
    }
}

/// Level row (#242): rank monkey, level, XP bar and the next unlock; tap opens the ladder.
/// The Progress page places it (its structure is owned there); this is the whole level section.
struct GameProgressCard: View {
    let badges: [Badge]
    @Environment(AppModel.self) private var model
    @State private var ladder = false

    var body: some View {
        let g = model.game
        let rank = model.rank
        Button { ladder = true } label: {
            HStack(spacing: 12) {
                RankMonkey(rank: rank, mood: .happy, scale: 0.72)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("Level \(g.level)").font(Theme.display(22))
                        Text(rank.title).font(Theme.label(11)).textCase(.uppercase).tracking(1)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.28)))
                        Spacer(minLength: 0)
                        Text("\(badges.filter(\.unlocked).count)/\(badges.count) 🏅").font(Theme.label(12)).opacity(0.9)
                    }
                    XPBarView(progress: g.levelProgress, height: 8, track: .black.opacity(0.25))
                    Text(nextLine(g, rank)).font(.footnote.weight(.semibold)).opacity(0.92).lineLimit(1).minimumScaleFactor(0.8)
                }
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy)).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(rank.gradient))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Level \(g.level), \(rank.title). \(nextLine(g, rank))")
        .accessibilityHint("Shows what each level brings")
        .sheet(isPresented: $ladder) { LevelLadderSheet() }
    }

    private func nextLine(_ g: GameProgress, _ rank: GameRank) -> String {
        guard let next = rank.next else { return "Legend. Every look unlocked 👑" }
        return "\((next.minXP - g.xp).formatted()) XP to \(next.title) · \(next.perks[0].title.lowercased())"
    }
}

/// Rank title next to a member's nickname in Community (#242): Regular and up; Legend gets the seal.
struct RankTitleChip: View {
    let level: Int?
    var compact = false

    var body: some View {
        if let level, GameRank.of(level: level) >= .regular {
            let rank = GameRank.of(level: level)
            HStack(spacing: 3) {
                if rank == .legend { Image(systemName: "checkmark.seal.fill") }
                Text(compact ? rank.title : "\(rank.title) · Level \(level)")
            }
            .font(Theme.label(compact ? 10 : 12)).textCase(.uppercase).tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 2 : 4)
            .background(Capsule().fill(rank.gradient))
            .fixedSize()
            .accessibilityLabel("\(rank.title), level \(level)")
        }
    }
}

/// The whole ladder (#242): every rank, its levels and what it unlocks; current rank highlighted.
struct LevelLadderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let g = model.game
        let current = model.rank
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(g, current)
                        ForEach(GameRank.allCases.reversed()) { rank in
                            rankCard(rank, current: current, g: g).id(rank)
                        }
                        Label("Levels unlock looks, never training features. Every workout earns 50 XP + 5 per set, and meeting your week goal adds \(GameProgress.weekBonus).",
                              systemImage: "info.circle.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                            .padding(.top, 4)
                    }
                    .padding(16)
                }
                .onAppear { proxy.scrollTo(current, anchor: .center) }
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Levels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
    }

    private func header(_ g: GameProgress, _ rank: GameRank) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RankMonkey(rank: rank, mood: .party, scale: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rank.title).font(Theme.label(12)).textCase(.uppercase).tracking(1.3).opacity(0.85)
                    Text("Level \(g.level)").font(Theme.display(36))
                    Text("\(g.xp.formatted()) XP total").font(.footnote.weight(.semibold)).opacity(0.9)
                }
                Spacer(minLength: 0)
            }
            XPBarView(progress: g.levelProgress, track: .black.opacity(0.25))
            Text("\(g.xpToNext) XP to level \(g.level + 1)").font(.footnote.weight(.semibold)).opacity(0.9)
            // Story sheet (#777): three looks, own photo, then Instagram, TikTok…
            StoryShareButton(poster: .level(g.level, xp: g.xp)) {
                Label("Share my level", systemImage: "square.and.arrow.up").font(Theme.label(14))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.3)))
            }
        }
        .foregroundStyle(.white)
        .gradientCard(rank.gradient, padding: 18)
    }

    @ViewBuilder private func rankCard(_ rank: GameRank, current: GameRank, g: GameProgress) -> some View {
        let unlocked = rank <= current
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RankMonkey(rank: rank, mood: rank == current ? .fired : .happy, scale: 0.7)
                    .saturation(unlocked ? 1 : 0.2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rank.title).font(Theme.display(24))
                    Text("\(rank.levels) · \(rank.minXP.formatted()) XP").font(Theme.label(12)).opacity(0.85)
                }
                Spacer(minLength: 0)
                Group {
                    if rank == current {
                        Text("YOU").font(Theme.label(12)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(.white))
                    } else if unlocked {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 24, weight: .bold))
                    } else {
                        VStack(alignment: .trailing, spacing: 0) {
                            Image(systemName: "lock.fill").font(.system(size: 18, weight: .bold))
                            Text("\((rank.minXP - g.xp).formatted()) XP").font(Theme.label(11))
                        }
                        .opacity(0.85)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rank.perks) { p in
                    Label(p.title, systemImage: p.symbol).font(.subheadline.weight(.semibold))
                }
            }
            if unlocked, rank.appIcon != nil || rank == .steel {
                perkControls(rank, current: current)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(unlocked ? AnyShapeStyle(rank.gradient) : AnyShapeStyle(Color.white.opacity(0.07))))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white, lineWidth: rank == current ? 3 : 0))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func perkControls(_ rank: GameRank, current: GameRank) -> some View {
        if rank == .steel {
            AccentPicker()
        } else if rank.appIcon != nil {
            AppIconPicker(rank: rank)
        }
    }
}

/// Steel perk: XP bar and level chip colour on Train and the Watch.
private struct AccentPicker: View {
    var body: some View {
        let pref = WatchHomePref.shared
        HStack(spacing: 10) {
            ForEach(GameAccent.allCases) { a in
                Button { pref.setAccent(a) } label: {
                    Circle().fill(a.gradient).frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(.white, lineWidth: pref.accent == a ? 3 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(a.title) colour")
                .accessibilityAddTraits(pref.accent == a ? .isSelected : [])
            }
        }
        .padding(10)
        .background(Capsule().fill(.black.opacity(0.25)))
    }
}

/// Iron, Titan and Legend perk: switch the home screen icon. Also unlocked early by invites (#745).
struct AppIconPicker: View {
    let rank: GameRank
    @State private var current: String?

    var body: some View {
        let name = rank.appIcon
        let on = current == name
        Button {
            let target = on ? nil : name
            UIApplication.shared.setAlternateIconName(target) { error in
                if error == nil { Task { @MainActor in current = target } }
            }
        } label: {
            HStack(spacing: 10) {
                Image("IconPreview-\(rank.title)").resizable().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(on ? "Using \(rank.title) icon" : "Use \(rank.title) icon").font(Theme.label(14))
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .bold))
            }
            .padding(8).padding(.trailing, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .disabled(!UIApplication.shared.supportsAlternateIcons)
        .onAppear { current = UIApplication.shared.alternateIconName }
    }
}

/// Square card shared from the ladder (#242).
struct LevelShareCard: View {
    let level: Int
    let xp: Int

    var body: some View {
        let rank = GameRank.of(level: level)
        VStack(spacing: 10) {
            RankMonkey(rank: rank, mood: .party, scale: 2.2)
            Text(rank.title.uppercased()).font(Theme.label(26)).tracking(3)
            Text("Level \(level)").font(Theme.display(72))
            Text("\(xp.formatted()) XP · MonkeyWorkout").font(Theme.label(20)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .frame(width: 600, height: 600)
        .background(rank.gradient)
    }

    @MainActor static func image(level: Int, xp: Int) -> Image {
        let r = ImageRenderer(content: LevelShareCard(level: level, xp: xp))
        r.scale = 2
        return r.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "star.fill")
    }
}
