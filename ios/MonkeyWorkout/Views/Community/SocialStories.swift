import APIClient
import SwiftUI
import WorkoutEngine

// Social, simpler (#738, design B from `social-simplify/b.png`): a square story row on top (live buddies, the week
// challenge, members who trained today), then one mixed feed. Replaces the gym card, stat tiles, share row and tabs.

/// Square story tiles: Live / Invites, the week challenge, each member who trained today, then Invite (#745).
struct SocialStoriesRow: View {
    let posts: [CommunityPost]
    @State private var story: StoryStart?
    private var live: LiveRoom { .shared }

    var body: some View {
        let today = TrainedToday.today(posts)
        let liveNow = live.paired.filter { $0.live != nil }.count + (live.room?.training ?? 0)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                if liveNow > 0 {
                    NavigationLink { BuddiesScreen() } label: { tile("🔴", "Live \(liveNow)", LinearGradient.buddies, ring: Color(hex: 0xFF3B5C)) }
                        .accessibilityLabel("\(liveNow) training live now")
                } else if !live.invites.isEmpty {
                    NavigationLink { BuddiesScreen() } label: { tile("🤝", "Invites \(live.invites.count)", LinearGradient.buddies, ring: Theme.lime) }
                        .accessibilityLabel("\(live.invites.count) gym buddy invites")
                }
                NavigationLink { ChallengeRoomView() } label: {
                    tile("🏆", "Challenge", WorkoutEngine.Category.power.gradient, ring: Theme.lime)
                }
                .accessibilityLabel("Week challenge \(live.wod.name)")
                ForEach(today) { p in
                    Button { story = StoryStart(id: p.id) } label: { tile(p.emoji, p.mine ? "You" : p.author.nickname, p.gradient, ring: Theme.lime) }
                        .accessibilityLabel("\(p.mine ? "You" : p.author.nickname) trained today: \(p.payload.title)")
                }
                // Own page since #745 (it opened Gym buddies): code, rewards, then buddies.
                NavigationLink { InviteView() } label: { tile("🎁", "Invite", WorkoutEngine.Category.strength.gradient, ring: Theme.lime) }
                    .accessibilityLabel("Invite a friend")
            }
            .buttonStyle(.plain)
        }
        .scrollClipDisabled()
        .fullScreenCover(item: $story) { s in StoryViewer(posts: today, start: s.id) }
        #if DEBUG
        .task { if Demo.screen == "community-story", let p = today.first { story = StoryStart(id: p.id) } }
        #endif
    }

    private func tile(_ emoji: String, _ title: String, _ gradient: LinearGradient, ring: Color) -> some View {
        VStack(spacing: 5) {
            Text(emoji).font(.system(size: 30))
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(ring, lineWidth: 3))
            Text(title).font(Theme.label(11)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 76)
        }
        .contentShape(Rectangle())
    }
}

struct StoryStart: Identifiable { let id: String }

/// Full screen: today's posts one per page, swipe through, close top right.
struct StoryViewer: View {
    let posts: [CommunityPost]
    @State var start: String
    @Environment(\.dismiss) private var dismiss

    init(posts: [CommunityPost], start: String) {
        self.posts = posts
        _start = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(posts) { p in
                        RoundedRectangle(cornerRadius: 2).fill(p.id == start ? Theme.lime : .white.opacity(0.3)).frame(height: 4)
                    }
                }
                .padding(.horizontal, 16)
                TabView(selection: $start) {
                    ForEach(posts) { p in
                        ScrollView { PostCard(post: p).padding(16) }
                            .scrollBounceBehavior(.basedOnSize)
                            .tag(p.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Trained today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .navigationDestination(for: CommunityAuthor.self) { MemberView(author: $0) }
        }
        .preferredColorScheme(.dark)
    }
}

/// For you / Following, then People.
struct SocialChips: View {
    @Binding var scope: CommunityFeedScope

