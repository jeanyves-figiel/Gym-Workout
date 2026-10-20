import SwiftUI
import WorkoutEngine

// Recipes (#496): the built-in library plus the member's own, filtered by meal, diet, avoid list and tags;
// a detailed page with servings, ingredients, steps, portions and a cook mode with timers.

extension Recipe {
    var gradient: LinearGradient {
        switch base {
        case .vegan: FuelPalette.veg
        case .vegetarian: FuelPalette.mint
        case .fish: FuelPalette.water
        case .poultry: FuelPalette.hot
        case .beef, .lamb: FuelPalette.coach
        case .pork: FuelPalette.violet
        }
    }
}

/// Explore-style recipe card: emoji tile, name, time and tags, protein big on the right.
struct RecipeRow: View {
    let recipe: Recipe
    @State private var store = FuelStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Text(recipe.emoji).font(.system(size: 24))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(recipe.name).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.75)
                    if store.saved.favourites.contains(recipe.id) { Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold)) }
                }
                Text(([recipe.minutes > 0 ? "\(recipe.minutes) min" : nil, recipe.cuisine.isEmpty ? nil : recipe.cuisine,
                       recipe.isOwn ? "Mine" : nil] as [String?]).compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                if store.prefs.noNumbers {
                    Text("✋ \(recipe.portions.palms)").font(Theme.display(18))
                } else {
                    Text("\(recipe.protein)g").font(Theme.display(21)).monospacedDigit()
                    Text("PROTEIN").font(Theme.label(8)).opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(recipe.gradient))
        .accessibilityElement(children: .combine)
    }
}

struct RecipeBrowserView: View {
    var slot: MealKind?
    @State private var store = FuelStore.shared
    @State private var filter = RecipeFilter()
    @State private var creating = false

    init(slot: MealKind? = nil) {
        self.slot = slot
        _filter = State(initialValue: RecipeFilter(slot: slot))
    }

