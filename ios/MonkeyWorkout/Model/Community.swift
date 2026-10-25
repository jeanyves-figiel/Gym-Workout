import APIClient
import Foundation
import WorkoutEngine

/// Community state (#61): own profile, feeds and the actions on them. Shared so the tab, sheets and
/// auto-share after a workout see the same posts.
@MainActor @Observable
final class Community {
    static let shared = Community()

    private(set) var profile: CommunityProfile?
    /// Account profile (#108): nickname, photo, about. Mirrors `profile` once joined.
    private(set) var publicProfile: PublicProfile?
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

    /// What the tab last showed (#641): kept per account so it opens at once, offline too.
    private struct Snapshot: Codable {
        var profile: CommunityProfile?
        var publicProfile: PublicProfile?
        var feed: [CommunityPost]
        var mine: [CommunityPost]
        var following: [CommunityPost]
    }
    private static let file = "community.json"

    /// At launch, before the server answers: the last profile and feeds of this account.
    func restore(userId: String?) {
        guard !demo, !loaded, let userId, let s = DeviceCache.load(Snapshot.self, Self.file, userId: userId) else { return }
        ownerId = userId
        profile = s.profile
        publicProfile = s.publicProfile
        feed = s.feed
        mine = s.mine
        following = s.following
        loaded = true
    }

    private func persist() {
        guard !demo, loaded, let ownerId else { return }
        let s = Snapshot(profile: profile, publicProfile: publicProfile, feed: Array(feed.prefix(30)),
                         mine: Array(mine.prefix(30)), following: Array(following.prefix(30)))
        DeviceCache.save(s, Self.file, userId: ownerId)
    }

