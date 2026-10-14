import SwiftUI
import WorkoutEngine

// Gym zones (#274): where the equipment sits in the member's gym. Design A + B: zone chips on the Equipment page
// (pick a zone, tap pictures to move them there), plus an optional rough floor plan that tells which zones are next
// to each other. Workouts keep supersets and circuits inside one zone.

extension GymLayout.Zone {
    static let palette: [(UInt32, UInt32)] = [
        (0x2F6BFF, 0x8A4DFF), (0xFF8A00, 0xFF3D8A), (0x00C9A7, 0x2EC5FF), (0xFFC23D, 0xFF7A3D),
        (0xA64DFF, 0xFF4DD8), (0x1ED98A, 0xB6FF6B), (0xFF2D55, 0xFF6FB5), (0x3DD6FF, 0x3D5AFF),
    ]

    var colors: [Color] {
        let p = Self.palette[color % Self.palette.count]
        return [Color(hex: p.0), Color(hex: p.1)]
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

/// Small zone tag: "📍 Free weights" on the zone's colours.
struct ZoneTag: View {
    let zone: GymLayout.Zone
    var text: String?

    var body: some View {
        Label(text ?? zone.name, systemImage: "mappin.circle.fill")
            .font(Theme.label(11))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(zone.gradient))
            .accessibilityLabel("In \(zone.name)")
    }
}

/// Equipment page band: switch zones on, pick the zone to paint with, add / edit zones, open the floor plan.
struct ZoneBar: View {
    @Binding var layout: GymLayout?
    /// Zone being painted: tapping a picture moves it there. nil = tap ticks / unticks as usual.
    @Binding var painting: String?
    let equipment: [Equipment]
    @State private var editing: GymLayout.Zone?
    @State private var plan = false

    var body: some View {
        if let current = layout {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Where is it in your gym?").font(.system(size: 16, weight: .heavy, design: .rounded))
                        Text(painting == nil ? "Pick a zone, then tap the pictures that sit there."
                             : painting == GymLayout.noZone ? "Tap pictures to clear their zone. Tap No zone again when done."
                             : "Tap pictures to move them here. Tap the zone again when done.")
                            .font(.caption.weight(.semibold)).opacity(0.88)
                    }
                    Spacer(minLength: 0)
                }
                // All zones on as many lines as they need (#289), then "No zone" to clear a picture's zone.
                FlowLayout(spacing: 6) {
                    ForEach(current.zones) { z in chip(z, count: z.items.filter { equipment.contains($0) }.count) }
                    noZoneChip(count: equipment.filter { current.zone(of: $0) == nil }.count)
                    Button {
                        let z = GymLayout.Zone(name: "Zone \(current.zones.count + 1)", color: current.nextColor, items: [])
                        layout?.zones.append(z)
                        editing = z
                    } label: {
                        Label("Zone", systemImage: "plus").font(Theme.label(12))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.35)))
                            .foregroundStyle(Theme.lime)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    Button { plan = true } label: {
                        Label(current.hasPlan ? "Floor plan" : "Draw a floor plan (optional)", systemImage: "square.grid.3x3.square")
                            .font(Theme.label(12))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Menu {
                        Button("Back to the usual layout", systemImage: "arrow.counterclockwise") { painting = nil; layout = .starter }
                        Button("Turn zones off", systemImage: "xmark.circle", role: .destructive) { painting = nil; layout = nil }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill").font(.system(size: 22))
                    }
                    .accessibilityLabel("Zone options")
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(paintGradient(current)))
            .animation(.spring(duration: 0.3), value: painting)
            .sheet(item: $editing) { z in
                ZoneEditSheet(zone: z, canDelete: current.zones.count > 1) { edited in
                    if let i = layout?.zones.firstIndex(where: { $0.id == edited.id }) { layout?.zones[i] = edited }
                } onDelete: {
                    if painting == z.id { painting = nil }
                    layout?.remove(z.id)
                }
            }
            .sheet(isPresented: $plan) { FloorPlanSheet(layout: Binding(get: { layout ?? current }, set: { layout = $0 }), equipment: equipment) }
        } else {
            Button { layout = .starter } label: {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group by where it sits").font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Supersets stay in one spot, no crossing the gym").font(.caption.weight(.semibold)).opacity(0.85)
                    }
                    Spacer()
                    Text("SET UP").font(Theme.label(11)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.lime))
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(GymLayout.Zone.starterGradient))
            }
            .buttonStyle(.plain)
        }
    }

    private func paintGradient(_ l: GymLayout) -> LinearGradient {
        if painting == GymLayout.noZone {
            return LinearGradient(colors: [Color(hex: 0x3A3A44), Color(hex: 0x1E1E24)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return painting.flatMap { l.zone(id: $0)?.gradient } ?? GymLayout.Zone.starterGradient
    }

    /// Eraser (#289): pictures tapped while it's on lose their zone (they then fit any zone in a workout).
    private func noZoneChip(count: Int) -> some View {
        let on = painting == GymLayout.noZone
        return Button {
            painting = on ? nil : GymLayout.noZone
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "eraser.fill")
                Text("No zone")
                Text("\(count)").monospacedDigit().opacity(0.8)
            }
            .font(Theme.label(12))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.45)))
            .overlay(Capsule().strokeBorder(.white.opacity(on ? 1 : 0.6), style: StrokeStyle(lineWidth: on ? 2.5 : 1.2, dash: on ? [] : [4, 3])))
            .scaleEffect(on ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint("Double-tap, then tap pictures to clear their zone.")
    }

    private func chip(_ z: GymLayout.Zone, count: Int) -> some View {
        let on = painting == z.id
        return Button {
            painting = on ? nil : z.id
        } label: {
            HStack(spacing: 5) {
                Text(z.name).lineLimit(1)
                Text("\(count)").monospacedDigit().opacity(0.8)
            }
            .font(Theme.label(12))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(z.gradient))
            .overlay(Capsule().strokeBorder(.white, lineWidth: on ? 2.5 : 0))
            .scaleEffect(on ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename or recolour", systemImage: "pencil") { editing = z }
        }
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint("Double-tap to move items here. Touch and hold to rename.")
    }
}

