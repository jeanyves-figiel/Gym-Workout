import SwiftUI
import WorkoutEngine

// MARK: - Where I train (#684, design A)

/// One row per weekday: the gym the member lifts at that day (one of their saved gyms, tap again for none) and
/// climbing. Picking a gym makes the day a gym day; the planner builds that day's workout for that gym's kit.
struct WeekPlacesEditor: View {
    @Binding var profile: Profile
    @Binding var climbingDays: [Int]
    let gyms: [SavedGym]
    /// Climbing chip on each day (members who climb).
    var showClimb = true

    private var ownId: String { profile.gym?.id ?? Gym.puls5.ref.id }

    /// The gym of `day`: its place, else the plan's gym on a gym day.
    private func gymId(_ day: Int) -> String? {
        if profile.dayPlaces != nil { return profile.place(onWeekday: day) }
        return profile.gymWeekdays?.contains(day) == true ? ownId : nil
    }

    private func pick(_ id: String, _ day: Int) {
        // First pick: the gym days picked so far start at the plan's gym.
        if profile.dayPlaces == nil {
            for d in profile.gymWeekdays ?? [] { profile.setPlace(ownId, onWeekday: d) }
        }
        profile.setPlace(gymId(day) == id ? nil : id, onWeekday: day)
        if profile.dayPlaces == nil { profile.gymWeekdays = nil }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(WeekSchedule.weekdays, id: \.self) { d in
                HStack(spacing: 6) {
                    Text(String(WeekSchedule.name(d).prefix(3)))
                        .font(Theme.label(12)).foregroundStyle(.white.opacity(0.85))
                        .frame(width: 34, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(gyms) { g in
                                PlaceChip(title: g.ref.name, symbol: g.kind?.symbol ?? (g.isPlace ? "dumbbell.fill" : "house.fill"),
                                          fill: (g.kind?.category ?? .strength).gradient, on: gymId(d) == g.id) { pick(g.id, d) }
                            }
                            if showClimb {
                                PlaceChip(title: "Climb", symbol: "figure.climbing", fill: WorkoutEngine.Category.power.gradient,
                                          on: climbingDays.contains(d)) {
                                    if climbingDays.contains(d) { climbingDays.removeAll { $0 == d } } else { climbingDays = (climbingDays + [d]).sorted() }
                                }
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(WeekSchedule.name(d))
            }
        }
        .accessibilityIdentifier("profile.weekPlaces")
    }
}

private struct PlaceChip: View {
    let title: String
    let symbol: String
    let fill: LinearGradient
    let on: Bool
    let action: () -> Void

    var body: some View {
        SelectChip(title: title, symbol: symbol, on: on, onFill: AnyShapeStyle(fill), offFill: AnyShapeStyle(Theme.cardStrong),
                   onInk: .white, offInk: .white.opacity(0.6), size: 12, height: 30, fills: false, action: action)
    }
}

// MARK: - The day's combo (#685, design A + B's Coach note)

/// On a workout day card: the day's parts in the order to do them (lift at its gym, then the planned run, then
/// climbing) and what the planner changed so they fit together. The day line (#758, design A): every workout of the
/// day (tap one to show it in the card), any sport and the daily routines (tap to open).
struct DayComboRow: View {
    let session: Session
    let day: Int
    /// The current week: its runs apply.
    let thisWeek: Bool
    var showNote = true
    /// False when the card's eyebrow already names the place (#717, design 1A): the lift part reads "Lift".
    var showPlace = true
    /// Every workout of the day in order, the shown one included (#758); empty = just `session`.
    var daySessions: [Session] = []
    /// Shows another workout of the day in the card (#758).
    var onSelect: ((Session) -> Void)? = nil
    /// Day key ("2026-10-26") for a dated sport day or trip (#758); nil = the weekly sport days only.
    var dayKey: String? = nil
    /// Daily routines as parts too (#758): coming days, not today (Train's Daily row has them).
    var routines = false
    /// The sport part as a menu (#947): Track live (today) and Log; nil = not offered (a coming day).
    var onSportTrack: ((Sport) -> Void)? = nil
    var onSportLog: ((Sport) -> Void)? = nil
    @State private var link = WatchLink.shared
    @Environment(AppModel.self) private var model
    @AppStorage(RoutinePrefs.tilesKey) private var tilesRaw = ""
    @AppStorage(RoutinePrefs.lengthsKey) private var lengthsRaw = ""

    private var run: RunWorkout? { thisWeek ? model.runWeek.first { $0.weekday == day }?.workout : nil }
    /// The day's sport (#758): a dated sport day or trip, else the weekly climbing or sport day.
    private var sport: Sport? {
        let date = dayKey.flatMap { PlanCalendar.date($0, model.planCalendar) } ?? Date()
        return model.daySport(onWeekday: day, key: dayKey, date: date)
    }
    private var sessions: [Session] { daySessions.isEmpty ? [session] : daySessions }

    var body: some View {
        let sessions = self.sessions
        let sport = self.sport
        let tiles = routines ? model.dailyTiles(tilesRaw) : []
        // A lone HIIT day shows its blocks (#757); otherwise each workout is one part.
        let hiitBlocks = sessions.count == 1 ? session.hiit : nil
        if sessions.count > 1 || session.hiit != nil || session.place != nil || run != nil || sport != nil || !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let hiit = hiitBlocks {
                            // A HIIT day (#757, design A2): its blocks, not "Lift".
                            ForEach(Array(Self.hiitParts(hiit).enumerated()), id: \.offset) { _, p in block(p.title, p.format.symbol) }
                        } else {
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                                let face = workoutPart(i + 1, s, many: sessions.count > 1)
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(.white, lineWidth: sessions.count > 1 && s.id == session.id ? 2 : 0))
                                if sessions.count > 1, let onSelect {
                                    Button { withAnimation(.snappy) { onSelect(s) } } label: { face }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Shows it in the card")
                                } else {
                                    face
                                }
                            }
                        }
                        let n = hiitBlocks == nil ? sessions.count : 0
                        if let run { part(n + 1, "\(run.title) \(run.minutes)′", run.symbol, WorkoutEngine.Category.cardio.colors) }
                        if let sport {
                            let face = part(n + (run == nil ? 1 : 2), sport == .climbing ? "Climb" : sport.label, sport == .climbing ? "figure.climbing" : sport.symbol,
                                            sport == .climbing ? WorkoutEngine.Category.power.colors : sport.colors)
                            if onSportTrack != nil || onSportLog != nil {
                                // The day's sport is picked here too (#947): its own actions, not the gym session's page.
                                Menu { sportItems(sport) } label: { face }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Track or log \(sport.label.lowercased())")
                                    .accessibilityIdentifier("train.daySport")
                            } else {
                                face
                            }
                        }
                        ForEach(tiles) { r in
                            let minutes = RoutinePrefs.length(lengthsRaw, r)
                            NavigationLink(value: r.sessionId(minutes: minutes)) {
                                part(nil, "\(r.short) \(minutes)′", r.symbol, WorkoutEngine.Category.mobility.colors)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if showNote, let note = session.synergy {
                    Label(note, systemImage: "bolt.fill")
                        .font(Theme.label(11)).foregroundStyle(Theme.lime)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.lime.opacity(0.15)))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("train.dayCombo")
        }
    }

