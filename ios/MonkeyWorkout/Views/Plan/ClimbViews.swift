import SwiftUI
import WorkoutEngine

// Climbing session log (#44): Train-tab card, recent climbs, log sheet.

extension ClimbKind {
    var colors: [Color] {
        switch self {
        case .boulder: [Color(red: 1.0, green: 0.37, blue: 0.23), Color(red: 1.0, green: 0.69, blue: 0.24)]
        case .lead: [Color(red: 0.24, green: 0.35, blue: 1.0), Color(red: 0.0, green: 0.78, blue: 1.0)]
        case .topRope: [Color(red: 0.49, green: 0.30, blue: 1.0), Color(red: 0.88, green: 0.25, blue: 0.98)]
        case .outdoor: [Color(red: 0.17, green: 0.71, blue: 0.45), Color(red: 0.78, green: 0.96, blue: 0.20)]
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

private extension ClimbEntry {
    var gradient: LinearGradient {
        (kind ?? .boulder).gradient
    }

    var durationText: String { Climbs.duration(minutes) }
}

extension Climbs {
    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}

/// Train tab climbing widget: Wall session on climbing days only (#521, design B) and the hard-climb note.
/// Logging a climb lives in Log sport → Climbing; Around sport days in Settings and on the Wall session page.
struct ClimbSection: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health

    private var monkeyGrade: MonkeyGradeLink { .shared }

    private var climbs: [ClimbEntry] {
        Climbs.merged(local: model.climbLogs, health: health.snapshot.recentClimbs, monkeyGrade: monkeyGrade.climbs(for: model.user?.id))
    }

    /// Train is being arranged: keep a tile to move even on a day with nothing to show.
    var arranging = false

    var body: some View {
        let all = climbs
        let wall = isClimbingDay && model.profile?.climbDayAddon != false
        let hard = Climbs.recentHard(all)
        // Nothing to show: no view at all, so Train keeps no gap for it.
        if wall || hard != nil || arranging {
            VStack(alignment: .leading, spacing: 12) {
                // Wall session (#366): on unless turned off in Around sport days.
                if wall {
                    NavigationLink {
                        WallSessionPage(today: true, climbedToday: all.contains { Calendar.current.isDateInToday($0.start) })
                    } label: {
                        ClimbBar(symbol: "hand.raised.fill", title: "Wall session", detail: "Warm-up · hangboard · cool-down",
                                 trailing: "chevron.right", gradient: ClimbKind.topRope.gradient)
                    }
                    .buttonStyle(.plain)
                } else if hard == nil {
                    ClimbBar(symbol: "hand.raised.fill", title: "Wall session", detail: "Shows on climbing days",
                             trailing: "calendar", gradient: ClimbKind.topRope.gradient)
                        .opacity(0.6)
                }
                if let hard {
                    HardClimbNote(climb: hard)
                }
                // Past climbs live on the History page (#442); delete one there with a long press.
            }
        }
    }

    /// Today's sport is climbing (#658): a dated snowboard day on a weekly climbing day shows its own prep instead.
    private var isClimbingDay: Bool {
        let today = WeekSchedule.fromCalendar(Calendar.current.component(.weekday, from: Date()))
        return model.profile?.sport(onWeekday: today, key: PlanCalendar.key(Date(), model.planCalendar)) == .climbing
    }
}

/// Slim gradient bar (design B): icon tile left, title + one detail line, action glyph right.
private struct ClimbBar: View {
    let symbol: String
    let title: String
    let detail: String
    let trailing: String
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(Theme.label(11)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: trailing).font(.subheadline.weight(.heavy))
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient))
        .contentShape(Rectangle())
    }
}

/// "Around climbing days" link on the Wall session and Sport prep pages (#658: free for every sport).
struct AroundSportLink: View {
    let sport: Sport
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Around \(sport.activity) days", systemImage: "slider.horizontal.3")
                .font(Theme.label(13))
                .foregroundStyle(Theme.lime)
        }
        .buttonStyle(.plain)
    }
}

