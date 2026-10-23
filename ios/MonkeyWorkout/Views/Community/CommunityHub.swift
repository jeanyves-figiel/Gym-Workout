import APIClient
import LiftSensor
import SwiftUI
import WorkoutEngine

// Community tab redesign (#666, designs C + B from `community-redesign/proposals.png`): your gym today on top, small
// tiles, quick shares, then Feed · Plans · Fuel · Mine.

enum CommunityTab: Hashable { case feed, plans, fuel, mine }

/// What the quick share buttons open.
enum CommunitySheet: String, Identifiable {
    case plan, meal, tip, fuelTip
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
    /// Community → Fuel: shared recipes and fuel tips.
    var isFuel: Bool { isRecipe || tipTopic == .fuel }
}

// MARK: - C: your gym today

/// Hero: who trained at your gym today, who's live, the week challenge with a bar for the week and the top 3.
struct GymPulseCard: View {
    let posts: [CommunityPost]
    @Environment(AppModel.self) private var model
    private var live: LiveRoom { .shared }

    private static let gradient = LinearGradient(colors: [Color(hex: 0x3B6CFF), Color(hex: 0x9B3CFF)], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let trained = TrainedTodayRow.today(posts).count
        let liveNow = live.paired.filter { $0.live != nil }.count + (live.room?.training ?? 0)
        NavigationLink { ChallengeRoomView() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(gymName) · today").font(Theme.label(10)).tracking(1.2).textCase(.uppercase).opacity(0.85).lineLimit(1)
                        Text("\(trained) trained · \(liveNow) live now").font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "building.2.fill").font(.system(size: 24, weight: .bold)).opacity(0.9)
                }
                challenge
                podium
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Self.gradient))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(gymName) today: \(trained) trained, \(liveNow) live. Week challenge \(live.wod.name).")
    }

    private var gymName: String { model.profile?.gym?.name ?? Gym.puls5.name }

    private var challenge: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("🔥 \(live.wod.name) · AMRAP \(WeeklyChallenge.minutes)′ · \(live.room?.joined ?? 0) joined")
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(Self.left()).opacity(0.85)
            }
            .font(Theme.label(11))
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.25))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Theme.lime).frame(width: g.size.width * Self.weekDone())
                    }
                }
        }
    }

    @ViewBuilder private var podium: some View {
        let top = Array((live.room?.leaderboard ?? []).prefix(3))
        if top.isEmpty {
            Text("Nobody on the board yet: tap to take first place.").font(.caption.weight(.semibold)).opacity(0.9)
        } else {
            // Silver, gold, bronze: the winner stands in the middle, tallest.
            let order = top.count == 3 ? [1, 0, 2] : Array(top.indices)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(order, id: \.self) { i in
                    let e = top[i]
                    VStack(spacing: 1) {
                        Text(["🥇", "🥈", "🥉"][min(i, 2)]).font(.system(size: 14))
                        Text(e.me ? "You" : e.nickname).font(Theme.label(11)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(ChallengeRoomView.score(e)).font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: [58, 48, 42][min(i, 2)])
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(i == 0 ? Theme.lime.opacity(0.45) : .white.opacity(0.2)))
                }
            }
        }
    }

    private static var isoWeek: DateInterval? { Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: .now) }

    static func weekDone(now: Date = .now) -> Double {
        guard let w = isoWeek, w.duration > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(w.start) / w.duration))
    }

    static func left(now: Date = .now) -> String {
        guard let w = isoWeek else { return "" }
        let days = Calendar(identifier: .iso8601).dateComponents([.day], from: now, to: w.end).day ?? 0
        return days <= 0 ? "last day" : "\(days + (days < 6 ? 1 : 0)) days left"
    }
}

/// Three small tiles instead of three full-width cards: gym, members, buddies.
struct CommunityTiles: View {
    @Environment(AppModel.self) private var model
    private var community: Community { .shared }
    private var live: LiveRoom { .shared }

    var body: some View {
        let liveCount = live.paired.filter { $0.live != nil }.count
        HStack(spacing: 8) {
            NavigationLink { ProfileSectionView(section: .gym) } label: {
                tile("building.2.fill", "\(model.profile?.equipment.count ?? 0)", "Gym items", WorkoutEngine.Category.strength.gradient)
            }
            .accessibilityLabel("Your gym, \(model.profile?.equipment.count ?? 0) items")
            NavigationLink { FindMembersView() } label: {
                tile("magnifyingglass", "\(community.profile?.following ?? 0)", "Following", WorkoutEngine.Category.cardio.gradient)
            }
            .accessibilityLabel("Find members. Following \(community.profile?.following ?? 0).")
            NavigationLink { BuddiesScreen() } label: {
                tile("figure.2", live.invites.isEmpty ? "\(liveCount)" : "\(live.invites.count)", live.invites.isEmpty ? "Buddies live" : "Invites",
                     LinearGradient(colors: [Color(hex: 0x00B86B), Color(hex: 0x1E9BFF)], startPoint: .topLeading, endPoint: .bottomTrailing),
                     badge: !live.invites.isEmpty)
            }
            .accessibilityLabel(live.invites.isEmpty ? "Gym buddies, \(liveCount) live" : "Gym buddies, \(live.invites.count) invites")
        }
        .buttonStyle(.plain)
    }

    private func tile(_ symbol: String, _ value: String, _ label: String, _ gradient: LinearGradient, badge: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.22)))
                Spacer(minLength: 0)
                if badge { Circle().fill(Theme.lime).frame(width: 10, height: 10) }
            }
            Spacer(minLength: 6)
            Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1)
            Text(label).font(Theme.label(9)).tracking(1).textCase(.uppercase).opacity(0.88).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient))
        .contentShape(Rectangle())
    }
}

