import HealthKit
import SwiftUI
import WorkoutEngine
import WorkoutKit

// Run & cardio programmes (#618, designs A + B + C from `apple-tech-radar/x1.png`), heart-rate zones on Progress
// (#609, design C from `t7.png`) and Apple's Workout app (#610, designs A + C from `t8.png`).

private let runColors = [Color(hex: 0xFF3D8B), Color(hex: 0xFF9A5E)]
private let hybridColors = [Color(hex: 0x00B86B), Color(hex: 0x3D59FF)]

extension RunWorkout {
    var symbol: String {
        switch sport {
        case .roadBike, .mountainBike: "bicycle"
        case .rowing: "figure.rower"
        default: kind == .race ? "flag.checkered" : "figure.run"
        }
    }

    var colors: [Color] {
        kind.hard ? runColors : zone == 2 ? [Color(hex: 0x00B86B), Color(hex: 0x3DFFB0)] : [Color(hex: 0x3D59FF), Color(hex: 0x00C7FF)]
    }
}

// MARK: - Train: goal race / hybrid card (designs A + C)

/// Under Next up on Train while a run goal is set: race countdown (or Hybrid mode), the week's runs next to lifting
/// days, tap a run for its steps and start.
struct RunGoalCard: View {
    @Environment(AppModel.self) private var model
    @State private var opened: RunDay?
    @State private var editing = false

    var body: some View {
        if let goal = model.runGoal {
            let week = model.runWeek
            VStack(alignment: .leading, spacing: 10) {
                Button { editing = true } label: { header(goal) }
                    .buttonStyle(.plain)
                weekStrip(week)
                if let today = week.first(where: { $0.weekday == model.todayWeekday }) {
                    Button { opened = today } label: { todayRow(today) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("train.todayRun")
                } else {
                    Text(goal.mode == .hybrid ? "Zone 2 and intervals fill the days around lifting." : "Long run Sat, never the day after legs.")
                        .font(Theme.label(11)).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: goal.mode == .hybrid ? hybridColors : runColors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .sheet(item: $opened) { RunSessionSheet(day: $0) }
            .sheet(isPresented: $editing) { RunGoalEditor(initial: goal) }
        }
    }

    @ViewBuilder private func header(_ goal: RunGoal) -> some View {
        let cal = model.planCalendar
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: goal.mode == .hybrid ? "figure.strengthtraining.functional" : "flag.checkered")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                if goal.mode == .hybrid {
                    Text("HYBRID MODE").font(Theme.label(11)).tracking(1.4).opacity(0.85)
                    Text("Lift \(model.profile?.sessionsPerWeek ?? 3)× · Cardio \(goal.perWeek)×").font(Theme.display(22))
                } else {
                    Text(raceLine(goal, cal)).font(Theme.label(11)).tracking(1.4).opacity(0.85).lineLimit(1)
                    Text("Target \(RunPlanner.clock(goal.target))").font(Theme.display(22))
                }
            }
            Spacer(minLength: 0)
            if let days = goal.daysLeft(now: Date(), cal), days >= 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(days >= 14 ? "\(days / 7)" : "\(days)").font(Theme.display(30))
                    Text(days >= 14 ? "WKS" : "DAYS").font(Theme.label(10)).opacity(0.85)
                }
            }
        }
    }

    private func raceLine(_ goal: RunGoal, _ cal: Calendar) -> String {
        var parts = [goal.distance.label]
        if let n = goal.raceName, !n.isEmpty { parts.append(n) }
        if let d = goal.race(cal) { parts.append(d.formatted(.dateTime.day().month(.abbreviated))) }
        if let phase = RunPlanner.phase(goal, weekStart: Progression.weekStart(Date(), cal), cal) { parts.append(phase.label) }
        return parts.joined(separator: " · ").uppercased()
    }

    /// M…S: lift, run (✓ when done) or rest.
    private func weekStrip(_ week: [RunDay]) -> some View {
        let lifting = Set((model.plan?.sessions ?? []).compactMap(\.weekday))
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { d in
                let run = week.first { $0.weekday == d }
                let today = d == model.todayWeekday
                Button { if let run { opened = run } } label: {
                    VStack(spacing: 2) {
                        Text(letters[d - 1]).font(Theme.label(10)).opacity(0.8)
                        Image(systemName: run.map { model.runDone($0) ? "checkmark" : $0.workout.symbol }
                              ?? (lifting.contains(d) ? "dumbbell.fill" : "moon.zzz.fill"))
                            .font(.system(size: 13, weight: .bold))
                            .frame(height: 18)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(today ? Theme.ink : .white)
                    .background(RoundedRectangle(cornerRadius: 9).fill(today ? Color.white : Color.white.opacity(run == nil ? 0.12 : 0.28)))
                }
                .buttonStyle(.plain)
                .disabled(run == nil)
                .accessibilityLabel(run.map { "\($0.workout.title)" } ?? (lifting.contains(d) ? "Lifting" : "Rest"))
            }
        }
    }

    private func todayRow(_ day: RunDay) -> some View {
        let done = model.runDone(day)
        return HStack(spacing: 8) {
            Image(systemName: day.workout.symbol).font(.system(size: 15, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text("Today · \(day.workout.title)").font(Theme.display(16)).lineLimit(1)
                Text(day.workout.detail).font(Theme.label(11)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(done ? "DONE" : "\(day.workout.minutes)′ ›").font(Theme.label(13))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.2)))
    }
}

