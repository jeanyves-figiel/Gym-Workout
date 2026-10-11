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
    @State private var settings = false

    private var monkeyGrade: MonkeyGradeLink { .shared }

    private var climbs: [ClimbEntry] {
        Climbs.merged(local: model.climbLogs, health: health.snapshot.recentClimbs, monkeyGrade: monkeyGrade.climbs(for: model.user?.id))
    }

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
            if model.profile?.climbDayAddon == true {
                NavigationLink(value: WorkoutTemplate.climbAddon.sessionId) {
                    ClimbAddonCard(today: isClimbingDay)
                }
                .buttonStyle(.plain)
            }
            Button { settings = true } label: {
                Label("Around climbing days", systemImage: "slider.horizontal.3")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.lime)
            }
            .buttonStyle(.plain)
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
        .sheet(isPresented: $settings) { ClimbSettingsView() }
        .task { if monkeyGrade.isConnected(for: model.user?.id) { await monkeyGrade.refresh() } }
    }

    private var isClimbingDay: Bool {
        let today = WeekSchedule.fromCalendar(Calendar.current.component(.weekday, from: Date()))
        return model.profile?.climbingDays.contains(today) ?? false
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
            Text([climb.detail, climb.effort.map { "Effort \($0)" }, climb.source].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.label(10)).opacity(0.75).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 160, height: 140, alignment: .topLeading)
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
            .selectableGradient(kind.gradient, selected: selected, cornerRadius: 20)
            .scaleEffect(selected ? 1 : 0.97)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

// MARK: - Around climbing days (#47)

extension ClimbNeighbour {
    var label: String {
        switch self {
        case .light: "Keep it light"
        case .strong: "Strong push or legs"
        case .rest: "Rest"
        case .any: "No adjustment"
        }
    }

    func blurb(before: Bool) -> String {
        switch self {
        case .light: before ? "No heavy pulling, grip or jumps. Push and legs preferred." : "Light on pulling and grip while fingers recover."
        case .strong: before ? "Hard push or leg day welcome. Only pulling and grip kept light." : "Hard push or leg day welcome. Pulling kept light."
        case .rest: "Keep this day free of gym sessions when the week allows."
        case .any: "Plan the gym session as if you weren't climbing."
        }
    }

    var symbol: String {
        switch self {
        case .light: "leaf.fill"
        case .strong: "flame.fill"
        case .rest: "bed.double.fill"
        case .any: "circle.dashed"
        }
    }

    var colors: [Color] {
        switch self {
        case .light: [Color(red: 0.12, green: 0.85, blue: 0.54), Color(red: 0.71, green: 1.0, blue: 0.42)]
        case .strong: [Color(red: 1.0, green: 0.18, blue: 0.33), Color(red: 1.0, green: 0.54, blue: 0.0)]
        case .rest: [Color(red: 0.18, green: 0.42, blue: 1.0), Color(red: 0.54, green: 0.30, blue: 1.0)]
        case .any: [Color(white: 0.35), Color(white: 0.55)]
        }
    }
}

extension ClimbSameDay {
    var label: String {
        switch self {
        case .avoid: "Climb only"
        case .allow: "Gym allowed"
        }
    }

    var blurb: String {
        switch self {
        case .avoid: "Gym sessions go on climbing days only when the week has no room."
        case .allow: "A gym session can share the day, e.g. gym in the morning, climb in the evening."
        }
    }

    var symbol: String { self == .avoid ? "figure.climbing" : "dumbbell.fill" }

    var colors: [Color] {
        self == .avoid ? ClimbKind.boulder.colors : ClimbKind.lead.colors
    }
}

/// Optional short session on climbing days: antagonists, shoulders, finger extensors, core.
private struct ClimbAddonCard: View {
    let today: Bool

    var body: some View {
        let t = WorkoutTemplate.climbAddon
        HStack(spacing: 16) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30, weight: .bold))
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(today ? "Climbing today · add-on" : "Climbing-day add-on").font(Theme.label(11)).tracking(1.2).opacity(0.85)
                Text("Antagonist & shoulders").font(Theme.display(22))
                Text("Push, shoulder health, finger extensors, core. No pulling or grip.")
                    .font(.footnote.weight(.medium)).opacity(0.85).multilineTextAlignment(.leading)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(t.session.estMin)").font(Theme.display(30)).monospacedDigit()
                Text("min").font(Theme.label(10)).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ClimbKind.topRope.gradient))
    }
}

/// How gym days around climbing are planned. Saving rebuilds this week's plan.
struct ClimbSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var before: ClimbNeighbour = .light
    @State private var after: ClimbNeighbour = .light
    @State private var sameDay: ClimbSameDay = .avoid
    @State private var addon = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Day before climbing").eyebrow()
                    ForEach(ClimbNeighbour.allCases) { o in
                        OptionCard(symbol: o.symbol, title: o.label, blurb: o.blurb(before: true), colors: o.colors,
                                   selected: before == o) { before = o }
                    }
                    Text("Day after climbing").eyebrow().padding(.top, 8)
                    ForEach(ClimbNeighbour.allCases) { o in
                        OptionCard(symbol: o.symbol, title: o.label, blurb: o.blurb(before: false), colors: o.colors,
                                   selected: after == o) { after = o }
                    }
                    Text("On climbing days").eyebrow().padding(.top, 8)
                    ForEach(ClimbSameDay.allCases) { o in
                        OptionCard(symbol: o.symbol, title: o.label, blurb: o.blurb, colors: o.colors,
                                   selected: sameDay == o) { sameDay = o }
                    }
                    Toggle(isOn: $addon) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Climbing-day add-on").font(Theme.display(18))
                            Text("Offer a short optional session (≈ \(WorkoutTemplate.climbAddon.session.estMin) min) on Train: push, shoulders, finger extensors, core.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.lime)
                    .card(padding: 16)
                    .padding(.top, 8)

                    Button { save() } label: { Label("Save", systemImage: "checkmark") }
                        .buttonStyle(LimeButtonStyle())
                        .padding(.top, 8)
                    Text("Saving rebuilds this week's plan around your climbing days.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Around climbing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard let p = model.profile else { return }
            before = p.climbPrefs.before
            after = p.climbPrefs.after
            sameDay = p.climbPrefs.sameDay
            addon = p.climbDayAddon ?? false
        }
    }

    private func save() {
        guard var p = model.profile else { return dismiss() }
        p.climbBefore = before == .light ? nil : before
        p.climbAfter = after == .light ? nil : after
        p.climbSameDay = sameDay == .avoid ? nil : sameDay
        p.climbDayAddon = addon ? true : nil
        if p != model.profile {
            model.applyProfile(p, seed: model.plan?.seed, week: model.plan?.week ?? 1)
        }
        dismiss()
    }
}

/// Explore-style selectable option: icon tile, title + blurb, gradient when picked.
private struct OptionCard: View {
    let symbol: String
    let title: String
    let blurb: String
    let colors: [Color]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.display(19))
                    Text(blurb).font(.footnote.weight(.medium)).opacity(0.85).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2.weight(.bold))
                    .opacity(selected ? 1 : 0.8)
            }
            .foregroundStyle(.white)
            .padding(14)
            .selectableGradient(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                selected: selected, cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
