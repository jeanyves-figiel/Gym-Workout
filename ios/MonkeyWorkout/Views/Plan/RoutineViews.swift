import SwiftUI
import WorkoutEngine

// Daily routines (#689, designs A + B from `daily-routines/proposals.png`): A, two daily tiles under Next up on Train;
// B, every routine in Explore → Daily. Both pick a length with chips (remembered) and open the routine's session.
// #732 (`daily-routines/v2`, A + C): more built-ins, the member's own routines, and an add card under the day card.

extension Routine {
    /// Own colour per routine, borrowed from the category palette.
    var gradient: LinearGradient {
        switch self {
        case .stretch: WorkoutEngine.Category.stretch.gradient
        case .hangs: WorkoutEngine.Category.power.gradient
        case .morning: WorkoutEngine.Category.mobility.gradient
        case .desk: WorkoutEngine.Category.warmup.gradient
        case .bedtime: WorkoutEngine.Category.cardio.gradient
        case .hips: Theme.routineGradient(0)
        case .shoulders: Theme.routineGradient(1)
        case .rollout: Theme.routineGradient(2)
        case .legs: Theme.routineGradient(3)
        case .wrists: Theme.routineGradient(4)
        case .splits: Theme.routineGradient(5)
        }
    }
}

extension DailyRoutine {
    var gradient: LinearGradient { builtIn?.gradient ?? Theme.routineGradient(mine?.routine?.color ?? 0) }
}

/// Length chips (5′ 10′ 20′ …); the picked one is white. One length (an own routine): nothing to pick.
struct RoutineLengthChips: View {
    let lengths: [Int]
    let selected: Int
    var onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if lengths.count > 1 {
                ForEach(lengths, id: \.self) { m in
                    SelectChip(title: "\(m)′", on: m == selected, offFill: AnyShapeStyle(.black.opacity(0.22)), offInk: .white,
                               height: 28, fills: false) { onPick(m) }
                        .accessibilityLabel("\(m) minutes")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Square-cornered icon tile used on routine cards.
struct RoutineIcon: View {
    let symbol: String
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).fill(.white.opacity(0.22)))
    }
}

/// Sheets the Daily row and the add cards open.
enum DailySheet: Identifiable {
    case pick, build, edit(CustomWorkout)

    var id: String {
        switch self {
        case .pick: "pick"
        case .build: "build"
        case .edit(let w): w.id.uuidString
        }
    }
}

// MARK: A · Daily row on Train

