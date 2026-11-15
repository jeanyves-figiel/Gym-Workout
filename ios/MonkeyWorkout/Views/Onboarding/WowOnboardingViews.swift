import SwiftUI
import WorkoutEngine

// Wow onboarding (#1084, mix A + B + C from `wow-onboarding/{a,b,c}.png`):
// A Coach Monkey chat (one question at a time, big gradient answers, Coach reacts),
// B "Building your plan…" ring and ticking checklist after the gym steps,
// C plan reveal: the week's workouts pop in one by one, then Train / Fuel / Mind / Insights tiles.

// MARK: - Story cards (#1103, design B from `onboarding-flow/b.png`)

/// Chapters of the sign-up story: the bar on top of every card.
enum StoryChapter: Int, CaseIterable {
    case you, app, body, gym

    var title: String {
        switch self {
        case .you: "YOU"
        case .app: "APP"
        case .body: "BODY"
        case .gym: "GYM"
        }
    }

    static func of(_ q: CoachIntroQuestion?) -> StoryChapter {
        switch q {
        case nil: .gym
        case .level, .diet, .allergies: .app
        case .figure, .pronouns, .health, .reminder: .body
        default: .you
        }
    }
}

/// Chapter bar for every story card: lime up to the current chapter.
struct StoryChapterBar: View {
    let chapter: StoryChapter
    var ink: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            ForEach(StoryChapter.allCases, id: \.self) { c in
                VStack(spacing: 4) {
                    Capsule().fill(c.rawValue <= chapter.rawValue ? ink : ink.opacity(0.25)).frame(height: 4)
                    Text(c.title).font(Theme.label(9)).tracking(1)
                        .foregroundStyle(ink.opacity(c.rawValue <= chapter.rawValue ? 1 : 0.5))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
        .animation(.snappy, value: chapter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chapter \(chapter.rawValue + 1) of \(StoryChapter.allCases.count): \(chapter.title.capitalized)")
    }
}

/// Answers so far as stickers that pile up on top of each card.
struct StoryStickers: View {
    let stickers: [String]
    var ink: Color = .white

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(Array(stickers.enumerated()), id: \.offset) { _, s in
                Text(s).font(Theme.label(11)).foregroundStyle(ink).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.22)))
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.45), value: stickers)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stickers.isEmpty ? "" : "So far: " + stickers.joined(separator: ", "))
    }
}

/// Coach's question split for a story card: the sentence with "?" is the big title, the rest is Coach's line.
enum StoryText {
    static func split(_ text: String) -> (lead: String?, title: String) {
        let sentences = text.split(separator: " ").reduce(into: [""]) { out, word in
            out[out.count - 1] += (out[out.count - 1].isEmpty ? "" : " ") + word
            if let last = word.last, ".?!".contains(last) { out.append("") }
        }.filter { !$0.isEmpty }
        guard let i = sentences.firstIndex(where: { $0.hasSuffix("?") }) else { return (nil, text) }
        let rest = sentences.enumerated().filter { $0.offset != i }.map(\.element).joined(separator: " ")
        return (rest.isEmpty ? nil : rest, sentences[i])
    }
}

