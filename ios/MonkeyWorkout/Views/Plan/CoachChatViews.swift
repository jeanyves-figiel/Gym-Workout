import APIClient
import SwiftUI
import WorkoutEngine

/// Workout chat (#381, design A): the member tells Coach Monkey what they want today ("45 min, legs, sore
/// shoulder") and gets a workout card in the chat with Start now / Add to a day / Tweak. The server turns the chat
/// into generator settings; the app's generator builds the workout from the member's gym and level.
struct CoachChatMessage: Identifiable, Equatable {
    enum Role: String { case member, coach }
    let id = UUID()
    var role: Role
    var text: String
    var workout: CustomWorkout?
    var settings: CoachWorkoutSettings?
}

/// Today's conversation, kept while the app runs; a new day starts a fresh chat.
@MainActor @Observable final class CoachChatStore {
    static let shared = CoachChatStore()
    var messages: [CoachChatMessage] = []
    var remaining: Int?
    var available: Bool?
    private var day = Calendar.current.startOfDay(for: Date())

    func rollOver() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != day {
            day = today
            messages = []
            remaining = nil
        }
    }
}

extension AppModel {
    /// What the coach knows about the member: goal, level, method, session length, gym, readiness, today's plan.
    func coachChatContext(readiness: String?) -> CoachChatContext {
        guard let p = profile else { return CoachChatContext(readiness: readiness) }
        let today = nextSession.flatMap { $0.weekday == todayWeekday ? $0.displayTitle : nil }
        return CoachChatContext(goal: p.goal.rawValue, level: p.experience.rawValue, sessionMinutes: Generator.sessionMinutes(p),
                                equipment: p.equipment.map(\.rawValue), readiness: readiness, todayPlanned: today,
                                method: p.trainingMethod.rawValue)
    }

    func coachChatStatus() async -> CoachChatStatus? {
        #if DEBUG
        if demo { return CoachChatStatus(available: true, remainingToday: 18) }
        #endif
        return try? await api.coachChatStatus()
    }

    /// Sends the conversation; the last message is the member's.
    func coachChat(_ messages: [CoachChatMessage], readiness: String?) async throws -> CoachChatAnswer<CoachWorkoutSettings> {
        #if DEBUG
        if demo { return try Demo.coachAnswer(messages.last?.text ?? "") }
        #endif
        let turns = messages.filter { !$0.text.isEmpty }.map { CoachChatTurn(role: $0.role.rawValue, text: $0.text) }
        return try await api.coachChat(turns, context: coachChatContext(readiness: readiness), as: CoachWorkoutSettings.self)
    }
}

/// "Ask Coach" bar inside the Coach card on Train: opens the chat.
struct AskCoachBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 13, weight: .bold))
                Text("Ask Coach for today's workout…").font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Theme.lime))
            }
            .foregroundStyle(.white)
            .padding(.leading, 12).padding(.trailing, 5).padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.28)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Coach for today's workout")
    }
}

