import SwiftUI
import WorkoutEngine

// My plans (#558, designs A + B + C from `meal-plan-pattern/proposals3.png`, blocks C1 from `proposals2.png`): named
// meal plans, each preset blocks one after the other (e.g. 2 weeks of weekday dinners, then a week of every meal)
// that start again when they end or every few weeks, and the dates each plan runs. Timeline lanes show what runs
// when; on overlap the period that started last wins; days no plan covers get nothing planned.

/// Ready-made meal patterns, shown as big cards.
enum MealPreset: String, CaseIterable, Identifiable {
    case everyMeal, lunchDinner, dinners, weekdayDinners, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyMeal: "Every meal"
        case .lunchDinner: "Lunch & dinner"
        case .dinners: "Dinners only"
        case .weekdayDinners: "Weekday dinners, weekend L+D"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .everyMeal: "Breakfast, lunch, dinner and snacks"
        case .lunchDinner: "Breakfast on you"
        case .dinners: "Breakfast and lunch on you"
        case .weekdayDinners: "Mon–Fri dinner · Sat–Sun lunch and dinner"
        case .custom: "Pick meals for each weekday"
        }
    }

    var emoji: String {
        switch self {
        case .everyMeal: "🍳"
        case .lunchDinner: "🥗"
        case .dinners: "🌙"
        case .weekdayDinners: "📅"
        case .custom: "✏️"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .everyMeal: FuelPalette.hot
        case .lunchDinner: FuelPalette.coach
        case .dinners: FuelPalette.violet
        case .weekdayDinners: FuelPalette.mint
        case .custom: FuelPalette.gradient(0x3A3A48, 0x22222C)
        }
    }

    var pattern: MealPattern? {
        switch self {
        case .everyMeal: .everyMeal
        case .lunchDinner: .lunchDinner
        case .dinners: .dinners
        case .weekdayDinners: .weekdayDinners
        case .custom: nil
        }
    }

    static func of(_ p: MealPattern) -> MealPreset { allCases.first { $0.pattern == p } ?? .custom }

    /// "Mon–Fri D · Sat L+D" style summary of a custom week.
    static func summary(_ p: MealPattern) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        func short(_ m: Set<MealKind>) -> String {
            m.isEmpty ? "off" : MealPattern.main.filter { m.contains($0) }.map { String($0.label.prefix(1)) }.joined(separator: "+")
        }
        var parts: [String] = []
        var i = 0
        while i < 7 {
            var j = i
            while j + 1 < 7 && p.week[j + 1] == p.week[i] { j += 1 }
            parts.append("\(names[i])\(j > i ? "–\(names[j])" : "") \(short(p.week[i]))")
            i = j + 1
        }
        return parts.joined(separator: " · ") + (p.extras ? " · snacks" : "")
    }
}

enum MealPlanFormat {
    static func length(_ days: Int) -> String {
        days % 7 == 0 ? (days == 7 ? "1 wk" : "\(days / 7) wk") : "\(days) d"
    }

    /// "3 Nov → 19 Dec", "5 Jan → …".
    static func period(_ p: MealPeriod, _ cal: Calendar) -> String {
        "\(day(p.from, cal)) → \(p.to.map { day($0, cal) } ?? "…")"
    }

    static func day(_ key: String, _ cal: Calendar) -> String {
        PlanCalendar.date(key, cal)?.formatted(.dateTime.day().month(.abbreviated)) ?? key
    }

    /// "Weekday dinners, weekend L+D" or "2 wk Dinners only → 1 wk Every meal", with the repeat.
    static func summary(_ p: NamedMealPlan) -> String {
        func name(_ b: MealBlock) -> String {
            let preset = MealPreset.of(b.pattern)
            return preset == .custom ? "Custom week" : preset.title
        }
        let blocks = p.blocks.count == 1 ? name(p.blocks[0])
            : p.blocks.map { "\(length($0.days)) \(name($0))" }.joined(separator: " → ")
        return blocks + (p.repeatWeeks.map { " · every \($0) wk" } ?? "")
    }

    static let gradients: [LinearGradient] = [FuelPalette.mint, FuelPalette.hot, FuelPalette.violet, FuelPalette.coach, FuelPalette.water]