struct CoachIntroChat: View {
    @Binding var answers: CoachIntroAnswers
    let onDone: () -> Void
    @Environment(HealthManager.self) private var healthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Coach types its reaction to the last answer on the new card, then the question shows (#1101 rhythm).
    @State private var typing = false
    @State private var typingTask: Task<Void, Never>?
    /// Card slide direction: forward on an answer, back on Back / swipe.
    @State private var forward = true

    private var questions: [CoachIntroQuestion] { answers.questions }
    private var index: Int { answers.next.flatMap { questions.firstIndex(of: $0) } ?? questions.count }
    /// Each card its own gradient, so every answer visibly moves you on.
    private var category: WorkoutEngine.Category { Self.cycle[index % Self.cycle.count] }
    private var ink: Color { category.ink }

    var body: some View {
        ZStack {
            category.gradient.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: index)
            VStack(alignment: .leading, spacing: 10) {
                header
                StoryStickers(stickers: answers.stickers, ink: ink)
                ScrollView {
                    storyCard
                        .id(answers.next?.rawValue ?? "gym")
                        .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .readableColumn()
        }
        .foregroundStyle(ink)
        .contentShape(Rectangle())
        // Swipe back like a story: right swipe undoes the last answer.
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width > 80, abs(v.translation.height) < 60, !answers.answered.isEmpty { back() }
        })
        .sensoryFeedback(.selection, trigger: answers.answered.count)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header, card, footer

    private var header: some View {
        HStack(spacing: 12) {
            if !answers.answered.isEmpty {
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.black.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("onboarding.chat.back")
            }
            StoryChapterBar(chapter: StoryChapter.of(answers.next), ink: ink)
            if answers.next != nil {
                Button("Skip") { skipAll() }
                    .font(Theme.label(15)).foregroundStyle(ink.opacity(0.85))
                    .accessibilityIdentifier("onboarding.chat.skip")
            }
        }
    }

    @ViewBuilder private var storyCard: some View {
        let q = answers.next
        let text = StoryText.split(q.map { CoachIntro.question($0, answers) } ?? CoachIntro.gymPrompt)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("🐵").font(.system(size: 46))
                if typing {
                    TypingBubble()
                } else if let line = coachLine(lead: text.lead) {
                    Text(line)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16,
                                                           topTrailingRadius: 16, style: .continuous).fill(.black.opacity(0.22)))
                        .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            if !typing {
                Text(q == nil ? "Now, your gym" : text.title)
                    .font(Theme.display(32)).lineLimit(4).minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isHeader)
                choices
                    .transition(.opacity.combined(with: .offset(y: 24)))
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: typing)
    }

    /// Coach's reaction to the last answer, then the lead-in of this question.
    private func coachLine(lead: String?) -> String? {
        let reaction = answers.answered.last.map { CoachIntro.reaction($0, answers) }
        let parts = [reaction, lead].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var footer: some View {
        Text(answers.next == nil ? "Questions done 🎉" : "‹ swipe back · \(index + 1) of \(questions.count)")
            .font(Theme.label(11)).opacity(0.75)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
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
            if let q = answers.next {
                switch q {
                case .goal:
                    ForEach(Goal.allCases) { g in
                        card(symbol: g.symbol, title: g.config.label, number: nil, id: "goal.\(g.rawValue)") { pick(.goal) { $0.goal = g } }
                    }
                case .days:
                    daysGrid
                case .minutes:
                    ForEach(Array(CoachIntro.minuteChoices.enumerated()), id: \.offset) { _, m in
                        card(symbol: m == nil ? "sparkles" : "timer", title: m.map(Self.minutesTitle) ?? "Coach picks",
                             number: m.map { "\($0)′" }, id: "minutes.\(m ?? 0)") { pick(.minutes) { $0.minutes = m } }
                    }
                case .experience:
                    ForEach(Array(Experience.allCases.enumerated()), id: \.element) { i, e in
                        card(symbol: ["leaf.fill", "flame.fill", "bolt.fill"][i % 3], title: Self.experienceTitle(e),
                             number: String(repeating: "★", count: e.level), id: "experience.\(e.rawValue)") {
                            pick(.experience) { $0.experience = e }
                        }
                    }
                case .level:
                    ForEach(AppLevel.allCases) { l in
                        card(symbol: l.symbol, title: l.title, number: nil, id: "level.\(l.rawValue)") { pick(.level) { $0.level = l } }
                    }
                case .diet:
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(FuelDiet.allCases) { d in
                            tile(emoji: d.emoji, symbol: nil, title: d.label, on: false, id: "diet.\(d.rawValue)") { pick(.diet) { $0.diet = d } }
                        }
                    }
                    ghostButton("Skip for now", id: "diet.skip") { pick(.diet) { $0.diet = nil } }
                case .weekdays:
                    dayPicker(selected: answers.weekdays ?? [], toggle: { d in
                        answers.weekdays = CoachIntro.toggled(answers.weekdays ?? [], d)
                    }, none: "Any day", noneAction: { pick(.weekdays) { $0.weekdays = nil } }, done: { pick(.weekdays) { _ in } })
                case .sports:
                    multiGrid(items: CoachIntro.sportChoices.map { ($0.rawValue, $0.symbol, $0.short, answers.sports.contains($0)) },
                              toggle: { id in
                                  guard let s = Sport(rawValue: id) else { return }
                                  if answers.sports.contains(s) { answers.sports.removeAll { $0 == s } } else { answers.sports.append(s) }
                              },
                              none: "Just the gym", noneAction: { pick(.sports) { $0.sports = []; $0.sportDays = [] } },
                              done: { pick(.sports) { _ in } })
                case .sportDays:
                    dayPicker(selected: answers.sportDays, toggle: { d in
                        answers.sportDays = CoachIntro.toggled(answers.sportDays, d)
                    }, none: "No fixed days", noneAction: { pick(.sportDays) { $0.sportDays = [] } }, done: { pick(.sportDays) { _ in } })
                case .focus:
                    multiGrid(items: MuscleGroup.allCases.map { ($0.rawValue, "scope", $0.label, answers.focus.contains($0)) },
                              toggle: { id in
                                  guard let m = MuscleGroup(rawValue: id) else { return }
                                  if answers.focus.contains(m) {
                                      answers.focus.removeAll { $0 == m }
                                  } else if answers.focus.count < CoachIntroAnswers.maxFocus {
                                      answers.focus.append(m)
                                  }
                              },
                              none: "No focus", noneAction: { pick(.focus) { $0.focus = [] } }, done: { pick(.focus) { _ in } })
                case .pain:
                    multiGrid(items: PainArea.allCases.map { ($0.rawValue, "bandage.fill", $0.label.capitalized, false) },
                              toggle: { id in pick(.pain) { $0.pain = PainArea(rawValue: id) } },
                              none: "Nothing hurts", noneAction: { pick(.pain) { $0.pain = nil } }, done: nil)
                case .allergies:
                    multiGrid(items: Allergen.allCases.map { ($0.rawValue, "xmark.circle.fill", $0.label, answers.allergies.contains($0)) },
                              toggle: { id in
                                  guard let x = Allergen(rawValue: id) else { return }
                                  if answers.allergies.contains(x) { answers.allergies.remove(x) } else { answers.allergies.insert(x) }
                              },
                              none: "I eat anything", noneAction: { pick(.allergies) { $0.allergies = [] } },
                              done: { pick(.allergies) { _ in } })
                case .figure:
                    HStack(spacing: 8) {
                        ForEach(BodyMapLayout.Figure.allCases) { f in
                            tile(emoji: nil, symbol: f == .male ? "figure.stand" : "figure.stand.dress", title: f == .male ? "Male" : "Female",
                                 on: false, id: "figure.\(f.rawValue)") { pick(.figure) { $0.figure = f } }
                        }
                    }
                    ghostButton("Skip", id: "figure.skip") { pick(.figure) { $0.figure = nil } }
                case .pronouns:
                    HStack(spacing: 8) {
                        ForEach([Pronouns.she, .he, .they], id: \.self) { pr in
                            tile(emoji: nil, symbol: "person.fill", title: pr.label, on: false, id: "pronouns.\(pr.rawValue)") {
                                pick(.pronouns) { $0.pronouns = pr }
                            }
                        }
                    }
                    ghostButton("Skip", id: "pronouns.skip") { pick(.pronouns) { $0.pronouns = nil } }
                case .health:
                    card(symbol: "heart.fill", title: "Connect Apple Health", number: nil, id: "health.connect") {
                        pick(.health) { $0.health = true }
                        Task { await healthManager.connect() }
                    }
                    ghostButton("Not now", id: "health.skip") { pick(.health) { $0.health = false } }
                case .reminder:
                    ForEach(Array(CoachIntro.reminderChoices.enumerated()), id: \.offset) { _, m in
                        if let m {
                            card(symbol: "bell.fill", title: "At \(CoachIntro.clock(m))", number: nil, id: "reminder.\(m)") {
                                pick(.reminder) { $0.reminder = m; $0.noReminders = false }
                                Task { await NotificationManager.shared.requestAuthorization() }
                            }
                        } else {
                            ghostButton("No reminders", id: "reminder.none") { pick(.reminder) { $0.reminder = nil; $0.noReminders = true } }
                        }
                    }
                }
            } else {
                solidButton("FIND MY GYM", id: "done", action: onDone)
            }
        }
    }

    private static let cycle: [WorkoutEngine.Category] = [.strength, .warmup, .power, .cardio, .mobility]

    private static func minutesTitle(_ m: Int) -> String {
        switch m {
        case ...30: "Quick"
        case ...45: "Solid"
        case ...60: "Full"
        default: "Beast"
        }
    }

    // MARK: Tiles (translucent white on the card's gradient, picked = solid white)

    private func fill(_ on: Bool) -> some ShapeStyle { on ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.24)) }

    private var daysGrid: some View {
        let recommended = (answers.goal ?? .balanced).recommendedSessions
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(CoachIntro.dayChoices, id: \.self) { d in
                let best = d == recommended
                Button { pick(.days) { $0.days = d } } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(d)").font(Theme.display(34)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        Spacer(minLength: 4)
                        Text(best ? "★ BEST" : "DAYS").font(Theme.label(11)).tracking(1).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(best ? Theme.ink : ink)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill(best)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(d) days a week\(best ? ", recommended" : "")")
                .accessibilityIdentifier("onboarding.chat.days.\(d)")
            }
        }
    }

    /// Answer row: icon tile left, heavy title, big number right.
    private func card(symbol: String, title: String, number: String?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.24)))
                Text(title).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if let number { Text(number).font(Theme.display(24)).monospacedDigit() }
            }
            .foregroundStyle(ink)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill(false)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.chat.\(id)")
    }

    private func tile(emoji: String?, symbol: String?, title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let emoji { Text(emoji).font(.system(size: 22)) }
                    if let symbol { Image(systemName: symbol).font(.system(size: 20, weight: .bold)) }
                    Spacer(minLength: 0)
                    if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold)) }
                }
                Text(title).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(on ? Theme.ink : ink)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(fill(on)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("onboarding.chat.\(id)")
    }

    /// Mon…Sun tiles (multi pick) with Done and a "none" answer; two letters that shrink to fit (#1101).
    private func dayPicker(selected: [Int], toggle: @escaping (Int) -> Void, none: String, noneAction: @escaping () -> Void,
                           done: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { d in
                    let on = selected.contains(d)
                    Button { withAnimation(.snappy) { toggle(d) } } label: {
                        Text(CoachIntro.weekdayShort[d - 1].prefix(2).uppercased())
                            .font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.5)
                            .foregroundStyle(on ? Theme.ink : ink)
                            .padding(.horizontal, 2)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill(on)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CoachIntro.weekdayShort[d - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("onboarding.chat.day.\(d)")
                }
            }
            doneRow(none: none, noneAction: noneAction, done: selected.isEmpty ? nil : done)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    /// Tiles, three a row; `done` nil = one tap answers.
    private func multiGrid(items: [(id: String, symbol: String, title: String, on: Bool)], toggle: @escaping (String) -> Void,
                           none: String, noneAction: @escaping () -> Void, done: (() -> Void)?) -> some View {
        let anyOn = items.contains { $0.on }
        return VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(items, id: \.id) { item in
                    tile(emoji: nil, symbol: item.symbol, title: item.title, on: item.on, id: "pick.\(item.id)") {
                        withAnimation(.snappy) { toggle(item.id) }
                    }
                }
            }
            doneRow(none: none, noneAction: noneAction, done: anyOn ? done : nil)
        }
    }

    private func doneRow(none: String, noneAction: @escaping () -> Void, done: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            ghostButton(none, id: "none", action: noneAction)
            if let done { solidButton("DONE", id: "multiDone", action: done) }
        }
    }

    private func ghostButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.display(16)).foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Capsule().fill(.black.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.chat.\(id)")
    }

    private func solidButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(15)).tracking(1.5).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Capsule().fill(Theme.ink))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.chat.\(id)")
    }

    // MARK: Actions

    /// Answer: the card slides away, the next one slides in, Coach types its reaction, then the question shows.
    private func pick(_ q: CoachIntroQuestion, _ set: (inout CoachIntroAnswers) -> Void) {
        guard !typing else { return }
        forward = true
        withAnimation(.snappy) {
            set(&answers)
            answers.answer(q)
            typing = true
        }
        let pause: Duration = reduceMotion ? .milliseconds(200) : .milliseconds(650)
        typingTask = Task {
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { typing = false }
        }
    }

    private func back() {
        stopTyping()
        forward = false
        withAnimation(.snappy) { answers.undoLast() }
    }

    private func stopTyping() {
        typingTask?.cancel()
        typingTask = nil
        typing = false
    }

    /// Skip: the rest keep their defaults (goal's own days and length, everything on, Fuel later).
    private func skipAll() {
        stopTyping()
        forward = true
        withAnimation(.snappy) {
            while let q = answers.next { answers.answer(q) }
        }
    }
}

