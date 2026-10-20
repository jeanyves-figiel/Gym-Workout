import SwiftUI
import UIKit
import UserNotifications
import WorkoutEngine

// Water through the day (#520, designs A + B + C from `nutrition-pointers/water-reminders.png`): the water card in
// Fuel shows where the pace says you should be; its sheet shows the pace and sets the reminders.

/// The water card on the Day and Portions layouts.
struct FuelWaterCard: View {
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    var title = "💧 WATER · TAP A GLASS"
    @State private var store = FuelStore.shared
    @State private var showPace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(Theme.label(10)).tracking(1.2).opacity(0.85)
                Spacer()
                Text("\(log.glasses)/\(plan.glasses)").font(Theme.display(17)).monospacedDigit()
            }
            WaterGlasses(filled: log.glasses, target: plan.glasses) { n in store.update(day, plan: plan) { $0.glasses = n } }
            Button { showPace = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bell.fill").font(.system(size: 11, weight: .bold))
                    Text(paceLine).font(Theme.label(12))
                    Spacer(minLength: 4)
                    Text("Pace").font(Theme.label(11)).opacity(0.85)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)).opacity(0.85)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Water pace and reminders")
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.water))
        .sheet(isPresented: $showPace) { WaterSheet(plan: plan, glasses: log.glasses, day: day) }
    }

    private var paceLine: String {
        guard Calendar.current.isDateInToday(day) else { return "Water reminders" }
        if log.glasses >= plan.glasses { return "Target hit 💧" }
        let aim = WaterPace.expected(by: WaterSheet.minuteNow(), plan: plan, prefs: store.prefs)
        return log.glasses >= aim ? "On pace: \(aim) by now" : "Behind: aim for \(aim) by now"
    }
}

/// Today's pace and the reminder settings (auto saved).
struct WaterSheet: View {
    let plan: FuelPlan
    let glasses: Int
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var store = FuelStore.shared
    @State private var notify = NotificationManager.shared

    static func minuteNow() -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Water").font(Theme.display(28))
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .bold)) }
                        .accessibilityLabel("Close")
                }
                pace
                remind
                quiet
                if notify.authorization == .denied || notify.authorization == .notDetermined { permission }
                Text("🐵 Training days raise the target and the pace on their own.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FuelPalette.coach))
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .task { await notify.refreshAuthorization() }
    }

    private var buckets: [WaterBucket] { WaterPace.buckets(plan, prefs: store.prefs) }

    private var pace: some View {
        let b = buckets
        let top = max(0.5, b.map(\.glasses).max() ?? 1)
        let now = Calendar.current.isDateInToday(day) ? Self.minuteNow() : -1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY'S PACE").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                Spacer()
                Text("\(glasses)/\(plan.glasses) · \(store.prefs.litres(plan.waterMl))").font(Theme.label(13)).monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(b) { x in
                    let current = now >= x.start && now < x.start + 120
                    VStack(spacing: 4) {
                        Text(x.training ? "🏋️" : " ").font(.system(size: 11))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(x.training ? Theme.lime : current ? .white : .white.opacity(0.45))
                            .frame(height: max(6, 90 * x.glasses / top))
                        Text(WaterPace.clock(x.start).prefix(2)).font(Theme.label(10)).opacity(current ? 1 : 0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            Text(summary).font(.footnote.weight(.semibold)).opacity(0.9)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.water))
    }

    private var summary: String {
        let cal = Calendar.current
        if let a = plan.activities.min(by: { $0.start < $1.start }) {
            let at = cal.component(.hour, from: a.start) * 60 + cal.component(.minute, from: a.start)
            return "More in the 2 h before \(a.title) at \(WaterPace.clock(at)), sips during, a top up in the hour after."
        }
        return "Spread from \(WaterPace.clock(store.prefs.wake)) to \(WaterPace.clock(store.prefs.sleep)), less in the last 2 h before bed."
    }

    private var remind: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REMIND ME").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(WaterRemind.allCases) { r in
                    let on = store.waterPrefs.remind == r
                    Button {
                        var w = store.waterPrefs
                        w.remind = r
                        store.setWaterPrefs(w)
                    } label: {
                        Text(r.label).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(on ? .black : .white)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.lime : Theme.cardStrong))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("Banners have +1 and +2 buttons, on your iPhone and your Apple Watch.")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
    }

    private var quiet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUIET").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
            HStack {
                Image(systemName: "moon.fill")
                Text("Sleep \(WaterPace.clock(store.prefs.sleep))–\(WaterPace.clock(store.prefs.wake))")
                Spacer()
                Text("Fuel settings").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .font(.subheadline.weight(.bold))
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            Toggle(isOn: Binding(get: { store.waterPrefs.quietWorkouts }, set: { on in
                var w = store.waterPrefs
                w.quietWorkouts = on
                store.setWaterPrefs(w)
            })) {
                Label("During workouts", systemImage: "figure.strengthtraining.traditional").font(.subheadline.weight(.bold))
            }
            .tint(Theme.lime)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            Text("Your notification quiet hours apply too.").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
    }

    private var permission: some View {
        Button {
            if notify.authorization == .denied {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } else {
                Task {
                    _ = await notify.requestAuthorization()
                    await notify.scheduleWater()
                }
            }
        } label: {
            HStack {
                Image(systemName: "bell.badge.fill")
                Text(notify.authorization == .denied ? "Notifications are off. Open Settings" : "Allow notifications for reminders")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
        }
        .buttonStyle(.plain)
    }
}
