import APIClient
import LiftSensor
import SwiftUI
import WorkoutEngine

// Social hub pieces (#666, simpler in #738): buddies, member plans, shared meals and tips.

/// What the Share sheet opens.
enum CommunitySheet: String, Identifiable {
    case win, plan, meal, tip
    var id: String { rawValue }
}

/// Train or fuel advice, posted as a note card (style "tip:train|fuel", text in the caption; no server change).
enum TipTopic: String, CaseIterable, Identifiable {
    case train, fuel
    var id: String { rawValue }
    var title: String { self == .train ? "Train tip" : "Fuel tip" }
    var symbol: String { self == .train ? "dumbbell.fill" : "fork.knife" }
    var colors: [Color] {
        self == .train ? [Color(hex: 0x00C6FF), Color(hex: 0x0062FF)] : [Color(hex: 0x6CC000), Color(hex: 0x0E9F6E)]
    }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

extension CommunityPost {
    var tipTopic: TipTopic? {
        guard kind == "note", let s = payload.style, s.hasPrefix("tip:") else { return nil }
        return TipTopic(rawValue: String(s.dropFirst(4)))
    }
    var isRecipe: Bool { kind == "note" && refId?.hasPrefix("recipe-") == true }
}

/// Gym buddies on their own page, opened from the Buddies tile.
struct BuddiesScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            BuddiesCard().padding(16)
                .scopedRefreshable { await LiveRoom.shared.load(api: model.api) }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Gym buddies")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Dashed lime card inviting a share: "Share your programme", "Share a meal"…
struct ShareInviteCard: View {
    let title: String
    let message: String
    let action: String
    let tap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.display(18))
            Text(message).font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            Button(action, action: tap)
                .font(Theme.label(12)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
                .buttonStyle(.plain)
                .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.lime.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }
}

/// Small lime-or-dark chips for filters inside a tab.
struct FilterChips<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(Value, String)]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    let value = items[i].0
                    let on = value == selection
                    Button { selection = value } label: {
                        Text(items[i].1).font(Theme.label(12))
                            .padding(.horizontal, 12).frame(minHeight: 32)
                            .foregroundStyle(on ? Theme.ink : .white)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.lime : Theme.cardStrong))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// Explore-style card: icon tile, name, who · weeks · days · level, copies on the right.
