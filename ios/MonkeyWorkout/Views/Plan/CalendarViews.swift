import SwiftUI
import WorkoutEngine

// Training calendar (#68): coming weeks, "can't train" dates, travel periods.

extension AwayKind {
    var label: String { self == .off ? "Can't train" : "Travelling" }
    var symbol: String { self == .off ? "nosign" : "airplane" }
    var gradient: LinearGradient { self == .off ? WorkoutEngine.Category.power.gradient : WorkoutEngine.Category.cardio.gradient }
}

extension TravelSetup {
    var symbol: String {
        switch self {
        case .hotelGym: "building.2.fill"
        case .dumbbells: "dumbbell.fill"
        case .bodyweight: "figure.strengthtraining.functional"
        case .bands: "arrow.left.and.right"
        case .fullGym: "magnifyingglass"
        }
    }

    var category: WorkoutEngine.Category {
        switch self {
        case .hotelGym: .strength
        case .dumbbells: .warmup
        case .bodyweight: .mobility
        case .bands: .cardio
        case .fullGym: .stretch
        }
    }
}

private let dayFormat: Date.FormatStyle = .dateTime.weekday(.abbreviated).day().month(.abbreviated)

/// Coming weeks with dated sessions, climbing days and away periods.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    /// Regular = iPad (#824): two weeks per row in a wider column.
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var editing: AwayPeriod?
    @State private var editingIsNew = false
    @State private var selected: DaySelection?
    @State private var findingGym = false

    var body: some View {
        let weeks = model.calendarWeeks()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ContentTitle(title: "Calendar")
                hero(weeks)
                // Training programme (#255): its phases over the coming weeks.
                if let a = model.activeProgramme, !a.paused, let p = a.programme {
                    Text("\(p.name) · week \(model.programmeWeek ?? 1) of \(p.weeks)").eyebrow()
                    ProgrammePhaseStrip(programme: p, week: model.programmeWeek)
                }
                HStack(spacing: 10) {
                    ForEach(AwayKind.allCases) { kind in
                        Button { start(kind) } label: {
                            Label(kind.label, systemImage: kind.symbol)
                                .font(Theme.label(15))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(kind.gradient))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Away periods live in their week cards as tappable strips; no separate list.
                if horizontalSize == .regular {
                    // iPad (#824): two weeks side by side instead of one narrow column down the middle.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)],
                              alignment: .leading, spacing: 16) {
                        ForEach(Array(weeks.enumerated()), id: \.element.id) { i, w in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(header(i, w)).eyebrow().padding(.top, 4)
                                WeekCalendarCard(week: w, current: i == 0, onAway: { edit($0) }) { wd in selected = DaySelection(week: w, weekday: wd, current: i == 0) }
                            }
                        }
                    }
                } else {
                    ForEach(Array(weeks.enumerated()), id: \.element.id) { i, w in
                        Text(header(i, w)).eyebrow().padding(.top, 4)
                        WeekCalendarCard(week: w, current: i == 0, onAway: { edit($0) }) { wd in selected = DaySelection(week: w, weekday: wd, current: i == 0) }
                    }
                }
                // Periods starting after the last week shown keep a way in.
                let later = laterAway(weeks)
                if !later.isEmpty {
                    Text("Later").eyebrow().padding(.top, 4)
                    ForEach(later) { a in AwayStrip(period: a) { edit(a) } }
                }
                Text("The 4-week cycle moves on one week each Monday here. Days off move sessions to free days that week; with too few free days you get fewer, fuller sessions. Travel days are rebuilt for the equipment there.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .modifier(CalendarColumn(maxWidth: horizontalSize == .regular ? 1100 : Theme.readableWidth))
        .background(Theme.bg.ignoresSafeArea())
        // Title in the content (#539), not under the toolbar's glass buttons.
        .titleInContent("Calendar")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { findingGym = true } label: { Image(systemName: "location.magnifyingglass") }
                    .accessibilityLabel("Find a gym")
            }
        }
        .sheet(isPresented: $findingGym) { GymFinderView() }
        .sheet(item: $editing) { a in
            AwayEditorView(initial: a, isNew: editingIsNew) { saved in
                if let saved { model.saveAway(saved) } else { model.deleteAway(a.id) }
                editing = nil
            }
        }
        .sheet(item: $selected) { s in
            DaySheet(selection: s) { kind, key in
                selected = nil
                start(kind, day: key)
            } onEdit: { a in
                selected = nil
                edit(a)
            }
        }
    }

    private func hero(_ weeks: [PlanCalendar.Week]) -> some View {
        let next4 = weeks.prefix(4)
        // Skipped sessions (#784) aren't coming any more.
        let count = next4.enumerated().reduce(0) { n, e in
            n + e.element.plan.sessions.filter { !model.doneIds.contains($0.id) && !model.isSkipped($0.id, in: e.element, current: e.offset == 0) }.count
        }
        let adapted = next4.filter(\.adapted).count
        return HStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.system(size: 26, weight: .bold))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Next 4 weeks").font(Theme.display(22))
                Text(adapted == 0 ? "Regular plan" : "\(adapted) week\(adapted == 1 ? "" : "s") adapted")
                    .font(.footnote.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(count)").font(Theme.display(44)).monospacedDigit()
                Text("SESSIONS").font(Theme.label(9)).tracking(1.2).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
    }

    private func header(_ i: Int, _ w: PlanCalendar.Week) -> String {
        let phase = Generator.phaseName(w.plan.week)
        switch i {
        case 0: return "This week · \(phase)"
        case 1: return "Next week · \(phase)"
        default: return "\(w.start.formatted(.dateTime.day().month(.abbreviated))) · \(phase)"
        }
    }

    private func laterAway(_ weeks: [PlanCalendar.Week]) -> [AwayPeriod] {
        guard let last = weeks.last?.days.last else { return model.upcomingAway }
        return model.upcomingAway.filter { $0.start > last }
    }

    private func start(_ kind: AwayKind, day: String? = nil) {
        let today = day ?? PlanCalendar.key(Date(), model.planCalendar)
        editingIsNew = true
        editing = AwayPeriod(kind: kind, start: today, end: today, setup: kind == .travel ? .hotelGym : nil)
    }

    private func edit(_ a: AwayPeriod) {
        editingIsNew = false
        editing = a
    }
}

