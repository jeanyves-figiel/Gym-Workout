import SwiftUI
import WorkoutEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ask your history (#868, design A + C from `ai-epic/c1.png`). A: the lime ask bar at the top of Progress with starter chips;
/// the answer is a big-number card with a mini chart. C: the same questions in Ask Coach get the card under Coach's answer.
/// Apple's on-device model calls the history tools (`HistoryAsk`) and words the answer; without it the question is read here
/// (`HistoryAsk.answer`). Either way nothing leaves the iPhone and it's free.
struct HistoryReply: Equatable {
    var text: String
    var answer: HistoryAnswer?
    var onDevice: Bool
    var seconds: Double
}

@MainActor enum HistoryAskService {
    /// The reply to a history question; nil when it isn't one (Ask Coach takes it).
    static func ask(_ question: String, records: [WorkoutRecord]) async -> HistoryReply? {
        let start = Date()
        let built = HistoryAsk.answer(question, records: records)
        #if canImport(FoundationModels)
        if #available(iOS 26, *), OnDeviceCoach.available, built != nil {
            if let m = await modelAnswer(question, records: records) {
                return HistoryReply(text: m.text, answer: m.answer ?? built, onDevice: true, seconds: Date().timeIntervalSince(start))
            }
        }
        #endif
        guard let built else { return nil }
        return HistoryReply(text: built.sentence, answer: built, onDevice: false, seconds: Date().timeIntervalSince(start))
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private static func modelAnswer(_ question: String, records: [WorkoutRecord]) async -> (text: String, answer: HistoryAnswer?)? {
        let box = HistoryBox()
        let tools: [any Tool] = [
            LiftHistoryTool(records: records, box: box), WorkoutCountTool(records: records, box: box), WeeklyVolumeTool(records: records, box: box),
        ]
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        guard let text = try? await session.respond(to: question).content.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return (text: text, answer: box.answer)
    }

    private static let instructions = """
    You are Coach Monkey in the MonkeyWorkout app. The member asks about their own logged workouts. Always call a tool to get \
    the numbers and use only what the tools return; never guess a number. Answer in at most two short sentences of plain text: \
    no lists, no markdown, no emoji. Use kg. If the tools found nothing, say so.
    """
    #endif
}

#if canImport(FoundationModels)
/// The last card a tool built, shown under the model's answer.
final class HistoryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: HistoryAnswer?
    var answer: HistoryAnswer? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@available(iOS 26, *)
struct LiftHistoryTool: Tool {
    let name = "liftHistory"
    let description = "The member's heaviest logged set of one exercise in a period, or two periods compared."
    let records: [WorkoutRecord]
    let box: HistoryBox

    @Generable struct Arguments {
        @Guide(description: "Exercise name as the member said it, like bench, back squat or deadlift")
        var exercise: String
        @Guide(description: "Period: this year, last year, this month, last month, a month name like June, last 8 weeks, or ever")
        var period: String
        @Guide(description: "A second period to compare with, like June, or an empty string")
        var compareWith: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let id = HistoryAsk.exercise(in: arguments.exercise, records: records) else {
            return "No logged sets of \(arguments.exercise)."
        }
        let now = Date()
        let p = HistoryAsk.periods(in: arguments.period, now: now).first ?? .all(now: now)
        let a: HistoryAnswer
        if let other = HistoryAsk.periods(in: arguments.compareWith, now: now).first {
            a = HistoryAsk.compare(exerciseId: id, then: other, now: p, records: records)
        } else {
            a = HistoryAsk.best(exerciseId: id, period: p, records: records, now: now)
        }
        box.answer = a
        return a.facts.joined(separator: "\n")
    }
}

@available(iOS 26, *)
struct WorkoutCountTool: Tool {
    let name = "workoutCount"
    let description = "How many workouts the member logged in a period, hours, longest streak and the periods before."
    let records: [WorkoutRecord]
    let box: HistoryBox

    @Generable struct Arguments {
        @Guide(description: "Period: this week, this month, last month, a month name like October, this year")
        var period: String
    }

    func call(arguments: Arguments) async throws -> String {
        let now = Date()
        let p = HistoryAsk.periods(in: arguments.period, now: now).first ?? HistoryAsk.periods(in: "this month", now: now)[0]
        let a = HistoryAsk.count(period: p, records: records, now: now)
        box.answer = a
        return a.facts.joined(separator: "\n")
    }
}

@available(iOS 26, *)
struct WeeklyVolumeTool: Tool {
    let name = "weeklyVolume"
    let description = "Weight the member moved per week (sets × reps × kg) in tonnes, this week last."
    let records: [WorkoutRecord]
    let box: HistoryBox

    @Generable struct Arguments {
        @Guide(description: "How many weeks to show", .range(2...12))
        var weeks: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let a = HistoryAsk.volume(weeks: arguments.weeks, records: records)
        box.answer = a
        return a.facts.joined(separator: "\n")
    }
}
#endif

/// The answer card: icon tile, title, detail and the big number, then the mini chart (last bar lime) and its caption.
struct HistoryAnswerCard: View {
    let answer: HistoryAnswer
    var onOpen: ((String) -> Void)?

    private var gradient: LinearGradient {
        switch answer.kind {
        case .best: WorkoutEngine.Category.strength.gradient
        case .compare: WorkoutEngine.Category.cardio.gradient
        case .count: WorkoutEngine.Category.mobility.gradient
        case .volume: WorkoutEngine.Category.power.gradient
        case .none: LinearGradient(colors: [Theme.cardStrong, Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var symbol: String {
        switch answer.kind {
        case .best: "trophy.fill"
        case .compare: "arrow.up.right"
        case .count: "calendar"
        case .volume: "chart.bar.fill"
        case .none: "magnifyingglass"
        }
    }

    var body: some View {
        if let id = answer.exerciseId, answer.kind != .none, let onOpen {
            Button { onOpen(id) } label: { card }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the exercise")
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            GradientTile(gradient: gradient, symbol: symbol, title: answer.title, detail: answer.detail.isEmpty ? nil : answer.detail,
                         value: answer.value == "–" ? nil : answer.value + (answer.unit == "kg" ? " kg" : answer.unit == "t" ? " t" : ""))
            if answer.bars.count > 1 {
                HistoryBars(bars: answer.bars)
                if !answer.caption.isEmpty {
                    Text(answer.caption + (answer.exerciseId != nil && onOpen != nil ? " · tap to open exercise" : ""))
                        .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Square bars, oldest first; the answer's bar lime.
struct HistoryBars: View {
    let bars: [HistoryAnswer.Bar]

    var body: some View {
        let top = max(bars.map(\.value).max() ?? 1, 0.001)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(i == bars.count - 1 ? Theme.lime : Color.white.opacity(0.18))
                        .frame(height: max(4, 64 * b.value / top))
                    Text(b.label).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 82, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Insights top (#868 A, #938 B + C): Coach monkey "Ask Coach about your training…" bar, question tiles, the answer card and Coach's sentence.
struct ProgressAskBar: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var asking = false
    @State private var reply: HistoryReply?
    @State private var asked = ""
    @State private var opening: String?
    @State private var listener = CoachListener()
    @FocusState private var typing: Bool
    /// CI screenshots: ask the first starter at once.
    var demoAsk = false

    private var records: [WorkoutRecord] { model.state.history }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HistoryAsk.starterTiles(records: records), id: \.self) { t in
                        Button { ask(t.question) } label: { StarterTile(starter: t) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t.question)
                    }
                }
            }
            if asking {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.lime)
                    Text("Looking through your workouts…").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
            } else if let reply {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(asked).font(.caption.weight(.heavy)).foregroundStyle(Theme.lime).lineLimit(2)
                        Spacer(minLength: 6)
                        Button { withAnimation(.snappy) { self.reply = nil } } label: {
                            Image(systemName: "xmark").font(.caption.weight(.black)).foregroundStyle(Theme.muted).frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear answer")
                    }
                    if let a = reply.answer { HistoryAnswerCard(answer: a) { opening = $0 } }
                    if reply.answer?.sentence != reply.text || reply.answer == nil {
                        Text(reply.text).font(.subheadline.weight(.semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(item: Binding(get: { opening.map(OpenID.init) }, set: { opening = $0?.id })) { o in
            NavigationStack { ExerciseDetailView(exerciseId: o.id).toolbar { CloseToolbarItem { opening = nil } } }
        }
        .task {
            if demoAsk, reply == nil, let q = HistoryAsk.starters(records: records).first { ask(q) }
        }
        .onDisappear { listener.cancel() }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            MonkeyFace(mood: .fired, scale: 0.36, gear: model.rank.gear)
                .frame(width: 26, height: 24)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.ink.opacity(0.12)))
                .accessibilityHidden(true)
            TextField("", text: $draft, prompt: Text("Ask Coach about your training…").foregroundStyle(Theme.ink.opacity(0.6)))
                .font(Theme.label(15))
                .focused($typing)
                .submitLabel(.search)
                .onSubmit { ask(draft) }
                .accessibilityLabel("Ask Coach about your training")
            if listener.listening {
                ProgressView().tint(Theme.ink)
            } else if !draft.isEmpty {
                Button { ask(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title3) }
                    .buttonStyle(.plain).accessibilityLabel("Ask")
            } else {
                Button { typing = false; listener.start { said in ask(said) } } label: { Image(systemName: "mic.fill").font(.subheadline.weight(.bold)) }
                    .buttonStyle(.plain).accessibilityLabel("Ask by voice")
            }
            if OnDeviceCoach.available {
                Label("on device", systemImage: "bolt.fill").font(Theme.label(10)).labelStyle(.titleAndIcon)
                    .accessibilityLabel("Answered on your iPhone")
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
    }

    private func ask(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }
        typing = false
        draft = ""
        asked = q
        asking = true
        let records = records
        Task {
            let r = await HistoryAskService.ask(q, records: records)
            asking = false
            if let r {
                withAnimation(.snappy) { reply = r }
            } else {
                // Not about the logged workouts: Ask Coach takes it (#412).
                reply = nil
                CoachAsk.shared.request = AskCoachRequest(focus: .tab(.progress), question: q)
            }
        }
    }

    private struct OpenID: Identifiable { let id: String }
}

/// Small gradient question tile under the ask bar (#938 C): kind on top, short title below, one line each.
private struct StarterTile: View {
    let starter: HistoryStarter

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(kind).font(Theme.label(9)).tracking(1).opacity(0.8)
            Text(starter.title).font(Theme.label(12)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 170, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.routineGradient(palette)))
    }

    private var kind: String {
        switch starter.kind {
        case .best: "BEST"
        case .compare: "COMPARE"
        case .count: "COUNT"
        case .volume: "VOLUME"
        }
    }

    private var palette: Int {
        switch starter.kind {
        case .best: 0
        case .compare: 1
        case .count: 2
        case .volume: 5
        }
    }
}