struct SharedPlanCard: View {
    let plan: MemberPlan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.programme.symbol).font(.system(size: 20, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.name).font(Theme.display(17)).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(plan.mine ? "You" : plan.author.nickname) · \(plan.weeks) wk · \(plan.sessionsPerWeek)×/wk · \(plan.level.title)")
                    .font(.caption.weight(.semibold)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.8)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(plan.copies)").font(Theme.display(24)).monospacedDigit()
                Text("COPIES").font(Theme.label(9)).tracking(1).opacity(0.85)
            }
            .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(plan.programme.palette.gradient))
        .opacity(plan.hidden ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One shared plan: what it is, its phases and signature workouts; copy it into My programmes, then start it there.
struct SharedPlanView: View {
    let plan: MemberPlan
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Programme?
    @State private var copying = false
    @State private var confirmBlock = false
    @State private var notice: String?

    private var p: Programme { plan.programme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                stats
                if let about = plan.about, !about.isEmpty {
                    Text("“\(about)”").font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading).card(padding: 14)
                }
                if !p.summary.isEmpty { Text(p.summary).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85)) }
                Text("Phases").eyebrow()
                ForEach(Array(p.phases.enumerated()), id: \.offset) { _, ph in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(ph.weeks) wk").font(Theme.label(12)).frame(width: 50, height: 32)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ph.kind.label).font(Theme.display(15))
                            if !ph.note.isEmpty { Text(ph.note).font(.caption.weight(.medium)).foregroundStyle(Theme.muted) }
                        }
                    }
                }
                if !p.signatures.isEmpty {
                    Text("Signature workouts").eyebrow()
                    // Gradient tiles, number left (#823).
                    ForEach(Array(p.signatures.enumerated()), id: \.element.id) { i, s in
                        GradientTile(gradient: Theme.routineGradient(i), number: "\(i + 1)", title: s.name,
                                     detail: "\(s.items.count) exercises")
                            .accessibilityElement(children: .combine)
                    }
                }
                actions
                if let notice { Text(notice).font(.footnote.weight(.semibold)).foregroundStyle(Theme.lime) }
                ErrorText(message: SharedPlans.shared.error)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !plan.mine {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu("Report") {
                            ForEach(CommunityReportReason.allCases) { r in
                                Button(r.rawValue.capitalized) { report(r) }
                            }
                        }
                        Button("Block \(plan.author.nickname)", role: .destructive) { confirmBlock = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
                }
            }
        }
        .confirmationDialog("Block \(plan.author.nickname)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { block() }
        } message: {
            Text("You won't see each other's posts, plans or profiles. Unblock any time from Your profile.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: p.symbol).font(.system(size: 24, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.7)
                    if !p.tagline.isEmpty { Text(p.tagline).font(.footnote.weight(.semibold)).opacity(0.9) }
                }
            }
            if plan.mine {
                Label("Shared by you · \(plan.visibility == .onlyMe ? "only you" : "members")", systemImage: "person.fill").font(Theme.label(12))
            } else {
                NavigationLink(value: plan.author) {
                    HStack(spacing: 8) {
                        AvatarView(url: model.api.resolve(plan.author.avatarUrl), nickname: plan.author.nickname, size: 26)
                        Text("by \(plan.author.nickname)").font(Theme.label(13))
                        Image(systemName: "chevron.right").font(.caption2.bold()).opacity(0.7)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(p.palette.gradient))
    }

    private var stats: some View {
        HStack(spacing: 8) {
            stat("\(plan.weeks)", "weeks")
            stat("\(plan.sessionsPerWeek)×", "per week")
            stat(plan.level.title, "level")
            stat("\(plan.copies)", "copies")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(Theme.label(9)).tracking(1).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }

    @ViewBuilder private var actions: some View {
        if plan.mine {
            Button("STOP SHARING") { unshare() }
                .buttonStyle(LimeButtonStyle(fill: Theme.cardStrong, text: .white))
        } else if let copied {
            NavigationLink { ProgrammeDetailView(programme: copied) } label: {
                Text("OPEN AND START").frame(maxWidth: .infinity)
            }
            .buttonStyle(LimeButtonStyle())
        } else {
            Button(copying ? "COPYING…" : "COPY TO MY PROGRAMMES") {
                copying = true
                Task {
                    copied = await SharedPlans.shared.copy(plan, model: model)
                    copying = false
                    notice = "In My programmes. The app builds each week for your gym, days and time."
                }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(copying)
        }
    }

    /// Stops at once (#717); the Undo bar shares it again as it was. Copies members made stay theirs.
    private func unshare() {
        let api = model.api
        Task {
            await SharedPlans.shared.unshare(plan, api: api)
            dismiss()
            UndoCloseCenter.shared.deleted("Plan no longer shared", detail: plan.name, symbol: "eye.slash.fill") { [plan] in
                Task { @MainActor in
                    try? await SharedPlans.shared.share(plan.programme, level: plan.level, about: plan.about, visibility: plan.visibility, api: api)
                }
            }
        }
    }

    private func report(_ reason: CommunityReportReason) {
        Task {
            await SharedPlans.shared.report(plan, reason: reason, api: model.api)
            dismiss()
        }
    }

    private func block() {
        Task {
            do {
                if !model.demo { try await model.api.block(plan.author.userId) }
                Community.shared.blocked(plan.author.userId)
                dismiss()
            } catch {
                SharedPlans.shared.error = error.localizedDescription
            }
        }
    }
}

/// Share one of My programmes, with its level and a line about it.
struct SharePlanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Values brought back by Undo (#717).
    var restoring: Draft?

    /// What's picked and typed, kept for Undo.
    struct Draft {
        var picked: Programme
        var level: SharedPlanLevel
        var about: String
        var visibility: CommunityVisibility
    }

    @State private var picked: Programme?
    @State private var level: SharedPlanLevel = .intermediate
    @State private var about = ""
    @State private var visibility: CommunityVisibility = .members
    @State private var task = FormTask()
    @State private var closeGuard = CloseGuard()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.myProgrammes.isEmpty {
                        ShareInviteCard(title: "Build your programme first",
                                        message: "Explore → Programmes → Build your own, or make a catalog programme yours. Then share it here.",
                                        action: "OPEN PROGRAMMES") {
                            dismiss()
                            model.openExploreProgrammes()
                        }
                    } else {
                        Text("Which programme").eyebrow()
                        ForEach(model.myProgrammes) { p in
                            Button { pick(p) } label: { row(p, on: picked?.id == p.id) }
                                .buttonStyle(.plain)
                        }
                        if picked != nil {
                            Text("Level").eyebrow()
                            FilterChips(selection: $level, items: SharedPlanLevel.allCases.map { l -> (SharedPlanLevel, String) in (l, l.title) })
                            Text("Say something").eyebrow()
                            TextField("Who it suits, what it did for you…", text: $about, axis: .vertical)
                                .lineLimit(1...4)
                                .card(padding: 14)
                                .onChange(of: about) { _, v in if v.utf16.count > 200 { about = v.utf16Capped(200) } }
                            Text("Who can see it").eyebrow()
                            VisibilityPicker(selection: $visibility)
                            ErrorText(message: task.error)
                            Button(task.busy ? "SHARING…" : alreadyShared ? "UPDATE" : "SHARE") { share() }
                                .buttonStyle(LimeButtonStyle())
                                .disabled(task.busy)
                        }
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Share plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .task { if !SharedPlans.shared.loaded { await SharedPlans.shared.load(api: model.api) } }
        }
        .preferredColorScheme(.dark)
        .undoableClose(closeGuard, offer: undoOffer)
        .onAppear {
            guard let restoring, picked == nil else { return }
            picked = restoring.picked
            level = restoring.level
            about = restoring.about
            visibility = restoring.visibility
        }
    }

    /// Undo bar when a programme was picked and something typed (#717).
    private var undoOffer: UndoOffer? {
        guard let picked, !about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let kept = Draft(picked: picked, level: level, about: about, visibility: visibility)
        return UndoOffer(title: "Share closed", detail: undoDetail(picked.name, "“\(about)”"), symbol: "calendar") {
            AnyView(SharePlanSheet(restoring: kept))
        }
    }

    private var alreadyShared: Bool { picked.map { SharedPlans.shared.sharedPlan(of: $0) != nil } ?? false }

    private func pick(_ p: Programme) {
        picked = p
        if let s = SharedPlans.shared.sharedPlan(of: p) {
            level = s.level
            about = s.about ?? ""
            visibility = s.visibility
        }
    }

    private func row(_ p: Programme, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: p.symbol).font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(Theme.display(16)).lineLimit(1)
                Text("\(p.weeks) wk · \(p.sessionsPerWeek)×/wk\(SharedPlans.shared.sharedPlan(of: p) != nil ? " · shared" : "")")
                    .font(.caption.weight(.semibold)).opacity(0.9)
            }
            Spacer(minLength: 4)
            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(p.palette.gradient))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.lime, lineWidth: on ? 3 : 0))
        .contentShape(Rectangle())
    }

    private func share() {
        guard let picked else { return }
        let text = about.trimmingCharacters(in: .whitespacesAndNewlines)
        let closing = closeGuard
        task.run {
            try await SharedPlans.shared.share(picked, level: level, about: text.isEmpty ? nil : text, visibility: visibility, api: model.api)
            closing.done()
            dismiss()
        }
    }
}

