import SwiftUI
import WorkoutEngine

// Climbing session log (#44): Train-tab card, recent climbs, log sheet.

extension ClimbKind {
    var colors: [Color] {
        switch self {
        case .boulder: [Color(red: 1.0, green: 0.37, blue: 0.23), Color(red: 1.0, green: 0.69, blue: 0.24)]
        case .lead: [Color(red: 0.24, green: 0.35, blue: 1.0), Color(red: 0.0, green: 0.78, blue: 1.0)]
        case .topRope: [Color(red: 0.49, green: 0.30, blue: 1.0), Color(red: 0.88, green: 0.25, blue: 0.98)]
        case .outdoor: [Color(red: 0.17, green: 0.71, blue: 0.45), Color(red: 0.78, green: 0.96, blue: 0.20)]
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

private extension ClimbEntry {
    var gradient: LinearGradient {
        (kind ?? .boulder).gradient
    }

    var durationText: String { Climbs.duration(minutes) }
}

extension Climbs {
    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}

/// Train tab: "Log climb" card, hard-climb note and recent climbs (logged here or from Apple Health).
struct ClimbSection: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var logging: ClimbLog?

    private var climbs: [ClimbEntry] { Climbs.merged(local: model.climbLogs, health: health.snapshot.recentClimbs) }

    var body: some View {
        let all = climbs
        VStack(alignment: .leading, spacing: 12) {
            Button {
                logging = ClimbLog(start: Date().addingTimeInterval(-90 * 60))
            } label: {
                ClimbHeroCard(thisWeek: Climbs.thisWeek(all))
            }
            .buttonStyle(.plain)
            if let hard = Climbs.recentHard(all) {
                HardClimbNote(climb: hard)
            }
            if !all.isEmpty {
                Text("Recent climbs").eyebrow().padding(.top, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(all.prefix(8)) { c in
                            ClimbTile(climb: c)
                                .contextMenu {
                                    if c.local {
                                        Button("Delete climb", systemImage: "trash", role: .destructive) { delete(c.id) }
                                    }
                                }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .sheet(item: $logging) { LogClimbView(initial: $0) }
    }

    private func delete(_ id: UUID) {
        model.deleteClimb(id)
        Task {
            await health.deleteClimb(id)
            await health.refresh()
        }
    }
}

/// Explore-style gradient card: icon tile left, big weekly count right.
private struct ClimbHeroCard: View {
    let thisWeek: Int

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.climbing")
                .font(.system(size: 30, weight: .bold))
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Log climb").font(Theme.display(24))
                Text("Boulder, lead, top rope or outdoor. Saved to Apple Health.")
                    .font(.footnote.weight(.medium)).opacity(0.85).multilineTextAlignment(.leading)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(thisWeek)").font(Theme.display(34)).monospacedDigit()
                Text("this wk").font(Theme.label(10)).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ClimbKind.boulder.gradient))
    }
}

private struct HardClimbNote: View {
    let climb: ClimbEntry

    var body: some View {
        let today = Calendar.current.isDateInToday(climb.start)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fingers.spread.fill").font(.title2).foregroundStyle(Theme.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hard climb \(today ? "today" : "yesterday")").font(.footnote.weight(.bold))
                Text("Fingers and lats need a day. Keep grip and heavy pulling light in your next gym session; push, legs and mobility are fine.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

private struct ClimbTile: View {
    let climb: ClimbEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: (climb.kind ?? .boulder).symbol).font(.system(size: 18, weight: .bold))
                Spacer()
                if let g = climb.topGrade, !g.isEmpty {
                    Text(g).font(Theme.display(20))
                }
            }
            Spacer(minLength: 0)
            Text(climb.kind?.label ?? "Climbing").font(Theme.display(17))
            Text("\(climb.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(climb.durationText)")
                .font(Theme.label(11)).opacity(0.9)
            Text(climb.effort.map { "Effort \($0) · \(climb.source)" } ?? climb.source)
                .font(Theme.label(10)).opacity(0.75).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 150, height: 130, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(climb.gradient))
    }
}

/// Sheet for logging a climb: type, start, duration, effort, top grade, notes.
struct LogClimbView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var log: ClimbLog

    init(initial: ClimbLog) { _log = State(initialValue: initial) }

    private var grade: Binding<String> {
        Binding(get: { log.topGrade ?? "" }, set: { log.topGrade = $0.isEmpty ? nil : String($0.prefix(12)) })
    }

    private var notes: Binding<String> {
        Binding(get: { log.notes ?? "" }, set: { log.notes = $0.isEmpty ? nil : String($0.prefix(500)) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Type").eyebrow()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(ClimbKind.allCases) { k in
                            KindTile(kind: k, selected: log.kind == k) { log.kind = k }
                        }
                    }

                    Text("When").eyebrow()
                    DatePicker("Started", selection: $log.start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .font(.body.weight(.semibold))
                        .card(padding: 14)

                    Text("Duration").eyebrow()
                    HStack {
                        StepButton(symbol: "minus") { log.minutes = max(15, log.minutes - 15) }
                        Spacer()
                        Text(Climbs.duration(log.minutes)).font(Theme.display(44)).monospacedDigit()
                        Spacer()
                        StepButton(symbol: "plus") { log.minutes = min(360, log.minutes + 15) }
                    }
                    .card(padding: 14)

                    HStack {
                        Text("Effort").eyebrow()
                        Spacer()
                        Text("\(log.effort) · \(ClimbLog.effortLabel(log.effort))").font(Theme.label(13)).foregroundStyle(Theme.heat(Double(log.effort - 1) / 9))
                    }
                    HStack(spacing: 5) {
                        ForEach(1...10, id: \.self) { e in
                            Button { log.effort = e } label: {
                                Text("\(e)")
                                    .font(Theme.label(15))
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .foregroundStyle(e == log.effort ? Theme.ink : .white)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(e <= log.effort ? Theme.heat(Double(e - 1) / 9).opacity(e == log.effort ? 1 : 0.35) : Theme.card))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Top grade (optional)").eyebrow()
                    TextField("e.g. 6B+, V5 or 7a", text: grade)
                        .font(Theme.display(22))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .card(padding: 14)

                    Text("Notes (optional)").eyebrow()
                    TextField("Projects, beta, how fingers felt", text: notes, axis: .vertical)
                        .lineLimit(2...5)
                        .card(padding: 14)

                    Button {
                        save()
                    } label: {
                        Label("Save climb", systemImage: "checkmark")
                    }
                    .buttonStyle(LimeButtonStyle())

                    Text(health.connected && health.writeWorkouts
                         ? "Also saved to Apple Health as a Climbing workout."
                         : "Saved in MonkeyWorkout. Connect Apple Health in Progress → Body & Health to also save it there.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Log climb")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        let entry = log
        model.saveClimb(entry)
        let weight = model.body.weightKg ?? health.snapshot.weightKg
        Task {
            if await health.saveClimb(entry, kcal: Climbs.kcal(entry, weightKg: weight)) {
                await health.refresh()
            }
        }
        dismiss()
    }
}

private struct KindTile: View {
    let kind: ClimbKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.2)))
                Text(kind.label).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(kind.gradient))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white, lineWidth: selected ? 3 : 0))
            .opacity(selected ? 1 : 0.45)
            .scaleEffect(selected ? 1 : 0.97)
            .animation(.spring(duration: 0.25), value: selected)
        }
        .buttonStyle(.plain)
    }
}

private struct StepButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .heavy))
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.cardStrong))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
