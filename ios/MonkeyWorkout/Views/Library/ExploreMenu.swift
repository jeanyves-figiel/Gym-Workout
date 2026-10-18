import SwiftUI
import WorkoutEngine

/// Explore top menu (#459, design B3): a live hero card for the picked section over a dock of colour icons.
/// The hero recolours per section and shows something current (this week's sets, top machine, last workout…).
struct ExploreMenu: View {
    @Binding var mode: LibraryView.Mode
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            ExploreHero(info: info(mode))
                .id(mode)
                .transition(.opacity)
            HStack(alignment: .top, spacing: 0) {
                ForEach(LibraryView.Mode.allCases) { m in
                    dockItem(m)
                    if m != LibraryView.Mode.allCases.last { Spacer(minLength: 2) }
                }
            }
            .padding(.horizontal, 4)
        }
        .sensoryFeedback(.selection, trigger: mode)
    }

    private func dockItem(_ m: LibraryView.Mode) -> some View {
        let on = m == mode
        return Button {
            withAnimation(.snappy(duration: 0.25)) { mode = m }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: m.symbol)
                    .font(.system(size: on ? 18 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: on ? 46 : 40, height: on ? 46 : 40)
                    .background(Circle().fill(m.gradient))
                    .overlay(Circle().strokeBorder(.white, lineWidth: on ? 2.5 : 0).padding(-4))
                    .shadow(color: on ? m.tint.opacity(0.55) : .clear, radius: 8, y: 4)
                    .frame(height: 50)
                Text(m.short)
                    .font(Theme.label(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(on ? Theme.lime : .white.opacity(0.7))
            }
            .frame(minWidth: 54)
            .opacity(on ? 1 : 0.8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.rawValue)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Live info per section

    private func info(_ m: LibraryView.Mode) -> ExploreHero.Info {
        switch m {
        case .muscles:
            let sets = model.weeklyWorkingSets
            guard sets > 0 else {
                return .init(mode: m, title: "Muscles", line: "Tap one on the body", value: "\(Muscle.allCases.count)", unit: "muscles")
            }
            let top = model.weekHeat.filter { $0.value > 0 }
                .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.name < $1.key.name) }
                .prefix(3).map(\.key.name)
            return .init(mode: m, title: "Muscles", line: "This week", value: "\(sets)", unit: "sets", chips: top)
        case .machines:
            let n = GymArea.allCases.reduce(0) { $0 + $1.browsable().count }
            return .init(mode: m, title: "Machines", line: topMachine.map { "Top: \($0.label)" } ?? "Browse by kit",
                         value: "\(n)", unit: "machines")
        case .categories:
            return .init(mode: m, title: "Types", line: topCategory.map { "Most: \($0.label)" } ?? "Pick a training type",
                         value: "\(WorkoutEngine.Category.allCases.count + 1)", unit: "types")
        case .workouts:
            return .init(mode: m, title: "Workouts", line: model.history.first.map { "Last: \($0.title)" } ?? "Ready-made and yours",
                         value: "\(model.myLibrary.count + model.builtInLibrary.count)", unit: "workouts")
        case .programmes:
            if let a = model.activeProgramme, let p = a.programme {
                return .init(mode: m, title: "Plans", line: a.paused ? "\(p.name) · paused" : "\(p.name) · of \(p.weeks) weeks",
                             value: "\(model.programmeWeek ?? 1)", unit: "week")
            }
            return .init(mode: m, title: "Plans", line: "Pick a goal", value: "\(Programme.all.count)", unit: "goals")
        }
    }

    /// Records of the last 30 days (top machine / type lines).
    private var recent: [WorkoutRecord] {
        let since = Date().addingTimeInterval(-30 * 86_400)
        return model.history.prefix { $0.startedAt >= since }.map { $0 }
    }

    private var topMachine: Equipment? {
        let browsable = Set(GymArea.allCases.flatMap { $0.browsable().map(\.item) })
        var sets: [Equipment: Int] = [:]
        for r in recent {
            for e in r.exercises where e.setsDone > 0 {
                guard let kit = Exercise.find(e.exerciseId)?.equipment.first(where: { browsable.contains($0) }) else { continue }
                sets[kit, default: 0] += e.setsDone
            }
        }
        return sets.max { $0.value < $1.value || ($0.value == $1.value && $0.key.label > $1.key.label) }?.key
    }

    private var topCategory: WorkoutEngine.Category? {
        var sets: [WorkoutEngine.Category: Int] = [:]
        for r in recent { for e in r.exercises { sets[e.category, default: 0] += e.setsDone } }
        return sets.filter { $0.value > 0 }.max { $0.value < $1.value || ($0.value == $1.value && $0.key.label > $1.key.label) }?.key
    }
}

/// Explore-style gradient hero: icon tile, title + live line, big number right, optional chips.
struct ExploreHero: View {
    struct Info {
        let mode: LibraryView.Mode
        let title: String
        let line: String
        let value: String
        let unit: String
        var chips: [String] = []
    }

    let info: Info

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                IconTile(symbol: info.mode.symbol, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(info.line).font(Theme.label(12)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.8)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(info.value).font(Theme.display(40)).monospacedDigit().lineLimit(1)
                    Text(info.unit).font(Theme.label(11)).opacity(0.85)
                }
            }
            if !info.chips.isEmpty {
                ViewThatFits(in: .horizontal) {
                    chips(info.chips)
                    chips(Array(info.chips.prefix(2)))
                    chips(Array(info.chips.prefix(1)))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(info.mode.gradient)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.white.opacity(0.12)).frame(width: 150, height: 150).offset(x: 50, y: -60)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .accessibilityElement(children: .combine)
    }

    private func chips(_ names: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(names, id: \.self) { n in
                Text(n).font(Theme.label(11)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.22)))
            }
        }
    }
}

extension LibraryView.Mode {
    /// Dock label: short so all five fit on the smallest iPhone.
    var short: String {
        switch self {
        case .muscles: "Muscles"
        case .machines: "Machines"
        case .categories: "Types"
        case .workouts: "Workouts"
        case .programmes: "Plans"
        }
    }

    var symbol: String {
        switch self {
        case .muscles: "figure.strengthtraining.traditional"
        case .machines: "gearshape.2.fill"
        case .categories: "square.grid.2x2.fill"
        case .workouts: "list.bullet.rectangle.fill"
        case .programmes: "flag.checkered"
        }
    }

    /// Own colour per section, borrowed from the category palette.
    private var palette: WorkoutEngine.Category {
        switch self {
        case .muscles: .strength
        case .machines: .warmup
        case .categories: .stretch
        case .workouts: .cardio
        case .programmes: .power
        }
    }

    var gradient: LinearGradient { palette.gradient }
    var tint: Color { palette.color }
}
