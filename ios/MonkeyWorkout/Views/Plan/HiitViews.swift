import SwiftUI
import WorkoutEngine

// HIIT (#693, designs A + B from `hiit/proposals.png`). A: HIIT days in the plan (Training profile → HIIT, also on
// Explore → HIIT): days a week, a Tabata finisher on lifting days, low impact. B: Explore → Ready-made → HIIT: a
// tile per format opens the builder (length, kit, impact, moves with Reshuffle) → Do today, Add to a day or Save.
// Saved HIITs stay on this device (`@AppStorage` `savedHiits`); their id is the spec, so nothing else is stored.

extension AppModel {
    var hiitPlan: HiitPlan? { profile?.hiit }

    /// Off (no days, no finisher) clears it, so the plan is exactly as before.
    func saveHiitPlan(_ plan: HiitPlan) {
        guard var p = profile else { return }
        let new: HiitPlan? = plan.on || plan.lowImpact ? plan : nil
        guard p.hiit != new else { return }
        p.hiit = new
        updateProfile(p)
    }
}

/// Saved HIITs (comma-separated session ids), newest first.
enum HiitPrefs {
    static let savedKey = "savedHiits"

    static func saved(_ raw: String) -> [HiitSpec] {
        raw.split(separator: ",").compactMap { HiitSpec(sessionId: String($0)) }
    }

    static func adding(_ raw: String, _ spec: HiitSpec) -> String {
        ([spec] + saved(raw).filter { $0 != spec }).prefix(20).map(\.sessionId).joined(separator: ",")
    }

    static func removing(_ raw: String, _ spec: HiitSpec) -> String {
        saved(raw).filter { $0 != spec }.map(\.sessionId).joined(separator: ",")
    }
}

extension HiitFormat {
    var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: tint.0), Color(hex: tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: B · Explore → HIIT

struct HiitLibrarySection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(HiitPrefs.savedKey) private var savedRaw = ""
    @State private var building: HiitFormat?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Short, hard intervals. Pick a format; it's built for your kit and length.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(HiitFormat.allCases) { f in
                    Button { building = f } label: { HiitFormatTile(format: f) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hiit.format.\(f.rawValue)")
                }
            }
            Text("In your plan").eyebrow().padding(.top, 6)
            HiitPlanEditor()
            let saved = HiitPrefs.saved(savedRaw)
            if !saved.isEmpty {
                Text("Saved").eyebrow().padding(.top, 6)
                ForEach(saved) { spec in
                    NavigationLink(value: spec.sessionId) { HiitSavedRow(spec: spec) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                let before = savedRaw
                                savedRaw = HiitPrefs.removing(savedRaw, spec)
                                UndoCloseCenter.shared.deleted("HIIT removed", detail: "\(spec.format.label) · \(spec.minutes)′") {
                                    savedRaw = before
                                }
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                }
            }
        }
        .sheet(item: $building) { HiitBuilderSheet(format: $0) }
    }
}

/// Square format tile: icon tile, heavy name, tag (Explore categories look).
struct HiitFormatTile: View {
    let format: HiitFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: format.symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
            Spacer(minLength: 4)
            Text(format.label).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.7)
            Text(format.tag).font(Theme.label(10)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(format.gradient))
        .contentShape(Rectangle())
    }
}

private struct HiitSavedRow: View {
    let spec: HiitSpec

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: spec.format.symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.format.label).font(Theme.display(18)).lineLimit(1)
                Text("\(spec.kit.label)\(spec.lowImpact ? " · low impact" : "")").font(Theme.label(10)).tracking(1).textCase(.uppercase)
                    .opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                // ′ in the number's own font: a small label-font ′ read as a clipped comma, "10," (#823).
                Text("\(spec.minutes)′").font(Theme.display(26))
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(spec.format.gradient))
    }
}