private struct HardClimbNote: View {
    let climb: ClimbEntry

    var body: some View {
        let today = Calendar.current.isDateInToday(climb.start)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fingers.spread.fill").font(.title2).foregroundStyle(Theme.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hard climb \(today ? "today" : "yesterday")").font(.footnote.weight(.bold))
                Text("Fingers and lats need a day. Keep grip and heavy pulling light in your next gym session; push, legs and mobility are fine.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

/// Sheet for logging a climb, laid out like Log sport (#460, design C): sport strip, one card in the type's colours
/// (type, start, duration, how hard, top grade as chips from recent climbs, notes), Save pinned.
struct LogClimbView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var log: ClimbLog
    @State private var closeGuard = CloseGuard()
    /// Typing kept on the device until saved (#437).
    @State private var draftKey: String?
    @State private var draftRestored = false
    @State private var showNotes: Bool
    /// "Other" picked: the grade is typed instead of tapped.
    @State private var typingGrade = false
    /// Another sport picked in the strip (or All): the sheet becomes Log sport.
    @State private var otherSport: SportLog?
    @FocusState private var gradeFocused: Bool
    private let initial: ClimbLog
    private let restoring: ClimbLog?
    /// A logged climb opened from its day (#592): saved over itself, no draft, and it can be deleted.
    private let editing: Bool

    /// `restoring`: the climb brought back by Undo (#285). `editing`: `initial` is a climb already logged (#592).
    init(initial: ClimbLog, restoring: ClimbLog? = nil, editing: Bool = false) {
        self.initial = initial
        self.restoring = restoring
        self.editing = editing
        _log = State(initialValue: restoring ?? initial)
        _showNotes = State(initialValue: (restoring ?? initial).notes != nil)
    }

    private var grade: Binding<String> {
        Binding(get: { log.topGrade ?? "" }, set: { log.topGrade = $0.isEmpty ? nil : String($0.prefix(12)) })
    }

    private var notes: Binding<String> {
        Binding(get: { log.notes ?? "" }, set: { log.notes = $0.isEmpty ? nil : String($0.prefix(500)) })
    }

    var body: some View {
        if let otherSport {
            LogSportView(initial: otherSport, picked: otherSport.sport != .climbing)
        } else {
            form
        }
    }

    private var form: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if draftRestored {
                        DraftRestoredStrip {
                            if let draftKey { DraftStore.clear(draftKey) }
                            log = initial
                            showNotes = initial.notes != nil
                            draftRestored = false
                        }
                    }
                    SportStrip(selected: .climbing, sports: model.sportOrder) { s in
                        if s != .climbing { switchTo(s) }
                    } all: {
                        switchTo(.climbing)
                    }
                    card
                    Text(health.connected && health.writeWorkouts
                         ? "Also saved to Apple Health as a Climbing workout."
                         : "Saved in MonkeyWorkout. Connect Apple Health in Progress → Body & Health to also save it there.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    if editing {
                        Button(role: .destructive) { delete() } label: {
                            Label("Delete climb", systemImage: "trash").font(Theme.label(15)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain).foregroundStyle(Color(hex: 0xFF5F6D)).padding(.top, 4)
                    }
                }
                .padding(16)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: log.kind)
            }
            .scrollDismissesKeyboard(.interactively)
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button { save() } label: {
                    Label("Save \(log.kind.label) · \(Climbs.duration(log.minutes)) · \(log.effort)", systemImage: "checkmark")
                }
                .buttonStyle(LimeButtonStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.bg.opacity(0.95).ignoresSafeArea())
            }
            .navigationTitle(editing ? "Edit climb" : "Log climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .undoableClose(closeGuard, offer: undoOffer)
        .keepsDraft(draftKey, log, blank: initial)
        .onAppear {
            guard draftKey == nil, restoring == nil, !editing else { return }
            draftKey = "climb"
            if let d = DraftStore.load("climb", as: ClimbLog.self), d != initial {
                log = d
                showNotes = d.notes != nil
                draftRestored = true
            }
        }
    }

    /// Design C card: type chips, start, duration, how hard, grade chips, notes, all in the type's colours.
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTimes(start: $log.start, minutes: log.minutes)
            HStack {
                Text(log.kind.label).font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Image(systemName: log.kind.symbol).font(.system(size: 40, weight: .bold))
            }

            HStack(spacing: 6) {
                ForEach(ClimbKind.allCases) { k in
                    CardChip(title: k.label, on: log.kind == k) { log.kind = k }
                }
            }

            CardDuration(minutes: CardTimes.endAnchored($log.minutes, start: $log.start), max: 360)

            Text("How hard · \(log.effort) \(ClimbLog.effortLabel(log.effort))")
                .font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
            FeelChips(effort: $log.effort)

            Text("Top grade").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
            gradePicker

            if showNotes {
                TextField("Projects, beta, how fingers felt", text: notes, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.25)))
            } else {
                AddChip(title: "Notes") { showNotes = true }
            }
        }
        .gradientCard(log.kind.gradient, padding: 18)
        .shadow(color: log.kind.colors[0].opacity(0.35), radius: 16, y: 8)
    }

    /// Grades of the member's recent climbs as chips (tap again to clear); "Other" types one. No history: the field.
    @ViewBuilder private var gradePicker: some View {
        let recent = recentGrades
        if recent.isEmpty || typingGrade {
            TextField("e.g. 6B+, V5 or 7a", text: grade)
                .font(Theme.display(22))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($gradeFocused)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.25)))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recent, id: \.self) { g in
                        gradeChip(g, on: log.topGrade == g) { log.topGrade = log.topGrade == g ? nil : g }
                    }
                    gradeChip("Other", on: false) {
                        typingGrade = true
                        gradeFocused = true
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func gradeChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(15)).lineLimit(1)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .foregroundStyle(on ? Theme.ink : .white)
                .background(Capsule().fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.25))))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Last few distinct grades logged here (newest first), plus the one in this log if typed.
    private var recentGrades: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for g in ([log.topGrade] + model.climbLogs.map(\.topGrade)).compactMap({ $0 }) where seen.insert(g.uppercased()).inserted {
            list.append(g)
            if list.count == 5 { break }
        }
        return list
    }

    /// Another sport in the strip: the sheet turns into Log sport for it, same start time (#460).
    /// `.climbing` (All): Log sport's full grid.
    private func switchTo(_ sport: Sport) {
        if let draftKey { DraftStore.clear(draftKey) }
        closeGuard.done()
        otherSport = SportLog(sport: sport, start: log.start)
    }

    /// Undo bar when anything was changed since the sheet opened (#285).
    private var undoOffer: UndoOffer? {
        guard log != initial else { return nil }
        let kept = log
        let original = initial
        return UndoOffer(title: "Climb closed",
                         detail: undoDetail(kept.kind.label, Climbs.duration(kept.minutes), kept.topGrade),
                         symbol: kept.kind.symbol, colors: kept.kind.colors) {
            AnyView(LogClimbView(initial: original, restoring: kept, editing: editing))
        }
    }

    private func save() {
        let entry = log
        if let draftKey { DraftStore.clear(draftKey) }
        model.saveClimb(entry)
        let weight = model.body.weightKg ?? health.snapshot.weightKg
        let replaces = editing
        Task {
            // An edited climb replaces its Health workout instead of adding a second one (#592).
            if replaces { await health.deleteClimb(entry.id) }
            if await health.saveClimb(entry, kcal: Climbs.kcal(entry, weightKg: weight)) {
                await health.refresh()
            }
        }
        closeGuard.done()
        dismiss()
    }

    private func delete() {
        let id = initial.id
        model.deleteClimb(id)
        Task {
            await health.deleteClimb(id)
            await health.refresh()
        }
        closeGuard.done()
        dismiss()
    }
}

