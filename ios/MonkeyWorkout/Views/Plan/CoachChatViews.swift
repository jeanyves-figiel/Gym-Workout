import APIClient
import PhotosUI
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
    /// "Open …" button (#412).
    var action: CoachChatAction?
    /// Follow-up questions to tap (#412).
    var suggestions: [String] = []
    /// Train around pain (#870): the plan Coach offers, with Apply.
    var protect: PainProtect?
    /// Answered by the on-device model (#608): badge + how long it took.
    var onDevice = false
    var seconds: Double?
    /// Exercises to add now (#856, freestyle), as ▶ / + cards.
    var exercises: [Exercise] = []
    /// The machine photo the member sent (#856), shown in their bubble; never sent again.
    var photo: UIImage?
    /// History question (#868 C): the answer card with its mini chart.
    var history: HistoryAnswer?
    /// Body measurements Coach logged (#1000): the card with Undo.
    var logged: LoggedMeasurement?
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
    /// What the coach knows about the member: goal, level, method, session length, gym, readiness, today's plan, pronouns,
    /// and what it remembers (#495).
    /// `focus`: the screen the member asks from (#412).
    func coachChatContext(readiness: String?, focus: CoachFocus? = nil) -> CoachChatContext {
        // How we talk to you (#415): the coach uses the member's pronouns and calls them what they picked.
        // A first name stays on the device: the coach writes {name} and the app fills it in.
        let pronouns = body.pronounsText, call = coachCallIsName ? Self.nameSlot : coachCallName
        guard let p = profile else {
            return CoachChatContext(readiness: readiness, screen: focus?.screen, focus: focus?.text, pronouns: pronouns, callName: call)
        }
        let today = nextSession.flatMap { $0.weekday == todayWeekday ? $0.displayTitle : nil }
        return CoachChatContext(goal: p.goal.rawValue, level: p.experience.rawValue, sessionMinutes: Generator.sessionMinutes(p),
                                equipment: p.equipment.map(\.rawValue), readiness: readiness, todayPlanned: today,
                                method: p.trainingMethod.rawValue, screen: focus?.screen, focus: focus?.text, pronouns: pronouns, callName: call,
                                // What the coach remembers (#495), within the server's limits.
                                memory: coachFacts.isEmpty ? nil : coachFacts.prefix(20).map { String($0.prefix(120)) },
                                // Building as they go (#856): the names Coach may hand back as exercises to add.
                                exercises: focus?.wantsExercises == true ? Freestyle.coachNames(profile: p) : nil)
    }

    /// Throws when the server can't be reached, so the chat shows an error card with Retry (#539).
    func coachChatStatus() async throws -> CoachChatStatus {
        #if DEBUG
        if demo { return CoachChatStatus(available: true, remainingToday: 18) }
        #endif
        return try await api.coachChatStatus()
    }

    /// Sends the conversation; the last message is the member's, with `photo` (JPEG) when they snapped a machine (#856).
    func coachChat(_ messages: [CoachChatMessage], readiness: String?, focus: CoachFocus? = nil, photo: Data? = nil) async throws
        -> CoachChatAnswer<CoachWorkoutSettings> {
        #if DEBUG
        if demo { return try Demo.coachAnswer(messages.last?.text ?? "", focus: focus) }
        #endif
        let name = coachCallIsName ? coachCallName : nil
        // The server takes the last 30 turns of up to 600 characters (#990): a long chat would otherwise be refused.
        let turns = messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.suffix(30).map { m in
            CoachChatTurn(role: m.role.rawValue, text: (m.role == .coach ? Self.slotName(m.text, name) : m.text).trimmingCharacters(in: .whitespacesAndNewlines).utf16Capped(600))
        }
        var answer = try await api.coachChat(turns, context: coachChatContext(readiness: readiness, focus: focus), photo: photo,
                                             as: CoachWorkoutSettings.self)
        answer.reply = Self.fillName(answer.reply, name)
        answer.suggestions = answer.suggestions?.map { Self.fillName($0, name) }
        return answer
    }

    static let nameSlot = "{name}"

    /// The coach's {name} → the member's first name (none: dropped with its comma).
    static func fillName(_ text: String, _ name: String?) -> String {
        guard let name else { return text.replacingOccurrences(of: ", " + nameSlot, with: "").replacingOccurrences(of: nameSlot, with: "") }
        return text.replacingOccurrences(of: nameSlot, with: name)
    }

    /// Earlier coach lines go back with {name} again, so the name never leaves the device.
    static func slotName(_ text: String, _ name: String?) -> String {
        guard let name, !name.isEmpty else { return text }
        return text.replacingOccurrences(of: name, with: nameSlot)
    }
}

