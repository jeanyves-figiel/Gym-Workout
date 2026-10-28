import APIClient
import SwiftUI
import WorkoutEngine

/// Set up the plan by talking to Coach (#873, design B from `ai-epic/a3.png`): the member says what they want once,
/// typed or spoken; Coach fills the plan tiles (goal, days, length, protect), each tap opens a quick fix, then
/// BUILD MY PLAN makes the plan on the profile the guided steps set up (gym, machines, map stay); Protect turns on
/// train around pain (#870) for that spot.
struct CoachPlanSetupView: View {
    let base: Profile
    /// The plan's profile and the spot to protect (pain mode, #870).
    let onBuild: (Profile, PainProtect?) -> Void
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var said = ""
    @State private var draft: CoachPlanDraft?
    @State private var asking = false
    @State private var problem: String?
    @State private var fixing: CoachPlanTile?
    @State private var listener = CoachListener()
    @FocusState private var typing: Bool

    init(base: Profile, onBuild: @escaping (Profile, PainProtect?) -> Void) {
        self.base = base
        self.onBuild = onBuild
        #if DEBUG
        if Demo.screen == "coach-plan" {
            _said = State(initialValue: Self.demoText)
            _draft = State(initialValue: Self.demoDraft)
        }
        #endif
    }

    static let demoText = "Lose weight and build muscle, 4 days, 1 hour max, bad knee"
    static let demoDraft = CoachPlanDraft(goal: "build", experience: "beginner", sessions: 4, weekdays: [1, 2, 4, 6], minutes: 60,
                                          protect: .init(area: "knee", side: "right", level: "loaded"), summary: "Muscle and fat loss, 4 days of an hour, sparing your knee.")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Say it once, your own words. Coach fills in your plan, you fix anything before it's built.")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                mic
                input
                if !said.isEmpty {
                    Text("“\(said)”")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if asking { ProgressView("Coach is filling in your plan…").tint(Theme.lime).foregroundStyle(Theme.muted) }
                if let problem { Text(problem).font(.footnote.weight(.semibold)).foregroundStyle(.orange) }
                if let draft { filled(draft) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Tell Coach your goal")
        .safeAreaInset(edge: .bottom) {
            Button { build() } label: { Text("BUILD MY PLAN") }
                .buttonStyle(LimeButtonStyle())
                .disabled(draft == nil || asking)
                .opacity(draft == nil ? 0.4 : 1)
                .accessibilityIdentifier("coachPlan.build")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .readableColumn()
                .background(Theme.bg.opacity(0.92).ignoresSafeArea())
        }
        .sheet(item: $fixing) { tile in
            CoachPlanFixSheet(tile: tile, draft: Binding(get: { draft ?? Self.demoDraft }, set: { draft = $0 }))
        }
        .onDisappear { listener.cancel() }
    }

    // MARK: Input

    private var mic: some View {
        Button { listener.listening ? listener.finish() : listen() } label: {
            Image(systemName: listener.listening ? "stop.fill" : "mic.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 96, height: 96)
                .background(Circle().fill(Theme.lime))
                .overlay(Circle().stroke(Theme.lime.opacity(listener.listening ? 0.5 : 0), lineWidth: 10).scaleEffect(1.15))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(listener.listening ? "Stop and send" : "Talk to Coach")
        .accessibilityIdentifier("coachPlan.mic")
        .overlay(alignment: .bottom) {
            if listener.listening {
                Text(listener.text.isEmpty ? "Listening…" : listener.text)
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(2)
                    .offset(y: 28)
            }
        }
        .padding(.bottom, listener.listening ? 24 : 0)
    }

    private var input: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("e.g. Lose weight and build muscle, 4 days, bad knee", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { send(text) }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .accessibilityIdentifier("coachPlan.text")
            Button { send(text) } label: {
                Image(systemName: "arrow.up").font(.system(size: 15, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.lime))
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).count < 3 || asking)
            .accessibilityLabel("Send to Coach")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
    }

    // MARK: Tiles

    private func filled(_ d: CoachPlanDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach filled in · tap to fix").eyebrow()
            if !d.summary.isEmpty {
                Text(d.summary).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(CoachPlanTile.allCases) { t in
                    Button { fixing = t } label: { tile(t, d) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coachPlan.tile.\(t.rawValue)")
                }
            }
        }
    }

    private func tile(_ t: CoachPlanTile, _ d: CoachPlanDraft) -> some View {
        let (line, big, symbol) = t.content(d)
        return VStack(alignment: .leading, spacing: 4) {
            Text(t.title).font(Theme.display(18))
            Text(line).font(.caption.weight(.bold)).opacity(0.88).lineLimit(2)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                if let big {
                    Text(big).font(Theme.display(34)).monospacedDigit()
                } else {
                    Image(systemName: symbol).font(.system(size: 26, weight: .bold))
                }
            }
        }
        .foregroundStyle(t.category.ink)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(t == .goal ? d.goalValue.gradient : t.category.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Change it")
    }

    // MARK: Actions

    private func listen() {
        typing = false
        listener.start { words in send(words) }
    }

    private func send(_ words: String) {
        let t = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 3, !asking else { return }
        typing = false
        said = String(t.prefix(500))
        text = ""
        problem = nil
        asking = true
        Task {
            defer { asking = false }
            if model.demo {
                draft = Self.demoDraft
                return
            }
            do {
                draft = try await model.api.coachPlan(said, as: CoachPlanDraft.self)
            } catch let APIError.server(_, _, message) {
                problem = message
            } catch {
                problem = "Coach couldn't answer just now. Try again, or go back and pick on the form."
            }
        }
    }

    private func build() {
        guard let draft else { return }
        onBuild(draft.applied(to: base), draft.pain())
    }
}

/// One tile of Coach's draft (#873), with its quick fix.
enum CoachPlanTile: String, CaseIterable, Identifiable {
    case goal, days, length, protect
    var id: String { rawValue }

    var title: String {
        switch self {
        case .goal: "Goal"
        case .days: "Days"
        case .length: "Length"
        case .protect: "Protect"
        }
    }

    var category: WorkoutEngine.Category {
        switch self {
        case .goal: .warmup
        case .days: .strength
        case .length: .cardio
        case .protect: .power
        }
    }

    /// Line, big number (or nil for the symbol) and symbol.
    func content(_ d: CoachPlanDraft) -> (String, String?, String) {
        switch self {
        case .goal:
            return ("\(d.goalValue.config.label) · \(d.experienceValue.rawValue)", nil, d.goalValue.symbol)
        case .days:
            let line = d.days.isEmpty ? "any days" : d.days.map { WeekSchedule.shortName($0) }.joined(separator: " ")
            return (line, "\(d.sessionCount)", "calendar")
        case .length:
            return (d.length.map { _ in "minutes a session" } ?? "auto, fits the goal", d.length.map { "\($0)′" }, "timer")
        case .protect:
            let pain = d.pain()
            return (pain.map { "\($0.spot) · \($0.level.label.lowercased())" } ?? "nothing to spare", nil,
                    pain == nil ? "checkmark.shield.fill" : "shield.lefthalf.filled")
        }
    }
}

/// Quick fix for one tile (#873): the same choices as the plan form.
struct CoachPlanFixSheet: View {
    let tile: CoachPlanTile
    @Binding var draft: CoachPlanDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(tile.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var content: some View {
        switch tile {
        case .goal:
            Text("Goal").eyebrow()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Goal.allCases) { g in
                    FixChip(title: g.config.label, selected: draft.goalValue == g) { draft.goal = g.rawValue }
                }
            }
            Text("Experience").eyebrow()
            HStack(spacing: 8) {
                ForEach(Experience.allCases) { e in
                    FixChip(title: e.rawValue.capitalized, selected: draft.experienceValue == e) { draft.experience = e.rawValue }
                }
            }
        case .days:
            Text("Gym days a week").eyebrow()
            HStack(spacing: 8) {
                ForEach(2...6, id: \.self) { n in
                    FixChip(title: "\(n)", selected: draft.sessionCount == n) {
                        draft.sessions = n
                        draft.weekdays = Array(draft.days.prefix(n))
                    }
                }
            }
            Text("Which days · optional").eyebrow()
            DayTiles(days: Binding(get: { draft.days }, set: { draft.weekdays = Array($0.prefix(draft.sessionCount)) }),
                     symbol: "dumbbell.fill", fill: AnyShapeStyle(WorkoutEngine.Category.strength.gradient), ink: .white)
        case .length:
            Text("Session length").eyebrow()
            HStack(spacing: 8) {
                FixChip(title: "Auto", selected: draft.length == nil) { draft.minutes = nil }
                ForEach(CoachPlanDraft.lengths, id: \.self) { m in
                    FixChip(title: "\(m)′", selected: draft.length == m) { draft.minutes = m }
                }
            }
        case .protect:
            Text("Where it hurts").eyebrow()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                FixChip(title: "Nothing", selected: draft.pain() == nil) { draft.protect = nil }
                ForEach(PainArea.allCases) { a in
                    FixChip(title: a.label.capitalized, selected: draft.protect?.area == a.rawValue) {
                        draft.protect = .init(area: a.rawValue, side: draft.protect?.side ?? "both", level: draft.protect?.level ?? PainLevel.mild.rawValue)
                    }
                }
            }
            if let pain = draft.pain() {
                if pain.area.sided {
                    Text("Side").eyebrow()
                    HStack(spacing: 8) {
                        ForEach(PainSide.allCases, id: \.self) { side in
                            FixChip(title: side.rawValue.capitalized, selected: pain.side == side) { draft.protect?.side = side.rawValue }
                        }
                    }
                }
                Text("How bad").eyebrow()
                HStack(spacing: 8) {
                    ForEach(PainLevel.allCases) { l in
                        FixChip(title: l.label, selected: pain.level == l) { draft.protect?.level = l.rawValue }
                    }
                }
            }
            Text("Your plan swaps the moves that load it until you tap Feels better on Train. \(PainProtect.notAdvice)")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }
}

private struct FixChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(selected ? Theme.ink : .white)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Not sure? Ask Coach

/// "Not sure? Ask Coach" on a plan form step (#873, design C): Coach explains the options from the answers so far and
/// offers its pick, used with one tap. The form stays the way to choose.
struct AskCoachFormHelp: View {
    let step: String
    let options: [CoachPlanHelpAsk.Option]
    let profile: Profile
    let onUse: (String) -> Void
    @Environment(AppModel.self) private var model
    @State private var answer: CoachPlanHelp?
    @State private var asking = false
    @State private var problem: String?
    @State private var used = false

