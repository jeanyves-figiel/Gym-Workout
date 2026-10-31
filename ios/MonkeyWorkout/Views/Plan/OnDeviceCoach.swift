import SwiftUI
import WorkoutEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Coach (#608): Apple's on-device model (iOS 26+, Apple Intelligence iPhones). A: short Ask Coach questions
/// answered offline, instantly, nothing sent. B: the finish screen's recap reworded the second a workout ends. The server
/// Coach stays for workouts and longer chats, and for iPhones without Apple Intelligence.
@MainActor enum OnDeviceCoach {
    /// Model ready and the member hasn't switched it off (Settings → Ask Coach).
    static var available: Bool {
        guard AskCoachPref.onDevice else { return false }
        #if DEBUG
        // Demo: off unless asked, so the demo Coach (and its UI tests) stay as they are.
        if Demo.enabled { return ProcessInfo.processInfo.arguments.contains("-onDeviceCoach") }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    struct Failed: Error {}

    /// Answers one question. `about`: who the member is and what they're looking at; `history`: the chat so far.
    static func answer(_ question: String, about: String, history: [CoachChatMessage]) async throws -> String {
        #if DEBUG
        if Demo.enabled { return "3–5 min between heavy sets of 5. Take 3:00 and add 30 s if the bar slows down." }
        #endif
        let earlier = history.suffix(6).map { "\($0.role == .member ? "Member" : "Coach"): \($0.text)" }.joined(separator: "\n")
        let prompt = (earlier.isEmpty ? "" : "Chat so far:\n\(earlier)\n\n") + "Member asks: \(question)"
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let session = LanguageModelSession(instructions: Self.instructions + "\n" + about)
            let text = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw Failed() }
            return text
        }
        #endif
        throw Failed()
    }

    /// The recap in Coach's words; nil keeps the built one.
    static func recap(_ base: WorkoutRecap) async -> WorkoutRecap? {
        guard available else { return nil }
        #if DEBUG
        if Demo.enabled { return nil }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let session = LanguageModelSession(instructions: Self.instructions)
            let prompt = "Write the recap of the workout that just ended, from these facts only:\n- "
                + base.facts.joined(separator: "\n- ")
                + "\nSuggested tip: \(base.tip)"
            guard let draft = try? await session.respond(to: prompt, generating: RecapDraft.self).content,
                  !draft.recap.isEmpty, !draft.tip.isEmpty else { return nil }
            var out = base
            out.recap = draft.recap
            out.tip = draft.tip
            return out
        }
        #endif
        return nil
    }

    /// Why a lift is stuck (#875), in two short sentences from the rule facts only; nil when the model fails.
    static func plateau(_ s: StalledLift, lift: String, fix: String?) async -> String? {
        guard available else { return nil }
        #if DEBUG
        if Demo.enabled { return "Your \(lift.lowercased()) sets dropped since the weeks before, and the weight stayed the same. Try heavier, shorter sets for 2 weeks." }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let session = LanguageModelSession(instructions: Self.instructions)
            let prompt = "The member's \(lift) estimated 1RM has been flat at \(Int(s.kg.rounded())) kg for \(s.weeks) weeks. "
                + "In two short sentences say the likely cause from these facts only, then the fix.\n- "
                + s.causes.map(\.fact).joined(separator: "\n- ")
                + (fix.map { "\nFix to suggest: \($0)" } ?? "")
            guard let text = try? await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return text
        }
        #endif
        return nil
    }

    /// A Coach nudge (#876) in Coach's words: same facts, same offer; nil keeps the built text.
    static func nudge(_ base: CoachNudge) async -> CoachNudge? {
        guard available, !base.facts.isEmpty else { return nil }
        #if DEBUG
        if Demo.enabled { return nil }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let session = LanguageModelSession(instructions: Self.instructions)
            let prompt = "Write a lock-screen notification for the member, from these facts only:\n- "
                + base.facts.joined(separator: "\n- ")
                + "\nKeep every number. Example of the tone: \(base.body)"
            guard let text = try? await session.respond(to: prompt, generating: NudgeDraft.self).content.text
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= 160 else { return nil }
            var out = base
            out.body = text
            return out
        }
        #endif
        return nil
    }

    private static let instructions = """
    You are Coach Monkey, the upbeat gym coach in the MonkeyWorkout app. Answer in at most three short sentences of plain text: \
    no lists, no markdown, no emoji. Use kg and minutes. Be concrete with numbers from their training when given. \
    The screen with charts is called Insights. You can't build or change workouts here: \
    for a new workout, tell the member to ask for one. For pain, injury or medical questions, keep it safe and suggest seeing \
    a professional.
    """
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
struct RecapDraft {
    @Guide(description: "Two short sentences on how the workout went, with the real numbers from the facts")
    var recap: String
    @Guide(description: "One short tip for next time, with a weight or rep number")
    var tip: String
}
#endif

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
struct NudgeDraft {
    @Guide(description: "One or two short, warm sentences under 140 characters, with the real numbers from the facts")
    var text: String
}
#endif

extension AppModel {
    /// Who the member is, for the on-device Coach (#608): goal, level, method, what they're looking at.
    func onDeviceCoachAbout(focus: CoachFocus?) -> String {
        var lines: [String] = []
        if let p = profile {
            lines.append("Member: goal \(p.goal.rawValue), level \(p.experience.rawValue), method \(p.trainingMethod.rawValue).")
        }
        if let p = body.pronounsText { lines.append("Pronouns: \(p).") }
        if let focus { lines.append("Looking at: \(focus.title)\(focus.detail.map { ", \($0)" } ?? "").") }
        // Their own recent training (#1010), shorter for the small on-device model.
        if let t = coachTraining { lines.append("Their training:\n" + t.prefix(12).joined(separator: "\n")) }
        return lines.joined(separator: "\n")
    }
}

/// "⚡ ON DEVICE" over an answer from the on-device model (#608 A).
struct OnDeviceBadge: View {
    var seconds: Double?

    var body: some View {
        HStack(spacing: 6) {
            Label("On device", systemImage: "bolt.fill")
                .font(Theme.label(10)).tracking(0.8).textCase(.uppercase)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lime))
            Text((seconds.map { String(format: "%.1f s · ", $0) } ?? "") + "nothing left your iPhone")
                .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.leading, 42)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Answered on your iPhone, nothing was sent")
    }
}

/// Finish screen (#608 B): two lines on the session and one tip, shown the second it ends.
struct RecapCard: View {
    let recap: WorkoutRecap
    var onDevice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Done · \(recap.title)").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
                Spacer(minLength: 6)
                if onDevice {
                    Image(systemName: "bolt.fill").font(.caption.weight(.black)).foregroundStyle(Theme.lime)
                        .accessibilityLabel("Written on your iPhone")
                }
            }
            Text(recap.recap).font(Theme.display(20)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next time").font(Theme.label(10)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.ink.opacity(0.7))
                Text(recap.tip).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime))
        }
        .foregroundStyle(.white)
        .gradientCard(WorkoutEngine.Category.power.gradient, padding: 14)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
extension Demo {
    /// Demo screen `player-done`: the finish recap (#608 B).
    static let recap = WorkoutRecap(title: "PUSH DAY · 48′", recap: "Bench press +2.5 kg vs last week, all 8s clean. Dips stopped at 2 of 3 sets.",
                                    tip: "Try 82.5 kg × 6 on bench press.")
}
#endif
