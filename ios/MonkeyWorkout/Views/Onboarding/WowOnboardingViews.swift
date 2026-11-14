import SwiftUI
import WorkoutEngine

// Wow onboarding (#1084, mix A + B + C from `wow-onboarding/{a,b,c}.png`):
// A Coach Monkey chat (one question at a time, big gradient answers, Coach reacts),
// B "Building your plan…" ring and ticking checklist after the gym steps,
// C plan reveal: the week's workouts pop in one by one, then Train / Fuel / Mind / Insights tiles.

// MARK: - A · Coach chat

struct CoachIntroChat: View {
    @Binding var answers: CoachIntroAnswers
    let onDone: () -> Void
    /// Coach "typing" between an answer and its reaction.
    @State private var typing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🐵").font(.system(size: 52)).padding(.top, 4)
                        ForEach(answers.answered) { q in
                            coachBubble(CoachIntro.question(q))
                            meBubble(answerText(q))
                            if !(typing && q == answers.answered.last) {
                                coachBubble(CoachIntro.reaction(q, answers))
                            }
                        }
                        if typing {
                            coachBubble("• • •").accessibilityLabel("Coach is typing")
                        } else if let q = answers.next {
                            coachBubble(CoachIntro.question(q))
                        } else {
                            coachBubble(CoachIntro.gymPrompt)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .readableWidth()
                .onChange(of: answers.answered.count) { scrollEnd(proxy) }
                .onChange(of: typing) { scrollEnd(proxy) }
            }
            choices
        }
        .background(Theme.bg.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: answers.answered.count)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scrollEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) { proxy.scrollTo("end", anchor: .bottom) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !answers.answered.isEmpty {
                Button { withAnimation(.snappy) { typing = false; answers.undoLast() } } label: {
                    Text("‹ Back").font(Theme.label(15)).foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.chat.back")
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(Theme.lime).frame(width: max(8, g.size.width * answers.fraction))
                }
            }
            .frame(height: 6)
            .animation(.snappy, value: answers.fraction)
            if answers.next != nil {
                Button("Skip") { skipAll() }
                    .font(Theme.label(15)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("onboarding.chat.skip")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Bubbles

    private func coachBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 5, bottomTrailingRadius: 18,
                                               topTrailingRadius: 18, style: .continuous).fill(Color.white.opacity(0.09)))
            .frame(maxWidth: 320, alignment: .leading)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func meBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 5,
                                               topTrailingRadius: 18, style: .continuous).fill(Theme.lime))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func answerText(_ q: CoachIntroQuestion) -> String {
        switch q {
        case .goal: answers.goal?.config.label ?? "Skip"
        case .days: answers.days.map { "\($0) days" } ?? "Skip"
        case .minutes: answers.minutes.map { "\($0) min" } ?? "You pick"
        case .experience: answers.experience.map(Self.experienceTitle) ?? "Skip"
        case .level: answers.level?.title ?? "Skip"
        case .diet: answers.diet.map { "\($0.emoji) \($0.label)" } ?? "Skip for now"
        }
    }

    static func experienceTitle(_ e: Experience) -> String {
        switch e {
        case .beginner: "New to it"
        case .intermediate: "A year or two"
        case .advanced: "Years"
        }
    }

    // MARK: Answers

    @ViewBuilder private var choices: some View {
        VStack(spacing: 8) {
            if typing {
                EmptyView()
            } else if let q = answers.next {
                switch q {
                case .goal:
                    ForEach(Goal.allCases) { g in
                        card(symbol: g.symbol, title: g.config.label, number: nil, gradient: g.gradient,
                             ink: g == .build || g == .athletic ? Theme.ink : .white, id: "goal.\(g.rawValue)") {
                            pick(.goal) { $0.goal = g }
                        }
                    }
                case .days:
                    daysGrid
                case .minutes:
                    ForEach(Array(CoachIntro.minuteChoices.enumerated()), id: \.offset) { i, m in
                        card(symbol: m == nil ? "sparkles" : "timer", title: m.map(Self.minutesTitle) ?? "Coach picks",
                             number: m.map { "\($0)′" }, gradient: Self.cycle[i % Self.cycle.count].gradient,
                             ink: Self.cycle[i % Self.cycle.count].ink,
                             id: "minutes.\(m ?? 0)") {
                            pick(.minutes) { $0.minutes = m }
                        }
                    }
                case .experience:
                    ForEach(Array(Experience.allCases.enumerated()), id: \.element) { i, e in
                        card(symbol: ["leaf.fill", "flame.fill", "bolt.fill"][i % 3], title: Self.experienceTitle(e),
                             number: String(repeating: "★", count: e.level),
                             gradient: [WorkoutEngine.Category.cardio, .warmup, .power][i % 3].gradient,
                             ink: [WorkoutEngine.Category.cardio, .warmup, .power][i % 3].ink, id: "experience.\(e.rawValue)") {
                            pick(.experience) { $0.experience = e }
                        }
                    }
                case .level:
                    ForEach(AppLevel.allCases) { l in
                        card(symbol: l.symbol, title: l.title, number: nil, gradient: l.category.gradient, ink: l.category.ink, id: "level.\(l.rawValue)") {
                            pick(.level) { $0.level = l }
                        }
                    }
                case .diet:
                    dietGrid
                }
            } else {
                Button { onDone() } label: { Text("FIND MY GYM") }
                    .buttonStyle(LimeButtonStyle())
                    .accessibilityIdentifier("onboarding.chat.done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .readableColumn()
        .background(Theme.bg.opacity(0.94).ignoresSafeArea())
        .animation(.snappy, value: answers.next)
        .animation(.snappy, value: typing)
    }

    private static let cycle: [WorkoutEngine.Category] = [.cardio, .warmup, .power, .strength, .mobility]

    private static func minutesTitle(_ m: Int) -> String {
        switch m {
        case ...30: "Quick"
        case ...45: "Solid"
        case ...60: "Full"
        default: "Beast"
        }
    }

    private var daysGrid: some View {
        let recommended = (answers.goal ?? .balanced).recommendedSessions
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            ForEach(Array(CoachIntro.dayChoices.enumerated()), id: \.element) { i, d in
                Button { pick(.days) { $0.days = d } } label: {
                    VStack(spacing: 2) {
                        Text("\(d)").font(Theme.display(34)).monospacedDigit()
                        Text(d == recommended ? "★ BEST" : "DAYS").font(Theme.label(9)).tracking(1)
                    }
                    .foregroundStyle(Self.cycle[i % Self.cycle.count].ink)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.cycle[i % Self.cycle.count].gradient))
                    .overlay {
                        if d == recommended { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.lime, lineWidth: 3) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(d) days a week\(d == recommended ? ", recommended" : "")")
                .accessibilityIdentifier("onboarding.chat.days.\(d)")
            }
        }
    }

    private var dietGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(FuelDiet.allCases.enumerated()), id: \.element) { i, d in
                Button { pick(.diet) { $0.diet = d } } label: {
                    HStack(spacing: 8) {
                        Text(d.emoji).font(.system(size: 22))
                        Text(d.label).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Self.cycle[i % Self.cycle.count].ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.cycle[i % Self.cycle.count].gradient))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.chat.diet.\(d.rawValue)")
            }
            Button { pick(.diet) { $0.diet = nil } } label: {
                Text("Skip for now").font(Theme.display(16)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.chat.diet.skip")
        }
    }

    /// Explore-style answer card: icon tile left, heavy title, big number right.
    private func card(symbol: String, title: String, number: String?, gradient: LinearGradient, ink: Color, id: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                Text(title).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if let number { Text(number).font(Theme.display(24)).monospacedDigit() }
            }
            .foregroundStyle(ink)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(gradient))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.chat.\(id)")
    }

    // MARK: Actions

    private func pick(_ q: CoachIntroQuestion, _ set: (inout CoachIntroAnswers) -> Void) {
        withAnimation(.snappy) {
            set(&answers)
            answers.answer(q)
            typing = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.snappy) { typing = false }
        }
    }

    /// Skip: the rest keep their defaults (goal's own days and length, everything on, Fuel later).
    private func skipAll() {
        withAnimation(.snappy) {
            typing = false
            while let q = answers.next { answers.answer(q) }
        }
    }
}

