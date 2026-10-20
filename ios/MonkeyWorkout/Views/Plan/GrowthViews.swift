import SwiftUI
import WorkoutEngine

// Growing with the member (#495, A + B + C from `smarter-app/option-{a,b,c}.png`): block review on Train every
// 4 weeks, daily auto-tune from the readiness line, growth path page from Progress and the weekly "Monkey noticed"
// bar on Train.

/// Explore-style gradient row: icon tile left, heavy title and one line, big value right, optional control.
struct SmartRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var value: String?
    var unit: String?
    let colors: [Color]
    var compact = false
    let trailing: Trailing

    init(symbol: String, title: String, detail: String, value: String? = nil, unit: String? = nil, colors: [Color],
         compact: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.value = value
        self.unit = unit
        self.colors = colors
        self.compact = compact
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 17 : 20, weight: .bold))
                .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(compact ? 15 : 17)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if let value {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value).font(Theme.display(compact ? 22 : 28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    if let unit { Text(unit).font(Theme.label(10)).opacity(0.85).lineLimit(1) }
                }
            }
            trailing
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 9 : 13)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

extension SmartRow where Trailing == EmptyView {
    init(symbol: String, title: String, detail: String, value: String? = nil, unit: String? = nil, colors: [Color], compact: Bool = false) {
        self.init(symbol: symbol, title: title, detail: detail, value: value, unit: unit, colors: colors, compact: compact) { EmptyView() }
    }
}

/// The palette of the smart cards, from the Explore categories.
enum SmartColors {
    static let strength = WorkoutEngine.Category.strength.colors
    static let power = WorkoutEngine.Category.power.colors
    static let cardio = WorkoutEngine.Category.cardio.colors
    static let warmup = WorkoutEngine.Category.warmup.colors
    static let mobility = WorkoutEngine.Category.mobility.colors
    static let stretch = WorkoutEngine.Category.stretch.colors
}

/// "+8%", "−3%".
private func percent(_ v: Double) -> String {
    let p = Int((v * 100).rounded())
    return p >= 0 ? "+\(p)%" : "−\(abs(p))%"
}

private func exerciseName(_ id: String) -> String { Exercise.find(id)?.name ?? id }

// MARK: - Block review (A)

