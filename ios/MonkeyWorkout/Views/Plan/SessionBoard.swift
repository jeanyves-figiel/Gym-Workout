import SwiftUI
import WorkoutEngine

// Workout page top (#766, design A by default, C to customise, from `session-wow/proposals.png` and
// `proposals-c.png`): a Poster hero in the focus colour with the figure and ranked muscle bars, or a Bento board
// (map tile + stat squares). Tap the map → `SessionMusclesSheet`; long press → arrange on the page (rows wiggle, drag to
// move, − to hide); the grid button in the top bar → `SessionCustomiseSheet`.
// Choices are per device (`@AppStorage`).

/// Poster hero or Bento board.
enum SessionLook: String, CaseIterable, Identifiable {
    case poster, bento
    var id: String { rawValue }
    var title: String { self == .poster ? "Poster" : "Bento" }
    var detail: String { self == .poster ? "Big hero, muscle bars" : "Map tile + stat squares" }
    var symbol: String { self == .poster ? "rectangle.portrait.fill" : "square.grid.2x2.fill" }
    static let storageKey = "sessionLook"
}

/// How the muscles show on the page and open in the sheet.
enum SessionMapStyle: String, CaseIterable, Identifiable {
    case pair, solid, bars
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pair: "Front + back"
        case .solid: "3D"
        case .bars: "Heat bars"
        }
    }
    var symbol: String {
        switch self {
        case .pair: "figure.stand"
        case .solid: "rotate.3d"
        case .bars: "chart.bar.fill"
        }
    }
    static let storageKey = "sessionMapStyle"
}

enum SessionMapSize: String, CaseIterable, Identifiable {
    case s, m, l
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    /// Hero / board height.
    var height: CGFloat {
        switch self {
        case .s: 250
        case .m: 300
        case .l: 370
        }
    }
    static let storageKey = "sessionMapSize"
}

/// Hero and map tile colours: the workout's focus, or a fixed palette.
enum SessionTheme: String, CaseIterable, Identifiable {
    case focus, sunset, ocean, candy, lime
    var id: String { rawValue }
    var title: String { self == .focus ? "Focus" : rawValue.capitalized }
    static let storageKey = "sessionTheme"

    func colors(_ focus: Focus) -> [Color] {
        switch self {
        case .focus: focus.heroColors
        case .sunset: [Color(hex: 0xFFC93D), Color(hex: 0xFF8A00), Color(hex: 0xFF2D55)]
        case .ocean: [Color(hex: 0x00C9A7), Color(hex: 0x2EC5FF), Color(hex: 0x2F6BFF)]
        case .candy: [Color(hex: 0xFF4DD8), Color(hex: 0xA64DFF), Color(hex: 0x2F6BFF)]
        case .lime: [Color(hex: 0x1ED98A), Color(hex: 0x00C9A7), Color(hex: 0x1F4FD9)]
        }
    }

    func gradient(_ focus: Focus) -> LinearGradient {
        LinearGradient(colors: colors(focus), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Exercises as the classic cards or as gradient tiles (C1).
enum SessionExerciseLook: String, CaseIterable, Identifiable {
    case list, tiles
    var id: String { rawValue }
    var title: String { self == .list ? "Cards" : "Tiles" }
    var symbol: String { self == .list ? "list.bullet.rectangle.fill" : "square.grid.3x2.fill" }
    static let storageKey = "sessionExercises"
}

/// Rows under the hero / board, in the member's order; missing = hidden.
enum SessionRow: String, CaseIterable, Identifiable {
    case stats, style, upFirst, xp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stats: "Duration · exercises · sets"
        case .style: "Workout style"
        case .upFirst: "Up first"
        case .xp: "XP banner"
        }
    }
    var symbol: String {
        switch self {
        case .stats: "stopwatch.fill"
        case .style: "slider.horizontal.3"
        case .upFirst: "list.number"
        case .xp: "star.fill"
        }
    }
    static let storageKey = "sessionRows"
    static let defaults = "stats,style,upFirst"

    static func parse(_ raw: String) -> [SessionRow] { raw.split(separator: ",").compactMap { SessionRow(rawValue: String($0)) } }
    static func join(_ rows: [SessionRow]) -> String { rows.map(\.rawValue).joined(separator: ",") }
}

extension Focus {
    /// Poster hero colours per focus.
    var heroColors: [Color] {
        switch self {
        case .push, .chestTri, .shouldersArms: [Color(hex: 0xFF8A00), Color(hex: 0xFF2D55), Color(hex: 0xA64DFF)]
        case .pull, .backBi: [Color(hex: 0xFF2D55), Color(hex: 0xA64DFF), Color(hex: 0x2F6BFF)]
        case .legs, .lower, .posterior, .fullLower: [Color(hex: 0x1ED98A), Color(hex: 0x00C9A7), Color(hex: 0x2F6BFF)]
        case .upper, .fullUpper, .chestBack: [Color(hex: 0x2F6BFF), Color(hex: 0x8A4DFF), Color(hex: 0xFF4DD8)]
        case .fullPower: [Color(hex: 0xFF2D55), Color(hex: 0xFF8A00), Color(hex: 0xFFC93D)]
        case .conditioning: [Color(hex: 0x00C9A7), Color(hex: 0x2EC5FF), Color(hex: 0x8A4DFF)]
        }
    }
}

extension Session {
    /// Sets of the power and strength blocks.
    var workSets: Int {
        blocks.filter { [BlockKind.power, .strength].contains($0.kind) }.flatMap(\.items).reduce(0) { $0 + $1.prescription.sets }
    }