// MARK: - B · Building your plan

struct PlanBuildView: View {
    let steps: [String]
    let onDone: () -> Void
    @State private var ticked = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double { steps.isEmpty ? 1 : Double(ticked) / Double(steps.count) }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            Text("🐵").font(.system(size: 60))
            Text("Building\nyour plan…").font(Theme.display(32)).multilineTextAlignment(.center).foregroundStyle(.white)
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 14)
                Circle().trim(from: 0, to: progress)
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(Theme.display(32)).monospacedDigit().foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 10) {
                        Image(systemName: i < ticked ? "checkmark.square.fill" : "square.dashed")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(i < ticked ? Theme.lime : Theme.muted)
                            .symbolEffect(.bounce, value: i < ticked)
                        Text(s).font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(i < ticked ? .white : Theme.muted)
                    }
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Building your plan")
        .task {
            let step: Duration = reduceMotion ? .milliseconds(150) : .milliseconds(480)
            for i in steps.indices {
                try? await Task.sleep(for: step)
                withAnimation(.snappy) { ticked = i + 1 }
            }
            try? await Task.sleep(for: .milliseconds(450))
            onDone()
        }
        .sensoryFeedback(.increase, trigger: ticked)
    }
}

// MARK: - C · Plan reveal

struct PlanRevealView: View {
    @Environment(AppModel.self) private var model
    let answers: CoachIntroAnswers
    let onGo: () -> Void
    let onFineTune: () -> Void
    /// Pieces popped in so far (week tiles first, then the four app tiles).
    @State private var shown = 0

