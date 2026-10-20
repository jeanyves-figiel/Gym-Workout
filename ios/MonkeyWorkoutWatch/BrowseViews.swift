import SwiftUI

/// Watch home (#219): the member's pick of Monkey coach (default), Crown deck or Charge & go,
/// changed here (gear) or on the iPhone (Settings → Style).
struct HomeView: View {
    @Environment(WatchStore.self) private var store
    let onStart: (WSession) -> Void

    var body: some View {
        Group {
            if !store.hasPlan {
                ScrollView {
                    NoPlanCard().watchMargins()
                }
            } else {
                switch store.homeStyle {
                case .coach: CoachHome(onStart: onStart)
                case .deck: DeckHome(onStart: onStart)
                case .rings: RingsHome(onStart: onStart)
                }
            }
        }
        .navigationDestination(for: WSession.self) { SessionDetailView(session: $0, onStart: onStart) }
    }
}

/// No plan synced yet (#541): gradient card in place of grey text. The Watch can't open the iPhone app itself,
/// so the card says where to go; the plan arrives here on its own once it's built.
private struct NoPlanCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 15, weight: .bold))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.25)))
            Text("No plan yet").font(W.display(18)).lineLimit(1).minimumScaleFactor(0.8)
            Text("Build your week on iPhone").font(.system(size: 12, weight: .semibold, design: .rounded)).opacity(0.9)
            HStack(spacing: 6) {
                Image(systemName: "iphone").font(.system(size: 13, weight: .bold))
                Text("Open MonkeyWorkout on iPhone").font(W.label(11)).lineLimit(2).minimumScaleFactor(0.8)
            }
            .foregroundStyle(W.ink)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.lime))
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(W.gradient(0xB23DFF, 0xFF3DA8)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No plan yet. Build your week in MonkeyWorkout on your iPhone; it syncs here.")
    }
}

/// Hero card (#134, design A) rows: this week, workouts, streak, progress; icon tile left, big number right.
struct HomeStatRows: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let snap = store.snapshot
        let p = snap.progress
        VStack(spacing: 6) {
            NavigationLink { SessionListView(title: "This week", sessions: snap.sessions) } label: {
                HomeRow(symbol: "calendar", title: "This week", value: "\(p.thisWeek)/\(p.target)", tint: (0xFF7A3D, 0xFF3D5A))
            }
            .buttonStyle(.plain)
            if !snap.extras.isEmpty {
                NavigationLink { SessionListView(title: "Workouts", sessions: snap.extras) } label: {
                    HomeRow(symbol: "figure.strengthtraining.traditional", title: "Workouts", value: "\(snap.extras.count)",
                            tint: (0x1E9BFF, 0x3DFFB0))
                }
                .buttonStyle(.plain)
            }
            NavigationLink { ProgressScreen() } label: {
                HomeRow(symbol: "flame.fill", title: "Streak", value: "\(p.streakWeeks)w", tint: (0xFFC23D, 0xFF7A3D))
            }
            .buttonStyle(.plain)
            NavigationLink { ProgressScreen() } label: {
                // Real counts on the right (#541), not a bare "›".
                HomeRow(symbol: "chart.line.uptrend.xyaxis", title: "Progress",
                        value: "\(p.records.count)", tint: (0x3D5AFF, 0x7B3DFF), unit: "PR")
            }
            .buttonStyle(.plain)
            // Fuel water (#496): a tap adds a glass on the iPhone too.
            if let water = snap.water {
                Button { store.addGlass() } label: {
                    HomeRow(symbol: "drop.fill", title: "Water +1", value: "\(water.today())/\(water.target)", tint: (0x1E9BFF, 0x3DD9FF))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.increase, trigger: water.today())
                .accessibilityLabel("Add a glass of water")
                .accessibilityValue("\(water.today()) of \(water.target) glasses today")
            }
            // Other sports (#418): snowboard, MTB, hike, Hyrox… tracked in the background with GPS.
            NavigationLink { SportPickerView() } label: {
                // Hyrox plus every tracked sport.
                HomeRow(symbol: "figure.mixed.cardio", title: "Track a sport", value: "\(TrackedSport.allCases.count + 1)",
                        tint: (0x00A3C4, 0x7DF9FF), unit: "SPORTS")
            }
            .buttonStyle(.plain)
            // Home style (#389): moved here from the gear next to the clock.
            NavigationLink { HomeStyleSettings() } label: {
                HomeRow(symbol: "paintpalette.fill", title: "Home style", value: "\(WatchHomeStyle.allCases.count)",
                        tint: (0x5A5F73, 0x2C2F3A), unit: "STYLES")
            }
            .buttonStyle(.plain)
        }
    }
}

/// Watch → gear: pick the home style (#219).
struct HomeStyleSettings: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ScreenTitle(text: "Home style")
                ForEach(WatchHomeStyle.allCases) { style in
                    let on = store.homeStyle == style
                    Button { store.setHomeStyle(style) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: style.symbol).font(.system(size: 13, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.25)))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(style.title).font(W.label(13)).lineLimit(1).minimumScaleFactor(0.8)
                                if style == .default { Text("DEFAULT").font(W.label(8)).tracking(1).opacity(0.85) }
                            }
                            Spacer(minLength: 2)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 17, weight: .bold))
                                .foregroundStyle(on ? W.lime : .white.opacity(0.6))
                        }
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(style.tint.0, style.tint.1)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(W.lime, lineWidth: on ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                }
                Text("Also sets your iPhone look. Change it there in Settings → Style.").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 2)
            }
            .watchMargins()
        }
        .sensoryFeedback(.selection, trigger: store.homeStyle)
    }
}

/// Explore-style row: icon tile left, label, big number right, on a vivid gradient.
struct HomeRow: View {
    let symbol: String
    let title: String
    let value: String
    let tint: (UInt32, UInt32)
    /// Small caps under the value (#541): "PR", "SPORTS".
    var unit: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.25)))
            Text(title).font(W.label(12)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: -2) {
                Text(value).font(W.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(W.label(7)).tracking(0.5).opacity(0.85) }
            }
        }
        .foregroundStyle(.white)
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(tint.0, tint.1)))
    }
}