/// Two square daily tiles under Next up, on every day type. Long press: swap for another routine or hide the row.
/// Nothing picked yet: the Add daily routines card (#732 A); after that, on days with nothing on Daily, Coach pick (C).
struct DailyRoutinesRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(RoutinePrefs.tilesKey) private var tilesRaw = ""
    @AppStorage(RoutinePrefs.lengthsKey) private var lengthsRaw = ""
    @AppStorage(RoutinePrefs.placesKey) private var placesRaw = ""
    @AppStorage(RoutinePrefs.offerKey) private var offer = ""
    @AppStorage(RoutinePrefs.coachKey) private var coachRaw = ""
    @State private var sheet: DailySheet?

    var body: some View {
        let tiles = model.dailyTiles(tilesRaw)
        Group {
            if !tiles.isEmpty {
                row(tiles)
            } else if tilesRaw != "off" {
                if offer != "dismissed" && model.usedRoutines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily").eyebrow()
                        DailyStarterCard(starters: Routine.starters(climber: model.isClimber), count: model.dailyRoutines.count,
                                         add: { tilesRaw = RoutinePrefs.pinning(tilesRaw, $0.rawValue) },
                                         open: { sheet = $0 }, close: closeStarter)
                    }
                } else if RoutinePrefs.coachOffers(coachRaw, today: today) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily").eyebrow()
                        CoachRoutineCard(open: { sheet = $0 }, close: closeCoach)
                    }
                }
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .pick:
                DailyRoutinePicker(initial: tiles.isEmpty ? Routine.dailyDefaults(climber: model.isClimber).map(\.rawValue) : tiles.map(\.key))
            case .build: MyRoutineEditor(initial: CustomWorkout(name: "", routine: RoutineLook()), addsToDaily: true)
            case .edit(let w): MyRoutineEditor(initial: w)
            }
        }
    }

    private var today: Int { RoutinePrefs.dayNumber(Date(), calendar: model.planCalendar) }

    /// Closed at once (#539); Undo brings the card back.
    private func closeStarter() {
        withAnimation(.snappy) { offer = "dismissed" }
        UndoCloseCenter.shared.deleted("Daily card closed", detail: "Explore → Daily adds one any time", symbol: "eye.slash.fill") {
            UserDefaults.standard.set("", forKey: RoutinePrefs.offerKey)
        }
    }

    /// Not today; the third close stops Coach pick (#732 C).
    private func closeCoach() {
        let before = coachRaw
        let next = RoutinePrefs.closingCoach(coachRaw, today: today)
        withAnimation(.snappy) { coachRaw = next }
        let stopped = !RoutinePrefs.coachOffers(next, today: today + 1)
        UndoCloseCenter.shared.deleted(stopped ? "Coach pick stopped" : "Coach pick hidden for today",
                                       detail: "Explore → Daily adds one any time", symbol: "eye.slash.fill") {
            UserDefaults.standard.set(before, forKey: RoutinePrefs.coachKey)
        }
    }

    private func row(_ tiles: [DailyRoutine]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily").eyebrow()
            HStack(alignment: .top, spacing: 12) {
                ForEach(tiles) { r in
                    tile(r, others: model.dailyRoutines.filter { !tiles.contains($0) })
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ r: DailyRoutine, others: [DailyRoutine]) -> some View {
        let minutes = RoutinePrefs.length(lengthsRaw, r)
        let done = model.routineDoneToday(r.key)
        let streak = model.routineStreak(r.key)
        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: r.sessionId(minutes: minutes)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        RoutineIcon(symbol: done ? "checkmark" : r.symbol)
                        Spacer(minLength: 4)
                        if streak > 0 {
                            Label("\(streak)", systemImage: "flame.fill")
                                .font(Theme.label(11)).labelStyle(.titleAndIcon)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.25)))
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
            .accessibilityHint(streak > 0 ? "\(streak) days in a row" : "Opens it")
            Spacer(minLength: 0)
            // Half-width tile: three lengths (the picked one always among them); Explore offers all.
            if r.lengths.count > 1 {
                RoutineLengthChips(lengths: r.tileLengths(minutes), selected: minutes) {
                    lengthsRaw = RoutinePrefs.setting(lengthsRaw, r.key, to: $0)
                }
            } else {
                Text("\(minutes)′").font(Theme.display(20)).monospacedDigit()
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
                    Button(p.label, systemImage: RoutinePrefs.place(placesRaw, r.key) == p ? "checkmark" : p.symbol) {
                        placesRaw = RoutinePrefs.setting(placesRaw, r.key, place: p)
                    }
                }
            }
            Menu("Swap for…", systemImage: "arrow.left.arrow.right") {
                ForEach(others) { o in
                    Button(o.label, systemImage: o.symbol) {
                        tilesRaw = RoutinePrefs.pinning(tilesRaw, o.key, replacing: r.key, used: model.usedRoutines, known: known)
                    }
                }
            }
            if let w = r.mine {
                Button("Edit routine", systemImage: "pencil") { sheet = .edit(w) }
            }
            Button("Choose Daily…", systemImage: "square.grid.2x2") { sheet = .pick }
            Button("Build my own…", systemImage: "plus.square.on.square") { sheet = .build }
            Button("Remove from Daily", systemImage: "minus.circle") {
                change(to: RoutinePrefs.removing(tilesRaw, r.key, used: model.usedRoutines, known: known), "\(r.short) removed from Daily")
            }
            Button("Hide Daily", systemImage: "eye.slash") { change(to: "off", "Daily hidden") }
        }
    }

    private func known(_ key: String) -> Bool { model.dailyRoutine(key) != nil }

    /// Remove and Hide happen at once (#717); the Undo bar puts the row back as it was.
    private func change(to raw: String, _ title: String) {
        let before = tilesRaw
        withAnimation(.snappy) { tilesRaw = raw }
        UndoCloseCenter.shared.deleted(title, symbol: "eye.slash.fill") {
            UserDefaults.standard.set(before, forKey: RoutinePrefs.tilesKey)
        }
    }

    private func detail(_ r: DailyRoutine, done: Bool) -> String {
        if done { return "Done today · again?" }
        if r.builtIn == .hangs && model.climbingToday { return "Climb day · keep it easy" }
        // Where (#700): home, or today's gym by name.
        switch RoutinePrefs.place(placesRaw, r.key) {
        case .home: return "At home · \(r.tag)"
        case .gym: return "At \(model.placeName(onWeekday: model.todayWeekday)) · \(r.tag)"
        case .anywhere: return r.tag
        }
    }
}

