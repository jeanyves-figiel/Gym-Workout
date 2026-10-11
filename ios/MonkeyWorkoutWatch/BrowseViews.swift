import SwiftUI

/// Today (#134, design A "Hero card"): the next workout fills the first screen with a big START;
/// crown down for gradient rows (this week, workouts, streak, progress), icon tile left, big number right.
struct HomeView: View {
    @Environment(WatchStore.self) private var store
    let onStart: (WSession) -> Void

    var body: some View {
        let snap = store.snapshot
        let p = snap.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if !store.hasPlan {
                    Eyebrow(text: "MonkeyWorkout", color: W.lime)
                    Text("Open MonkeyWorkout on your iPhone to sync your plan.").font(.footnote)
                } else {
                    if let next = store.next {
                        NavigationLink(value: next) { NextCard(session: next, week: snap.week) }
                            .buttonStyle(.plain)
                        LimeButton(title: "▶ START") { onStart(next) }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(text: "This week", color: .white.opacity(0.85))
                            Text("Week complete 🏆").font(W.display(20))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(W.gradient(0x3DFFB0, 0x1E9BFF)))
                    }
                    HStack {
                        Text("\(p.thisWeek)/\(p.target) done").foregroundStyle(W.lime)
                        Spacer()
                        if let r = snap.readiness {
                            Text("Ready \(r.components(separatedBy: " ").first ?? r)").foregroundStyle(W.color(0x3DFFB0))
                        }
                    }
                    .font(W.label(11))
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)
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
        .navigationTitle("Today")
        .navigationDestination(for: WSession.self) { SessionDetailView(session: $0, onStart: onStart) }
    }
}

/// Big gradient card for the next workout: day, title, length, plan week.
private struct NextCard: View {
    let session: WSession
    let week: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Next up · \(session.dayLabel)", color: .white.opacity(0.85))
            Spacer(minLength: 0)
            Text(session.title).font(W.display(21)).lineLimit(2).minimumScaleFactor(0.6)
            HStack(alignment: .lastTextBaseline) {
                Text("\(session.estMin) min · \(session.items.count) ex").font(W.label(10)).opacity(0.9)
                Spacer()
                Text("W\(week)").font(W.display(22))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(W.gradient(session.tint, session.blocks.first?.tint2)))
    }
}

/// Explore-style row: icon tile left, label, big number right, on a vivid gradient.
private struct HomeRow: View {
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