    /// Track live (a paired Watch, or climbing, which tracks on the iPhone too, #829) and Log.
    @ViewBuilder private func sportItems(_ sport: Sport) -> some View {
        if let onSportTrack, link.ready || sport == .climbing {
            let live = sport == .climbing && ClimbLive.shared.running
            Button { onSportTrack(sport) } label: {
                Label(live ? "Climbing live" : "Track live", systemImage: link.ready ? "applewatch.radiowaves.left.and.right" : "dot.radiowaves.left.and.right")
            }
        }
        if let onSportLog {
            Button { onSportLog(sport) } label: {
                Label(sport == .climbing ? "Log climb" : "Log \(sport.short.lowercased())", systemImage: "plus.circle.fill")
            }
        }
    }

    /// HIIT blocks in order, repeats of the same format and length merged: "Pyramid 4′ ×2", "EMOM 17′".
    static func hiitParts(_ w: HiitWorkout) -> [(format: HiitFormat, title: String)] {
        var out: [(format: HiitFormat, seconds: Int, count: Int)] = []
        for b in w.blocks {
            if let last = out.last, last.format == b.format, last.seconds == b.seconds {
                out[out.count - 1].count += 1
            } else {
                out.append((b.format, b.seconds, 1))
            }
        }
        return out.map { p in (p.format, "\(p.format.label) \(Hiit.short(max(60, p.seconds / 60 * 60)))" + (p.count > 1 ? " ×\(p.count)" : "")) }
    }