    var body: some View {
        let list = RecipeBook.list(filter, prefs: store.prefs, favourites: store.saved.favourites, own: store.saved.recipes)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search: salmon, oats, 15 min…", text: $filter.query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All meals", on: filter.slot == nil) { filter.slot = nil }
                        ForEach(MealKind.allCases) { k in
                            chip("\(k.emoji) \(k.label)", on: filter.slot == k) { filter.slot = filter.slot == k ? nil : k }
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("♥ Favourites", on: filter.favouritesOnly) { filter.favouritesOnly.toggle() }
                        chip("Mine", on: filter.ownOnly) { filter.ownOnly.toggle() }
                        ForEach(RecipeTag.allCases) { t in
                            chip("\(t.emoji) \(t.label)", on: filter.tags.contains(t)) {
                                if filter.tags.contains(t) { filter.tags.remove(t) } else { filter.tags.insert(t) }
                            }
                        }
                    }
                }
                Toggle(isOn: $filter.fitMe) {
                    Text("Only what fits my diet (\(store.prefs.diet.label)\(store.prefs.avoid.isEmpty ? "" : ", no \(store.prefs.avoid.map(\.label).sorted().joined(separator: ", ").lowercased())"))")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.lime)
                Text("\(list.count) recipes").eyebrow()
                ForEach(list) { r in
                    NavigationLink(value: r) { RecipeRow(recipe: r) }
                        .buttonStyle(.plain)
                }
                if list.isEmpty {
                    Text("Nothing matches. Clear a filter or add your own recipe.")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add my own recipe")
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { RecipeEditorView(recipe: nil) } }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(12)).lineLimit(1)
                .foregroundStyle(on ? Theme.ink : .white)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    /// Opened from a meal of the day: "I ate this" ticks that meal.
    var eat: (slot: FuelSlot, plan: FuelPlan, day: Date)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var servings: Int
    @State private var cooking = false
    @State private var editing = false
    @State private var choosingMeal = false
    @State private var eaten = false
    @State private var posting = false

    init(recipe: Recipe, eat: (slot: FuelSlot, plan: FuelPlan, day: Date)? = nil) {
        self.recipe = recipe
        self.eat = eat
        _servings = State(initialValue: recipe.servings)
    }

    var body: some View {
        let prefs = store.prefs
        let fav = store.saved.favourites.contains(recipe.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if !recipe.fits(prefs) {
                    Label("Outside your diet or avoid list", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.bold)).foregroundStyle(Color(hex: 0xFFD23D))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    if prefs.noNumbers {
                        ForEach(Portions.Kind.allCases) { k in macro("\(k.emoji) \(recipe.portions[k])", k.food, FuelPalette.portion(k), FuelPalette.ink(k)) }
                    } else {
                        macro("\(recipe.protein)g", "Protein", FuelPalette.protein, .white)
                        macro("\(recipe.carbs)g", "Carbs", FuelPalette.carbs, Theme.ink)
                        macro("\(recipe.fat)g", "Fat", FuelPalette.fats, .white)
                        macro("\(recipe.kcal)", "kcal", FuelPalette.water, .white)
                    }
                }
                Text(prefs.noNumbers ? "Per serving." : "Per serving · \(recipe.portions.palms) ✋ \(recipe.portions.cups) 🤲 \(recipe.portions.fists) ✊ \(recipe.portions.thumbs) 👍\(recipe.fibre.map { " · \($0) g fibre" } ?? "")")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)

                HStack {
                    Text("Ingredients").font(Theme.display(20))
                    Spacer()
                    Stepper(value: $servings, in: 1...12) {
                        Text("\(servings) serving\(servings == 1 ? "" : "s")").font(Theme.label(13))
                    }
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, line in
                        let have = haveIngredient(line)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: have ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(have ? Theme.lime : Theme.muted)
                            Text(recipe.ingredient(line, servings: servings)).font(.body.weight(.semibold))
                        }
                    }
                }
                .card(padding: 14)

                Text("Steps").font(Theme.display(20))
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(Theme.display(15)).foregroundStyle(Theme.ink)
                                .frame(width: 28, height: 28).background(Circle().fill(Theme.lime))
                            Text(step).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card(padding: 14)
                if let tip = recipe.tip {
                    FuelTile(emoji: "💡", label: "Tip", title: tip, gradient: FuelPalette.coach)
                }
                if !recipe.contains.isEmpty {
                    Text("Contains: \(recipe.contains.map(\.label).joined(separator: ", "))")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                }

                Button { cooking = true } label: { Label("Cook mode", systemImage: "flame.fill") }
                    .buttonStyle(LimeButtonStyle())
                HStack(spacing: 8) {
                    Button { ateIt() } label: {
                        Label(eaten ? "Logged" : "I ate this", systemImage: eaten ? "checkmark.circle.fill" : "fork.knife")
                            .font(Theme.label(14)).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(Theme.cardStrong))
                    }
                    .buttonStyle(.plain)
                    .disabled(eaten)
                    NavigationLink { AddToPlanView(recipe: recipe) } label: {
                        Label("Add to plan", systemImage: "calendar.badge.plus")
                            .font(Theme.label(14)).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(Theme.cardStrong))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if recipe.isOwn {
                    Button { editing = true } label: { Image(systemName: "pencil") }.accessibilityLabel("Edit recipe")
                }
                Button { store.toggleFavourite(recipe.id) } label: { Image(systemName: fav ? "heart.fill" : "heart") }
                    .accessibilityLabel(fav ? "Remove from favourites" : "Add to favourites")
                Menu {
                    Button("Share to Community", systemImage: "person.3.fill") { posting = true }
                    ShareLink("Send the recipe", item: shareText)
                } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share")
            }
        }
        .sheet(isPresented: $posting) { ShareRecipeSheet(recipe: recipe) }
        .fullScreenCover(isPresented: $cooking) { CookModeView(recipe: recipe, servings: servings) }
        .sheet(isPresented: $editing) { NavigationStack { RecipeEditorView(recipe: recipe) } }
        .confirmationDialog("Which meal?", isPresented: $choosingMeal, titleVisibility: .visible) {
            let plan = model.fuelPlan(on: Date())
            ForEach(plan.slots) { s in
                Button("\(s.time) · \(s.title)") { tick(s, plan: plan, day: Date()) }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                PlatePicture(recipe: recipe, size: 104)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(recipe.minutes) min").font(Theme.display(24))
                    if let prep = recipe.prep, let cook = recipe.cook {
                        Text("\(prep) prep · \(cook) cook").font(Theme.label(11)).opacity(0.85)
                    }
                }
            }
            Text(recipe.name).font(Theme.display(26)).fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6) {
                ForEach(recipe.slots, id: \.self) { s in pill("\(s.emoji) \(s.label)") }
                if !recipe.cuisine.isEmpty { pill(recipe.cuisine) }
                pill(recipe.base.label)
                if let d = recipe.difficulty { pill(d.capitalized) }
                ForEach(recipe.tags) { t in pill("\(t.emoji) \(t.label)") }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(recipe.gradient))
    }

    private func pill(_ t: String) -> some View {
        Text(t).font(Theme.label(11)).padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(.black.opacity(0.25)))
    }

    private func macro(_ value: String, _ label: String, _ g: LinearGradient, _ ink: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(18)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(Theme.label(9)).opacity(0.85)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(g))
    }

    /// Ingredient line naming a food the member has at home.
    private func haveIngredient(_ line: String) -> Bool {
        let have = store.pantryIds
        guard !have.isEmpty else { return false }
        return FoodBook.find(in: line, own: store.saved.foods).contains { have.contains($0.id) }
    }

    private func ateIt() {
        if let eat {
            tick(eat.slot, plan: eat.plan, day: eat.day)
            dismiss()
        } else {
            choosingMeal = true
        }
    }

    private func tick(_ slot: FuelSlot, plan: FuelPlan, day: Date) {
        let servingsEaten = max(1, servings / max(1, recipe.servings))
        store.update(day, plan: plan) { $0.tick(slot, recipe: recipe, servings: servingsEaten) }
        eaten = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var shareText: String {
        var lines = ["\(recipe.emoji) \(recipe.name)", "\(recipe.minutes) min · \(servings) serving\(servings == 1 ? "" : "s")", "", "Ingredients:"]
        lines += recipe.ingredients.map { "• " + recipe.ingredient($0, servings: servings) }
        lines += ["", "Steps:"]
        lines += recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if let tip = recipe.tip { lines += ["", "Tip: \(tip)"] }
        lines += ["", "From MonkeyFit"]
        return lines.joined(separator: "\n")
    }
}

