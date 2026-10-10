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

    var detail: String {
        let s = session
        let count = s.blocks.reduce(0) { $0 + $1.items.count }
        let muscles = s.topMuscles(2).map(\.name)
        switch source {
        case let .mine(w):
            return ([w.kcal.map { "\($0) kcal" }, "\(count) exercises"] + muscles).compactMap { $0 }.joined(separator: " · ")
        case let .builtIn(t):
            return "\(count) exercises · \(t.kcal) kcal · \(t.activityPoints) pts"
        case let .member(sw):
            return (["by @\(sw.author.nickname)", "\(count) exercises"] + (sw.saves > 0 ? ["♥ \(sw.saves)"] : [])).joined(separator: " · ")
        }
    }

    /// Small tag on shared or reported workouts of mine.
    var badge: String? {
        guard case let .mine(w) = source else { return nil }
        if w.hidden { return "HIDDEN" }
        return w.visibility == .private ? nil : w.visibility.label.uppercased()
    }

    /// Vivid card colours from where the work sits (Explore style).
    var palette: WorkoutEngine.Category {
        let s = session
        let exercises = s.blocks.flatMap(\.items).map { Exercise.get($0.exerciseId) }
        let counts = Dictionary(grouping: exercises, by: \.category).mapValues(\.count)
        if let top = counts.max(by: { $0.value < $1.value })?.key, top != .strength { return top }
        switch s.focus {
        case .lower, .fullLower, .legs: return .warmup
        case .upper, .fullUpper: return .mobility
        case .push, .fullPower: return .power
        case .conditioning: return .cardio
        case .pull: return .strength
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

// MARK: - Train tab section

/// Train tab: the workout library in short (my workouts, then built-in), with the full library one tap away.
struct WorkoutLibrarySection: View {
    @Environment(AppModel.self) private var model
    @State private var editing: CustomWorkout?

    private var preview: [LibraryEntry] { Array((model.myLibrary + model.builtInLibrary).prefix(4)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workout library").eyebrow()
                Spacer()
                Button { editing = CustomWorkout(name: "") } label: { Label("New", systemImage: "plus") }
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.lime)
            }
            ForEach(preview) { e in
                NavigationLink(value: e.session.id) { LibraryCard(entry: e, done: model.state.done[e.session.id] ?? false) }
                    .buttonStyle(.plain)
            }
            NavigationLink { WorkoutLibraryView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.lime)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.lime.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Browse the library").font(.system(.headline, design: .rounded).weight(.heavy))
                        Text("Your workouts, built-in and shared by members. Start one now or add it to your plan.")
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
    }
}

/// Explore-style card: icon tile left, heavy name, big minutes right, on a vivid gradient.
struct LibraryCard: View {
    let entry: LibraryEntry
    var done = false

    var body: some View {
        let palette = entry.palette
        HStack(spacing: 14) {
            Image(systemName: palette.symbol)
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
                Text(entry.detail).font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(1)
            }
            Spacer(minLength: 4)
            if done {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 26, weight: .bold))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(entry.session.estMin)").font(Theme.display(28)).monospacedDigit()
                    Text("′").font(Theme.display(16))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                if filter == .all || filter == .mine {
                    section("My workouts", entries(model.myLibrary)) {
                        Button { editing = CustomWorkout(name: "") } label: {
                            Label("Build your own workout", systemImage: "square.and.pencil")
                                .font(Theme.label(15))
                                .foregroundStyle(Theme.lime)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                        }
                        .buttonStyle(.plain)
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
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Workout library")
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $query, prompt: "Search workouts")
        .onSubmit(of: .search) { Task { memberState = await model.loadSharedLibrary(query: query) } }
        .task { memberState = await model.loadSharedLibrary() }
        .refreshable { memberState = await model.loadSharedLibrary(query: query) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = CustomWorkout(name: "") } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New workout")
            }
        }
        .sheet(item: $editing) { w in CustomWorkoutEditor(initial: w) }
    }

    private func entries(_ list: [LibraryEntry]) -> [LibraryEntry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return list }
        return list.filter { e in words.allSatisfy { e.name.lowercased().contains($0) || e.detail.lowercased().contains($0) } }
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
            NavigationLink(value: e.session.id) { LibraryCard(entry: e, done: model.state.done[e.session.id] ?? false) }
                .buttonStyle(.plain)
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
                Text("From your library").font(.system(.headline, design: .rounded).weight(.heavy))
                Text("Placed into this week's plan.").font(.caption).foregroundStyle(Theme.muted)
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
            Text("A replaced day goes back to its planned session.")
        }
    }

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
            Picker("Visibility", selection: Binding(get: { w.visibility }, set: { model.setVisibility(w.id, $0) })) {
                ForEach(WorkoutVisibility.allCases) { v in Label(v.label, systemImage: v.symbol).tag(v) }
            }
            .pickerStyle(.segmented)
            Text(w.hidden
                 ? "Hidden from members after reports, pending review."
                 : w.visibility == .private ? "Only you see it." : "Members can find it in their library, start it and save a copy.")
                .font(.caption)
                .foregroundStyle(w.hidden ? .orange : Theme.muted)
        }
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
                    Text("Week \(model.plan?.week ?? 1): replace a planned day, or add an extra session. A new variation keeps it; changing week clears it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 6)
                    ForEach(Array(model.replaceableSessions.enumerated()), id: \.offset) { i, pair in
                        let done = model.state.done[pair.current.id] ?? false
                        Button { replacing = i; pickedExtra = false } label: {
                            dayRow(number: String(format: "%02d", i + 1), title: pair.current.displayTitle,
                                   day: pair.current.weekday.map { WeekSchedule.name($0).uppercased() } ?? "DAY \(i + 1)",
                                   note: done ? "DONE" : pair.current.isPlanInsert ? "FROM LIBRARY" : nil,
                                   action: "Replace", selected: replacing == i && !pickedExtra)
                        }
                        .buttonStyle(.plain)
                        .disabled(done)
                        .opacity(done ? 0.5 : 1)
                    }
                    Button { pickedExtra = true; replacing = nil } label: {
                        dayRow(number: "+", title: "Extra session", day: extraDay.map { WeekSchedule.name($0).uppercased() } ?? "ANY DAY",
                               note: nil, action: "Add", selected: pickedExtra, dashed: true)
                    }
                    .buttonStyle(.plain)
                    if pickedExtra {
                        Picker("Day", selection: $extraDay) {
                            Text("Any day").tag(Int?.none)
                            ForEach(1...7, id: \.self) { d in Text(WeekSchedule.name(d)).tag(Int?.some(d)) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.lime)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Button(confirmTitle) {
                    model.insertIntoPlan(workout, replacing: pickedExtra ? nil : replacing, weekday: extraDay)
                    onDone(pickedExtra ? "Added to this week." : "Placed into this week's plan.")
                    dismiss()
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(!pickedExtra && replacing == nil)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("Add to plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private var confirmTitle: String {
        if pickedExtra { return "Add extra session" }
        guard let r = replacing, model.replaceableSessions.indices.contains(r) else { return "Pick a day" }
        return "Replace " + (model.replaceableSessions[r].current.weekday.map { WeekSchedule.name($0) } ?? "day \(r + 1)")
    }

    private func dayRow(number: String, title: String, day: String, note: String?, action: String, selected: Bool, dashed: Bool = false) -> some View {
        HStack(spacing: 14) {
            Text(number).font(Theme.display(30)).foregroundStyle(dashed ? Theme.lime : .white).frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.headline, design: .rounded).weight(.heavy)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(day).font(Theme.label(11)).tracking(1).foregroundStyle(Theme.lime)
                    if let note { Text(note).font(Theme.label(10)).tracking(1).foregroundStyle(Theme.muted) }
                }
            }
            Spacer()
            Text(action).font(Theme.label(12))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(selected ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.12))))
                .foregroundStyle(selected ? Theme.ink : .white)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(selected ? Theme.lime : Theme.stroke, style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: dashed && !selected ? [6, 4] : []))
        )
    }
}
