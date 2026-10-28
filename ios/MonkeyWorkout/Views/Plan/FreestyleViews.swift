import SwiftUI
import WorkoutEngine

// MARK: - Build as I go (#490: mockups A + B + C, all three)

/// The player before the first exercise: what first? Coach's picks (B), muscle tiles and search (A), what the member
/// did lately. One screen, no scrolling. + on a pick or a recent one lines it up (#795): the next tap starts the first
/// exercise with the lined-up ones queued after it, or the header card starts the lined-up ones in order.
struct FreestyleStartView: View {
    let started: Date
    let picks: [Exercise]
    let recent: [Exercise]
    @Binding var lined: [Exercise]
    let onPick: (Exercise) -> Void
    let onStartLined: () -> Void
    let onBrowse: (MuscleGroup?) -> Void
    /// Ask Coach bar (#856): type, talk or snap the machine.
    var onCoach: ((FreestyleCoachEntry) -> Void)? = nil
    let onClose: () -> Void
    @AppStorage(AskCoachPref.bubbleKey) private var coachShown = true
    @State private var gate: ProGate?

    private static let tiles: [MuscleGroup] = [.chest, .back, .legs, .shoulders, .arms, .core, .hips]
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "pause.fill").font(.system(size: 16, weight: .heavy))
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
                }
                .accessibilityLabel("Pause or leave workout")
                Spacer()
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    Text(Format.elapsed(ctx.date.timeIntervalSince(started))).font(Theme.label(14)).monospacedDigit()
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().stroke(Theme.stroke, lineWidth: 1.5))
                }
            }

            if lined.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("FREESTYLE", systemImage: "plus.square.on.square").font(Theme.label(11)).tracking(1.2).opacity(0.9)
                    Text("What first?").font(Theme.display(32)).lineLimit(1).minimumScaleFactor(0.6)
                    Text("Tap to start one, + to line up the next ones too.")
                        .font(Theme.label(12)).opacity(0.85).lineLimit(2).minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient.freestyle))
            } else {
                // Same place and size: the header becomes START with what's lined up.
                Button(action: onStartLined) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("\(lined.count) LINED UP", systemImage: "list.number").font(Theme.label(11)).tracking(1.2).opacity(0.9)
                            Text("Start").font(Theme.display(32)).lineLimit(1)
                            Text(lined.map(\.name).joined(separator: " → "))
                                .font(Theme.label(12)).opacity(0.85).lineLimit(2).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "play.fill").font(.system(size: 20, weight: .heavy))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                            .foregroundStyle(Theme.ink)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient.freestyle))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("freestyle.startLined")
            }

            if coachShown, let onCoach { FreestyleCoachBar { entry in ProStore.shared.run(.askCoach, $gate) { onCoach(entry) } } }

            if !picks.isEmpty {
                Text("Coach picks").eyebrow()
                FreestylePickRow(picks: picks, height: coachShown && onCoach != nil ? 66 : 74, lined: lined.map(\.id), onLine: line, onPick: onPick)
            }

            Text("By muscle").eyebrow()
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(Self.tiles) { g in
                    Button { onBrowse(g) } label: { tile(g.label, symbol: g.symbol, fill: g.gradient) }
                        .buttonStyle(.plain)
                }
                Button { onBrowse(nil) } label: {
                    tile("Search", symbol: "magnifyingglass", fill: LinearGradient(colors: [Theme.lime, Theme.lime], startPoint: .top, endPoint: .bottom), ink: Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("freestyle.search")
            }

            if !recent.isEmpty {
                Text("Lately").eyebrow()
                VStack(spacing: 6) {
                    ForEach(recent.prefix(2), id: \.id) { e in
                        let at = lined.firstIndex { $0.id == e.id }
                        HStack(spacing: 10) {
                            Button { onPick(e) } label: {
                                HStack(spacing: 10) {
                                    FreestyleThumb(exercise: e, size: 34)
                                    Text(e.name).font(Theme.label(14)).lineLimit(1)
                                    Spacer(minLength: 4)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start \(e.name)")
                            Button { line(e) } label: { FreestyleLineMark(position: at.map { $0 + 1 }, size: 34) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(at == nil ? "Line up \(e.name)" : "Take \(e.name) out of the line-up")
                            // ▶ beside + on every card (#856): start now or build the list first, both one tap.
                            Button { onPick(e) } label: { FreestylePlayMark(size: 34) }
                                .buttonStyle(.plain)
                                .accessibilityHidden(true)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .readableColumn()
        .proPaywall($gate)
    }

    /// + lines an exercise up, tapped again takes it out.
    private func line(_ e: Exercise) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            if let i = lined.firstIndex(where: { $0.id == e.id }) { lined.remove(at: i) } else { lined.append(e) }
        }
    }

    private func tile(_ title: String, symbol: String, fill: LinearGradient, ink: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol).font(.system(size: 15, weight: .heavy))
            Spacer(minLength: 4)
            Text(title).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(ink)
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
        .accessibilityElement(children: .combine)
    }
}

/// Queue shelf in Up next's place (#795, design A): what's lined up first (outlined), then the Coach's picks to fill
/// three tiles, and + for the whole catalog. A tap on a pick lines it up and never leaves this exercise; a lined-up
/// one opens. Same height as Up next, so nothing else moves.
struct FreestyleQueueBar: View {
    let queued: [Exercise]
    let picks: [Exercise]
    /// This exercise is done and nothing is lined up: the picks light up, as what comes next.
    var ready = false
    let onQueued: (Int) -> Void
    let onPick: (Exercise) -> Void
    let onMore: () -> Void

    private static let slots = 3

    var body: some View {
        let shown = Array(queued.prefix(Self.slots))
        let fill = Array(picks.filter { p in !queued.contains { $0.id == p.id } }.prefix(Self.slots - shown.count))
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(queued.isEmpty ? (ready ? "Pick next · Coach" : "Line up next · Coach picks") : "Queue · \(queued.count) lined up")
                    .font(Theme.label(10)).tracking(1.2).textCase(.uppercase).opacity(0.85).lineLimit(1)
                Spacer(minLength: 4)
                Button(action: onMore) {
                    Label("More", systemImage: "magnifyingglass")
                        .font(Theme.label(10)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.lime))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Line up another exercise")
                .accessibilityIdentifier("freestyle.more")
            }
            HStack(spacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, e in
                    Button { onQueued(i) } label: {
                        tile(e, detail: i == 0 ? "Next" : "\(i + 1)\(i == 1 ? "nd" : "rd")", lined: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(e.name), lined up \(i + 1)")
                }
                ForEach(fill, id: \.id) { e in
                    Button { onPick(e) } label: { tile(e, detail: "+ Coach", lined: false) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Line up \(e.name)")
                }
                Button(action: onMore) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.lime)
                        .frame(width: 38, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.lime, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Line up an exercise from the catalog")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardStrong))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.lime, lineWidth: ready ? 2 : 0))
        .animation(.spring(duration: 0.3), value: ready)
        .animation(.snappy, value: queued.map(\.id))
        .accessibilityIdentifier("freestyle.next")
    }

    private func tile(_ e: Exercise, detail: String, lined: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(e.name).font(Theme.label(11)).lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Text(detail).font(Theme.label(9)).opacity(0.9).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(e.primary.first?.group.gradient ?? WorkoutEngine.Category.strength.gradient))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: lined ? 2 : 0))
    }
}

/// + / lined-up number beside a start-screen exercise (#795).
struct FreestyleLineMark: View {
    /// Place in the line-up; nil = not lined up.
    let position: Int?
    let size: CGFloat

    var body: some View {
        Group {
            if let position {
                Text("\(position)").font(Theme.label(size > 30 ? 15 : 12)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.lime))
            } else {
                Image(systemName: "plus").font(.system(size: size > 30 ? 14 : 11, weight: .heavy))
                    .foregroundStyle(Theme.lime)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(.black.opacity(0.28)))
            }
        }
        .contentShape(Rectangle())
    }
}

