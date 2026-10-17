import Charts
import LiftSensor
import SwiftUI
import WorkoutEngine

// Hyrox add-on on the iPhone (#426, B + C from `other-sports/hyrox-proposals.png`): the hub (division, goal,
// pacing plan, sims, start on the Watch) and the race report (replay, splits vs plan and last race, run fade,
// what to work on). Races are recorded on the Watch (`HyroxTracker`).

enum HyroxColors {
    static let race = LinearGradient(colors: [Color(hex: 0xFF3D8B), Color(hex: 0xFF9A5E)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let run = LinearGradient(colors: [Color(hex: 0x3D59FF), Color(hex: 0x00C7FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let go = LinearGradient(colors: [Color(hex: 0x00B86B), Color(hex: 0x7DFFB0)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let report = LinearGradient(colors: [Color(hex: 0xFF5E3A), Color(hex: 0xFFB03D)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let focus = LinearGradient(colors: [Color(hex: 0x7D4DFF), Color(hex: 0xE040FB)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let runColor = Color(hex: 0x00C7FF)
    static let stationColor = Color(hex: 0xFF3D8B)
}

extension HyroxStep {
    var short: String {
        switch self {
        case let .run(n, _): "Run \(n)"
        case let .station(s): s.name
        }
    }
}

/// Progress: the way into the hub, with the race countdown.
struct HyroxHubCard: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.cross.training").font(.system(size: 20, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(HyroxHubView.countdown(model).uppercased()).font(Theme.label(10)).tracking(1).opacity(0.9)
                    Text("Hyrox · \(model.hyroxDivision.label)").font(Theme.display(19)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(HyroxColors.race))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { HyroxHubView() }
    }
}

/// B · Hyrox hub: division and goal, pacing plan per split, sims for this week, Start race on Watch, past races.
struct HyroxHubView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var report: HyroxRace?
    @State private var sent: String?

    static func countdown(_ model: AppModel) -> String {
        let name = model.hyroxProfile.raceName.flatMap { $0.isEmpty ? nil : $0 } ?? "Hyrox"
        guard let date = model.hyroxPlan?.event else { return "\(name) · set a race date in My sports" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day ?? 0
        if days < 0 { return "\(name) · done" }
        return days == 0 ? "\(name) · race day" : "\(name) · \(days) days"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    HyroxSettingsCard()
                    pacing
                    sims
                    startButton(.full, title: "Start race on Watch")
                    if let sent { Label(sent, systemImage: "applewatch").font(Theme.label(13)).foregroundStyle(Theme.lime) }
                    races
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Hyrox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(item: $report) { race in
                NavigationStack {
                    ScrollView { HyroxReportView(race: race).padding(16) }
                        .readableWidth()
                        .background(Theme.bg.ignoresSafeArea())
                        .navigationTitle(race.format.label)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { CloseToolbarItem { report = nil } }
                }
                .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        let d = model.hyroxDivision
        return VStack(alignment: .leading, spacing: 6) {
            Text(Self.countdown(model).uppercased()).font(Theme.label(11)).tracking(1.2).opacity(0.9)
            Text("\(d.label)\(model.hyroxGoalSeconds.map { " · goal \(HyroxTime.clock($0))" } ?? "")").font(Theme.display(26))
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                ForEach(HyroxStation.allCases.filter { d.load($0) != nil }) { s in
                    Text("\(s.name.components(separatedBy: " ").first ?? s.name) \(d.load(s) ?? "")")
                        .font(Theme.label(10)).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.25)))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(HyroxColors.race))
    }

    @ViewBuilder private var pacing: some View {
        let steps = HyroxFormat.full.steps
        if let goal = model.hyroxGoalSeconds {
            let p = HyroxPacing(goalSeconds: goal, steps: steps)
            VStack(alignment: .leading, spacing: 6) {
                Text("Pacing plan").eyebrow()
                ForEach(steps.indices, id: \.self) { i in
                    HStack {
                        Circle().fill(steps[i].isRun ? HyroxColors.runColor : HyroxColors.stationColor).frame(width: 8, height: 8)
                        Text(steps[i].short).font(Theme.label(14))
                        if let s = steps[i].station { Text(s.work).font(Theme.label(11)).foregroundStyle(Theme.muted) }
                        Spacer()
                        Text(steps[i].isRun ? "\(HyroxTime.clock(p.targets[i])) /km" : HyroxTime.clock(p.targets[i])).font(Theme.label(14))
                    }
                }
                HStack {
                    Circle().fill(Color(hex: 0xFFB03D)).frame(width: 8, height: 8)
                    Text("Roxzone, all").font(Theme.label(14))
                    Spacer()
                    Text(HyroxTime.clock(p.roxzone)).font(Theme.label(14))
                }
            }
            .card(padding: 14)
        }
    }

    /// Sims for this week: compromised runs on the station that cost the most, a half race, the full plan.
    private var sims: some View {
        let last = model.hyroxRaces.first { $0.format == .full }.map { HyroxReport($0, last: model.lastFullRace(before: $0)) }
        let focus = last?.weakest ?? .sledPush
        let options: [(HyroxFormat, String)] = [
            (.compromised(focus, rounds: 4), last?.weakest != nil ? "Your weakest station last race" : "Legs and lungs under fatigue"),
            (.half(second: false), "Runs 1–4, SkiErg to burpees"),
            (.half(second: true), "Runs 1–4, rowing to wall balls"),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("This week · sims").eyebrow()
            if let f = last?.focus {
                Label("Work on: \(f)", systemImage: "target").font(Theme.label(13)).foregroundStyle(Theme.lime)
            }
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o.0.label).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(o.1).font(Theme.label(11)).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Button { start(o.0) } label: {
                        Label("Watch", systemImage: "applewatch").font(Theme.label(12)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(HyroxColors.run))
            }
        }
    }

    private func startButton(_ format: HyroxFormat, title: String) -> some View {
        Button { start(format) } label: {
            HStack {
                Text(title).font(Theme.display(18))
                Spacer()
                Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(HyroxColors.go))
        }
        .buttonStyle(.plain)
    }

    private func start(_ format: HyroxFormat) {
        WatchSync.shared.startHyrox(format)
        sent = "\(format.label): opening on your Watch. Or start it there: Track a sport → Hyrox."
    }

    @ViewBuilder private var races: some View {
        let list = model.hyroxRaces
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Races and sims").eyebrow()
                ForEach(list) { r in
                    Button { report = r } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.format.label).font(Theme.label(14))
                                Text(r.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(Theme.label(11))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(HyroxTime.clock(r.total)).font(Theme.display(18))
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 14)
        }
    }
}

/// Division, goal time and race name, saved with the training profile (the Watch gets them too).
private struct HyroxSettingsCard: View {
    @Environment(AppModel.self) private var model
    @State private var p = HyroxProfile()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Division").eyebrow()
            HStack(spacing: 6) {
                ForEach(HyroxDivision.Category.allCases, id: \.self) { c in
                    SportChip(title: c.rawValue.capitalized, selected: p.category == c.rawValue) { p.category = c.rawValue }
                }
            }
            HStack(spacing: 6) {
                ForEach(groups, id: \.self) { g in
                    SportChip(title: g.rawValue.capitalized, selected: p.group == g.rawValue) { p.group = g.rawValue }
                }
            }
            Stepper(value: Binding(get: { p.goalMinutes ?? 90 }, set: { p.goalMinutes = $0 }), in: 50...180, step: 1) {
                HStack {
                    Text("Goal").font(Theme.label(14))
                    Spacer()
                    Text(p.goalMinutes.map { HyroxTime.clock(Double($0) * 60) } ?? "Not set").font(Theme.display(18))
                }
            }
            TextField("Race (e.g. Hyrox Hamburg)", text: Binding(get: { p.raceName ?? "" }, set: { p.raceName = $0.isEmpty ? nil : $0 }))
                .font(Theme.label(14))
                .textFieldStyle(.roundedBorder)
            Text("Race date: the event date of Hyrox in My sports.").font(.caption).foregroundStyle(Theme.muted)
        }
        .card(padding: 14)
        .onAppear {
            guard !loaded else { return }
            p = model.hyroxProfile
            loaded = true
        }
        .onChange(of: p) { _, new in
            var fixed = new
            if !groups.map(\.rawValue).contains(fixed.group) { fixed.group = "men" }
            model.saveHyroxProfile(fixed)
        }
    }

    private var groups: [HyroxDivision.Group] {
        p.category == "doubles" || p.category == "relay" ? HyroxDivision.Group.allCases : [.men, .women]
    }
}

/// C · Race report: replay, every split vs plan and the last race (tap one to fix it), run fade, what to work on.
struct HyroxReportView: View {
    @Environment(AppModel.self) private var model
    @State var race: HyroxRace
    @State private var editing: Int?
    @State private var replay: Double = 1
    @State private var playing = false

    private var last: HyroxRace? { race.format == .full ? model.lastFullRace(before: race) : nil }
    private var report: HyroxReport { HyroxReport(race, last: last) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            ReplayBar(race: race, progress: replay)
            Button {
                replay = 0
                playing = true
                withAnimation(.linear(duration: 4)) { replay = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { playing = false }
            } label: { Label(playing ? "Replaying…" : "Replay race", systemImage: "play.fill") }
                .buttonStyle(LimeButtonStyle())
                .disabled(playing)
            splits
            fade
            if let f = report.focus {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work on").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                    Text(f).font(Theme.display(19))
                    Text("Your Hyrox hub's sims start with it this week.").font(.footnote).opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(HyroxColors.focus))
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(race.format.label) · \(race.division.label)".uppercased()).font(Theme.label(10)).tracking(1).opacity(0.9)
                Text(HyroxTime.clock(race.total)).font(Theme.display(38))
                if let d = report.vsLast {
                    Text(d < 0 ? "PB \(HyroxTime.delta(d)) 🎉" : "\(HyroxTime.delta(d)) vs last race").font(Theme.label(15))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Runs \(HyroxTime.clock(race.runSeconds))").font(Theme.label(12))
                Text("Stations \(HyroxTime.clock(race.stationSeconds))").font(Theme.label(12))
                Text("Roxzone \(HyroxTime.clock(race.roxzone))").font(Theme.label(12))
                if let hr = race.avgHR { Text("♥ \(Int(hr)) avg").font(Theme.label(12)) }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(HyroxColors.report))
    }

    private var splits: some View {
        let rows = report.rows
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Splits").eyebrow()
                Spacer()
                Text(last != nil ? "plan · last" : race.goalSeconds != nil ? "vs plan" : "").font(Theme.label(11)).foregroundStyle(Theme.muted)
            }
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                VStack(spacing: 6) {
                    Button { editing = editing == i ? nil : i } label: {
                        HStack(spacing: 8) {
                            Circle().fill(r.step.isRun ? HyroxColors.runColor : HyroxColors.stationColor).frame(width: 8, height: 8)
                            Text(r.step.short).font(Theme.label(14)).lineLimit(1)
                            if let reps = r.reps, reps > 0 { Text("\(reps)").font(Theme.label(11)).foregroundStyle(Theme.muted) }
                            if !race.splits[i].auto { Image(systemName: "hand.tap").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                            Spacer()
                            Text(HyroxTime.clock(r.seconds)).font(Theme.label(14))
                            if let d = r.delta {
                                Text(HyroxTime.delta(d)).font(Theme.label(12)).frame(width: 52, alignment: .trailing)
                                    .foregroundStyle(d <= 0 ? Color.green : Color(hex: 0xFF6B6B))
                            }
                            if let l = r.last {
                                Text(HyroxTime.delta(r.seconds - l)).font(Theme.label(11)).frame(width: 48, alignment: .trailing)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    if editing == i {
                        HStack {
                            Text("Fix this split").font(Theme.label(12)).foregroundStyle(Theme.muted)
                            Spacer()
                            fixButton("−5 s", i, -5)
                            fixButton("+5 s", i, 5)
                        }
                    }
                }
            }
        }
        .card(padding: 14)
    }

    private func fixButton(_ title: String, _ i: Int, _ by: Double) -> some View {
        Button {
            var r = race
            let next = i + 1 < r.splits.count ? r.splits[i + 1].start : r.end
            let end = min(next, max(r.splits[i].start.addingTimeInterval(5), r.splits[i].end.addingTimeInterval(by)))
            r.splits[i].end = end
            r.splits[i].auto = false
            race = r
            model.saveHyroxRace(r)
        } label: {
            Text(title).font(Theme.label(13)).padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Theme.cardStrong))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var fade: some View {
        let runs = race.splits.filter(\.step.isRun)
        if runs.count >= 3 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Run pace").eyebrow()
                    Spacer()
                    if let f = report.fade {
                        Text(f > 0 ? "+\(Int((f * 100).rounded())) % at the end" : "Held your pace").font(Theme.label(12))
                            .foregroundStyle(f > 0.08 ? Color(hex: 0xFF6B6B) : Theme.lime)
                    }
                }
                Chart(runs.indices, id: \.self) { i in
                    LineMark(x: .value("Run", i + 1), y: .value("min/km", runs[i].seconds / 60))
                        .foregroundStyle(HyroxColors.runColor)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Run", i + 1), y: .value("min/km", runs[i].seconds / 60))
                        .foregroundStyle(HyroxColors.runColor)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel { if let m = v.as(Double.self) { Text(HyroxTime.clock(m * 60)) } }
                    }
                }
                .frame(height: 120)
            }
            .card(padding: 14)
        }
    }
}

/// The race as a track of steps (width = time); fills up during the replay.
private struct ReplayBar: View, Animatable {
    let race: HyroxRace
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let total = max(race.total, 1)
        let at = race.start.addingTimeInterval(total * progress)
        let now = race.splits.first { $0.start <= at && $0.end >= at }
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xFFB03D).opacity(0.35))
                    ForEach(race.splits.indices, id: \.self) { i in
                        let s = race.splits[i]
                        let x = s.start.timeIntervalSince(race.start) / total * geo.size.width
                        let w = max(2, s.seconds / total * geo.size.width)
                        Rectangle()
                            .fill(s.step.isRun ? HyroxColors.runColor : HyroxColors.stationColor)
                            .opacity(s.start <= at ? 1 : 0.25)
                            .frame(width: w)
                            .offset(x: x)
                    }
                    Rectangle().fill(Theme.lime).frame(width: 3).offset(x: progress * geo.size.width - 1.5)
                        .shadow(color: Theme.lime, radius: 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 30)
            Text(progress >= 1 ? "Finish · \(HyroxTime.clock(total))"
                 : "\(HyroxTime.clock(total * progress)) · \(now?.step.short ?? "Roxzone")")
                .font(Theme.label(12)).foregroundStyle(Theme.muted).monospacedDigit()
        }
    }
}