    var exerciseCount: Int { blocks.reduce(0) { $0 + $1.items.count } }

    /// First moves of the main part (Up first strip).
    var upFirst: [PlannedExercise] {
        let main = blocks.first { [BlockKind.power, .strength].contains($0.kind) && !$0.items.isEmpty } ?? blocks.first { !$0.items.isEmpty }
        return Array((main?.items ?? []).prefix(3))
    }
}

/// Body side with the most load: the Poster hero shows that one.
func busiestSide(_ heat: [Muscle: Double], figure: BodyFigure) -> BodySide {
    func load(_ side: BodySide) -> Double {
        Set(BodyMapLayout.shapes(side, figure: figure).map(\.muscle)).reduce(0) { $0 + (heat[$1] ?? 0) }
    }
    return load(.back) > load(.front) ? .back : .front
}

/// Top of the workout page: hero or board, then the member's rows.
struct SessionBoard: View {
    let session: Session
    var readOnly = false
    var onMuscle: (Muscle) -> Void
    var onMap: () -> Void
    var onEditExercises: (() -> Void)?
    var onExercise: (PlannedExercise) -> Void
    var onCustomise: () -> Void
    @AppStorage(SessionLook.storageKey) private var look = SessionLook.poster
    @AppStorage(SessionMapStyle.storageKey) private var mapStyle = SessionMapStyle.pair
    @AppStorage(SessionMapSize.storageKey) private var mapSize = SessionMapSize.m
    @AppStorage(SessionTheme.storageKey) private var theme = SessionTheme.focus
    @AppStorage(SessionRow.storageKey) private var rowsRaw = SessionRow.defaults
    @Environment(\.bodyFigure) private var figure
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Long press: rows wiggle, drag one onto another to move it, − hides it (C3).
    @State private var arranging = false
    @State private var wiggle = false

    private var empty: Bool { session.blocks.allSatisfy { $0.items.isEmpty } }
    private var rows: [SessionRow] { SessionRow.parse(rowsRaw) }

    /// Demo screen `session-bento` shows the board without changing the saved look.
    private var shownLook: SessionLook {
        #if DEBUG
        if Demo.screen == "session-bento" { return .bento }
        #endif
        return look
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if arranging { arrangeBar }
            Group {
                switch shownLook {
                case .poster: poster
                case .bento: bento
                }
            }
            .rotationEffect(.degrees(arranging && !reduceMotion ? (wiggle ? 0.4 : -0.4) : 0))
            ForEach(rows) { row in
                rowView(row)
                    .modifier(ArrangeTile(id: row.rawValue, title: row.title, on: arranging && (row != .stats || shownLook == .poster),
                                          wiggle: wiggle && !reduceMotion, onHide: { hide(row) }) { dropped in move(dropped, to: row) })
            }
        }
        .animation(arranging ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default, value: wiggle)
        .sensoryFeedback(.impact, trigger: arranging)
    }

    private func startArranging() {
        withAnimation(.snappy) { arranging = true }
        wiggle = true
    }

    private func hide(_ row: SessionRow) {
        withAnimation(.snappy) { rowsRaw = SessionRow.join(rows.filter { $0 != row }) }
    }