// MARK: - Fuel and tips

/// Share meal: pick one of your recipes or favourites (or a popular one), then the usual Share recipe sheet.
struct ShareMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var recipe: Recipe?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Self.mine.isEmpty ? "Popular recipes" : "Your recipes and favourites").eyebrow()
                    ForEach(Self.mine.isEmpty ? Array(RecipeBook.catalog.prefix(8)) : Self.mine) { r in
                        Button { recipe = r } label: {
                            HStack(spacing: 12) {
                                PlatePicture(recipe: r, size: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(r.emoji) \(r.name)").font(Theme.display(15)).lineLimit(2)
                                    Text("\(r.protein) g protein · \(r.kcal) kcal · \(r.minutes) min").font(.caption.weight(.semibold)).opacity(0.85)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(TipTopic.fuel.gradient))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Share meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(item: $recipe, onDismiss: { dismiss() }) { ShareRecipeSheet(recipe: $0) }
        }
        .preferredColorScheme(.dark)
    }

    @MainActor static var mine: [Recipe] {
        let s = FuelStore.shared.saved
        return s.recipes + RecipeBook.catalog.filter { s.favourites.contains($0.id) }
    }
}

/// Post a tip: train or fuel, up to 280 characters, members by default.
struct PostTipSheet: View {
    var topic: TipTopic = .train
    /// Text brought back by Undo (#717).
    var restoring: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: TipTopic?
    @State private var text = ""
    @State private var visibility: CommunityVisibility = .members
    @State private var task = FormTask()
    @State private var closeGuard = CloseGuard()