/// White square + button on a gradient card.
private struct PlusTile: View {
    var tint: Color

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
    }
}

/// Full-width action on a gradient card: white (main) or dark glass.
private struct CardAction: View {
    let title: String
    let symbol: String
    var main = false
    var tint: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(main ? tint : .white)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(main ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.25))))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// ✕ on a card's top-right corner.
private struct CardClose: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .heavy))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.3)))
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }
}

/// #732 A: three tailored routines to add in one tap, See all, Build my own; ✕ closes it.
struct DailyStarterCard: View {
    let starters: [Routine]
    let count: Int
    let add: (Routine) -> Void
    let open: (DailySheet) -> Void
    let close: () -> Void

    private static let gradient = LinearGradient(colors: Theme.routinePalette[5] + Theme.routinePalette[1].suffix(1),
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoutineIcon(symbol: Routine.stretch.symbol, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add daily routines").font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("5–10 min · builds a streak").font(Theme.label(10)).tracking(1.1).textCase(.uppercase).opacity(0.9)
                }
                Spacer(minLength: 36)
            }
            HStack(spacing: 8) {
                ForEach(starters) { r in
                    Button { withAnimation(.snappy) { add(r) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RoutineIcon(symbol: r.symbol, size: 30)
                            Text(r.short).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                            PlusTile(tint: Theme.routinePalette[5][0])
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(r.gradient))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(r.label) to Daily")
                    .accessibilityIdentifier("daily.starter.\(r.rawValue)")
                }
            }
            HStack(spacing: 8) {
                CardAction(title: "See all \(count)", symbol: "square.grid.2x2.fill", main: true, tint: Theme.routinePalette[5][0]) { open(.pick) }
                    .accessibilityIdentifier("daily.suggest")
                CardAction(title: "Build my own", symbol: "plus") { open(.build) }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.gradient))
        .overlay(alignment: .topTrailing) { CardClose(label: "Not now", action: close).accessibilityIdentifier("daily.suggest.close") }
    }
}

/// #732 C: one routine matched to today (pull → shoulders, leg day → hips, rest → roll out, climb → wrists).
struct CoachRoutineCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(RoutinePrefs.tilesKey) private var tilesRaw = ""
    @AppStorage(RoutinePrefs.lengthsKey) private var lengthsRaw = ""
    let open: (DailySheet) -> Void
    let close: () -> Void

    var body: some View {
        let pick = model.coachRoutinePick
        let r = DailyRoutine(pick.routine)
        let minutes = RoutinePrefs.length(lengthsRaw, r)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MonkeyFace(mood: .happy, scale: 0.4)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach pick · \(pick.why)").font(Theme.label(10)).tracking(1).textCase(.uppercase).opacity(0.9)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(r.label).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    // ′ in the number's own font: a small label-font ′ read as a clipped comma, "10," (#823).
                    Text("\(minutes)′").font(Theme.display(30)).monospacedDigit()
                }
                .padding(.trailing, 30)
            }
            RoutineLengthChips(lengths: r.lengths, selected: minutes) { lengthsRaw = RoutinePrefs.setting(lengthsRaw, r.key, to: $0) }
            HStack(spacing: 8) {
                CardAction(title: "Make it daily", symbol: "plus", main: true, tint: Theme.routinePalette[1][1]) {
                    withAnimation(.snappy) { tilesRaw = RoutinePrefs.pinning(tilesRaw, r.key) }
                }
                .accessibilityIdentifier("daily.coach.add")
                NavigationLink(value: r.sessionId(minutes: minutes)) {
                    Label("Just today", systemImage: "play.fill")
                        .font(Theme.label(13)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                CardAction(title: "Other routines", symbol: "square.grid.2x2.fill") { open(.pick) }
                CardAction(title: "Build my own", symbol: "plus") { open(.build) }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(r.gradient))
        .overlay(alignment: .topTrailing) { CardClose(label: "Not today", action: close).accessibilityIdentifier("daily.coach.close") }
    }
}

