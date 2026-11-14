import SwiftUI
import WorkoutEngine

// Invisible Monkey (#1087, Direction A from `auto-tracking/direction-a.png`): "Today · auto" on Fuel lists what the
// Watch, the photos and the gym noticed. Sure finds are already logged (Undo on the row), the rest is one tap.

/// Fuel card: today's automatic finds, or an invite to turn them on.
struct AutoTrackCard: View {
    let plan: FuelPlan
    let day: Date
    @State private var settings = false
    private var store: AutoTrackStore { AutoTrackStore.shared }

    var body: some View {
        Group {
            if store.prefs.anyOn {
                card
            } else if !store.saved.inviteHidden {
                invite
            }
        }
        .sheet(isPresented: $settings) { AutoTrackSettingsView() }
    }

    private var invite: some View {
        FuelTile(emoji: "✨", label: "New · Invisible Monkey", title: "Track without typing",
                 detail: "Watch sips, meals and food photos log themselves. On this iPhone only.", gradient: AutoPalette.invite) {
            Button { withAnimation(.snappy) { store.hideInvite() } } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).frame(width: 32, height: 32)
            }
            .accessibilityLabel("Hide")
        }
        .contentShape(Rectangle())
        .onTapGesture { settings = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("fuel.auto.invite")
    }

    private var card: some View {
        let events = store.today
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today · auto").font(Theme.display(20))
                Spacer()
                Button { settings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .heavy)).frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.12)))
                }
                .accessibilityLabel("Auto tracking settings")
            }
            if events.isEmpty {
                Text(empty).font(.footnote.weight(.semibold)).opacity(0.8)
            }
            ForEach(events) { e in AutoTrackRow(event: e, plan: plan, day: day) }
            if !events.isEmpty {
                Text(AutoTrack.summary(events)).font(Theme.label(11)).padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AutoPalette.invite))
            }
        }
        .foregroundStyle(.white)
        .accessibilityIdentifier("fuel.auto")
    }

    private var empty: String {
        let p = store.prefs
        if p.watchOn { return "Nothing caught yet. Your Watch sends sips and meals every hour or so." }
        if p.photos { return "Nothing caught yet. Photograph a meal and it shows up here." }
        return "Nothing caught yet today."
    }
}

/// One find: gradient tile, icon left, big number right, one-tap answers under it.
struct AutoTrackRow: View {
    let event: AutoEvent
    let plan: FuelPlan
    let day: Date
    @Environment(AppModel.self) private var model
    @State private var justAte = false
    @State private var scan = false
    @State private var photo: UIImage?
    @State private var gate: ProGate?
    private var store: AutoTrackStore { AutoTrackStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FuelTile(emoji: emoji, label: label, title: title, detail: detail, gradient: AutoPalette.of(event)) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(number).font(.system(size: 24, weight: .black, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if event.state == .pending {
                        Text("\(event.percent)%").font(Theme.label(10)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.28)))
                    }
                }
            }
            actions
        }
        .sheet(isPresented: $justAte) { JustAteSheet(plan: plan, day: day) }
        .sheet(isPresented: $scan) {
            if let slot = AutoTrack.slot(plan.slots, at: event.start, calendar: model.planCalendar) {
                PlateScanSheet(plan: plan, day: day, slot: slot, logged: { store.keep(event.id) }, autoImage: photo)
                    .remotePaused(.foodScan)
            }
        }
        .proPaywall($gate)
    }

    @ViewBuilder private var actions: some View {
        switch (event.state, event.source) {
        case (.pending, .photo):
            HStack(spacing: 8) {
                answer("Scan it", "camera.viewfinder", lime: true) {
                    ProStore.shared.run(.foodScan, $gate) {
                        Task {
                            photo = await PhotoInbox.image(id: event.photoId ?? "")
                            scan = true
                        }
                    }
                }
                answer("Not food", "xmark") { bin() }
            }
        case (.pending, _):
            HStack(spacing: 8) {
                answer("What was it?", "fork.knife", lime: true) {
                    store.keep(event.id)
                    justAte = true
                }
                answer("Not a meal", "xmark") { bin() }
            }
        case (.logged, .sips), (.logged, .place):
            HStack {
                Spacer()
                Button {
                    Haptics.undo()
                    withAnimation(.snappy) { store.dismiss(event.id) }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").font(Theme.label(11))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .accessibilityLabel("Undo \(title)")
            }
        default:
            EmptyView()
        }
    }

    private func bin() {
        Haptics.undo()
        withAnimation(.snappy) { store.dismiss(event.id) }
    }

    private func answer(_ text: String, _ symbol: String, lime: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: symbol).font(Theme.label(12)).frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(lime ? Theme.ink : .white)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lime ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(.white.opacity(0.12))))
        }
        .buttonStyle(.plain)
    }

    private var time: String { event.start.formatted(date: .omitted, time: .shortened) }

    private var emoji: String {
        switch (event.kind, event.source) {
        case (.water, _): "💧"
        case (.gym, _): "🏋️"
        case (_, .photo): "📸"
        default: "🍽️"
        }
    }

    private var label: String {
        switch event.source {
        case .sips: "Watch · sips"
        case .bites: "Watch · bites"
        case .photo: "Your photo"
        case .place: "Arrived"
        }
    }

    private var title: String {
        switch (event.kind, event.source) {
        case (.water, _): "\(event.count ?? 0) sips caught"
        case (.gym, _): "Gym at \(time)"
        case (_, .photo): event.state == .kept ? "\(event.title ?? "Meal") logged" : "\(event.title ?? "Meal") at \(time)?"
        default: event.state == .kept ? "Meal at \(time)" : "Meal at \(time)?"
        }
    }

    private var detail: String? {
        switch (event.kind, event.source) {
        case (.water, _): "\(time) · logged as water"
        case (.gym, _): "Today's workout one tap away"
        case (_, .photo): event.state == .kept ? "Scanned" : "Scan the photo for grams and macros"
        default: "\(event.count ?? 0) bites · \(Int(event.end.timeIntervalSince(event.start) / 60)) min"
        }
    }

    private var number: String {
        switch event.kind {
        case .water:
            let ml = event.ml ?? 0
            return ml >= 1000 ? String(format: "%.1f L", Double(ml) / 1000) : "\(ml) ml"
        case .gym: return "✓"
        case .meal: return event.state == .kept ? "✓" : "?"
        }
    }
}

