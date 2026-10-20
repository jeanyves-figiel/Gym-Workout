import SwiftUI
import WorkoutEngine

// MARK: - Library entries

/// One workout in the library, whatever its source.
struct LibraryEntry: Identifiable, Hashable {
    enum Source: Hashable {
        case mine(CustomWorkout)
        case builtIn(WorkoutTemplate)
        case member(SharedWorkout)
    }

    let source: Source

    var id: String { session.id }

    var session: Session {
        switch source {
        case let .mine(w): w.session
        case let .builtIn(t): t.session
        case let .member(s): s.workout.session
        }
    }

    var name: String {
        switch source {
        case let .mine(w): w.name
        case let .builtIn(t): t.name
        case let .member(s): s.name
        }
    }

    /// First subtitle line: the muscles the workout targets (#252).
    var muscleLine: String { session.workMuscles(3).map(\.name).joined(separator: " · ") }

    /// Second subtitle line: size and source facts.
    var detail: String {
        let count = session.blocks.reduce(0) { $0 + $1.items.count }
        switch source {
        case let .mine(w):
            return (["\(count) exercises", w.kcal.map { "\($0) kcal" }]).compactMap { $0 }.joined(separator: " · ")
        case let .builtIn(t):
            return "\(count) exercises · \(t.kit) · \(t.levelLabel)"
        case let .member(sw):
            return (["by @\(sw.author.nickname)", "\(count) exercises"] + (sw.saves > 0 ? ["♥ \(sw.saves)"] : [])).joined(separator: " · ")
        }
    }

    /// What it is for: filter chips in Explore.
    var goal: WorkoutTemplate.Goal {
        if case let .builtIn(t) = source { return t.goal }
        return WorkoutTemplate.Goal(session)
    }

    /// Free-text search: name, every muscle and muscle group worked, goal, kit and the detail line.
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let muscles = session.blocks.flatMap(\.items).flatMap { item -> [Muscle] in
            let e = Exercise.get(item.exerciseId)
            return e.primary + e.secondary
        }
        let text = ([name, detail, goal.label, session.focus.label] + muscles.map(\.name) + muscles.map(\.group.label))
            .joined(separator: " ").lowercased()
        return words.allSatisfy { text.contains($0) }
    }

    /// Small tag on shared or reported workouts of mine.
    var badge: String? {
        guard case let .mine(w) = source else { return nil }
        if w.hidden { return "HIDDEN" }
        return w.visibility == .private ? nil : w.visibility.label.uppercased()
    }

    /// Most common exercise category: the card's icon.
    var mainCategory: WorkoutEngine.Category { session.mainCategory }

    /// Vivid card colours from where the work sits (Explore style).
    var palette: WorkoutEngine.Category { session.palette }
}

extension Session {
    /// Most common exercise category: a card's icon.
    var mainCategory: WorkoutEngine.Category {
        let exercises = blocks.flatMap(\.items).map { Exercise.get($0.exerciseId) }
        let counts = Dictionary(grouping: exercises, by: \.category).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? .strength
    }

    /// Vivid card colours from where the work sits (Explore style).
    var palette: WorkoutEngine.Category {
        let top = mainCategory
        if top != .strength { return top }
        switch focus {
        case .lower, .fullLower, .legs: return .warmup
        case .upper, .fullUpper: return .mobility
        case .push, .fullPower: return .power
        case .conditioning: return .cardio
        case .pull: return .strength
        case .chestTri, .backBi, .shouldersArms, .chestBack, .posterior: return focus.palette
        }
    }
}

extension AppModel {
    var myLibrary: [LibraryEntry] { customWorkouts.map { LibraryEntry(source: .mine($0)) } }
    var builtInLibrary: [LibraryEntry] { WorkoutTemplate.all.map { LibraryEntry(source: .builtIn($0)) } }
    var memberLibrary: [LibraryEntry] { sharedLibrary.map { LibraryEntry(source: .member($0)) } }

    /// Navigation title for a standalone or planned library workout.
    func libraryTitle(_ s: Session) -> String? {
        if s.isPlanInsert { return s.dayLabel }
        if customWorkout(sessionId: s.id) != nil { return "My workout" }
        if sharedWorkout(sessionId: s.id) != nil { return "Member workout" }
        if s.isExample { return "Built-in workout" }
        return nil
    }
}

