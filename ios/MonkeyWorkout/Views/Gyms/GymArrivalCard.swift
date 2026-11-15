import SwiftUI
import WorkoutEngine

/// Your gym → **Know when I arrive** (#1098, design A from `auto-tracking/gym-move/gym-a.png`): Gym arrival lives with
/// the gym it watches, not in Fuel. A Core Location region (150 m) around the home gym's map position, else where the
/// member stands when turning it on (#1092). Arriving sends one notification a day opening today's session.
struct GymArrivalCard: View {
    @Environment(AppModel.self) private var model
    @State private var on = AutoTrackStore.shared.prefs.gym
    @State private var notice: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("📍").font(.system(size: 22)).frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Know when I arrive").font(Theme.display(17))
                    Text("Arriving here puts today's workout one tap away.")
                        .font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.9)
                }
                Spacer(minLength: 4)
                Toggle("Know when I arrive", isOn: Binding(get: { on }, set: { v in Task { await set(v) } }))
                    .labelsHidden().tint(Theme.lime).disabled(busy)
            }
            .padding(14)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.violet))
            if let notice {
                Text(notice).font(.footnote.weight(.bold)).foregroundStyle(Theme.lime)
            }
            Text("Your location is checked on this iPhone only for the arrival, never stored or shared.")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.bottom, 6)
    }

    /// Turning on asks for location; a refusal stays off and says why.
    private func set(_ v: Bool) async {
        var p = AutoTrackStore.shared.prefs
        notice = nil
        guard v else {
            on = false
            p.gym = false
            AutoTrackStore.shared.setPrefs(p)
            return
        }
        busy = true
        defer { busy = false }
        if let g = model.homePlace, let lat = g.latitude, let lng = g.longitude {
            (p.gymLatitude, p.gymLongitude) = (lat, lng)
            notice = "Watching \(g.name) · 150 m around its pin."
        } else if let here = await GymArrival.shared.here() {
            // No map position for the home gym (#1092): the gym is where the member is now.
            (p.gymLatitude, p.gymLongitude) = (here.latitude, here.longitude)
            notice = "Your gym is set to where you are now. Turn this on at the gym, or pick your gym on the map below."
        } else {
            on = false
            notice = "Location is off for MonkeyWorkout. Allow it in iOS Settings › Privacy › Location Services."
            return
        }
        GymArrival.shared.askAlways()
        p.gym = true
        on = true
        AutoTrackStore.shared.setPrefs(p)
    }
}