/// Builder (B): length, kit, impact, the moves it picked (Reshuffle), then Do today / Add to a day / Save.
struct HiitBuilderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HiitPrefs.savedKey) private var savedRaw = ""
    @State private var spec: HiitSpec
    @State private var playing: HiitSpec?
    @State private var gate: ProGate?
    @State private var added: String?
    /// Add to day failed (no plan synced yet, #717).
    @State private var addError: String?

    init(format: HiitFormat) {
        _spec = State(initialValue: HiitSpec(format: format, minutes: 20, kit: .gym))
    }

    private var workout: HiitWorkout { Hiit.build(spec, gym: model.profile?.equipment ?? []) }

    var body: some View {
        let w = workout
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: spec.format.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spec.format.label).font(Theme.display(30))
                            Text(spec.format.tag).font(Theme.label(12)).opacity(0.9)
                        }
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            // ′ in the number's own font: a small label-font ′ read as a clipped comma, "10," (#823).
                            Text("\(w.minutes)′").font(Theme.display(34))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(spec.format.gradient))

                    Text("Length").eyebrow()
                    chips(HiitSpec.lengths.map { ("\($0)′", $0) }, selected: spec.minutes) { spec.minutes = $0 }
                    Text("Kit").eyebrow()
                    chips(Hiit.Kit.allCases.map { ($0.label, $0) }, selected: spec.kit) { spec.kit = $0 }
                    Text("Impact").eyebrow()
                    chips([("Normal", false), ("Low · no jumps", true)], selected: spec.lowImpact) { spec.lowImpact = $0 }

                    HStack {
                        Text("Moves").eyebrow()
                        Spacer()
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { spec.shuffle += 1 }
                        } label: {
                            Label("Reshuffle", systemImage: "arrow.triangle.2.circlepath").font(Theme.label(13))
                        }
                        .foregroundStyle(Theme.lime)
                        .accessibilityIdentifier("hiit.reshuffle")
                    }
                    ForEach(Array(w.blocks.enumerated()), id: \.offset) { i, b in
                        HiitBlockCard(block: b, index: i)
                    }
                    if let added {
                        Label(added, systemImage: "checkmark.circle.fill").font(Theme.label(14)).foregroundStyle(Theme.lime)
                    }
                    ErrorText(message: addError)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { actions }
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $playing) { WorkoutPlayerView(sessionId: $0.sessionId) }
        .proPaywall($gate)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { ProStore.shared.run(.generateWorkout, $gate) { playing = spec } } label: {
                Label("Do today", systemImage: "play.fill").font(Theme.label(15)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
            }
            .accessibilityIdentifier("hiit.doToday")
            Menu {
                ForEach(model.todayWeekday...7, id: \.self) { wd in
                    Button(wd == model.todayWeekday ? "Today" : WeekSchedule.name(wd)) { add(wd) }
                }
            } label: {
                Text("Add to day").font(Theme.label(15)).frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
            }
            .disabled(model.plan == nil)
            Button {
                savedRaw = HiitPrefs.adding(savedRaw, spec)
                Haptics.success()
                added = "Saved in Explore → HIIT"
            } label: {
                Text("Save").font(Theme.label(15)).frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bg.ignoresSafeArea())
    }

    private func add(_ weekday: Int) {
        let s = workout.session(id: spec.sessionId)
        let day = weekday == model.todayWeekday ? "today" : WeekSchedule.name(weekday)
        guard model.addExtra(CustomWorkout(name: s.title), generated: s, weekday: weekday) != nil else {
            added = nil
            addError = "Couldn't add it to \(day). Try again once your week has synced."
            Haptics.destructive()
            return
        }
        Haptics.success()
        addError = nil
        added = "Added to \(day)"
    }

    private func chips<T: Equatable>(_ options: [(String, T)], selected: T, pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                SelectChip(title: o.0, on: o.1 == selected) { withAnimation(.snappy(duration: 0.2)) { pick(o.1) } }
            }
        }
    }
}

/// One block of a HIIT: format, numbers and its moves.
struct HiitBlockCard: View {
    let block: HiitBlock
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(HiitWorkout.group(block: index, move: 0).prefix(1)) · \(block.format.label)").font(Theme.display(18))
                Spacer()
                Text(block.summary).font(Theme.label(12)).opacity(0.9)
            }
            ForEach(Array(block.moves.enumerated()), id: \.offset) { _, m in
                HStack(spacing: 10) {
                    if let e = Exercise.find(m.exerciseId) { ExerciseThumbnail(exercise: e, size: 40) }
                    Text(m.label).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(block.format.gradient).frame(width: 4).padding(.vertical, 10)
        }
    }
}

