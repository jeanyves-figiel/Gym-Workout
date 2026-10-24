import SwiftUI
import WorkoutEngine

// Plan sport (#474, design C from `sport-trips/proposals-2.png`): from a day in Calendar or the Train week strip, a
// sport once, every week or as a trip; Your week shows climbing and every other sport as cards with day dots.

/// Sport strip with "All" opening the full picker (#474, design C of `sport-trips/add-sport-proposals.png`).
struct SportStripPicker: View {
    @Binding var selected: Sport
    var sports: [Sport]
    @Environment(AppModel.self) private var model
    @State private var all = false

    var body: some View {
        SportStrip(selected: selected, sports: sports, pick: { selected = $0 }) { all = true }
            .sheet(isPresented: $all) {
                NavigationStack {
                    ScrollView {
                        SportPicker(sports: sports, mine: model.mySports, live: false, selected: selected) { s in
                            selected = s
                            all = false
                        }
                        .padding(16)
                    }
                    .readableWidth()
                    .background(Theme.bg.ignoresSafeArea())
                    .navigationTitle("All sports")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { CloseToolbarItem { all = false } }
                }
                .preferredColorScheme(.dark)
            }
    }
}

/// Plan sport on a day: once, every week (that weekday) or a trip until a later day. Editing a dated day or trip
/// opens it with Remove.
struct PlanSportSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case once = "Once", weekly = "Every week", trip = "Trip"
        var id: String { rawValue }
    }

    /// Day key ("2027-02-13") the sheet was opened on.
    let day: String
    var editing: SportTrip?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sport: Sport
    @State private var mode: Mode
    @State private var until: Date
    @State private var name: String
    /// Removed: nothing left to auto save.
    @State private var removed = false

    init(day: String, editing: SportTrip? = nil, sport: Sport? = nil) {
        self.day = editing?.start ?? day
        self.editing = editing
        let cal = Progression.calendar()
        let start = PlanCalendar.date(editing?.start ?? day, cal) ?? Date()
        _sport = State(initialValue: editing?.sport ?? sport ?? .snowboard)
        _mode = State(initialValue: editing.map { $0.isTrip ? .trip : .once } ?? .once)
        _until = State(initialValue: editing.flatMap { PlanCalendar.date($0.end, cal) } ?? cal.date(byAdding: .day, value: 6, to: start) ?? start)
        _name = State(initialValue: editing?.name ?? "")
    }

    private var cal: Calendar { model.planCalendar }
    private var startDate: Date { PlanCalendar.date(day, cal) ?? Date() }
    private var weekday: Int { WeekSchedule.fromCalendar(cal.component(.weekday, from: startDate)) }
    private var modes: [Mode] { editing == nil ? Mode.allCases : [.once, .trip] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SportStripPicker(selected: $sport, sports: model.sportOrder)
                    HStack(spacing: 6) {
                        ForEach(modes) { m in
                            SportChip(title: m.rawValue, selected: mode == m) { withAnimation(.snappy) { mode = m } }
                        }
                    }
                    card
                    Text(footnote).font(.footnote).foregroundStyle(Theme.muted)
                    if let editing {
                        Button(role: .destructive) { remove(editing) } label: { Label("Remove \(editing.title)", systemImage: "trash") }
                            .font(Theme.label(14))
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                // A new sport day is planned with the button; an existing one saves itself (#717, #437).
                if editing == nil {
                    Button { save() } label: { Label(saveTitle, systemImage: "checkmark") }
                        .buttonStyle(LimeButtonStyle())
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.bg.opacity(0.95).ignoresSafeArea())
                }
            }
            .navigationTitle("Plan sport · \(startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .autoSave(removed ? nil : editing.map { _ in trip }, title: "Sport day", symbol: sport.symbol, detail: { $0.title },
                      save: { [model] t in model.saveSportTrip(t) })
        }
        .preferredColorScheme(.dark)
    }

    /// The sport's colours hold what is planned.
    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: sport.symbol).font(.system(size: 20, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sport.label).font(Theme.display(20)).lineLimit(1)
                    Text(summary).font(Theme.label(12)).opacity(0.9).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if mode == .trip {
                DatePicker("Until", selection: $until, in: startDate..., displayedComponents: .date)
                    .font(Theme.label(15))
                    .colorScheme(.dark)
                TextField("Name (e.g. Laax week)", text: $name)
                    .font(Theme.label(15))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(sport.gradient))
    }

    private var days: Int { max(1, (cal.dateComponents([.day], from: startDate, to: until).day ?? 0) + 1) }

    private var summary: String {
        switch mode {
        case .once: startDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .weekly: "Every \(WeekSchedule.name(weekday))"
        case .trip: "\(startDate.formatted(.dateTime.day().month(.abbreviated))) – \(until.formatted(.dateTime.day().month(.abbreviated))) · \(days) days"
        }
    }

    private var saveTitle: String {
        switch mode {
        case .once: "Plan \(sport.short) day"
        case .weekly: "\(sport.short) every \(WeekSchedule.name(weekday))"
        case .trip: "Plan \(days)-day trip"
        }
    }

    private var footnote: String {
        switch mode {
        case .weekly: "Added to your usual days in Train → Edit plan → Your week. Gym days around it spare \(sport.loadLabel)."
        default: "No gym on \(mode == .trip ? "those days" : "that day"): sessions move to free days, and the days around it spare \(sport.loadLabel)."
        }
    }

    /// The dated day or trip as on screen.
    private var trip: SportTrip {
        let end = mode == .trip ? PlanCalendar.key(until, cal) : day
        let n = name.trimmingCharacters(in: .whitespaces)
        return SportTrip(id: editing?.id ?? UUID(), sport: sport, start: day, end: end, name: mode == .trip && !n.isEmpty ? n : nil)
    }

    private func save() {
        switch mode {
        case .weekly: model.addWeeklySportDay(sport, weekday: weekday)
        case .once, .trip: model.saveSportTrip(trip)
        }
        dismiss()
    }

    /// Removed at once (#717); the Undo bar puts it back as it was saved.
    private func remove(_ editing: SportTrip) {
        let saved = model.profile?.sportTrips?.first { $0.id == editing.id } ?? editing
        removed = true
        model.deleteSportTrip(editing.id)
        dismiss()
        UndoCloseCenter.shared.deleted("\(saved.title) removed", symbol: saved.sport.symbol) { [model] in model.saveSportTrip(saved) }
    }
}

