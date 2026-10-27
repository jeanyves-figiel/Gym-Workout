import SwiftUI
import WorkoutEngine

// Current gym in Explore (#662, design A, tile 1 from `explore-current-gym/pinned.png`): My gym is pinned on the left
// of the machine chips as a sunset tile (gym name, machine count). Tap = My gym filter, ▾ = the gym sheet: Gym map,
// Machines here, Add missing.

extension LinearGradient {
    /// Sunset: the pinned gym tile and its sheet.
    static let gymSunset = LinearGradient(colors: [Color(red: 1, green: 0.37, blue: 0.43), Color(red: 1, green: 0.76, blue: 0.44)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension AppModel {
    /// Gym areas the member's gym counts against: climbing only when the gym has climbing kit.
    var gymAreas: [GymArea] {
        let eq = Set(profile?.equipment ?? [])
        return GymArea.allCases.filter { $0 != .climbing || $0.items.contains { eq.contains($0) } }
    }

    /// Machines (not mats or rollers) in the member's gym.
    var gymMachineCount: Int { Self.machineCount(profile?.equipment ?? []) }

    /// Machines among `equipment` (#823, design C): what Explore counts, so gym cards say "69 items · 67 machines".
    static func machineCount(_ equipment: [Equipment]) -> Int {
        let all = Set(GymArea.allCases.flatMap(\.items))
        return Set(equipment).filter { all.contains($0) }.count
    }

    /// Browsable machines the member's gym doesn't have yet.
    var gymMissingCount: Int {
        let eq = Set(profile?.equipment ?? [])
        return gymAreas.flatMap { $0.browsable() }.filter { !eq.contains($0.item) }.count
    }
}

/// Pinned My gym tile: tap filters to the gym, ▾ opens the gym sheet.
struct GymChipTile: View {
    @Environment(AppModel.self) private var model
    let on: Bool
    let toggle: () -> Void
    @State private var sheet = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: on ? "checkmark" : "mappin.and.ellipse").font(.system(size: 13, weight: .heavy))
                    VStack(alignment: .leading, spacing: 0) {
                        // Shrinks to fit: "Fitnesspark Pu…" lost the gym's number (#823).
                        Text(model.gymName).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(on ? "Only mine" : "\(model.gymMachineCount) machines").font(Theme.label(9)).opacity(0.7).lineLimit(1)
                    }
                    .frame(maxWidth: 116, alignment: .leading)
                }
                .padding(.leading, 10).padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("My gym, \(model.gymName)")
            .accessibilityAddTraits(on ? .isSelected : [])
            Button { sheet = true } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .heavy))
                    .frame(width: 26, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Gym map and machines")
        }
        .foregroundStyle(Theme.ink)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(LinearGradient.gymSunset))
        .overlay {
            if on { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white, lineWidth: 2).padding(-3) }
        }
        .sheet(isPresented: $sheet) { ExploreGymSheet() }
    }
}

/// The current gym: Gym map, Machines here, Add missing.
struct ExploreGymSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    // Plain @State binding (#673): a Binding(get:set:) over a value this body never reads left the plan stale, so the
    // auto-placed zones only showed on the second open.
    @State private var mapDraft: GymLayout = .starter
    @State private var mapOpen = false
    @State private var kitDraft: [Equipment] = []
    @State private var zonesDraft: GymLayout?
    @State private var kitOpen = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Where things are and what your gym has. Workouts are planned from it.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    HStack(spacing: 10) {
                        tile("map.fill", value: zoneCount, label: "Gym map", gradient: WorkoutEngine.Category.strength.gradient) {
                            mapDraft = model.profile?.gymLayout ?? .starter
                            mapOpen = true
                        }
                        tile("checkmark", value: "\(model.gymMachineCount)", label: "Here", gradient: WorkoutEngine.Category.stretch.gradient, ink: Theme.ink,
                             action: openKit)
                        tile("plus", value: "\(model.gymMissingCount)", label: "Add missing", gradient: .gymSunset, ink: Theme.ink,
                             action: openKit)
                    }
                }
                .padding(16)
            }
            .glassSheetBackground()
            .navigationTitle(model.gymName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $mapOpen, onDismiss: {
            model.setGymLayout(mapDraft)
        }) {
            FloorPlanSheet(layout: $mapDraft, equipment: model.profile?.equipment ?? [])
        }
        .sheet(isPresented: $kitOpen, onDismiss: { model.setGymEquipment(kitDraft, layout: zonesDraft) }) {
            EquipmentSheet(equipment: $kitDraft, layout: $zonesDraft)
        }
    }

    private var zoneCount: String {
        guard let l = model.profile?.gymLayout else { return "Draw" }
        return "\(l.zones.count)"
    }

    private func openKit() {
        kitDraft = model.profile?.equipment ?? []
        zonesDraft = model.profile?.gymLayout
        kitOpen = true
    }

    private func tile(_ symbol: String, value: String, label: String, gradient: LinearGradient, ink: Color = .white,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GradientStat(symbol: symbol, value: value, label: label, gradient: gradient, ink: ink)
        }
        .buttonStyle(.plain)
    }
}