// MARK: - Around sport days (#47, any sport #658)

extension ClimbNeighbour {
    var symbol: String {
        switch self {
        case .light: "leaf.fill"
        case .strong: "flame.fill"
        case .rest: "bed.double.fill"
        case .any: "circle.dashed"
        }
    }

    var colors: [Color] {
        switch self {
        case .light: [Color(red: 0.12, green: 0.85, blue: 0.54), Color(red: 0.71, green: 1.0, blue: 0.42)]
        case .strong: [Color(red: 1.0, green: 0.18, blue: 0.33), Color(red: 1.0, green: 0.54, blue: 0.0)]
        case .rest: [Color(red: 0.18, green: 0.42, blue: 1.0), Color(red: 0.54, green: 0.30, blue: 1.0)]
        case .any: [Color(white: 0.35), Color(white: 0.55)]
        }
    }
}

/// How gym days around each sport are planned (design A, #658): a strip of the member's sports on top, the
/// "Around climbing" cards below, worded from the picked sport's load. Climbing keeps its own fields and Wall session;
/// other sports save into their `SportPlan`. Saving rebuilds this week's plan.
struct AroundSportView: View {
    /// Sport shown first; nil = the first of the member's sports.
    var initial: Sport? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sport: Sport = .climbing
    @State private var picks = Picks()
    @State private var loaded = false