/// Freestyle start screen hooks (#856): Coach's exercises start at once (▶) or line up (+) like the screen's own.
struct CoachFreestyle {
    /// What's lined up on the start screen, in order.
    var lined: Binding<[Exercise]>
    /// ▶: this one now, then what's lined up. None in the Add exercises picker (#934): + ticks it there.
    var start: ((Exercise) -> Void)?
}

/// The chat: a sheet from the 🐵 header tile and sparks (#412) that knows the screen.
struct CoachChatView: View {
    /// Asked from a screen (#412): its focus, a question to send, or listen at once.
    var ask: AskCoachRequest?
    /// Asked from the freestyle start screen (#856): exercise cards with ▶ / + and the 📷 machine photo.
    var freestyle: CoachFreestyle?
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var store = CoachChatStore.shared
    @State private var draft = ""
    @State private var sending = false
    /// Status didn't load (#539): error card with Retry above the greeting.
    @State private var statusError: String?
    @State private var gate: ProGate?
    @State private var playing: CustomWorkout?
    @State private var planning: CustomWorkout?
    @State private var tweaking: CoachChatMessage?
    @State private var listener = CoachListener()
    @State private var voice = CoachVoice()
    @State private var opening: CoachOpen?
    /// Form check (#833): exercise picker, then the camera.
    @State private var formPicking = false
    @State private var formFilming: Exercise?
    @State private var detent: PresentationDetent = .large
    /// The last question was spoken: read the answer aloud (#412).
    @State private var spoken = false
    /// Machine photo (#856): camera, or the photo library where there's no camera.
    @State private var snapping = false
    @State private var picking = false
    @State private var photoItem: PhotosPickerItem?
    /// Ids lined up on the start screen, mirrored here so the + marks update in the sheet (#856).
    @State private var linedIds: [String] = []
    @FocusState private var typing: Bool

    private var focus: CoachFocus? { ask?.focus }