/// Cook mode: one big step at a time, the screen stays on, a timer when the step names minutes.
struct CookModeView: View {
    let recipe: Recipe
    let servings: Int
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var ends: Date?
    @State private var showIngredients = false

    private var minutes: Int? { Self.minutes(in: recipe.steps[step]) }

    /// First "12 min" / "10 minutes" / "5-7 min" in a step (upper bound of a range).
    static func minutes(in text: String) -> Int? {
        guard let r = text.range(of: #"(\d+)(\s*[-–]\s*(\d+))?\s*(min|minutes|mins)\b"#, options: .regularExpression) else { return nil }
        let nums = text[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return nums.last.flatMap { (1...240).contains($0) ? $0 : nil }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button { showIngredients.toggle() } label: {
                    Label(showIngredients ? "Steps" : "Ingredients", systemImage: showIngredients ? "list.number" : "basket.fill")
                        .font(Theme.label(14))
                }
                Spacer()
                Text("\(step + 1) / \(recipe.steps.count)").font(Theme.label(15)).monospacedDigit()
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .bold)) }
                    .accessibilityLabel("Close")
            }
            .foregroundStyle(.white)
            Text("\(recipe.emoji) \(recipe.name)").font(Theme.label(14)).foregroundStyle(Theme.muted)
            if showIngredients {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, l in
                            Text("• " + recipe.ingredient(l, servings: servings)).font(.title3.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
                Text(recipe.steps[step]).font(Theme.display(28)).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                if let m = minutes {
                    if let ends {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            let left = max(0, Int(ends.timeIntervalSince(ctx.date)))
                            Text(Format.elapsed(TimeInterval(left))).font(Theme.display(54)).monospacedDigit()
                                .foregroundStyle(left == 0 ? Theme.lime : .white)
                        }
                        Button("Stop timer") { self.ends = nil }.font(Theme.label(15)).foregroundStyle(Theme.muted)
                    } else {
                        Button { ends = Date().addingTimeInterval(Double(m) * 60) } label: {
                            Label("Start \(m) min timer", systemImage: "timer")
                        }
                        .buttonStyle(LimeButtonStyle(fill: Theme.cardStrong, text: .white))
                    }
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button { withAnimation(.snappy) { step = max(0, step - 1); ends = nil } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .heavy)).frame(width: 64, height: 56)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .disabled(step == 0)
                .accessibilityLabel("Previous step")
                if step < recipe.steps.count - 1 {
                    Button { withAnimation(.snappy) { step += 1; ends = nil } } label: { Text("NEXT STEP") }
                        .buttonStyle(LimeButtonStyle())
                } else {
                    Button { dismiss() } label: { Text("DONE · ENJOY") }
                        .buttonStyle(LimeButtonStyle())
                }
            }
            .foregroundStyle(.white)
        }
        .padding(20)
        .background(recipe.gradient.opacity(0.35).ignoresSafeArea())
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sensoryFeedback(.selection, trigger: step)
    }
}

/// Puts a recipe on a coming day's meal.
struct AddToPlanView: View {
    let recipe: Recipe
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared

    var body: some View {
        let cal = Calendar.current
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RecipeRow(recipe: recipe)
                ForEach(0..<7, id: \.self) { i in
                    if let d = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: Date())) {
                        let plan = model.fuelPlan(on: d)
                        let key = store.key(d)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.fuelDayLabel(key)).font(Theme.display(17))
                            FlowLayout(spacing: 6) {
                                ForEach(plan.slots.filter { recipe.slots.contains($0.recipeKind) || recipe.slots.contains($0.kind) }) { s in
                                    Button {
                                        store.pin(PlannedMeal(day: key, slot: s.id, kind: s.kind, recipeId: recipe.id, servings: store.saved.people))
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        dismiss()
                                    } label: {
                                        Text("\(s.kind.emoji) \(s.title) · \(s.time)").font(Theme.label(12))
                                            .foregroundStyle(Theme.ink)
                                            .padding(.horizontal, 10).padding(.vertical, 7)
                                            .background(Capsule().fill(Theme.lime))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 12)
                    }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Add to plan")
    }
}

/// The member's own recipe: name, meals, time, macros per serving, ingredients and steps (one per line).
/// Standard sheet chrome (#539): a new recipe has Save beside the X and keeps a draft; an existing one saves on its
/// own, and Delete removes it at once with Undo.
struct RecipeEditorView: View {
    let recipe: Recipe?
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var name = ""
    @State private var emoji = "🍽️"
    @State private var slots: Set<MealKind> = [.lunch, .dinner]
    @State private var minutes = 20
    @State private var servings = 1
    @State private var protein = 30
    @State private var carbs = 50
    @State private var fat = 15
    @State private var veg = 1
    @State private var base: RecipeBase = .poultry
    @State private var contains: Set<Allergen> = []
    @State private var ingredients = ""
    @State private var steps = ""
    @State private var loaded = false
    @State private var draftRestored = false
    /// Deleted from this screen: the auto-save on close must not write it back.
    @State private var removed = CloseGuard()

