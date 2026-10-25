import Charts
import SwiftUI
import WorkoutEngine

// MARK: - Expert lifters (#499)
//
// Designs A + B + C from `expert-lifters/proposals.png`:
// A · Lift Focus: a peaking block for one lift toward a target (Training profile card, Lift Lab button).
// B · Pro Sets: set styles per exercise (exercise page), shown in the player's set card with warm-ups and plates.
// C · Lift Lab: one lift's numbers (exercise page).

private let focusColors = [Color(hex: 0xFF9F1C), Color(hex: 0xFF3D5A)]
private let labColors = [Color(hex: 0x3D5AFF), Color(hex: 0x8A4FFF)]
private let tealColors = [Color(hex: 0x00C6A7), Color(hex: 0x1E9BFF)]
private let pinkColors = [Color(hex: 0xB23DFF), Color(hex: 0xFF4FD8)]
private let hotColors = [Color(hex: 0xFF3D8B), Color(hex: 0xFF9A5E)]

private func gradient(_ c: [Color]) -> LinearGradient { LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing) }

/// Explore-look stat card: icon tile left, heavy title and line, big number right.
struct ExpertStatCard: View {
    let symbol: String
    let title: String
    let detail: String
    let value: String
    var unit: String = ""
    let colors: [Color]
    /// My plan add-on grid (#760): square tile, icon and value on top, title and detail below.
    @Environment(\.statCardTile) private var tile

    var body: some View {
        if tile { tileBody } else { rowBody }
    }

    private var tileBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.black.opacity(0.22)))
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value).font(Theme.display(20)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    if !unit.isEmpty { Text(unit).font(Theme.label(9)).opacity(0.85).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
            Text(title).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.caption2.weight(.semibold)).opacity(0.88).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .gradientCard(gradient(colors), padding: 12)
        .accessibilityElement(children: .combine)
    }

    private var rowBody: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption.weight(.semibold)).opacity(0.88).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).font(Theme.display(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                if !unit.isEmpty { Text(unit).font(Theme.label(10)).opacity(0.85) }
            }
        }
        .gradientCard(gradient(colors), padding: 14)
        .accessibilityElement(children: .combine)
    }
}

extension EnvironmentValues {
    /// `ExpertStatCard` as a square tile (#760).
    @Entry var statCardTile = false
}

// MARK: - B · Pro Sets in the player

/// Warm-up ramp before the first set: "WARM-UP 20×10 · 60×5 · 85×3 · 100×1".
struct WarmupLine: View {
    let steps: [RampStep]

    var body: some View {
        HStack(spacing: 6) {
            Text("WARM-UP").font(Theme.label(10)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Theme.lime))
            Text(steps.map { "\(LoadAdvisor.formatKg($0.kg))×\($0.reps)" }.joined(separator: " · "))
                .font(Theme.label(12)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player.warmup")
    }
}

/// The coming set's role ("TOP · 3 @ RPE 8") and the plates per side for barbell work. One line, always the same height.
struct ProSetLine: View {
    let set: PlannedSet?
    let kg: Double?
    let bar: Double?
    let color: Color

    var body: some View {
        let plates = bar.flatMap { b in kg.flatMap { Plates.perSide(total: $0, bar: b) } }
        if set?.role.tag != nil || plates != nil {
            HStack(spacing: 6) {
                if let set, let tag = set.role.tag {
                    Text(tag).font(Theme.label(10)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(color))
                    Text([set.target, set.note].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 4)
                if let plates {
                    PlateStrip(plates: plates)
                    Text(plates.isEmpty ? "Empty bar" : plates.map { LoadAdvisor.formatKg($0) }.joined(separator: " ") + " /side")
                        .font(Theme.label(11)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(height: 24)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("player.proSet")
        }
    }
}

/// Plates on one side of the bar, heaviest inside, height by weight.
struct PlateStrip: View {
    let plates: [Double]

    var body: some View {
        HStack(spacing: 1.5) {
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.5)).frame(width: 12, height: 3)
            ForEach(Array(plates.enumerated()), id: \.offset) { _, p in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Self.color(p))
                    .frame(width: p >= 10 ? 5 : 3.5, height: 8 + 14 * min(1, p / 25))
            }
        }
        .accessibilityHidden(true)
    }

    /// Competition plate colours.
    static func color(_ kg: Double) -> Color {
        switch kg {
        case 25...: Color(hex: 0xFF3D5A)
        case 20...: Color(hex: 0x2F6BFF)
        case 15...: Color(hex: 0xFFC93D)
        case 10...: Color(hex: 0x1ED98A)
        case 5...: .white
        default: Color.white.opacity(0.6)
        }
    }
}

// MARK: - B · Set style (exercise page)

/// Exercise page: the exercise's set style, tap to change.
struct SetStyleCard: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise
    @State private var open = false

