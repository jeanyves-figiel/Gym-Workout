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
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(on ? 1 : 0.6))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? AnyShapeStyle(fill) : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The day's combo (#685, design A + B's Coach note)

/// On a workout day card: the day's parts in the order to do them (lift at its gym, then the planned run, then
/// climbing) and what the planner changed so they fit together.
struct DayComboRow: View {
    let session: Session
    let day: Int
    /// The current week: its runs apply.
    let thisWeek: Bool
    var showNote = true
    @Environment(AppModel.self) private var model

    private var run: RunWorkout? { thisWeek ? model.runWeek.first { $0.weekday == day }?.workout : nil }
    private var climbs: Bool { model.profile?.climbingDays.contains(day) ?? false }

    var body: some View {
        if session.place != nil || run != nil || climbs {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        part(1, session.place.map { "Lift · \($0)" } ?? "Lift", "dumbbell.fill", WorkoutEngine.Category.strength.colors)
                        if let run { part(2, "\(run.title) \(run.minutes)′", run.symbol, WorkoutEngine.Category.cardio.colors) }
                        if climbs { part(run == nil ? 2 : 3, "Climb", "figure.climbing", WorkoutEngine.Category.power.colors) }
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
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("train.dayCombo")
        }
    }

    private func part(_ n: Int, _ title: String, _ symbol: String, _ colors: [Color]) -> some View {
        HStack(spacing: 5) {
            Text("\(n)").font(Theme.label(11)).frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.25)))
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            Text(title).font(Theme.label(11)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
    }
}

// MARK: - Today's place (#700, design A)

/// On a workout day card: where the day happens ("📍 Puls 5 ▾"). The menu moves just this day, or this weekday
/// every week, to another saved gym; the workout is rebuilt for that gym's kit, same session type.
struct PlaceMenuChip: View {
    let weekday: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = model.placeId(onWeekday: weekday)
        let day = WeekSchedule.name(weekday)
        Menu {
            Section("Just this \(day)") {
                ForEach(model.placeChoices) { g in
                    Button { model.setPlaceToday(g.id, onWeekday: weekday) } label: { choice(g, on: g.id == current) }
                }
            }
            Section("Every \(day)") {
                ForEach(model.placeChoices) { g in
                    Button { model.setPlaceEveryWeek(g.id, onWeekday: weekday) } label: {
                        choice(g, on: g.id == (model.profile?.place(onWeekday: weekday) ?? model.homeGym.id))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 11, weight: .bold))
                Text(model.placeName(onWeekday: weekday)).font(Theme.label(12)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.28)))
        }
        .accessibilityLabel("Where on \(day): \(model.placeName(onWeekday: weekday))")
        .accessibilityIdentifier("train.placeChip")
    }

    private func choice(_ g: SavedGym, on: Bool) -> some View {
        Label(g.ref.name, systemImage: on ? "checkmark" : g.kind?.symbol ?? (g.isPlace ? "dumbbell.fill" : "house.fill"))
    }
}
