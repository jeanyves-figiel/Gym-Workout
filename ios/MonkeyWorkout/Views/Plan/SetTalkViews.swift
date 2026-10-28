import APIClient
import SwiftUI
import WorkoutEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Talk to Coach mid-set (#874, design A + C from `ai-epic/b1.png`): hold the mic in Up next, ask about the set on
/// screen; the answer card sits over the exercise picture (nothing in the layout moves) with up to two one-tap fixes,
/// and Coach says the answer out loud.

extension AppModel {
    /// Rules first (instant, offline), then the on-device model, then the server Coach (Pro).
    func setTalk(_ question: String, context: SetTalkContext) async -> SetTalkAnswer {
        if let a = SetTalk.rules(question, context) { return a }
        #if DEBUG
        if demo {
            return SetTalkAnswer(heard: question, text: "Same weight, slower on the way down. Brace before every rep.", source: .onDevice)
        }
        #endif
        if OnDeviceCoach.available, let wire = await OnDeviceCoach.setTalk(question, facts: context.facts),
           let a = SetTalk.cleaned(wire, heard: question, context: context, source: .onDevice) {
            return a
        }
        if !ProStore.shared.locked, let wire = try? await api.coachSet(question, context: context, as: SetTalkWireAnswer.self),
           let a = SetTalk.cleaned(wire, heard: question, context: context, source: .server) {
            return a
        }
        let text = ProStore.shared.locked
            ? "Ask me \"too heavy?\" or \"how long to rest?\". Other questions are part of Pro."
            : "Can't reach Coach right now. Try \"too heavy?\" or \"how long to rest?\"."
        return SetTalkAnswer(heard: question, text: text, source: .rules)
    }

    /// "97.5 kg × 5": the exercise's best set the last time it was done before this workout.
    func setTalkLastTime(exerciseId: String, sessionId: String) -> String? {
        let from = workoutWindowStart(sessionId)
        guard let last = state.logs.last(where: { $0.exerciseId == exerciseId && $0.date < from && $0.weightKg != nil }) else { return nil }
        let day = Calendar.current.startOfDay(for: last.date)
        let sets = state.logs.filter { $0.exerciseId == exerciseId && Calendar.current.startOfDay(for: $0.date) == day && $0.weightKg != nil }
        guard let best = sets.max(by: { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }), let kg = best.weightKg else { return nil }
        return LoadAdvisor.formatKg(kg) + " kg" + (best.reps.map { " × \($0)" } ?? "")
    }
}

extension OnDeviceCoach {
    /// The on-device model's answer and fixes (#874); nil when it can't run or answer.
    static func setTalk(_ question: String, facts: String) async -> SetTalkWireAnswer? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let session = LanguageModelSession(instructions: setTalkInstructions)
            guard let d = try? await session.respond(to: facts + "\n\nMember says: " + question, generating: SetTalkDraft.self).content else {
                return nil
            }
            var actions: [SetTalkWireAction] = []
            if d.kg > 0 { actions.append(.init(kind: "weight", kg: d.kg)) }
            if !d.swapId.isEmpty { actions.append(.init(kind: "swap", exerciseId: d.swapId)) }
            if d.restSec > 0 { actions.append(.init(kind: "rest", sec: d.restSec)) }
            return SetTalkWireAnswer(answer: d.answer, actions: actions)
        }
        #endif
        return nil
    }

    private static let setTalkInstructions = """
    You are Coach Monkey, the upbeat gym coach in the MonkeyWorkout app. The member is between sets and asks you something \
    out loud; your answer is spoken back. Answer in one or two short sentences of plain text, max 30 words, with numbers \
    from the facts. Too heavy or 0 reps in reserve: a lighter kg. Easy: a little heavier. Pain: lighter or a swap from the \
    list, and stop if it is sharp pain. Never diagnose.
    """
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
struct SetTalkDraft {
    @Guide(description: "One or two short spoken sentences, max 30 words")
    var answer: String
    @Guide(description: "New kg for the coming set, a multiple of the weight step; 0 to keep the weight")
    var kg: Double
    @Guide(description: "Exercise id copied from the swaps list to swap to; empty to keep the exercise")
    var swapId: String
    @Guide(description: "Rest in seconds before the next set; 0 to keep the planned rest")
    var restSec: Int
}
#endif

/// Hold to ask Coach (#874 A), first in the Up next bar. A short tap starts listening until the member stops talking.
struct SetTalkMic: View {
    let listening: Bool
    let onStart: () -> Void
    let onEnd: () -> Void
    @State private var pressed: Date?
    @State private var down = false

    var body: some View {
        Image(systemName: listening ? "waveform" : "mic.fill")
            .font(.system(size: 18, weight: .heavy))
            .symbolEffect(.variableColor.iterative, isActive: listening)
            .foregroundStyle(listening ? Theme.ink : .white)
            .frame(width: 52)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(listening ? Theme.lime : Theme.cardStrong))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !down else { return }
                    down = true
                    if listening { onEnd() } else { pressed = Date(); onStart() }
                }
                .onEnded { _ in
                    down = false
                    guard let p = pressed else { return }
                    pressed = nil
                    // Held: release sends. Tapped: keep listening until the member stops talking.
                    if Date().timeIntervalSince(p) > 0.5 { onEnd() }
                })
            .accessibilityElement()
            .accessibilityLabel(listening ? "Stop listening" : "Talk to Coach")
            .accessibilityHint("Ask about this set, or say done, a weight, reps, skip rest or next")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { listening ? onEnd() : onStart() }
            .accessibilityIdentifier("player.talk")
    }
}

/// What Coach heard, the answer (or that it's thinking) and up to two fixes, over the exercise picture (#874 A).
struct SetTalkCard: View {
    let heard: String
    let answer: SetTalkAnswer?
    let onAction: (SetTalkAction) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Coach's answer")
                Spacer(minLength: 24)
                Label("\"\(heard)\"", systemImage: "mic.fill")
                    .font(.subheadline.weight(.bold)).lineLimit(2)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
            }
            .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                if let answer {
                    Text(answer.text).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if answer.source == .onDevice {
                        Label("On device", systemImage: "bolt.fill").font(Theme.label(10)).tracking(0.8).textCase(.uppercase)
                            .foregroundStyle(Theme.lime)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Coach is thinking…").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))

            if let actions = answer?.actions, !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                        Button { onAction(a) } label: {
                            Label(a.label, systemImage: a.symbol)
                                .font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(i == 0 ? Theme.ink : .white)
                                .padding(.horizontal, 12).frame(minHeight: 40)
                                .background(Capsule().fill(i == 0 ? Theme.lime : Theme.card))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("player.talk.action\(i)")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.82)))
        .accessibilityElement(children: .contain)
    }
}