/// The chat, full screen.
struct CoachChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var store = CoachChatStore.shared
    @State private var draft = ""
    @State private var sending = false
    @State private var gate: ProGate?
    @State private var playing: CustomWorkout?
    @State private var planning: CustomWorkout?
    @State private var tweaking: CoachChatMessage?
    @FocusState private var typing: Bool

    private static let starters = ["45 min full body", "Quick 20 min, I'm tired", "Legs, sore shoulder", "Upper body, no barbell"]
    private static let tweaks = ["Shorter", "Harder", "Easier", "No barbell", "Swap the first exercise"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            greeting
                            ForEach(store.messages) { m in message(m).id(m.id) }
                            if sending { typingBubble.id("typing") }
                            chips.id("chips")
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: store.messages.count) { scrollDown(proxy) }
                    .onChange(of: sending) { scrollDown(proxy) }
                    .onAppear { scrollDown(proxy, animated: false) }
                }
                inputBar
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Ask Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .proPaywall($gate)
            .fullScreenCover(item: $playing) { w in WorkoutPlayerView(sessionId: w.sessionId) }
            .sheet(item: $planning) { w in AddToPlanSheet(workout: w) }
            .sheet(item: $tweaking) { m in
                if let w = m.workout { CustomWorkoutEditor(initial: w, generated: m.settings?.options) }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            store.rollOver()
            if let s = await model.coachChatStatus() {
                store.available = s.available
                store.remaining = s.remainingToday
            }
        }
    }

    // MARK: Messages

    private var greeting: some View {
        coachBubble(store.available == false
                    ? "Coach chat isn't switched on yet. Check back soon!"
                    : "Hey! What do you feel like today? Tell me your time, what to train and anything sore.")
    }

    @ViewBuilder private func message(_ m: CoachChatMessage) -> some View {
        switch m.role {
        case .member:
            Text(m.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 5, topTrailingRadius: 18)
                    .fill(Theme.lime))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        case .coach:
            VStack(alignment: .leading, spacing: 10) {
                if !m.text.isEmpty { coachBubble(m.text) }
                if let w = m.workout { workoutCard(w, message: m) }
            }
        }
    }

    private func coachBubble(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            MonkeyFace(mood: .fired, scale: 0.55, gear: model.rank.gear)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 5, bottomTrailingRadius: 18, topTrailingRadius: 18)
                    .fill(Color.white.opacity(0.1)))
        }
        .padding(.trailing, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach: \(text)")
    }

    private var typingBubble: some View {
        HStack(spacing: 8) {
            MonkeyFace(mood: .fired, scale: 0.55, gear: model.rank.gear).frame(width: 34, height: 34)
            ProgressView().tint(.white)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .accessibilityLabel("Coach is typing")
    }

    /// The workout made for today: name, length, first exercises, Start now / Add to day / Tweak.
    private func workoutCard(_ w: CustomWorkout, message m: CoachChatMessage) -> some View {
        let items = w.playableItems
        let latest = store.messages.last { $0.workout != nil }?.id == m.id
        return VStack(alignment: .leading, spacing: 8) {
            Text("Made for today · \(w.session.estMin) min").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
            Text(w.name).font(Theme.display(22)).lineLimit(2).minimumScaleFactor(0.7)
            VStack(spacing: 0) {
                ForEach(items.prefix(3)) { it in
                    HStack {
                        Text(it.exercise?.name ?? it.exerciseId).font(.footnote.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(it.sets)×\(it.reps)").font(.footnote.weight(.heavy)).monospacedDigit()
                    }
                    .padding(.vertical, 5)
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.22)).frame(height: 1) }
                }
                if items.count > 3 {
                    Button { tweaking = m } label: {
                        HStack {
                            Text("+\(items.count - 3) more").font(.footnote.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .padding(.vertical, 5)
                        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.22)).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all \(items.count) exercises")
                }
            }
            HStack(spacing: 6) {
                cardButton("Start now", symbol: "play.fill", primary: true) {
                    ProStore.shared.run(.generateWorkout, $gate) { playing = save(w) }
                }
                cardButton("Add to day", symbol: "calendar.badge.plus") {
                    ProStore.shared.run(.generateWorkout, $gate) { planning = save(w) }
                }
                cardButton("Tweak", symbol: "slider.horizontal.3") { tweaking = m }
            }
            .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .gradientCard(WorkoutEngine.Category.power.gradient, padding: 14)
        .opacity(latest ? 1 : 0.7)
    }

    private func cardButton(_ title: String, symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleOnly)
                .font(Theme.label(13))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(primary ? Theme.ink : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(primary ? Theme.lime : .white.opacity(0.24)))
        }
        .buttonStyle(.plain)
    }

    /// Starters before the first message, quick tweaks after a workout.
    @ViewBuilder private var chips: some View {
        let options: [String] = store.messages.isEmpty ? Self.starters
            : (store.messages.last?.workout != nil ? Self.tweaks : [])
        if !options.isEmpty, store.available != false, !sending {
            FlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { o in
                    Button { send(o) } label: {
                        Text(o).font(Theme.label(12)).foregroundStyle(.white)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 42)
        }
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // The keyboard's mic dictates (iOS), so no separate voice button.
                TextField("Tell Coach…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.body)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .onChange(of: draft) { if draft.count > 500 { draft = String(draft.prefix(500)) } }
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.4)
                .accessibilityLabel("Send")
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.1)))
            if let r = store.remaining, r <= 5 {
                Text(r == 0 ? "No messages left today. Coach is back tomorrow!" : "\(r) message\(r == 1 ? "" : "s") left today")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        !sending && store.available != false && store.remaining != 0
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending, store.available != false, store.remaining != 0 else { return }
        store.messages.append(CoachChatMessage(role: .member, text: t))
        draft = ""
        sending = true
        let history = store.messages
        let readiness = Readiness.assess(health.snapshot)?.0.title
        Task {
            defer { sending = false }
            do {
                let a = try await model.coachChat(history, readiness: readiness)
                store.remaining = a.remainingToday
                var reply = CoachChatMessage(role: .coach, text: a.reply)
                if let s = a.workout, let profile = model.profile {
                    let w = s.workout(profile: profile, seed: UInt32.random(in: .min ... .max))
                        .withFlow(CoachWorkoutSettings.flowMinutes, profile: profile)
                    if w.playableItems.isEmpty {
                        reply.text += (reply.text.isEmpty ? "" : " ") + "Hmm, nothing in your gym fits that. Try other muscles or equipment."
                    } else {
                        reply.workout = w
                        reply.settings = s
                    }
                }
                store.messages.append(reply)
            } catch {
                if case let APIError.server(_, code, message) = error {
                    if code == "daily_limit" { store.remaining = 0 }
                    if code == "coach_unavailable" { store.available = false }
                    store.messages.append(CoachChatMessage(role: .coach, text: message))
                } else {
                    store.messages.append(CoachChatMessage(role: .coach, text: "I couldn't reach the gym floor. Check your connection and try again."))
                }
            }
        }
    }

    /// Saves the workout to the member's workouts once (starting or planning it needs a saved workout).
    private func save(_ w: CustomWorkout) -> CustomWorkout {
        if model.customWorkout(w.id) == nil { return model.saveCustomWorkout(w) }
        return model.customWorkout(w.id) ?? w
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable = sending ? AnyHashable("typing") : AnyHashable("chips")
        if animated { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .bottom) } }
        else { proxy.scrollTo(target, anchor: .bottom) }
    }
}

