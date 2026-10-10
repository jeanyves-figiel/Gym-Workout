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

/// Entry card on the Train tab.
struct CalendarEntryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let weeks = model.calendarWeeks(count: 4)
        let count = weeks.reduce(0) { $0 + $1.plan.sessions.filter { !model.doneIds.contains($0.id) }.count }
        NavigationLink {
            CalendarView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Calendar").font(Theme.display(22))
                    Text(model.upcomingAway.isEmpty ? "Next 4 weeks · mark days off or travel" : "Next 4 weeks · \(model.upcomingAway.count) away")
                        .font(.footnote.weight(.semibold)).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(count)").font(Theme.display(34)).monospacedDigit()
                    Text("PLANNED").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calendar, \(count) sessions planned in the next 4 weeks")
    }
}

/// Coming weeks with dated sessions, climbing days and away periods.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: AwayPeriod?
    @State private var editingIsNew = false
    @State private var selected: DaySelection?
    @State private var findingGym = false

    var body: some View {
        let weeks = model.calendarWeeks()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(weeks)
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
                if !model.upcomingAway.isEmpty {
                    Text("Away").eyebrow().padding(.top, 4)
                    ForEach(model.upcomingAway) { a in
                        Button { edit(a) } label: { AwayRow(period: a) }.buttonStyle(.plain)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.element.id) { i, w in
                    Text(header(i, w)).eyebrow().padding(.top, 4)
                    WeekCalendarCard(week: w, current: i == 0) { wd in selected = DaySelection(week: w, weekday: wd, current: i == 0) }
                }
                Text("The 4-week cycle moves on one week each Monday here. Days off move sessions to free days that week; with too few free days you get fewer, fuller sessions. Travel days are rebuilt for the equipment there.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Calendar")
        .toolbarTitleDisplayMode(.inlineLarge)
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
            .presentationDetents([.medium, .large])
        }
    }

    private func hero(_ weeks: [PlanCalendar.Week]) -> some View {
        let next4 = weeks.prefix(4)
        let count = next4.reduce(0) { $0 + $1.plan.sessions.filter { !model.doneIds.contains($0.id) }.count }
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
        let phase = Generator.weekLabel(w.plan.week).components(separatedBy: " · ").first ?? ""
        switch i {
        case 0: return "This week · \(phase)"
        case 1: return "Next week · \(phase)"
        default: return "\(w.start.formatted(.dateTime.day().month(.abbreviated))) · \(phase)"
        }
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
            ForEach(notes, id: \.self) { n in
                Text(n).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .card(padding: 12)
    }

    private var summary: String {
        let n = week.plan.sessions.count
        let trips = week.plan.sessions.filter { $0.weekday.map { week.travel[$0] != nil } ?? false }.count
        return "\(n) session\(n == 1 ? "" : "s")" + (trips > 0 ? " · \(trips) away" : "")
    }

    private var notes: [String] {
        var out: [String] = []
        let periods = Dictionary(grouping: Array(week.off.values) + Array(week.travel.values), by: \.id).compactMap { $0.value.first }
        for p in periods.sorted(by: { $0.start < $1.start }) {
            out.append("\(p.kind == .travel ? "✈︎" : "⛔︎") \(p.title)" + (p.kind == .travel ? " · \(equipmentLine(p))" : ""))
        }
        if week.dropped > 0 { out.append("\(week.dropped) session\(week.dropped == 1 ? "" : "s") skipped: not enough free days") }
        return out
    }

    private func equipmentLine(_ p: AwayPeriod) -> String {
        let items = p.travelEquipment.filter { $0 != .mat }
        if items.isEmpty { return "bodyweight" }
        if items.count > 5 { return "\(items.count) items" }
        return items.map { $0.label.lowercased() }.joined(separator: ", ")
    }

    private func range(_ cal: Calendar) -> String {
        let end = cal.date(byAdding: .day, value: 6, to: week.start)!
        return "\(week.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    @ViewBuilder
    private func tile(_ wd: Int, today: String, cal: Calendar) -> some View {
        let key = week.days[wd - 1]
        let session = week.plan.sessions.first { $0.weekday == wd }
        let done = session.map { current && model.doneIds.contains($0.id) } ?? false
        let off = week.off[wd] != nil
        let travel = week.travel[wd] != nil
        let climb = week.climbing.contains(wd)
        let past = key < today
        let day = week.date(wd, cal).map { cal.component(.day, from: $0) } ?? 0
        let tag: String? = session.map { short($0.focus) } ?? (off ? "Off" : climb ? "Climb" : nil)
        let fill = tileFill(session: session != nil, off: off, travel: travel, climb: climb)
        VStack(spacing: 1) {
            Text(WeekSchedule.shortName(wd).uppercased()).font(Theme.label(9))
            Text("\(day)").font(Theme.display(17)).monospacedDigit()
            if done {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .black))
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
        .opacity(past && !done ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(wd, session: session, done: done, off: off, travel: travel, climb: climb))
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

/// What's on a day; quick "can't train" / travel from there.
struct DaySheet: View {
    let selection: DaySelection
    let onAdd: (AwayKind, String) -> Void
    let onEdit: (AwayPeriod) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.planCalendar
        let wd = selection.weekday
        let key = selection.week.days[wd - 1]
        let session = selection.week.plan.sessions.first { $0.weekday == wd }
        let away = selection.week.off[wd] ?? selection.week.travel[wd]
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text((selection.week.date(wd, cal) ?? Date()).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(Theme.display(28))
                    if let away {
                        Button { onEdit(away) } label: { AwayRow(period: away) }.buttonStyle(.plain)
                    }
                    if selection.week.climbing.contains(wd) {
                        Label("Climbing day", systemImage: "figure.climbing")
                            .font(Theme.label(15)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Capsule().fill(WorkoutEngine.Category.warmup.gradient))
                    }
                    if let session {
                        SessionPreview(session: session, current: selection.current, done: selection.current && model.doneIds.contains(session.id))
                    } else if away == nil {
                        Text("No gym session planned.").foregroundStyle(Theme.muted)
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
            }
            .background(Theme.bg.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
    }
}

/// Session summary for any week (future sessions can't be opened yet: they are previews).
private struct SessionPreview: View {
    let session: Session
    let current: Bool
    let done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.focus.label).font(.system(.title3, design: .rounded).weight(.heavy))
                Spacer()
                if done {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.lime)
                } else {
                    Text("\(session.estMin)′").font(Theme.label(15)).foregroundStyle(Theme.muted)
                }
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
            if current {
                NavigationLink {
                    SessionView(sessionId: session.id)
                } label: {
                    Label("Open session", systemImage: "list.bullet")
                }
                .buttonStyle(LimeButtonStyle())
            } else {
                Text("Exercises may still change with your progress and plan settings.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .card()
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
    @Environment(\.dismiss) private var dismiss

    init(initial: AwayPeriod, isNew: Bool, onDone: @escaping (AwayPeriod?) -> Void) {
        self.isNew = isNew
        self.onDone = onDone
        let cal = Progression.calendar()
        _draft = State(initialValue: initial)
        _from = State(initialValue: PlanCalendar.date(initial.start, cal) ?? Date())
        _to = State(initialValue: PlanCalendar.date(initial.end, cal) ?? Date())
        _note = State(initialValue: initial.note ?? "")
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

                    Button("Save") { save() }
                        .buttonStyle(LimeButtonStyle())
                        .padding(.top, 6)
                    if !isNew {
                        Button(role: .destructive) {
                            onDone(nil)
                            dismiss()
                        } label: {
                            Text("Remove").font(Theme.label(15)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isNew ? "Away" : "Edit away")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $findingGym) {
                GymFinderView(place: note) { ref in
                    draft.gym = ref
                    draft.setup = .fullGym
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
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.22)))
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
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(setup.category.gradient))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.lime, lineWidth: on ? 3 : 0))
            .opacity(on ? 1 : 0.7)
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

    private func save() {
        let cal = Progression.calendar()
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = AwayPeriod(id: draft.id, kind: draft.kind, start: PlanCalendar.key(from, cal), end: PlanCalendar.key(max(from, to), cal),
                           note: n.isEmpty ? nil : n, setup: draft.kind == .travel ? (draft.setup ?? .hotelGym) : nil,
                           equipment: draft.kind == .travel ? draft.equipment : nil, gym: draft.kind == .travel ? draft.gym : nil)
        onDone(p)
        dismiss()
    }
}

/// Moves one session of this week to the next free day (e.g. from a missed-session reminder).
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
                    Label("No free day left this week. It's skipped; the plan carries on next week.", systemImage: "info.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                case .none:
                    Button { result = .some(model.reschedule(sessionId: sessionId)) } label: {
                        Label("Move to next free day", systemImage: "arrow.forward.circle.fill")
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(session == nil)
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
