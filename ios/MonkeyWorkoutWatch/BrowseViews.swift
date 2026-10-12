import SwiftUI

/// Watch home (#219): the member's pick of Monkey coach (default), Crown deck or Charge & go,
/// changed here (gear) or on the iPhone (Account → Apple Watch).
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
                Text("Also in the iPhone app: Account → Apple Watch.").font(.system(size: 10, weight: .semibold))
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

/// Plan days or other workouts as gradient rows.
struct SessionListView: View {
    let title: String
    let sessions: [WSession]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(sessions) { s in
                    NavigationLink(value: s) {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.dayLabel.uppercased()).font(W.label(9)).opacity(0.85)
                                Text(s.title).font(W.label(14)).lineLimit(1)
                            }
                            Spacer()
                            if s.done {
                                Image(systemName: "checkmark.circle.fill")
                            } else {
                                Text("\(s.estMin)′").font(W.label(12))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.gradient(s.tint)))
                        .opacity(s.done ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(title)
    }
}

/// Exercises of a session with suggested loads; tap one for its form cues.
struct SessionDetailView: View {
    let session: WSession
    let onStart: (WSession) -> Void
    @State private var cues: WItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title).font(W.display(17))
                Text("\(session.blocks.count) blocks · \(session.estMin) min").font(W.label(10)).foregroundStyle(.secondary)
                ForEach(session.blocks, id: \.title) { b in
                    ForEach(b.items) { it in
                        Button { cues = it } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(W.color(b.tint)).frame(width: 7, height: 7).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(it.name).font(W.label(12)).lineLimit(2)
                                    Text(it.sets > 1 ? "\(it.sets) × \(it.reps)" : it.reps).font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    if let kg = it.kg, it.loggable {
                                        Text("↑ \(WatchPlayer.kg(kg)) kg\(it.targetReps.map { " × \($0)" } ?? "")")
                                            .font(W.label(10)).foregroundStyle(W.lime)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(7)
                            .background(RoundedRectangle(cornerRadius: 10).fill(W.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
                LimeButton(title: "▶ START") { onStart(session) }.padding(.top, 4)
            }
        }
        .sheet(item: $cues) { it in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(it.name).font(W.display(16))
                    ForEach(it.cues, id: \.self) { Text("• \($0)").font(.footnote) }
                    if let i = it.intensity { Text(i).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

/// Streak, week ring, PRs and recent sessions.
struct ProgressScreen: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let p = store.snapshot.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(p.streakWeeks)").font(W.display(30))
                        Text("week streak · best \(p.bestStreakWeeks)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.15), lineWidth: 6)
                        Circle().trim(from: 0, to: min(1, Double(p.thisWeek) / Double(max(1, p.target))))
                            .stroke(W.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(p.thisWeek)/\(p.target)").font(W.label(12))
                    }
                    .frame(width: 48, height: 48)
                }
                if !p.records.isEmpty {
                    Eyebrow(text: "Best e1RM", color: W.lime)
                    ForEach(p.records, id: \.name) { r in
                        HStack {
                            Text(r.name).font(W.label(11)).lineLimit(1)
                            Spacer()
                            Text("\(WatchPlayer.kg(r.kg)) kg").font(W.label(11)).foregroundStyle(W.lime)
                        }
                    }
                }
                if !p.recent.isEmpty {
                    Eyebrow(text: "Recent", color: W.lime)
                    ForEach(p.recent, id: \.date) { r in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.title).font(W.label(11)).lineLimit(1)
                            Text("\(r.date.formatted(.dateTime.weekday().day().month())) · \(r.minutes)′ · \(r.sets) sets")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress")
    }
}