// MARK: - Explore tab section

/// Explore → Workouts: my workouts and built-in ones, with the full library (members, search) one tap away.
struct WorkoutLibrarySection: View {
    @Environment(AppModel.self) private var model
    @State private var editing: CustomWorkout?
    @State private var gate: ProGate?
    /// Goal chip (#252); nil = all.
    @State private var goal: WorkoutTemplate.Goal?
    @State private var query = ""
    @FocusState private var searching: Bool

    private var all: [LibraryEntry] { model.myLibrary + model.builtInLibrary }
    private var preview: [LibraryEntry] { all.filter { (goal == nil || $0.goal == goal) && $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workout library").eyebrow()
                Spacer()
                ProBadge()
                Button { ProStore.shared.run(.buildWorkout, $gate) { editing = CustomWorkout(name: "") } } label: { Label("New", systemImage: "plus") }
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.lime)
            }
            searchField
            goalChips
            ForEach(preview) { e in
                NavigationLink(value: e.session.id) { LibraryCard(entry: e, done: model.state.done[e.session.id] ?? false) }
                    .buttonStyle(.plain)
            }
            if preview.isEmpty {
                Text("No workout matches. Try a muscle (\"glutes\"), a goal (\"cardio\") or clear the filter.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            }
            NavigationLink { WorkoutLibraryView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.lime)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.lime.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Browse all workouts").font(.system(.headline, design: .rounded).weight(.heavy))
                        Text("Search the library, including workouts shared by members. Start one now or add it to your plan.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
        .sheet(item: $editing) { w in CustomWorkoutEditor(initial: w) }
        .proPaywall($gate)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.body.weight(.bold)).foregroundStyle(Theme.muted)
            TextField("Name, muscle or goal", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searching)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .font(.body.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var goalChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "All", all.count)
                ForEach(WorkoutTemplate.Goal.allCases, id: \.self) { g in
                    let n = all.filter { $0.goal == g }.count
                    if n > 0 { chip(g, g.label, n) }
                }
            }
        }
    }

    private func chip(_ g: WorkoutTemplate.Goal?, _ label: String, _ n: Int) -> some View {
        Button { withAnimation(.snappy) { goal = g } } label: {
            Text("\(label) \(n)")
                .font(Theme.label(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(goal == g ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.08))))
                .foregroundStyle(goal == g ? Theme.ink : .white)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(goal == g ? .isSelected : [])
    }
}

/// Explore-style card: icon tile left, heavy name, big minutes right, on a vivid gradient.
struct LibraryCard: View {
    let entry: LibraryEntry
    var done = false

    var body: some View {
        let palette = entry.palette
        HStack(spacing: 14) {
            Image(systemName: entry.mainCategory.symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.name).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.8)
                    if let badge = entry.badge {
                        Text(badge).font(Theme.label(9)).tracking(0.8)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.3)))
                    }
                }
                // Two short lines instead of one cut line (#252).
                if !entry.muscleLine.isEmpty {
                    Text(entry.muscleLine).font(.footnote.weight(.semibold)).opacity(0.92).lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(entry.detail).font(.caption.weight(.semibold)).opacity(0.8).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            if done {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 26, weight: .bold))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(entry.session.estMin)").font(Theme.display(28)).monospacedDigit()
                    Text(" min").font(Theme.label(13))
                }
                .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(palette.gradient))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Full library