extension CoachIntroAnswers {
    /// Answered values as story stickers (#1103); skipped ones stay off.
    var stickers: [String] {
        answered.compactMap { q -> String? in
            switch q {
            case .goal: goal.map { "\($0.config.label)" }
            case .days: days.map { "\($0) days" }
            case .minutes: minutes.map { "\($0) min" }
            case .experience: experience.map(CoachIntroChat.experienceTitle)
            case .level: level?.title
            case .diet: diet.map { "\($0.emoji) \($0.label)" }
            case .weekdays: weekdays.flatMap { $0.isEmpty ? nil : CoachIntro.dayList($0) }
            case .sports: sports.isEmpty ? nil : CoachIntro.sportList(sports)
            case .sportDays: sportDays.isEmpty ? nil : CoachIntro.dayList(sportDays)
            case .focus: focus.isEmpty ? nil : focus.map(\.label).joined(separator: " + ")
            case .pain: pain.map { "🩹 " + $0.label.capitalized }
            case .allergies: allergies.isEmpty ? nil : "No " + Allergen.allCases.filter { allergies.contains($0) }.map(\.label).joined(separator: ", ")
            case .figure: nil
            case .pronouns: pronouns?.label
            case .health: health == true ? "❤️ Health" : nil
            case .reminder: reminder.map { "🔔 \(CoachIntro.clock($0))" }
            }
        }
    }
}