    var body: some View {
        let style = model.setStyle(exercise.id)
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: style.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set style").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                    Text(style.label).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
            }
            .gradientCard(gradient(hotColors), padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercise.setStyle")
        .sheet(isPresented: $open) { SetStyleSheet(exercise: exercise) }
    }
}

/// Pick how this exercise's sets are done; applies to every workout with it.
struct SetStyleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Every workout with \(exercise.name) uses it. Rate your sets and Monkey sets the next weights.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    let current = model.setStyle(exercise.id)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(SetStyle.allCases.enumerated()), id: \.element) { n, s in
                            Button {
                                model.setSetStyle(s, for: exercise.id)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: s.symbol)
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(width: 36, height: 36)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.22)))
                                    Text(s.label).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.6)
                                    Text(s.blurb).font(.caption2.weight(.semibold)).opacity(0.9).lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                                .padding(12)
                                .selectableGradient(gradient(Self.palette[n % Self.palette.count]), selected: s == current, cornerRadius: 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(s == current ? .isSelected : [])
                            .accessibilityIdentifier("setStyle.\(s.rawValue)")
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Set style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
    }

    static let palette: [[Color]] = [labColors, focusColors, pinkColors, tealColors, hotColors,
                                     WorkoutEngine.Category.strength.colors, WorkoutEngine.Category.power.colors,
                                     WorkoutEngine.Category.cardio.colors]
}

// MARK: - C · Lift Lab

/// Exercise page entry to the lift's Lift Lab.
struct LiftLabCard: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise

    var body: some View {
        NavigationLink {
            LiftLabView(exerciseId: exercise.id)
        } label: {
            ExpertStatCard(symbol: "flask.fill", title: "Lift Lab", detail: "e1RM trend, rep records, test-day attempts",
                           value: model.liveOneRepMax(exercise.id).map { LoadAdvisor.formatKg($0) } ?? "–", unit: "e1RM kg",
                           colors: labColors)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercise.liftLab")
    }
}

struct LiftLabView: View {
    @Environment(AppModel.self) private var model
    let exerciseId: String
    @State private var focusing = false

    private var since: Date { Date().addingTimeInterval(-28 * 86400) }

    var body: some View {
        let e = Exercise.get(exerciseId)
        let trend = Array(model.oneRepMaxTrend(exerciseId).suffix(12))
        let orm = model.liveOneRepMax(exerciseId)
        let logs = model.setLogs.filter { $0.exerciseId == exerciseId && !PRPlanner.isPRSession($0.sessionId) }
        let records = LiftLab.repRecords(exerciseId: exerciseId, logs: logs, attempts: model.state.prAttempts ?? [])
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(e, trend: trend, orm: orm)
                if trend.count >= 2 { trendCard(trend, best: records.first { $0.reps == 1 }?.kg) }
                if !records.isEmpty { recordsCard(records) }
                speedCard(e)
                if let orm { heavyAndAttempts(e, orm: orm, logs: logs) }
                if orm == nil && records.isEmpty {
                    Text("Log a few sets of \(e.name) and its numbers show here.")
                        .font(.subheadline).foregroundStyle(Theme.muted).card()
                }
                if ProSets.eligible(e) { actions(e) }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Lift Lab")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $focusing) { LiftFocusSheet(exerciseId: exerciseId) }
    }