    static func gradient(_ id: UUID, in book: MealPlanBook) -> LinearGradient {
        gradients[(book.plans.firstIndex { $0.id == id } ?? 0) % gradients.count]
    }
}


/// Meal plan screen's top: timeline lanes, the plan running today, the other plans, New plan, people.
struct MyPlansCard: View {
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared
    @State private var editing: NamedMealPlan?
    @State private var creating = false
    @State private var openId: UUID?
    /// Plans and plan options before New plan, put back when the new plan is closed without Save (#1032).
    @State private var before: FuelStore.Saved?
    /// Save & plan my days tapped on the open sheet.
    @State private var confirmed = false
    /// Re-plans the days; true = say how many meals were planned (not after a delete).
    let replan: (_ announce: Bool) -> Void

    var body: some View {
        let cal = model.planCalendar
        let book = store.book
        let active = book.active(on: store.key(Date()))?.plan
        let others = book.plans.filter { $0.id != active?.id }
        VStack(alignment: .leading, spacing: 10) {
            if !book.plans.isEmpty {
                label("MY PLANS")
                PlanLanes(book: book, cal: cal)
            }
            if let active {
                label("ACTIVE TODAY")
                card(active, book: book, active: true, cal: cal)
            }
            if !others.isEmpty {
                label(active == nil ? "PLANS · NONE TODAY" : "OTHER PLANS")
                ForEach(others) { card($0, book: book, active: false, cal: cal) }
            }
            // #1034: New plan is a bold card, not a faint dashed outline. No plan yet → violet hero that says what a
            // plan does (design B); with plans → lime action card like Cook together / Groceries.
            if book.plans.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("🗓️").font(.system(size: 22)).frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NO MEAL PLAN YET").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                            Text("Plan your week").font(Theme.display(20))
                        }
                    }
                    Text(Self.how).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { newPlan(book) } label: {
                        Label("New plan", systemImage: "plus").font(Theme.label(15)).foregroundStyle(Color(hex: 0x7A3DFF))
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fuel.plan.new")
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.violet))
            } else {
                Button { newPlan(book) } label: {
                    FuelTile(emoji: "🗓️", label: "Meal plan", title: "New plan", detail: "Pick meals and when",
                             gradient: FuelPalette.lime, ink: Theme.ink) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .black)).foregroundStyle(Theme.lime)
                            .frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.ink))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuel.plan.new")
                Text(Self.how).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(.white)
        // Closing the plan sheet re-plans the days (#1015): no empty days to fill by hand. A new plan is only kept
        // with Save & plan my days; ✕ or swipe on a new plan discards it and its option changes (#1032).
        .sheet(item: $editing, onDismiss: {
            defer { creating = false; before = nil; confirmed = false }
            if creating, !confirmed {
                if let before { store.restorePlanSetup(before) }
                return
            }
            replan(store.book.plans.contains { $0.id == openId })
        }) { p in MealPlanEditor(planId: p.id, isNew: creating, onSave: { confirmed = true }).onAppear { openId = p.id } }
    }

    private static let how = "Meals follow each day's training, your diet and favourites, use what you have first, and come back as often as your Variety pick says. Batch dinners become next day's lunch when that day has lunch."

    private func newPlan(_ book: MealPlanBook) {
        let first = book.plans.isEmpty
        before = store.saved
        confirmed = false
        let p = NamedMealPlan(name: first ? "My plan" : "New plan", blocks: [MealBlock(pattern: .lunchDinner, days: 7)],
                              periods: first ? [MealPeriod(from: store.key(Date()))] : [])
        store.savePlan(p)
        creating = true
        editing = p
    }

    private func label(_ t: String) -> some View {
        Text(t).font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
    }

    private func card(_ p: NamedMealPlan, book: MealPlanBook, active: Bool, cal: Calendar) -> some View {
        Button { creating = false; before = nil; editing = p } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(p.name).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    if active {
                        Text("ACTIVE").font(Theme.label(10)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lime))
                    }
                }
                Text(MealPlanFormat.summary(p)).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(2)
                Text("\(store.saved.people) \(store.saved.people == 1 ? "person" : "people") · \(store.saved.budget.map { "\(BudgetFormat.money($0.rounded())) a week" } ?? "no budget limit")")
                    .font(.caption.weight(.semibold)).opacity(0.9).lineLimit(1)
                HStack(spacing: 5) {
                    ForEach(p.periods.isEmpty ? ["Not scheduled"] : p.periods.map { MealPlanFormat.period($0, cal) }, id: \.self) { t in
                        Text(t).font(Theme.label(10)).lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.28)))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MealPlanFormat.gradient(p.id, in: book)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { creating = false; editing = p }
            Button("Delete plan", systemImage: "trash", role: .destructive) { MealPlanDelete.run(p) { replan(false) } }
        }
        .accessibilityLabel("\(p.name)\(active ? ", active today" : ""). Edit")
        .accessibilityAction(named: "Delete plan") { MealPlanDelete.run(p) { replan(false) } }
    }
}

