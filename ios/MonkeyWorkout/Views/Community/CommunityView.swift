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
        .navigationTitle("Community")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            if let p = community.profile {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { CommunityProfileView() } label: {
                        AvatarView(url: model.api.resolve(p.avatarUrl), nickname: p.nickname, size: 32)
                    }
                    .accessibilityLabel("Your community profile")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("Share a win")
                }
            }
        }
        .sheet(isPresented: $composing) { ShareWinView() }
        .navigationDestination(for: CommunityAuthor.self) { MemberView(author: $0) }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Picker("Feed", selection: $scope) {
                    Text("Members").tag(CommunityFeedScope.members)
                    Text("Following").tag(CommunityFeedScope.following)
                    Text("Mine").tag(CommunityFeedScope.mine)
                }
                .pickerStyle(.segmented)
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
        case .following: "Tap a member's name, then Follow, to see their wins here."
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
            if let c = post.caption { Text(c).font(.subheadline.weight(.medium)) }
            if post.hidden {
                Label("Hidden from members while reports are reviewed", systemImage: "eye.slash.fill").font(.caption.bold())
            }
            ReactionBar(post: post)
            ErrorText(message: error)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(post.payload.gradient))
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
                    Text(post.author.nickname).font(Theme.label(13))
                }
            }
            .buttonStyle(.plain)
            Text(post.createdAt.formatted(.relative(presentation: .named))).font(.caption.weight(.semibold)).opacity(0.8)
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

/// Like + encouragement cheers. Own posts show counts only.
struct ReactionBar: View {
    let post: CommunityPost
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CommunityReaction.allCases) { r in
                let on = post.reacted(r)
                Button {
                    Task { await Community.shared.toggle(r, on: post, api: model.api) }
                } label: {
                    HStack(spacing: 4) {
                        Text(r.emoji)
                        if post.count(r) > 0 { Text("\(post.count(r))").monospacedDigit() }
                    }
                    .font(Theme.label(13))
                    .foregroundStyle(on ? Theme.ink : .white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(on ? Theme.lime : .white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .disabled(post.mine)
                .accessibilityLabel("\(r.title), \(post.count(r))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: post.myReactions)
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
        }
    }

    var title: String {
        switch self {
        case .like: "Like"
        case .strong: "Strong"
        case .fire: "On fire"
        case .clap: "Keep going"
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
    var gradient: LinearGradient {
        (style.flatMap(WorkoutEngine.Category.init(rawValue:)) ?? .strength).gradient
    }
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