/// A dated sport day or trip on a day sheet; tap to edit.
struct SportTripRow: View {
    let trip: SportTrip
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trip.sport.symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.title).font(.system(size: 16, weight: .heavy, design: .rounded)).lineLimit(1)
                Text(dates).font(.caption.weight(.semibold)).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(trip.sport.gradient))
    }

    private var dates: String {
        let cal = model.planCalendar
        guard let a = PlanCalendar.date(trip.start, cal), let b = PlanCalendar.date(trip.end, cal) else { return "" }
        let f = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        let n = (cal.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        return trip.isTrip ? "\(a.formatted(f)) – \(b.formatted(f)) · \(n) days · no gym" : "\(a.formatted(f)) · no gym"
    }
}

// MARK: - Your week: sport cards

/// Climbing and every other sport as bold cards (#474 design C): a switch, day dots to tap, the card opens the rest.
struct MySportCards: View {
    @Binding var profile: Profile
    /// Shows the Snow ready link (#428); off during onboarding.
    var programmeLink = false
    let climbingDays: Binding<[Int]>
    @State private var editing: SportPlan?
    @State private var snow: ProgrammeRoute?

    var body: some View {
        let list = (profile.sports ?? []).filter { $0.sport != .climbing }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("My sports", systemImage: "figure.mixed.cardio").font(Theme.label(13)).foregroundStyle(Theme.muted)
                Spacer()
                Button { editing = SportPlan(sport: firstFree(list)) } label: {
                    Label("Add", systemImage: "plus").font(Theme.label(13)).foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add sport")
            }
            climbingCard
            ForEach(list) { sp in sportCard(sp) }
            if list.isEmpty {
                Text("Snowboard, bike, Hyrox… Gym days are planned around them. Trips and one-off days: tap a day in Calendar.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if programmeLink, let ride = SnowRide.from(profile.sports) {
                Button { snow = ProgrammeRoute(id: ride.programmeId) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "snowflake").font(.system(size: 14, weight: .bold))
                        Text("Snow ready programme").font(Theme.label(14))
                        Spacer(minLength: 4)
                        Text("Get ready for the season ›").font(.footnote.weight(.bold)).foregroundStyle(Theme.lime)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $snow) { ProgrammeSheet(id: $0.id) }
        .sheet(item: $editing) { sp in
            SportPlanEditor(plan: sp, isNew: !(profile.sports ?? []).contains { $0.sport == sp.sport }) { saved, removed in
                var all = (profile.sports ?? []).filter { $0.sport != sp.sport && $0.sport != saved.sport }
                if !removed { all.append(saved) }
                profile.sports = all.isEmpty ? nil : all
            }
        }
    }

    private var climbingCard: some View {
        SportDayCard(sport: .climbing, title: "Climbing",
                     detail: profile.climbs ? (profile.climbingDays.isEmpty ? "\(profile.climbingDaysPerWeek) days / week · best free days" : "Gym placed around climbing")
                                            : "Off",
                     on: Binding(get: { profile.climbs }, set: { profile.climbs = $0 }),
                     days: climbingDays, tapCard: nil) {
            if profile.climbs && profile.climbingDays.isEmpty {
                HStack(spacing: 6) {
                    Text("or days / week").font(Theme.label(11)).opacity(0.85)
                    ForEach(1...4, id: \.self) { n in
                        CardChip(title: "\(n)", on: profile.climbingDaysPerWeek == n) { profile.climbingDaysPerWeek = n }
                    }
                }
            }
        }
    }

    private func sportCard(_ sp: SportPlan) -> some View {
        SportDayCard(sport: sp.sport, title: sp.sport.label, detail: detail(sp),
                     on: Binding(get: { sp.isOn }, set: { on in update(sp.sport) { $0.paused = on ? nil : true } }),
                     days: Binding(get: { WeekSchedule.normalized(sp.weekdays) }, set: { d in update(sp.sport) { $0.weekdays = d } }),
                     tapCard: { editing = sp }) { EmptyView() }
    }

    private func detail(_ sp: SportPlan) -> String {
        guard sp.isOn else { return "Off · days kept" }
        var parts = [sp.seasonMonths.map(SportPlanEditor.seasonText) ?? "All year", sp.sport.loadLabel]
        if let e = sp.event { parts.append("Event \(e.formatted(.dateTime.day().month(.abbreviated)))") }
        return parts.joined(separator: " · ")
    }

    private func update(_ sport: Sport, _ change: (inout SportPlan) -> Void) {
        guard var all = profile.sports, let i = all.firstIndex(where: { $0.sport == sport }) else { return }
        change(&all[i])
        profile.sports = all
    }

    private func firstFree(_ list: [SportPlan]) -> Sport {
        Sport.allCases.first { s in s != .climbing && !list.contains { $0.sport == s } } ?? .other
    }
}

/// One sport card of Your week: icon, name, switch, and the week's days as dots to tap.
struct SportDayCard<Extra: View>: View {
    let sport: Sport
    let title: String
    let detail: String
    @Binding var on: Bool
    @Binding var days: [Int]
    /// Opens the sport's details (season, event, days around it); nil = no details.
    let tapCard: (() -> Void)?
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { tapCard?() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: sport.symbol).font(.system(size: 17, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(title).font(Theme.display(17)).lineLimit(1)
                                if tapCard != nil { Image(systemName: "chevron.right").font(.caption.bold()).opacity(0.7) }
                            }
                            Text(detail).font(Theme.label(11)).opacity(0.85).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(tapCard == nil)
                .accessibilityLabel("\(title), \(detail)")
                Toggle("", isOn: $on).labelsHidden().tint(Theme.lime)
                    .accessibilityLabel("\(title) on")
            }
            if on {
                HStack(spacing: 5) {
                    ForEach(WeekSchedule.weekdays, id: \.self) { d in
                        let picked = days.contains(d)
                        Button {
                            if picked { days.removeAll { $0 == d } } else { days = (days + [d]).sorted() }
                        } label: {
                            Text(WeekSchedule.initial(d)).font(Theme.label(13))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(picked ? Theme.ink : .white)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(picked ? AnyShapeStyle(Color.white) : AnyShapeStyle(.black.opacity(0.25))))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title) on \(WeekSchedule.name(d))")
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
                extra()
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(sport.gradient))
        .opacity(on ? 1 : 0.7)
        .animation(.snappy, value: on)
    }
}
