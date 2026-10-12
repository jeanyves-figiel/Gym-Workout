import SwiftUI
import WorkoutEngine

/// Account → Your gym (#160): the gym your plan is built for. While a trip covers today it shows the trip's
/// place and equipment and opens the calendar; otherwise the home gym, opening Training profile → Your gym.
struct YourGymCard: View {
    @Environment(AppModel.self) private var model
    /// Saved gym picked in the quick switch (#180), waiting for confirmation.
    @State private var switching: SavedGym?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            card
            if model.currentTrip == nil, !model.otherGyms.isEmpty { quickSwitch }
        }
        .confirmationDialog("Switch to \(switching?.ref.name ?? "")?", isPresented: Binding(
            get: { switching != nil }, set: { if !$0 { switching = nil } }), titleVisibility: .visible, presenting: switching) { g in
            Button("Switch gym") { model.switchGym(to: g) }
        } message: { g in
            Text("This week's plan is rebuilt for its \(g.equipment.count) items. \(model.gymName) stays in your gyms to switch back.")
        }
    }

    /// One tap to train at another saved gym (#180); trips and holidays stay in the calendar.
    private var quickSwitch: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.otherGyms) { g in
                    Button { switching = g } label: {
                        HStack(spacing: 6) {
                            Image(systemName: g.kind?.symbol ?? (g.isPlace ? "mappin.and.ellipse" : "house.fill"))
                                .font(.system(size: 13, weight: .bold))
                            Text(g.ref.name).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                            Text("\(g.equipment.count)").font(Theme.label(12)).opacity(0.8)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Capsule().fill((g.kind?.category ?? .strength).gradient))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch to \(g.ref.name), \(g.equipment.count) items")
                }
            }
        }
    }

    private var card: some View {
        let trip = model.currentTrip
        return NavigationLink {
            if trip != nil { CalendarView() } else { ProfileSectionView(section: .gym) }
        } label: {
            AccountCard(symbol: trip == nil ? "building.2.fill" : "airplane", title: trip?.title ?? model.gymName,
                        subtitle: subtitle(trip), gradient: WorkoutEngine.Category.strength.gradient) {
                AccountValue(value: "\(trip?.travelEquipment.count ?? model.profile?.equipment.count ?? 0)", unit: "items")
            }
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ trip: AwayPeriod?) -> String {
        if trip != nil { return [model.tripLine, "Home: \(model.gymName)"].compactMap { $0 }.joined(separator: " · ") }
        let shown = Community.shared.profile?.showGym == true ? "Shown to members" : "Your gym"
        return [shown, model.tripLine].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Your gym on your Community profile, with the Show my gym switch (#152, #160). The trip line is only for you:
/// members only ever see the home gym, and only while it's shown.
struct ShowGymCard: View {
    @Environment(AppModel.self) private var model
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        let p = Community.shared.profile
        let on = p?.showGym == true
        VStack(alignment: .leading, spacing: 6) {
            AccountCard(symbol: "building.2.fill", title: p?.gym ?? model.gymName,
                        subtitle: [on ? "Shown on your profile and in Find members" : "Hidden. Show it to find members at your gym",
                                   model.tripLine.map { "\($0) (only you see this)" }].compactMap { $0 }.joined(separator: " · "),
                        gradient: WorkoutEngine.Category.strength.gradient) {
                if saving {
                    ProgressView().tint(.white)
                } else {
                    Toggle("Show my gym", isOn: Binding(get: { on }, set: { set($0) }))
                        .labelsHidden()
                        .tint(Theme.lime)
                }
            }
            ErrorText(message: error)
        }
    }

    private func set(_ on: Bool) {
        saving = true
        error = nil
        Task {
            defer { saving = false }
            #if DEBUG
            if model.demo { return }
            #endif
            do { Community.shared.setProfile(try await model.api.setShowGym(on)) } catch { self.error = error.localizedDescription }
        }
    }
}