    private func header(_ e: Exercise, trend: [(Date, Double)], orm: Double?) -> some View {
        let gain: Double? = trend.count >= 2 ? (trend.last?.1 ?? 0) - (trend.first?.1 ?? 0) : nil
        let unit = gain.map { ($0 >= 0 ? "+" : "") + LoadAdvisor.formatKg($0) + " kg" } ?? "e1RM kg"
        return ExpertStatCard(symbol: "flask.fill", title: e.name, detail: "Estimated 1RM · \(trend.count) weeks",
                              value: orm.map { LoadAdvisor.formatKg($0) } ?? "–", unit: unit, colors: labColors)
    }

    private func trendCard(_ trend: [(Date, Double)], best: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("e1RM trend").eyebrow()
            Chart {
                ForEach(Array(trend.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Week", p.0), y: .value("kg", p.1))
                        .foregroundStyle(Theme.lime)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        .interpolationMethod(.catmullRom)
                }
                if let best {
                    RuleMark(y: .value("Best", best))
                        .foregroundStyle(Color(hex: 0xFF4FD8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 140)
        }
        .card()
    }

    private func recordsCard(_ records: [RepRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rep records").eyebrow()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(records) { r in recordTile(r) }
            }
            Text("Coloured: set in the last 4 weeks.").font(.caption2).foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func recordTile(_ r: RepRecord) -> some View {
        let fresh = r.date >= since
        let fill: AnyShapeStyle = fresh ? AnyShapeStyle(gradient(focusColors)) : AnyShapeStyle(Theme.cardStrong)
        return VStack(spacing: 2) {
            Text("\(r.reps)RM").font(Theme.label(10)).opacity(0.85)
            Text(LoadAdvisor.formatKg(r.kg)).font(Theme.display(18)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.reps) rep max \(LoadAdvisor.formatKg(r.kg)) kg\(fresh ? ", new this month" : "")")
    }

    @ViewBuilder
    private func speedCard(_ e: Exercise) -> some View {
        if let speed = barSpeed(e) {
            let detail = String(format: "%.2f m/s", speed.now) + (speed.then.map { String(format: " · was %.2f", $0) } ?? "")
            let value = speed.then.map { Self.percent(speed.now / $0 - 1) } ?? String(format: "%.2f", speed.now)
            ExpertStatCard(symbol: "bolt.fill", title: "Bar speed @ \(LoadAdvisor.formatKg(speed.kg))", detail: detail,
                           value: value, unit: speed.then == nil ? "m/s" : "faster", colors: tealColors)
        }
    }

    @ViewBuilder
    private func heavyAndAttempts(_ e: Exercise, orm: Double, logs: [SetLog]) -> some View {
        ExpertStatCard(symbol: "chart.bar.fill", title: "Heavy sets ≥85%", detail: "Last 4 weeks",
                       value: "\(LiftLab.heavySets(exerciseId: exerciseId, logs: logs, oneRepMax: orm, since: since))",
                       unit: "sets", colors: pinkColors)
        let target = model.liftFocus.flatMap { $0.exerciseId == exerciseId ? $0.targetKg : nil }
        AttemptsCard(attempts: LiftFocus.attempts(oneRepMax: orm, target: target, exercise: e))
    }

    private func actions(_ e: Exercise) -> some View {
        VStack(spacing: 12) {
            SetStyleCard(exercise: e)
            Button { focusing = true } label: {
                Label(model.liftFocus?.exerciseId == exerciseId ? "Lift Focus running" : "Focus this lift", systemImage: "scope")
            }
            .buttonStyle(LimeButtonStyle())
            .accessibilityIdentifier("lab.focus")
        }
    }

    static func percent(_ v: Double) -> String { (v >= 0 ? "+" : "") + "\(Int((v * 100).rounded()))%" }

    /// Fastest rep at the last measured load, now and on the first day measured at that load.
    private func barSpeed(_ e: Exercise) -> (kg: Double, now: Double, then: Double?)? {
        let sets = LiftSets.shared.sets(exerciseId: e.id).filter { !$0.machine && $0.kg > 0 }
        guard let last = sets.last, let now = sets.filter({ $0.kg == last.kg && Calendar.current.isDate($0.date, inSameDayAs: last.date) })
            .compactMap(\.best).max() else { return nil }
        let first = sets.first { $0.kg == last.kg }
        let then = first.flatMap { f in
            Calendar.current.isDate(f.date, inSameDayAs: last.date) ? nil
                : sets.filter { $0.kg == last.kg && Calendar.current.isDate($0.date, inSameDayAs: f.date) }.compactMap(\.best).max()
        }
        return (last.kg, now, then)
    }
}

/// Opener, second and third for a test day.
struct AttemptsCard: View {
    let attempts: [Double]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Test day attempts").font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.7)
                Text("Opener · second · third").font(.caption.weight(.semibold)).opacity(0.88)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                ForEach(Array(attempts.enumerated()), id: \.offset) { _, kg in
                    Text(LoadAdvisor.formatKg(kg)).font(Theme.display(17)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.22)))
                }
            }
        }
        .gradientCard(gradient(focusColors), padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A · Lift Focus

/// Training profile card: the running block, or start one.
struct LiftFocusCard: View {
    @Environment(AppModel.self) private var model
    @State private var setup = false

    var body: some View {
        Group {
            if let f = model.liftFocus, !f.finished(on: Date()) {
                NavigationLink { LiftFocusView() } label: { running(f) }
                    .buttonStyle(.plain)
            } else {
                Button { setup = true } label: {
                    ExpertStatCard(symbol: "scope", title: "Lift Focus", detail: "Peak one lift for a target by a test day",
                                   value: "", colors: focusColors)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("profile.liftFocus")
        .sheet(isPresented: $setup) { LiftFocusSheet(exerciseId: nil) }
    }

    private func running(_ f: LiftFocus) -> some View {
        let w = f.week(on: Date())
        return ExpertStatCard(symbol: "scope", title: Exercise.find(f.exerciseId)?.name ?? "Lift Focus",
                              detail: w.map { "Week \($0) of \(f.weeks) · \(f.phase(week: $0).label) · goal \(LoadAdvisor.formatKg(f.targetKg)) kg" }
                                  ?? "Starts \(f.start.formatted(.dateTime.day().month()))",
                              value: model.liveOneRepMax(f.exerciseId).map { LoadAdvisor.formatKg($0) } ?? "–", unit: "e1RM kg",
                              colors: focusColors)
    }
}

/// The running block: week bars, prediction, rest of plan, weak point.
struct LiftFocusView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        ScrollView {
            if let f = model.liftFocus {
                let e = Exercise.get(f.exerciseId)
                let live = model.liveOneRepMax(f.exerciseId)
                let current = f.week(on: Date())
                VStack(alignment: .leading, spacing: 12) {
                    ExpertStatCard(symbol: "scope", title: e.name.uppercased(),
                                   detail: "Goal \(LoadAdvisor.formatKg(f.targetKg)) kg · \(f.testDate.formatted(.dateTime.day().month()))",
                                   value: live.map { LoadAdvisor.formatKg($0) } ?? "–", unit: "e1RM kg", colors: focusColors)
                    weekBars(f, current: current)
                    let predicted = f.predicted(trend: model.oneRepMaxTrend(f.exerciseId))
                    let toGo = f.targetKg - (live ?? f.startOneRepMax)
                    ExpertStatCard(symbol: "chart.line.uptrend.xyaxis",
                                   title: predicted.map { $0 >= f.targetKg ? "On track" : "Behind" } ?? "Building",
                                   detail: predicted.map { "Predicted \(LoadAdvisor.formatKg(LoadAdvisor.round($0, to: 0.5))) kg on test day" }
                                       ?? "Log 2 weeks for a prediction",
                                   value: toGo > 0 ? "+\(LoadAdvisor.formatKg(toGo))" : "✓", unit: toGo > 0 ? "kg to go" : "target hit",
                                   colors: labColors)
                    ExpertStatCard(symbol: "scalemass.fill", title: "Rest of plan",
                                   detail: f.maintenance ? "Other lifts at maintenance volume" : "Other lifts as planned",
                                   value: f.maintenance ? "−30%" : "100%", unit: "sets", colors: tealColors)
                    let acc = LiftFocus.accessories(for: f.exerciseId, f.weakPoint).compactMap(Exercise.find)
                    if !acc.isEmpty {
                        ExpertStatCard(symbol: "puzzlepiece.fill", title: "Weak point",
                                       detail: "\(f.weakPoint.label(for: f.exerciseId)) → \(acc.map(\.name).joined(separator: ", "))",
                                       value: "\(acc.count)", unit: "added", colors: pinkColors)
                    }
                    Text(f.template.label + " · " + f.template.blurb).font(.footnote).foregroundStyle(Theme.muted)
                    Button { editing = true } label: { Label("Change block", systemImage: "slider.horizontal.3") }
                        .buttonStyle(LimeButtonStyle())
                    Button(role: .destructive) { model.setLiftFocus(nil) } label: {
                        Text("Stop Lift Focus").font(Theme.label(14)).frame(maxWidth: .infinity)
                    }
                    .padding(.top, 4)
                    .accessibilityIdentifier("focus.stop")
                }
                .padding(16)
            }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Lift Focus")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { LiftFocusSheet(exerciseId: model.liftFocus?.exerciseId) }
    }

    /// One bar per week, height by intensity; deloads lime, the current week ringed.
    private func weekBars(_ f: LiftFocus, current: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(current.map { "Block · week \($0) of \(f.weeks)" } ?? "Block · \(f.weeks) weeks").eyebrow()
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(1...f.weeks, id: \.self) { w in
                    let ph = f.phase(week: w)
                    let pct = ph == .test ? 1.0 : (f.doses(week: w).first?.map(\.pct).max() ?? 0.6)
                    let label = ph == .test ? "TEST" : ph == .deload ? "DL" : "\(Int((pct * 100).rounded()))"
                    VStack(spacing: 3) {
                        Text(label).font(Theme.label(9)).foregroundStyle(ph == .deload ? Theme.ink : .white)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 3)
                            .frame(height: 30 + 70 * max(0, (pct - 0.4) / 0.6))
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(ph == .deload ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Self.barColor(pct))))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.white, lineWidth: w == current ? 2 : 0))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 104, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(f.weeks) week block\(current.map { ", now week \($0)" } ?? "")")
        }
        .card()
    }

    static func barColor(_ pct: Double) -> Color {
        switch pct {
        case 0.95...: Color(hex: 0xFF3D5A)
        case 0.9...: Color(hex: 0xFF9F1C)
        case 0.86...: Color(hex: 0xFF3D8B)
        case 0.82...: Color(hex: 0xFF4FD8)
        case 0.78...: Color(hex: 0xB23DFF)
        case 0.74...: Color(hex: 0x8A4FFF)
        default: Color(hex: 0x3D5AFF)
        }
    }
}

/// Set up (or change) a Lift Focus block: lift, target, template, length, weak point, maintenance.
struct LiftFocusSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let exerciseId: String?

