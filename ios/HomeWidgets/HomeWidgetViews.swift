import SwiftUI
import WidgetKit

// Home Screen widget faces (#297): three looks (A gradient cards, B Monkey coach, C data tiles) × topics × sizes.
// Plain SwiftUI so the app draws the same faces as live previews in Account → Home Screen widgets.
// Also needs WatchShared/MonkeyFace.swift and GameLadder.swift (Color(hex:), GameRank, MonkeyGear).

private let lime = Color(hex: 0xCCFF3D)
private let tileInk = Color(hex: 0x1B1C21)
private let cell = Color(hex: 0x26272E)

private func heavy(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
private func label(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }

private func tintGradient(_ t: (UInt32, UInt32)) -> LinearGradient {
    LinearGradient(colors: [Color(hex: t.0), Color(hex: t.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum HomeWidgetFormat {
    static func kg(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// "18.4 t" or "850 kg".
    static func volume(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1f t", v / 1000) : "\(Int(v.rounded())) kg"
    }

    /// "Today", "Yesterday", "Mon", or "12 Oct".
    static func day(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Today" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: y) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 99
        let f = DateFormatter()
        f.dateFormat = days < 7 ? "EEE" : "d MMM"
        return f.string(from: date)
    }

    static func todayWeekday(_ now: Date) -> Int { (Calendar.current.component(.weekday, from: now) + 5) % 7 + 1 }
    static let initials = ["M", "T", "W", "T", "F", "S", "S"]
}

/// Coach Monkey's line for the topic.
enum HomeWidgetNudge {
    static func text(_ s: HomeWidgetSnapshot, topic: HomeWidgetTopic) -> String {
        if !s.signedIn { return "Open MonkeyWorkout to set up your week." }
        switch topic {
        case .streak: return s.streakWeeks > 0 ? "\(s.streakWeeks) weeks in a row! Keep the fire going." : "Hit your goal this week to start a streak."
        case .readiness:
            switch s.readiness {
            case "Take it easier"?: return "Low battery today. Lighter sets, more mobility."
            case "Ready to push"?: return "Fully charged! Go for quality reps."
            case .some: return "One marker is off. Train as planned."
            case nil: return "Connect Apple Health and I'll read your recovery."
            }
        case .level: return "\(s.xpPerLevel - s.xpInLevel) XP to level \(s.level + 1). One workout is 50 XP plus 5 a set."
        case .records: return s.records.first.map { "Best \($0.name): \(HomeWidgetFormat.kg($0.kg)) kg. Beat it?" } ?? "Log a heavy set to set your first record."
        case .lastWorkout, .volume: return s.last.map { "Last: \($0.title), \($0.sets) sets. Nice work!" } ?? "Your first workout is waiting."
        case .climbing: return s.climbing.thisWeek > 0 ? "\(s.climbing.thisWeek) climbing days this week. Strong fingers!" : "No climbing yet this week. Log one from Train."
        case .fuel:
            guard let f = s.fuel else { return "Open Fuel to see today's pointers." }
            if let n = f.next { return "\(f.headline). Next: \(n)\(f.nextTime.map { " at \($0)" } ?? "")." }
            return f.glasses < f.glassesTarget ? "\(f.glassesTarget - f.glasses) more glasses of water today." : "Day fuelled. Nice work!"
        case .nextUp, .week, .dashboard:
            if s.weekDone { return "Week cleared! Rest up or add a bonus session." }
            if let n = s.next { return n.day == "Today" ? "Ready to roll! \(n.title), \(n.minutes) min." : "Next: \(n.title) on \(n.day). \(s.toGoal) to go this week." }
            return "\(s.toGoal) more this week to open the chest."
        }
    }

    static func mood(_ s: HomeWidgetSnapshot) -> MonkeyFace.Mood {
        .from(weekDone: s.weekDone, readiness: s.readiness, streakWeeks: s.streakWeeks)
    }

    static func moodTitle(_ s: HomeWidgetSnapshot) -> String {
        switch mood(s) {
        case .party: "Party time!"
        case .fired: "Pumped!"
        case .sleepy: "Sleepy"
        case .happy: "Happy"
        }
    }
}

/// One headline number per topic, used by the gradient and data looks.
struct HomeWidgetStat {
    var kicker: String
    var value: String
    var caption: String
    var detail: String

    init(_ topic: HomeWidgetTopic, _ s: HomeWidgetSnapshot, now: Date) {
        switch topic {
        case .nextUp:
            kicker = "Next up · \(s.next?.day ?? "Week")"
            value = s.next?.title ?? (s.weekDone ? "Week done" : "Rest day")
            caption = s.next.map { "\($0.exercises) exercises · \($0.minutes) min" } ?? "\(s.done) of \(s.target) done"
            detail = s.next != nil ? "Tap to open" : ""
        case .week, .dashboard:
            kicker = "Week \(s.week) of \(s.weeks) · \(s.phase)"
            value = "\(s.done)/\(s.target)"
            caption = s.weekDone ? "Goal reached" : "\(s.toGoal) to goal"
            detail = s.deload ? "Deload week" : ""
        case .streak:
            kicker = "Streak"
            value = "\(s.streakWeeks)"
            caption = s.streakWeeks == 1 ? "week in a row" : "weeks in a row"
            detail = "Best \(s.bestStreakWeeks)"
        case .readiness:
            kicker = "Readiness"
            value = switch s.readiness {
            case "Ready to push"?: "Go"
            case "Take it easier"?: "Easy"
            case .some: "OK"
            case nil: "–"
            }
            caption = s.readiness ?? "Connect Apple Health"
            detail = [s.sleepHours.map { String(format: "Sleep %.1fh", $0) }, s.hrv.map { "HRV \(Int($0))" }]
                .compactMap { $0 }.joined(separator: " · ")
        case .level:
            kicker = "Level · \(s.rank)"
            value = "\(s.level)"
            caption = "\(s.xpInLevel) / \(s.xpPerLevel) XP"
            detail = "\(s.badges) badges"
        case .records:
            kicker = "Top lift"
            value = s.records.first.map { HomeWidgetFormat.kg($0.kg) } ?? "–"
            caption = s.records.first.map { "kg · \($0.name)" } ?? "No records yet"
            detail = s.records.dropFirst().first.map { "\($0.name) \(HomeWidgetFormat.kg($0.kg))" } ?? ""
        case .lastWorkout:
            kicker = "Last workout"
            value = s.last.map { HomeWidgetFormat.day($0.date, now: now) } ?? "–"
            caption = s.last?.title ?? "No workouts yet"
            detail = s.last.map { "\($0.minutes) min · \($0.sets) sets" } ?? ""
        case .volume:
            kicker = "Volume · 4 wk"
            value = HomeWidgetFormat.volume(s.volume4Weeks)
            caption = s.volumeTrend.map { $0 >= 0 ? "+\($0)% this week" : "\($0)% this week" } ?? "Kg lifted"
            detail = ""
        case .climbing:
            kicker = "Climbing"
            value = "\(s.climbing.thisWeek)"
            caption = s.climbing.thisWeek == 1 ? "day this week" : "days this week"
            detail = s.climbing.lastDate.map { "Last \(HomeWidgetFormat.day($0, now: now))\(s.climbing.lastGrade.map { " · \($0)" } ?? "")" } ?? "Log a climb in Train"
        case .fuel:
            kicker = "Fuel · \(s.fuel?.headline ?? "Today")"
            value = s.fuel.map { "\($0.palms)/\($0.palmsTarget)" } ?? "–"
            caption = s.fuel == nil ? "Open Fuel" : "protein palms"
            detail = s.fuel.map { f in "💧 \(f.glasses)/\(f.glassesTarget)\(f.next.map { " · \($0)" } ?? "")" } ?? ""
        }
    }
}

// MARK: - Entry point

/// The face of one Home Screen widget (small, medium or large). Its background is `HomeWidgetBackground`.
struct HomeWidgetFace: View {
    let topic: HomeWidgetTopic
    let look: HomeWidgetLook
    let size: HomeWidgetSize
    let snap: HomeWidgetSnapshot
    var now = Date()

    var body: some View {
        Group {
            switch look {
            case .gradient: GradientFace(topic: topic, size: size, s: snap, now: now)
            case .coach: CoachFace(topic: topic, size: size, s: snap, now: now)
            case .data: DataFace(topic: topic, size: size, s: snap, now: now)
            }
        }
        .foregroundStyle(look == .gradient && topic.inkOnGradient ? Color(hex: 0x2A1A00) : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct HomeWidgetBackground: View {
    let topic: HomeWidgetTopic
    let look: HomeWidgetLook

    var body: some View {
        switch look {
        case .gradient: tintGradient(topic.tint)
        case .coach: LinearGradient(colors: [Color(hex: 0x2E1A6E), Color(hex: 0x4B2FD6), Color(hex: 0x7A3CFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .data: tileInk
        }
    }
}

/// App-side preview with the widget's corner radius and margins.
struct HomeWidgetPreview: View {
    let topic: HomeWidgetTopic
    let look: HomeWidgetLook
    let size: HomeWidgetSize
    let snap: HomeWidgetSnapshot
    /// Width of a small widget; medium and large are 2 × + spacing.
    var unit: CGFloat = 150

    var body: some View {
        let gap = unit * 0.13
        let w = size == .small ? unit : unit * 2 + gap
        let h = size == .large ? unit * 2 + gap : unit
        Group {
            if size == .lock {
                HomeLockFace(topic: topic, family: .rectangular, snap: snap)
                    .padding(10)
                    .frame(width: unit * 1.3, height: unit * 0.5)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.45)))
                    .foregroundStyle(.white)
            } else {
                HomeWidgetFace(topic: topic, look: look, size: size, snap: snap)
                    .padding(unit * 0.1)
                    .frame(width: w, height: h)
                    .background(HomeWidgetBackground(topic: topic, look: look))
                    .clipShape(RoundedRectangle(cornerRadius: unit * 0.15, style: .continuous))
                    .environment(\.homeWidgetScale, unit / 158)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeWidgetScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    /// Previews smaller than a real widget scale their type with it.
    var homeWidgetScale: CGFloat {
        get { self[HomeWidgetScaleKey.self] }
        set { self[HomeWidgetScaleKey.self] = newValue }
    }
}

// MARK: - Shared pieces

private struct WeekStrip: View {
    let s: HomeWidgetSnapshot
    let now: Date
    var height: CGFloat = 26
    var style: Style = .light
    enum Style { case light, data }
    @Environment(\.homeWidgetScale) private var k

    var body: some View {
        let today = HomeWidgetFormat.todayWeekday(now)
        HStack(spacing: 3 * k) {
            ForEach(1...7, id: \.self) { wd in
                let d = s.days.first { $0.weekday == wd }
                ZStack {
                    RoundedRectangle(cornerRadius: 7 * k, style: .continuous).fill(fill(d))
                    if wd == today {
                        RoundedRectangle(cornerRadius: 7 * k, style: .continuous).strokeBorder(.white, lineWidth: 2 * k)
                    }
                    VStack(spacing: 0) {
                        Text(HomeWidgetFormat.initials[wd - 1]).font(label(9 * k))
                        if d?.climb == true { Image(systemName: "figure.climbing").font(.system(size: 6 * k, weight: .bold)) }
                    }
                    .foregroundStyle(d?.done == true ? (style == .data ? Color(hex: 0x063300) : Color(hex: 0x3B3BD0)) : .white)
                }
                .frame(height: height * k)
            }
        }
    }

    private func fill(_ d: HomeWidgetSnapshot.Day?) -> Color {
        if d?.done == true { return style == .data ? lime : .white }
        if d?.missed == true { return Color(hex: 0xFF5F6D) }
        return .white.opacity(d?.planned == true ? 0.32 : 0.14)
    }
}

private struct StartButton: View {
    let s: HomeWidgetSnapshot
    var fill: Color = .white
    @Environment(\.homeWidgetScale) private var k

    var body: some View {
        if let n = s.next {
            Link(destination: HomeWidgetLink.session(n.id)) {
                Label("Start", systemImage: "play.fill")
                    .font(label(12 * k))
                    .foregroundStyle(Color(hex: 0x111111))
                    .padding(.horizontal, 11 * k).padding(.vertical, 6 * k)
                    .background(Capsule().fill(fill))
            }
        }
    }
}

private struct Ring: View {
    let progress: Double
    var color: Color = .white
    var line: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: line)
            Circle().trim(from: 0, to: max(0.001, min(1, progress))).stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct Bars: View {
    let values: [Double]
    var color: Color
    @Environment(\.homeWidgetScale) private var k

    var body: some View {
        let mx = max(values.max() ?? 1, 1)
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: 3 * k) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 3 * k).fill(color.opacity(i == values.count - 1 ? 1 : 0.6))
                        .frame(height: max(3, g.size.height * CGFloat(v / mx)))
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
        }
    }
}

private struct XPBar: View {
    let s: HomeWidgetSnapshot
    @Environment(\.homeWidgetScale) private var k

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(lime).frame(width: g.size.width * CGFloat(s.xpInLevel) / CGFloat(max(1, s.xpPerLevel)))
            }
        }
        .frame(height: 6 * k)
    }
}

// MARK: - A: Gradient cards

private struct GradientFace: View {
    let topic: HomeWidgetTopic
    let size: HomeWidgetSize
    let s: HomeWidgetSnapshot
    let now: Date
    @Environment(\.homeWidgetScale) private var k

    var body: some View {
        let stat = HomeWidgetStat(topic, s, now: now)
        switch size {
        case .small: small(stat)
        case .medium: medium(stat)
        default: if topic == .dashboard { GradientDashboard(s: s, now: now) } else { large(stat) }
        }
    }

    private var icon: some View {
        Image(systemName: topic.symbol).font(.system(size: 14 * k, weight: .bold))
            .frame(width: 28 * k, height: 28 * k)
            .background(RoundedRectangle(cornerRadius: 8 * k, style: .continuous).fill(.white.opacity(0.25)))
    }

    private func small(_ st: HomeWidgetStat) -> some View {
        VStack(alignment: .leading, spacing: 2 * k) {
            HStack(alignment: .top) {
                icon
                Spacer(minLength: 0)
                if topic == .week {
                    Ring(progress: Double(s.done) / Double(max(1, s.target)), line: 5 * k).frame(width: 30 * k, height: 30 * k)
                }
            }
            Spacer(minLength: 0)
            Text(st.kicker).font(label(8 * k)).textCase(.uppercase).opacity(0.85).lineLimit(1)
            Text(st.value).font(heavy((st.value.count > 6 ? 20 : 34) * k)).lineLimit(1).minimumScaleFactor(0.5)
            Text(st.caption).font(label(11 * k)).lineLimit(2).minimumScaleFactor(0.8)
        }
        .widgetURL(HomeWidgetLink.url(for: topic, snap: s))
    }

    private func medium(_ st: HomeWidgetStat) -> some View {
        VStack(alignment: .leading, spacing: 6 * k) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1 * k) {
                    Text(st.kicker).font(label(9 * k)).textCase(.uppercase).opacity(0.85).lineLimit(1)
                    Text(st.value).font(heavy(22 * k)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(st.caption).font(label(11 * k)).opacity(0.9).lineLimit(1)
                }
                Spacer(minLength: 4)
                icon
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8 * k) {
                detailRow
                if topic == .nextUp || topic == .week { StartButton(s: s) }
            }
        }
        .widgetURL(HomeWidgetLink.url(for: topic, snap: s))
    }

    @ViewBuilder private var detailRow: some View {
        switch topic {
        case .volume: Bars(values: s.volumeWeeks, color: .white).frame(height: 28 * k)
        case .records:
            HStack(spacing: 6 * k) {
                ForEach(s.records.prefix(3), id: \.self) { r in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.name).font(label(8 * k)).lineLimit(1).opacity(0.85)
                        Text("\(HomeWidgetFormat.kg(r.kg)) kg").font(heavy(13 * k)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .level: XPBar(s: s)
        default: WeekStrip(s: s, now: now)
        }
    }

    private func large(_ st: HomeWidgetStat) -> some View {
        VStack(alignment: .leading, spacing: 8 * k) {
            medium(st).frame(height: 120 * k)
            Divider().overlay(.white.opacity(0.4))
            Text(HomeWidgetNudge.text(s, topic: topic)).font(label(12 * k)).lineLimit(2)
            if topic == .records {
                ForEach(s.records.prefix(4).dropFirst(3), id: \.self) { r in
                    Text("\(r.name) \(HomeWidgetFormat.kg(r.kg)) kg").font(label(11 * k))
                }
            }
            Spacer(minLength: 0)
            NextRow(s: s, fill: .white.opacity(0.2))
        }
    }
}

private struct NextRow: View {
    let s: HomeWidgetSnapshot
    var fill: Color
    var button: Color = .white
    @Environment(\.homeWidgetScale) private var k

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Next up\(s.next.map { " · \($0.day)" } ?? "")").font(label(8 * k)).textCase(.uppercase).opacity(0.85)
                Text(s.next?.title ?? (s.weekDone ? "Week done" : "Nothing planned")).font(heavy(14 * k)).lineLimit(1)
                if let n = s.next { Text("\(n.minutes) min").font(label(10 * k)).opacity(0.85) }
            }
            Spacer(minLength: 4)
            StartButton(s: s, fill: button)
        }
        .padding(8 * k)
        .background(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(fill))
    }
}

private struct GradientDashboard: View {
    let s: HomeWidgetSnapshot
    let now: Date
    @Environment(\.homeWidgetScale) private var k

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * k) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1 * k) {
                    Text("Week \(s.week) of \(s.weeks) · \(s.phase)").font(label(9 * k)).textCase(.uppercase).opacity(0.85)
                    Text("\(s.done) of \(s.target) done").font(heavy(21 * k))
                }
                Spacer()
                ZStack {
                    Ring(progress: Double(s.done) / Double(max(1, s.target)), color: lime, line: 5 * k)
                    Text(readinessShort).font(label(9 * k))
                }
                .frame(width: 42 * k, height: 42 * k)
            }
            WeekStrip(s: s, now: now)
            Spacer(minLength: 0)
            NextRow(s: s, fill: .white.opacity(0.2))
            Spacer(minLength: 0)
            HStack(spacing: 6 * k) {
                chip("Streak", "\(s.streakWeeks) wk", "flame.fill")
                chip("Top lift", s.records.first.map { "\(HomeWidgetFormat.kg($0.kg)) kg" } ?? "–", "trophy.fill")
            }
        }
        .widgetURL(HomeWidgetLink.tab("train"))
    }

    private var readinessShort: String {
        switch s.readiness {
        case "Ready to push"?: "GO"
        case "Take it easier"?: "EASY"
        case .some: "OK"
        case nil: "\(s.done)/\(s.target)"
        }
    }

    private func chip(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(label(8 * k)).textCase(.uppercase).opacity(0.85)
            Label(value, systemImage: symbol).font(heavy(14 * k)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7 * k)
        .background(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(.white.opacity(0.2)))
    }
}