/// `readableWidth()` with its own cap (#824): the iPad calendar's two-week rows get a wider column.
private struct CalendarColumn: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.horizontal, max(0, (width - maxWidth) / 2))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

struct DaySelection: Identifiable {
    let week: PlanCalendar.Week
    let weekday: Int
    let current: Bool
    var id: String { week.days[weekday - 1] }
}

/// One week: seven day tiles plus what changed.
struct WeekCalendarCard: View {
    let week: PlanCalendar.Week
    let current: Bool
    let onAway: (AwayPeriod) -> Void
    let onDay: (Int) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.planCalendar
        let today = PlanCalendar.key(Date(), cal)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(range(cal)).font(.system(.subheadline, design: .rounded).weight(.heavy))
                Spacer()
                Text(summary).font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 4) {
                ForEach(WeekSchedule.weekdays, id: \.self) { wd in
                    Button { onDay(wd) } label: { tile(wd, today: today, cal: cal) }
                        .buttonStyle(.plain)
                }
            }
            ForEach(periods) { p in AwayStrip(period: p) { onAway(p) } }
            if week.dropped > 0 {
                Text("\(week.dropped) session\(week.dropped == 1 ? "" : "s") skipped: not enough free days")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 12)
    }

    /// Away periods touching this week, earliest first.
    private var periods: [AwayPeriod] {
        Dictionary(grouping: Array(week.off.values) + Array(week.travel.values), by: \.id)
            .compactMap { $0.value.first }
            .sorted { $0.start < $1.start }
    }

    /// The week's sessions not skipped (#784): skipped ones leave a rest day behind.
    private var planned: [Session] { week.plan.sessions.filter { !model.isSkipped($0.id, in: week, current: current) } }

    private var summary: String {
        let n = planned.count
        let trips = planned.filter { $0.weekday.map { week.travel[$0] != nil } ?? false }.count
        return "\(n) session\(n == 1 ? "" : "s")" + (trips > 0 ? " · \(trips) away" : "")
    }

    private func range(_ cal: Calendar) -> String {
        let end = cal.date(byAdding: .day, value: 6, to: week.start)!
        return "\(week.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    @ViewBuilder
    private func tile(_ wd: Int, today: String, cal: Calendar) -> some View {
        let key = week.days[wd - 1]
        let session = planned.first { $0.weekday == wd }
        // A skipped workout is gone (#854): a plain rest day, no "Skipped" tag.
        let done = session.map { current && model.doneIds.contains($0.id) } ?? false
        let off = week.off[wd] != nil
        let travel = week.travel[wd] != nil
        let climb = week.climbing.contains(wd)
        let past = key < today
        // An earlier day of this week with its session not done (#266).
        let missed = current && !done && session.map { s in model.missedSessions.contains { $0.id == s.id } } == true
        let day = week.date(wd, cal).map { cal.component(.day, from: $0) } ?? 0
        let count = planned.filter { $0.weekday == wd }.count
        // Other sports' days (#416), in season on that date.
        let sport = model.sportDays(on: week.date(wd, cal) ?? Date()).first { $0.weekday == wd }?.sport
        // A dated sport day or trip (#474) shows in the sport's colours.
        let trip = week.trips[wd]
        let tag: String? = session.map { ($0.hiit != nil ? "HIIT" : short($0.focus)) + (count > 1 ? " +\(count - 1)" : "") } ?? (off ? "Off" : trip.map { $0.sport.short } ?? (climb ? "Climb" : sport?.short))
        let fill = missed ? AnyShapeStyle(MissedStyle.gradient)
            : trip.map { AnyShapeStyle($0.sport.gradient) } ?? tileFill(session: session != nil, off: off, travel: travel, climb: climb)
        VStack(spacing: 1) {
            Text(WeekSchedule.shortName(wd).uppercased()).font(Theme.label(9))
            Text("\(day)").font(Theme.display(17)).monospacedDigit()
            if done {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .black))
            } else if missed {
                Text("Missed").font(.system(size: 9, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            } else if let tag {
                Text(tag).font(.system(size: 9, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(" ").font(.system(size: 9))
            }
        }
        .foregroundStyle(climb && session == nil && !off ? Theme.ink : .white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.lime, lineWidth: key == today ? 2 : 0))
        .opacity(past && !done && !missed ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(wd, session: session, done: done, off: off, travel: travel, climb: climb) + (missed ? ", missed" : ""))
    }

    private func tileFill(session: Bool, off: Bool, travel: Bool, climb: Bool) -> AnyShapeStyle {
        if session { return AnyShapeStyle(travel ? WorkoutEngine.Category.cardio.gradient : WorkoutEngine.Category.strength.gradient) }
        if off { return AnyShapeStyle(WorkoutEngine.Category.power.color.opacity(0.4)) }
        if travel { return AnyShapeStyle(WorkoutEngine.Category.cardio.color.opacity(0.35)) }
        if climb { return AnyShapeStyle(WorkoutEngine.Category.warmup.gradient) }
        return AnyShapeStyle(Color.white.opacity(0.05))
    }

    private func short(_ f: Focus) -> String {
        switch f {
        case .fullLower: "Lower"
        case .fullUpper: "Upper"
        case .fullPower: "Power"
        case .upper: "Upper"
        case .lower: "Lower"
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .conditioning: "Cond."
        case .chestTri: "Chest"
        case .backBi: "Back"
        case .shouldersArms: "Arms"
        case .chestBack: "C & B"
        case .posterior: "Glutes"
        }
    }

    private func accessibility(_ wd: Int, session: Session?, done: Bool, off: Bool, travel: Bool, climb: Bool) -> String {
        var parts = [WeekSchedule.name(wd)]
        if let s = session { parts.append(s.focus.label + (done ? ", done" : "")) }
        if off { parts.append("can't train") }
        if travel { parts.append("travelling") }
        if climb { parts.append("climbing") }
        return parts.joined(separator: ", ")
    }
}

/// Upcoming away period as a vivid row.
struct AwayRow: View {
    let period: AwayPeriod
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.planCalendar
        HStack(spacing: 12) {
            Image(systemName: period.kind == .travel ? (period.setup ?? .hotelGym).symbol : period.kind.symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(period.title).font(.system(size: 16, weight: .heavy, design: .rounded)).lineLimit(1)
                Text(dates(cal)).font(.caption.weight(.semibold)).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(period.kind.gradient))
    }

    private func dates(_ cal: Calendar) -> String {
        guard let a = PlanCalendar.date(period.start, cal), let b = PlanCalendar.date(period.end, cal) else { return "" }
        let days = (cal.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        return a == b ? a.formatted(dayFormat) : "\(a.formatted(dayFormat)) – \(b.formatted(dayFormat)) · \(days) days"
    }
}

/// Away period as a slim gradient strip in a week card; tap to edit.
struct AwayStrip: View {
    let period: AwayPeriod
    let onTap: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let text = ([period.title] + [dates(model.planCalendar)].compactMap { $0 }).joined(separator: " · ")
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: period.kind == .travel ? (period.setup ?? .hotelGym).symbol : period.kind.symbol)
                    .font(.caption.weight(.heavy))
                Text(text).font(.system(.caption, design: .rounded).weight(.heavy)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.bold()).opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(period.kind.gradient))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(text)")
    }

    /// "23 Nov" or "1–8 Nov" / "28 Oct – 3 Nov".
    private func dates(_ cal: Calendar) -> String? {
        guard let a = PlanCalendar.date(period.start, cal), let b = PlanCalendar.date(period.end, cal) else { return nil }
        let short: Date.FormatStyle = .dateTime.day().month(.abbreviated)
        guard a < b else { return a.formatted(short) }
        // The locale's own range, "Oct 29 – 30" / "29–30 Oct", never "29–Oct 30" (#823).
        return (a..<b).formatted(.interval.day().month(.abbreviated))
    }
}

