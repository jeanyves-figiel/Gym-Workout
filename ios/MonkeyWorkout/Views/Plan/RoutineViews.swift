import SwiftUI
import WorkoutEngine

// Daily routines (#689, designs A + B from `daily-routines/proposals.png`): A, two daily tiles under Next up on Train;
// B, every routine in Explore → Routines. Both pick a length with chips (remembered) and open the routine's session.

extension Routine {
    /// Own colour per routine, borrowed from the category palette.
    var gradient: LinearGradient {
        switch self {
        case .stretch: WorkoutEngine.Category.stretch.gradient
        case .hangs: WorkoutEngine.Category.power.gradient
        case .morning: WorkoutEngine.Category.mobility.gradient
        case .desk: WorkoutEngine.Category.warmup.gradient
        case .bedtime: WorkoutEngine.Category.cardio.gradient
        }
    }
}

/// Length chips (5′ 10′ 20′ …); the picked one is white.
struct RoutineLengthChips: View {
    let routine: Routine
    let selected: Int
    /// Lengths to offer; nil = all of the routine's.
    var lengths: [Int]? = nil
    var onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(lengths ?? routine.lengths, id: \.self) { m in
                let on = m == selected
                Button { onPick(m) } label: {
                    Text("\(m)′")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(on ? Theme.ink : .white)
                        .frame(minWidth: 30, minHeight: 28)
                        .padding(.horizontal, 2)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Color.white : Color.black.opacity(0.22)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(m) minutes")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: A · Daily row on Train

/// Two square daily tiles under Next up, on every day type. Long press: swap for another routine or hide the row.
struct DailyRoutinesRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(RoutinePrefs.tilesKey) private var tilesRaw = ""
    @AppStorage(RoutinePrefs.lengthsKey) private var lengthsRaw = ""
    @AppStorage(RoutinePrefs.placesKey) private var placesRaw = ""

    var body: some View {
        let tiles = RoutinePrefs.tiles(tilesRaw, climber: model.isClimber)
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily").eyebrow()
                HStack(alignment: .top, spacing: 12) {
                    ForEach(tiles) { r in
                        tile(r, others: Routine.allCases.filter { !tiles.contains($0) })
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tile(_ r: Routine, others: [Routine]) -> some View {
        let minutes = RoutinePrefs.length(lengthsRaw, r)
        let done = model.routineDoneToday(r)
        let streak = model.routineStreak(r)
        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: r.template(minutes: minutes).sessionId) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Image(systemName: done ? "checkmark" : r.symbol)
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                        Spacer(minLength: 4)
                        if streak > 0 {
                            Label("\(streak)", systemImage: "flame.fill")
                                .font(Theme.label(11)).labelStyle(.titleAndIcon)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.25)))
                        }
                    }
                    Text(r.short).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail(r, done: done)).font(Theme.label(11)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(r.label), \(minutes) minutes\(done ? ", done today" : "")")
            .accessibilityHint(streak > 0 ? "\(streak) days in a row" : "Opens the routine")
            Spacer(minLength: 0)
            // Half-width tile: three lengths (the picked one always among them); Explore offers all.
            RoutineLengthChips(routine: r, selected: minutes, lengths: r.tileLengths(minutes)) {
                lengthsRaw = RoutinePrefs.setting(lengthsRaw, r, to: $0)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(r.gradient).opacity(done ? 0.7 : 1))
        .contextMenu {
            // Where it happens (#700, design C): home, the day's gym or anywhere.
            Menu("Where", systemImage: "mappin.and.ellipse") {
                ForEach(RoutinePlace.allCases) { p in
                    Button(p.label, systemImage: RoutinePrefs.place(placesRaw, r) == p ? "checkmark" : p.symbol) {
                        placesRaw = RoutinePrefs.setting(placesRaw, r, place: p)
                    }
                }
            }
            Menu("Swap for…", systemImage: "arrow.left.arrow.right") {
                ForEach(others) { o in
                    Button(o.label, systemImage: o.symbol) {
                        tilesRaw = RoutinePrefs.pinning(tilesRaw, o, replacing: r, climber: model.isClimber)
                    }
                }
            }
            Button("Hide daily row", systemImage: "eye.slash") { tilesRaw = "off" }
        }
    }

