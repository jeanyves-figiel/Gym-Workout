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
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "MonkeyWorkout", color: W.lime)
                        Text("Open MonkeyWorkout on your iPhone to sync your plan.").font(.footnote)
                    }
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { HomeStyleSettings() } label: { Image(systemName: "gearshape.fill") }
            }
        }
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
                HomeRow(symbol: "chart.line.uptrend.xyaxis", title: "Progress",
                        value: p.records.isEmpty ? "›" : "\(p.records.count) PR", tint: (0x3D5AFF, 0x7B3DFF))
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
        }
        .sensoryFeedback(.selection, trigger: store.homeStyle)
        .navigationTitle("Home style")
    }
}

/// Explore-style row: icon tile left, label, big number right, on a vivid gradient.
struct HomeRow: View {
    let symbol: String
    let title: String
    let value: String
    let tint: (UInt32, UInt32)

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.25)))
            Text(title).font(W.label(11)).lineLimit(1)
            Spacer(minLength: 2)
            Text(value).font(W.display(19)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(tint.0, tint.1)))
    }
}