/// Build as I go's trail (#581, design C) in place of "1/1": done exercises ✓, this one lime, queued ones outlined, and
/// + to queue another. One row; scrolls sideways when long, keeping this exercise in view.
struct FreestyleTrail: View {
    enum Mark { case done, now, queued }
    struct Item: Identifiable {
        let uid: String
        let name: String
        let state: Mark
        var id: String { uid }
    }
    let items: [Item]
    let onTap: (String) -> Void
    let onAdd: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { it in
                        Button { onTap(it.uid) } label: { chip(it) }
                            .buttonStyle(.plain)
                            .id(it.uid)
                            .accessibilityLabel("\(it.name), \(it.state == .done ? "done" : it.state == .now ? "now" : "queued")")
                    }
                    Button(action: onAdd) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .heavy))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardStrong))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add an exercise to this workout")
                }
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: items.first { $0.state == .now }?.uid) { scroll(proxy, animated: true) }
        }
        .frame(height: 30)
        .foregroundStyle(.white)
        .accessibilityIdentifier("freestyle.trail")
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let uid = items.first(where: { $0.state == .now })?.uid else { return }
        if animated { withAnimation(.snappy) { proxy.scrollTo(uid, anchor: .center) } } else { proxy.scrollTo(uid, anchor: .center) }
    }

    private func chip(_ it: Item) -> some View {
        HStack(spacing: 4) {
            Image(systemName: it.state == .done ? "checkmark" : it.state == .now ? "circle.fill" : "clock")
                .font(.system(size: it.state == .now ? 7 : 10, weight: .heavy))
            Text(it.name).font(Theme.label(11)).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .foregroundStyle(it.state == .now ? Theme.ink : it.state == .done ? Theme.lime : .white)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(it.state == .now ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.white.opacity(it.state == .queued ? 0.35 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

/// The Coach's picks as gradient tiles in the colour of the muscle each one trains.
struct FreestylePickRow: View {
    let picks: [Exercise]
    let height: CGFloat
    /// Ids lined up on the start screen (#795), in order.
    var lined: [String] = []
    /// + in each tile's corner lines it up; nil = no corner button.
    var onLine: ((Exercise) -> Void)? = nil
    let onPick: (Exercise) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(picks, id: \.id) { e in
                Button { onPick(e) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.name).font(Theme.label(height > 60 ? 13 : 11)).lineLimit(2).minimumScaleFactor(0.7)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        // With ▶ and + in the corner (#856) the tile's colour says the muscle.
                        if onLine == nil {
                            Text(e.primary.first?.group.label ?? e.category.label).font(Theme.label(9)).opacity(0.85).lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(7)
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(e.primary.first?.group.gradient ?? WorkoutEngine.Category.strength.gradient))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(onLine == nil ? "Add \(e.name)" : "Start \(e.name)")
                .overlay(alignment: .bottomTrailing) {
                    if let onLine {
                        let at = lined.firstIndex(of: e.id)
                        HStack(spacing: 4) {
                            Button { onLine(e) } label: { FreestyleLineMark(position: at.map { $0 + 1 }, size: 26) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(at == nil ? "Line up \(e.name)" : "Take \(e.name) out of the line-up")
                            // ▶ beside + (#856): the tile starts it too, the mark says so.
                            Button { onPick(e) } label: { FreestylePlayMark(size: 26) }
                                .buttonStyle(.plain)
                                .accessibilityHidden(true)
                        }
                        .padding(5)
                    }
                }
            }
        }
    }
}

/// ▶ beside + on a start-screen exercise (#856): start this one now.
struct FreestylePlayMark: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "play.fill").font(.system(size: size > 30 ? 13 : 10, weight: .heavy))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.lime))
            .contentShape(Rectangle())
    }
}

