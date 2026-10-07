import SwiftUI
import WorkoutEngine

struct WeekView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        Group {
            if let plan = model.plan, let profile = model.profile {
                List {
                    Section {
                        header(plan, profile)
                    }
                    if let e = model.syncError {
                        Section { Label(e, systemImage: "icloud.slash").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section("Sessions") {
                        ForEach(plan.sessions) { s in
                            NavigationLink(value: s.id) { SessionCard(session: s, done: model.state.done[s.id] ?? false) }
                        }
                    }
                }
                .navigationDestination(for: String.self) { id in SessionView(sessionId: id) }
            } else {
                ContentUnavailableView("No plan yet", systemImage: "calendar.badge.plus")
            }
        }
        .navigationTitle("This week")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New variation", systemImage: "shuffle") { model.newVariation() }
                    Button("Edit training profile", systemImage: "slider.horizontal.3") { editing = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ProfileFormView(initial: model.profile) { p in
                    model.applyProfile(p)
                    editing = false
                }
                .navigationTitle("Training profile")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } } }
            }
        }
        .refreshable { await model.sync() }
    }

    @ViewBuilder
    private func header(_ plan: WeekPlan, _ profile: Profile) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button { model.setWeek(plan.week - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(plan.week <= 1)
                Spacer()
                VStack {
                    Text("Week \(plan.week) / \(Generator.mesocycleWeeks)").font(.headline)
                    Text(Generator.weekLabel(plan.week))
                        .font(.caption)
                        .foregroundStyle(plan.deload ? .orange : .secondary)
                }
                Spacer()
                Button { model.setWeek(plan.week + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(plan.week >= Generator.mesocycleWeeks)
            }
            .buttonStyle(.borderless)
            Text("\(profile.goal.config.label) · \(profile.sessionsPerWeek)×/week · \(plan.sessionMinutes) min"
                + (profile.climbingDaysPerWeek > 0 ? " · \(profile.climbingDaysPerWeek) climbing days" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SessionCard: View {
    let session: Session
    let done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title).font(.subheadline.bold())
                Spacer()
                Text(done ? "✓ Done" : "\(session.estMin)′")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(done ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15)))
            }
            GeometryReader { geo in
                let total = max(1, session.blocks.reduce(0) { $0 + max(1, $1.targetMin) })
                HStack(spacing: 2) {
                    ForEach(session.blocks) { b in
                        b.kind.color.frame(width: max(2, (geo.size.width - CGFloat(session.blocks.count - 1) * 2) * CGFloat(max(1, b.targetMin)) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            Text(session.blocks.map { "\($0.kind.short) \($0.targetMin)′" }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(done ? 0.6 : 1)
    }
}