/// One choice on the plan sheet's variety cards (#1015).
private struct VarietyCard: Identifiable {
    let id: MealVariety
    let title: String
    let detail: String
    let colors: [Color]
}

/// Deletes a named plan with an Undo bar that brings back the plan and its planned meals.
enum MealPlanDelete {
    @MainActor static func run(_ p: NamedMealPlan, then replan: () -> Void) {
        let before = FuelStore.shared.deleteNamedPlan(p.id)
        replan()
        UndoCloseCenter.shared.deleted("\(p.name) deleted", detail: "Meal plan", symbol: "trash") {
            FuelStore.shared.restoreBook(before)
        }
    }
}

/// One lane per plan over the coming months: bars where it runs, a lime line for today.
struct PlanLanes: View {
    let book: MealPlanBook
    let cal: Calendar
    private static let span = 98

    var body: some View {
        let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date())) ?? Date()
        let firsts = (0..<Self.span).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .filter { cal.component(.day, from: $0) == 1 }
        // The month the lanes start in, unless the next one's label would sit on it.
        let gap = firsts.first.flatMap { cal.dateComponents([.day], from: start, to: $0).day } ?? Self.span
        let months = gap > 12 ? [start] + firsts : firsts
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 76, height: 1)
                GeometryReader { g in
                    ForEach(months, id: \.self) { m in
                        Text(m.formatted(.dateTime.month(.abbreviated))).font(Theme.label(9)).foregroundStyle(Theme.muted)
                            .offset(x: x(m, start, g.size.width))
                    }
                }
                .frame(height: 12)
            }
            ForEach(book.plans) { p in
                HStack(spacing: 6) {
                    Text(p.name).font(Theme.label(10)).lineLimit(1).frame(width: 76, alignment: .leading)
                    GeometryReader { g in
                        let w = g.size.width
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.card)
                            ForEach(p.periods) { per in
                                if let a = PlanCalendar.date(per.from, cal) {
                                    let b = per.to.flatMap { PlanCalendar.date($0, cal) }
                                    let x0 = max(0, x(a, start, w))
                                    let x1 = min(w, b.map { x($0, start, w) + w / CGFloat(Self.span) } ?? w)
                                    if x1 > x0 {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(MealPlanFormat.gradient(p.id, in: book))
                                            .frame(width: x1 - x0).offset(x: x0)
                                    }
                                }
                            }
                            Rectangle().fill(Theme.lime).frame(width: 2).offset(x: x(Date(), start, w))
                        }
                    }
                    .frame(height: 18)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(book.plans.map { "\($0.name): \($0.periods.isEmpty ? "not scheduled" : $0.periods.map { MealPlanFormat.period($0, cal) }.joined(separator: ", "))" }
            .joined(separator: ". "))
    }

    private func x(_ d: Date, _ start: Date, _ w: CGFloat) -> CGFloat {
        let days = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: d)).day ?? 0
        return CGFloat(days) / CGFloat(Self.span) * w
    }
}

/// One named plan: name, blocks, repeat, when it runs, people, budget, delete. An existing plan saves as it's
/// changed; the sticky button (#1015) confirms and closes, and closing fills the days. A new plan is a draft until
/// the sticky button: ✕ or swipe discards it (#1032).
struct MealPlanEditor: View {
    let planId: UUID
    var isNew = false
    /// Sticky Save tapped: the caller keeps a new plan.
    var onSave: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared
    @State private var editing: MealBlock?
    @State private var ownBudget = false
    @State private var preview: (week: [Recipe], distinct: Int)?

