import SwiftUI
import WorkoutEngine

// MARK: - Warm-up and cool-down of one workout (#293)

private func rgb(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// One style tile: copy and colours.
struct FlowStyleTile: Identifiable {
    let raw: String
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
    var id: String { raw }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }

    static func all(_ kind: BlockKind) -> [FlowStyleTile] {
        kind == .warmup ? WarmupStyle.allCases.map(\.tile) : CooldownStyle.allCases.map(\.tile)
    }

    static func named(_ raw: String, _ kind: BlockKind) -> FlowStyleTile? { all(kind).first { $0.raw == raw } }
}

extension WarmupStyle {
    var tile: FlowStyleTile {
        switch self {
        case .auto: FlowStyleTile(raw: rawValue, title: "Auto", subtitle: "Matches exercises", symbol: "sparkles", colors: [rgb(0x3A3A4A), rgb(0x5A5A70)])
        case .pulse: FlowStyleTile(raw: rawValue, title: "Pulse raiser", subtitle: "Bike, row, ski", symbol: "heart.fill", colors: [rgb(0xFF3D71), rgb(0xFF7A2F)])
        case .dynamic: FlowStyleTile(raw: rawValue, title: "Dynamic", subtitle: "Drills, no machine", symbol: "figure.flexibility", colors: [rgb(0xFF7A2F), rgb(0xFFB13D)])
        case .activation: FlowStyleTile(raw: rawValue, title: "Activation", subtitle: "Glutes, shoulders", symbol: "bolt.fill", colors: [rgb(0xFF9B2F), rgb(0xFFD23F)])
        }
    }
}

extension CooldownStyle {
    var tile: FlowStyleTile {
        switch self {
        case .auto: FlowStyleTile(raw: rawValue, title: "Auto", subtitle: "Flush + stretches", symbol: "sparkles", colors: [rgb(0x3A3A4A), rgb(0x5A5A70)])
        case .stretch: FlowStyleTile(raw: rawValue, title: "Stretch", subtitle: "Static stretches", symbol: "figure.cooldown", colors: [rgb(0x1ED98A), rgb(0x8EE85A)])
        case .foamRoll: FlowStyleTile(raw: rawValue, title: "Foam roll", subtitle: "Roll, then stretch", symbol: "cylinder.fill", colors: [rgb(0x3DD6D0), rgb(0x3D5AFF)])
        case .easyCardio: FlowStyleTile(raw: rawValue, title: "Easy cardio", subtitle: "Spin down, stretch", symbol: "figure.walk", colors: [rgb(0x21C98A), rgb(0x1E9BFF)])
        case .breathe: FlowStyleTile(raw: rawValue, title: "Breathe", subtitle: "Long exhales", symbol: "wind", colors: [rgb(0x8A4DFF), rgb(0x21C98A)])
        }
    }
}

extension FlowTweaks {
    /// Style picked for `kind` in this workout, else the profile's default.
    func style(_ kind: BlockKind, profile: Profile?) -> String {
        switch kind {
        case .warmup: (warmupStyle ?? profile?.warmupStyle ?? .auto).rawValue
        default: (cooldownStyle ?? profile?.cooldownStyle ?? .auto).rawValue
        }
    }

    /// Short summary for a card: the style, or the exact moves' time.
    func summary(_ kind: BlockKind, profile: Profile?) -> String {
        if let m = movesMinutes(kind) { return "Your moves · \(m)′" }
        return FlowStyleTile.named(style(kind, profile: profile), kind)?.title ?? "Auto"
    }
}

/// Block opened from a Warm-up / Cool-down chip or card (sheet item).
struct FlowTweakTarget: Identifiable {
    let kind: BlockKind
    var id: String { kind.rawValue }
}

/// Warm-up or cool-down of one workout (#293, design A+C): style tiles, the exact moves (swap, remove, add,
/// minutes) and Use as my default.
struct FlowTweakSheet: View {
    let kind: BlockKind
    @Binding var tweaks: FlowTweaks
    /// Moves the block gets with some tweaks (generated, or the exact moves).
    let preview: (FlowTweaks) -> [PlannedExercise]
    /// Leaves the block out of the workout; nil = not offered.
    var onRemove: (() -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PlannedExercise] = []
    @State private var picker: PickerMode?
    @State private var useDefault = false

    static let maxMoves = 8

    /// Swap one move, or add new ones.
    enum PickerMode: Identifiable {
        case swap(Int)
        case add
        var id: String {
            switch self {
            case let .swap(i): "swap\(i)"
            case .add: "add"
            }
        }
    }

    private var style: String { tweaks.style(kind, profile: model.profile) }
    private var custom: Bool { tweaks.moves(kind) != nil }
    private var category: WorkoutEngine.Category { kind == .warmup ? .warmup : .stretch }

    /// Current moves: the exact ones, or the generated block's.
    private var moves: [BlockPick] {
        tweaks.moves(kind) ?? items.map { BlockPick(exerciseId: $0.exerciseId, minutes: max(1, Int((Double($0.estSec) / 60).rounded()))) }
    }

    private var minutes: Int { moves.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(kind.flowLabel, systemImage: kind.symbol).font(Theme.display(28))
                        Spacer()
                        Text("\(minutes)′").font(Theme.display(28)).monospacedDigit()
                    }

