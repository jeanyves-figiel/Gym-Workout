import SwiftUI
import UniformTypeIdentifiers
import WorkoutEngine

// Editing the Train screen (#260): A's wiggle mode on the page (remove, resize, drag to reorder, look menu,
// Add widget gallery) and B's one-tap presets and Customise list.

/// Edit chrome around one widget: wiggles, − removes, the corner handle cycles its size, the top-right menu
/// picks its look; drag onto another widget to take its place. The widget itself doesn't react while editing.
struct TrainWidgetEditChrome<Content: View>: View {
    let widget: TrainWidget
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
        .overlay(alignment: .topTrailing) { if !widget.kind.looks.isEmpty { lookMenu } }
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
            Label(widget.kind.title, systemImage: widget.kind.symbol)
                .font(Theme.label(15)).foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(widget.kind.palette.gradient))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            withAnimation(.snappy) { model.editTrainLayout { $0.move(id, to: widget.id) } }
            return true
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(widget.kind.title), \(widget.size.title)\(widget.resolvedLook.map { ", \($0.title)" } ?? "")")
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
        .accessibilityLabel("Remove \(widget.kind.title)")
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

    private var lookMenu: some View {
        Menu {
            Picker("Look", selection: Binding(get: { widget.resolvedLook }, set: { look in
                model.editTrainLayout { $0.update(widget.id) { $0.look = look } }
            })) {
                ForEach(widget.kind.looks) { Text($0.title).tag(Optional($0)) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "paintpalette.fill")
                Text(widget.resolvedLook?.title ?? "Look")
            }
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Capsule().fill(.white))
        }
        .padding(8)
        .accessibilityLabel("Look: \(widget.resolvedLook?.title ?? "")")
    }

    private func remove() {
        withAnimation(.snappy) { model.editTrainLayout { $0.remove(widget.id) } }
    }

    private func resize() {
        withAnimation(.snappy) { model.editTrainLayout { $0.update(widget.id) { $0.size = $0.nextSize } } }
    }

    private func shift(_ by: Int) {
        model.editTrainLayout { l in
            guard let i = l.widgets.firstIndex(where: { $0.id == widget.id }) else { return }
            let j = i + by
            guard l.widgets.indices.contains(j) else { return }
            l.widgets.swapAt(i, j)
        }
    }
}

/// Top of Train while editing: presets (B), Add widget, the list view and Done.
struct TrainEditBar: View {
    let onAdd: () -> Void
    let onList: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TrainLayout.Preset.allCases) { p in
                        let on = model.trainPreset == p
                        Button {
                            withAnimation(.snappy) { model.setTrainLayout(model.presetLayout(p)) }
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

/// Add widget gallery (A): every widget as a bold tile with what it shows, its sizes and looks.
struct TrainWidgetGallery: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let layout = model.trainLayout
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    // No Fuel widget while Fuel is hidden (#1004).
                    ForEach(TrainWidgetKind.allCases.filter { $0 != .fuel || TabsPref.shared.shows(.fuel) }) { kind in
                        let on = layout.contains(kind)
                        Button {
                            withAnimation(.snappy) { model.editTrainLayout { $0.add(kind) } }
                            dismiss()
                        } label: {
                            tile(kind, on: on)
                        }
                        .buttonStyle(.plain)
                        .disabled(on)
                        .accessibilityLabel(on ? "\(kind.title), already on Train" : "Add \(kind.title): \(kind.detail)")
                    }
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

    private func tile(_ kind: TrainWidgetKind, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: kind.symbol)
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.25)))
                Spacer()
                if on { Image(systemName: "checkmark.circle.fill").font(.title3) }
            }
            Text(kind.title).font(Theme.display(16)).lineLimit(2).minimumScaleFactor(0.8)
            Text(kind.detail).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(3)
            Spacer(minLength: 0)
            Text((kind.sizes.map(\.title) + kind.looks.map(\.title)).joined(separator: " · "))
                .font(.system(size: 10, weight: .heavy, design: .rounded)).opacity(0.85).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .selectableGradient(kind.palette.gradient, selected: !on, cornerRadius: 20, dim: true)
    }
}