    private func move(_ raw: String, to target: SessionRow) {
        guard let dragged = SessionRow(rawValue: raw), dragged != target,
              let from = rows.firstIndex(of: dragged), let to = rows.firstIndex(of: target) else { return }
        // Dropped on a later row it lands after it, on an earlier one before it.
        var r = rows
        r.remove(at: from)
        r.insert(dragged, at: to)
        withAnimation(.snappy) { rowsRaw = SessionRow.join(r) }
    }

    /// Arrange mode bar: look, hidden rows to add back, all options, Done.
    private var arrangeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(SessionLook.allCases) { l in
                    Button { withAnimation(.snappy) { look = l } } label: {
                        Label(l.title, systemImage: l.symbol).font(Theme.label(13))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .foregroundStyle(look == l ? Theme.ink : .white)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look == l ? Color.white : Theme.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(look == l ? .isSelected : [])
                }
                Spacer(minLength: 4)
                Button(action: onCustomise) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .heavy))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("All page options")
                Button("Done") { withAnimation(.snappy) { arranging = false }; wiggle = false }
                    .font(Theme.label(14)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.lime))
                    .buttonStyle(.plain)
            }
            let hidden = SessionRow.allCases.filter { !rows.contains($0) }
            if !hidden.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(hidden) { r in
                            Button { withAnimation(.snappy) { rowsRaw = SessionRow.join(rows + [r]) } } label: {
                                Label(r.title, systemImage: "plus").font(Theme.label(12))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Show \(r.title)")
                        }
                    }
                }
            }
            Text("Drag a tile onto another to move it · − hides it").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private func rowView(_ row: SessionRow) -> some View {
        switch row {
        case .stats:
            // The board has its own stat squares.
            if shownLook == .poster {
                HStack(spacing: 10) {
                    GradientStat(symbol: "stopwatch.fill", value: "\(session.estMin)′", label: "Duration",
                                 gradient: WorkoutEngine.Category.cardio.gradient)
                    exercisesTile(
                        GradientStat(symbol: "figure.strengthtraining.traditional", value: "\(session.exerciseCount)", label: "Exercises",
                                     gradient: WorkoutEngine.Category.mobility.gradient))
                    GradientStat(symbol: "square.stack.3d.up.fill", value: "\(session.workSets)", label: "Work sets",
                                 gradient: WorkoutEngine.Category.strength.gradient)
                }
            }
        case .style:
            if !readOnly { WorkoutStyleCard(session: session) }
        case .upFirst:
            if !session.upFirst.isEmpty { upFirstStrip }
        case .xp:
            if !empty { SessionGameBanner(session: session) }
        }
    }

    // MARK: Poster (A)

    private var poster: some View {
        let heat = session.muscleHeat
        let top = session.topMuscles(mapStyle == .bars ? 6 : 4)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(theme.gradient(session.focus))
            if mapStyle != .bars && !empty {
                HStack {
                    Spacer()
                    heroFigure(heat)
                        .frame(width: mapSize.height * 0.5)
                        .shadow(color: .white.opacity(0.45), radius: 14)
                        .padding(.trailing, 4)
                        .padding(.top, 34)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onMap)
                .accessibilityElement()
                .accessibilityLabel("Muscles worked")
                .accessibilityHint("Opens the muscle map")
                .accessibilityAddTraits(.isButton)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(session.displayTitle.uppercased())
                    .font(Theme.display(52)).lineLimit(2).minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                if !readOnly { WorkoutFocusChips(session: session) }
                Spacer(minLength: 8)
                if !top.isEmpty {
                    Text(mapStyle == .bars ? "Muscles worked" : "Target").font(Theme.label(10)).tracking(1.4).textCase(.uppercase).opacity(0.85)
                    MuscleHeatBars(muscles: top, heat: heat, onTap: onMuscle)
                        .frame(maxWidth: mapStyle == .bars ? .infinity : 170, alignment: .leading)
                }
            }
            .padding(18)
        }
        .foregroundStyle(.white)
        .frame(height: mapSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in startArranging() })
    }

    @ViewBuilder
    private func heroFigure(_ heat: [Muscle: Double]) -> some View {
        let side = busiestSide(heat, figure: figure)
        if mapStyle == .solid {
            BodyMap3DView(heat: heat, yaw: side == .back ? 180 : 0) { _ in }
                .allowsHitTesting(false)
        } else {
            BodyMapView(side: side, heat: heat, showLabel: false, onColor: true)
                .allowsHitTesting(false)
        }
    }

    // MARK: Bento (C)

    private var bento: some View {
        let heat = session.muscleHeat
        return VStack(alignment: .leading, spacing: 10) {
            Text(session.displayTitle).font(Theme.display(38)).lineLimit(1).minimumScaleFactor(0.6)
            if !readOnly { WorkoutFocusChips(session: session) }
            HStack(spacing: 10) {
                Button(action: onMap) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 26, style: .continuous).fill(theme.gradient(session.focus))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Muscles").font(Theme.label(10)).tracking(1.4).textCase(.uppercase).opacity(0.85)
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .heavy))
                            }
                            tileMap(heat)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .allowsHitTesting(false)
                            Text(session.topMuscles(3).map(\.name).joined(separator: " · "))
                                .font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(12)
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Muscles worked: \(session.topMuscles(3).map(\.name).joined(separator: ", "))")
                .accessibilityHint("Opens the muscle map")
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                VStack(spacing: 10) {
                    MiniStat(value: "\(session.estMin)′", label: "Min", gradient: WorkoutEngine.Category.cardio.gradient)
                    exercisesTile(MiniStat(value: "\(session.exerciseCount)", label: "Exercises", gradient: WorkoutEngine.Category.mobility.gradient))
                    MiniStat(value: "\(session.workSets)", label: "Sets", gradient: WorkoutEngine.Category.strength.gradient)
                }
                .frame(width: 104)
            }
            .frame(height: mapSize.height)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in startArranging() })
        }
    }

    @ViewBuilder
    private func tileMap(_ heat: [Muscle: Double]) -> some View {
        switch mapStyle {
        case .pair: BodyMapPair(heat: heat, spacing: 4)
        case .solid: BodyMap3DView(heat: heat, yaw: busiestSide(heat, figure: figure) == .back ? 180 : 0) { _ in }
        case .bars: MuscleHeatBars(muscles: session.topMuscles(6), heat: heat, onTap: nil)
        }
    }

    // MARK: Parts

    /// Until the workout starts the exercise count opens the editor (#295).
    @ViewBuilder
    private func exercisesTile<Tile: View>(_ tile: Tile) -> some View {
        if let onEditExercises {
            Button(action: onEditExercises) {
                tile.overlay(alignment: .topTrailing) {
                    Image(systemName: "pencil").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white).padding(10)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit exercises")
        } else {
            tile
        }
    }

    private var upFirstStrip: some View {
        HStack(spacing: 6) {
            Text("Up first").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(session.upFirst, id: \.uid) { item in
                        Button { onExercise(item) } label: {
                            Text(Exercise.get(item.exerciseId).name)
                                .font(Theme.label(13)).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}

/// A row in arrange mode: wiggles, drags onto another row to move, − hides it; its own taps are off meanwhile.
private struct ArrangeTile: ViewModifier {
    let id: String
    let title: String
    let on: Bool
    let wiggle: Bool
    let onHide: () -> Void
    let onDrop: (String) -> Void

    func body(content: Content) -> some View {
        if on {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .background(Color.white.opacity(0.001))
                        .draggable(id) {
                            Text(title).font(Theme.label(14)).padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.lime)).foregroundStyle(Theme.ink)
                        }
                }
                .overlay(alignment: .topLeading) {
                    Button(action: onHide) {
                        Image(systemName: "minus").font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color(hex: 0xFF3D5D)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -8, y: -8)
                    .accessibilityLabel("Hide \(title)")
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first else { return false }
                    onDrop(first)
                    return true
                }
                .rotationEffect(.degrees(wiggle ? -0.6 : 0.6))
                .accessibilityAction(named: "Hide", onHide)
        } else {
            content
        }
    }
}

/// Small stat square for the board.
struct MiniStat: View {
    let value: String
    let label: String
    let gradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(value).font(Theme.display(26)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.label(10)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient))
        .accessibilityElement(children: .combine)
    }
}