    private var ask: CoachPlanHelpAsk { CoachPlanHelpAsk(step: step, options: options, so: CoachPlanHelpAsk.soFar(profile)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🐵 Not sure? Ask Coach").font(.system(size: 14, weight: .heavy, design: .rounded))
                Spacer()
                if asking {
                    ProgressView().tint(Theme.lime)
                } else if answer == nil {
                    pill("Ask") { load() }
                        .accessibilityIdentifier("coachHelp.ask.\(step)")
                }
            }
            if let answer {
                Text(answer.answer).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                if let pick = answer.pick(in: ask) {
                    HStack {
                        Text(used ? "Using Coach's pick: \(pick.label)" : "Use Coach's pick: \(pick.label)")
                            .font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(2)
                        Spacer()
                        if !used {
                            pill("Use") {
                                onUse(pick.id)
                                used = true
                            }
                            .accessibilityIdentifier("coachHelp.use.\(step)")
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.lime)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardStrong))
                }
            }
            if let problem { Text(problem).font(.footnote.weight(.semibold)).foregroundStyle(.orange) }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        #if DEBUG
        .onAppear { if Demo.screen == "coach-help", step == "Goal", answer == nil { load() } }
        #endif
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(13)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
    }

    private func load() {
        problem = nil
        asking = true
        let ask = ask
        Task {
            defer { asking = false }
            if model.demo {
                answer = CoachPlanHelp(answer: "For your goal I'd start here: it fits your days and you can change it any time.",
                                       pick: ask.options.first?.id)
                return
            }
            do {
                answer = try await model.api.coachPlanHelp(ask, as: CoachPlanHelp.self)
            } catch let APIError.server(_, _, message) {
                problem = message
            } catch {
                problem = "Coach couldn't answer just now. Try again in a moment."
            }
        }
    }
}