    /// What's picked, saved on its own (#437).
    struct Picks: Equatable {
        var climbBefore: ClimbNeighbour = .light, climbAfter: ClimbNeighbour = .light, climbSameDay: ClimbSameDay = .avoid
        var addon = true
        var sports: [SportPlan] = []
    }

    /// Climbing (for climbers) first, then the member's other sports.
    private var sports: [Sport] {
        guard let p = model.profile else { return [] }
        return (Generator.isClimber(p) ? [.climbing] : []) + p.otherSports.map(\.sport)
    }

    private var before: Binding<ClimbNeighbour> {
        Binding(get: { sport == .climbing ? picks.climbBefore : plan.before ?? sport.defaultBefore },
                set: { v in
                    if sport == .climbing { picks.climbBefore = v } else { update { $0.before = v == sport.defaultBefore ? nil : v } }
                })
    }

    private var after: Binding<ClimbNeighbour> {
        Binding(get: { sport == .climbing ? picks.climbAfter : plan.after ?? sport.defaultAfter },
                set: { v in
                    if sport == .climbing { picks.climbAfter = v } else { update { $0.after = v == sport.defaultAfter ? nil : v } }
                })
    }

    private var sameDay: Binding<ClimbSameDay> {
        Binding(get: { sport == .climbing ? picks.climbSameDay : plan.sameDay ?? .avoid },
                set: { v in
                    if sport == .climbing { picks.climbSameDay = v } else { update { $0.sameDay = v == .avoid ? nil : v } }
                })
    }

    private var plan: SportPlan { picks.sports.first { $0.sport == sport } ?? SportPlan(sport: sport) }

