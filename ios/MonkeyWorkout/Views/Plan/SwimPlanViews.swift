import LiftSensor
import SwiftUI
import WorkoutEngine

// Swimming (#624, design A + B + C from `apple-tech-radar/x7.png`; #615 B buddy alert): swim plans made of swim
// sets (B), sets with send-offs the Watch buzzes (A), and a swim block added to a gym day (C).

extension LinearGradient {
    static let swim = LinearGradient(colors: [Color(hex: 0x00A3C4), Color(hex: 0x3D59FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let swimPlan = LinearGradient(colors: [Color(hex: 0x00B86B), Color(hex: 0x00A3C4)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let swimDay = LinearGradient(colors: [Color(hex: 0x3D59FF), Color(hex: 0x7D4DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Workout library entry.
struct SwimCard: View {
    @State private var store = SwimStore.shared

    var body: some View {
        NavigationLink { SwimHubView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.pool.swim").font(.system(size: 22, weight: .heavy))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Swim").font(Theme.display(20))
                    Text(store.planLine() ?? "Plans, sets with send-offs, pool + gym").font(Theme.label(12)).opacity(0.9).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(LinearGradient.swim))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.swim")
    }
}

/// Swim hub: the plan (or goal tiles to start one), the next swim with its sets, gym days with a swim block, settings.
struct SwimHubView: View {
    @Environment(AppModel.self) private var model
    @State private var store = SwimStore.shared
    @State private var perWeek = 2
    @State private var showing: SwimWorkout?
    @State private var watchFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ContentTitle(title: "Swim")
                if let plan = store.plan { planSection(plan) } else { goalPicker }
                gymDays
                settings
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .titleInContent("Swim")
        .sheet(item: $showing) { SwimWorkoutSheet(workout: $0) }
        .alert("Couldn't reach your Watch", isPresented: $watchFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open MonkeyWorkout on your Apple Watch: today's swim is under Swim.")
        }
    }

    // MARK: Plan (B)

    @ViewBuilder private func planSection(_ plan: SwimPlan) -> some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 4) {
            Text("PLAN · \(plan.goal.label.uppercased())").font(Theme.label(12)).opacity(0.9)
            Text(plan.week(on: now).map { "Week \($0) of \(plan.weeks)" } ?? (now < plan.start ? "Starts \(plan.start.formatted(.dateTime.weekday(.wide)))" : "Done"))
                .font(Theme.display(26))
            Text("\(plan.perWeek)× a week · \(Self.dayNames(plan.days)) · pool \(plan.pool) m").font(Theme.label(12)).opacity(0.9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(.swimPlan)
        .contextMenu {
            Button("Stop plan", systemImage: "trash", role: .destructive) { stop(plan) }
        }
        if let next = plan.next(from: now) {
            let today = Calendar.current.isDateInToday(next.day)
            Button { showing = next.workout } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text((today ? "TODAY" : next.day.formatted(.dateTime.weekday(.abbreviated)).uppercased()) + " · \(next.workout.totalMeters) M · \(next.workout.minutes)′")
                        .font(Theme.label(12)).opacity(0.9)
                    Text(next.workout.summary).font(Theme.display(20)).multilineTextAlignment(.leading)
                    Text("Tap for the sets · Watch buzzes each send-off").font(Theme.label(12)).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .gradientCard(.swimDay)
            }
            .buttonStyle(.plain)
            if today {
                Button { startOnWatch() } label: {
                    Label("Start on Watch", systemImage: "applewatch").font(Theme.label(17)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
            }
        }
        if let w = plan.week(on: now) {
            Text("Week \(w)").eyebrow().padding(.top, 4)
            ForEach(0..<plan.perWeek, id: \.self) { i in
                let wk = plan.workout(week: w, index: i)
                Button { showing = wk } label: {
                    HStack {
                        Text(Self.dayNames([plan.days.sorted()[min(i, plan.days.count - 1)]])).font(Theme.label(14)).frame(width: 44, alignment: .leading)
                        Text(wk.summary).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        Text("\(wk.totalMeters) m").font(Theme.display(17))
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a plan").eyebrow()
            ForEach(SwimPlan.Goal.allCases) { g in
                Button { start(g) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: g == .learn ? "figure.pool.swim" : g == .oneK ? "1.square.fill" : "2.square.fill")
                            .font(.system(size: 20, weight: .heavy)).frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.label).font(Theme.display(19))
                            Text("8 weeks · ends with \(g.test) m non-stop").font(Theme.label(12)).opacity(0.9)
                        }
                        Spacer()
                    }
                    .gradientCard(g == .learn ? .swimPlan : g == .oneK ? .swim : .swimDay, padding: 12)
                }
                .buttonStyle(.plain)
            }
            Picker("Swims a week", selection: $perWeek) {
                Text("2 a week").tag(2)
                Text("3 a week").tag(3)
            }
            .pickerStyle(.segmented)
            Text("Swim days go on days without lifting.").font(Theme.label(12)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Gym days (C)

    @ViewBuilder private var gymDays: some View {
        let sessions = (model.plan?.sessions ?? []).filter { !(model.state.done[$0.id] ?? false) }
        if !sessions.isEmpty {
            Text("Pool + gym").eyebrow().padding(.top, 6)
            Text("Add a short swim as warm-up or finisher to a gym day.").font(Theme.label(12)).foregroundStyle(Theme.muted)
            ForEach(sessions) { s in SwimBlockCard(session: s, alwaysShow: true) }
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").eyebrow().padding(.top, 6)
            Picker("Pool", selection: Binding(get: { store.saved.pool }, set: { store.setPool($0) })) {
                Text("Pool 25 m").tag(25)
                Text("Pool 50 m").tag(50)
            }
            .pickerStyle(.segmented)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open water buddy alert").font(Theme.label(15))
                    Text("This iPhone alerts if a swim started on the Watch is still going after \(store.saved.buddyMinutes) min.")
                        .font(Theme.label(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Stepper("", value: Binding(get: { store.saved.buddyMinutes }, set: { store.setBuddyMinutes($0) }), in: 15...240, step: 15)
                    .labelsHidden()
            }
            .card(padding: 12)
            Text("Apple Watch Ultra: depth and time under water while snorkelling (up to 6 m).").font(Theme.label(12)).foregroundStyle(Theme.muted)
        }
    }

    private func start(_ g: SwimPlan.Goal) {
        // Monday weeks like Train (#989): the swim week turns over with the plan's, not on a Sunday.
        let cal = Progression.calendar()
        let days = SwimPlan.days(perWeek: perWeek, lifting: model.liftingWeekdays)
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
        store.setPlan(SwimPlan(goal: g, weeks: 8, perWeek: perWeek, start: start, days: days, pool: store.saved.pool))
        Haptics.success()
    }

    private func stop(_ plan: SwimPlan) {
        store.setPlan(nil)
        UndoCloseCenter.shared.deleted("Swim plan stopped", detail: plan.goal.label, symbol: "figure.pool.swim") {
            SwimStore.shared.setPlan(plan)
        }
    }

    private func startOnWatch() {
        WatchSync.shared.push()
        WatchSync.shared.startSport(.swim, saver: false) { ok in
            if !ok { watchFailed = true }
        }
    }

    /// Calendar weekdays (1 = Sunday) as "Tue · Thu".
    static func dayNames(_ days: [Int]) -> String {
        let names = Calendar.current.shortWeekdaySymbols
        return days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { names[($0 - 1) % 7] }.joined(separator: " · ")
    }
}

/// One swim workout: every set with its send-off (A).
struct SwimWorkoutSheet: View {
    let workout: SwimWorkout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(workout.totalMeters) m").font(Theme.display(30))
                            Text("about \(workout.minutes) min").font(Theme.label(13)).opacity(0.9)
                        }
                        Spacer()
                        Image(systemName: "figure.pool.swim").font(.system(size: 30, weight: .heavy))
                    }
                    .gradientCard(.swim)
                    ForEach(Array(workout.sets.enumerated()), id: \.offset) { i, set in
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(Theme.display(18)).frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.22)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.title).font(Theme.display(18))
                                Text(set.reps > 1 ? "leave every \(WodTimer.clock(set.sendOff))" : "in \(WodTimer.clock(set.sendOff))")
                                    .font(Theme.label(12)).opacity(0.9)
                            }
                            Spacer()
                            Text("\(set.totalMeters) m").font(Theme.display(18))
                        }
                        .gradientCard(set.stroke == .easy ? .swimPlan : set.stroke == .drill ? .swimDay : .swim, padding: 12)
                    }
                    Text("Your Watch buzzes at every send-off, with Water Lock on.").font(Theme.label(12)).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }
}

/// Gym day + swim block (C): the session, then "+ Swim 15′ · 300 m easy · 4×50 free". Tap cycles the length,
/// the chip switches warm-up / finisher, long press removes it.
struct SwimBlockCard: View {
    let session: Session
    /// In the swim hub every gym day shows, with "+ Swim" when it has none.
    var alwaysShow = false
    @State private var store = SwimStore.shared

    var body: some View {
        let block = store.block(for: session.id)
        if block != nil || alwaysShow || store.plan != nil {
            VStack(alignment: .leading, spacing: 6) {
                if alwaysShow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.title.uppercased()) · \(session.estMin)′").font(Theme.label(12)).opacity(0.9)
                        Text(session.blocks.flatMap(\.items).prefix(3).map { Exercise.find($0.exerciseId)?.name ?? $0.exerciseId }
                            .joined(separator: " · ")).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gradientCard(.swimDay, padding: 12)
                }
                if let block {
                    Button { cycle(block) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("+ SWIM \(block.minutes)′ · \(block.place.label.uppercased())").font(Theme.label(12)).opacity(0.9)
                                Text(block.workout.summary).font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer()
                            Text(block.place == .warmup ? "Finisher" : "Warm-up").font(Theme.label(12))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(.white.opacity(0.22)))
                                .onTapGesture { store.setBlock(.init(place: block.place == .warmup ? .finisher : .warmup, minutes: block.minutes), for: session.id) }
                        }
                        .gradientCard(.swimPlan, padding: 12)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove swim", systemImage: "trash", role: .destructive) { remove(block) }
                    }
                } else {
                    Button { store.setBlock(.init(place: .finisher, minutes: 15), for: session.id) } label: {
                        Label("Add a swim", systemImage: "figure.pool.swim").font(Theme.label(14)).foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 10 → 15 → 20 → 30 → 10 minutes.
    private func cycle(_ b: SwimStore.Block) {
        let steps = [10, 15, 20, 30]
        let next = steps[((steps.firstIndex(of: b.minutes) ?? 0) + 1) % steps.count]
        store.setBlock(.init(place: b.place, minutes: next), for: session.id)
    }

    private func remove(_ b: SwimStore.Block) {
        store.setBlock(nil, for: session.id)
        let id = session.id
        UndoCloseCenter.shared.deleted("Swim removed", detail: "\(b.minutes)′ \(b.place.label.lowercased())", symbol: "figure.pool.swim") {
            SwimStore.shared.setBlock(b, for: id)
        }
    }
}