#if DEBUG
extension Demo {
    /// Demo coach (no network): a shoulder-safe legs workout for any message.
    static func coachAnswer(_ text: String) throws -> CoachChatAnswer<CoachWorkoutSettings> {
        let json = #"""
        {"reply":"Legs it is, 45 minutes. I kept your shoulder out of it: no overhead work, no barbell on your back.",
         "workout":{"name":"Legs, shoulder-safe","minutes":45,"groups":["legs","hips"],"rest":"standard","grouping":"straight",
                    "avoidGroups":["shoulders"],"avoidEquipment":[],"avoidKeywords":[]},
         "remainingToday":17}
        """#
        return try JSONDecoder().decode(CoachChatAnswer<CoachWorkoutSettings>.self, from: Data(json.utf8))
    }

    /// Demo screen `coach-chat`: one exchange with its workout card.
    @MainActor static func fillCoachChat(profile: Profile) {
        let store = CoachChatStore.shared
        guard store.messages.isEmpty, let a = try? coachAnswer(""), let s = a.workout else { return }
        let w = s.workout(profile: profile, seed: 7).withFlow(CoachWorkoutSettings.flowMinutes, profile: profile)
        store.messages = [
            CoachChatMessage(role: .member, text: "45 min, legs, my shoulder is a bit sore"),
            CoachChatMessage(role: .coach, text: a.reply, workout: w, settings: s),
        ]
    }
}
#endif
