import APIClient
import Foundation
import WorkoutEngine

/// Community state (#61): own profile, feeds and the actions on them. Shared so the tab, sheets and
/// auto-share after a workout see the same posts.
@MainActor @Observable
final class Community {
    static let shared = Community()

    private(set) var profile: CommunityProfile?
    /// Profile fetched at least once for `ownerId` (distinguishes "not joined" from "not loaded").
    private(set) var loaded = false
    private(set) var feed: [CommunityPost] = []
    private(set) var mine: [CommunityPost] = []
    private(set) var following: [CommunityPost] = []
    private var next: [CommunityFeedScope: String] = [:]
    private(set) var loading = false
    var error: String?
    private var ownerId: String?
    private var demo = false

    func posts(_ scope: CommunityFeedScope) -> [CommunityPost] {
        switch scope {
        case .members: feed
        case .following: following
        case .mine: mine
        }
    }
    func hasMore(_ scope: CommunityFeedScope) -> Bool { next[scope] != nil }

    /// Loads the profile (and feeds when joined). Resets when a different user signs in.
    func load(api: APIClient, userId: String?) async {
        guard !demo, let userId else { return }
        if ownerId != userId {
            ownerId = userId
            profile = nil
            loaded = false
            feed = []
            mine = []
            following = []
            next = [:]
        }
        do {
            profile = try await api.communityProfile()
            loaded = true
            error = nil
            if profile != nil { await refresh(api: api) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh(api: APIClient) async {
        guard !demo, profile != nil else { return }
        loading = true
        defer { loading = false }
        do {
            async let f = api.communityFeed(.members)
            async let m = api.communityFeed(.mine)
            async let g = api.communityFeed(.following)
            let (fp, mp, gp) = try await (f, m, g)
            feed = fp.posts
            mine = mp.posts
            following = gp.posts
            next = [.members: fp.nextBefore, .mine: mp.nextBefore, .following: gp.nextBefore].compactMapValues { $0 }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore(_ scope: CommunityFeedScope, api: APIClient) async {
        guard let before = next[scope], !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await api.communityFeed(scope, before: before)
            switch scope {
            case .members: feed += page.posts
            case .following: following += page.posts
            case .mine: mine += page.posts
            }
            next[scope] = page.nextBefore
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setProfile(_ p: CommunityProfile) {
        let joined = profile == nil
        profile = p
        loaded = true
        if joined { feed = []; mine = []; following = [] }
    }

    func left() {
        profile = nil
        feed = []
        mine = []
        following = []
        next = [:]
    }

    /// Optimistic cheer toggle; reverts on failure.
    func toggle(_ reaction: CommunityReaction, on post: CommunityPost, api: APIClient) async {
        guard !post.mine else { return }
        let on = !post.reacted(reaction)
        var optimistic = post
        optimistic.reactions[reaction.rawValue, default: 0] += on ? 1 : -1
        if on { optimistic.myReactions.append(reaction.rawValue) } else { optimistic.myReactions.removeAll { $0 == reaction.rawValue } }
        replace(optimistic)
        if demo { return }
        do { replace(try await api.react(post.id, reaction, on: on)) } catch {
            replace(post)
            self.error = error.localizedDescription
        }
    }

    func replace(_ post: CommunityPost) {
        if let i = feed.firstIndex(where: { $0.id == post.id }) { feed[i] = post }
        if let i = mine.firstIndex(where: { $0.id == post.id }) { mine[i] = post }
        if let i = following.firstIndex(where: { $0.id == post.id }) { following[i] = post }
    }

    func insert(_ post: CommunityPost) {
        let existed = mine.contains { $0.id == post.id }
        mine.removeAll { $0.id == post.id }
        feed.removeAll { $0.id == post.id }
        mine.insert(post, at: 0)
        if post.visibility != .onlyMe { feed.insert(post, at: 0) }
        if !existed, post.visibility != .onlyMe { profile?.sharedPosts += 1 }
    }

    func updated(_ post: CommunityPost) {
        replace(post)
        if post.visibility == .onlyMe { feed.removeAll { $0.id == post.id } }
        else if !feed.contains(where: { $0.id == post.id }) { feed.insert(post, at: 0); feed.sort { $0.createdAt > $1.createdAt } }
    }

    func removed(_ id: String) {
        feed.removeAll { $0.id == id }
        following.removeAll { $0.id == id }
        mine.removeAll { $0.id == id }
    }

    /// Hides everything from a member just blocked.
    func blocked(_ userId: String) {
        feed.removeAll { $0.author.userId == userId }
        following.removeAll { $0.author.userId == userId }
    }

    func unfollowed(_ userId: String) {
        following.removeAll { $0.author.userId == userId }
        if profile != nil { profile!.following = max(0, profile!.following - 1) }
    }

    func followed() {
        profile?.following += 1
    }

    /// Auto-share (profile setting): posts a finished workout with the profile's default visibility.
    func didRecord(_ record: WorkoutRecord, api: APIClient, userId: String?) {
        guard !demo, let p = profile, p.autoShare, ownerId == userId, record.totalSets > 0 else { return }
        Task {
            do {
                let w = WinCard.workout(record)
                insert(try await api.sharePost(kind: w.kind, refId: w.refId, visibility: nil, caption: nil, card: w.card))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    #if DEBUG
    func loadDemo(joined: Bool = true) {
        demo = true
        loaded = true
        guard joined else { return }
        profile = CommunityProfile(
            userId: "demo", nickname: "monkey_jy", bio: "Climber who lifts. Chasing a strict one-arm hang.", avatarUrl: nil,
            defaultVisibility: .members, autoShare: false, sharedPosts: 34, cheersReceived: 96, followers: 12, following: 8)
        let now = Date()
        let bea = CommunityAuthor(userId: "u-bea", nickname: "bench_bea")
        let me = CommunityAuthor(userId: "demo", nickname: "monkey_jy")
        let crimpy = CommunityAuthor(userId: "u-crimpy", nickname: "crimpy")
        let posts = [
            CommunityPost(
                id: "p1", author: bea, mine: false, kind: "workout", visibility: .members, caption: "New bench best, 80 kg!",
                payload: CommunityCard(title: "Upper body power", metric: .init(value: "6.4", unit: "t lifted"), style: "strength",
                                       stats: [.init(label: "min", value: "52"), .init(label: "sets", value: "18")]),
                createdAt: now.addingTimeInterval(-2 * 3600), reactions: ["like": 12, "strong": 5, "fire": 3], myReactions: ["like"]),
            CommunityPost(
                id: "p2", author: me, mine: true, kind: "badge", visibility: .members,
                payload: CommunityCard(title: "Unbreakable", subtitle: "8-week streak", metric: .init(value: "8", unit: "weeks"), style: "power"),
                createdAt: now.addingTimeInterval(-5 * 3600), reactions: ["like": 7, "clap": 4]),
            CommunityPost(
                id: "p3", author: crimpy, mine: false, kind: "workout", visibility: .everyone,
                payload: CommunityCard(title: "Legs & core", metric: .init(value: "41", unit: "min"), style: "cardio",
                                       stats: [.init(label: "sets", value: "14")]),
                createdAt: now.addingTimeInterval(-26 * 3600), reactions: ["like": 3, "strong": 2]),
        ]
        feed = posts
        mine = posts.filter(\.mine)
        following = posts.filter { $0.author.userId == "u-bea" }
    }
    #endif
}

/// Shareable "wins" built from local progress.
struct WinCard: Identifiable {
    var kind: String
    var refId: String
    var card: CommunityCard
    var symbol: String
    var date: Date?
    var id: String { "\(kind):\(refId)" }

    static func workout(_ r: WorkoutRecord) -> WinCard {
        let minutes = max(1, r.durationSec / 60)
        let volume = r.volumeKg
        let lifted = Format.volumeParts(volume)
        let metric: CommunityCard.Metric = volume >= 1000
            ? .init(value: lifted.value, unit: "\(lifted.unit) lifted")
            : .init(value: "\(minutes)", unit: "min")
        var stats: [CommunityCard.Stat] = [.init(label: "min", value: "\(minutes)"), .init(label: "sets", value: "\(r.totalSets)")]
        stats.append(.init(label: "exercises", value: "\(r.exercises.filter { $0.setsDone > 0 }.count)"))
        if let kcal = r.kcal { stats.append(.init(label: "kcal", value: "\(Int(kcal.rounded()))")) }
        let sets = Dictionary(grouping: r.exercises, by: \.category).mapValues { $0.reduce(0) { $0 + $1.setsDone } }
        let style = sets.max { $0.value < $1.value }?.key.rawValue ?? WorkoutEngine.Category.strength.rawValue
        let subtitle = r.startedAt.formatted(.dateTime.weekday(.wide).day().month())
        return WinCard(kind: "workout", refId: r.id.uuidString.lowercased(),
                       card: CommunityCard(title: r.title, subtitle: subtitle, metric: metric, style: style, stats: stats),
                       symbol: "dumbbell.fill", date: r.startedAt)
    }

    static func badge(_ b: Badge) -> WinCard {
        let style: WorkoutEngine.Category = switch b.tier {
        case .gold: .warmup
        case .silver: .mobility
        case .bronze: .power
        }
        let tier = switch b.tier {
        case .gold: "Gold"
        case .silver: "Silver"
        case .bronze: "Bronze"
        }
        return WinCard(kind: "badge", refId: b.id,
                       card: CommunityCard(title: b.title, subtitle: "\(tier) badge · \(b.detail)", style: style.rawValue),
                       symbol: b.symbol, date: b.unlockedAt)
    }

    static func best(_ pr: PersonalRecord) -> WinCard {
        let name = Exercise.get(pr.exerciseId).name
        let kg = pr.kg.rounded() == pr.kg ? "\(Int(pr.kg))" : String(format: "%.1f", pr.kg)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        let day = f.string(from: pr.date)
        return WinCard(kind: "record", refId: "\(pr.exerciseId):\(day)",
                       card: CommunityCard(title: "\(name) best", subtitle: "New personal best", metric: .init(value: kg, unit: "kg"),
                                           style: WorkoutEngine.Category.strength.rawValue),
                       symbol: "arrow.up.right.circle.fill", date: pr.date)
    }
}