    private var sessions: [Session] { model.plan?.sessions ?? [] }
    private var modules: Set<AppModule> { (answers.level ?? .everything).modules }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("🐵🎉").font(.system(size: 56)).padding(.top, 8)
                (Text("Your plan is ") + Text("ready").foregroundStyle(Theme.lime))
                    .font(Theme.display(32)).foregroundStyle(.white).multilineTextAlignment(.center)
                weekStrip
                if let first = sessions.first { nextUp(first) }
                tiles
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .readableWidth()
        .background {
            ZStack {
                Theme.bg
                RadialGradient(colors: [Theme.lime.opacity(0.28), .clear], center: .top, startRadius: 10, endRadius: 380)
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button { onGo() } label: { Text("LET'S GO") }
                    .buttonStyle(LimeButtonStyle())
                    .accessibilityIdentifier("onboarding.reveal.go")
                Button("Fine-tune my plan") { onFineTune() }
                    .font(Theme.label(15)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("onboarding.reveal.fineTune")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .readableColumn()
            .background(Theme.bg.opacity(0.92).ignoresSafeArea())
        }
        .sensoryFeedback(.impact(weight: .light), trigger: shown)
        .task {
            let total = sessions.count + 5
            for i in 0..<total {
                try? await Task.sleep(for: .milliseconds(170))
                withAnimation(.spring(duration: 0.45, bounce: 0.4)) { shown = i + 1 }
            }
        }
    }

    private func visible(_ i: Int) -> Bool { shown > i }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { i, s in
                VStack(spacing: 3) {
                    Text("DAY \(i + 1)").font(Theme.label(9)).tracking(1).opacity(0.85)
                    Text(s.focus.dayLabel).font(Theme.label(11)).lineLimit(2).minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(s.focus.palette.ink)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.horizontal, 3)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(s.focus.palette.gradient))
                .scaleEffect(visible(i) ? 1 : 0.4)
                .opacity(visible(i) ? 1 : 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sessions.count) workouts a week")
    }

    private func nextUp(_ s: Session) -> some View {
        tile(symbol: "dumbbell.fill", title: "First up · \(s.title)", line: "\(s.focus.dayLabel) · made for your gym",
             number: "\(s.estMin)′", category: s.focus.palette)
            .opacity(visible(sessions.count) ? 1 : 0)
            .offset(y: visible(sessions.count) ? 0 : 20)
    }

    private var tiles: some View {
        let goal = answers.goal ?? model.profile?.goal ?? .balanced
        var items: [(String, String, String, WorkoutEngine.Category)] = [
            ("TRAIN", "figure.strengthtraining.traditional", "\(sessions.count)×/wk", .strength),
        ]
        if modules.contains(.fuel) {
            items.append(("FUEL", "fork.knife", answers.diet?.emoji ?? FuelGoal.from(goal).label, .warmup))
        }
        if modules.contains(.mind) { items.append(("MIND", "brain.head.profile", "Daily", .mobility)) }
        items.append(("INSIGHTS", "sparkles", "Week 1", .cardio))
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: item.1).font(.system(size: 13, weight: .bold))
                        Text(item.0).font(Theme.label(12)).tracking(1)
                    }
                    Spacer(minLength: 8)
                    Text(item.2).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.5)
                }
                .foregroundStyle(item.3.ink)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(item.3.gradient))
                .scaleEffect(visible(sessions.count + 1 + i) ? 1 : 0.6)
                .opacity(visible(sessions.count + 1 + i) ? 1 : 0)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tile(symbol: String, title: String, line: String, number: String, category: WorkoutEngine.Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                Text(line).font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(number).font(Theme.display(28)).monospacedDigit()
        }
        .foregroundStyle(category.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(category.gradient))
        .accessibilityElement(children: .combine)
    }
}