    private var plan: NamedMealPlan? { store.book.plans.first { $0.id == planId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let p = plan {
                    VStack(alignment: .leading, spacing: 10) {
                        label("NAME")
                        TextField("Plan name", text: Binding(get: { p.name }, set: { v in update { $0.name = v } }))
                            .font(Theme.display(17)).padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                        label("BLOCKS")
                        ForEach(p.blocks) { b in
                            Button { editing = b } label: { row(b) }.buttonStyle(.plain)
                        }
                        if p.length < MealSchedule.maxDays && p.blocks.count < 8 {
                            dashed("Add block") {
                                let b = MealBlock(pattern: .lunchDinner, days: min(7, MealSchedule.maxDays - p.length))
                                update { $0.blocks.append(b) }
                                editing = b
                            }
                        }
                        label("REPEAT")
                        let choices = [1, 2, 3, 4, 6, 8].filter { $0 * 7 > p.length }.prefix(3)
                        HStack(spacing: 6) {
                            chip("Back to back", on: p.repeatWeeks == nil) { update { $0.repeatWeeks = nil } }
                            ForEach(Array(choices), id: \.self) { w in
                                chip("Every \(w) wk", on: p.repeatWeeks == w) { update { $0.repeatWeeks = w } }
                            }
                        }
                        label("WHEN")
                        ForEach(p.periods) { per in period(per) }
                        dashed("Add dates") {
                            let cal = model.planCalendar
                            let after = p.periods.compactMap { $0.to.flatMap { PlanCalendar.date($0, cal) } }.max()
                            let from = after.flatMap { cal.date(byAdding: .day, value: 1, to: $0) }.map { max($0, Date()) } ?? Date()
                            let to = cal.date(byAdding: .day, value: 27, to: from) ?? from
                            update { $0.periods.append(MealPeriod(from: store.key(from), to: store.key(to))) }
                        }
                        Text(p.periods.isEmpty ? "Not scheduled: add dates to use it." : "Days no plan covers get nothing planned. Where plans overlap, the dates that start last win.")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        label("FOR")
                        Stepper(value: Binding(get: { store.saved.people }, set: { store.setPlanOptions(people: $0) }), in: 1...8) {
                            Text("\(store.saved.people) \(store.saved.people == 1 ? "person" : "people")").font(Theme.display(16))
                        }
                        .accessibilityIdentifier("fuel.plan.people")
                        label("BUDGET A WEEK")
                        budget()
                        label("VARIETY")
                        variety()
                        if !isNew { Button {
                            dismiss()
                            // The meal list is re-planned when the sheet closes.
                            MealPlanDelete.run(p) {}
                        } label: {
                            Label("DELETE PLAN", systemImage: "trash").font(Theme.label(14)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FuelPalette.protein))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8) }
                    }
                    .padding(16)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { onSave(); dismiss() } label: {
                    Label(isNew ? "SAVE & PLAN MY DAYS" : "SAVE & RE-PLAN", systemImage: "wand.and.stars")
                }
                .buttonStyle(LimeButtonStyle())
                .accessibilityHint("Closes and fills your days, keeping meals you picked")
                .accessibilityIdentifier("fuel.plan.save")
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
                .background(LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(plan?.name ?? "Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(item: $editing) { b in MealBlockSheet(planId: planId, blockId: b.id) }
            // The plan is re-planned when this sheet closes.
            .sheet(isPresented: $ownBudget) { BudgetSheet(replan: {}).presentationDetents([.large]) }
        }
        .preferredColorScheme(.dark)
    }

    /// Same meals / Some variety / Always new as cards (design B), with a live preview of the dinners it gives (C).
    private func variety() -> some View {
        let current = store.saved.variety ?? .varied
        let cards: [VarietyCard] = [
            VarietyCard(id: .same, title: "🔁 Same meals", detail: "A few favourites on repeat · simpler shopping",
             colors: [Color(red: 0.18, green: 0.72, blue: 0.63), Color(red: 0.23, green: 0.53, blue: 0.94)]),
            VarietyCard(id: .varied, title: "⚖️ Some variety", detail: "No meal twice in 3 days",
             colors: [Color(red: 0.48, green: 0.3, blue: 0.94), Color(red: 0.9, green: 0.31, blue: 0.65)]),
            VarietyCard(id: .new, title: "🌈 Always new", detail: "Different every day for 2 weeks",
             colors: [Color(red: 0.94, green: 0.63, blue: 0.23), Color(red: 0.93, green: 0.31, blue: 0.54)]),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(cards) { card in
                let on = card.id == current
                Button { store.setVariety(card.id) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title).font(Theme.display(16))
                            Text(card.detail).font(.caption.weight(.semibold)).opacity(0.9)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: card.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .opacity(on ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.title.dropFirst(2)). \(card.detail)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            if let preview, !preview.week.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("NEXT 7").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("≈ \(preview.distinct) different in 4 weeks").font(Theme.label(11)).foregroundStyle(Theme.lime)
                    }
                    HStack(spacing: 5) {
                        ForEach(Array(preview.week.enumerated()), id: \.offset) { _, r in
                            Text(r.emoji).font(.system(size: 20))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Next meals: \(preview.week.map(\.name).joined(separator: ", ")). About \(preview.distinct) different in 4 weeks.")
            }
        }
        .task(id: "\(current.rawValue)-\(store.saved.people)-\(store.version)") {
            preview = model.mealVarietyPreview(current)
        }
    }

    /// Saver / Normal / Treat for these people and meals, the member's own amount, or no limit (#1015).
    private func budget() -> some View {
        let market = BudgetFormat.market
        let current = store.saved.budget.map { BudgetFormat.whole($0) }
        let value: (BudgetLevel) -> Double = { BudgetFormat.whole($0.weekly(people: store.saved.people, share: store.mealShare)) }
        let isLevel = BudgetLevel.allCases.contains { l in current.map { abs($0 - value(l)) < 0.5 } ?? false }
        let money: (Double) -> String = { $0.formatted(.currency(code: market.currency).precision(.fractionLength(0))) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(BudgetLevel.allCases) { level in
                    let v = value(level)
                    chip("\(level.emoji) \(level.label) \(Int(v))", on: current.map { abs($0 - v) < 0.5 } ?? false) {
                        store.setBudget(BudgetFormat.toCHF(v))
                    }
                }
            }
            HStack(spacing: 6) {
                chip(current != nil && !isLevel ? "✏️ Own · \(money(current ?? 0))" : "✏️ Own", on: current != nil && !isLevel) { ownBudget = true }
                chip("No limit", on: current == nil) { store.setBudget(nil) }
            }
            Text("\(market.currency) for everyone, \(Int((store.mealShare * 21).rounded())) meals a week. The plan picks recipes to fit.")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .accessibilityIdentifier("fuel.plan.budget")
    }

    private func update(_ change: (inout NamedMealPlan) -> Void) {
        guard var p = plan else { return }
        change(&p)
        store.savePlan(p)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 6)
    }

    private func row(_ b: MealBlock) -> some View {
        let preset = MealPreset.of(b.pattern)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset == .custom ? "Custom week" : preset.title).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                Text(preset == .custom ? MealPreset.summary(b.pattern) : preset.detail).font(.caption.weight(.semibold)).opacity(0.85)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Text("\(MealPlanFormat.length(b.days)) ▾").font(Theme.label(12))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.28)))
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(preset.gradient))
        .accessibilityLabel("\(preset.title), \(b.days) days. Edit")
    }

    /// From and until (or ongoing), with a menu to make it ongoing, give it an end, or remove it.
    private func period(_ per: MealPeriod) -> some View {
        let cal = model.planCalendar
        func date(_ k: String) -> Date { PlanCalendar.date(k, cal) ?? Date() }
        func set(_ change: @escaping (inout MealPeriod) -> Void) {
            update { p in
                guard let i = p.periods.firstIndex(where: { $0.id == per.id }) else { return }
                change(&p.periods[i])
                if let to = p.periods[i].to, to < p.periods[i].from { p.periods[i].to = p.periods[i].from }
            }
        }
        return HStack(spacing: 6) {
            DatePicker("From", selection: Binding(get: { date(per.from) }, set: { d in set { $0.from = PlanCalendar.key(d, cal) } }),
                       displayedComponents: .date)
                .labelsHidden()
            Image(systemName: "arrow.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.muted)
            if let to = per.to {
                DatePicker("Until", selection: Binding(get: { date(to) }, set: { d in set { $0.to = PlanCalendar.key(d, cal) } }),
                           in: date(per.from)..., displayedComponents: .date)
                    .labelsHidden()
            } else {
                Text("Ongoing").font(Theme.label(13))
            }
            Spacer(minLength: 0)
            Menu {
                if per.to == nil {
                    Button("Set an end date", systemImage: "calendar") {
                        set { $0.to = PlanCalendar.key(cal.date(byAdding: .day, value: 27, to: date($0.from)) ?? Date(), cal) }
                    }
                } else {
                    Button("Ongoing", systemImage: "infinity") { set { $0.to = nil } }
                }
                Button("Remove dates", systemImage: "trash", role: .destructive) {
                    update { $0.periods.removeAll { $0.id == per.id } }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
            }
            .accessibilityLabel("Change dates")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }

    private func dashed(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus").font(Theme.label(13)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(on ? Theme.ink : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One block of a plan: length, preset cards, the weekday grid for a custom week. Changes save as they're made.
struct MealBlockSheet: View {
    let planId: UUID
    let blockId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var custom = false

    private var plan: NamedMealPlan? { store.book.plans.first { $0.id == planId } }
    private var block: MealBlock? { plan?.blocks.first { $0.id == blockId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let p = plan, let b = block {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("HOW LONG").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                        let room = MealSchedule.maxDays - p.length + b.days
                        HStack(spacing: 6) {
                            ForEach([3, 5, 7, 14, 21, 28].filter { $0 <= room }, id: \.self) { n in
                                chip(MealPlanFormat.length(n), on: b.days == n) { update { $0.days = n } }
                            }
                        }
                        Text("MEALS").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 6)
                        let current = MealPreset.of(b.pattern)
                        let selected = custom ? MealPreset.custom : current
                        ForEach(MealPreset.allCases) { preset in
                            Button {
                                if let pattern = preset.pattern {
                                    custom = false
                                    update { $0.pattern = pattern }
                                } else {
                                    custom = true
                                }
                            } label: { card(preset, on: preset == selected) }
                            .buttonStyle(.plain)
                        }
                        if selected == .custom { grid(b.pattern) }
                        if p.blocks.count > 1 {
                            Button {
                                let before = p
                                var after = p
                                after.blocks.removeAll { $0.id == blockId }
                                dismiss()
                                store.savePlan(after)
                                UndoCloseCenter.shared.deleted("Block removed", detail: p.name, symbol: "trash") {
                                    FuelStore.shared.savePlan(before)
                                }
                            } label: {
                                Label("Remove block", systemImage: "trash").font(Theme.label(13)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FuelPalette.protein))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Plan block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private func update(_ change: (inout MealBlock) -> Void) {
        guard var p = plan, let i = p.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        change(&p.blocks[i])
        store.savePlan(p)
    }

    private func card(_ p: MealPreset, on: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.title).font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.7)
                Text(p.detail).font(.caption.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 4)
            Text(on ? "✓" : p.emoji).font(.system(size: 22, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(p.gradient))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.lime, lineWidth: on ? 3 : 0))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Mon–Sun rows with Breakfast / Lunch / Dinner toggles, plus snacks.
    private func grid(_ p: MealPattern) -> some View {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return VStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { d in
                HStack(spacing: 6) {
                    Text(names[d]).font(Theme.label(13)).frame(width: 40, alignment: .leading)
                    ForEach(MealPattern.main) { k in
                        let on = p.week[d].contains(k)
                        Button {
                            update {
                                var w = $0.pattern.week
                                if on { w[d].remove(k) } else { w[d].insert(k) }
                                $0.pattern = MealPattern(week: w, extras: $0.pattern.extras)
                            }
                            custom = true
                        } label: {
                            Text(k.label).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(on ? Theme.ink : Theme.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(on ? AnyShapeStyle(Self.gradient(k)) : AnyShapeStyle(Theme.card)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(names[d]) \(k.label)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Toggle(isOn: Binding(get: { p.extras }, set: { v in
                update { $0.pattern = MealPattern(week: $0.pattern.week, extras: v) }
                custom = true
            })) { Text("Snacks, pre-workout and recovery too").font(Theme.label(13)) }
                .tint(Theme.lime)
                .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardStrong))
    }

    static func gradient(_ k: MealKind) -> LinearGradient {
        switch k {
        case .breakfast: FuelPalette.carbs
        case .lunch: FuelPalette.veg
        default: FuelPalette.protein
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(on ? Theme.ink : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