/// Ranked muscles with a white heat bar each; tap opens the muscle.
struct MuscleHeatBars: View {
    let muscles: [Muscle]
    let heat: [Muscle: Double]
    var sets: [Muscle: Int] = [:]
    var onTap: ((Muscle) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(muscles) { m in
                let row = VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(m.name).font(Theme.label(13)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let n = sets[m] { Text("\(n) sets").font(Theme.label(11)).opacity(0.85) }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.22))
                            RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: max(8, geo.size.width * (heat[m] ?? 0)))
                        }
                    }
                    .frame(height: 7)
                }
                if let onTap {
                    Button { onTap(m) } label: { row.contentShape(Rectangle()) }.buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
    }
}

/// Map tile opened (C2): 2D / 3D / heat bars, the picked muscle's sets, sets per muscle tiles → muscle page.
struct SessionMusclesSheet: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SessionMapStyle.storageKey) private var savedStyle = SessionMapStyle.pair
    @AppStorage(SessionTheme.storageKey) private var theme = SessionTheme.focus
    @State private var style: SessionMapStyle?
    @State private var picked: Muscle?
    @State private var open: Muscle?

    var body: some View {
        let heat = session.muscleHeat
        let sets = session.setsPerMuscle()
        let setsBy = Dictionary(uniqueKeysWithValues: sets.map { ($0.muscle, $0.sets) })
        let shown = style ?? savedStyle
        // Last workout of the same focus before today: what it did per muscle against this plan.
        let last = model.history.first { $0.focus == session.focus && !Calendar.current.isDateInToday($0.startedAt) && $0.totalSets > 0 }
        let lastSets = last?.setsPerMuscle
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ContentTitle(title: "Muscles worked", subtitle: session.displayTitle)
                    HStack(spacing: 6) {
                        ForEach(SessionMapStyle.allCases) { s in
                            Button { withAnimation(.snappy) { style = s } } label: {
                                Label(s.title, systemImage: s.symbol).font(Theme.label(13))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .foregroundStyle(shown == s ? Theme.ink : .white)
                                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(shown == s ? Color.white : Theme.card))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(shown == s ? .isSelected : [])
                        }
                    }
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(RadialGradient(colors: [theme.colors(session.focus)[1].opacity(0.55), Theme.bg], center: .center, startRadius: 10, endRadius: 260))
                        stage(shown, heat: heat, sets: setsBy)
                            .padding(14)
                        if let picked {
                            Button { open = picked } label: {
                                Label("\(picked.name) · \(setsBy[picked] ?? 0) sets", systemImage: "chevron.right")
                                    .labelStyle(.titleAndIcon)
                                    .font(Theme.label(13)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Capsule().fill(.white))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 12)
                        }
                    }
                    .frame(height: 400)
                    if shown != .bars { HeatLegend() }
                    if let last, let lastSets { lastCard(last, lastSets: lastSets, sets: sets) }
                    Text("Sets per muscle").eyebrow()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(sets) { row in
                            Button { open = row.muscle } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("\(row.sets)").font(Theme.display(28)).monospacedDigit()
                                        if let lastSets { Text(Self.delta(row.sets - (lastSets[row.muscle] ?? 0))).font(Theme.label(11)).opacity(0.85) }
                                    }
                                    Text(row.muscle.name).font(Theme.label(10)).tracking(0.8).textCase(.uppercase).lineLimit(1).minimumScaleFactor(0.6)
                                }
                                .foregroundStyle((heat[row.muscle] ?? 0) > 0.55 ? .white : Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 76, alignment: .bottomLeading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.heat(heat[row.muscle] ?? 0)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(row.muscle.name), \(row.sets) sets")
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .titleInContent("Muscles worked")
            .toolbar { CloseToolbarItem { dismiss() } }
            .navigationDestination(item: $open) { MuscleDetailView(muscle: $0) }
        }
    }

    static func delta(_ d: Int) -> String { d > 0 ? "+\(d)" : d < 0 ? "−\(-d)" : "=" }

    private func lastCard(_ last: WorkoutRecord, lastSets: [Muscle: Int], sets: [MuscleSets]) -> some View {
        let line = sets.prefix(4).map { "\($0.muscle.name) \(Self.delta($0.sets - (lastSets[$0.muscle] ?? 0)))" }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                Text("vs last \(last.title) · \(last.startedAt.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                Text(line).font(.footnote.weight(.semibold)).opacity(0.9).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(WorkoutEngine.Category.cardio.gradient))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stage(_ s: SessionMapStyle, heat: [Muscle: Double], sets: [Muscle: Int]) -> some View {
        switch s {
        case .pair:
            BodyMapPair(heat: heat, selected: picked, tapTolerance: 6) { m in withAnimation(.snappy) { picked = m } }
                .padding(.top, 36)
        case .solid:
            BodyMap3DView(heat: heat, selected: picked) { m in withAnimation(.snappy) { picked = m } }
                .padding(.top, 36)
        case .bars:
            MuscleHeatBars(muscles: session.topMuscles(10), heat: heat, sets: sets) { open = $0 }
                .foregroundStyle(.white)
                .padding(.top, 8)
        }
    }
}