    private func detail(_ r: Routine, done: Bool) -> String {
        if done { return "Done today · again?" }
        if r == .hangs && model.climbingToday { return "Climb day · keep it easy" }
        // Where (#700): home, or today's gym by name.
        switch RoutinePrefs.place(placesRaw, r) {
        case .home: return "At home · \(r.tag)"
        case .gym: return "At \(model.placeName(onWeekday: model.todayWeekday)) · \(r.tag)"
        case .anywhere: return r.tag
        }
    }
}

extension Routine {
    /// Up to three lengths for a half-width tile, around the picked one.
    func tileLengths(_ picked: Int) -> [Int] {
        guard lengths.count > 3, let i = lengths.firstIndex(of: picked) else { return Array(lengths.prefix(3)) }
        let start = min(max(i - 1, 0), lengths.count - 3)
        return Array(lengths[start..<(start + 3)])
    }
}

// MARK: B · Explore → Routines

/// Every routine with its lengths; Show on Train puts it on the daily row.
struct RoutineLibrarySection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(RoutinePrefs.tilesKey) private var tilesRaw = ""
    @AppStorage(RoutinePrefs.lengthsKey) private var lengthsRaw = ""
    @AppStorage(RoutinePrefs.placesKey) private var placesRaw = ""
    @State private var filter: Routine.Kind?

    var body: some View {
        let onTrain = RoutinePrefs.tiles(tilesRaw, climber: model.isClimber)
        VStack(alignment: .leading, spacing: 12) {
            Text("Short routines for any day. Pick a length; the routine fits it.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                chip(nil, "All")
                chip(.stretch, "Stretch")
                chip(.hang, "Hang")
                chip(.mobility, "Mobility")
            }
            ForEach(Routine.allCases.filter { filter == nil || $0.kind == filter }) { r in
                card(r, onTrain: onTrain.contains(r))
            }
        }
    }

    private func chip(_ k: Routine.Kind?, _ label: String) -> some View {
        let on = filter == k
        return Button { withAnimation(.snappy(duration: 0.25)) { filter = k } } label: {
            Text(label).font(Theme.label(13))
                .foregroundStyle(on ? Theme.ink : .white.opacity(0.85))
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.white : Theme.card))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func card(_ r: Routine, onTrain: Bool) -> some View {
        let minutes = RoutinePrefs.length(lengthsRaw, r)
        let t = r.template(minutes: minutes)
        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: t.sessionId) {
                HStack(spacing: 12) {
                    Image(systemName: r.symbol)
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(r.tag).font(Theme.label(10)).tracking(1.1).textCase(.uppercase).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(minutes)").font(Theme.display(30)).monospacedDigit()
                        Text("′").font(Theme.label(14))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(r.label), \(minutes) minutes")
            HStack(spacing: 8) {
                RoutineLengthChips(routine: r, selected: minutes) { lengthsRaw = RoutinePrefs.setting(lengthsRaw, r, to: $0) }
                Spacer(minLength: 0)
                // Where (#700, design C).
                let place = RoutinePrefs.place(placesRaw, r)
                Menu {
                    ForEach(RoutinePlace.allCases) { p in
                        Button(p.label, systemImage: place == p ? "checkmark" : p.symbol) {
                            placesRaw = RoutinePrefs.setting(placesRaw, r, place: p)
                        }
                    }
                } label: {
                    Image(systemName: place.symbol)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.22)))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Where: \(place.label)")
                Button {
                    tilesRaw = RoutinePrefs.pinning(tilesRaw == "off" ? "" : tilesRaw, r, climber: model.isClimber)
                } label: {
                    Image(systemName: onTrain ? "checkmark" : "pin.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.22)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onTrain)
                .accessibilityLabel(onTrain ? "On Train" : "Show on Train")
            }
            if r == .hangs {
                Text(Routine.hangIntensity).font(Theme.label(11)).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(r.gradient))
    }
}