/// Share plan · Share meal · Post a tip.
struct QuickShareRow: View {
    let open: (CommunitySheet) -> Void

    var body: some View {
        HStack(spacing: 8) {
            button(.plan, "Share plan", "calendar", [Color(hex: 0xFF3CAC), Color(hex: 0x784BA0)])
            button(.meal, "Share meal", "fork.knife", TipTopic.fuel.colors)
            button(.tip, "Post a tip", "lightbulb.fill", TipTopic.train.colors)
        }
    }

    private func button(_ s: CommunitySheet, _ title: String, _ symbol: String, _ colors: [Color]) -> some View {
        Button { open(s) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                Text(title).font(Theme.display(14)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Gym buddies on their own page, opened from the Buddies tile.
struct BuddiesScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            BuddiesCard().padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Gym buddies")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await LiveRoom.shared.load(api: model.api) }
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

// MARK: - B: Plans

/// Community → Plans: members' programmes by level, and the invite to share yours.
struct PlansSection: View {
    let share: () -> Void
    @Environment(AppModel.self) private var model
    @State private var level: SharedPlanLevel?
    private var store: SharedPlans { .shared }
    private var levels: [(SharedPlanLevel?, String)] {
        [(nil, "All levels")] + SharedPlanLevel.allCases.map { (Optional($0), $0.title) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FilterChips(selection: $level, items: levels)
            ErrorText(message: store.error)
            if store.plans.isEmpty && store.loaded && !store.loading {
                Text(level.map { "No \($0.title.lowercased()) plans yet." } ?? "No member plans yet. Be the first to share yours.")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                    .padding(.vertical, 6)
            } else if !store.loaded {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
            ForEach(store.plans) { p in
                NavigationLink { SharedPlanView(plan: p) } label: { SharedPlanCard(plan: p) }
                    .buttonStyle(.plain)
            }
            ShareInviteCard(title: "Share your programme",
                            message: "Your own programme, weeks and signature workouts. Members copy it and the app builds it for their gym.",
                            action: "SHARE MY PLAN", tap: share)
        }
        .task { if !store.loaded { await store.load(api: model.api) } }
        .onChange(of: level) { _, l in Task { await store.load(api: model.api, level: l) } }
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
    @State private var confirmUnshare = false
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
                    ForEach(p.signatures) { s in
                        HStack {
                            Text(s.name).font(Theme.display(15)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(s.items.count) exercises").font(Theme.label(11)).foregroundStyle(Theme.muted)
                        }
                        .card(padding: 12)
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
        .confirmationDialog("Stop sharing this plan?", isPresented: $confirmUnshare, titleVisibility: .visible) {
            Button("Stop sharing", role: .destructive) {
                Task {
                    await SharedPlans.shared.unshare(plan, api: model.api)
                    dismiss()
                }
            }
        } message: {
            Text("Members who copied it keep their copy. Your programme stays in My programmes.")
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
            Button("STOP SHARING") { confirmUnshare = true }
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
                SharedPlans.shared.blocked(plan.author.userId)
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
    @State private var picked: Programme?
    @State private var level: SharedPlanLevel = .intermediate
    @State private var about = ""
    @State private var visibility: CommunityVisibility = .members
    @State private var task = FormTask()

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
                                .onChange(of: about) { _, v in if v.count > 200 { about = String(v.prefix(200)) } }
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
        task.run {
            try await SharedPlans.shared.share(picked, level: level, about: text.isEmpty ? nil : text, visibility: visibility, api: model.api)
            dismiss()
        }
    }
}

// MARK: - Fuel and tips

/// Community → Fuel: members' recipes and fuel tips, with invites to share yours.
struct FuelSection: View {
    let open: (CommunitySheet) -> Void
    private var community: Community { .shared }

    var body: some View {
        let posts = community.posts(.members).filter(\.isFuel)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ShareInviteCard(title: "A meal", message: "Recipe with its macros.", action: "SHARE") { open(.meal) }
                ShareInviteCard(title: "A tip", message: "Swap, prep, timing.", action: "POST") { open(.fuelTip) }
            }
            if posts.isEmpty {
                Text("No recipes or fuel tips from members yet.").font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            }
            ForEach(posts) { PostCard(post: $0) }
        }
    }
}

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
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: TipTopic?
    @State private var text = ""
    @State private var visibility: CommunityVisibility = .members
    @State private var task = FormTask()

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
                        .onChange(of: text) { _, v in if v.count > 280 { text = String(v.prefix(280)) } }
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
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func card(_ t: TipTopic) -> CommunityCard {
        CommunityCard(title: t == .train ? "💡 Train tip" : "🥗 Fuel tip", style: "tip:\(t.rawValue)")
    }

    private func post() {
        let t = current
        let tip = trimmed
        task.run {
            #if DEBUG
            if model.demo {
                let me = CommunityAuthor(userId: "demo", nickname: Community.shared.profile?.nickname ?? "me")
                Community.shared.insert(CommunityPost(id: UUID().uuidString, author: me, mine: true, kind: "note", visibility: visibility,
                                                      caption: tip, payload: Self.card(t), createdAt: Date()))
                dismiss()
                return
            }
            #endif
            let post = try await model.api.sharePost(kind: "note", refId: nil, visibility: visibility, caption: tip, card: Self.card(t))
            Community.shared.insert(post)
            dismiss()
        }
    }
}