/// How the member opens Coach from the freestyle screen (#856).
enum FreestyleCoachEntry {
    case type, talk, photo
}

/// Ask Coach bar on the freestyle start screen (#856, design A): tap to type, 📷 to snap the machine in front of you,
/// 🎙 to talk. Coach answers with exercises to start (▶) or line up (+).
struct FreestyleCoachBar: View {
    @Environment(AppModel.self) private var model
    let open: (FreestyleCoachEntry) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { open(.type) } label: {
                HStack(spacing: 10) {
                    MonkeyFace(mood: .fired, scale: 0.45, gear: model.rank.gear)
                        .frame(width: 30, height: 28)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(RadialGradient(colors: [Color(hex: 0xEDFF7A), Theme.lime], center: .init(x: 0.3, y: 0.3), startRadius: 2, endRadius: 30)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Ask Coach").font(Theme.label(14)).lineLimit(1)
                        Text("A muscle, a machine, an idea").font(Theme.label(11)).foregroundStyle(Theme.muted).lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Coach what to do")
            .accessibilityIdentifier("freestyle.coach")
            Button { open(.photo) } label: { icon("camera.fill", fill: Theme.cardStrong, ink: .white) }
                .buttonStyle(.plain)
                .accessibilityLabel("Snap the machine in front of you")
            Button { open(.talk) } label: { icon("mic.fill", fill: Theme.lime, ink: Theme.ink) }
                .buttonStyle(.plain)
                .accessibilityLabel("Talk to Coach")
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.lime.opacity(0.7), lineWidth: 1.5))
    }

    private func icon(_ symbol: String, fill: Color, ink: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .heavy))
            .foregroundStyle(ink)
            .frame(width: 44, height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(fill))
            .contentShape(Rectangle())
    }
}

/// Lime "Add" for the hero card (#490 C): adds to the queue at any time.
struct FreestyleAddChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add", systemImage: "plus")
                .font(Theme.label(11)).lineLimit(1).fixedSize()
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add an exercise to this workout")
        .accessibilityIdentifier("player.add")
    }
}

private struct FreestyleThumb: View {
    let exercise: Exercise
    let size: CGFloat

    var body: some View {
        if ExerciseImage.hasMedia(exercise) {
            ExerciseThumbnail(exercise: exercise, size: size)
        } else {
            Image(systemName: exercise.category.symbol)
                .font(.system(size: size * 0.42, weight: .heavy))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(.white.opacity(0.2)))
        }
    }
}

extension LinearGradient {
    /// Build as I go: violet to magenta, as in the mockups.
    static let freestyle = LinearGradient(colors: [Color(hex: 0xB23DFF), Color(hex: 0xFF4FD8)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Workout library entry (#490 C): start an empty workout and build it in the player.
struct FreestyleCard: View {
    let resuming: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus.square.on.square").font(.system(size: 22, weight: .heavy))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(resuming ? "Resume custom session" : Freestyle.title).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("Start empty, pick exercises for your gym").font(Theme.label(12)).opacity(0.9).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill").font(.system(size: 16, weight: .heavy))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime))
                    .foregroundStyle(Theme.ink)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient.freestyle))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.freestyle")
    }
}