    @State private var lift = ""
    @State private var target = 100.0
    @State private var template = FocusTemplate.monkeyPeak
    @State private var weeks = 10
    @State private var weak = WeakPoint.none
    @State private var maintenance = true
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Lift").eyebrow()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(lifts, id: \.id) { e in
                                chip(e.name, on: lift == e.id) {
                                    lift = e.id
                                    resetTarget()
                                }
                            }
                        }
                    }
                    let orm = model.liveOneRepMax(lift)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                            Text(orm.map { "Now \(LoadAdvisor.formatKg($0)) kg e1RM" } ?? "No e1RM yet").font(.caption.weight(.semibold)).opacity(0.88)
                        }
                        Spacer()
                        stepButton("minus") { target = max(2.5, target - 2.5) }
                        Text(LoadAdvisor.formatKg(target)).font(Theme.display(30)).monospacedDigit().frame(minWidth: 76)
                        stepButton("plus") { target += 2.5 }
                    }
                    .gradientCard(gradient(focusColors), padding: 14)
                    .accessibilityIdentifier("focus.target")

                    Text("Template").eyebrow()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(FocusTemplate.allCases) { t in
                            Button {
                                template = t
                                if !t.lengths.contains(weeks) { weeks = t.lengths[t.lengths.count / 2] }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t.label).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(t.blurb).font(.caption2.weight(.semibold)).opacity(0.9).lineLimit(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                                .padding(10)
                                .selectableGradient(gradient(Self.templateColors(t)), selected: template == t, cornerRadius: 18)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(template == t ? .isSelected : [])
                        }
                    }

                    Text("Length · test \(testDate.formatted(.dateTime.weekday(.abbreviated).day().month()))").eyebrow()
                    HStack(spacing: 6) {
                        ForEach(template.lengths, id: \.self) { n in chip("\(n) weeks", on: weeks == n) { weeks = n } }
                    }

                    if !LiftFocus.accessories(for: lift, .bottom).isEmpty {
                        Text("Weak point").eyebrow()
                        HStack(spacing: 6) {
                            ForEach(WeakPoint.allCases) { w in chip(w.label(for: lift), on: weak == w) { weak = w } }
                        }
                        if weak != .none {
                            Text("Adds " + LiftFocus.accessories(for: lift, weak).compactMap(Exercise.find).map(\.name).joined(separator: " and "))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }

                    Toggle(isOn: $maintenance) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rest of plan at maintenance").font(Theme.label(14))
                            Text("Other strength work −30% sets, so the focus lift recovers").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.lime)
                    .card(padding: 14)

                    Button {
                        model.startLiftFocus(exerciseId: lift, targetKg: target, template: template, weeks: weeks,
                                             weakPoint: weak, maintenance: maintenance)
                        dismiss()
                    } label: { Label(model.liftFocus == nil ? "Start Lift Focus" : "Start new block", systemImage: "scope") }
                        .buttonStyle(LimeButtonStyle())
                        .disabled(lift.isEmpty)
                        .accessibilityIdentifier("focus.start")
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Lift Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .onAppear(perform: load)
        }
    }

    /// The lift asked for, the running block's, then the big lifts the gym has, then lifts with logs.
    private var lifts: [Exercise] {
        let equipment = Set(model.profile?.equipment ?? [])
        var ids = [exerciseId, model.liftFocus?.exerciseId].compactMap { $0 }
        ids += LiftFocus.suggested
        var seen = Set<String>()
        return ids.compactMap(Exercise.find).filter { e in
            seen.insert(e.id).inserted && ProSets.eligible(e) && (e.id == exerciseId || e.equipment.allSatisfy(equipment.contains))
        }
    }

    private var testDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let monday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7), to: today) ?? today
        return LiftFocus(exerciseId: lift, targetKg: target, start: monday, weeks: weeks, template: template, startOneRepMax: target).testDate
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let f = model.liftFocus, exerciseId == nil || exerciseId == f.exerciseId {
            lift = f.exerciseId
            target = f.targetKg
            template = f.template
            weeks = f.weeks
            weak = f.weakPoint
            maintenance = f.maintenance
        } else {
            lift = exerciseId ?? lifts.first?.id ?? ""
            resetTarget()
        }
    }

    /// 5% over the current e1RM, rounded to 2.5 kg.
    private func resetTarget() {
        weak = .none
        if let orm = model.liveOneRepMax(lift) { target = LoadAdvisor.round(orm * 1.05, to: 2.5, .up) }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(13)).lineLimit(1)
                .foregroundStyle(on ? Theme.ink : .white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.lime : Theme.cardStrong))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .heavy))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "More kg" : "Less kg")
    }

    static func templateColors(_ t: FocusTemplate) -> [Color] {
        switch t {
        case .monkeyPeak: focusColors
        case .wave531: labColors
        case .gzcl: tealColors
        case .smolovJr: pinkColors
        }
    }
}
