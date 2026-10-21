import APIClient
import SwiftUI
import WorkoutEngine

/// "Community" tab (#61): members' shared wins with cheers, your own progress log, and your profile.
struct CommunityView: View {
    @Environment(AppModel.self) private var model
    @State private var scope: CommunityFeedScope = .members
    @State private var composing = false
    private var community: Community { .shared }

    var body: some View {
        Group {
            if !community.loaded {
                VStack(spacing: 12) {
                    if let e = community.error {
                        ErrorText(message: e)
                        Button("Retry") { Task { await community.load(api: model.api, userId: model.user?.id) } }
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await community.load(api: model.api, userId: model.user?.id) }
            } else if community.profile == nil {
                JoinCommunityView()
            } else {
                feed
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(community.loaded && community.profile == nil ? "Join the community" : "Community")
        .toolbarTitleDisplayMode(.inlineLarge)
        // Member feed draws its own header (#151): system toolbar items stretched into a capsule over the title.
        .toolbar(community.profile == nil ? .automatic : .hidden, for: .navigationBar)
        .sheet(isPresented: $composing) { ShareWinView() }
        .navigationDestination(for: CommunityAuthor.self) { MemberView(author: $0) }
    }

    /// Title, Share a win and the Me pill (#560): your community profile is in the Me sheet.
    private var header: some View {
        HStack(spacing: 12) {
            Text("Community").font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Button { composing = true } label: { HeaderTile(symbol: "plus", lime: true) }
                .buttonStyle(.plain)
                .accessibilityLabel("Share a win")
            MePill()
        }
        .padding(.top, 4)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                CommunityGymCard()
                FindMembersCard()
                TrainedTodayRow(posts: community.posts(.members))
                GradientSegments(selection: $scope, items: [
                    SegmentItem(value: .members, title: "Members", symbol: "person.3.fill"),
                    SegmentItem(value: .following, title: "Following", symbol: "heart.fill"),
                    SegmentItem(value: .mine, title: "Mine", symbol: "person.fill"),
                ])
                .padding(.bottom, 4)

                ErrorText(message: community.error)
                let posts = community.posts(scope)
                if posts.isEmpty && !community.loading {
                    EmptyFeedCard(scope: scope) { composing = true }
                }
                ForEach(posts) { PostCard(post: $0) }
                if community.hasMore(scope) {
                    ProgressView().padding().task { await community.loadMore(scope, api: model.api) }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .refreshable { await community.refresh(api: model.api) }
    }
}

private struct EmptyFeedCard: View {
    let scope: CommunityFeedScope
    let share: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .bold))
            Text(title).font(Theme.display(24))
            Text(message).font(.subheadline.weight(.medium)).opacity(0.9)
            Button("SHARE A WIN", action: share).buttonStyle(LimeButtonStyle()).padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(WorkoutEngine.Category.mobility.gradient))
    }

    private var symbol: String {
        switch scope {
        case .members: "person.3.fill"
        case .following: "person.crop.circle.badge.checkmark"
        case .mine: "trophy.fill"
        }
    }

    private var title: String {
        switch scope {
        case .members: "Nothing shared yet"
        case .following: "Follow members"
        case .mine: "Your wins live here"
        }
    }

    private var message: String {
        switch scope {
        case .members: "Be the first: share a workout, a personal best or a badge with the members."
        case .following: "Find members by nickname, or tap a name on a post, then Follow to see their wins here."
        case .mine: "Share a workout, a personal best or a badge. Keep it to yourself or show the members."
        }
    }
}