/// Train, at the start of a new cycle: what the 4 weeks brought and what the next block changes.
struct BlockReviewCard: View {
    let review: BlockReview
    @Environment(AppModel.self) private var model
    @State private var tweaking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hero
            BlockReviewRows(review: review, compact: true)
        }
        .sheet(isPresented: $tweaking) { BlockReviewSheet(review: review) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("Block \(review.number) done. \(review.levelUp ? "You grew." : "Here's your review.")")
                    .font(Theme.display(22)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { withAnimation { model.closeBlockReview(review) } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .heavy))
                        .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the block review")
            }
            Text("\(Growth.blockWeeks) weeks · \(review.sessionsDone) of \(review.sessionsPlanned) sessions"
                 + (review.easyEffort ? " · effort trending easy" : ""))
                .font(.footnote.weight(.semibold)).opacity(0.9)
            HStack(spacing: 10) {
                Button { withAnimation { model.applyBlockReview(review, levelUp: true, plateaus: Set(review.plateaus.map(\.id)), focus: true) } } label: {
                    Text("Start block \(review.number + 1)").font(Theme.label(15)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .accessibilityHint(review.hasChanges ? "Applies every change below to your plan" : "Starts the next block as planned")
                if review.hasChanges {
                    Button { tweaking = true } label: {
                        Text("Tweak").font(Theme.label(15)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Pick which changes the next block makes")
                }
            }
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: SmartColors.strength, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

/// The review's rows: strength, level, plateaus, deload, focus.
struct BlockReviewRows: View {
    let review: BlockReview
    var compact = false

    var body: some View {
        VStack(spacing: 8) {
            if let gain = review.strengthChange {
                SmartRow(symbol: "dumbbell.fill", title: "Strength",
                         detail: "Est. 1RM, " + review.lifts.prefix(3).map { exerciseName($0.exerciseId) }.joined(separator: ", "),
                         value: percent(gain), unit: "vs block \(max(1, review.number - 1))", colors: SmartColors.power, compact: compact)
            }
            if review.levelUp {
                SmartRow(symbol: "arrow.up.forward.square.fill", title: "Level up",
                         detail: review.experience.map { "Now \($0.rawValue): more sets, harder moves" } ?? "Next block steps up",
                         value: "L\(review.level)", unit: "was L\(review.level - 1)", colors: SmartColors.cardio, compact: compact)
            } else {
                SmartRow(symbol: "stairs", title: "Level \(review.level)",
                         detail: "Do 3 of 4 sessions and get 2% stronger to level up",
                         value: "L\(review.level)", colors: SmartColors.cardio, compact: compact)
            }
            ForEach(review.plateaus) { p in
                SmartRow(symbol: "rectangle.split.3x1.fill", title: "Plateau: \(exerciseName(p.exerciseId))",
                         detail: p.swapTo.map { "\(p.weeks) weeks flat → \(exerciseName($0))" } ?? "\(p.weeks) weeks flat · try new rep ranges",
                         value: "\(p.weeks)", unit: "wks", colors: UndoOffer.warm, compact: compact)
            }
            SmartRow(symbol: "moon.fill", title: "Deload week", detail: "Week \(Growth.blockWeeks) of the next block, then you come back stronger",
                     value: "−40%", unit: "volume", colors: SmartColors.warmup, compact: compact)
            if let g = review.lagging, let vs = review.laggingVs {
                SmartRow(symbol: "scope", title: "Focus next: \(g.label)", detail: "Behind \(vs.label.lowercased()) · one more set on its moves",
                         value: "+1", unit: "set", colors: SmartColors.mobility, compact: compact)
            }
        }
    }
}

/// Tweak: pick which changes the next block makes.
struct BlockReviewSheet: View {
    let review: BlockReview
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var levelUp = true
    @State private var plateaus: Set<String> = []
    @State private var focus = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next block").eyebrow()
                    if review.experience != nil {
                        SmartRow(symbol: "arrow.up.forward.square.fill", title: "Level up",
                                 detail: "Plan for \(review.experience?.rawValue ?? "")", value: nil, colors: SmartColors.cardio) {
                            Toggle("Level up", isOn: $levelUp).labelsHidden().tint(Theme.lime)
                        }
                    }
                    ForEach(review.plateaus.filter { $0.swapTo != nil }) { p in
                        SmartRow(symbol: "arrow.triangle.swap", title: "Swap \(exerciseName(p.exerciseId))",
                                 detail: "For \(exerciseName(p.swapTo ?? "")) on its days", colors: UndoOffer.warm) {
                            Toggle("Swap", isOn: Binding(get: { plateaus.contains(p.id) },
                                                         set: { on in if on { plateaus.insert(p.id) } else { plateaus.remove(p.id) } }))
                                .labelsHidden().tint(Theme.lime)
                        }
                    }
                    if let g = review.lagging {
                        SmartRow(symbol: "scope", title: "Focus: \(g.label)", detail: "One more set on its moves", colors: SmartColors.mobility) {
                            Toggle("Focus", isOn: $focus).labelsHidden().tint(Theme.lime)
                        }
                    }
                    Text("You can change any of this later in Training profile.")
                        .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.applyBlockReview(review, levelUp: levelUp, plateaus: plateaus, focus: focus)
                    dismiss()
                } label: {
                    Text("Start block \(review.number + 1)").font(Theme.label(16)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .padding(16)
                .background(Theme.bg)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Tweak block \(review.number + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .onAppear { plateaus = Set(review.plateaus.filter { $0.swapTo != nil }.map(\.id)) }
    }
}

// MARK: - Daily auto-tune (B)

extension TuneLevel {
    var colors: [Color] {
        switch self {
        case .light: [.orange, Color(red: 0.95, green: 0.25, blue: 0.3)]
        case .medium: UndoOffer.warm
        case .push: [Theme.lime, Color(red: 0.2, green: 0.85, blue: 0.5)]
        }
    }

    var symbol: String {
        switch self {
        case .light: "tortoise.fill"
        case .medium: "figure.strengthtraining.traditional"
        case .push: "bolt.fill"
        }
    }
}

extension TuneChange {
    var title: String {
        switch kind {
        case .swap: "\(exerciseName(exerciseId)) → \(to.map(exerciseName) ?? "")"
        case .dropSet, .addSet: "\(exerciseName(exerciseId)) \(fromSets ?? 0) → \(toSets ?? 0) sets"
        case .easier: "\(exerciseName(exerciseId)) 1 RPE lower"
        }
    }

    var detail: String {
        switch kind {
        case .swap: "Spares your sore muscles"
        case .dropSet: "Same load, one set less"
        case .addSet: "You're fresh: one more"
        case .easier: "Same sets, lighter effort"
        }
    }

    var symbol: String {
        switch kind {
        case .swap: "arrow.triangle.swap"
        case .dropSet: "scissors"
        case .addSet: "plus.square.fill"
        case .easier: "gauge.with.dots.needle.33percent"
        }
    }
}

/// Today's ready score, the level (Monkey's pick or the member's), sore muscles and what changed, each with Undo.
struct AutoTuneSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var explaining = false

    var body: some View {
        let verdict = model.tuneVerdict
        let level = model.tuneLevel
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    hero(verdict, level: level)
                    Text("Sore today").eyebrow()
                    soreGrid
                    Text("Monkey changed today").eyebrow()
                    changes
                    if !verdict.factors.isEmpty {
                        Text("Your score").eyebrow()
                        ForEach(verdict.factors) { f in
                            SmartRow(symbol: symbol(f.id), title: f.title, detail: f.detail,
                                     value: f.points > 0 ? "+\(f.points)" : f.points < 0 ? "−\(abs(f.points))" : "0",
                                     unit: "points", colors: f.points < 0 ? UndoOffer.warm : SmartColors.cardio, compact: true)
                        }
                    }
                    SmartRow(symbol: "wand.and.stars", title: "Auto-tune every day",
                             detail: "Fits today's workout to your recovery and sore muscles", colors: SmartColors.strength, compact: true) {
                        Toggle("Auto-tune every day", isOn: Binding(get: { model.tuneOn }, set: { model.setTuneOn($0) }))
                            .labelsHidden().tint(Theme.lime)
                    }
                    if let r = Readiness.assess(health.snapshot) {
                        Button("How readiness works ›") { explaining = true }
                            .font(Theme.label(14)).foregroundStyle(Theme.lime)
                            .sheet(isPresented: $explaining) {
                                ReadinessSheet(snapshot: health.snapshot, readiness: r.0, flags: r.1).presentationDetents([.large])
                            }
                    } else if !health.connected {
                        Text("Connect Apple Health in Settings for sleep, HRV and resting heart rate in your score.")
                            .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Today's tune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private func hero(_ v: TuneVerdict, level: TuneLevel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready score \(v.score) · go \(level.title.lowercased())").font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.7)
            Text(model.dayTune.level == nil ? v.reason : "Your pick · Monkey says \(v.level.title.lowercased())")
                .font(.footnote.weight(.semibold)).opacity(0.9)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(Theme.lime).frame(width: g.size.width * CGFloat(v.score) / 100)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                ForEach(TuneLevel.allCases) { l in
                    let on = l == level
                    Button { withAnimation(.snappy) { model.setTuneLevel(l == v.level ? nil : l) } } label: {
                        Label(l.title, systemImage: l.symbol).font(Theme.label(14))
                            .foregroundStyle(on ? Theme.ink : .white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(on ? 1 : 0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint(l.rule)
                }
            }
            .sensoryFeedback(.selection, trigger: level)
            Text(level.rule).font(.caption.weight(.bold)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: level.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var soreGrid: some View {
        let sore = Set(model.dayTune.sore)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(MuscleGroup.allCases) { g in
                let on = sore.contains(g)
                Button { withAnimation(.snappy) { model.toggleSore(g) } } label: {
                    Text(g.label).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(.white.opacity(on ? 1 : 0.75))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(on ? AnyShapeStyle(LinearGradient(colors: SmartColors.power, startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Theme.card)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Color.clear : Theme.stroke))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var changes: some View {
        let list = model.tuneChanges
        if list.isEmpty {
            SmartRow(symbol: "checkmark", title: "As planned", detail: model.tuneOn ? "Nothing to change in today's workout" : "Auto-tune is off",
                     colors: SmartColors.stretch, compact: true)
        }
        ForEach(list) { c in
            SmartRow(symbol: c.symbol, title: c.title, detail: c.detail, colors: SmartColors.mobility, compact: true) {
                Button("Undo") { withAnimation { model.undoTune(c) } }
                    .font(Theme.label(12)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.3)))
                    .buttonStyle(.plain)
            }
        }
        if !model.dayTune.undone.isEmpty {
            Button("Put back \(model.dayTune.undone.count) undone") { withAnimation { model.redoTunes() } }
                .font(Theme.label(14)).foregroundStyle(Theme.lime)
        }
    }

    private func symbol(_ id: String) -> String {
        switch id {
        case "hrv": "waveform.path.ecg"
        case "rhr": "heart.fill"
        case "sleep": "bed.double.fill"
        case "effort": "flame.fill"
        case "streak": "calendar"
        default: "figure.cooldown"
        }
    }
}

// MARK: - What Monkey noticed (C)

extension Insight {
    var symbol: String {
        switch kind {
        case .longRests: "timer"
        case .skippedDay: "calendar.badge.exclamationmark"
        case .goalHit: "trophy.fill"
        case .untrained: "figure.strengthtraining.functional"
        case .bests: "star.fill"
        }
    }

    var colors: [Color] {
        switch kind {
        case .longRests: SmartColors.power
        case .skippedDay: SmartColors.cardio
        case .goalHit: SmartColors.strength
        case .untrained: SmartColors.mobility
        case .bests: SmartColors.warmup
        }
    }

    /// The one-tap fix, when there is one.
    var actionTitle: String? {
        switch kind {
        case .goalHit: "Set next goal"
        case .skippedDay: toWeekday.map { "Move to " + ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][$0 - 1] }
        case .untrained: "Make it a focus"
        case .longRests, .bests: nil
        }
    }
}

/// One notice with its fix.
struct InsightRow: View {
    let insight: Insight
    @Environment(AppModel.self) private var model
    @State private var done = false

    var body: some View {
        SmartRow(symbol: insight.symbol, title: insight.title, detail: insight.detail, value: done ? nil : insight.value,
                 colors: insight.colors) {
            if let action = insight.actionTitle {
                Button {
                    withAnimation { model.act(on: insight); done = true }
                } label: {
                    Text(done ? "Done" : action).font(Theme.label(12)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .disabled(done)
            }
        }
    }
}

/// Train, once a week: one slim bar, tap for the growth path.
struct NoticedBar: View {
    let insights: [Insight]
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        HStack(spacing: 10) {
            Button { open = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 15, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(insights.count == 1 ? "Monkey noticed 1 thing" : "Monkey noticed \(insights.count) things")
                            .font(Theme.label(14))
                        Text(insights.map(\.title).joined(separator: " · ")).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your growth path")
            Button { withAnimation { model.closeNoticed() } } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
                    .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide until next week")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: SmartColors.mobility, startPoint: .leading, endPoint: .trailing)))
        .sheet(isPresented: $open) {
            NavigationStack {
                GrowthPathView().toolbar { CloseToolbarItem { open = false } }
            }
        }
    }
}

// MARK: - Growth path (C)

private let dayMonth: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("d MMM")
    return f
}()

private let monthOnly: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("MMM")
    return f
}()

/// Goal with its predicted date and milestones, what Monkey noticed, growth level, auto-tune and the coach's memory.
struct GrowthPathView: View {
    @Environment(AppModel.self) private var model
    @State private var editingGoal = false
    @State private var tuning = false

    var body: some View {
        let goal = model.growthGoal
        let status = model.goalStatus
        let notices = model.noticed
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                goalHero(goal, status)
                if let status { road(status) }
                Text("What Monkey noticed this week").eyebrow()
                if notices.isEmpty {
                    SmartRow(symbol: "checkmark", title: "All on track", detail: "Nothing new this week. Keep it up!", colors: SmartColors.stretch, compact: true)
                }
                ForEach(notices) { InsightRow(insight: $0) }
                Text("Monkey grows with you").eyebrow()
                SmartRow(symbol: "stairs", title: "Growth level", detail: "Block review every \(Growth.blockWeeks) weeks levels your plan up",
                         value: "L\(model.growthLevel)", colors: SmartColors.cardio)
                Button { tuning = true } label: {
                    SmartRow(symbol: "wand.and.stars", title: "Daily auto-tune",
                             detail: model.tuneOn ? "Today: \(model.tuneLevel.title) · \(model.tuneChanges.count) changes" : "Off",
                             value: model.tuneOn ? "\(model.tuneVerdict.score)" : nil, unit: "ready", colors: SmartColors.power)
                }
                .buttonStyle(.plain)
                NavigationLink { CoachMemoryView() } label: {
                    SmartRow(symbol: "brain.head.profile", title: "Coach remembers", detail: "Goals, likes, notes · used in Ask Coach",
                             value: "\(model.coachFacts.count)", unit: "facts", colors: SmartColors.warmup)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Growth path")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingGoal) { GoalEditSheet() }
        .sheet(isPresented: $tuning) { AutoTuneSheet() }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func goalHero(_ goal: GrowthGoal?, _ status: GoalStatus?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("Your goal").font(Theme.label(12)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                Spacer()
                Button(goal == nil ? "Pick" : "Edit") { editingGoal = true }
                    .font(Theme.label(13)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.25)))
                    .buttonStyle(.plain)
            }
            if let goal, let status {
                Text("\(exerciseName(goal.exerciseId)) · \(GoalFormat.kg(goal.targetKg))").font(Theme.display(24))
                    .lineLimit(2).minimumScaleFactor(0.7)
                if status.reached {
                    Text("Reached! Next: \(GoalFormat.kg(goal.nextTargetKg))").font(.footnote.weight(.semibold)).opacity(0.9)
                    Button { withAnimation { model.nextGoal() } } label: {
                        Text("Set next goal").font(Theme.label(15)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Now \(status.currentKg.map(GoalFormat.kg) ?? "–") est. 1RM · " + (status.predicted == nil ? "keep logging for a date" : "on pace for"))
                        .font(.footnote.weight(.semibold)).opacity(0.9)
                    if let d = status.predicted {
                        Text(dayMonth.string(from: d)).font(Theme.display(44)).monospacedDigit()
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(Theme.lime).frame(width: g.size.width * CGFloat(status.progress))
                    }
                }
                .frame(height: 10)
                .accessibilityLabel("\(Int(status.progress * 100)) % of the way")
            } else {
                Text("Pick a lift to grow").font(Theme.display(24))
                Text("Log a main lift for 3 weeks and Monkey suggests a goal with a date.")
                    .font(.footnote.weight(.semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: SmartColors.mobility, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func road(_ s: GoalStatus) -> some View {
        let next = s.milestones.first { $0.reachedAt == nil && !$0.beyond }?.kg
        return HStack(spacing: 8) {
            ForEach(s.milestones) { m in
                let reached = m.reachedAt != nil
                let isNext = m.kg == next
                VStack(spacing: 2) {
                    Text(reached ? "✓" : isNext ? "NEXT" : m.beyond ? "THEN" : "").font(Theme.label(11))
                    Text(GoalFormat.kg(m.kg)).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.6)
                    Text((m.reachedAt ?? m.predicted).map { monthOnly.string(from: $0) } ?? "–").font(Theme.label(11)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                    reached ? AnyShapeStyle(LinearGradient(colors: SmartColors.stretch, startPoint: .topLeading, endPoint: .bottomTrailing))
                    : isNext ? AnyShapeStyle(LinearGradient(colors: SmartColors.power, startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Theme.card)))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Pick the lift and the target of the long-term goal.
struct GoalEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exerciseId = ""
    @State private var target = 80.0

    private var lifts: [String] {
        let logged = Set(model.state.history.flatMap(\.exercises).filter { $0.estimatedOneRepMax != nil }.map(\.exerciseId))
            .filter { Exercise.find($0)?.main == true }
        let base = ["back-squat", "bench-press", "deadlift", "ohp", "barbell-row"]
        return Array(logged).sorted() + base.filter { !logged.contains($0) }
    }

    private var current: Double? {
        Progression.oneRepMaxTrend(exerciseId, records: model.state.history, calendar: model.planCalendar).last?.1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lift").eyebrow()
                    ForEach(lifts, id: \.self) { id in
                        let on = id == exerciseId
                        Button { exerciseId = id; suggestTarget() } label: {
                            HStack {
                                Text(exerciseName(id)).font(Theme.label(15))
                                Spacer()
                                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)) }
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(on ? AnyShapeStyle(LinearGradient(colors: SmartColors.mobility, startPoint: .leading, endPoint: .trailing))
                                      : AnyShapeStyle(Theme.card)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Text("Target est. 1RM").eyebrow()
                    SmartRow(symbol: "target", title: GoalFormat.kg(target),
                             detail: current.map { "Now \(GoalFormat.kg($0))" } ?? "No logs yet for this lift", colors: SmartColors.power) {
                        Stepper("Target", value: $target, in: 10...400, step: 2.5).labelsHidden()
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.setGoal(exerciseId: exerciseId, targetKg: target)
                    dismiss()
                } label: {
                    Text("Save goal").font(Theme.label(16)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .disabled(exerciseId.isEmpty)
                .padding(16)
                .background(Theme.bg)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Your goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let g = model.growthGoal {
                exerciseId = g.exerciseId
                target = g.targetKg
            } else if let first = lifts.first {
                exerciseId = first
                suggestTarget()
            }
        }
    }

    private func suggestTarget() {
        target = current.map { max(20, (($0 * 1.1) / 5).rounded(.up) * 5) } ?? 60
    }
}

/// What the coach remembers: what the app knows, then the member's own notes (add, remove).
struct CoachMemoryView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        let notes = model.growth.notes ?? []
        let known = Array(model.coachFacts.dropLast(notes.count))
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sent with your Ask Coach questions so answers fit you. Your notes sync with your profile.")
                    .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                Text("Monkey knows").eyebrow()
                ForEach(known, id: \.self) { f in
                    SmartRow(symbol: "lightbulb.fill", title: f, detail: "From your profile and workouts", colors: SmartColors.strength, compact: true)
                }
                Text("Your notes").eyebrow()
                ForEach(notes, id: \.self) { n in
                    SmartRow(symbol: "note.text", title: n, detail: "You told the coach", colors: SmartColors.warmup, compact: true) {
                        Button { withAnimation { model.removeCoachNote(n) } } label: {
                            Image(systemName: "trash.fill").font(.system(size: 13, weight: .bold))
                                .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Forget: \(n)")
                    }
                }
                HStack(spacing: 8) {
                    TextField("e.g. Left knee: no deep lunges", text: $draft)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .font(Theme.label(15)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                        .buttonStyle(.plain)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Coach remembers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        model.addCoachNote(draft)
        draft = ""
    }
}

/// Progress widget: the goal, its date and what Monkey noticed; opens the growth path.
struct GrowthWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let goal = model.growthGoal
        let status = model.goalStatus
        let n = model.noticed.count
        NavigationLink { GrowthPathView() } label: {
            SmartRow(symbol: "chart.line.uptrend.xyaxis",
                     title: goal.map { "\(exerciseName($0.exerciseId)) · \(GoalFormat.kg($0.targetKg))" } ?? "Growth path",
                     detail: [status?.predicted.map { "On pace for \(dayMonth.string(from: $0))" } ?? (goal == nil ? "Pick a goal" : nil),
                              n > 0 ? "\(n) noticed" : nil, "Level \(model.growthLevel)"].compactMap { $0 }.joined(separator: " · "),
                     value: status.map { "\(Int($0.progress * 100))%" }, colors: SmartColors.mobility)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your growth path")
    }
}