// MARK: - Run session: steps, start in MonkeyFit or Apple Workout, Send to Workout app

/// The planned run as big step blocks (design B preview), Start (design C: MonkeyFit player or Apple Workout,
/// remembered per sport) and Send to Workout app (#610 design A).
struct RunSessionSheet: View {
    let day: RunDay
    /// Demo screen `run-start`: the chooser open.
    var demoChoosing = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var remember = false
    @State private var applePreview = false
    @State private var message: String?
    @State private var link = WatchLink.shared

    private var workout: RunWorkout { day.workout }

    private var demoShowsStart: Bool {
        #if DEBUG
        Demo.enabled
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(workout.title).font(Theme.display(32))
                    Text("\(workout.detail) · \(workout.minutes) min").eyebrow()
                    ForEach(Array(workout.steps.enumerated()), id: \.offset) { _, step in stepBlock(step) }
                    if let message { Text(message).font(Theme.label(12)).foregroundStyle(Theme.lime) }
                    if link.ready || demoShowsStart {
                        Button { start() } label: {
                            Label("Start \(workout.title.lowercased())", systemImage: "play.fill")
                                .font(Theme.label(16)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(Theme.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("run.start")
                        Button { applePreview = true } label: {
                            Label("Send to Workout app", systemImage: "applewatch")
                                .font(Theme.label(15)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(LinearGradient(colors: runColors, startPoint: .leading, endPoint: .trailing),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Pair an Apple Watch to run this with its steps, or log it after with Log sport.")
                            .font(Theme.label(12)).opacity(0.8)
                    }
                    Text("Done in any app? It shows as done once Apple Health has it.").font(Theme.label(11)).opacity(0.7)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(isPresented: $choosing) { chooser }
            .appleWorkoutPreview(workout, isPresented: $applePreview)
            .onAppear { if demoChoosing { choosing = true } }
        }
        .preferredColorScheme(.dark)
    }

    private func stepBlock(_ s: RunStep) -> some View {
        let tint = s.kind == .work ? runColors : s.zone.map { z in HeartZones.tints[z - 1] }.map { [Color(hex: $0.0), Color(hex: $0.1)] }
            ?? [Color(hex: 0x3D59FF), Color(hex: 0x00C7FF)]
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(stepTitle(s)).font(Theme.display(17))
                Text([s.pace.map { "\(RunPlanner.clock($0))/km" }, s.zone.map { "Zone \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.label(11)).opacity(0.85)
            }
            Spacer()
            Text(s.meters.map { $0 >= 1000 ? String(format: "%.1f km", Double($0) / 1000) : "\($0) m" } ?? s.seconds.map { RunPlanner.clock($0) } ?? "")
                .font(Theme.display(20))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: tint, startPoint: .leading, endPoint: .trailing)))
    }

    private func stepTitle(_ s: RunStep) -> String {
        switch s.kind {
        case .warmup: "Warm-up"
        case .recover: "Recover"
        case .cooldown: "Cool-down"
        case .steady: workout.sport == .run ? "Easy" : "Steady"
        case .work: s.of.map { $0 > 1 ? "Rep \(s.rep ?? 1) of \($0)" : "Work" } ?? "Work"
        }
    }

    /// Remembered choice starts at once; else the chooser (design C).
    private func start() {
        switch RunStartChoice.remembered(workout.sport) {
        case .monkey: startMonkey()
        case .apple: applePreview = true
        case nil: choosing = true
        }
    }

    private func startMonkey() {
        WatchSync.shared.startSport(workout.sport, saver: false, run: workout) { ok in
            message = ok ? "Started on your Watch." : "Couldn't reach your Watch. Open MonkeyWorkout on it: today's run is at the top of Track a sport."
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start \(workout.title.lowercased())").font(Theme.display(24))
            choice(.monkey, title: "MonkeyFit player", detail: "Steps, zones, Coach voice", symbol: "figure.run", colors: runColors)
            choice(.apple, title: "Apple Workout", detail: "Workout Buddy, Precision Start", symbol: "applewatch",
                   colors: [Color(hex: 0x3D59FF), Color(hex: 0x00C7FF)])
            Toggle("Remember for \(workout.sport.label.lowercased())", isOn: $remember)
                .font(Theme.label(14)).tint(Theme.lime)
        }
        .padding(20)
        .presentationDetents([.height(320)])
        .preferredColorScheme(.dark)
    }

    private func choice(_ c: RunStartChoice, title: String, detail: String, symbol: String, colors: [Color]) -> some View {
        Button {
            if remember { RunStartChoice.remember(c, for: workout.sport) }
            choosing = false
            if c == .monkey { startMonkey() } else {
                // After the chooser closes: one sheet at a time.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    applePreview = true
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.display(18))
                    Text(detail).font(Theme.label(11)).opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WorkoutKit (#610)

/// A planned run as Apple's custom workout: warm-up, interval blocks (same reps grouped), cool-down, with pace or
/// heart-rate zone alerts where the Workout app supports them.
enum AppleWorkoutPlan {
    static func plan(_ w: RunWorkout) -> WorkoutPlan? {
        let activity: HKWorkoutActivityType = switch w.sport {
        case .roadBike, .mountainBike: .cycling
        case .rowing: .rowing
        default: .running
        }
        let location: HKWorkoutSessionLocationType = w.sport == .rowing ? .indoor : .outdoor
        guard CustomWorkout.supportsActivity(activity) else { return nil }
        var steps = w.steps
        var warmup: WorkoutStep?
        var cooldown: WorkoutStep?
        if steps.first?.kind == .warmup { warmup = step(steps.removeFirst(), activity, location) }
        if steps.last?.kind == .cooldown { cooldown = step(steps.removeLast(), activity, location) }
        // Work + its recovery as one pair; identical pairs in a row become one block with iterations.
        var pairs: [[RunStep]] = []
        for s in steps {
            if s.kind == .recover, let last = pairs.last, last.count == 1, last[0].kind == .work {
                pairs[pairs.count - 1].append(s)
            } else {
                pairs.append([s])
            }
        }
        var blocks: [IntervalBlock] = []
        var i = 0
        while i < pairs.count {
            var n = 1
            while i + n < pairs.count, same(pairs[i + n], pairs[i]) { n += 1 }
            // The last rep has no recovery: it still counts with the block when the rest match.
            if i + n < pairs.count, pairs[i + n].count == 1, pairs[i].count == 2, same([pairs[i + n][0]], [pairs[i][0]]) { n += 1 }
            let intervalSteps = pairs[i].map { s in
                IntervalStep(s.kind == .recover ? .recovery : .work, step: step(s, activity, location))
            }
            blocks.append(IntervalBlock(steps: intervalSteps, iterations: n))
            i += n
        }
        let custom = CustomWorkout(activity: activity, location: location, displayName: w.title, warmup: warmup, blocks: blocks, cooldown: cooldown)
        return WorkoutPlan(.custom(custom), id: UUID())
    }

    private static func same(_ a: [RunStep], _ b: [RunStep]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.kind == $1.kind && $0.meters == $1.meters && $0.seconds == $1.seconds && $0.pace == $1.pace }
    }

    private static func step(_ s: RunStep, _ activity: HKWorkoutActivityType, _ location: HKWorkoutSessionLocationType) -> WorkoutStep {
        let goal: WorkoutGoal = if let m = s.meters { .distance(Double(m), .meters) } else if let sec = s.seconds { .time(Double(sec), .seconds) } else { .open }
        return WorkoutStep(goal: goal, alert: alert(s, activity, location))
    }

    private static func alert(_ s: RunStep, _ activity: HKWorkoutActivityType, _ location: HKWorkoutSessionLocationType) -> (any WorkoutAlert)? {
        var a: (any WorkoutAlert)?
        if let pace = s.pace, activity == .running {
            // ±3 % around the target pace, as speed.
            let mps = 1000 / Double(pace)
            a = SpeedRangeAlert(target: Measurement(value: mps * 0.97, unit: UnitSpeed.metersPerSecond)...Measurement(value: mps * 1.03, unit: UnitSpeed.metersPerSecond),
                                metric: .current)
        } else if let z = s.zone {
            a = HeartRateZoneAlert(zone: z)
        }
        guard let a, CustomWorkout.supportsAlert(a, activity: activity, location: location) else { return nil }
        return a
    }
}

extension View {
    /// Apple's preview sheet for the run (Send to Watch, schedule), when it makes a custom workout.
    func appleWorkoutPreview(_ w: RunWorkout, isPresented: Binding<Bool>) -> some View {
        modifier(AppleWorkoutPreview(plan: AppleWorkoutPlan.plan(w), isPresented: isPresented))
    }
}

private struct AppleWorkoutPreview: ViewModifier {
    let plan: WorkoutPlan?
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if let plan { content.workoutPreview(plan, isPresented: $isPresented) } else { content }
    }
}

// MARK: - Goal editor

/// Race (distance, date, goal time, name) or Hybrid; runs a week. Remove ends the programme.
struct RunGoalEditor: View {
    var initial: RunGoal?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var goal = RunGoal()
    @State private var date = Calendar.current.date(byAdding: .weekOfYear, value: 10, to: Date()) ?? Date()
    @State private var targetMinutes = 58
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(initial == nil ? "Run & cardio" : "Your run plan").font(Theme.display(30))
                    HStack(spacing: 8) {
                        modeTile(.race, title: "Race", detail: "5K · 10K · half", symbol: "flag.checkered", colors: runColors)
                        modeTile(.hybrid, title: "Hybrid", detail: "Fitter + stronger", symbol: "figure.strengthtraining.functional", colors: hybridColors)
                    }
                    if goal.mode == .race {
                        Text("Distance").eyebrow()
                        HStack(spacing: 8) {
                            ForEach(RunDistance.allCases) { d in
                                Button {
                                    goal.distance = d
                                    targetMinutes = d.defaultTarget / 60
                                } label: {
                                    Text(d.short).font(Theme.display(18))
                                        .foregroundStyle(goal.distance == d ? Theme.ink : .white)
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .background(RoundedRectangle(cornerRadius: 14).fill(goal.distance == d ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        DatePicker("Race day", selection: $date, in: Date()..., displayedComponents: .date)
                            .font(Theme.label(15))
                        Stepper(value: $targetMinutes, in: 12...300) {
                            HStack {
                                Text("Goal time").font(Theme.label(15))
                                Spacer()
                                Text(RunPlanner.clock(targetMinutes * 60)).font(Theme.display(20))
                                Text("\(RunPlanner.clock(targetMinutes * 60 * 1000 / Int(goal.distance.km * 1000)))/km").font(Theme.label(11)).opacity(0.75)
                            }
                        }
                        TextField("Race name (optional)", text: Binding(get: { goal.raceName ?? "" }, set: { goal.raceName = $0.isEmpty ? nil : $0 }))
                            .font(Theme.label(15))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                    }
                    Stepper(value: $goal.perWeek, in: 2...4) {
                        HStack {
                            Text(goal.mode == .race ? "Runs a week" : "Cardio a week").font(Theme.label(15))
                            Spacer()
                            Text("\(goal.perWeek)").font(Theme.display(20))
                        }
                    }
                    Text(goal.mode == .race
                         ? "Runs slot around your lifting: long run on Saturday, never the day after legs. Base, build, peak, then a light race week."
                         : "Two Zone 2 sessions (bike, row or run) and one interval day, added around your lifting.")
                        .font(Theme.label(12)).opacity(0.8)
                    Button { save() } label: {
                        Text("Save").font(Theme.label(16)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Theme.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("run.save")
                    if initial != nil {
                        Button(role: .destructive) {
                            model.saveRunGoal(nil)
                            dismiss()
                        } label: {
                            Text("Remove run plan").font(Theme.label(14)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
                .padding(16)
            }
            .foregroundStyle(.white)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func modeTile(_ m: RunGoal.Mode, title: String, detail: String, symbol: String, colors: [Color]) -> some View {
        Button { goal.mode = m } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                Text(title).font(Theme.display(20))
                Text(detail).font(Theme.label(11)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(goal.mode == m ? Theme.lime : .clear, lineWidth: 3))
            .opacity(goal.mode == m ? 1 : 0.6)
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let initial else { return }
        goal = initial
        if let d = initial.race(model.planCalendar) { date = d }
        targetMinutes = initial.target / 60
    }

    private func save() {
        var g = goal
        if g.mode == .race {
            g.raceDate = RunPlanner.dayKey(date, model.planCalendar)
            g.targetSeconds = targetMinutes * 60
        } else {
            g.raceDate = nil
        }
        model.saveRunGoal(g)
        dismiss()
    }
}

/// Training profile hub: the run plan, or set one up.
struct RunGoalProfileCard: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            if let g = model.runGoal {
                ExpertStatCard(symbol: g.mode == .hybrid ? "figure.strengthtraining.functional" : "figure.run",
                               title: g.mode == .hybrid ? "Hybrid mode" : "\(g.distance.label) plan",
                               detail: g.mode == .hybrid ? "Zone 2 and intervals around lifting" : "Goal \(RunPlanner.clock(g.target))",
                               value: "\(g.perWeek)×", unit: "a week", colors: g.mode == .hybrid ? hybridColors : runColors)
            } else {
                ExpertStatCard(symbol: "figure.run", title: "Run & cardio", detail: "5K, 10K, half or Hybrid around your lifting",
                               value: "", colors: runColors)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.runGoal")
        .sheet(isPresented: $editing) { RunGoalEditor(initial: model.runGoal) }
    }
}

// MARK: - Progress: week in zones (#609, design C)

/// Minutes per heart-rate zone this week and the Zone 2 goal ring.
struct ZoneWeekCard: View {
    let time: ZoneTime
    let fromApple: Bool

    var body: some View {
        let mins = time.minutes
        let top = max(mins.max() ?? 1, 1)
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ZONE 2 THIS WEEK").font(Theme.label(11)).tracking(1.4).opacity(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(time.zone2Minutes)′").font(Theme.display(34))
                    Text("goal \(HeartZones.zone2Goal)′").font(Theme.label(12)).opacity(0.85)
                }
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<HeartZones.count, id: \.self) { i in
                        let t = HeartZones.tints[i]
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(LinearGradient(colors: [Color(hex: t.1), Color(hex: t.0)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 24, height: max(4, 46 * CGFloat(mins[i]) / CGFloat(top)))
                            Text("Z\(i + 1)").font(Theme.label(9)).opacity(0.85)
                        }
                    }
                }
                Text(fromApple ? "Your zones from Apple Health" : "Zones from your age and resting heart rate")
                    .font(Theme.label(9)).opacity(0.7)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 9)
                Circle().trim(from: 0, to: time.zone2Progress)
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((time.zone2Progress * 100).rounded()))%").font(Theme.display(18))
            }
            .frame(width: 78, height: 78)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x00B86B), Color(hex: 0x00A3C4)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }
}