/// Coach "typing": three dots that bounce in turn (#1101).
struct TypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(.white).frame(width: 8, height: 8)
                    .phaseAnimator(reduceMotion ? [0.6] : [0.35, 1, 0.35]) { dot, phase in
                        dot.opacity(phase).offset(y: phase == 1 ? -3 : 0)
                    } animation: { _ in .easeInOut(duration: 0.3).delay(Double(i) * 0.12) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 5, bottomTrailingRadius: 18,
                                           topTrailingRadius: 18, style: .continuous).fill(.black.opacity(0.22)))
        .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
        .accessibilityElement()
        .accessibilityLabel("Coach is typing")
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
                Circle().stroke(Color.white.opacity(0.22), lineWidth: 14)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
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
                            .foregroundStyle(i < ticked ? .white : .white.opacity(0.45))
                            .symbolEffect(.bounce, value: i < ticked)
                        Text(s).font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(i < ticked ? .white : .white.opacity(0.55))
                    }
                }
            }
            .frame(maxWidth: 320, alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        // Story card (#1103): the build is one more gradient card.
        .background(WorkoutEngine.Category.strength.gradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
                Text("Your plan\nis ready")
                    .font(Theme.display(34)).foregroundStyle(.white).multilineTextAlignment(.center)
                // The answers' stickers fly in (#1103 B).
                StoryStickers(stickers: answers.stickers)
                    .scaleEffect(shown > 0 ? 1 : 1.4)
                    .opacity(shown > 0 ? 1 : 0)
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
                WorkoutEngine.Category.mobility.gradient
                ConfettiBurst()
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button { onGo() } label: { Text("LET'S GO") }
                    .buttonStyle(LimeButtonStyle())
                    .accessibilityIdentifier("onboarding.reveal.go")
                Button("Fine-tune my plan") { onFineTune() }
                    .font(Theme.label(15)).foregroundStyle(.white.opacity(0.85))
                    .accessibilityIdentifier("onboarding.reveal.fineTune")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .readableColumn()
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
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.horizontal, 3)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
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
                .foregroundStyle(.white)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
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
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white, lineWidth: 2.5))
        .accessibilityElement(children: .combine)
    }
}