    private func block(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(title).font(Theme.label(11)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.28)))
    }

    /// A workout of the day: alone it reads "Lift" (or its type, #757) with the place; one of several (#758) shows
    /// its own name.
    private func workoutPart(_ n: Int, _ s: Session, many: Bool) -> some View {
        let lifts = s.blocks.contains { $0.kind == .strength }
        let symbol = s.hiit != nil ? "bolt.heart.fill" : lifts ? "dumbbell.fill" : s.focus.symbol
        let colors = s.hiit != nil ? Theme.hiitColors : (lifts ? WorkoutEngine.Category.strength : .cardio).colors
        let name = many ? (s.hiit.map { "HIIT · \($0.minutes)′" } ?? s.displayTitle) : lifts ? "Lift" : s.focus.dayLabel
        return part(n, s.place.flatMap { showPlace && !many ? "\(name) · \($0)" : nil } ?? name, symbol, colors)
    }

    private func part(_ n: Int?, _ title: String, _ symbol: String, _ colors: [Color]) -> some View {
        HStack(spacing: 5) {
            if let n {
                Text("\(n)").font(Theme.label(11)).frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.25)))
            }
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(title).font(Theme.label(11)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
    }
}

// MARK: - Today's place (#700, design A; #703: always there, Home built in, trips)

/// On a workout day card: where the day happens ("📍 Puls 5 ▾"). The menu moves just this day, or this weekday
/// every week, to another place; the workout is rebuilt for that place's kit, same session type. Home is always a
/// choice. On a travel day the trip sets the place (changed in Calendar).
/// Sits in the card's eyebrow line (#717, design 1A): "Next up · Today · 📍 Puls 5 ▾".
struct PlaceMenuChip: View {
    let weekday: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        let trip = model.tripThisWeek(weekday)
        let name = trip?.title ?? model.placeName(onWeekday: weekday)
        Menu {
            PlaceMenuItems(weekday: weekday)
        } label: {
            HStack(spacing: 4) {
                Text("·").opacity(0.8)
                Image(systemName: trip == nil ? "mappin.and.ellipse" : "airplane").font(.system(size: 11, weight: .bold))
                Text(name).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
            }
            .font(Theme.label(12)).tracking(1.4)
            .foregroundStyle(.white)
            // 44 pt to tap, no taller line (#752): the hit area reaches past the row, the layout doesn't.
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .padding(.vertical, -14)
        }
        .accessibilityLabel("Where on \(WeekSchedule.name(weekday)): \(name)")
        .accessibilityIdentifier("train.placeChip")
    }
}

/// The place choices for `weekday`: just this day or every week. Also in the day card's long-press menu.
struct PlaceMenuItems: View {
    let weekday: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        let day = WeekSchedule.name(weekday)
        if let trip = model.tripThisWeek(weekday) {
            // Travel (#68): the trip's kit plans this day; dates and kit are edited in Calendar.
            Section("Trip · \(trip.title)") {
                Text("This day is planned for the trip. Change it in Calendar.")
            }
        } else {
            let current = model.placeId(onWeekday: weekday)
            let weekly = model.profile?.place(onWeekday: weekday) ?? model.homeGym.id
            Section("Just this \(day)") {
                ForEach(model.placeChoices) { g in
                    Button { model.setPlaceToday(g.id, onWeekday: weekday) } label: { choice(g, on: g.id == current) }
                }
            }
            Section("Every \(day)") {
                ForEach(model.placeChoices) { g in
                    Button { model.setPlaceEveryWeek(g.id, onWeekday: weekday) } label: { choice(g, on: g.id == weekly) }
                }
            }
        }
    }

    private func choice(_ g: SavedGym, on: Bool) -> some View {
        Label(g.id == SavedGym.builtInHome.id ? "Home · bodyweight" : g.ref.name,
              systemImage: on ? "checkmark" : g.kind?.symbol ?? (g.isPlace ? "dumbbell.fill" : "house.fill"))
    }
}
