import Charts
import SwiftUI
import WorkoutEngine

// Customisable Progress (#444, A + C from `history-page/custom-proposals.png`): Train's wiggle mode (#260) on the
// Progress board (remove, resize, drag to reorder, presets, Add widget gallery, Customise list) and optional
// sport widgets, one per sport.

extension ProgressWidgetKind {
    /// The Progress part a tile opens.
    var section: ProgressSection {
        switch self {
        case .training, .consistency, .weekly, .streak, .level, .sport, .chest, .growth: .training
        case .body: .body
        case .records: .records
        case .badges: .badges
        case .muscles: .muscles
        case .history: .history
        case .programmes: .programmes
        }
    }

    var symbol: String {
        switch self {
        case .level: "star.fill"
        case .streak: "flame.fill"
        case .consistency: "square.grid.3x3.fill"
        case .weekly: "chart.bar.fill"
        case .sport: "figure.mixed.cardio"
        case .chest: "gift.fill"
        case .growth: "chart.line.uptrend.xyaxis"
        default: section.symbol
        }
    }

    var colors: [Color] {
        switch self {
        case .level: [Color(red: 0.49, green: 0.94, blue: 0.69), Color(red: 0.29, green: 0.66, blue: 0.94)]
        case .streak: [Theme.lime, Color(red: 0.36, green: 0.84, blue: 0.54)]
        case .consistency: [Theme.lime, Color(red: 0.12, green: 0.85, blue: 0.54)]
        case .weekly: WorkoutEngine.Category.power.colors
        case .sport: Sport.other.colors
        case .chest: [Color(hex: 0xFF7A3D), Color(hex: 0xFF3D8A)]
        case .growth: WorkoutEngine.Category.mobility.colors
        default: section.colors
        }
    }
}

extension ProgressWidget {
    var symbol: String { sport?.symbol ?? kind.symbol }
    var colors: [Color] { sport?.colors ?? kind.colors }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

/// Edit chrome around one board widget: wiggles, − removes, the corner handle cycles its size; drag onto another
/// widget to take its place. The widget itself doesn't react while editing.
struct ProgressWidgetEditChrome<Content: View>: View {
    let widget: ProgressWidget
    @ViewBuilder let content: Content
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = false
    @State private var targeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: TrainWidgetMetrics.corner, style: .continuous)
        ZStack {
            content.allowsHitTesting(false)
            Color.clear.contentShape(shape)
        }
        .overlay(shape.strokeBorder(.white.opacity(targeted ? 0.95 : 0.45), style: StrokeStyle(lineWidth: targeted ? 3 : 1.5, dash: [6, 5])))
        .overlay(alignment: .bottomTrailing) { if widget.kind.sizes.count > 1 { resizeButton } }
        .overlay(alignment: .topLeading) { removeButton }
        .rotationEffect(.degrees(wiggle ? 0.8 : -0.8))
        .scaleEffect(targeted ? 0.97 : 1)
        .animation(.snappy, value: targeted)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true).delay(Double.random(in: 0...0.12))) { wiggle = true }
        }
        .draggable(widget.id.uuidString) {
            Label(widget.title, systemImage: widget.symbol)
                .font(Theme.label(15)).foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(widget.gradient))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            withAnimation(.snappy) { model.editProgressBoard { $0.move(id, to: widget.id) } }
            return true
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(widget.title), \(widget.size.title)")
        .accessibilityHint("Drag onto another widget to move it")
        .accessibilityAction(named: "Remove") { remove() }
        .accessibilityAction(named: "Next size") { resize() }
        .accessibilityAction(named: "Move up") { shift(-1) }
        .accessibilityAction(named: "Move down") { shift(1) }
    }

    private var removeButton: some View {
        Button(action: remove) {
            Image(systemName: "minus")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.3)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.bg, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .offset(x: -8, y: -8)
        .accessibilityLabel("Remove \(widget.title)")
    }

    private var resizeButton: some View {
        Button(action: resize) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                Text(widget.size.letter)
            }
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel("Size \(widget.size.title), change to \(widget.nextSize.title)")
    }

    private func remove() {
        withAnimation(.snappy) { model.editProgressBoard { $0.remove(widget.id) } }
    }

    private func resize() {
        withAnimation(.snappy) { model.editProgressBoard { $0.update(widget.id) { $0.size = $0.nextSize } } }
    }

    private func shift(_ by: Int) {
        model.editProgressBoard { b in
            guard let i = b.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
            let j = i + by
            guard b.widgets.indices.contains(j) else { return }
            b.widgets.swapAt(i, j)
        }
    }
}