enum AutoPalette {
    static let invite = LinearGradient(colors: [Color(hex: 0xFF5EA8), Color(hex: 0x7A3CFF)], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func of(_ e: AutoEvent) -> LinearGradient {
        switch (e.kind, e.source) {
        case (.water, _): FuelPalette.water
        case (.gym, _): FuelPalette.violet
        case (_, .photo): FuelPalette.hot
        default: FuelPalette.carbs
        }
    }
}

// MARK: - Settings

/// Which senses are on, each with what it sees in one sentence. Bold tiles, no grey list.
struct AutoTrackSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = AutoTrackStore.shared.prefs
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Monkey notices what you drink, eat and train, so you don't type it. Sure finds log themselves with Undo; the rest is one tap.")
                        .font(.subheadline.weight(.semibold)).opacity(0.85)
                    toggle("💧", "Sips", "Your Watch feels a cup or bottle tilt to your mouth and logs water.", FuelPalette.water, $prefs.sips)
                    if prefs.sips { sipSize }
                    toggle("🍽️", "Meals", "Your Watch feels a run of bites and asks what you ate.", FuelPalette.carbs, $prefs.bites)
                    toggle("📸", "Food photos", "New photos of food on this iPhone become a one-tap meal.", FuelPalette.hot, $prefs.photos)
                    toggle("🏋️", "Gym arrival", "Arriving at your home gym puts today's workout one tap away.", FuelPalette.violet, $prefs.gym)
                    if let notice {
                        Text(notice).font(.footnote.weight(.bold)).foregroundStyle(Theme.lime)
                    }
                    privacy
                }
                .padding(16)
                .foregroundStyle(.white)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Auto tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .onChange(of: prefs) { old, new in Task { await apply(old: old, new: new) } }
        }
        .preferredColorScheme(.dark)
    }

    private func apply(old: AutoTrackPrefs, new: AutoTrackPrefs) async {
        var p = new
        notice = nil
        if new.photos, !old.photos, !(await PhotoInbox.ask()) {
            p.photos = false
            notice = "Photos is off for MonkeyWorkout. Allow it in iOS Settings › Privacy › Photos."
        }
        if new.gym, !old.gym {
            if model.homePlace?.latitude == nil {
                p.gym = false
                notice = "Pick your home gym on the map first (Your gym), then turn this on."
            } else {
                GymArrival.shared.askAlways()
            }
        }
        if p != prefs { prefs = p }
        AutoTrackStore.shared.setPrefs(p)
    }

    private var sipSize: some View {
        HStack {
            Text("One sip").font(Theme.label(12))
            Spacer()
            Stepper("\(prefs.mlPerSip) ml", value: $prefs.mlPerSip, in: AutoTrack.sipRange, step: 5)
                .font(Theme.display(16)).fixedSize()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.08)))
    }

    private func toggle(_ emoji: String, _ title: String, _ text: String, _ fill: LinearGradient, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 22)).frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(17))
                Text(text).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.9)
            }
            Spacer(minLength: 4)
            Toggle(title, isOn: on).labelsHidden().tint(Theme.lime)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill))
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Stays on your devices", systemImage: "lock.fill").font(Theme.label(12))
            Text("Wrist movement is read on your Watch; only the times of sips and bites reach your iPhone. Photos are checked on this iPhone and only sent to Coach's AI when you tap Scan it. Your location is used only for the arrival, never stored. Nothing here is synced or shared.")
                .font(.footnote.weight(.semibold)).opacity(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.08)))
    }
}