/// What's on a day; quick "can't train" / travel from there.
struct DaySheet: View {
    let selection: DaySelection
    let onAdd: (AwayKind, String) -> Void
    let onEdit: (AwayPeriod) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var moving: Session?
    @State private var adding = false
    @State private var insertsBefore = 0
    @State private var logging: Session?
    /// An earlier day of this week is logged, never planned (#537, #818): the past day's "What did you do?" (#800),
    /// then the workout or sport picked there.
    @State private var loggingPast = false
    @State private var pastPick: PastDayPick?
    @State private var pastWorkout: Session?
    @State private var pastSport: SportLog?
    /// Plan sport (#474): a new sport on this day, or the dated sport day / trip being edited.
    @State private var planningSport = false
    @State private var editingTrip: SportTrip?
    /// Profile when Plan sport opened: the day sheet closes after a change (its week is a snapshot).
    @State private var profileBefore: Profile?
    /// Opens sized to its content (#264): the medium detent cut off Can't train / Travelling.
    @State private var contentHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 0
    @State private var detent: PresentationDetent = .large

    var body: some View {
        let cal = model.planCalendar
        let wd = selection.weekday
        let key = selection.week.days[wd - 1]
        let all = selection.week.plan.sessions.filter { $0.weekday == wd }
        // Skipped workouts are gone (#849), as on Train.
        let sessions = all.filter { !model.isSkipped($0.id, in: selection.week, current: selection.current) }
        let away = selection.week.off[wd] ?? selection.week.travel[wd]
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text((selection.week.date(wd, cal) ?? Date()).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(Theme.display(28))
                    // Ask Coach about this day (#412 C).
                    CoachSpark(question: sessions.isEmpty ? "What could I do this day?" : "Help me plan this day", focus: CoachFocus(
                        screen: "calendar",
                        title: (selection.week.date(wd, cal) ?? Date()).formatted(.dateTime.weekday(.wide).day().month(.wide)),
                        detail: sessions.isEmpty ? (away == nil ? "rest day" : "away") : "planned: " + sessions.map(\.displayTitle).joined(separator: ", ")))
                    if let away {
                        Button { onEdit(away) } label: { AwayRow(period: away) }.buttonStyle(.plain)
                    }
                    if let trip = selection.week.trips[wd] {
                        Button {
                            profileBefore = model.profile
                            editingTrip = trip
                        } label: { SportTripRow(trip: trip) }.buttonStyle(.plain)
                    }
                    if selection.week.climbing.contains(wd) {
                        Label("Climbing day", systemImage: "figure.climbing")
                            .font(Theme.label(15)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Capsule().fill(WorkoutEngine.Category.warmup.gradient))
                    }
                    ForEach(model.sportDays(on: selection.week.date(wd, cal) ?? Date()).filter { $0.weekday == wd && selection.week.trips[wd] == nil }, id: \.sport) { sd in
                        Label("\(sd.sport.label) day", systemImage: sd.sport.symbol)
                            .font(Theme.label(15)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Capsule().fill(sd.sport.gradient))
                    }
                    ForEach(sessions) { session in
                        let done = selection.current && model.doneIds.contains(session.id)
                        let missed = selection.current && model.missedSessions.contains { $0.id == session.id }
                        if missed {
                            // Missed (#266): log it, mark it done, do it today or skip.
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Missed").font(Theme.label(12)).tracking(1.4).textCase(.uppercase).foregroundStyle(.white.opacity(0.9))
                                MissedActionsRow(session: session) { logging = session }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MissedStyle.gradient))
                        }
                        SessionPreview(session: session, current: selection.current, done: done, canMove: selection.current && !done && !missed,
                                       canSkip: !done && model.state.activeWorkout?.sessionId != session.id,
                                       stopTitle: stopWeekdayTitle(model, session, weekday: wd, in: selection.current ? nil : selection.week)) {
                            moving = session
                        } onSkip: {
                            skipDay(model, session, in: selection.current ? nil : selection.week)
                        } onStop: {
                            // The plan changes: the sheet's week is a snapshot, so it closes.
                            stopWeekday(model, session, weekday: wd)
                            dismiss()
                        }
                    }
                    if sessions.isEmpty && away == nil && selection.week.trips[wd] == nil {
                        Text("No gym session planned.").foregroundStyle(Theme.muted)
                    }
                    if selection.current && selection.week.off[wd] == nil {
                        let past = key < PlanCalendar.key(Date(), cal)
                        Button {
                            if past {
                                loggingPast = true
                            } else {
                                insertsBefore = model.state.synced?.planInserts?.count ?? 0
                                adding = true
                            }
                        } label: {
                            Label(past ? "Log a workout" : sessions.isEmpty ? "Add workout" : "Add another workout",
                                  systemImage: past ? "square.and.pencil" : "plus.circle.fill")
                                .font(Theme.label(15)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime))
                        }
                        .buttonStyle(.plain)
                    }
                    if away == nil && selection.week.trips[wd] == nil && key >= PlanCalendar.key(Date(), cal) {
                        // Plan sport (#474): once, every week or a trip from this day.
                        Button {
                            profileBefore = model.profile
                            planningSport = true
                        } label: {
                            Label("Plan sport", systemImage: "figure.mixed.cardio")
                                .font(Theme.label(15)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sport.snowboard.gradient))
                        }
                        .buttonStyle(.plain)
                    }
                    if away == nil {
                        HStack(spacing: 10) {
                            ForEach(AwayKind.allCases) { kind in
                                Button { onAdd(kind, key) } label: {
                                    Label(kind.label, systemImage: kind.symbol)
                                        .font(Theme.label(14)).foregroundStyle(.white)
                                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(kind.gradient))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0; fit() }
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: { chromeHeight = $0; fit() }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents(fitDetent.map { [$0, .large] } ?? [.large], selection: $detent)
        .sheet(item: $moving) { s in MoveSessionSheet(sessionId: s.id) { _ in dismiss() } }
        .sheet(item: $logging) { s in MissedLogSheet(session: s) }
        .sheet(isPresented: $loggingPast, onDismiss: logPastPick) { PastDayLogSheet(day: dayDate) { pastPick = $0 } }
        .sheet(item: $pastWorkout) { s in MissedLogSheet(session: s, day: dayDate) }
        .sheet(item: $pastSport) { LogSportView(initial: $0) }
        .sheet(isPresented: $planningSport, onDismiss: closeIfPlanned) { PlanSportSheet(day: key, sport: model.profile?.otherSports.first?.sport) }
        .sheet(item: $editingTrip, onDismiss: closeIfPlanned) { t in PlanSportSheet(day: t.start, editing: t) }
        .sheet(isPresented: $adding, onDismiss: { if (model.state.synced?.planInserts?.count ?? 0) > insertsBefore { dismiss() } }) { AddWorkoutSheet(weekday: wd) }
    }

    /// This day's date, for logging on it.
    private var dayDate: Date { selection.week.date(selection.weekday, model.planCalendar) ?? Date() }

    /// Opens the log sheet for what "What did you do?" picked, once it's down (#818).
    private func logPastPick() {
        guard let pick = pastPick else { return }
        pastPick = nil
        let evening = model.planCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayDate) ?? dayDate
        switch pick {
        case let .workout(s): pastWorkout = s
        case let .sport(sport): pastSport = sport.map { SportLog(sport: $0, start: evening, minutes: 60) } ?? SportLog(start: evening)
        }
    }

    private func closeIfPlanned() {
        if model.profile != profileBefore { dismiss() }
    }

    /// Content + close bar + home indicator; nil until measured.
    private var fitDetent: PresentationDetent? {
        contentHeight > 0 ? .height((contentHeight + chromeHeight).rounded(.up)) : nil
    }

    /// Snap to the fitted height on open and when the content changes (e.g. a session moved away).
    private func fit() {
        if let d = fitDetent { detent = d }
    }
}