    var body: some View {
        HStack(spacing: 6) {
            chip(.members, "For you")
            chip(.following, "Following")
            NavigationLink { FindMembersView() } label: {
                Label("People", systemImage: "magnifyingglass").font(Theme.label(12)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(minHeight: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
            }
            .accessibilityLabel("Find people")
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }

    private func chip(_ value: CommunityFeedScope, _ title: String) -> some View {
        let on = value == scope
        return Button { scope = value } label: {
            Text(title).font(Theme.label(12))
                .padding(.horizontal, 12).frame(minHeight: 32)
                .foregroundStyle(on ? Theme.ink : .white)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.lime : Theme.cardStrong))
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One + sheet: Win, Plan, Meal, Tip as four squares.
struct ShareHubSheet: View {
    let pick: (CommunitySheet) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                square(.win, "A win", "Workout, best, badge", "trophy.fill", WorkoutEngine.Category.power.gradient)
                square(.plan, "A plan", "Your programme", "calendar", LinearGradient(colors: [Color(hex: 0xFF3CAC), Color(hex: 0x784BA0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                square(.meal, "A meal", "Recipe and macros", "fork.knife", TipTopic.fuel.gradient)
                square(.tip, "A tip", "Train or fuel advice", "lightbulb.fill", TipTopic.train.gradient)
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.height(340)])
        .preferredColorScheme(.dark)
    }

    private func square(_ s: CommunitySheet, _ title: String, _ detail: String, _ symbol: String, _ gradient: LinearGradient) -> some View {
        Button {
            pick(s)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                Spacer(minLength: 6)
                Text(title).font(Theme.display(20)).lineLimit(1)
                Text(detail).font(.caption.weight(.semibold)).opacity(0.88).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share \(title.lowercased())")
    }
}

/// The one thing to do with a post: Beat it (a member's personal best), Save to Fuel (a member's recipe).
struct PostAction: View {
    let post: CommunityPost
    @State private var attempt: Exercise?
    private var fuel: FuelStore { .shared }

    var body: some View {
        if let e = Self.exercise(post) {
            chip("🔥 Beat it") { attempt = e }
                .fullScreenCover(item: $attempt) { PRAttemptView(exerciseId: $0.id) }
        } else if let r = Self.recipe(post) {
            let saved = fuel.saved.favourites.contains(r.id)
            chip(saved ? "✓ In Fuel" : "＋ Save to Fuel") { fuel.toggleFavourite(r.id) }
                .accessibilityAddTraits(saved ? .isSelected : [])
        }
    }

    private func chip(_ title: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(Theme.label(12)).lineLimit(1)
                .padding(.horizontal, 10).frame(minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.22)))
        }
        .buttonStyle(.plain)
    }

    /// Someone else's personal best: refId "exerciseId:yyyy-mm-dd".
    @MainActor static func exercise(_ post: CommunityPost) -> Exercise? {
        guard !post.mine, post.kind == "record", let id = post.refId?.split(separator: ":").first else { return nil }
        return Exercise.find(String(id))
    }

    /// Someone else's recipe from the book: refId "recipe-<id>".
    @MainActor static func recipe(_ post: CommunityPost) -> Recipe? {
        guard !post.mine, post.isRecipe, let ref = post.refId else { return nil }
        let id = String(ref.dropFirst("recipe-".count))
        return RecipeBook.catalog.first { $0.id == id }
    }
}

extension CommunityFeedScope {
    /// For you mixes member plans into the posts: one plan after every third post.
    @MainActor static func mixed(_ posts: [CommunityPost], plans: [MemberPlan]) -> [SocialItem] {
        var items: [SocialItem] = []
        var rest = plans.filter { !$0.hidden }[...]
        for (i, p) in posts.enumerated() {
            items.append(.post(p))
            if i % 3 == 2, let plan = rest.popFirst() { items.append(.plan(plan)) }
        }
        items += rest.map { SocialItem.plan($0) }
        return items
    }
}

enum SocialItem: Identifiable {
    case post(CommunityPost)
    case plan(MemberPlan)
    var id: String {
        switch self {
        case .post(let p): "post-\(p.id)"
        case .plan(let p): "plan-\(p.id)"
        }
    }
}