/// Top of Progress while editing: presets, Add widget, the list view.
struct ProgressEditBar: View {
    let onAdd: () -> Void
    let onList: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ProgressBoard.Preset.allCases) { p in
                        let on = model.progressBoardPreset == p
                        Button {
                            withAnimation(.snappy) { model.setProgressBoard(model.progressPreset(p)) }
                        } label: {
                            Text(p.title)
                                .font(Theme.label(13))
                                .foregroundStyle(on ? Theme.ink : .white)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(on ? Theme.lime : Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(p.title) preset: \(p.detail)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            HStack(spacing: 8) {
                Button(action: onAdd) {
                    Label("Add widget", systemImage: "plus")
                        .font(Theme.label(14)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.lime))
                }
                .buttonStyle(.plain)
                Button(action: onList) {
                    Label("List", systemImage: "list.bullet")
                        .font(Theme.label(14)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Arrange widgets as a list")
            }
            Text("Drag a widget onto another to move it. The corner button changes its size.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

/// Add widget gallery: every Progress widget, then a card per sport (C).
struct ProgressWidgetGallery: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let board = model.progressBoard
        let mine = model.progressSports
        let others = Sport.allCases.filter { !mine.contains($0) && $0 != .other }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    grid(ProgressWidgetKind.allCases.filter { $0 != .sport }.map { ProgressWidget($0) }, board: board)
                    Text("Your sports").eyebrow().padding(.top, 8)
                    Text("A card for each sport you want to follow: sessions, time and its best.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    grid((mine.isEmpty ? [.climbing] : mine).map { ProgressWidget.sport($0) }, board: board)
                    Text("More sports").eyebrow().padding(.top, 8)
                    grid(others.map { ProgressWidget.sport($0) }, board: board)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    private func grid(_ widgets: [ProgressWidget], board: ProgressBoard) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(widgets) { w in
                let on = board.widgets.contains { $0.kind == w.kind && $0.sport == w.sport }
                Button {
                    // Sport cards go to the top: the member picked them to focus on that sport.
                    withAnimation(.snappy) { model.editProgressBoard { $0.add(w, at: w.kind == .sport ? 0 : nil) } }
                    dismiss()
                } label: {
                    tile(w, on: on)
                }
                .buttonStyle(.plain)
                .disabled(on)
                .accessibilityLabel(on ? "\(w.title), already on Progress" : "Add \(w.title)")
            }
        }
    }

    private func tile(_ w: ProgressWidget, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: w.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.25)))
                Spacer()
                if on { Image(systemName: "checkmark.circle.fill").font(.title3) }
            }
            Text(w.title).font(Theme.display(16)).lineLimit(2).minimumScaleFactor(0.8)
            if w.kind != .sport {
                Text(w.kind.detail).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(3)
            }
            Spacer(minLength: 0)
            Text(w.kind.sizes.map(\.title).joined(separator: " · "))
                .font(.system(size: 10, weight: .heavy, design: .rounded)).opacity(0.85).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: w.kind == .sport ? 120 : 160, alignment: .topLeading)
        .selectableGradient(w.gradient, selected: !on, cornerRadius: 20)
    }
}

/// Customise Progress as a list: presets, the widgets in order with their size, more to add, reset.
struct ProgressCustomiseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let board = model.progressBoard
        NavigationStack {
            // Explore-style gradient rows (#539), as Customise Train: removing is instant with Undo.
            List {
                ContentTitle(title: "Customise Progress",
                             subtitle: "Drag ≡ to reorder · swipe left to remove · Add widget adds a card per sport")
                    .cardRow()
                Section("Presets") {
                    ForEach(ProgressBoard.Preset.allCases) { p in
                        Button {
                            withAnimation { model.setProgressBoard(model.progressPreset(p)) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.title).font(Theme.label(15))
                                    Text(p.detail).font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                SquareToggle(on: model.progressBoardPreset == p)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.progressBoardPreset == p ? .isSelected : [])
                        .darkCardRow()
                    }
                }
                Section("On Progress") {
                    ForEach(board.widgets) { w in row(w).gradientRow(w.gradient) }
                        .onMove { from, to in model.editProgressBoard { $0.move(fromOffsets: from, toOffset: to) } }
                        .onDelete { idx in remove(idx.map { board.widgets[$0] }, from: board) }
                }
                if !board.addable.isEmpty {
                    Section("Add") {
                        ForEach(board.addable) { kind in
                            Button {
                                withAnimation { model.editProgressBoard { $0.add(ProgressWidget(kind)) } }
                            } label: {
                                HStack(spacing: 10) {
                                    icon(ProgressWidget(kind))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(kind.title).font(Theme.label(14))
                                        Text(kind.detail).font(.caption.weight(.semibold)).opacity(0.8).lineLimit(2)
                                    }
                                    Spacer()
                                    SquareToggle(on: false)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(kind.title)")
                            .gradientRow(ProgressWidget(kind).gradient)
                            .opacity(0.75)
                        }
                    }
                }
                Section {
                    Button("Reset to default") { withAnimation { model.setProgressBoard(nil) } }
                        .font(Theme.label(15))
                        .foregroundStyle(Theme.lime)
                        .disabled(!model.progressBoardCustomised)
                        .darkCardRow()
                }
            }
            .environment(\.editMode, .constant(.active))
            .themedForm()
            .titleInContent("Customise Progress")
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    /// Swipe-removed widgets go at once; the Undo bar puts the board back.
    private func remove(_ widgets: [ProgressWidget], from board: ProgressBoard) {
        let ids = widgets.map(\.id)
        model.editProgressBoard { b in ids.forEach { b.remove($0) } }
        UndoCloseCenter.shared.deleted("\(widgets.first?.title ?? "Widget") removed", symbol: "rectangle.stack.badge.minus") { [model] in
            model.setProgressBoard(board)
        }
    }

    private func icon(_ w: ProgressWidget) -> some View {
        IconTile(symbol: w.symbol, size: 30)
    }

    private func row(_ w: ProgressWidget) -> some View {
        HStack(spacing: 10) {
            icon(w)
            Text(w.title).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if w.kind.sizes.count > 1 {
                Menu {
                    Picker("Size", selection: Binding(get: { w.size }, set: { size in
                        model.editProgressBoard { $0.update(w.id) { $0.size = size } }
                    })) {
                        ForEach(w.kind.sizes) { Text($0.title).tag($0) }
                    }
                } label: {
                    Text(w.size.title)
                        .font(Theme.label(12)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.lime))
                }
            } else {
                Text(w.size.title).font(Theme.label(12)).opacity(0.7)
            }
        }
    }
}

