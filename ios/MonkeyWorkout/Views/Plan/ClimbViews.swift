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

/// Train tab: "Log climb" card, hard-climb note and recent climbs (logged here or from Apple Health).
struct ClimbSection: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var logging: ClimbLog?
    @State private var settings = false
    @State private var gate: ProGate?

    @AppStorage("wallDay") private var wallDayRaw = WallDay.bouldering.rawValue

    private var monkeyGrade: MonkeyGradeLink { .shared }
    private var wallDay: WallDay { WallDay(rawValue: wallDayRaw) ?? .bouldering }

    private var climbs: [ClimbEntry] {
        Climbs.merged(local: model.climbLogs, health: health.snapshot.recentClimbs, monkeyGrade: monkeyGrade.climbs(for: model.user?.id))
    }

    var body: some View {
        let all = climbs
        VStack(alignment: .leading, spacing: 12) {
            // Log climb and Wall session side by side (design B slim bars); Wall session opens its own page.
            HStack(spacing: 8) {
                Button {
                    logging = ClimbLog(start: Date().addingTimeInterval(-90 * 60))
                } label: {
                    ClimbBar(symbol: "figure.climbing", title: "Log climb", detail: "\(Climbs.thisWeek(all)) this wk",
                             trailing: "plus", gradient: ClimbKind.boulder.gradient)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Log a climbing session")
                // Wall session (#366): on unless turned off in Around climbing days.
                if model.profile?.climbDayAddon != false {
                    NavigationLink {
                        WallSessionPage(today: isClimbingDay, climbedToday: all.contains { Calendar.current.isDateInToday($0.start) })
                    } label: {
                        ClimbBar(symbol: "hand.raised.fill", title: "Wall session", detail: wallDay.label,
                                 trailing: "chevron.right", gradient: ClimbKind.topRope.gradient)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let hard = Climbs.recentHard(all) {
                HardClimbNote(climb: hard)
            }
            AroundClimbingLink { ProStore.shared.run(.climbing, $gate) { settings = true } }
            // Past climbs live on the History page (#442); delete one there with a long press.
        }
        .sheet(item: $logging) { LogClimbView(initial: $0) }
        .sheet(isPresented: $settings) { ClimbSettingsView() }
        .proPaywall($gate)
        .task { if monkeyGrade.isConnected(for: model.user?.id) { await monkeyGrade.refresh() } }
    }

    private var isClimbingDay: Bool {
        let today = WeekSchedule.fromCalendar(Calendar.current.component(.weekday, from: Date()))
        return model.profile?.climbingDays.contains(today) ?? false
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

/// "Around climbing days" link under the climbing cards and on the Wall session page.
struct AroundClimbingLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label("Around climbing days", systemImage: "slider.horizontal.3")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.lime)
                ProBadge()
            }
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

    /// `restoring`: the climb brought back by Undo (#285).
    init(initial: ClimbLog, restoring: ClimbLog? = nil) {
        self.initial = initial
        self.restoring = restoring
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
            .navigationTitle("Log climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .undoableClose(closeGuard, offer: undoOffer)
        .keepsDraft(draftKey, log, blank: initial)
        .onAppear {
            guard draftKey == nil, restoring == nil else { return }
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker("Started", selection: $log.start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .colorScheme(.dark)
                    Text(log.kind.label).font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer()
                Image(systemName: log.kind.symbol).font(.system(size: 40, weight: .bold))
            }

            HStack(spacing: 6) {
                ForEach(ClimbKind.allCases) { k in
                    CardChip(title: k.label, on: log.kind == k) { log.kind = k }
                }
            }

            CardDuration(minutes: $log.minutes, max: 360)

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
            AnyView(LogClimbView(initial: original, restoring: kept))
        }
    }

    private func save() {
        let entry = log
        if let draftKey { DraftStore.clear(draftKey) }
        model.saveClimb(entry)
        let weight = model.body.weightKg ?? health.snapshot.weightKg
        Task {
            if await health.saveClimb(entry, kcal: Climbs.kcal(entry, weightKg: weight)) {
                await health.refresh()
            }
        }
        closeGuard.done()
        dismiss()
    }
}

// MARK: - Around climbing days (#47)

extension ClimbNeighbour {
    var label: String {
        switch self {
        case .light: "Keep it light"
        case .strong: "Strong push or legs"
        case .rest: "Rest"
        case .any: "No adjustment"
        }
    }

    func blurb(before: Bool) -> String {
        switch self {
        case .light: before ? "No heavy pulling, grip or jumps. Push and legs preferred." : "Light on pulling and grip while fingers recover."
        case .strong: before ? "Hard push or leg day welcome. Only pulling and grip kept light." : "Hard push or leg day welcome. Pulling kept light."
        case .rest: "Keep this day free of gym sessions when the week allows."
        case .any: "Plan the gym session as if you weren't climbing."
        }
    }

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

extension ClimbSameDay {
    var label: String {
        switch self {
        case .avoid: "Climb only"
        case .allow: "Gym allowed"
        }
    }

    var blurb: String {
        switch self {
        case .avoid: "Gym sessions go on climbing days only when the week has no room."
        case .allow: "A gym session can share the day, e.g. gym in the morning, climb in the evening."
        }
    }

    var symbol: String { self == .avoid ? "figure.climbing" : "dumbbell.fill" }

    var colors: [Color] {
        self == .avoid ? ClimbKind.boulder.colors : ClimbKind.lead.colors
    }
}

/// How gym days around climbing are planned. Saving rebuilds this week's plan.
struct ClimbSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var before: ClimbNeighbour = .light
    @State private var after: ClimbNeighbour = .light
    @State private var sameDay: ClimbSameDay = .avoid
    @State private var addon = false
    @State private var loaded = false

    /// What's picked, saved on its own (#437).
    struct Picks: Equatable {
        var before: ClimbNeighbour, after: ClimbNeighbour, sameDay: ClimbSameDay, addon: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Day before climbing").eyebrow()
                    ForEach(ClimbNeighbour.allCases) { o in
                        OptionCard(symbol: o.symbol, title: o.label, blurb: o.blurb(before: true), colors: o.colors,
                                   selected: before == o) { before = o }
                    }
                    Text("Day after climbing").eyebrow().padding(.top, 8)
                    ForEach(ClimbNeighbour.allCases) { o in
                        OptionCard(symbol: o.symbol, title: o.label, blurb: o.blurb(before: false), colors: o.colors,
                                   selected: after == o) { after = o }
                    }
                    Text("On climbing days").eyebrow().padding(.top, 8)
                    ForEach(ClimbSameDay.allCases) { o in
                        OptionCard(symbol: o.symbol, title: o.label, blurb: o.blurb, colors: o.colors,
                                   selected: sameDay == o) { sameDay = o }
                    }
                    Toggle(isOn: $addon) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wall session").font(Theme.display(18))
                            Text("Show warm-up, hangboard and after-climb sessions for the climbing gym on Train.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.lime)
                    .card(padding: 16)
                    .padding(.top, 8)

                    Text("Changes save on their own and rebuild this week's plan around your climbing days.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Around climbing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            .autoSave(loaded ? Picks(before: before, after: after, sameDay: sameDay, addon: addon) : nil,
                      title: "Climbing days", symbol: "figure.climbing",
                      detail: { _ in "This week's plan rebuilt" },
                      save: { [model] in Self.store($0, model: model) })
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded, let p = model.profile else { return }
            before = p.climbPrefs.before
            after = p.climbPrefs.after
            sameDay = p.climbPrefs.sameDay
            addon = p.climbDayAddon ?? true
            loaded = true
        }
    }

    private static func store(_ k: Picks, model: AppModel) {
        guard var p = model.profile else { return }
        p.climbBefore = k.before == .light ? nil : k.before
        p.climbAfter = k.after == .light ? nil : k.after
        p.climbSameDay = k.sameDay == .avoid ? nil : k.sameDay
        // Wall session (#366) is on by default; only "off" is stored.
        p.climbDayAddon = k.addon ? (p.climbDayAddon == true ? true : nil) : false
        if p != model.profile {
            model.updateProfile(p)
        }
    }
}

/// Explore-style selectable option: icon tile, title + blurb, gradient when picked.
private struct OptionCard: View {
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
