import APIClient
import SwiftUI
import WorkoutEngine

// "What can I eat?" (#869, epic #865, A + B from `ai-epic/d1.png`): a lime tile on today's Fuel day asks Monkey for
// three meals made of What I have, aimed at the protein and carbs left (A). Each idea logs with one tap; tapping the
// card opens the recipe card with grams and steps, Log as eaten at the bottom (B). Pro, same gate as the food scan.

/// Today's tile and, once asked, the three ideas under it.
struct MealIdeasCard: View {
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared
    @State private var gate: ProGate?
    @State private var ideas: [MealIdea] = []
    @State private var asking = false
    @State private var notice: String?
    @State private var logged: Set<String> = []
    @State private var open: MealIdea?

    private static let gradients = [FuelPalette.coach, FuelPalette.hot, FuelPalette.violet]

    var body: some View {
        let slot = nextSlot
        let empty = store.saved.pantry.isEmpty && !model.demo
        VStack(alignment: .leading, spacing: 8) {
            if empty {
                NavigationLink(value: FuelRoute.pantry) { tile("Add what you have first, then ask") }
                    .buttonStyle(.plain)
            } else {
                Button { ProStore.shared.run(.foodScan, $gate) { ask(slot) } } label: {
                    tile(asking ? "Monkey is cooking up ideas…" : "From your pantry · hits what's left")
                }
                .buttonStyle(.plain)
                .disabled(asking || slot == nil)
            }
            if let notice { Text(notice).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted) }
            if !ideas.isEmpty, let slot {
                Text("\(ideas.count) IDEA\(ideas.count == 1 ? "" : "S") · \(slot.kind.label.uppercased())")
                    .font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 2)
                ForEach(Array(ideas.enumerated()), id: \.element.id) { n, idea in
                    row(idea, slot: slot, gradient: Self.gradients[n % Self.gradients.count])
                }
                HStack(spacing: 4) {
                    Text("Uses: " + usedNames).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { ask(slot) } label: { Label("Other ideas", systemImage: "arrow.clockwise") }
                        .disabled(asking)
                        .accessibilityIdentifier("fuel.ideas.again")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.muted)
            }
        }
        .animation(.snappy, value: ideas)
        .proPaywall($gate)
        .sheet(item: $open) { idea in
            if let slot { MealIdeaSheet(idea: idea, plan: plan, day: day, slot: slot) { logged.insert(idea.id) } }
        }
        .task {
            #if DEBUG
            if Demo.enabled, Demo.screen == "fuel-ideas", ideas.isEmpty { ask(nextSlot) }
            #endif
        }
    }

    private var nextSlot: FuelSlot? {
        let cal = Calendar.current
        return plan.next(after: cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date()))
    }

    private var usedNames: String {
        let own = store.saved.foods
        var seen = Set<String>(), names: [String] = []
        for i in ideas.flatMap(\.items) where seen.insert(i.foodId).inserted {
            if let f = FoodBook.food(i.foodId, own: own) { names.append(f.name.lowercased()) }
        }
        return names.joined(separator: ", ")
    }

    private func tile(_ detail: String) -> some View {
        HStack(spacing: 12) {
            Text("🐵").font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text("What can I eat?").font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.75).lineLimit(1)
            }
            Spacer(minLength: 4)
            if asking {
                ProgressView().tint(Theme.ink)
            } else if ProStore.shared.locked {
                Text("PRO").font(Theme.label(10)).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(0.15)))
            } else {
                Image(systemName: "sparkles").font(.system(size: 20, weight: .black))
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.lime))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("fuel.ideas")
    }

    private func row(_ idea: MealIdea, slot: FuelSlot, gradient: LinearGradient) -> some View {
        let own = store.saved.foods
        let m = idea.totals(own: own)
        let done = logged.contains(idea.id)
        return HStack(spacing: 12) {
            Text(idea.foods(own: own).first?.food.emoji ?? "🍽️").font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 1) {
                Text(idea.name).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.75)
                Text("\(idea.minutes)′ · \(Int(m.protein.rounded())) g protein · \(Int(m.kcal.rounded())) kcal")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.9).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { log(idea, slot: slot) } label: {
                Text(done ? "✓" : "LOG").font(Theme.label(12))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .disabled(done)
            .accessibilityLabel(done ? "Logged" : "Log \(idea.name)")
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { open = idea }
        .accessibilityIdentifier("fuel.idea")
    }

    private func log(_ idea: MealIdea, slot: FuelSlot) {
        let items = idea.servings(own: store.saved.foods)
        guard !items.isEmpty else { return }
        Haptics.success()
        store.update(day, plan: plan) { $0.log(items, at: slot, own: store.saved.foods) }
        logged.insert(idea.id)
    }

    private func ask(_ slot: FuelSlot?) {
        guard let slot, !asking else { return }
        asking = true
        notice = nil
        Task {
            defer { asking = false }
            do {
                let found = try await model.mealIdeas(plan: plan, log: log, slot: slot)
                logged = []
                ideas = found
                if found.isEmpty { notice = "Not enough in What I have for a meal. Add a few foods and ask again." }
            } catch APIError.server(_, _, let message) {
                notice = message
            } catch {
                notice = "Couldn't reach the server. Check your connection and try again."
            }
        }
    }
}