// MARK: A · HIIT in the plan

/// Days a week (0–3), Tabata finisher on lifting days, low impact. Each tap saves and re-plans the week.
struct HiitPlanEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let h = model.hiitPlan ?? HiitPlan(days: 0)
        VStack(alignment: .leading, spacing: 10) {
            Text("HIIT days a week").font(Theme.label(13)).opacity(0.9)
            HStack(spacing: 6) {
                ForEach(0...3, id: \.self) { n in
                    chip("\(n)", on: h.days == n) { var x = h; x.setDays(n); model.saveHiitPlan(x) }
                }
            }
            if h.days > 0 {
                // Which days, format and length (#757, design B).
                Text("Which days").font(Theme.label(13)).opacity(0.9)
                FlowLayout(spacing: 6) {
                    hug("Coach picks", symbol: "sparkles", on: h.weekdays.isEmpty) { var x = h; x.weekdays = []; model.saveHiitPlan(x) }
                    ForEach(1...7, id: \.self) { wd in
                        hug(WeekSchedule.shortName(wd), on: h.weekdays.contains(wd)) { var x = h; x.toggle(wd); model.saveHiitPlan(x) }
                            .accessibilityIdentifier("hiit.day.\(wd)")
                    }
                }
                Text("Format").font(Theme.label(13)).opacity(0.9)
                FlowLayout(spacing: 6) {
                    hug("Coach mix", symbol: "shuffle", on: h.format == nil) { var x = h; x.format = nil; model.saveHiitPlan(x) }
                    ForEach(HiitFormat.allCases) { f in
                        hug(f.label, on: h.format == f) { var x = h; x.format = f; model.saveHiitPlan(x) }
                    }
                }
                Text("Length").font(Theme.label(13)).opacity(0.9)
                HStack(spacing: 6) {
                    chip("Auto", on: h.minutes == nil) { var x = h; x.minutes = nil; model.saveHiitPlan(x) }
                    ForEach(HiitSpec.lengths, id: \.self) { m in
                        chip("\(m)′", on: h.minutes == m) { var x = h; x.minutes = m; model.saveHiitPlan(x) }
                    }
                }
                HiitPlannedList()
            }
            HStack(spacing: 6) {
                chip("Finisher on lifting days", on: h.finisher) { var x = h; x.finisher.toggle(); model.saveHiitPlan(x) }
                chip("Low impact", on: h.lowImpact) { var x = h; x.lowImpact.toggle(); model.saveHiitPlan(x) }
            }
            Text(h.weekdays.isEmpty
                 ? "Coach puts HIIT on free days away from leg days, changes the formats every week and keeps the deload week easy."
                 : "Your days stay HIIT days; a lifting day stays the lift's. The deload week stays easy.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient.hiit).opacity(0.35))
        .disabled(model.profile == nil)
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        SelectChip(title: label, on: on, offFill: AnyShapeStyle(.black.opacity(0.25)), offInk: .white, action: action)
    }

    private func hug(_ label: String, symbol: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        SelectChip(title: label, symbol: symbol, on: on, offFill: AnyShapeStyle(.black.opacity(0.25)), offInk: .white, fills: false, action: action)
    }
}

/// This week's and next week's HIIT days (#757, design B): day, name, blocks, minutes.
struct HiitPlannedList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let weeks = model.calendarWeeks(count: 2)
        ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
            let list = w.plan.sessions.filter { $0.hiit != nil }
            if !list.isEmpty {
                Text(i == 0 ? "This week" : "Next week").font(Theme.label(13)).opacity(0.9)
                ForEach(list, id: \.id) { s in row(s, week: w, current: i == 0) }
            }
        }
    }

    private func row(_ s: Session, week w: PlanCalendar.Week, current: Bool) -> some View {
        let date = s.weekday.flatMap { w.date($0, model.planCalendar) }
        let day = date?.formatted(.dateTime.weekday(.abbreviated).day()) ?? "Any day"
        let parts = s.hiit.map { DayComboRow.hiitParts($0).map(\.title).joined(separator: " · ") } ?? ""
        let face = HStack(spacing: 10) {
            Image(systemName: "bolt.heart.fill").font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day) · \(s.displayTitle)").font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
                Text(parts).font(Theme.label(10)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Text("\(s.estMin)′").font(Theme.display(20))
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient.hiit))
        .contentShape(Rectangle())
        // This week's opens its overview (blocks, moves, Start); a later one is a preview.
        return Group {
            if current {
                NavigationLink(value: s.id) { face }.buttonStyle(.plain)
            } else {
                face
            }
        }
        .accessibilityIdentifier("hiit.planned.\(s.weekday ?? 0)")
    }
}