/// Customise Train as a list (B): presets, the widgets in order with size and look, more to add, reset.
struct TrainCustomiseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let layout = model.trainLayout
        NavigationStack {
            // Explore-style gradient rows (#539): one card per widget with its tile, drag ≡ to reorder; removing
            // is instant with Undo.
            List {
                ContentTitle(title: "Customise Train", subtitle: "Drag ≡ to reorder · swipe left to remove")
                    .cardRow()
                Section("Presets") {
                    // Gradient tiles, number left (#823), like the widget rows below.
                    ForEach(Array(TrainLayout.Preset.allCases.enumerated()), id: \.element) { i, p in
                        Button {
                            withAnimation { model.setTrainLayout(model.presetLayout(p)) }
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(i + 1)").font(Theme.display(16))
                                    .frame(width: 30, height: 30)
                                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.2)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.title).font(Theme.label(15))
                                    Text(p.detail).font(.caption.weight(.semibold)).opacity(0.85)
                                }
                                Spacer()
                                SquareToggle(on: model.trainPreset == p)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.trainPreset == p ? .isSelected : [])
                        .gradientRow(Theme.routineGradient(i))
                    }
                }
                Section("On Train") {
                    ForEach(layout.widgets) { w in
                        row(w).gradientRow(w.kind.palette.gradient, ink: w.kind.palette.ink)
                    }
                    .onMove { from, to in model.editTrainLayout { $0.move(fromOffsets: from, toOffset: to) } }
                    .onDelete { idx in remove(idx.map { layout.widgets[$0] }, from: layout) }
                }
                if !layout.addable.isEmpty {
                    Section("Add") {
                        ForEach(layout.addable) { kind in
                            Button {
                                withAnimation { model.editTrainLayout { $0.add(kind, at: $0.widgets.count) } }
                            } label: {
                                HStack(spacing: 10) {
                                    icon(kind)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(kind.title).font(Theme.label(14))
                                        Text(kind.detail).font(.caption.weight(.semibold)).opacity(0.8).lineLimit(2)
                                    }
                                    Spacer()
                                    SquareToggle(on: false, ink: kind.palette.ink)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(kind.title)")
                            .gradientRow(kind.palette.gradient, ink: kind.palette.ink)
                            .opacity(0.75)
                        }
                    }
                }
                Section {
                    Button("Reset to default") { withAnimation { model.setTrainLayout(nil) } }
                        .font(Theme.label(15))
                        .foregroundStyle(Theme.lime)
                        .disabled(!model.trainLayoutCustomised)
                        .darkCardRow()
                }
            }
            .environment(\.editMode, .constant(.active))
            .themedForm()
            .titleInContent("Customise Train")
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    /// Swipe-removed widgets go at once; the Undo bar puts the layout back.
    private func remove(_ widgets: [TrainWidget], from layout: TrainLayout) {
        let ids = widgets.map(\.id)
        model.editTrainLayout { l in ids.forEach { l.remove($0) } }
        UndoCloseCenter.shared.deleted("\(widgets.first?.kind.title ?? "Widget") removed", symbol: "rectangle.stack.badge.minus") { [model] in
            model.setTrainLayout(layout)
        }
    }

    private func icon(_ kind: TrainWidgetKind) -> some View {
        IconTile(symbol: kind.symbol, size: 30, ink: kind.palette.isLight)
            .foregroundStyle(kind.palette.ink)
    }

    private func row(_ w: TrainWidget) -> some View {
        HStack(spacing: 10) {
            icon(w.kind)
            // Two lines ahead of the look and size menus: "Trainin…" (#823).
            Text(w.kind.title).font(Theme.label(14)).lineLimit(2).minimumScaleFactor(0.8).layoutPriority(1)
            Spacer(minLength: 4)
            if !w.kind.looks.isEmpty {
                Menu {
                    Picker("Look", selection: Binding(get: { w.resolvedLook }, set: { look in
                        model.editTrainLayout { $0.update(w.id) { $0.look = look } }
                    })) {
                        ForEach(w.kind.looks) { Text($0.title).tag(Optional($0)) }
                    }
                } label: {
                    Text(w.resolvedLook?.title ?? "").font(Theme.label(12)).underline()
                }
            }
            if w.kind.sizes.count > 1 {
                Menu {
                    Picker("Size", selection: Binding(get: { w.size }, set: { size in
                        model.editTrainLayout { $0.update(w.id) { $0.size = size } }
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
