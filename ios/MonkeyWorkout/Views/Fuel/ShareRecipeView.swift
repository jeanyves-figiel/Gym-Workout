import APIClient
import SwiftUI
import WorkoutEngine

/// Share a recipe to Community (#496): posted as a note card (refId "recipe-<id>", no server change), with the
/// macros per serving as stats. Sharing again updates the same post.
struct ShareRecipeSheet: View {
    let recipe: Recipe
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var visibility: CommunityVisibility = Community.shared.profile?.defaultVisibility ?? .onlyMe
    @State private var task = FormTask()

    static func card(_ r: Recipe) -> CommunityCard {
        CommunityCard(title: "\(r.emoji) \(r.name)", subtitle: ["Recipe", "\(r.minutes) min", r.cuisine].filter { !$0.isEmpty }.joined(separator: " · "),
                      metric: .init(value: "\(r.protein)", unit: "g protein"), style: WorkoutEngine.Category.cardio.rawValue,
                      stats: [.init(label: "carbs g", value: "\(r.carbs)"), .init(label: "fat g", value: "\(r.fat)"),
                              .init(label: "kcal", value: "\(r.kcal)"), .init(label: "min", value: "\(r.minutes)")])
    }

    var body: some View {
        let card = Self.card(recipe)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        PlatePicture(recipe: recipe, size: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title).font(Theme.display(18)).lineLimit(2)
                            Text(card.subtitle ?? "").font(.footnote.weight(.medium)).opacity(0.85)
                        }
                        Spacer(minLength: 6)
                        AccountValue(value: "\(recipe.protein)", unit: "g protein")
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(card.gradient))

                    if Community.shared.profile == nil {
                        Text("Join Community first (Community tab) to share recipes with other members.")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted).card()
                    } else {
                        Text("Say something").eyebrow()
                        TextField("Why you like it, a swap you made…", text: $caption, axis: .vertical)
                            .lineLimit(1...4)
                            .card(padding: 14)
                            .onChange(of: caption) { _, v in if v.count > 280 { caption = String(v.prefix(280)) } }
                        Text("Who can see it").eyebrow()
                        VisibilityPicker(selection: $visibility)
                        ErrorText(message: task.error)
                        Button(task.busy ? "SHARING…" : "SHARE") { share(card) }
                            .buttonStyle(LimeButtonStyle())
                            .disabled(task.busy)
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Share recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private func share(_ card: CommunityCard) {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        task.run {
            #if DEBUG
            if model.demo {
                dismiss()
                return
            }
            #endif
            let post = try await model.api.sharePost(kind: "note", refId: String("recipe-\(recipe.id)".prefix(64)), visibility: visibility,
                                                     caption: text.isEmpty ? nil : text, card: card)
            Community.shared.insert(post)
            dismiss()
        }
    }
}