    private static let draftKey = "recipe-new"
    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !slots.isEmpty }

    var body: some View {
        List {
            ContentTitle(title: recipe == nil ? "New recipe" : "Edit recipe",
                         subtitle: recipe == nil ? "New recipe · Save to keep" : "Your recipe · saves as you go")
                .cardRow()
            if draftRestored {
                DraftRestoredStrip {
                    DraftStore.clear(Self.draftKey)
                    load(Self.blank)
                    draftRestored = false
                }
                .cardRow()
            }
            Section("Recipe") {
                HStack {
                    TextField("🍽️", text: $emoji).frame(width: 44).font(.title)
                        .accessibilityLabel("Emoji")
                    TextField("Name", text: $name).font(Theme.display(20))
                }
                .darkCardRow()
                Picker("Main ingredient", selection: $base) { ForEach(RecipeBase.allCases) { Text($0.label).tag($0) } }
                    .font(Theme.label(15))
                    .gradientRow(FuelPalette.violet)
                Stepper("\(minutes) min", value: $minutes, in: 0...240, step: 5)
                    .font(Theme.label(15))
                    .gradientRow(FuelPalette.water)
                Stepper("\(servings) serving\(servings == 1 ? "" : "s")", value: $servings, in: 1...12)
                    .font(Theme.label(15))
                    .gradientRow(FuelPalette.mint, ink: Theme.ink)
            }
            Section("Meals") {
                ForEach(MealKind.allCases) { k in
                    let on = slots.contains(k)
                    Button {
                        if on { slots.remove(k) } else { slots.insert(k) }
                    } label: {
                        HStack {
                            Text("\(k.emoji) \(k.label)").font(Theme.label(15))
                            Spacer()
                            SquareToggle(on: on)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .gradientRow(FuelPalette.hot)
                    .opacity(on ? 1 : 0.7)
                }
            }
            Section("Per serving") {
                Stepper("Protein \(protein) g", value: $protein, in: 0...150, step: 5)
                    .font(Theme.label(15)).gradientRow(FuelPalette.protein)
                Stepper("Carbs \(carbs) g", value: $carbs, in: 0...250, step: 5)
                    .font(Theme.label(15)).gradientRow(FuelPalette.carbs, ink: Theme.ink)
                Stepper("Fat \(fat) g", value: $fat, in: 0...120, step: 5)
                    .font(Theme.label(15)).gradientRow(FuelPalette.fats)
                Stepper("Veg \(veg) fist\(veg == 1 ? "" : "s")", value: $veg, in: 0...4)
                    .font(Theme.label(15)).gradientRow(FuelPalette.veg, ink: Theme.ink)
                Text("≈ \(4 * protein + 4 * carbs + 9 * fat) kcal").font(Theme.label(14)).foregroundStyle(Theme.muted).cardRow()
            }
            Section("Contains") {
                FlowLayout(spacing: 6) {
                    ForEach(Allergen.allCases) { a in
                        let on = contains.contains(a)
                        Button { if on { contains.remove(a) } else { contains.insert(a) } } label: {
                            Text(a.label).font(Theme.label(12)).foregroundStyle(on ? Theme.ink : .white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .cardRow()
            }
            Section("Ingredients · one per line") {
                TextEditor(text: $ingredients).frame(minHeight: 110).scrollContentBackground(.hidden).darkCardRow()
            }
            Section("Steps · one per line") {
                TextEditor(text: $steps).frame(minHeight: 140).scrollContentBackground(.hidden).darkCardRow()
            }
            if let recipe {
                Section {
                    Button("Delete recipe", role: .destructive) { delete(recipe) }
                        .font(Theme.label(15))
                        .darkCardRow()
                }
            }
        }
        .themedForm()
        .titleInContent(recipe == nil ? "New recipe" : "Edit recipe")
        .toolbar {
            if recipe == nil {
                SaveToolbarItem(disabled: !valid) { saveNew() }
            }
            CloseToolbarItem { dismiss() }
        }
        // An existing recipe saves on its own (#437); an empty name or no meal waits.
        .autoSave(recipe != nil && loaded && valid ? edited : nil, title: "Recipe", symbol: "fork.knife",
                  detail: { $0.name }, save: { [removed] r in if !removed.saved { FuelStore.shared.saveRecipe(Self.withKeys(r)) } })
        .keepsDraft(recipe == nil && loaded ? Self.draftKey : nil, edited, blank: Self.blank)
        .onAppear {
            guard !loaded else { return }
            if let recipe {
                load(recipe)
            } else if let d = DraftStore.load(Self.draftKey, as: Recipe.self) {
                load(d)
                draftRestored = true
            }
            loaded = true
        }
    }

    private func lines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// A new recipe's empty form, as the draft compares it.
    private static let blank = Recipe(id: "draft", name: "", slots: [.lunch, .dinner], minutes: 20, servings: 1,
                                      protein: 30, carbs: 50, fat: 15, veg: 1, base: .poultry)

    private func load(_ r: Recipe) {
        name = r.name
        emoji = r.emoji
        slots = Set(r.slots)
        minutes = r.minutes
        servings = r.servings
        protein = r.protein
        carbs = r.carbs
        fat = r.fat
        veg = r.veg
        base = r.base
        contains = Set(r.contains)
        ingredients = r.ingredients.joined(separator: "\n")
        steps = r.steps.joined(separator: "\n")
    }

    /// What's on screen as a recipe (food keys are matched when it's written, see `withKeys`).
    private var edited: Recipe {
        var r = Recipe(id: recipe?.id ?? "draft", name: name.trimmingCharacters(in: .whitespaces),
                       emoji: String(emoji.prefix(2)).isEmpty ? "🍽️" : String(emoji.prefix(2)),
                       slots: MealKind.allCases.filter { slots.contains($0) }, minutes: minutes, servings: servings,
                       protein: protein, carbs: carbs, fat: fat, veg: veg, base: base,
                       contains: Allergen.allCases.filter { contains.contains($0) },
                       tags: minutes <= 15 ? [.quick] : [], ingredients: lines(ingredients), steps: lines(steps))
        r.keys = recipe?.keys
        return r
    }

    private static func withKeys(_ recipe: Recipe) -> Recipe {
        var r = recipe
        let keys = Array(Set(r.ingredients.flatMap { FoodBook.find(in: $0).map(\.id) })).sorted()
        r.keys = keys.isEmpty ? nil : keys
        return r
    }

    private func saveNew() {
        var r = Self.withKeys(edited)
        r.id = "own-\(UUID().uuidString.lowercased())"
        DraftStore.clear(Self.draftKey)
        store.saveRecipe(r)
        dismiss()
    }

    /// Deleted at once (#539); Undo puts the recipe back as it was.
    private func delete(_ recipe: Recipe) {
        removed.done()
        store.deleteRecipe(recipe.id)
        dismiss()
        UndoCloseCenter.shared.deleted("\(recipe.name) deleted", symbol: "fork.knife") {
            FuelStore.shared.saveRecipe(recipe)
        }
    }
}