/// Session summary for any week; tap it for the full workout page (#840).
private struct SessionPreview: View {
    let session: Session
    let current: Bool
    let done: Bool
    /// This week, not done: "Move to…".
    var canMove = false
    /// Not done (#854): Skip, any week; long press it for "Stop training <weekday>s" when `stopTitle` is set.
    var canSkip = false
    var stopTitle: String? = nil
    var onMove: () -> Void = {}
    var onSkip: () -> Void = {}
    var onStop: () -> Void = {}
    @Environment(AppModel.self) private var model
    @State private var hiitSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The whole summary opens the full workout page (#840): this week's, or a later week's ahead (#758).
            NavigationLink {
                if current { SessionView(sessionId: session.id) } else { SessionView(sessionId: session.id, preview: session) }
            } label: { summary }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendar.openWorkout")
            // Outside the link: its HIIT › button opens HIIT settings (#841).
            if model.isPlannedHiit(session) { hiitSource }
            if current {
                HStack(spacing: 10) {
                    NavigationLink {
                        SessionView(sessionId: session.id)
                    } label: {
                        Label(canMove ? "Open" : "Open session", systemImage: "list.bullet").lineLimit(1)
                    }
                    .buttonStyle(LimeButtonStyle())
                    if canMove {
                        Button(action: onMove) {
                            Label(canSkip ? "Move" : "Move to…", systemImage: "arrow.left.arrow.right")
                                .lineLimit(1)
                                .font(Theme.label(15)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(Capsule().fill(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                    if canSkip { skipButton }
                }
            } else {
                Text("Exercises may still change with your progress and plan settings.")
                    .font(.caption).foregroundStyle(Theme.muted)
                if canSkip { skipButton }
            }
        }
        .card()
    }
}

extension SessionPreview {
    /// Where a planned HIIT day comes from (#841, design B): HIIT settings, opened from here.
    fileprivate var hiitSource: some View {
        let h = model.profile?.hiit
        let picked = h?.weekdays.contains(session.weekday ?? 0) == true
        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
            Text("HIIT day · \(h?.days ?? 1)× a week, \(picked ? "your pick" : "Coach picks the day")")
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button { hiitSettings = true } label: {
                Text("HIIT ›").padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0xFF8A3D).opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("calendar.hiitSettings")
        }
        .font(Theme.label(12)).foregroundStyle(Color(hex: 0xFFB27A))
        .sheet(isPresented: $hiitSettings) { HiitSettingsSheet() }
    }

    /// Title, stripe and main exercises; a chevron says it opens.
    fileprivate var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.displayTitle).font(.system(.title3, design: .rounded).weight(.heavy))
                Spacer()
                if done {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.lime)
                } else {
                    Text("\(session.estMin)′").font(Theme.label(15)).foregroundStyle(Theme.muted)
                }
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted)
            }
            BlockStripe(blocks: session.blocks, height: 6)
            ForEach(session.blocks.filter { $0.kind == .power || $0.kind == .strength }) { b in
                VStack(alignment: .leading, spacing: 4) {
                    Text(b.title).eyebrow()
                    ForEach(b.items) { it in
                        HStack {
                            Text(Exercise.find(it.exerciseId)?.name ?? it.exerciseId).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(it.prescription.sets) × \(it.prescription.reps)").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// Skip (#854, design A): one tap with the Undo bar; long press for the plan change.
    fileprivate var skipButton: some View {
        Button(action: onSkip) {
            Label("Skip", systemImage: "nosign")
                .lineLimit(1).minimumScaleFactor(0.8)
                .font(Theme.label(15)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Capsule().fill(MissedStyle.gradient))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let stopTitle { Button(stopTitle, systemImage: "arrow.triangle.2.circlepath", role: .destructive, action: onStop) }
        }
        .accessibilityIdentifier("calendar.skip")
    }
}

/// Create or edit a "can't train" or travel period.
struct AwayEditorView: View {
    let isNew: Bool
    /// nil = delete.
    let onDone: (AwayPeriod?) -> Void
    @State private var draft: AwayPeriod
    @State private var from: Date
    @State private var to: Date
    @State private var note: String
    @State private var showEquipment = false
    @State private var query = ""
    @State private var results: [GymRef] = []
    @State private var searching = false
    @State private var findingGym = false
    @State private var settingUp = false
    @State private var closeGuard = CloseGuard()
    /// Set on Remove so a pending auto save never brings the period back (#437).
    @State private var removed = CloseGuard()
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let initial: AwayPeriod
    private let baseline: Draft

    /// What's entered, kept for Undo (#285). Dates as calendar days.
    struct Draft: Equatable {
        var period: AwayPeriod
        var from: String
        var to: String
        var note: String
    }

    init(initial: AwayPeriod, isNew: Bool, restoring: Draft? = nil, onDone: @escaping (AwayPeriod?) -> Void) {
        self.isNew = isNew
        self.onDone = onDone
        self.initial = initial
        let base = Draft(period: initial, from: initial.start, to: initial.end, note: initial.note ?? "")
        self.baseline = base
        let shown = restoring ?? base
        let cal = Progression.calendar()
        _draft = State(initialValue: shown.period)
        _from = State(initialValue: PlanCalendar.date(shown.from, cal) ?? Date())
        _to = State(initialValue: PlanCalendar.date(shown.to, cal) ?? Date())
        _note = State(initialValue: shown.note)
    }

    private var entered: Draft {
        let cal = Progression.calendar()
        return Draft(period: draft, from: PlanCalendar.key(from, cal), to: PlanCalendar.key(to, cal), note: note)
    }

    /// Undo bar when anything was changed since the sheet opened (#285).
    private var undoOffer: UndoOffer? {
        let kept = entered
        guard isNew, kept != baseline else { return nil }
        let original = self.initial, new = self.isNew, done = self.onDone
        let kind = kept.period.kind
        return UndoOffer(title: new ? "Away closed" : "Edit closed", detail: undoDetail(kind.label, kept.note),
                         symbol: kind.symbol, colors: kind == .off ? WorkoutEngine.Category.power.colors : WorkoutEngine.Category.cardio.colors) {
            AnyView(AwayEditorView(initial: original, isNew: new, restoring: kept, onDone: done))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    kindPicker
                    VStack(spacing: 0) {
                        DatePicker("From", selection: $from, displayedComponents: .date)
                            .padding(.vertical, 6)
                        Divider().overlay(Theme.stroke)
                        DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                            .padding(.vertical, 6)
                        Divider().overlay(Theme.stroke)
                        TextField(draft.kind == .travel ? "Where (optional)" : "Reason (optional)", text: $note)
                            .padding(.vertical, 12)
                    }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .card(padding: 14)

                    if draft.kind == .travel {
                        Text("What's there").eyebrow().padding(.top, 4)
                        // Saved gyms and the swipe setup (#162).
                        ForEach(model.savedGyms.filter { $0.id != model.homeGym.id }) { g in
                            SavedGymRow(gym: g, selected: draft.gym?.id == g.id) { pick(g) }
                                .card(padding: 10)
                        }
                        Button { settingUp = true } label: {
                            Label("Set up this gym in a few swipes", systemImage: "rectangle.stack.badge.plus")
                                .font(Theme.label(14)).foregroundStyle(Theme.lime)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Capsule().strokeBorder(Theme.lime, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        ForEach(TravelSetup.allCases) { setup in setupCard(setup) }
                        if draft.setup == .fullGym { gymSearch }
                        Button { showEquipment = true } label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.lime)
                                Text("Fine-tune equipment").bold()
                                Spacer()
                                Text("\(draft.travelEquipment.count) items").foregroundStyle(Theme.lime).bold()
                                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Theme.muted)
                            }
                            .foregroundStyle(.white)
                            .card(padding: 14)
                        }
                        .buttonStyle(.plain)
                        Text("Sessions on these days are rebuilt for this equipment. Climbing days are paused.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    } else {
                        Text("Sessions on these days move to free days of the same week. With too few free days left, the week switches to fewer, fuller sessions. Climbing days are paused.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }

                    if isNew {
                        Button("Save") { save() }
                            .buttonStyle(LimeButtonStyle())
                            .padding(.top, 6)
                    } else {
                        Text("Changes save on their own.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    if !isNew {
                        Button(role: .destructive) {
                            // As saved, auto-saved edits included, for the Undo bar (#822).
                            let stored = model.away.first { $0.id == initial.id } ?? period
                            removed.done()
                            closeGuard.done()
                            onDone(nil)
                            dismiss()
                            UndoCloseCenter.shared.deleted("\(stored.kind.label) removed", detail: undoDetail(stored.note), symbol: stored.kind.symbol) { [model] in
                                model.saveAway(stored)
                            }
                        } label: {
                            Text("Remove").font(Theme.label(15)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isNew ? "Away" : "Edit away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(isPresented: $findingGym) {
                GymFinderView(place: note) { ref in
                    draft.gym = ref
                    draft.setup = .fullGym
                }
            }
            .sheet(isPresented: $settingUp) {
                GymSetupView(ref: draft.setup == .fullGym ? draft.gym : nil, name: note, actionTitle: "USE FOR THIS TRIP") { g in
                    model.saveGym(g)
                    pick(g)
                }
            }
            .sheet(isPresented: $showEquipment) {
                EquipmentSheet(equipment: Binding(get: { draft.travelEquipment }, set: { draft.equipment = $0 }))
            }
            .onChange(of: from) { _, v in if to < v { to = v } }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard q.count >= 2 else {
                    results = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                searching = true
                let found = await GymSearch.search(q)
                searching = false
                guard !Task.isCancelled else { return }
                results = found
            }
        }
        .preferredColorScheme(.dark)
        .undoableClose(closeGuard, offer: undoOffer)
        // Editing a saved period saves on its own (#437), straight to the plan (onDone would close the sheet).
        .autoSave(isNew ? nil : period, title: "Away", symbol: draft.kind.symbol,
                  detail: { undoDetail($0.kind.label, $0.note) },
                  save: { [model, removed] in if !removed.saved { model.saveAway($0) } })
    }

    private var kindPicker: some View {
        HStack(spacing: 4) {
            ForEach(AwayKind.allCases) { kind in
                Button {
                    draft.kind = kind
                    if kind == .travel && draft.setup == nil { draft.setup = .hotelGym }
                } label: {
                    Label(kind.label, systemImage: kind.symbol)
                        .font(Theme.label(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(draft.kind == kind ? Theme.ink : .white)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(draft.kind == kind ? Theme.lime : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(draft.kind == kind ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
    }

    private func setupCard(_ setup: TravelSetup) -> some View {
        let on = (draft.setup ?? .hotelGym) == setup
        return Button {
            draft.setup = setup
            draft.equipment = nil
            if setup != .fullGym { draft.gym = nil }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: setup.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(setup.category.isLight ? Theme.ink.opacity(0.12) : .white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(setup.label).font(Theme.display(19))
                    Text(setup.blurb).font(.footnote.weight(.medium)).opacity(0.85)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(setup.equipment.count)").font(Theme.display(24))
                    Text("ITEMS").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
            }
            .foregroundStyle(setup.category.ink)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(setup.category.gradient))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.lime, lineWidth: on ? 3 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var gymSearch: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { findingGym = true } label: {
                Label(note.trimmingCharacters(in: .whitespaces).isEmpty ? "Find gyms near me" : "Find gyms near \(note.trimmingCharacters(in: .whitespaces))",
                      systemImage: "location.magnifyingglass")
                    .font(Theme.label(14)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search a gym (name or city)", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
            ForEach(query.isEmpty ? (draft.gym.map { [$0] } ?? []) : results) { g in
                Button {
                    draft.gym = g
                    query = ""
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.system(size: 15, weight: .bold, design: .rounded))
                            if !g.address.isEmpty { Text(g.address).font(.caption).foregroundStyle(Theme.muted).lineLimit(2) }
                        }
                        Spacer()
                        if draft.gym?.id == g.id {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.ink, Theme.lime)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 12)
    }

    private func pick(_ g: SavedGym) {
        draft.gym = g.ref
        draft.setup = .fullGym
        draft.equipment = g.equipment
    }

    private var period: AwayPeriod {
        let cal = Progression.calendar()
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return AwayPeriod(id: draft.id, kind: draft.kind, start: PlanCalendar.key(from, cal), end: PlanCalendar.key(max(from, to), cal),
                          note: n.isEmpty ? nil : n, setup: draft.kind == .travel ? (draft.setup ?? .hotelGym) : nil,
                          equipment: draft.kind == .travel ? draft.equipment : nil, gym: draft.kind == .travel ? draft.gym : nil)
    }

    private func save() {
        closeGuard.done()
        onDone(period)
        dismiss()
    }
}

/// Moves one session of this week to the next free day or a picked day (e.g. from a missed-session reminder).
struct RescheduleSheet: View {
    let sessionId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var result: Date??
    @State private var awayDraft: AwayPeriod?

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    var body: some View {
        let session = model.plan?.sessions.first { $0.id == sessionId }
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let session {
                    Text(session.focus.label).font(Theme.display(28))
                    if let wd = session.weekday {
                        Text("Planned \(WeekSchedule.name(wd))").foregroundStyle(Theme.muted)
                    }
                }
                switch result {
                case .some(.some(let d)):
                    Label("Moved to \(d.formatted(.dateTime.weekday(.wide)))", systemImage: "checkmark.circle.fill")
                        .font(Theme.label(17)).foregroundStyle(Theme.lime)
                case .some(.none):
                    // A missed session that finds no free day stays where it was (#822): nothing is skipped.
                    Label("No free day left this week, so it stays where it was. The plan carries on next week.", systemImage: "info.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                case .none:
                    if session == nil {
                        // Its week has rolled on (#822): no dead Move button.
                        Label("That week is over and your plan has moved on: nothing left to move.", systemImage: "info.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                    } else {
                        Button { result = .some(model.reschedule(sessionId: sessionId)) } label: {
                            Label("Move to next free day", systemImage: "arrow.forward.circle.fill")
                        }
                        .buttonStyle(LimeButtonStyle())
                    }
                }
                if result == nil, session != nil {
                    NavigationLink {
                        ScrollView { MoveDayPicker(sessionId: sessionId) { _ in dismiss() }.padding(16) }
                            .readableWidth()
                            .background(Theme.bg.ignoresSafeArea())
                            .navigationTitle("Pick a day")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Pick a day this week…", systemImage: "calendar")
                            .font(Theme.label(15)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    let today = PlanCalendar.key(Date(), model.planCalendar)
                    awayDraft = AwayPeriod(kind: .off, start: today, end: today)
                } label: {
                    Label("I can't train on other days…", systemImage: "calendar.badge.minus")
                        .font(Theme.label(15)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AwayKind.off.gradient))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(20)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $awayDraft) { a in
                AwayEditorView(initial: a, isNew: true) { saved in
                    if let saved { model.saveAway(saved) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
