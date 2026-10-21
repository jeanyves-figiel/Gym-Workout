import SwiftUI
import WorkoutEngine

// Meal plan blocks (#558, design C1): the plan is preset blocks one after the other (e.g. 2 weeks of weekday
// dinners, then a week of every meal), the whole cycle can repeat every few weeks, and a custom block picks the
// meals for each weekday.

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
}

/// The plan card: blocks, Add block, repeat, people.
struct MealBlocksCard: View {
    @State private var store = FuelStore.shared
    @State private var editing: MealBlock?
    let replan: () -> Void

    var body: some View {
        let schedule = store.schedule
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR PLAN · \(schedule.length) DAYS\(schedule.repeatWeeks.map { " · EVERY \($0) WK" } ?? "")")
                .font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
            ForEach(schedule.blocks) { b in
                Button { editing = b } label: { row(b) }
                    .buttonStyle(.plain)
            }
            if schedule.length < MealSchedule.maxDays && schedule.blocks.count < 8 {
                Button {
                    let b = MealBlock(pattern: .lunchDinner, days: min(7, MealSchedule.maxDays - schedule.length))
                    store.setBlocks(schedule.blocks + [b])
                    editing = b
                } label: {
                    Label("Add block", systemImage: "plus").font(Theme.label(13)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .buttonStyle(.plain)
            }
            Text("REPEAT").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 4)
            HStack(spacing: 6) {
                chip("Off", on: schedule.repeatWeeks == nil) { store.setRepeat(weeks: nil) }
                ForEach(schedule.repeatChoices.prefix(4), id: \.self) { w in
                    chip("\(w) wk", on: schedule.repeatWeeks == w) {
                        store.setRepeat(weeks: w)
                        replan()
                    }
                }
            }
            Text(schedule.repeatWeeks == nil ? "Plan once, from today." : "Starts again every \(schedule.repeatWeeks!) weeks and plans itself a week ahead.")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            Stepper(value: Binding(get: { store.saved.people }, set: { store.setPlanOptions(people: $0) }), in: 1...8) {
                Text("For \(store.saved.people) \(store.saved.people == 1 ? "person" : "people")").font(Theme.display(16))
            }
            Text("Meals follow each day's training, your diet and favourites, use what you have first, and don't repeat within 3 days. Batch dinners become next day's lunch when that day has lunch.")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(.white)
        .sheet(item: $editing, onDismiss: replan) { b in MealBlockSheet(blockId: b.id) }
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
                .background(Capsule().fill(.black.opacity(0.28)))
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(preset.gradient))
        .accessibilityLabel("\(preset.title), \(b.days) days. Edit")
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(13)).lineLimit(1)
                .foregroundStyle(on ? Theme.ink : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One block: preset cards, length, the weekday grid for a custom week. Changes save as they're made.
struct MealBlockSheet: View {
    let blockId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var custom = false

    private var block: MealBlock? { store.schedule.blocks.first { $0.id == blockId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let b = block {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("HOW LONG").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                        let room = MealSchedule.maxDays - store.schedule.length + b.days
                        HStack(spacing: 6) {
                            ForEach([3, 5, 7, 14, 21, 28].filter { $0 <= room }, id: \.self) { n in
                                chip(MealPlanFormat.length(n), on: b.days == n) { update { $0.days = n } }
                            }
                        }
                        Text("MEALS").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 6)
                        let current = MealPreset.of(b.pattern)
                        let selected = custom ? MealPreset.custom : current
                        ForEach(MealPreset.allCases) { p in
                            Button {
                                if let pattern = p.pattern { custom = false; update { $0.pattern = pattern } } else { custom = true }
                            } label: { card(p, on: p == selected) }
                            .buttonStyle(.plain)
                        }
                        if selected == .custom { grid(b.pattern) }
                        if store.schedule.blocks.count > 1 {
                            Button(role: .destructive) {
                                let before = store.schedule.blocks
                                store.setBlocks(before.filter { $0.id != blockId })
                                dismiss()
                                UndoCloseCenter.shared.deleted("Block removed", detail: MealPreset.of(b.pattern).title, symbol: "trash") {
                                    FuelStore.shared.setBlocks(before)
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
        var blocks = store.schedule.blocks
        guard let i = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        change(&blocks[i])
        store.setBlocks(blocks)
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
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
