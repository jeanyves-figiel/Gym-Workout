import SwiftUI
import WorkoutEngine

// Equipment page (#162): a picture of every item in use, grouped by area of the gym, with search, so members who
// don't know a machine's name can still tell whether their gym has it.

extension GymArea {
    var symbol: String {
        switch self {
        case .barbells: "figure.strengthtraining.traditional"
        case .dumbbells: "dumbbell.fill"
        case .cables: "cable.connector"
        case .machines: "gearshape.2.fill"
        case .stations: "figure.climbing"
        case .functional: "figure.cross.training"
        case .cardio: "figure.run.treadmill"
        case .climbing: "figure.climbing"
        }
    }

    var category: WorkoutEngine.Category {
        switch self {
        case .barbells: .strength
        case .dumbbells: .warmup
        case .cables: .cardio
        case .machines: .mobility
        case .stations: .power
        case .functional: .stretch
        case .cardio: .cardio
        case .climbing: .power
        }
    }
}

/// Equipment list as picture tiles: tap to tick or untick. Same binding as before, so every caller keeps working.
struct EquipmentSheet: View {
    @Binding var equipment: [Equipment]
    /// Items kept because the member wasn't sure (marked with a ?).
    var unsure: [Equipment] = []
    /// Redo this gym's list in a few swipes (#180); the sheet closes first, the caller opens the setup.
    var onSetup: (() -> Void)?
    /// Where the items sit in the gym (#274); nil = no zones on this page (trips, new gym setup).
    var layout: Binding<GymLayout?>?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// Zone being painted (#274): a tap moves the picture there instead of ticking it; `GymLayout.noZone` clears it.
    @State private var painting: String?
    /// Pictures grouped by zone instead of by type (#289).
    #if DEBUG
    @State private var byZone = Demo.screen == "equipment-by-zone"
    #else
    @State private var byZone = false
    #endif

    init(equipment: Binding<[Equipment]>, unsure: [Equipment] = [], layout: Binding<GymLayout?>? = nil, onSetup: (() -> Void)? = nil) {
        _equipment = equipment
        self.unsure = unsure
        self.layout = layout
        self.onSetup = onSetup
    }

    private var zones: GymLayout? { layout?.wrappedValue }

    /// Painting: the item goes to the painted zone (and is ticked on: it's there). Else ticked / unticked.
    private func tap(_ e: Equipment) {
        if let id = painting, let layout {
            if id == GymLayout.noZone { layout.wrappedValue?.unassign(e) } else { layout.wrappedValue?.move(e, to: id) }
            if !equipment.contains(e) { equipment.append(e) }
        } else if equipment.contains(e) {
            equipment.removeAll { $0 == e }
        } else {
            equipment.append(e)
        }
    }

    private var anyArea: Bool { GymArea.allCases.contains { a in a.items.contains { $0.matches(query) } } }

    private var floor: [Equipment] { GymArea.floor.filter { $0.matches(query) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if query.isEmpty {
                        hero
                        if let onSetup { setupCard(onSetup) }
                    }
                    if let layout {
                        ZoneBar(layout: layout, painting: $painting, equipment: equipment) { found in
                            equipment += found
                        }
                    }
                    if let zones {
                        Picker("Group pictures", selection: $byZone) {
                            Text("By type").tag(false)
                            Text("By zone").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    if let zones, byZone {
                        zoneSections(zones)
                    } else {
                        ForEach(GymArea.allCases) { area in
                            let items = area.items.filter { $0.matches(query) }
                            if !items.isEmpty {
                                AreaSection(area: area, items: items, equipment: $equipment, unsure: unsure, layout: zones, tap: tap, onMove: move)
                            }
                        }
                        if !floor.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Floor").eyebrow()
                                EquipmentGrid(items: floor, equipment: $equipment, unsure: unsure, layout: zones, tap: tap, onMove: move)
                            }
                        }
                    }
                    if !anyArea && floor.isEmpty {
                        Text("Nothing matches “\(query)”.").font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 24)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search: rack, swiss ball, rower…")
            .autocorrectionDisabled()
            .navigationTitle("Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    /// Touch and hold → move to another zone, or no zone (#289).
    private func move(_ e: Equipment, to id: String?) {
        if let id { layout?.wrappedValue?.move(e, to: id) } else { layout?.wrappedValue?.unassign(e) }
    }

    /// By zone (#289): one coloured section per zone with the gym's items there, then those without a zone.
    @ViewBuilder private func zoneSections(_ l: GymLayout) -> some View {
        ForEach(l.zones) { z in
            let items = z.items.filter { equipment.contains($0) && $0.matches(query) }
            ZoneSection(title: z.name, count: items.count, fill: AnyShapeStyle(z.gradient), dashed: false) {
                EquipmentGrid(items: items, equipment: $equipment, unsure: unsure, layout: l, tap: tap, onMove: move)
            }
        }
        let loose = Equipment.allCases.filter { equipment.contains($0) && l.zone(of: $0) == nil && $0.matches(query) }
        ZoneSection(title: "No zone", count: loose.count, fill: AnyShapeStyle(Theme.cardStrong), dashed: true) {
            if loose.isEmpty {
                Text("Every item has a zone.").font(.caption).foregroundStyle(Theme.muted)
            } else {
                EquipmentGrid(items: loose, equipment: $equipment, unsure: unsure, layout: l, tap: tap, onMove: move)
            }
        }
    }

    private func setupCard(_ action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime.opacity(0.18)))
                    .foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up this gym in a few swipes").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("One card per area instead of ticking items").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(.white)
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text("What's at your gym").font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.7)
                Text("Tap a picture to tick or untick it. Not sure? Leave it on and say \"Not here?\" in a workout.")
                    .font(.footnote.weight(.semibold)).opacity(0.88)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(equipment.count)").font(Theme.display(26))
                Text("OF \(Equipment.allCases.count)").font(Theme.label(9)).tracking(1.2).opacity(0.8)
            }
            .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
    }
}