/// Pick up to two routines for Train's Daily row (#696 B), each with its length; Build my own makes a new one (#732).
struct DailyRoutinePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RoutinePrefs.tilesKey) private var tilesRaw = ""
    @AppStorage(RoutinePrefs.lengthsKey) private var lengthsRaw = ""
    @State private var picked: [String]
    @State private var building = false

    init(initial: [String]) { _picked = State(initialValue: Array(initial.prefix(2))) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick up to two. They sit on Train every day.")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(model.dailyRoutines) { tile($0) }
                        buildTile
                    }
                    ForEach(picked.compactMap(model.dailyRoutine)) { r in
                        let minutes = RoutinePrefs.length(lengthsRaw, r)
                        HStack(spacing: 8) {
                            Text(r.short).font(Theme.label(13)).lineLimit(1)
                            Spacer(minLength: 4)
                            RoutineLengthChips(lengths: r.tileLengths(minutes), selected: minutes) {
                                lengthsRaw = RoutinePrefs.setting(lengthsRaw, r.key, to: $0)
                            }
                        }
                    }
                    Button {
                        tilesRaw = RoutinePrefs.choosing(picked.filter { model.dailyRoutine($0) != nil })
                        dismiss()
                    } label: {
                        Text(saveTitle)
                            .font(Theme.label(16)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("daily.pick.save")
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Daily")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(isPresented: $building) {
                MyRoutineEditor(initial: CustomWorkout(name: "", routine: RoutineLook())) { w in toggle(w.sessionId) }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private var saveTitle: String {
        if picked.isEmpty { return "Hide Daily" }
        if picked.count == 2 { return "Add 2 to Train" }
        return "Add \(model.dailyRoutine(picked[0])?.short ?? "1") to Train"
    }

    private func toggle(_ key: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if let i = picked.firstIndex(of: key) { picked.remove(at: i) }
            else { if picked.count == 2 { picked.removeFirst() }; picked.append(key) }
        }
    }

    private func tile(_ r: DailyRoutine) -> some View {
        let on = picked.contains(r.key)
        return Button { toggle(r.key) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: r.symbol).font(.system(size: 18, weight: .bold))
                Spacer(minLength: 0)
                Text(r.short).font(Theme.label(12)).lineLimit(2).minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(r.gradient))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white, lineWidth: on ? 3 : 0))
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.ink)
                        .frame(width: 18, height: 18)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white))
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var buildTile: some View {
        Button { building = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "plus").font(.system(size: 18, weight: .heavy))
                Spacer(minLength: 0)
                Text("Build my own").font(Theme.label(12)).lineLimit(2).minimumScaleFactor(0.75)
            }
            .foregroundStyle(Theme.lime)
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("daily.pick.build")
    }
}

// MARK: B · Explore → Daily