struct WorkoutLibraryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", mine = "Mine", builtIn = "Built-in", members = "Members"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var memberState: AppModel.SharedLibraryLoad?
    @State private var editing: CustomWorkout?
    @State private var gate: ProGate?
    /// Build as I go (#490): the empty workout open in the player.
    @State private var freestyle: Session?
    /// Pick mode (#178, Add workout → Browse library): tapping a workout hands it over instead of opening it.
    private let onPick: ((LibraryEntry) -> Void)?

    init(onPick: ((LibraryEntry) -> Void)? = nil) {
        self.onPick = onPick
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ContentTitle(title: "Workout library")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { f in
                            Button { withAnimation(.snappy) { filter = f } } label: {
                                Text("\(f.rawValue) \(count(f))")
                                    .font(Theme.label(14))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Capsule().fill(filter == f ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.08))))
                                    .foregroundStyle(filter == f ? Theme.ink : .white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if onPick == nil, query.isEmpty {
                    FreestyleCard(resuming: model.freestyleInProgress != nil) {
                        freestyle = model.freestyleInProgress ?? model.startFreestyle()
                    }
                }
                if filter == .all || filter == .mine {
                    section("My workouts", entries(model.myLibrary)) {
                        if onPick == nil {
                            Button { ProStore.shared.run(.buildWorkout, $gate) { editing = CustomWorkout(name: "") } } label: {
                                HStack {
                                    Label("Build your own workout", systemImage: "square.and.pencil")
                                        .font(Theme.label(15))
                                        .foregroundStyle(Theme.lime)
                                    Spacer()
                                    ProBadge()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if filter == .all || filter == .builtIn {
                    section("Built-in", entries(model.builtInLibrary)) { EmptyView() }
                }
                if filter == .all || filter == .members {
                    section("From members", entries(model.memberLibrary)) { membersFooter }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        // Title in the content (#539), not under the toolbar's glass buttons.
        .titleInContent("Workout library")
        .searchable(text: $query, prompt: "Name, muscle or goal")
        .onSubmit(of: .search) { Task { memberState = await model.loadSharedLibrary(query: query) } }
        .task { memberState = await model.loadSharedLibrary() }
        .refreshable { memberState = await model.loadSharedLibrary(query: query) }
        .toolbar {
            if onPick == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ProStore.shared.run(.buildWorkout, $gate) { editing = CustomWorkout(name: "") } } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New workout")
                }
            }
        }
        .sheet(item: $editing) { w in CustomWorkoutEditor(initial: w) }
        .fullScreenCover(item: $freestyle) { s in WorkoutPlayerView(sessionId: s.id) }
        .proPaywall($gate)
    }

    private func entries(_ list: [LibraryEntry]) -> [LibraryEntry] {
        list.filter { $0.matches(query) }
    }

    private func count(_ f: Filter) -> Int {
        switch f {
        case .all: model.myLibrary.count + model.builtInLibrary.count + model.memberLibrary.count
        case .mine: model.myLibrary.count
        case .builtIn: model.builtInLibrary.count
        case .members: model.memberLibrary.count
        }
    }

    @ViewBuilder
    private func section<Footer: View>(_ title: String, _ list: [LibraryEntry], @ViewBuilder footer: () -> Footer) -> some View {
        Text(title).eyebrow().padding(.top, 10)
        ForEach(list) { e in
            if let onPick {
                Button { onPick(e) } label: { LibraryCard(entry: e) }
                    .buttonStyle(.plain)
            } else {
                NavigationLink(value: e.session.id) { LibraryCard(entry: e, done: model.state.done[e.session.id] ?? false) }
                    .buttonStyle(.plain)
            }
        }
        footer()
    }

    @ViewBuilder
    private var membersFooter: some View {
        switch memberState {
        case nil:
            ProgressView().frame(maxWidth: .infinity).padding()
        case .needsCommunityProfile:
            NavigationLink { CommunityView() } label: {
                hint("person.2.fill", "Join the community", "Create your Community profile to see workouts other members share, and to share yours.")
            }
            .buttonStyle(.plain)
        case let .failed(message):
            hint("icloud.slash", "Couldn't load member workouts", message)
        case .loaded where model.memberLibrary.isEmpty:
            hint("sparkles", "Nothing shared yet", "Share one of your workouts with members from its page: set it to Members or Public.")
        case .loaded:
            EmptyView()
        }
    }

    private func hint(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.lime)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.headline, design: .rounded).weight(.heavy))
                Text(text).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}

// MARK: - Workout page panel