/// "HIIT" badge on a HIIT day card's eyebrow (#757, design A2).
struct HiitBadge: View {
    var body: some View {
        Text("HIIT").font(Theme.label(10)).tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(LinearGradient.hiit))
            .accessibilityLabel("HIIT day")
    }
}

/// The day card's Format menu on a HIIT day (#757, design A2): Coach's pick or a format, a length, all settings.
/// Only this week's days change here; a later week's day opens HIIT settings.
struct HiitDayMenuItems: View {
    let session: Session
    let thisWeek: Bool
    let onSettings: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        if thisWeek {
            let picked = model.hiitDaySpec(session)
            let minutes = picked?.minutes ?? HiitSpec(format: .tabata, minutes: session.estMin).minutes
            Section("Just this day") {
                Button { model.setHiitDay(nil, for: session) } label: {
                    Label(planName, systemImage: picked == nil ? "checkmark" : "shuffle")
                }
                ForEach(HiitFormat.allCases) { f in
                    Button { model.setHiitDay(spec(f, minutes), for: session) } label: {
                        Label("\(f.label) · \(f.tag)", systemImage: picked?.format == f ? "checkmark" : f.symbol)
                    }
                }
                if let picked {
                    Menu("Length · \(picked.minutes)′", systemImage: "clock") {
                        ForEach(HiitSpec.lengths, id: \.self) { m in
                            Button { model.setHiitDay(spec(picked.format, m), for: session) } label: {
                                Label("\(m)′", systemImage: picked.minutes == m ? "checkmark" : "clock")
                            }
                        }
                    }
                }
            }
        }
        Button("HIIT settings…", systemImage: "gearshape", action: onSettings)
    }

    /// The plan's own HIIT: Coach mix, or the format set in HIIT settings.
    private var planName: String {
        model.hiitPlan?.format.map { "Plan · \($0.label)" } ?? "Coach mix"
    }

    private func spec(_ f: HiitFormat, _ minutes: Int) -> HiitSpec {
        HiitSpec(format: f, minutes: minutes, kit: .gym, lowImpact: model.hiitPlan?.lowImpact ?? false)
    }
}

/// HIIT settings sheet (#757): Training profile → HIIT and the day card's Format menu.
struct HiitSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("HIIT").font(Theme.display(30))
                    HiitPlanEditor()
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
            .navigationDestination(for: String.self) { SessionView(sessionId: $0) }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}

/// Training profile card: HIIT days, or set them up.
struct HiitProfileCard: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    static func detail(_ h: HiitPlan?) -> String {
        guard let h else { return "Tabata, EMOM, AMRAP days in your week" }
        var parts: [String] = []
        if h.days > 0 {
            parts.append(h.weekdays.isEmpty ? "Coach plans the days" : h.weekdays.sorted().map(WeekSchedule.shortName).joined(separator: ", "))
            if let f = h.format { parts.append(f.label) }
        }
        if h.finisher { parts.append("Tabata finisher") }
        if h.lowImpact { parts.append("Low impact") }
        return parts.isEmpty ? "Tabata, EMOM, AMRAP days in your week" : parts.joined(separator: " · ")
    }

    var body: some View {
        let h = model.hiitPlan
        Button { editing = true } label: {
            let days = h?.days ?? 0
            ExpertStatCard(symbol: "bolt.heart.fill", title: "HIIT", detail: Self.detail(h),
                           value: days > 0 ? "\(days)×" : "", unit: days > 0 ? "a week" : "",
                           colors: Theme.hiitColors)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.hiit")
        .sheet(isPresented: $editing) { HiitSettingsSheet() }
    }
}