/// One idea as a recipe card: the foods with grams, totals, steps, then Log as eaten on the meal.
struct MealIdeaSheet: View {
    let idea: MealIdea
    let plan: FuelPlan
    let day: Date
    let slot: FuelSlot
    var logged: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared

    var body: some View {
        let own = store.saved.foods
        let foods = idea.foods(own: own)
        let m = idea.totals(own: own)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(foods.first?.food.emoji ?? "🍽️").font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(idea.name).font(Theme.display(19)).lineLimit(2).minimumScaleFactor(0.7)
                            Text("\(idea.minutes)′ · \(slot.kind.label)").font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.9)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(Int(m.protein.rounded()))").font(Theme.display(30)).monospacedDigit()
                            Text("G PROT").font(Theme.label(9)).opacity(0.85)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(FuelPalette.hot))
                    HStack(spacing: 6) {
                        number("\(Int(m.carbs.rounded()))", "carbs g")
                        number("\(Int(m.fat.rounded()))", "fat g")
                        number("\(Int(m.kcal.rounded()))", "kcal")
                    }
                    label("FROM YOUR PANTRY")
                    VStack(spacing: 0) {
                        ForEach(foods, id: \.food.id) { f in
                            HStack {
                                Text("\(f.food.emoji) \(f.food.name)").font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer()
                                Text("\(Int(f.grams.rounded())) g").font(.subheadline.weight(.heavy)).foregroundStyle(Theme.lime).monospacedDigit()
                            }
                            .padding(.vertical, 9)
                            Divider().overlay(Theme.card)
                        }
                    }
                    if !idea.steps.isEmpty {
                        label("STEPS")
                        ForEach(Array(idea.steps.enumerated()), id: \.offset) { n, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(n + 1)").font(Theme.label(12)).foregroundStyle(Theme.ink)
                                    .frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.lime))
                                Text(step).font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                Button { log() } label: { Text("Log as eaten · \(Int(m.kcal.rounded())) kcal").frame(maxWidth: .infinity) }
                    .buttonStyle(LimeButtonStyle())
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .accessibilityIdentifier("fuel.idea.log")
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Cook it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private func number(_ v: String, _ unit: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(Theme.display(18)).monospacedDigit()
            Text(unit).font(Theme.label(9)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }

    private func label(_ t: String) -> some View {
        Text(t).font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 4)
    }

    private func log() {
        let items = idea.servings(own: store.saved.foods)
        guard !items.isEmpty else { return }
        Haptics.success()
        store.update(day, plan: plan) { $0.log(items, at: slot, own: store.saved.foods) }
        logged()
        dismiss()
    }
}