/// On a library workout's page: add to plan, share (mine), save a copy / report / block (members'),
/// or take a planned one back out. "Start workout" below runs it as a quick session.
struct LibraryActionsPanel: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @State private var planning: CustomWorkout?
    @State private var reporting = false
    @State private var confirmBlock = false
    @State private var confirmRemove = false
    @State private var notice: String?
    @State private var gate: ProGate?

    var body: some View {
        if session.isPlanInsert {
            plannedPanel
        } else if session.isStandalone, let workout = model.libraryWorkout(for: session) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    pill("Add to plan", "calendar.badge.plus") { planning = workout }
                    if let shared = model.sharedWorkout(sessionId: session.id) {
                        pill("Save copy", "plus.square.on.square") {
                            model.saveCopy(of: shared)
                            notice = "Saved to My workouts."
                        }
                    }
                }
                if let mine = model.customWorkout(sessionId: session.id) {
                    visibilityPicker(mine)
                } else if let shared = model.sharedWorkout(sessionId: session.id) {
                    authorRow(shared)
                }
                if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime)
                }
            }
            .sheet(item: $planning) { w in AddToPlanSheet(workout: w) { notice = $0 } }
        }
    }

    private var plannedPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.lime)
            VStack(alignment: .leading, spacing: 2) {
                Text(isExtra ? "Extra session" : "From your library").font(.system(.headline, design: .rounded).weight(.heavy))
                Text(isExtra ? "Added to this week." : "Placed into this week's plan.").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Remove") { confirmRemove = true }
                .font(Theme.label(13))
                .foregroundStyle(Theme.lime)
        }
        .card()
        .confirmationDialog("Remove from this week?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove from plan", role: .destructive) {
                if let id = session.planInsertId { model.removePlanInsert(id) }
            }
        } message: {
            Text(isExtra ? "It comes off this week's plan." : "A replaced day goes back to its planned session.")
        }
    }

    private var isExtra: Bool { model.planInsert(for: session)?.replacing == nil }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.label(15))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func visibilityPicker(_ w: CustomWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who can see it").eyebrow()
            GradientSegments(selection: Binding(get: { w.visibility }, set: { v in
                if v == .private { model.setVisibility(w.id, v) } else { ProStore.shared.run(.shareWorkout, $gate) { model.setVisibility(w.id, v) } }
            }), items: WorkoutVisibility.allCases.map { SegmentItem(value: $0, title: $0.label, symbol: $0.symbol) })
            Text(w.hidden
                 ? "Hidden from members after reports, pending review."
                 : w.visibility == .private ? "Only you see it." : "Members can find it in their library, start it and save a copy.")
                .font(.caption)
                .foregroundStyle(w.hidden ? .orange : Theme.muted)
        }
        .proPaywall($gate)
    }

    private func authorRow(_ s: SharedWorkout) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(s.author.nickname)").font(.system(.subheadline, design: .rounded).weight(.heavy))
                Text(s.saves == 1 ? "Saved once" : "Saved \(s.saves) times").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Menu {
                Button("Report workout", systemImage: "exclamationmark.bubble") { reporting = true }
                Button("Block @\(s.author.nickname)", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(Theme.muted)
            }
            .accessibilityLabel("Report or block")
        }
        .card(padding: 12)
        .confirmationDialog("Report this workout", isPresented: $reporting, titleVisibility: .visible) {
            ForEach([("spam", "Spam"), ("harassment", "Harassment"), ("hate", "Hate"), ("sexual", "Sexual content"), ("violence", "Violence"), ("other", "Other")], id: \.0) { r in
                Button(r.1) { Task { await run { try await model.report(s, reason: r.0, details: nil) }; notice = "Thanks, we'll review it." } }
            }
        } message: {
            Text("It disappears from your library. Reported workouts are reviewed.")
        }
        .confirmationDialog("Block @\(s.author.nickname)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await run { try await model.block(s.author) }; notice = "Blocked." } }
        } message: {
            Text("You won't see each other's workouts or posts. Undo in Community settings.")
        }
    }

    private func run(_ op: () async throws -> Void) async {
        do { try await op() } catch { notice = error.localizedDescription }
    }
}

// MARK: - Add to plan