extension GymLayout.Zone {
    static let starterGradient = LinearGradient(colors: [Color(hex: 0x2F6BFF), Color(hex: 0x00C9A7)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Rename, recolour or delete a zone.
private struct ZoneEditSheet: View {
    @State var zone: GymLayout.Zone
    let canDelete: Bool
    let onSave: (GymLayout.Zone) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Zone name", text: $zone.name)
                    .font(Theme.display(22))
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(zone.gradient))
                Text("Colour").eyebrow()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(GymLayout.Zone.palette.indices, id: \.self) { i in
                        let c = GymLayout.Zone.palette[i]
                        Button { zone.color = i } label: {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: c.0), Color(hex: c.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(height: 48)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white, lineWidth: zone.color == i ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(i + 1)")
                    }
                }
                if canDelete {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete zone", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .padding(.top, 6)
                    Text("Its items go back to where they usually are.").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        zone.name = zone.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Zone" : zone.name
                        onSave(zone)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

/// Rough floor plan (B): drag zone blocks to where they are and resize them from the corner. Blocks that touch count
/// as next to each other, so a superset can use both.
struct FloorPlanSheet: View {
    @Binding var layout: GymLayout
    let equipment: [Equipment]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?

    private static let grid = 0.05

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Drag each zone to where it is. Pull the corner to resize. Zones that touch count as next to each other.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    GeometryReader { geo in
                        let size = geo.size
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(Theme.stroke))
                            ForEach(layout.zones) { z in
                                if let r = z.rect { block(z, r, size) }
                            }
                        }
                    }
                    .aspectRatio(0.8, contentMode: .fit)

                    let unplaced = layout.zones.filter { $0.rect == nil }
                    if !unplaced.isEmpty {
                        Text("Tap to put on the plan").eyebrow()
                        UnplacedZoneChips(zones: unplaced) { place($0) }
                    }
                    if let id = selected, let z = layout.zone(id: id) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                ZoneTag(zone: z)
                                Spacer()
                                Button("Take off the plan") {
                                    setRect(id, nil)
                                    selected = nil
                                }
                                .font(.caption.bold()).foregroundStyle(Theme.lime)
                            }
                            let items = z.items.filter { equipment.contains($0) }
                            Text(items.isEmpty ? "Nothing here yet" : items.map(\.label).joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.muted)
                            let next = layout.zones.filter { $0.id != z.id && $0.rect != nil && layout.near(z, $0) }
                            Text(next.isEmpty ? "No zone next to it" : "Next to: " + next.map(\.name).joined(separator: ", "))
                                .font(.caption.weight(.bold))
                        }
                        .card(padding: 12)
                    }
                    if layout.hasPlan {
                        Button("Clear the plan", role: .destructive) {
                            for z in layout.zones { setRect(z.id, nil) }
                            selected = nil
                        }
                        .font(.footnote.bold())
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Gym layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if !layout.hasPlan { autoPlace() } }
        }
        .preferredColorScheme(.dark)
    }

    private func block(_ z: GymLayout.Zone, _ r: GymLayout.Rect, _ size: CGSize) -> some View {
        let on = selected == z.id
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(z.gradient)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(z.name).font(Theme.label(12)).lineLimit(2)
                    Text("\(z.items.filter { equipment.contains($0) }.count)").font(Theme.label(10)).opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(6)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.black.opacity(0.3)))
                    .padding(2)
                    .highPriorityGesture(DragGesture(minimumDistance: 1).onChanged { g in
                        if dragBase == nil { dragBase = r }
                        let b = dragBase ?? r
                        var n = b
                        let dx = Double(g.translation.width / size.width), dy = Double(g.translation.height / size.height)
                        n.w = snap(max(0.15, min(1 - b.x, b.w + dx)))
                        n.h = snap(max(0.1, min(1 - b.y, b.h + dy)))
                        setRect(z.id, n)
                    }.onEnded { _ in dragBase = nil })
                    .accessibilityLabel("Resize \(z.name)")
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: on ? 2.5 : 0))
            .frame(width: CGFloat(r.w) * size.width - 3, height: CGFloat(r.h) * size.height - 3)
            .offset(x: CGFloat(r.x) * size.width + 1.5, y: CGFloat(r.y) * size.height + 1.5)
            .onTapGesture { selected = on ? nil : z.id }
            .gesture(DragGesture(minimumDistance: 4).onChanged { g in
                if dragBase == nil { dragBase = r }
                let b = dragBase ?? r
                var n = b
                let dx = Double(g.translation.width / size.width), dy = Double(g.translation.height / size.height)
                n.x = snap(max(0, min(1 - b.w, b.x + dx)))
                n.y = snap(max(0, min(1 - b.h, b.y + dy)))
                setRect(z.id, n)
                selected = z.id
            }.onEnded { _ in dragBase = nil })
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(z.name) on the floor plan")
    }

    @State private var dragBase: GymLayout.Rect?

    private func snap(_ v: Double) -> Double { (v / Self.grid).rounded() * Self.grid }

    private func setRect(_ id: String, _ r: GymLayout.Rect?) {
        if let i = layout.zones.firstIndex(where: { $0.id == id }) { layout.zones[i].rect = r }
    }

    /// First open: zones laid out two per row, so the member only moves what differs.
    private func autoPlace() {
        let n = layout.zones.count
        let rows = max(1, (n + 1) / 2)
        let h: Double = snap(min(0.3, 1 / Double(rows)))
        for (i, z) in layout.zones.enumerated() {
            setRect(z.id, Self.spot(i, height: h, gap: 0.05))
        }
    }

    /// A zone put on the plan: in the first free spot of a 2-column grid, else top left.
    private func place(_ z: GymLayout.Zone) {
        let taken: [GymLayout.Rect] = layout.zones.compactMap(\.rect)
        var free: GymLayout.Rect?
        for i in 0..<10 {
            let s = Self.spot(i, height: 0.15, gap: 0.05)
            if s.y + s.h <= 1 && !taken.contains(where: { $0.gap(to: s) == 0 }) { free = s; break }
        }
        setRect(z.id, free ?? Self.spot(0, height: 0.15, gap: 0))
        selected = z.id
    }

    /// Spot `i` of a 2-column grid: left / right, rows of `height` with `gap` between them.
    private static func spot(_ i: Int, height: Double, gap: Double) -> GymLayout.Rect {
        let x: Double = i % 2 == 0 ? 0 : 0.55
        let y: Double = Double(i / 2) * (height + gap)
        return GymLayout.Rect(x: x, y: y, w: 0.45, h: height)
    }
}

private struct UnplacedZoneChips: View {
    let zones: [GymLayout.Zone]
    let action: (GymLayout.Zone) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(zones) { z in
                    Button { action(z) } label: { ZoneTag(zone: z, text: "+ \(z.name)") }.buttonStyle(.plain)
                }
            }
        }
    }
}