                    Text("Style").eyebrow().padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(FlowStyleTile.all(kind)) { t in styleTile(t) }
                    }

                    HStack {
                        Text(custom ? "Your moves" : "Moves").eyebrow()
                        Spacer()
                        if custom {
                            Button("Back to style") { tweaks.setMoves(nil, for: kind) }
                                .font(Theme.label(13)).foregroundStyle(Theme.lime)
                        }
                    }
                    .padding(.top, 8)
                    ForEach(Array(moves.enumerated()), id: \.offset) { i, m in row(i, m) }
                    if moves.count < Self.maxMoves {
                        Button { picker = .add } label: {
                            Label("Add a move", systemImage: "plus.circle.fill")
                                .font(Theme.label(15))
                                .foregroundStyle(Theme.lime)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        }
                        .buttonStyle(.plain)
                    }

                    Toggle(isOn: Binding(get: { useDefault }, set: { useDefault = $0; writeDefault($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use as my default").font(Theme.label(15))
                            Text("Every new workout and your plan get this \(kind.flowLabel.lowercased()).")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.lime)
                    .padding(.top, 6)

                    Text(custom
                         ? "Your moves set the \(kind.flowLabel.lowercased()) time. Pick a style to go back to picked moves."
                         : "Moves follow the style, your exercises and your gym. Swap, remove or add one to make it yours.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)

                    if let onRemove {
                        Button(role: .destructive) { onRemove(); dismiss() } label: {
                            Label("Leave out \(kind.flowLabel.lowercased())", systemImage: "minus.circle")
                                .font(Theme.label(15))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .padding(.top, 8)
                    }
                }
                .padding(16)
                .animation(.spring(duration: 0.3), value: moves)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(item: $picker) { mode in
                switch mode {
                case let .swap(i):
                    ExercisePickerView(limit: 1, category: category) { exs in
                        guard let e = exs.first else { return }
                        edit { m in
                            guard m.indices.contains(i) else { return }
                            m[i] = BlockPick(exerciseId: e.id, minutes: m[i].minutes)
                        }
                    }
                case .add:
                    ExercisePickerView(limit: Self.maxMoves - moves.count, category: category) { exs in
                        edit { m in
                            let have = Set(m.map(\.exerciseId))
                            m += exs.filter { !have.contains($0.id) }.map { BlockPick(exerciseId: $0.id, minutes: BlockPicks.defaultMinutes($0, in: kind)) }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            items = preview(tweaks)
            useDefault = matchesDefault
        }
        .onChange(of: tweaks) {
            items = preview(tweaks)
            if useDefault { writeDefault(true) }
        }
    }

    private func styleTile(_ t: FlowStyleTile) -> some View {
        let on = !custom && style == t.raw
        return Button {
            switch kind {
            case .warmup: tweaks.warmupStyle = WarmupStyle(rawValue: t.raw)
            default: tweaks.cooldownStyle = CooldownStyle(rawValue: t.raw)
            }
            tweaks.setMoves(nil, for: kind)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: t.symbol).font(.system(size: 18, weight: .bold)).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(t.subtitle).font(Theme.label(10)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .selectableGradient(t.gradient, selected: on, cornerRadius: 16, ring: Theme.lime)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(t.title), \(t.subtitle)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func row(_ i: Int, _ m: BlockPick) -> some View {
        let e = Exercise.find(m.exerciseId)
        return HStack(spacing: 10) {
            if let e { ExerciseThumbnail(exercise: e, size: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(e?.name ?? m.exerciseId).font(Theme.label(14)).lineLimit(2)
                Menu {
                    ForEach(Array(1...10), id: \.self) { v in
                        Button("\(v) min") { edit { $0[i].minutes = v } }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(m.minutes) min")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(Theme.label(12))
                    .opacity(0.85)
                }
                .accessibilityLabel("\(m.minutes) minutes")
            }
            Spacer(minLength: 4)
            roundButton("arrow.triangle.2.circlepath", label: "Swap") { picker = .swap(i) }
            roundButton("xmark", label: "Remove") { edit { $0.remove(at: i) } }
                .disabled(moves.count <= 1)
                .opacity(moves.count <= 1 ? 0.4 : 1)
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(kind.gradient))
        .accessibilityElement(children: .contain)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.footnote.bold()).frame(width: 32, height: 32).background(Circle().fill(.black.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Turns the current moves into exact moves and changes them.
    private func edit(_ change: (inout [BlockPick]) -> Void) {
        var m = moves
        change(&m)
        guard !m.isEmpty else { return }
        tweaks.setMoves(m, for: kind)
    }

    /// This block already is the profile's default.
    private var matchesDefault: Bool {
        guard let p = model.profile else { return false }
        if let m = tweaks.moves(kind) { return p.picks(kind)?.only == true && p.picks(kind)?.items == m }
        let own = kind == .warmup ? p.warmupStyle?.rawValue : p.cooldownStyle?.rawValue
        return own != nil && own == style
    }

    /// Saves (or with `on` false clears) this block's style and exact moves as the profile's default.
    private func writeDefault(_ on: Bool) {
        guard var p = model.profile else { return }
        let picked = tweaks.moves(kind)
        switch kind {
        case .warmup:
            let s = on ? WarmupStyle(rawValue: style) : nil
            p.warmupStyle = s == .auto ? nil : s
        default:
            let s = on ? CooldownStyle(rawValue: style) : nil
            p.cooldownStyle = s == .auto ? nil : s
        }
        if on, let picked {
            p.setPicks(BlockPicks(items: picked, only: true), for: kind)
        } else if let cur = p.picks(kind), cur.only, picked == nil || cur.items == picked {
            // Exact moves saved as the default earlier (or replaced by a style now).
            p.setPicks(BlockPicks(), for: kind)
        }
        guard p != model.profile else { return }
        model.updateProfile(p)
    }
}