/// Confetti on the reveal (#1103 B): emoji pieces fall once; still with Reduce Motion.
struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fallen = false
    private static let emoji = ["🎉", "✨", "🎊", "💪", "⭐️", "🍌"]
    private static let pieces: [(String, CGFloat, CGFloat, Double)] = (0..<18).map(piece)

    private static func stop(_ i: Int) -> CGFloat { 0.25 + CGFloat(i % 5) * 0.15 }

    private static func piece(_ i: Int) -> (String, CGFloat, CGFloat, Double) {
        let x = CGFloat((i * 37) % 100) / 100
        let size = CGFloat(14 + (i * 7) % 14)
        let delay = Double(i % 6) * 0.08
        return (emoji[i % emoji.count], x, size, delay)
    }

    var body: some View {
        GeometryReader { g in
            ForEach(Array(Self.pieces.enumerated()), id: \.offset) { i, p in
                Text(p.0).font(.system(size: p.2))
                    .rotationEffect(.degrees(fallen ? Double(i * 47) : 0))
                    .position(x: g.size.width * p.1, y: fallen ? g.size.height * Self.stop(i) : -30)
                    .opacity(fallen ? 0 : 1)
                    .animation(.easeIn(duration: 2.2).delay(p.3), value: fallen)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { fallen = true } }
        .opacity(reduceMotion ? 0 : 1)
    }
}