    private static let starters = ["45 min full body", "Quick 20 min, I'm tired", "Legs, sore shoulder", "Upper body, no barbell"]
    private static let tweaks = ["Shorter", "Harder", "Easier", "No barbell", "Swap the first exercise"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let focus, focus.screen != "train", freestyle == nil { focusChip(focus) }
                            if let statusError {
                                InlineErrorCard(title: "Couldn't reach Coach", message: statusError) { Task { await loadStatus() } }
                            }
                            greeting
                            if store.messages.isEmpty {
                                FormCheckCoachTile(exercise: focusExercise, picking: $formPicking, filming: $formFilming)
                            }
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
            .sheet(isPresented: $formPicking) { FormCheckPicker { e in formFilming = e } }
            .fullScreenCover(item: $formFilming) { e in FormCheckView(exercise: e) }
            .fullScreenCover(isPresented: $snapping) {
                CameraPicker { if let img = $0 { send("", photo: img) } }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $picking, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) {
                guard let item = photoItem else { return }
                photoItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { send("", photo: img) }
                }
            }
            .sheet(item: $opening) { o in
                NavigationStack {
                    switch o {
                    case let .exercise(id): ExerciseDetailView(exerciseId: id)
                    case .calendar: CalendarView()
                    case .measurements: MeasurementsView()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents(ask == nil ? [.large] : [.medium, .large], selection: $detent)
        .task {
            store.rollOver()
            linedIds = freestyle?.lined.wrappedValue.map(\.id) ?? []
            await loadStatus()
            guard let ask else { return }
            if let q = ask.question { send(q, spoken: ask.spoken) }
            else if ask.listen { listen() }
            else if ask.photo { snap() }
        }
        .onDisappear {
            listener.cancel()
            voice.stop()
        }
    }

    /// The exercise on screen when Coach was opened from its page, if the camera can check it.
    private var focusExercise: Exercise? {
        guard let focus, focus.screen == "exercise", let e = Exercise.named(focus.title), FormModel.supports(e) else { return nil }
        return e
    }

    private func loadStatus() async {
        statusError = nil
        do {
            let s = try await model.coachChatStatus()
            store.available = s.available
            store.remaining = s.remainingToday
        } catch is CancellationError {
            // Closed: nothing to report.
        } catch {
            statusError = error.localizedDescription
        }
    }

    private func focusChip(_ f: CoachFocus) -> some View {
        Label("Looking at: \(f.title)", systemImage: "eyes")
            .font(Theme.label(12))
            .lineLimit(1)
            .foregroundStyle(Theme.lime)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .accessibilityLabel("Asking about \(f.title)")
    }

    // MARK: Messages

    private var greeting: some View {
        coachBubble(store.available == false && !OnDeviceCoach.available ? "Coach chat isn't switched on yet. Check back soon!" : hello)
    }

    private var hello: String {
        if focus?.screen == CoachFocus.pickerScreen { return "What are you after? Name a muscle or a machine, or snap the machine and I'll find its exercises." }
        if freestyle != nil { return "What do you want to hit now? Name a muscle, tell me the machine in front of you, or snap it." }
        if let focus, focus.screen != "train" { return "Ask me anything about \(focus.title), by text or voice." }
        return "Hey! What do you feel like today? Tell me your time, what to train and anything sore."
    }

    @ViewBuilder private func message(_ m: CoachChatMessage) -> some View {
        switch m.role {
        case .member:
            VStack(alignment: .trailing, spacing: 6) {
                if let photo = m.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Your photo of the machine")
                }
                Text(m.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 5, topTrailingRadius: 18)
                        .fill(Theme.lime))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
        case .coach:
            VStack(alignment: .leading, spacing: 10) {
                if m.onDevice { OnDeviceBadge(seconds: m.seconds) }
                if !m.text.isEmpty { coachBubble(m.text) }
                if !m.exercises.isEmpty, freestyle != nil { exerciseCards(m.exercises) }
                // No button to a tab the member hid (#1004).
                if let a = m.action, MainTab(rawValue: a.target).map(TabsPref.shared.shows) ?? true { actionButton(a) }
                if let h = m.history { HistoryAnswerCard(answer: h) { opening = .exercise($0) }.padding(.leading, 42) }
                if let p = m.protect { PainPlanCard(protect: p) }
                if let l = m.logged { loggedCard(m.id, l) }
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

    /// Measurements Coach logged (#1000): tap opens Measurements, Undo puts today's entry back.
    private func loggedCard(_ messageId: UUID, _ l: LoggedMeasurement) -> some View {
        HStack(spacing: 10) {
            Image(systemName: l.undone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(l.undone ? "UNDONE" : "LOGGED TODAY").font(Theme.label(11)).tracking(1.2).opacity(0.7)
                Text(l.summary.prefix(1).uppercased() + l.summary.dropFirst())
                    .font(Theme.label(15))
                    .strikethrough(l.undone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if !l.undone {
                Button { undoLogged(messageId) } label: {
                    Text("Undo").font(Theme.label(13)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.ink))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.logged.undo")
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime))
        .contentShape(Rectangle())
        .onTapGesture { opening = .measurements }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Undo") { undoLogged(messageId) }
        .padding(.leading, 42)
    }

    private func undoLogged(_ messageId: UUID) {
        guard let i = store.messages.firstIndex(where: { $0.id == messageId }), let l = store.messages[i].logged, !l.undone else { return }
        model.undoLogged(l)
        store.messages[i].logged?.undone = true
        Haptics.undo()
    }

    /// Coach's "Open …" button (#412).
    private func actionButton(_ a: CoachChatAction) -> some View {
        Button { open(a) } label: {
            Label(a.label, systemImage: a.target == "exercise" ? "figure.strengthtraining.traditional" : "arrow.up.right")
                .font(Theme.label(13))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
        .padding(.leading, 42)
    }

    private func open(_ a: CoachChatAction) {
        switch a.target {
        case "progress": go(.progress)
        case "explore": go(.explore)
        case "settings":
            dismiss()
            Task { try? await Task.sleep(for: .milliseconds(450)); model.settingsOpen = true }
        case "fuel": go(.fuel)
        case "calendar": opening = .calendar
        default:
            if let e = a.exercise.flatMap({ Exercise.named($0) }) { opening = .exercise(e.id) }
        }
    }

    private func go(_ tab: MainTab) {
        model.tab = tab
        dismiss()
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
                    planning = save(w)
                }
                cardButton("Tweak", symbol: "slider.horizontal.3") { tweaking = m }
            }
            .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .gradientCard(WorkoutEngine.Category.power.gradient, padding: 14)
        .opacity(latest ? 1 : 0.7)
    }

    /// Coach's exercises on the freestyle screen (#856, design A + B): ▶ starts it now, + lines it up (the number once
    /// lined up), and "Line up all" for the rest. In the Add exercises picker (#934) + ticks it, no ▶.
    private func exerciseCards(_ list: [Exercise]) -> some View {
        let fresh = list.filter { !linedIds.contains($0.id) }
        return VStack(spacing: 6) {
            ForEach(list, id: \.id) { e in
                let at = linedIds.firstIndex(of: e.id)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.name).font(Theme.label(14)).lineLimit(2).minimumScaleFactor(0.8)
                        Text(e.primary.first?.group.label ?? e.category.label).font(Theme.label(10)).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button { line(e) } label: { FreestyleLineMark(position: at.map { $0 + 1 }, size: 34) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(at == nil ? (freestyle?.start == nil ? "Add \(e.name)" : "Line up \(e.name)") : "Take \(e.name) out of the line-up")
                    if freestyle?.start != nil {
                        Button { startNow(e) } label: { FreestylePlayMark(size: 34) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start \(e.name) now")
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(e.primary.first?.group.gradient ?? WorkoutEngine.Category.strength.gradient))
            }
            if fresh.count > 1 {
                Button { fresh.forEach { line($0) } } label: {
                    Label(freestyle?.start == nil ? "Add all \(fresh.count)" : "Line up all \(fresh.count)", systemImage: "plus")
                        .font(Theme.label(13)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 42)
    }

    /// + on a Coach card: lines it up on the start screen, tapped again takes it out.
    private func line(_ e: Exercise) {
        guard let lined = freestyle?.lined else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            if let i = lined.wrappedValue.firstIndex(where: { $0.id == e.id }) { lined.wrappedValue.remove(at: i) } else { lined.wrappedValue.append(e) }
            linedIds = lined.wrappedValue.map(\.id)
        }
    }

    private func startNow(_ e: Exercise) {
        freestyle?.start?(e)
        dismiss()
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
        let last = store.messages.last
        let options: [String] = store.messages.isEmpty ? (focus?.starters.isEmpty == false ? focus!.starters : Self.starters)
            : (last?.workout != nil ? Self.tweaks : (last?.role == .coach ? last?.suggestions ?? [] : []))
        if !options.isEmpty, serverOpen || OnDeviceCoach.available, !sending {
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
                if listener.listening {
                    ListeningBars()
                    Text(listener.text.isEmpty ? "Listening…" : listener.text)
                        .font(.body).foregroundStyle(.white).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Tell Coach…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.body)
                        .focused($typing)
                        .submitLabel(.send)
                        .onSubmit { send(draft) }
                        .onChange(of: draft) { if draft.count > 500 { draft = String(draft.prefix(500)) } }
                }
                // Freestyle (#856): snap the machine in front of you.
                if freestyle != nil, draft.isEmpty, !listener.listening {
                    Button(action: snap) {
                        Image(systemName: "camera.fill").font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.14)))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSnap)
                    .opacity(canSnap ? 1 : 0.4)
                    .accessibilityLabel("Snap the machine")
                    .accessibilityIdentifier("askCoach.photo")
                }
                // Empty field: the mic (#412), on-device speech-to-text; tap again to send now.
                if draft.isEmpty {
                    Button { listener.listening ? listener.finish() : listen() } label: {
                        Image(systemName: listener.listening ? "stop.fill" : "mic.fill").font(.system(size: 16, weight: .black))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.lime))
                            // 44 pt hit area around the 34 pt tile (#540).
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canTalk)
                    .opacity(canTalk ? 1 : 0.4)
                    .accessibilityLabel(listener.listening ? "Stop and send" : "Talk to Coach")
                    .accessibilityIdentifier("askCoach.mic")
                } else {
                    Button { send(draft) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .black))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.lime))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.4)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.leading, 16).padding(.trailing, 1).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.1)))
            if let p = listener.problem {
                Text(p).font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted).padding(.leading, 16)
            }
            if let r = store.remaining, r <= 5 {
                Text(r == 0 ? "No messages left today. Coach is back at \(Self.quotaReset.formatted(date: .omitted, time: .shortened))." : "\(r) message\(r == 1 ? "" : "s") left today")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 8)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        canTalk && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The on-device Coach (#608) keeps answering when the server one is off or out of messages.
    private var canTalk: Bool { !sending && (serverOpen || OnDeviceCoach.available) }
    private var serverOpen: Bool { store.available != false && store.remaining != 0 }

    /// A photo needs the server Coach (the on-device one can't see).
    private var canSnap: Bool { !sending && serverOpen }

    private func snap() {
        guard canSnap else { return }
        voice.stop()
        typing = false
        if UIImagePickerController.isSourceTypeAvailable(.camera) { snapping = true } else { picking = true }
    }

    private func listen() {
        guard canTalk else { return }
        voice.stop()
        typing = false
        listener.start { said in send(said, spoken: true) }
    }

    private func send(_ text: String, spoken: Bool = false, photo: UIImage? = nil) {
        var said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A machine photo (#856) asks what to do on it unless the member typed something.
        let jpeg: Data?
        if let photo {
            jpeg = GymScanSheet.jpeg(photo)
            guard jpeg != nil else {
                store.messages.append(CoachChatMessage(role: .coach, text: "I couldn't read that photo. Try another one."))
                return
            }
            if said.isEmpty { said = "What can I do on this machine?" }
        } else {
            jpeg = nil
        }
        let t = said
        // "Check my form" opens the camera (#833) instead of a chat answer.
        if FormCheckCoachTile.asks(t) {
            draft = ""
            if let e = focusExercise { formFilming = e } else { formPicking = true }
            return
        }
        guard !t.isEmpty, !sending else { return }
        // "Weight is now 66" (#1000): logged on the iPhone at once, free, even offline or with Coach's AI off.
        if photo == nil, let said = MeasurementSay.parse(t) {
            store.messages.append(CoachChatMessage(role: .member, text: t))
            draft = ""
            self.spoken = spoken
            store.messages.append(CoachChatMessage(role: .coach, text: "Done, it's on today's entry.", onDevice: true, logged: model.logSaid(said)))
            speak("Logged \(said.summary).")
            return
        }
        // About the logged workouts (#868 C): answered on the iPhone with a chart card, free, even when chat is off.
        if photo == nil, HistoryAsk.answer(t, records: model.state.history) != nil {
            store.messages.append(CoachChatMessage(role: .member, text: t))
            draft = ""
            sending = true
            self.spoken = spoken
            let records = model.state.history
            Task {
                defer { sending = false }
                guard let r = await HistoryAskService.ask(t, records: records) else { return }
                store.messages.append(CoachChatMessage(role: .coach, text: r.text, onDevice: true, seconds: r.seconds, history: r.answer))
                speak(r.text)
            }
            return
        }
        guard canTalk else { return }
        store.messages.append(CoachChatMessage(role: .member, text: t, photo: photo))
        draft = ""
        sending = true
        self.spoken = spoken
        let history = store.messages
        let readiness = Readiness.assess(health.snapshot)?.0.title
        let focus = focus
        // Short questions, or no server Coach: the on-device model answers (#608 A).
        let local = jpeg == nil && OnDeviceCoach.available && (CoachRoute.onDevice(t) || !serverOpen)
        let about = model.onDeviceCoachAbout(focus: focus)
        Task {
            defer { sending = false }
            if local, await answerOnDevice(t, about: about, history: Array(history.dropLast())) { return }
            guard serverOpen else {
                store.messages.append(CoachChatMessage(role: .coach, text: "I couldn't answer that one here. Try again later."))
                return
            }
            do {
                let a = try await model.coachChat(history, readiness: readiness, focus: focus, photo: jpeg)
                store.remaining = a.remainingToday
                var reply = CoachChatMessage(role: .coach, text: a.reply, action: a.action, suggestions: a.suggestions ?? [])
                var seen = Set<String>()
                reply.exercises = (a.exercises ?? []).compactMap { Exercise.named($0) }.filter { seen.insert($0.id).inserted }
                reply.protect = a.protect.flatMap(PainProtect.init(chat:))
                // Coach logs what the member told it (#1000), with Undo on the card.
                if let m = a.measurement.map(MeasurementSay.init(chat:)), !m.isEmpty { reply.logged = model.logSaid(m) }
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
                speak(reply.text)
            } catch {
                if case let APIError.server(_, code, message) = error {
                    if code == "daily_limit" { store.remaining = 0 }
                    if code == "coach_unavailable" { store.available = false }
                    store.messages.append(CoachChatMessage(role: .coach, text: message))
                } else if jpeg == nil, OnDeviceCoach.available, await answerOnDevice(t, about: about, history: Array(history.dropLast())) {
                    // No signal (#608 A): the on-device Coach answers instead.
                } else {
                    store.messages.append(CoachChatMessage(role: .coach, text: "I couldn't reach the gym floor. Check your connection and try again."))
                }
            }
        }
    }

    /// On-device answer (#608 A); false when the model couldn't answer, so the server Coach can.
    /// The daily message allowance turns over at midnight UTC on the server (#989), shown in local time.
    static var quotaReset: Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? Date()
    }

    private func answerOnDevice(_ question: String, about: String, history: [CoachChatMessage]) async -> Bool {
        let start = Date()
        guard let text = try? await OnDeviceCoach.answer(question, about: about, history: history) else { return false }
        let reply = CoachChatMessage(role: .coach, text: text, onDevice: true, seconds: Date().timeIntervalSince(start))
        store.messages.append(reply)
        speak(reply.text)
        return true
    }

    /// Reads the answer aloud (#412): after a spoken question, or always / never per Settings.
    private func speak(_ text: String) {
        let mode = AskCoachPref.speak
        guard mode == .always || (mode == .whenTalking && spoken), !text.isEmpty, !model.demo else { return }
        voice.speak(text, style: CoachPref.style)
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
    /// Demo coach (no network): a shoulder-safe legs workout for any message; a form tip with an open button when asked
    /// from an exercise (#412).
    static func coachAnswer(_ text: String, focus: CoachFocus? = nil) throws -> CoachChatAnswer<CoachWorkoutSettings> {
        if focus?.wantsExercises == true {
            let json = #"""
            {"reply":"That's a cable stack with a rope: perfect for triceps. Start with pushdowns, elbows pinned to your sides.",
             "workout":null,"action":null,"exercises":["Cable triceps pushdown","Face pull","Straight-arm pulldown"],
             "suggestions":["Something harder","Add biceps"],"remainingToday":17}
            """#
            return try JSONDecoder().decode(CoachChatAnswer<CoachWorkoutSettings>.self, from: Data(json.utf8))
        }
        if focus?.screen == "exercise" || focus?.screen == "player" {
            let json = #"""
            {"reply":"Tuck your elbows to about 45 degrees and grip a little narrower. Still clicking? Swap to the neutral-grip dumbbell press.",
             "workout":null,"action":{"target":"exercise","exercise":"Dumbbell bench press","label":"Open DB bench press"},
             "suggestions":["Show form cues","Lighter weight?"],"remainingToday":17}
            """#
            return try JSONDecoder().decode(CoachChatAnswer<CoachWorkoutSettings>.self, from: Data(json.utf8))
        }
        let json = #"""
        {"reply":"Legs it is, 45 minutes. I kept your shoulder out of it: no overhead work, no barbell on your back.",
         "workout":{"name":"Legs, shoulder-safe","minutes":45,"groups":["legs","hips"],"rest":"standard","grouping":"straight",
                    "avoidGroups":["shoulders"],"avoidEquipment":[],
                    "avoidKeywords":["back squat","box squat","front squat","smith-squat","good-morning"]},
         "remainingToday":17}
        """#
        // The reply promises "no barbell on your back": the settings now say so too (#823), so the card no longer
        // lists Barbell back squat or Smith machine squat right under it.
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

/// Screens the coach's button opens in the chat sheet (#412).
enum CoachOpen: Identifiable {
    case exercise(String)
    case calendar
    case measurements

    var id: String {
        switch self {
        case let .exercise(e): "exercise-\(e)"
        case .calendar: "calendar"
        case .measurements: "measurements"
        }
    }
}
