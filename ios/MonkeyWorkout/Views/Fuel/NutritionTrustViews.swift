import APIClient
import SwiftUI
import WorkoutEngine

// Where Fuel's numbers come from (#1017, design A + B + C from `nutrition-accuracy/proposals.png`):
// A trust card under a recipe's macros (Checked values + Members), B the per-ingredient source list behind
// Checked values, C a Checked / ≈ Estimate badge and the review sheet after "I ate this".

extension FoodSource {
    var tint: Color {
        switch kind {
        case .usda: Color(hex: 0x3D5AFF)
        case .label: Color(hex: 0xFF9A3C)
        case .openFoodFacts: Color(hex: 0x1FC8A0)
        case .estimate: Color(hex: 0xA43DFF)
        }
    }
}

/// Checked / ≈ Estimate pill (C), on recipe heroes and on numbers the app or AI guessed.
struct TrustBadge: View {
    let checked: Bool
    var detail: String?

    init(_ level: RecipeTrust.Level) {
        switch level {
        case .checked: checked = true; detail = nil
        case .mostlyChecked: checked = true; detail = nil
        case .estimate: checked = false; detail = nil
        }
    }

    init(estimate: Bool, detail: String? = nil) {
        checked = !estimate
        self.detail = detail
    }

    var body: some View {
        Text(checked ? "✓ CHECKED" : "≈ ESTIMATE\(detail.map { " · \($0)" } ?? "")")
            .font(Theme.label(11)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(checked ? Theme.lime : Color(hex: 0xFF9A3C)))
            .accessibilityLabel(checked ? "Checked values" : "Estimated values")
    }
}

/// A: under the macros. Checked values opens the per-ingredient sources (B); Members shows the review score.
struct RecipeTrustCard: View {
    let recipe: Recipe
    let trust: RecipeTrust
    @Binding var reviewing: RecipeReviewSheet.Start?
    @State private var reviews = RecipeReviewStore.shared

    var body: some View {
        VStack(spacing: 8) {
            NavigationLink { RecipeSourcesView(recipe: recipe, trust: trust) } label: {
                row(icon: trust.level == .estimate ? "questionmark" : "checkmark", gradient: FuelPalette.violet,
                    title: trust.level == .estimate ? "Estimated values" : "Checked values", sub: sourceLine, big: nil)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows where each ingredient's numbers come from")
            if RecipeReviewStore.reviewable(recipe) {
                let s = reviews.summaries[recipe.id]
                row(icon: "star.fill", gradient: FuelPalette.coach, title: "Members", sub: membersLine(s),
                    big: s?.stars.map { String(format: "%.1f", $0) })
                HStack(spacing: 8) {
                    Button { reviewing = .cooked } label: {
                        Label(reviews.mine[recipe.id] == nil ? "I cooked it" : "Your review", systemImage: "star.fill")
                            .font(Theme.label(14)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FuelPalette.lime))
                    }
                    Button { reviewing = .valuesWrong } label: {
                        Label("Values look wrong", systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.label(14)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceLine: String {
        switch trust.level {
        case .checked: "USDA FoodData Central · \(trust.lines.count) of \(trust.lines.count) ingredients · totals add up"
        case let .mostlyChecked(labels):
            "USDA for \(trust.checkedCount) of \(trust.lines.count) ingredients, \(labels) typical label value\(labels == 1 ? "" : "s") · totals add up"
        case .estimate: recipe.isOwn ? "Your own numbers, not checked" : "Not computed from checked ingredients"
        }
    }

    private func membersLine(_ s: RecipeReviewSummary?) -> String {
        guard let s, s.reviews > 0 else { return "No reviews yet · be the first" }
        return "\(s.reviews) review\(s.reviews == 1 ? "" : "s") · \(s.flagged) flagged values"
    }

    private func row(icon: String, gradient: LinearGradient, title: String, sub: String, big: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .heavy))
                .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.black.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(17))
                Text(sub).font(.caption.weight(.semibold)).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let big { Text(big).font(Theme.display(28)) } else { Image(systemName: "chevron.right").font(.footnote.weight(.bold)).opacity(0.8) }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient))
    }
}

/// B: every ingredient with its grams, its source chip and the kcal it adds per serving.
struct RecipeSourcesView: View {
    let recipe: Recipe
    let trust: RecipeTrust

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ContentTitle(title: "Where the numbers come from")
                if trust.lines.isEmpty {
                    Text(recipe.isOwn ? "You entered these numbers yourself. Add ingredients from the food list to have them added up for you."
                                      : "These numbers aren't computed from ingredients, so treat them as an estimate.")
                        .font(.body.weight(.semibold)).foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(trust.lines) { l in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Int(l.grams)) g \(l.name)").font(.body.weight(.semibold))
                                    if let ref = l.source.ref { Text(ref).font(.caption2.weight(.medium)).foregroundStyle(Theme.muted) }
                                }
                                Spacer(minLength: 6)
                                Text(l.source.chip).font(Theme.label(10)).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(l.source.tint))
                                Text("\(l.kcal)").font(Theme.display(15)).foregroundStyle(Theme.lime).frame(minWidth: 36, alignment: .trailing)
                            }
                            .padding(.vertical, 9)
                            .accessibilityElement(children: .combine)
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                    .card(padding: 14)
                    if let m = trust.computed {
                        Text("Added up per serving: \(Int(m.protein.rounded())) g protein · \(Int(m.carbs.rounded())) g carbs · \(Int(m.fat.rounded())) g fat · \(Int(m.kcal.rounded())) kcal. Right column: kcal per serving.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    legend(FoodSource(kind: .usda), "Matched to the USDA FoodData Central entry shown, raw or dry weight unless it says cooked.")
                    legend(FoodSource(kind: .label), "Typical European label values for this kind of product. Brands differ a little.")
                    legend(FoodSource(kind: .openFoodFacts), "Read from Open Food Facts by barcode, entered by its community.")
                    legend(FoodSource(kind: .estimate), "Guessed (photo scan, meal ideas) or entered by you.")
                }
                .card(padding: 14)
                Text("Pointers, not prescriptions: weigh dry foods dry, and check a packet's label when it differs.")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .titleInContent("Sources")
    }

    private func legend(_ s: FoodSource, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(s.chip).font(Theme.label(10)).foregroundStyle(.white).frame(minWidth: 40)
                .padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(s.tint))
            Text(text).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// C: stars, numbers and cooking chips. Opened by I cooked it, Values look wrong, or once after I ate this.
