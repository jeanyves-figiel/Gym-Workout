import SwiftUI
import WorkoutEngine

// MARK: - Build as I go (#490: mockups A + B + C, all three)

/// The player before the first exercise: what first? Coach's picks (B), muscle tiles and search (A), what the member
/// did lately. One screen, no scrolling.
struct FreestyleStartView: View {
    let started: Date
    let picks: [Exercise]
    let recent: [Exercise]
    let onPick: (Exercise) -> Void
    let onBrowse: (MuscleGroup?) -> Void
    let onClose: () -> Void

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
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().stroke(Theme.stroke, lineWidth: 1.5))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("FREESTYLE", systemImage: "plus.square.on.square").font(Theme.label(11)).tracking(1.2).opacity(0.9)
                Text("What first?").font(Theme.display(32)).lineLimit(1).minimumScaleFactor(0.6)
                Text("Add exercises as you go. Each one is logged like a planned workout.")
                    .font(Theme.label(12)).opacity(0.85).lineLimit(2).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient.freestyle))

            if !picks.isEmpty {
                Text("Coach picks").eyebrow()
                FreestylePickRow(picks: picks, height: 74, onPick: onPick)
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
                        Button { onPick(e) } label: {
                            HStack(spacing: 10) {
                                FreestyleThumb(exercise: e, size: 34)
                                Text(e.name).font(Theme.label(14)).lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "plus").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.lime)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(e.name)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .readableColumn()
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

/// In Up next's place (#490 B; always since #581): the Coach's three next picks, one tap = next, and
/// More for the whole catalog. Same height as Up next, so nothing else moves.
struct FreestyleNextBar: View {
    let picks: [Exercise]
    /// This exercise is done: the picks light up, as what comes next.
    var ready = false
    let onPick: (Exercise) -> Void
    let onMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(ready ? "Pick next · Coach" : "Next · Coach picks").font(Theme.label(10)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                Spacer(minLength: 4)
                Button(action: onMore) {
                    Label("More", systemImage: "magnifyingglass")
                        .font(Theme.label(10)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.lime))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add another exercise")
                .accessibilityIdentifier("freestyle.more")
            }
            FreestylePickRow(picks: picks, height: 44, onPick: onPick)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardStrong))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.lime, lineWidth: ready ? 2 : 0))
        .animation(.spring(duration: 0.3), value: ready)
        .accessibilityIdentifier("freestyle.next")
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
    let onPick: (Exercise) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(picks, id: \.id) { e in
                Button { onPick(e) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.name).font(Theme.label(height > 60 ? 13 : 11)).lineLimit(2).minimumScaleFactor(0.7)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Text(e.primary.first?.group.label ?? e.category.label).font(Theme.label(9)).opacity(0.85).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(7)
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(e.primary.first?.group.gradient ?? WorkoutEngine.Category.strength.gradient))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(e.name)")
            }
        }
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
                    Text(resuming ? "Resume freestyle" : "Build as I go").font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("Start empty, add exercises as you train").font(Theme.label(12)).opacity(0.9).lineLimit(1)
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
