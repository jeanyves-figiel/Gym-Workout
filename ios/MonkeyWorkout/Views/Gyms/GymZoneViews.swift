import APIClient
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
    /// Gym scan (#406) found items the gym list doesn't have yet: the caller ticks them.
    var onScanned: (([Equipment]) -> Void)? = nil
    @Environment(AppModel.self) private var model
    @State private var editing: GymLayout.Zone?
    @State private var plan = false
    @State private var scanning = false
    @State private var gate: ProGate?

    var body: some View {
        VStack(spacing: 10) {
            if let shared = model.sharedGymMap, !(layout?.hasPlan ?? false) { sharedOffer(shared) }
            content
        }
        .task { await model.loadSharedGymMap() }
        .proPaywall($gate)
        .sheet(isPresented: $scanning) {
            GymScanSheet(layout: Binding(get: { layout ?? .starter }, set: { layout = $0 })) { found in
                onScanned?(found.filter { !equipment.contains($0) })
            }
        }
    }

    /// Shared map (#406): members at this gym already mapped it; one tap uses their plan.
    private func sharedOffer(_ shared: SharedGymMap<GymLayout>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Map ready for your gym").font(.system(size: 16, weight: .heavy, design: .rounded))
                Text("Mapped by \(shared.members) \(shared.members == 1 ? "member" : "members")"
                     + (shared.agreement.map { " · \($0)% agree" } ?? "") + " · \(shared.layout.zones.count) zones")
                    .font(.caption.weight(.semibold)).opacity(0.9)
            }
            Spacer(minLength: 0)
            Button {
                painting = nil
                layout = shared.layout
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Text("USE IT").font(Theme.label(12)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("zones.useShared")
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x00C9A7), Color(hex: 0x2EC5FF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    @ViewBuilder private var content: some View {
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
                        Label(current.hasPlan ? "Gym map" : "Draw your gym map", systemImage: "square.grid.3x3.square")
                            .font(Theme.label(12))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    Button { ProStore.shared.run(.gymScan, $gate) { scanning = true } } label: {
                        Label("Scan", systemImage: "camera.viewfinder")
                            .font(Theme.label(12))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("zones.scan")
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

/// Floor plan (B; real plan look #406): floor tiles, outer walls and a draggable entrance. Drag each zone to where it
/// is and resize it from the corner; blocks that touch count as next to each other, so a superset can use both. Tap a
/// zone to see what sits there and drag a piece onto another zone to move it. 3D tilts the plan for a look.
struct FloorPlanSheet: View {
    @Binding var layout: GymLayout
    let equipment: [Equipment]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var tilted = false
    @State private var dropTarget: String?
    @State private var roomScan = false

    private static let grid = 0.05

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Text(tilted ? "Your gym in 3D. Switch back to 2D to edit."
                             : "Drag each zone to where it is, pull the corner to resize, drag the door to your entrance.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 8)
                        Picker("View", selection: $tilted) {
                            Text("2D").tag(false)
                            Text("3D").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 96)
                        .accessibilityIdentifier("plan.view")
                    }
                    GeometryReader { geo in
                        let size = geo.size
                        ZStack(alignment: .topLeading) {
                            GymFloor(door: layout.door)
                            ForEach(layout.zones) { z in
                                if let r = z.rect { block(z, r, size) }
                            }
                            doorHandle(size)
                        }
                        .coordinateSpace(name: "plan")
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .aspectRatio(0.8, contentMode: .fit)
                    .rotation3DEffect(.degrees(tilted ? 50 : 0), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
                    .scaleEffect(tilted ? 0.92 : 1)
                    .shadow(color: .black.opacity(tilted ? 0.6 : 0), radius: 18, y: 18)
                    .allowsHitTesting(!tilted)
                    .animation(.spring(duration: 0.6), value: tilted)

                    if RoomScan.supported || layout.sizeM != nil {
                        HStack {
                            if let m = layout.sizeM {
                                Label("\(Int(m.x.rounded())) × \(Int(m.y.rounded())) m", systemImage: "ruler.fill").font(Theme.label(12))
                            }
                            Spacer()
                            if RoomScan.supported {
                                Button { roomScan = true } label: {
                                    Label(layout.sizeM == nil ? "Scan the room" : "Scan again", systemImage: "camera.metering.matrix")
                                        .font(Theme.label(12))
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(Capsule().fill(Theme.lime))
                                        .foregroundStyle(Theme.ink)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    let unplaced = layout.zones.filter { $0.rect == nil }
                    if !unplaced.isEmpty {
                        Text("Tap to put on the plan").eyebrow()
                        UnplacedZoneChips(zones: unplaced) { place($0) }
                    }
                    if let id = selected, let z = layout.zone(id: id) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(z.name).font(Theme.display(20))
                                Spacer()
                                Button("Take off the plan") {
                                    setRect(id, nil)
                                    selected = nil
                                }
                                .font(.caption.bold())
                            }
                            let items = z.items.filter { equipment.contains($0) }
                            if items.isEmpty {
                                Text("Nothing here yet").font(.caption.weight(.semibold))
                            } else {
                                Text("Drag a piece onto another zone, or touch and hold it").font(.caption.weight(.semibold)).opacity(0.85)
                                FlowLayout(spacing: 6) {
                                    ForEach(items) { e in itemChip(e, in: z) }
                                }
                            }
                            let next = layout.zones.filter { $0.id != z.id && $0.rect != nil && layout.near(z, $0) }
                            Text(next.isEmpty ? "No zone next to it" : "Next to: " + next.map(\.name).joined(separator: ", "))
                                .font(.caption.weight(.bold))
                        }
                        .gradientCard(z.gradient, padding: 14)
                    }
                    if layout.hasPlan {
                        Button("Clear the plan", role: .destructive) {
                            for z in layout.zones { setRect(z.id, nil) }
                            layout.door = nil
                            selected = nil
                        }
                        .font(.footnote.bold())
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Gym map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if !layout.hasPlan { autoPlace() } }
            #if canImport(RoomPlan) && !targetEnvironment(simulator)
            .fullScreenCover(isPresented: $roomScan) {
                RoomScanView { result in
                    if let result {
                        layout.sizeM = result.sizeM
                        if let d = result.door { layout.door = d }
                    }
                    roomScan = false
                }
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }

    /// One piece of equipment in the selected zone: drag it onto another block, or move it from the menu.
    private func itemChip(_ e: Equipment, in z: GymLayout.Zone) -> some View {
        Label(e.label, systemImage: e.symbol)
            .font(Theme.label(12))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.3)))
            .draggable(e.rawValue)
            .contextMenu {
                ForEach(layout.zones.filter { $0.id != z.id }) { other in
                    Button("Move to \(other.name)") { layout.move(e, to: other.id) }
                }
            }
            .accessibilityHint("Touch and hold to move it to another zone.")
    }

    /// Entrance marker: drag it along the walls.
    private func doorHandle(_ size: CGSize) -> some View {
        let d = layout.entrance
        return Text("DOOR")
            .font(Theme.label(9))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Theme.lime))
            .position(x: min(max(CGFloat(d.x) * size.width, 24), size.width - 24),
                      y: min(max(CGFloat(d.y) * size.height, 12), size.height - 12))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("plan")).onChanged { g in
                let p = GymLayout.Point(x: Double(g.location.x / size.width), y: Double(g.location.y / size.height))
                layout.door = p.onWall
            })
            .accessibilityLabel("Entrance")
    }

    private func block(_ z: GymLayout.Zone, _ r: GymLayout.Rect, _ size: CGSize) -> some View {
        let on = selected == z.id
        let items = z.items.filter { equipment.contains($0) }
        let w = CGFloat(r.w) * size.width - 6, h = CGFloat(r.h) * size.height - 6
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(z.gradient)
            .opacity(0.9)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(z.name).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(items.count)").font(Theme.label(10)).opacity(0.8)
                    }
                    // Equipment icons: the plan shows what sits where.
                    let fit = max(0, Int((w - 12) / 18) * max(0, Int((h - 34) / 18)))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 4), count: max(1, Int((w - 12) / 18))),
                              alignment: .leading, spacing: 4) {
                        ForEach(Array(Set(items.map(\.symbol))).sorted().prefix(fit), id: \.self) { s in
                            Image(systemName: s).font(.system(size: 11, weight: .bold)).opacity(0.85)
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(6)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
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
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(dropTarget == z.id ? Theme.lime : .white, lineWidth: on || dropTarget == z.id ? 3 : 0))
            .frame(width: w, height: h)
            .offset(x: CGFloat(r.x) * size.width + 3, y: CGFloat(r.y) * size.height + 3)
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
            .dropDestination(for: String.self) { ids, _ in
                let moved = ids.compactMap(Equipment.init(rawValue:))
                for e in moved { layout.move(e, to: z.id) }
                return !moved.isEmpty
            } isTargeted: { dropTarget = $0 ? z.id : (dropTarget == z.id ? nil : dropTarget) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(z.name) on the floor plan, \(items.count) items")
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