/// Every routine with its lengths; Show on Train puts it on the daily row. Mine: the member's own (#732).
struct RoutineLibrarySection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(RoutinePrefs.tilesKey) private var tilesRaw = ""
    @AppStorage(RoutinePrefs.lengthsKey) private var lengthsRaw = ""
    @AppStorage(RoutinePrefs.placesKey) private var placesRaw = ""
    @State private var filter: Filter = .all
    @State private var sheet: DailySheet?

    enum Filter: Hashable { case all, kind(Routine.Kind), mine }

    var body: some View {
        let onTrain = model.dailyTiles(tilesRaw).map(\.key)
        VStack(alignment: .leading, spacing: 12) {
            Text("Short Daily sessions for any day. Pick a length; the session fits it.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(.all, "All")
                    chip(.kind(.stretch), "Stretch")
                    chip(.kind(.hang), "Hang")
                    chip(.kind(.mobility), "Mobility")
                    chip(.kind(.recovery), "Recovery")
                    chip(.mine, "Mine")
                }
            }
            .scrollClipDisabled()
            ForEach(shown) { r in
                card(r, onTrain: onTrain.contains(r.key))
            }
            if filter == .all || filter == .mine {
                newRoutineButton
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .pick, .build: MyRoutineEditor(initial: CustomWorkout(name: "", routine: RoutineLook()))
            case .edit(let w): MyRoutineEditor(initial: w)
            }
        }
    }

    private var shown: [DailyRoutine] {
        model.dailyRoutines.filter { r in
            switch filter {
            case .all: true
            case .kind(let k): r.builtIn?.kind == k
            case .mine: r.mine != nil
            }
        }
    }

    private func chip(_ f: Filter, _ label: String) -> some View {
        SelectChip(title: label, on: filter == f, height: 34, fills: false) { withAnimation(.snappy(duration: 0.25)) { filter = f } }
    }

    private var newRoutineButton: some View {
        Button { sheet = .build } label: {
            Label("New routine", systemImage: "plus.circle.fill")
                .font(Theme.label(15))
                .foregroundStyle(Theme.lime)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("routines.new")
    }

    private func known(_ key: String) -> Bool { model.dailyRoutine(key) != nil }

    private func card(_ r: DailyRoutine, onTrain: Bool) -> some View {
        let minutes = RoutinePrefs.length(lengthsRaw, r)
        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: r.sessionId(minutes: minutes)) {
                HStack(spacing: 12) {
                    RoutineIcon(symbol: r.symbol, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(r.tag).font(Theme.label(10)).tracking(1.1).textCase(.uppercase).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        // ′ in the number's own font: a small label-font ′ read as a clipped comma, "10," (#823).
                        Text("\(minutes)′").font(Theme.display(30)).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(r.label), \(minutes) minutes")
            HStack(spacing: 8) {
                RoutineLengthChips(lengths: r.lengths, selected: minutes) { lengthsRaw = RoutinePrefs.setting(lengthsRaw, r.key, to: $0) }
                Spacer(minLength: 0)
                if let w = r.mine {
                    Menu {
                        mineActions(w)
                    } label: {
                        smallButton("ellipsis")
                    }
                    .accessibilityLabel("Routine actions")
                }
                // Where (#700, design C).
                let place = RoutinePrefs.place(placesRaw, r.key)
                Menu {
                    ForEach(RoutinePlace.allCases) { p in
                        Button(p.label, systemImage: place == p ? "checkmark" : p.symbol) {
                            placesRaw = RoutinePrefs.setting(placesRaw, r.key, place: p)
                        }
                    }
                } label: {
                    smallButton(place.symbol)
                }
                .accessibilityLabel("Where: \(place.label)")
                // Toggles (#703): tap again takes it off Train's Daily row.
                Button {
                    tilesRaw = onTrain ? RoutinePrefs.removing(tilesRaw, r.key, used: model.usedRoutines, known: known)
                                       : RoutinePrefs.pinning(tilesRaw, r.key, used: model.usedRoutines, known: known)
                } label: {
                    smallButton(onTrain ? "checkmark" : "pin.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(onTrain ? "Remove from Daily" : "Show on Train")
                .accessibilityAddTraits(onTrain ? .isSelected : [])
            }
            if r.builtIn == .hangs {
                Text(Routine.hangIntensity).font(Theme.label(11)).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(r.gradient))
        .contextMenu {
            if let w = r.mine { mineActions(w) }
        }
    }

    @ViewBuilder
    private func mineActions(_ w: CustomWorkout) -> some View {
        Button("Edit", systemImage: "pencil") { sheet = .edit(w) }
        Button("Duplicate", systemImage: "plus.square.on.square") { sheet = .edit(w.duplicated()) }
        Button("Delete", systemImage: "trash", role: .destructive) { delete(w) }
    }

    private func smallButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .frame(width: 44, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.22)))
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }

    /// Deleted at once (#539); Undo saves it back. Past sessions stay in history.
    private func delete(_ w: CustomWorkout) {
        model.deleteCustomWorkout(w.id)
        UndoCloseCenter.shared.deleted("\(w.name) deleted", detail: "Past sessions stay in your history", symbol: "trash.fill") { [model] in
            model.saveCustomWorkout(w)
        }
    }
}