    private var current: TipTopic { picked ?? topic }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(TipTopic.allCases) { t in
                            let on = t == current
                            Button { picked = t } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: t.symbol).font(.title3.bold())
                                    Text(t.title).font(Theme.label(13))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? AnyShapeStyle(t.gradient) : AnyShapeStyle(Theme.card)))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.lime, lineWidth: on ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    Text("Your tip").eyebrow()
                    TextField(current == .train ? "Film your squat from the side once a month…" : "Prep 3 boxes on Sunday…",
                              text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .card(padding: 14)
                        .onChange(of: text) { _, v in if v.utf16.count > 280 { text = v.utf16Capped(280) } }
                    Text("\(text.count)/280").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                    Text("Who can see it").eyebrow()
                    VisibilityPicker(selection: $visibility)
                    ErrorText(message: task.error)
                    Button(task.busy ? "POSTING…" : "POST TIP") { post() }
                        .buttonStyle(LimeButtonStyle())
                        .disabled(task.busy || trimmed.count < 8)
                }
                .padding(16)
            }
            .readableWidth()
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Post a tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .undoableClose(closeGuard, offer: undoOffer)
        .onAppear { if let restoring, text.isEmpty { text = restoring } }
    }

    /// Undo bar when something was typed (#717).
    private var undoOffer: UndoOffer? {
        guard !trimmed.isEmpty else { return nil }
        let kept = text
        let t = current
        return UndoOffer(title: "Tip closed", detail: "“\(trimmed)”", symbol: "lightbulb.fill", colors: t.colors) {
            AnyView(PostTipSheet(topic: t, restoring: kept))
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func card(_ t: TipTopic) -> CommunityCard {
        CommunityCard(title: t == .train ? "💡 Train tip" : "🥗 Fuel tip", style: "tip:\(t.rawValue)")
    }

    private func post() {
        let t = current
        let tip = trimmed
        let closing = closeGuard
        task.run {
            #if DEBUG
            if model.demo {
                let me = CommunityAuthor(userId: "demo", nickname: Community.shared.profile?.nickname ?? "me")
                Community.shared.insert(CommunityPost(id: UUID().uuidString, author: me, mine: true, kind: "note", visibility: visibility,
                                                      caption: tip, payload: Self.card(t), createdAt: Date()))
                closing.done()
                dismiss()
                return
            }
            #endif
            let post = try await model.api.sharePost(kind: "note", refId: nil, visibility: visibility, caption: tip, card: Self.card(t))
            Community.shared.insert(post)
            closing.done()
            dismiss()
        }
    }
}