    /// Loads the profile (and feeds when joined). Resets when a different user signs in.
    func load(api: APIClient, userId: String?) async {
        guard !demo, let userId else { return }
        if ownerId != userId {
            ownerId = userId
            profile = nil
            publicProfile = nil
            loaded = false
            feed = []
            mine = []
            following = []
            next = [:]
            SharedPlans.shared.reset()
        }
        do {
            async let pub = api.publicProfile()
            profile = try await api.communityProfile()
            publicProfile = try await pub
            loaded = true
            error = nil
            if profile != nil { await refresh(api: api) } else { persist() }
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
            persist()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Tells the server the game level (#242) when it changed, so members see the rank title and Legend badge.
    func reportLevel(_ level: Int, api: APIClient) async {
        guard !demo, let p = profile, p.level != level else { return }
        do {
            try await api.setCommunityLevel(level)
            profile?.level = level
        } catch {}
    }

    /// Pronouns next to the nickname (#415); nil hides them. Members only.
    func setPronouns(_ pronouns: String?, api: APIClient) async {
        guard !demo, let p = profile, p.pronouns != pronouns else { return }
        do {
            try await api.setCommunityPronouns(pronouns)
            profile?.pronouns = pronouns
        } catch {}
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

    /// Nickname, photo and about for Account and the join form, joined or not.
    var me: PublicProfile {
        if let p = profile { return PublicProfile(nickname: p.nickname, bio: p.bio, avatarUrl: p.avatarUrl, member: true) }
        return publicProfile ?? PublicProfile()
    }

    func setProfile(_ p: CommunityProfile) {
        let joined = profile == nil
        profile = p
        publicProfile = PublicProfile(nickname: p.nickname, bio: p.bio, avatarUrl: p.avatarUrl, member: true)
        loaded = true
        if joined { feed = []; mine = []; following = [] }
        persist()
    }

    /// Saved from Account; a member's community profile shows the same values.
    func setPublic(_ p: PublicProfile) {
        publicProfile = p
        defer { persist() }
        guard profile != nil else { return }
        if let n = p.nickname, !n.isEmpty { profile!.nickname = n }
        profile!.bio = p.bio
        profile!.avatarUrl = p.avatarUrl
    }

    /// Leaving keeps nickname, photo and about on Account.
    func left() {
        publicProfile = PublicProfile(nickname: profile?.nickname, bio: profile?.bio, avatarUrl: profile?.avatarUrl, member: false)
        profile = nil
        feed = []
        mine = []
        following = []
        next = [:]
        SharedPlans.shared.reset()
        persist()
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
        // Shared by hand counts too, so auto-share never re-posts it over the caption (#479).
        if !demo, let ref = post.refId, let ownerId { remember("\(post.kind):\(ref)", userId: ownerId) }
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

    /// Auto-share (profile setting, #479): posts finished workouts, sports and climbs of the last 24 h with the
    /// profile's default visibility. Loads the profile first when it isn't yet (a Watch-finished workout can land
    /// before the Community screen ever loaded). Each win is posted once: ids already in Mine or posted before are
    /// skipped, so a post the member deleted stays deleted; a failed post is retried on the next call.
    func autoShare(_ wins: [WinCard], api: APIClient, userId: String?, now: Date = Date()) async {
        guard !demo, let userId else { return }
        if sharing { shareAgain = true; return }
        sharing = true
        defer { sharing = false }
        repeat {
            shareAgain = false
            if ownerId != userId || !loaded { await load(api: api, userId: userId) }
            guard ownerId == userId, profile?.autoShare == true else { return }
            let posted = Set(mine.map { "\($0.kind):\($0.refId ?? "")" })
            let done = Set(autoShared(userId))
            let due = wins.filter { w in
                guard let d = w.date, now.timeIntervalSince(d) < Self.autoShareWindow, d <= now.addingTimeInterval(3600) else { return false }
                return !posted.contains(w.id) && !done.contains(w.id)
            }
            for w in due {
                do {
                    insert(try await api.sharePost(kind: w.postKind, refId: w.refId, visibility: nil, caption: nil, card: w.card))
                    remember(w.id, userId: userId)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } while shareAgain
    }

    /// Wins older than this are never auto-shared (turning auto-share on doesn't post the past).
    static let autoShareWindow: TimeInterval = 24 * 3600
    private var sharing = false
    private var shareAgain = false
    private static func autoSharedKey(_ userId: String) -> String { "community.autoShared.\(userId)" }
    private func autoShared(_ userId: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.autoSharedKey(userId)) ?? []
    }
    private func remember(_ id: String, userId: String) {
        var done = autoShared(userId)
        guard !done.contains(id) else { return }
        done.append(id)
        UserDefaults.standard.set(Array(done.suffix(200)), forKey: Self.autoSharedKey(userId))
    }

    /// Removes the workout's auto-shared post when the workout is undone (#133).
    func didUndo(_ record: WorkoutRecord, api: APIClient) {
        let ref = WinCard.workout(record).refId
        for p in mine where p.kind == "workout" && p.refId == ref {
            Task {
                try? await api.deletePost(p.id)
                removed(p.id)
            }
        }
    }

    #if DEBUG
    func loadDemo(joined: Bool = true) {
        demo = true
        loaded = true
        // Not joined yet: the Account profile is already set, so joining is prefilled (#108).
        publicProfile = PublicProfile(nickname: "monkey_jy", bio: "Climber who lifts. Chasing a strict one-arm hang.", member: joined)
        guard joined else { return }
        profile = CommunityProfile(
            userId: "demo", nickname: "monkey_jy", bio: "Climber who lifts. Chasing a strict one-arm hang.", avatarUrl: nil,
            defaultVisibility: .members, autoShare: false, showGym: true, gym: "Fitnesspark Puls 5", sharedPosts: 34, cheersReceived: 96, followers: 12, following: 8,
            level: 9)
        profile?.socials = SocialHandles(instagram: "monkey_jy", strava: "monkeyjy")
        profile?.socialsVisibility = .following
        let now = Date()
        let bea = CommunityAuthor(userId: "u-bea", nickname: "bench_bea", level: 42)
        let me = CommunityAuthor(userId: "demo", nickname: "monkey_jy", level: 9)
        let crimpy = CommunityAuthor(userId: "u-crimpy", nickname: "crimpy", level: 4)
        let tom = CommunityAuthor(userId: "u-tom", nickname: "tom_runs", level: 12)
        let posts = [
            CommunityPost(
                id: "p0", author: bea, mine: false, kind: "record", refId: "bench-press:2026-10-24", visibility: .members,
                payload: CommunityCard(title: "Bench Press best", subtitle: "New personal best", metric: .init(value: "100", unit: "kg"), style: "moment:pr"),
                createdAt: now.addingTimeInterval(-1 * 3600), reactions: ["like": 9, "strong": 6, "fire": 3, "beast": 4], myReactions: ["fire"]),
            CommunityPost(
                id: "p1", author: bea, mine: false, kind: "workout", visibility: .members, caption: "New bench best, 100 kg!",
                payload: CommunityCard(title: "Chest Push Focus", subtitle: "Today", metric: .init(value: "6.4", unit: "t lifted"), style: "strength",
                                       stats: [.init(label: "min", value: "52"), .init(label: "sets", value: "18")]),
                createdAt: now.addingTimeInterval(-2 * 3600), reactions: ["like": 12, "strong": 5, "fire": 3, "banana": 2], myReactions: ["like"]),
            CommunityPost(
                id: "p2", author: me, mine: true, kind: "badge", visibility: .members,
                payload: CommunityCard(title: "Unbreakable", subtitle: "Trained every week", metric: .init(value: "8", unit: "weeks"), style: "moment:streak"),
                createdAt: now.addingTimeInterval(-3 * 3600), reactions: ["like": 7, "clap": 4]),
            CommunityPost(
                id: "p5", author: me, mine: true, kind: "workout", visibility: .members,
                payload: CommunityCard(title: "Legs", subtitle: "Today", metric: .init(value: "9.1", unit: "t lifted"), style: "strength",
                                       stats: [.init(label: "min", value: "55"), .init(label: "sets", value: "27"), .init(label: "exercises", value: "12")]),
                createdAt: now.addingTimeInterval(-3.5 * 3600), reactions: ["like": 4, "strong": 2, "beast": 1]),
            CommunityPost(
                id: "p4", author: tom, mine: false, kind: "workout", visibility: .members,
                payload: CommunityCard(title: "Running", subtitle: "Today", metric: .init(value: "8.4", unit: "km"), style: "sport:run",
                                       stats: [.init(label: "min", value: "44")]),
                createdAt: now.addingTimeInterval(-4 * 3600), reactions: ["clap": 2]),
            CommunityPost(
                id: "p7", author: tom, mine: false, kind: "note", visibility: .members,
                caption: "Prep 3 chicken and rice boxes on Sunday: 150 g protein a day all week without thinking.",
                payload: PostTipSheet.card(.fuel), createdAt: now.addingTimeInterval(-5 * 3600), reactions: ["banana": 24, "beast": 6]),
            CommunityPost(
                id: "p8", author: bea, mine: false, kind: "note", refId: "recipe-\(RecipeBook.catalog[0].id)", visibility: .members,
                caption: "My post-bench bowl.", payload: ShareRecipeSheet.card(RecipeBook.catalog[0]),
                createdAt: now.addingTimeInterval(-6 * 3600), reactions: ["like": 8]),
            CommunityPost(
                id: "p9", author: crimpy, mine: false, kind: "note", visibility: .members,
                caption: "Film your squat from the side once a month. Depth lies.",
                payload: PostTipSheet.card(.train), createdAt: now.addingTimeInterval(-8 * 3600), reactions: ["strong": 5]),
            CommunityPost(
                id: "p6", author: crimpy, mine: false, kind: "badge", visibility: .members,
                payload: CommunityCard(title: "Now Regular", subtitle: "Level 4 → 5", metric: .init(value: "5", unit: "level"), style: "moment:level"),
                createdAt: now.addingTimeInterval(-20 * 3600), reactions: ["clap": 3]),
            CommunityPost(
                id: "p3", author: crimpy, mine: false, kind: "workout", visibility: .everyone,
                payload: CommunityCard(title: "Pull Day", metric: .init(value: "41", unit: "min"), style: "strength",
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
    /// Kind sent to the server: sports post as workouts (refId "sport-<id>"), so no server change is needed (#479).
    var postKind: String { kind == "sport" ? "workout" : kind }
    var id: String { "\(postKind):\(refId)" }

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
        let top = sets.max { $0.value < $1.value }?.key ?? .strength
        let subtitle = r.startedAt.formatted(.dateTime.weekday(.wide).day().month())
        return WinCard(kind: "workout", refId: r.id.uuidString.lowercased(),
                       card: CommunityCard(title: r.title, subtitle: subtitle, metric: metric, style: top.rawValue, stats: stats),
                       symbol: top.symbol, date: r.startedAt)
    }

    /// A finished workout worth posting: sets ticked, or at least 10 minutes in the player (#479: a workout
    /// tracked without ticking sets was left out of Share a win and auto-share).
    static func shareable(_ r: WorkoutRecord) -> Bool { r.totalSets > 0 || r.durationSec >= 600 }

    /// Another sport (#479): logged here, tracked on the Watch or read from Apple Health.
    static func sport(_ e: SportEntry) -> WinCard {
        let big: CommunityCard.Metric = if let d = e.distanceKm, d >= 1 {
            .init(value: d >= 10 ? "\(Int(d.rounded()))" : String(format: "%.1f", d), unit: "km")
        } else {
            .init(value: "\(max(1, e.minutes))", unit: "min")
        }
        var stats: [CommunityCard.Stat] = [.init(label: "min", value: "\(e.minutes)")]
        if let m = e.elevationM, m >= 10 { stats.append(.init(label: "m up", value: "\(Int(m.rounded()))")) }
        if let hr = e.avgHR { stats.append(.init(label: "bpm", value: "\(Int(hr.rounded()))")) }
        if let k = e.kcal, k > 0 { stats.append(.init(label: "kcal", value: "\(Int(k.rounded()))")) }
        return WinCard(kind: "sport", refId: "sport-\(e.id.uuidString.lowercased())",
                       card: CommunityCard(title: e.sport.label, subtitle: e.start.formatted(.dateTime.weekday(.wide).day().month()),
                                           metric: big, style: "sport:\(e.sport.rawValue)", stats: Array(stats.prefix(4))),
                       symbol: e.sport.symbol, date: e.start)
    }

    /// A climbing session (#479): logged here or read from Apple Health.
    static func climb(_ e: ClimbEntry) -> WinCard {
        let metric: CommunityCard.Metric = if let g = e.topGrade, !g.isEmpty, g.count <= 12 {
            .init(value: g, unit: "top grade")
        } else {
            .init(value: "\(max(1, e.minutes))", unit: "min")
        }
        var stats: [CommunityCard.Stat] = [.init(label: "min", value: "\(e.minutes)")]
        if let x = e.effort { stats.append(.init(label: "effort", value: "\(x)/10")) }
        return WinCard(kind: "climb", refId: e.id.uuidString.lowercased(),
                       card: CommunityCard(title: e.kind.map { "\($0.label) climbing" } ?? "Climbing",
                                           subtitle: e.start.formatted(.dateTime.weekday(.wide).day().month()),
                                           metric: metric, style: "sport:climbing", stats: stats),
                       symbol: e.kind?.symbol ?? Sport.climbing.symbol, date: e.start)
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
                                           style: "moment:pr"),
                       symbol: "trophy.fill", date: pr.date)
    }
}

extension AppModel {
    /// What auto-share may post (#479): finished workouts, sports logged here (or tracked on the Watch, from Health)
    /// and climbs logged here, plus the bests, streak milestones and level ups they earned (#566).
    /// `Community.autoShare` keeps the last 24 h and skips what's already posted.
    func autoShareWins(healthSports: [SportEntry] = []) -> [WinCard] {
        let workouts = state.history.filter(WinCard.shareable).map(WinCard.workout)
        let sports = Sports.merged(local: sportLogs, health: healthSports.filter { $0.tracked == true }).map(WinCard.sport)
        let climbs = climbLogs.map { WinCard.climb(ClimbEntry($0)) }
        let moments = WinCard.moments(history: state.history, weights: weightEntries, targetPerWeek: gameTarget,
                                      moveXP: MoveStore.shared.xp + FuelStore.shared.xp)
        return workouts + sports + climbs + moments
    }
}