struct RecipeReviewSheet: View {
    enum Start: String, Identifiable { case cooked, valuesWrong, ate; var id: String { rawValue } }

    let recipe: Recipe
    let start: Start
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reviews = RecipeReviewStore.shared
    @State private var draft = RecipeReview()
    @State private var sending = false
    @State private var failed = false

    private static let numbers: [(String, String)] = [("right", "Look right"), ("portion-big", "Portion too big"), ("portion-small", "Too small"), ("kcal-off", "kcal off")]
    private static let cooking: [(String, String)] = [("easy", "Easy"), ("steps-unclear", "Steps unclear"), ("took-longer", "Took longer")]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ContentTitle(title: start == .valuesWrong ? "What looks wrong?" : "How was \(recipe.name)?")
                    if start != .valuesWrong {
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { n in
                                Button { draft.stars = n } label: {
                                    Image(systemName: n <= (draft.stars ?? 0) ? "star.fill" : "star")
                                        .font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.lime)
                                        .frame(width: 48, height: 48)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
                            }
                        }
                    }
                    Text("NUMBERS").font(Theme.label(12)).foregroundStyle(Theme.muted)
                    chips(Self.numbers, selected: draft.numbers) { draft.numbers = $0 }
                    if start != .valuesWrong {
                        Text("COOKING").font(Theme.label(12)).foregroundStyle(Theme.muted)
                        chips(Self.cooking, selected: draft.cooking) { draft.cooking = $0 }
                    }
                    if failed {
                        Text("Couldn't send. Check your connection and try again.").font(.footnote.weight(.bold)).foregroundStyle(Color(hex: 0xFF5F8F))
                    }
                    Text("Reviews are anonymous: members see the counts, never who said what. Flagged numbers are checked and fixed.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    Button { send() } label: { Text(sending ? "Sending…" : "Send review") }
                        .buttonStyle(LimeButtonStyle())
                        .disabled(draft.isEmpty || sending)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .titleInContent("Review")
            .toolbar { CloseToolbarItem { close() } }
        }
        .onAppear {
            draft = reviews.mine[recipe.id] ?? RecipeReview()
            if start == .valuesWrong, draft.numbers == "right" { draft.numbers = nil }
        }
        .presentationDetents([.medium, .large])
    }

    private func chips(_ items: [(String, String)], selected: String?, pick: @escaping (String?) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                let key = items[i].0
                SelectChip(title: items[i].1, on: selected == key, onFill: AnyShapeStyle(Theme.lime), fills: false) {
                    pick(selected == key ? nil : key)
                }
            }
        }
    }

    private func close() {
        if start == .ate { reviews.markPrompted(recipe.id) }
        dismiss()
    }

    private func send() {
        sending = true
        failed = false
        Task {
            do {
                try await reviews.save(recipe.id, draft, api: model.api, demo: model.demo)
                dismiss()
            } catch {
                failed = true
            }
            sending = false
        }
    }
}