// MARK: - B: Monkey coach

private struct CoachFace: View {
    let topic: HomeWidgetTopic
    let size: HomeWidgetSize
    let s: HomeWidgetSnapshot
    let now: Date
    @Environment(\.homeWidgetScale) private var k

    private var rank: GameRank { .of(level: s.level) }
    private var monkey: some View { MonkeyFace(mood: HomeWidgetNudge.mood(s), scale: 0.8 * k, gear: rank.gear) }

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        default: large
        }
    }

    private var levelChip: some View {
        Text("LV \(s.level)").font(label(10 * k)).foregroundStyle(Color(hex: 0x111111))
            .padding(.horizontal, 6 * k).padding(.vertical, 2 * k)
            .background(Capsule().fill(lime))
    }

    private func bubble(_ text: String, lines: Int) -> some View {
        Text(text).font(label(11 * k)).foregroundStyle(Color(hex: 0x222222)).lineLimit(lines).minimumScaleFactor(0.85)
            .padding(.horizontal, 8 * k).padding(.vertical, 6 * k)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10 * k, style: .continuous).fill(.white))
    }

    @ViewBuilder private var small: some View {
        if topic == .level {
            VStack(alignment: .leading, spacing: 3 * k) {
                HStack {
                    levelChip
                    Spacer()
                    Image(systemName: "shippingbox.fill").font(.system(size: 16 * k)).foregroundStyle(Color(hex: 0xFFC371))
                }
                Spacer(minLength: 0)
                Text(s.rank).font(heavy(20 * k))
                Text("\(s.xpInLevel) / \(s.xpPerLevel) XP").font(label(10 * k)).opacity(0.9)
                XPBar(s: s)
                Text(s.toGoal == 0 ? "Weekly chest open!" : "Chest in \(s.toGoal) session\(s.toGoal == 1 ? "" : "s")").font(label(9 * k)).opacity(0.85)
            }
            .widgetURL(HomeWidgetLink.tab("level"))
        } else {
            let st = HomeWidgetStat(topic, s, now: now)
            VStack(spacing: 3 * k) {
                monkey.frame(height: 56 * k)
                Text(topic == .nextUp || topic == .week ? HomeWidgetNudge.moodTitle(s) : st.value).font(heavy(18 * k)).lineLimit(1).minimumScaleFactor(0.6)
                Text(topic == .nextUp ? (s.next.map { "\($0.title) · \($0.day)" } ?? st.caption) : st.caption)
                    .font(label(10 * k)).opacity(0.9).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(HomeWidgetLink.url(for: topic, snap: s))
        }
    }

    private var medium: some View {
        HStack(spacing: 10 * k) {
            monkey.frame(width: 60 * k)
            VStack(alignment: .leading, spacing: 6 * k) {
                bubble(HomeWidgetNudge.text(s, topic: topic), lines: 3)
                HStack {
                    Text("LV \(s.level) · \(s.xpInLevel) XP").font(label(10 * k)).foregroundStyle(Color(hex: 0x111111))
                        .padding(.horizontal, 7 * k).padding(.vertical, 3 * k).background(Capsule().fill(lime))
                    Spacer(minLength: 4)
                    StartButton(s: s, fill: lime)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .widgetURL(HomeWidgetLink.url(for: topic, snap: s))
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8 * k) {
            HStack(spacing: 10 * k) {
                monkey.frame(width: 60 * k, height: 56 * k)
                VStack(alignment: .leading, spacing: 3 * k) {
                    Text("\(s.rank) · LV \(s.level)").font(heavy(19 * k)).lineLimit(1)
                    XPBar(s: s)
                    Text(toNextRank)
                        .font(label(10 * k)).opacity(0.85)
                }
            }
            bubble(HomeWidgetNudge.text(s, topic: topic == .dashboard ? .week : topic), lines: 2)
            HStack(spacing: 6 * k) {
                tile("flame.fill", "\(s.streakWeeks)", "streak")
                tile("medal.fill", "\(s.badges)", "badges")
                tile("dumbbell.fill", "\(s.workouts)", "workouts")
            }
            Spacer(minLength: 0)
            NextRow(s: s, fill: .black.opacity(0.25), button: lime)
        }
        .widgetURL(HomeWidgetLink.url(for: topic, snap: s))
    }

    private var toNextRank: String {
        guard let next = rank.next else { return "Top rank reached" }
        let xp = (s.level - 1) * s.xpPerLevel + s.xpInLevel
        return "\(max(0, next.minXP - xp)) XP to \(next.title)"
    }

    private func tile(_ symbol: String, _ value: String, _ caption: String) -> some View {
        VStack(spacing: 0) {
            Label(value, systemImage: symbol).font(heavy(15 * k)).lineLimit(1)
            Text(caption).font(label(9 * k)).opacity(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6 * k)
        .background(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(.white.opacity(0.14)))
    }
}

// MARK: - C: Data tiles

private struct DataFace: View {
    let topic: HomeWidgetTopic
    let size: HomeWidgetSize
    let s: HomeWidgetSnapshot
    let now: Date
    @Environment(\.homeWidgetScale) private var k

    static func accent(_ t: HomeWidgetTopic) -> Color {
        switch t {
        case .readiness, .week, .dashboard, .nextUp: lime
        case .volume, .lastWorkout: Color(hex: 0x57B8FF)
        case .streak, .records, .climbing, .fuel: Color(hex: 0xFF9A3C)
        case .level: Color(hex: 0xFF5F9E)
        }
    }

    var body: some View {
        switch size {
        case .small: small
        case .medium: grid(rows: 2)
        default: large
        }
    }

    private var small: some View {
        let st = HomeWidgetStat(topic, s, now: now)
        let c = Self.accent(topic)
        return VStack(alignment: .leading, spacing: 3 * k) {
            Text(st.kicker).font(label(8 * k)).textCase(.uppercase).foregroundStyle(c).lineLimit(1)
            Spacer(minLength: 0)
            Text(st.value).font(heavy((st.value.count > 6 ? 20 : 32) * k)).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.5).monospacedDigit()
            if topic == .volume { Bars(values: s.volumeWeeks, color: c).frame(height: 20 * k) }
            Text(st.caption).font(label(10 * k)).lineLimit(2).minimumScaleFactor(0.8)
            if !st.detail.isEmpty { Text(st.detail).font(label(9 * k)).foregroundStyle(.white.opacity(0.65)).lineLimit(1) }
        }
        .widgetURL(HomeWidgetLink.url(for: topic, snap: s))
    }

    /// The picked topic first, then the most useful others.
    private var topics: [HomeWidgetTopic] {
        let base: [HomeWidgetTopic] = [.week, .streak, .nextUp, .lastWorkout, .readiness, .records, .volume, .level]
        let first = topic == .dashboard ? HomeWidgetTopic.week : topic
        return [first] + base.filter { $0 != first }
    }

    private func grid(rows: Int) -> some View {
        let ts = Array(topics.prefix(rows * 2))
        return VStack(spacing: 6 * k) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 6 * k) {
                    ForEach(ts[(r * 2)..<(r * 2 + 2)], id: \.self) { t in dataCell(t) }
                }
            }
        }
        .widgetURL(HomeWidgetLink.url(for: topic, snap: s))
    }

    private func dataCell(_ t: HomeWidgetTopic) -> some View {
        let wide = t == .nextUp || t == .lastWorkout
        return VStack(alignment: .leading, spacing: 1 * k) {
            Text(cellTitle(t)).font(label(8 * k)).textCase(.uppercase).foregroundStyle(Self.accent(t)).lineLimit(1)
            Text(cellValue(t)).font(heavy((wide ? 12 : 17) * k)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(wide ? Color.white : Self.accent(t))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(7 * k)
        .background(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(cell))
    }

    private func cellTitle(_ t: HomeWidgetTopic) -> String {
        switch t {
        case .nextUp: "Next"
        case .lastWorkout: "Last"
        default: t.title
        }
    }

    private func cellValue(_ t: HomeWidgetTopic) -> String {
        let st = HomeWidgetStat(t, s, now: now)
        switch t {
        case .nextUp: return s.next.map { "\($0.title) · \($0.minutes)m" } ?? st.value
        case .lastWorkout: return "\(st.caption) · \(st.value)"
        case .streak: return "\(s.streakWeeks) wk"
        default: return st.value
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 7 * k) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(s.week) / \(s.weeks)").font(heavy(18 * k))
                Spacer()
                Text(s.readiness ?? "\(s.done)/\(s.target) done").font(label(10 * k)).foregroundStyle(lime).lineLimit(1)
            }
            WeekStrip(s: s, now: now, style: .data)
            HStack(spacing: 6 * k) {
                VStack(alignment: .leading, spacing: 2 * k) {
                    Text("Records").font(label(8 * k)).textCase(.uppercase).foregroundStyle(Self.accent(.records))
                    ForEach(s.records.prefix(3), id: \.self) { r in
                        HStack(spacing: 3) {
                            Text(r.name).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(HomeWidgetFormat.kg(r.kg)).font(heavy(11 * k))
                        }
                        .font(label(10 * k))
                    }
                    if s.records.isEmpty { Text("None yet").font(label(10 * k)).opacity(0.6) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(7 * k).background(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(cell))
                VStack(alignment: .leading, spacing: 2 * k) {
                    Text(topic == .climbing ? "Climbing" : "Volume").font(label(8 * k)).textCase(.uppercase).foregroundStyle(Self.accent(topic == .climbing ? .climbing : .volume))
                    if topic == .climbing {
                        Text(HomeWidgetStat(.climbing, s, now: now).value + " days").font(heavy(16 * k)).foregroundStyle(Self.accent(.climbing))
                        Text(HomeWidgetStat(.climbing, s, now: now).detail).font(label(9 * k)).lineLimit(2)
                    } else {
                        Bars(values: s.volumeWeeks, color: Color(hex: 0x57B8FF)).frame(maxHeight: .infinity)
                        Text("\(HomeWidgetFormat.volume(s.volume4Weeks))\(s.volumeTrend.map { $0 >= 0 ? " · +\($0)%" : " · \($0)%" } ?? "")").font(label(9 * k)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(7 * k).background(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(cell))
            }
            .frame(maxHeight: .infinity)
            NextRow(s: s, fill: cell, button: lime)
        }
        .widgetURL(HomeWidgetLink.url(for: topic, snap: s))
    }
}

// MARK: - Lock Screen

/// Lock Screen faces (accessory families): tinted by the system, so no colours.
struct HomeLockFace: View {
    enum Family { case circular, rectangular, inline }
    let topic: HomeWidgetTopic
    let family: Family
    let snap: HomeWidgetSnapshot
    var now = Date()

    var body: some View {
        let s = snap
        let st = HomeWidgetStat(topic, s, now: now)
        switch family {
        case .inline:
            Label(inline(st), systemImage: topic.symbol)
        case .circular:
            switch topic {
            case .week, .dashboard, .nextUp:
                Gauge(value: Double(min(s.done, max(1, s.target))), in: 0...Double(max(1, s.target))) {
                    Image(systemName: "dumbbell.fill")
                } currentValueLabel: { Text("\(s.done)/\(s.target)").font(heavy(14)) }
                .gaugeStyle(.accessoryCircularCapacity)
            case .level:
                Gauge(value: Double(s.xpInLevel), in: 0...Double(max(1, s.xpPerLevel))) {
                    Text("LV")
                } currentValueLabel: { Text("\(s.level)").font(heavy(16)) }
                .gaugeStyle(.accessoryCircular)
            default:
                ZStack {
                    Circle().fill(.white.opacity(0.15))
                    VStack(spacing: 0) {
                        Image(systemName: topic.symbol).font(.system(size: 12, weight: .bold))
                        Text(st.value).font(heavy(15)).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .padding(4)
                }
            }
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(st.kicker, systemImage: topic.symbol).font(label(11)).lineLimit(1)
                Text(topic == .nextUp ? st.value : "\(st.value) \(st.caption)").font(heavy(15)).lineLimit(1).minimumScaleFactor(0.7)
                Text(topic == .nextUp ? st.caption : st.detail.isEmpty ? " " : st.detail).font(label(11)).lineLimit(1).opacity(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inline(_ st: HomeWidgetStat) -> String {
        switch topic {
        case .nextUp: snap.next.map { "\($0.title) · \($0.day)" } ?? st.caption
        case .week, .dashboard: "\(snap.done)/\(snap.target) this week"
        case .streak: "\(snap.streakWeeks) week streak"
        case .level: "LV \(snap.level) · \(snap.xpInLevel) XP"
        default: "\(st.value) \(st.caption)"
        }
    }
}

// MARK: - Sample data

extension HomeWidgetSnapshot {
    /// Widget gallery placeholder and DEBUG demo screens.
    static var sample: HomeWidgetSnapshot {
        var s = HomeWidgetSnapshot()
        s.signedIn = true
        s.week = 3; s.weeks = 4; s.phase = "Build"
        s.days = (1...7).map { wd in Day(weekday: wd, planned: [1, 2, 3, 5].contains(wd), done: [1, 2].contains(wd), missed: false, climb: wd == 6) }
        s.done = 2; s.target = 3
        s.next = Next(id: "demo", title: "Push · Upper A", day: "Today", minutes: 52, exercises: 6, tint: 0x3B6CFF)
        s.streakWeeks = 6; s.bestStreakWeeks = 9
        s.readiness = "Ready to push"; s.sleepHours = 7.7; s.hrv = 62; s.restingHR = 52
        s.level = 7; s.rank = "Regular"; s.xpInLevel = 340; s.nextRank = "Iron"; s.badges = 12; s.workouts = 41
        s.records = [Lift(name: "Squat", kg: 120), Lift(name: "Bench press", kg: 100), Lift(name: "Deadlift", kg: 150)]
        s.last = Last(title: "Legs · Lower B", date: Date().addingTimeInterval(-86_400), minutes: 58, sets: 22, volumeKg: 6_400)
        s.volumeWeeks = [3_900, 4_600, 4_300, 5_600]
        s.climbing = Climbing(thisWeek: 2, lastDate: Date().addingTimeInterval(-2 * 86_400), lastKind: "Boulder", lastGrade: "6B+")
        s.fuel = Fueling(headline: "Big day", palms: 4, palmsTarget: 7, glasses: 6, glassesTarget: 12, next: "Recovery meal", nextTime: "18:30")
        return s
    }
}