/// Customise the workout page (C3): look, map style and size, colours, rows (drag ≡ to reorder). Saved at once.
struct SessionCustomiseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SessionLook.storageKey) private var look = SessionLook.poster
    @AppStorage(SessionMapStyle.storageKey) private var mapStyle = SessionMapStyle.pair
    @AppStorage(SessionMapSize.storageKey) private var mapSize = SessionMapSize.m
    @AppStorage(SessionTheme.storageKey) private var theme = SessionTheme.focus
    @AppStorage(SessionRow.storageKey) private var rowsRaw = SessionRow.defaults
    @AppStorage(SessionExerciseLook.storageKey) private var exerciseLook = SessionExerciseLook.list
    var focus: Focus = .pull

    private var rows: [SessionRow] { SessionRow.parse(rowsRaw) }

    var body: some View {
        NavigationStack {
            List {
                ContentTitle(title: "Customise workout page", subtitle: "Look, map and tiles · same on every workout")
                    .cardRow()
                Section("Look") {
                    tiles(SessionLook.allCases, selected: look, title: \.title, symbol: \.symbol) { look = $0 }
                        .darkCardRow()
                }
                Section("Map style") {
                    tiles(SessionMapStyle.allCases, selected: mapStyle, title: \.title, symbol: \.symbol) { mapStyle = $0 }
                        .darkCardRow()
                }
                Section("Map size") {
                    tiles(SessionMapSize.allCases, selected: mapSize, title: \.title, symbol: \.symbolName) { mapSize = $0 }
                        .darkCardRow()
                }
                Section("Exercises") {
                    tiles(SessionExerciseLook.allCases, selected: exerciseLook, title: \.title, symbol: \.symbol) { exerciseLook = $0 }
                        .darkCardRow()
                }
                Section("Colours") {
                    HStack(spacing: 10) {
                        ForEach(SessionTheme.allCases) { t in
                            Button { withAnimation { theme = t } } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.gradient(focus))
                                        .frame(height: 40)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(.white, lineWidth: theme == t ? 3 : 0)
                                        }
                                    Text(t.title).font(Theme.label(11)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(theme == t ? .isSelected : [])
                        }
                    }
                    .darkCardRow()
                }
                Section("Tiles · drag ≡ to reorder") {
                    ForEach(rows) { r in
                        rowLabel(r, on: true)
                    }
                    .onMove { from, to in
                        var r = rows
                        r.move(fromOffsets: from, toOffset: to)
                        rowsRaw = SessionRow.join(r)
                    }
                    ForEach(SessionRow.allCases.filter { !rows.contains($0) }) { r in
                        rowLabel(r, on: false).opacity(0.7)
                    }
                }
                Section {
                    Button("Reset to default") {
                        withAnimation {
                            look = .poster; mapStyle = .pair; mapSize = .m; theme = .focus; rowsRaw = SessionRow.defaults; exerciseLook = .list
                        }
                    }
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.lime)
                    .darkCardRow()
                }
            }
            .environment(\.editMode, .constant(.active))
            .themedForm()
            .titleInContent("Customise workout page")
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    private func rowLabel(_ r: SessionRow, on: Bool) -> some View {
        Button {
            withAnimation { rowsRaw = SessionRow.join(on ? rows.filter { $0 != r } : rows + [r]) }
        } label: {
            HStack(spacing: 10) {
                IconTile(symbol: r.symbol, size: 30)
                Text(r.title).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                SquareToggle(on: on)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Hide \(r.title)" : "Show \(r.title)")
        .darkCardRow()
    }

    private func tiles<T: Identifiable & Equatable>(_ all: [T], selected: T, title: KeyPath<T, String>, symbol: KeyPath<T, String>,
                                                     pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 10) {
            ForEach(all) { v in
                let on = v == selected
                Button { withAnimation(.snappy) { pick(v) } } label: {
                    VStack(spacing: 6) {
                        Image(systemName: v[keyPath: symbol]).font(.system(size: 22, weight: .bold)).frame(height: 28)
                        Text(v[keyPath: title]).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? Theme.ink : .white)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.card)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

private extension SessionMapSize {
    var symbolName: String {
        switch self {
        case .s: "rectangle.compress.vertical"
        case .m: "rectangle"
        case .l: "rectangle.expand.vertical"
        }
    }
}