/// One sport's card (C): sessions in the last 30 days, time, its best (top grade, longest, farthest);
/// large adds 8 weeks of minutes.
struct SportProgressWidget: View {
    let sport: Sport
    let size: TrainWidgetSize
    /// This sport's sessions, newest first.
    let items: [HistoryItem]

    private var month: [HistoryItem] { items.filter { $0.start > Date().addingTimeInterval(-30 * 86_400) } }

    /// Top grade for climbing, else the farthest or the longest session of the last 30 days.
    private var best: (value: String, label: String)? {
        switch sport {
        case .climbing:
            let grades = month.compactMap { item -> String? in
                guard case .climb(let c) = item else { return nil }
                return c.topGrade
            }
            return Climbs.hardest(grades).map { ($0, "top grade") }
        default:
            let km = month.compactMap { item -> Double? in
                guard case .sport(let s) = item else { return nil }
                return s.distanceKm
            }.max()
            if let km, km > 0 { return (km >= 10 ? "\(Int(km.rounded())) km" : String(format: "%.1f km", km), "farthest") }
            return month.map(\.minutes).max().map { (History.duration($0), "longest") }
        }
    }

    var body: some View {
        let minutes = month.reduce(0) { $0 + $1.minutes }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: sport.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).opacity(0.7)
            }
            .padding(.bottom, 4)
            if size == .small {
                Text("\(month.count)").font(Theme.display(26)).monospacedDigit()
                Text(month.count == 1 ? "session · 30 days" : "sessions · 30 days").font(.caption.weight(.semibold)).opacity(0.9)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    stat("\(month.count)", "sessions")
                    stat(minutes > 0 ? History.duration(minutes) : "0", "time")
                    if let best { stat(best.value, best.label) }
                }
                Text(items.first.map { "Last: \($0.title) · \($0.start.formatted(.relative(presentation: .named)))" } ?? "No sessions yet. Log one from Train.")
                    .font(.caption.weight(.semibold)).opacity(0.9).lineLimit(1)
                if size == .large { weeks.padding(.top, 6) }
            }
            Spacer(minLength: 0)
            Text("\(sport.label) · 30 days").font(Theme.label(11)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(sport.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(Theme.label(9)).tracking(1).opacity(0.85)
        }
    }

    /// Minutes per week, last 8 weeks.
    private var weeks: some View {
        let cal = Progression.calendar()
        let thisWeek = Progression.weekStart(Date(), cal)
        let bars: [(Date, Int)] = (0..<8).reversed().map { ago in
            let start = cal.date(byAdding: .weekOfYear, value: -ago, to: thisWeek)!
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, items.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + $1.minutes })
        }
        return Chart(bars, id: \.0) { b in
            BarMark(x: .value("Week", b.0, unit: .weekOfYear), y: .value("Minutes", b.1))
                .foregroundStyle(.white.opacity(0.85))
                .cornerRadius(4)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 60)
        .accessibilityLabel("Minutes per week, last 8 weeks")
    }
}

/// A widget with nothing to show yet, kept visible while editing.
struct ProgressWidgetPlaceholder: View {
    let widget: ProgressWidget
    let note: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: widget.symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(widget.title).font(Theme.display(18))
                Text(note).font(.caption.weight(.semibold)).opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(widget.gradient.opacity(0.6)))
    }
}