    private func update(_ change: (inout SportPlan) -> Void) {
        guard let i = picks.sports.firstIndex(where: { $0.sport == sport }) else { return }
        change(&picks.sports[i])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if sports.isEmpty {
                        Text("Add a sport in Train → Edit plan or on a Calendar day, then pick how gym days fit around it here.")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                    } else {
                        if sports.count > 1 { strip }
                        options
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(sports.count == 1 ? "Around \(sport.activity)" : "Around your sports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            .autoSave(loaded ? picks : nil, title: "Sport days", symbol: sport.symbol,
                      detail: { _ in "This week's plan rebuilt" },
                      save: { [model] in Self.store($0, model: model) })
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded, let p = model.profile else { return }
            picks = Picks(climbBefore: p.climbPrefs.before, climbAfter: p.climbPrefs.after, climbSameDay: p.climbPrefs.sameDay,
                          addon: p.climbDayAddon ?? true, sports: p.otherSports)
            sport = initial.flatMap { s in sports.contains(s) ? s : nil } ?? sports.first ?? .climbing
            loaded = true
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sports) { s in
                    Button { withAnimation(.snappy) { sport = s } } label: {
                        Label(s.short, systemImage: s.symbol)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(sport == s ? AnyShapeStyle(s.gradient) : AnyShapeStyle(Theme.cardStrong)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: sport == s ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(sport == s ? .isSelected : [])
                }
            }
            .padding(2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder private var options: some View {
        Text("Day before \(sport.activity)").eyebrow()
        ForEach(ClimbNeighbour.allCases) { o in
            OptionCard(symbol: o.symbol, title: sport.aroundLabel(o), blurb: sport.aroundBlurb(o, before: true), colors: o.colors,
                       selected: before.wrappedValue == o) { before.wrappedValue = o }
        }
        Text("Day after \(sport.activity)").eyebrow().padding(.top, 8)
        if sport == .scubaDiving {
            Text("Rest is advised the day after diving: hard exercise after a dive raises the risk of decompression sickness.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime)
        }
        ForEach(ClimbNeighbour.allCases) { o in
            OptionCard(symbol: o.symbol, title: sport.aroundLabel(o), blurb: sport.aroundBlurb(o, before: false), colors: o.colors,
                       selected: after.wrappedValue == o) { after.wrappedValue = o }
        }
        Text("On \(sport.activity) days").eyebrow().padding(.top, 8)
        if sport.allowsSameDayGym {
            ForEach(ClimbSameDay.allCases) { o in
                OptionCard(symbol: o == .avoid ? sport.symbol : "dumbbell.fill", title: sport.sameDayLabel(o), blurb: sport.sameDayBlurb(o),
                           colors: o == .avoid ? sport.colors : ClimbKind.lead.colors, selected: sameDay.wrappedValue == o) { sameDay.wrappedValue = o }
            }
        } else {
            Text("No gym on dive days.").font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime)
        }
        if sport == .climbing {
            Toggle(isOn: $picks.addon) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wall session").font(Theme.display(18))
                    Text("Show warm-up, hangboard and after-climb sessions for the climbing gym on Train.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.lime)
            .card(padding: 16)
            .padding(.top, 8)
        }
        Text("Changes save on their own and rebuild this week's plan around your sport days.")
            .font(.footnote).foregroundStyle(Theme.muted)
    }

    private static func store(_ k: Picks, model: AppModel) {
        guard var p = model.profile else { return }
        p.climbBefore = k.climbBefore == .light ? nil : k.climbBefore
        p.climbAfter = k.climbAfter == .light ? nil : k.climbAfter
        p.climbSameDay = k.climbSameDay == .avoid ? nil : k.climbSameDay
        // Wall session (#366) is on by default; only "off" is stored.
        p.climbDayAddon = k.addon ? (p.climbDayAddon == true ? true : nil) : false
        // Only the around-day fields: days, season and event may have changed elsewhere meanwhile.
        p.sports = p.sports?.map { sp in
            guard let edited = k.sports.first(where: { $0.sport == sp.sport }) else { return sp }
            var out = sp
            out.before = edited.before
            out.after = edited.after
            out.sameDay = edited.sameDay
            return out
        }
        if p != model.profile {
            model.updateProfile(p)
        }
    }
}

/// Explore-style selectable option: icon tile, title + blurb, gradient when picked.
struct OptionCard: View {
    let symbol: String
    let title: String
    let blurb: String
    let colors: [Color]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.display(19))
                    Text(blurb).font(.footnote.weight(.medium)).opacity(0.85).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2.weight(.bold))
                    .opacity(selected ? 1 : 0.8)
            }
            .foregroundStyle(.white)
            .padding(14)
            .selectableGradient(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                selected: selected, cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