/// One shared win: gradient card, big number, stats, caption and cheers.
struct PostCard: View {
    let post: CommunityPost
    @Environment(AppModel.self) private var model
    @State private var reporting = false
    @State private var confirmBlock = false
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if let m = CommunityMoment(post) { Text(m.label).font(Theme.label(11)).tracking(1.5).opacity(0.85) }
                    Text(post.payload.title).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.7)
                    if let s = post.payload.subtitle { Text(s).font(.footnote.weight(.semibold)).opacity(0.85) }
                }
                Spacer(minLength: 8)
                if let m = post.payload.metric {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(m.value).font(Theme.display(34)).monospacedDigit()
                        Text(m.unit.uppercased()).font(Theme.label(10)).tracking(1).opacity(0.85)
                    }
                }
            }
            if let stats = post.payload.stats, !stats.isEmpty {
                HStack(spacing: 6) {
                    ForEach(stats, id: \.self) { s in
                        Text("\(s.value) \(s.label)")
                            .font(Theme.label(11))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.18)))
                    }
                }
            }
            if let q = CoachQuip.line(for: post) { CoachQuipRow(text: q) }
            if let c = post.caption { Text(c).font(.subheadline.weight(.medium)) }
            if post.hidden {
                Label("Hidden from members while reports are reviewed", systemImage: "eye.slash.fill").font(.caption.bold())
            }
            ReactionBar(post: post)
            ErrorText(message: error)
        }
        .foregroundStyle(post.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(post.gradient))
        .opacity(post.hidden ? 0.6 : 1)
        .sheet(isPresented: $reporting) {
            ReportSheet(postId: post.id, userId: post.author.userId, nickname: post.author.nickname)
        }
        .confirmationDialog("Block \(post.author.nickname)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { block() }
        } message: {
            Text("You won't see each other's posts or profiles. Unblock any time from your community profile.")
        }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            NavigationLink(value: post.author) {
                HStack(spacing: 8) {
                    AvatarView(url: model.api.resolve(post.author.avatarUrl), nickname: post.author.nickname, size: 28)
                    Text(post.author.nickname).font(Theme.label(13)).lineLimit(1).layoutPriority(1)
                    RankTitleChip(level: post.author.level, compact: true)
                    PronounsChip(pronouns: post.author.pronouns)
                }
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            Text(post.createdAt.formatted(.relative(presentation: .named))).font(.caption.weight(.semibold)).opacity(0.8).lineLimit(1)
            Spacer()
            if post.mine {
                Image(systemName: post.visibility.symbol).font(.caption.bold()).opacity(0.85)
                    .accessibilityLabel("Visible to: \(post.visibility.title)")
            }
            menu
        }
    }

    private var menu: some View {
        Menu {
            if post.visibility == .everyone, let url = model.api.shareURL(postId: post.id) {
                ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
            }
            if post.mine {
                Picker("Who can see it", selection: Binding(get: { post.visibility }, set: { setVisibility($0) })) {
                    ForEach(CommunityVisibility.allCases) { v in Label(v.title, systemImage: v.symbol).tag(v) }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } else {
                Button("Report post", systemImage: "flag") { reporting = true }
                Button("Block \(post.author.nickname)", systemImage: "hand.raised") { confirmBlock = true }
            }
        } label: {
            Image(systemName: "ellipsis").font(.body.bold()).frame(width: 32, height: 28).contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    private func setVisibility(_ v: CommunityVisibility) {
        Task {
            do { Community.shared.updated(try await model.api.updatePost(post.id, visibility: v, caption: nil)) } catch { self.error = error.localizedDescription }
        }
    }

    private func delete() {
        Task {
            do {
                try await model.api.deletePost(post.id)
                Community.shared.removed(post.id)
            } catch { self.error = error.localizedDescription }
        }
    }

    private func block() {
        Task {
            do {
                try await model.api.block(post.author.userId)
                Community.shared.blocked(post.author.userId)
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// Like + encouragement cheers: bold square tiles, an emoji burst when you cheer (#566). Own posts show counts only.
struct ReactionBar: View {
    let post: CommunityPost
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: CommunityReaction?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(CommunityReaction.allCases) { r in
                let on = post.reacted(r)
                Button {
                    if !on, !reduceMotion { burst = r }
                    Task { await Community.shared.toggle(r, on: post, api: model.api) }
                } label: {
                    HStack(spacing: 3) {
                        Text(r.emoji).font(.system(size: 15))
                        if post.count(r) > 0 { Text("\(post.count(r))").monospacedDigit().lineLimit(1) }
                    }
                    .font(Theme.label(12))
                    .foregroundStyle(on ? Theme.ink : .white)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.lime : .black.opacity(0.22)))
                    .overlay(alignment: .top) {
                        if burst == r { BurstView(emoji: r.emoji) { burst = nil } }
                    }
                }
                .buttonStyle(.plain)
                .disabled(post.mine)
                .accessibilityLabel("\(r.title), \(post.count(r))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: post.myReactions)
    }
}

/// Three emojis that pop up and fade above a cheer tile.
private struct BurstView: View {
    let emoji: String
    let done: () -> Void
    @State private var up = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Text(emoji).font(.system(size: 18))
                    .offset(x: CGFloat(i - 1) * (up ? 16 : 4), y: up ? -44 - CGFloat(i % 2) * 10 : 0)
                    .scaleEffect(up ? 1.3 : 0.6)
                    .opacity(up ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { up = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { done() }
        }
    }
}

/// Round profile photo with an initial fallback.
struct AvatarView: View {
    let url: URL?
    let nickname: String
    var size: CGFloat = 32
    var ring: Color = .white

    var body: some View {
        ZStack {
            Circle().fill(WorkoutEngine.Category.mobility.gradient)
            Text(String(nickname.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            if let url {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ring, lineWidth: max(1.5, size / 28)))
        .accessibilityHidden(true)
    }
}

extension CommunityReaction {
    var emoji: String {
        switch self {
        case .like: "❤️"
        case .strong: "💪"
        case .fire: "🔥"
        case .clap: "👏"
        case .beast: "🦍"
        case .banana: "🍌"
        }
    }

    var title: String {
        switch self {
        case .like: "Like"
        case .strong: "Strong"
        case .fire: "On fire"
        case .clap: "Keep going"
        case .beast: "Beast"
        case .banana: "Banana earned"
        }
    }
}

extension CommunityVisibility {
    var title: String {
        switch self {
        case .onlyMe: "Only me"
        case .members: "Members"
        case .everyone: "Public"
        }
    }

    var symbol: String {
        switch self {
        case .onlyMe: "lock.fill"
        case .members: "person.2.fill"
        case .everyone: "globe"
        }
    }

    var blurb: String {
        switch self {
        case .onlyMe: "Private progress log, nobody else sees it."
        case .members: "Signed-in MonkeyWorkout members."
        case .everyone: "Members, plus anyone with the link."
        }
    }
}

extension CommunityCard {
    var colors: [Color] {
        // Sport and climb posts (#479): "sport:<Sport raw value>".
        if let s = style, s.hasPrefix("sport:"), let sport = Sport(rawValue: String(s.dropFirst(6))) { return sport.colors }
        // Moments (#566): "moment:pr|streak|level".
        if let s = style, s.hasPrefix("moment:"), let m = CommunityMoment(rawValue: String(s.dropFirst(7))) { return m.colors }
        return (style.flatMap(WorkoutEngine.Category.init(rawValue:)) ?? .strength).colors
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

/// Three big tiles: Only me / Members / Public.
struct VisibilityPicker: View {
    @Binding var selection: CommunityVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(CommunityVisibility.allCases) { v in
                    let on = v == selection
                    Button { selection = v } label: {
                        VStack(spacing: 6) {
                            Image(systemName: v.symbol).font(.title3.bold())
                            Text(v.title).font(Theme.label(12))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(on ? Theme.ink : .white)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Theme.lime : Theme.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(selection.blurb).font(.footnote).foregroundStyle(Theme.muted)
        }
    }
}

/// Pronouns next to a nickname (#415), when the member shows them.
struct PronounsChip: View {
    let pronouns: String?

    var body: some View {
        if let pronouns, !pronouns.isEmpty {
            Text(pronouns)
                .font(Theme.label(10))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.lime))
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Pronouns \(pronouns)")
        }
    }
}