private struct AreaSection: View {
    let area: GymArea
    let items: [Equipment]
    @Binding var equipment: [Equipment]
    let unsure: [Equipment]
    var layout: GymLayout?
    var tap: ((Equipment) -> Void)?
    var onMove: ((Equipment, String?) -> Void)?

    var body: some View {
        let on = items.filter { equipment.contains($0) }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: area.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(area.category.gradient))
                Text(area.label).font(Theme.display(19))
                Text("\(on)/\(items.count)").font(Theme.label(12)).foregroundStyle(Theme.muted).monospacedDigit()
                Spacer()
                Button(on == items.count ? "None" : "All") {
                    if on == items.count { equipment.removeAll { items.contains($0) } } else { equipment += items.filter { !equipment.contains($0) } }
                }
                .font(.caption.bold())
                .foregroundStyle(Theme.lime)
            }
            EquipmentGrid(items: items, equipment: $equipment, unsure: unsure, layout: layout, tap: tap, onMove: onMove)
        }
    }
}

/// By zone section (#289): a bar in the zone's colours with its name and count, the pictures under it.
private struct ZoneSection<Content: View>: View {
    let title: String
    let count: Int
    let fill: AnyShapeStyle
    let dashed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(Theme.display(18)).lineLimit(1)
                Spacer()
                Text("\(count)").font(Theme.display(18)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: dashed ? 1.5 : 0, dash: [5, 4])).foregroundStyle(Theme.muted))
            content
        }
    }
}

struct EquipmentGrid: View {
    let items: [Equipment]
    @Binding var equipment: [Equipment]
    var unsure: [Equipment] = []
    /// Zones (#274): each picture shows its zone's colour; `tap` paints or ticks (default: tick / untick).
    var layout: GymLayout?
    var tap: ((Equipment) -> Void)?
    /// Touch and hold a picture to move it to another zone or no zone (#289).
    var onMove: ((Equipment, String?) -> Void)?

    private func mover(_ e: Equipment) -> ((String?) -> Void)? {
        guard let onMove else { return nil }
        return { (id: String?) in onMove(e, id) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 12) {
            ForEach(items) { e in
                EquipmentTile(item: e, on: equipment.contains(e), unsure: unsure.contains(e), zone: layout?.zone(of: e),
                              zones: layout?.zones, onMove: mover(e)) {
                    if let tap { return tap(e) }
                    if equipment.contains(e) { equipment.removeAll { $0 == e } } else { equipment.append(e) }
                }
            }
        }
    }
}

/// Picture of the item in use, its name under it; ticked items are bright with a lime check.
struct EquipmentTile: View {
    let item: Equipment
    let on: Bool
    var unsure = false
    /// Zone it sits in (#274): ribbon with its name and a border in its colours (#289).
    var zone: GymLayout.Zone?
    /// The gym's zones when it has them (nil = no zones): a ticked picture without a zone says "No zone".
    var zones: [GymLayout.Zone]?
    /// Touch and hold: move to a zone id, or nil for no zone.
    var onMove: ((String?) -> Void)?
    let action: () -> Void

    private var border: AnyShapeStyle {
        guard on else { return AnyShapeStyle(Theme.stroke) }
        guard zones != nil else { return AnyShapeStyle(Theme.lime) }
        return zone.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Theme.muted)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ExerciseImage(exercise: Exercise.get(item.pictureExerciseId))
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .saturation(on ? 1 : 0)
                    .opacity(on ? 1 : 0.45)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(border, style: StrokeStyle(lineWidth: on ? 3 : 1, dash: on && zones != nil && zone == nil ? [6, 4] : [])))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: on ? (unsure ? "questionmark.circle.fill" : "checkmark.circle.fill") : "circle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(on ? Theme.ink : .white, on ? Theme.lime : .white.opacity(0.0))
                            .padding(6)
                    }
                    .overlay(alignment: .bottom) {
                        if on, zones != nil { ribbon }
                    }
                Text(item.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(on ? .white : Theme.muted)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let zones, let onMove {
                Section("Where is it?") {
                    ForEach(zones) { z in
                        Button(z.id == zone?.id ? "\(z.name) ✓" : z.name) { onMove(z.id) }
                    }
                    Button("No zone", systemImage: "xmark.circle") { onMove(nil) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityLabel(zones == nil ? item.label : "\(item.label), \(zone?.name ?? "no zone")")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? "At this gym. Double-tap to remove." : "Not at this gym. Double-tap to add.")
    }

    /// Zone name on its colours across the bottom of the picture (#289); grey "No zone" when it has none.
    private var ribbon: some View {
        Text((zone?.name ?? "No zone").uppercased())
            .font(Theme.label(10)).tracking(0.6)
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(zone == nil ? Theme.muted : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(zone.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color.black.opacity(0.7)))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }
}