/// Replace a session of this week, or add the workout as an extra session (optionally on a weekday).
struct AddToPlanSheet: View {
    let workout: CustomWorkout
    var onDone: (String) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// nil = extra session.
    @State private var replacing: Int?
    @State private var extraDay: Int?
    @State private var pickedExtra = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Week \(model.plan?.week ?? 1) · \(Generator.phaseName(model.plan?.week ?? 1)): replace a planned day, or add an extra session. A new variation keeps it; changing week clears it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 6)
                    ForEach(Array(model.replaceableSessions.enumerated()), id: \.offset) { i, pair in
                        let done = model.state.done[pair.current.id] ?? false
                        let card = dayCard(number: i + 1, session: pair.current,
                                           day: pair.current.weekday.map { WeekSchedule.name($0).uppercased() } ?? "DAY \(i + 1)",
                                           note: done ? "DONE" : pair.current.isPlanInsert ? "FROM LIBRARY" : nil,
                                           done: done, selected: replacing == i && !pickedExtra)
                        if done {
                            // Not a button: a disabled one would grey the text out on the dark canvas.
                            card
                        } else {
                            Button { replacing = i; pickedExtra = false } label: { card }
                                .buttonStyle(.plain)
                        }
                    }
                    Button { pickedExtra = true; replacing = nil } label: { extraCard }
                        .buttonStyle(.plain)
                    if pickedExtra {
                        Picker("Day", selection: $extraDay) {
                            Text("Any day").tag(Int?.none)
                            ForEach(1...7, id: \.self) { d in Text(WeekSchedule.name(d)).tag(Int?.some(d)) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.lime)
                    }
                    // Right under the days: no empty gap between the list and the action.
                    Button(confirmTitle) {
                        model.insertIntoPlan(workout, replacing: pickedExtra ? nil : replacing, weekday: extraDay)
                        onDone(pickedExtra ? "Added to this week." : "Placed into this week's plan.")
                        dismiss()
                    }
                    .buttonStyle(LimeButtonStyle(fill: canConfirm ? Theme.lime : Theme.cardStrong,
                                                 text: canConfirm ? Theme.ink : Color.white.opacity(0.6)))
                    .disabled(!canConfirm)
                    .padding(.top, 10)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add to plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.large])
    }

    private var canConfirm: Bool { pickedExtra || replacing != nil }

    private var confirmTitle: String {
        if pickedExtra { return "Add extra session" }
        guard let r = replacing, model.replaceableSessions.indices.contains(r) else { return "Pick a day" }
        return "Replace " + (model.replaceableSessions[r].current.weekday.map { WeekSchedule.name($0) } ?? "day \(r + 1)")
    }

    /// Explore-style day card: number tile, session name, weekday; done days stay readable, just calmer.
    private func dayCard(number: Int, session: Session, day: String, note: String?, done: Bool, selected: Bool) -> some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", number))
                .font(Theme.display(22))
                .monospacedDigit()
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle).font(Theme.display(20)).lineLimit(2).minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Text(day).font(Theme.label(11)).tracking(1)
                    if let note {
                        Text(note).font(Theme.label(10)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.3)))
                    }
                }
                .opacity(0.9)
            }
            Spacer(minLength: 4)
            if done {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 26, weight: .bold))
            } else {
                Text("Replace").font(Theme.label(12))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(selected ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.25))))
                    .foregroundStyle(selected ? Theme.ink : .white)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(session.palette.gradient)
                .saturation(done ? 0.15 : 1)
                .brightness(done ? -0.15 : 0)
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var extraCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.lime)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Extra session").font(Theme.display(20))
                Text(extraDay.map { WeekSchedule.name($0).uppercased() } ?? "ANY DAY")
                    .font(Theme.label(11)).tracking(1).foregroundStyle(Theme.lime)
            }
            Spacer(minLength: 4)
            Text("Add").font(Theme.label(12))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(pickedExtra ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.12))))
                .foregroundStyle(pickedExtra ? Theme.ink : .white)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.lime.opacity(pickedExtra ? 1 : 0.6), style: StrokeStyle(lineWidth: pickedExtra ? 3 : 1.5, dash: pickedExtra ? [] : [6, 4]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityAddTraits(pickedExtra ? .isSelected : [])
    }
}
