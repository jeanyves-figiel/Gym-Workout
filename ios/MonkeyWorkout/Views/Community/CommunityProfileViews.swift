import APIClient
import PhotosUI
import SwiftUI
import WorkoutEngine

// MARK: - Join

/// First visit: create a community profile and accept the guidelines (App Store 1.2).
struct JoinCommunityView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "person.3.fill").font(.system(size: 30, weight: .bold))
                    Text("Train together").font(Theme.display(30))
                    Text("Track your wins, share them with the members you choose, and cheer others on.")
                        .font(.subheadline.weight(.medium)).opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(WorkoutEngine.Category.power.gradient))

                CommunityProfileForm(profile: nil)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Profile form (join + edit)

struct CommunityProfileForm: View {
    let profile: CommunityProfile?
    var onSaved: () -> Void = {}
    @Environment(AppModel.self) private var model
    @State private var nickname = ""
    @State private var bio = ""
    @State private var visibility: CommunityVisibility = .onlyMe
    @State private var autoShare = false
    @State private var accepted = false
    @State private var showGuidelines = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var removePhoto = false
    @State private var task = FormTask()
    @State private var loaded = false

    private var joining: Bool { profile == nil }
    private var nicknameValid: Bool { nickname.range(of: "^[A-Za-z0-9_.]{3,20}$", options: .regularExpression) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        if let photo, let img = UIImage(data: photo) {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 84, height: 84).clipShape(Circle())
                                .overlay(Circle().strokeBorder(Theme.lime, lineWidth: 3))
                        } else {
                            AvatarView(url: removePhoto ? nil : model.api.resolve(profile?.avatarUrl),
                                       nickname: nickname.isEmpty ? "?" : nickname, size: 84, ring: Theme.lime)
                        }
                        Image(systemName: "camera.fill").font(.caption.bold()).foregroundStyle(Theme.ink)
                            .padding(7).background(Circle().fill(Theme.lime))
                    }
                }
                .accessibilityLabel("Choose profile photo")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile photo").font(.system(.body, design: .rounded).weight(.heavy))
                    Text("Optional. Location and camera details are removed.").font(.footnote).foregroundStyle(Theme.muted)
                    if photo != nil || (profile?.avatarUrl != nil && !removePhoto) {
                        Button("Remove photo", role: .destructive) {
                            photo = nil
                            photoItem = nil
                            removePhoto = true
                        }
                        .font(.footnote.bold())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Nickname").eyebrow()
                TextField("e.g. monkey_jy", text: $nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .card(padding: 14)
                Text("3–20 letters, digits, _ or . · shown instead of your name")
                    .font(.footnote).foregroundStyle(nickname.isEmpty || nicknameValid ? Theme.muted : .red)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("About you").eyebrow()
                TextField("A short description (optional)", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
                    .card(padding: 14)
                    .onChange(of: bio) { _, v in if v.count > 160 { bio = String(v.prefix(160)) } }
                Text("\(bio.count)/160").font(.caption).foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default visibility of your posts").eyebrow()
                VisibilityPicker(selection: $visibility)
            }

            Toggle(isOn: $autoShare) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-share workouts").font(.system(.body, design: .rounded).weight(.heavy))
                    Text("Post each finished workout with your default visibility.").font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .card(padding: 14)

            if joining {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Community guidelines").eyebrow()
                    GuidelinesText()
                    Button("Read the full guidelines") { showGuidelines = true }.font(.footnote.bold())
                    Toggle("I agree to the community guidelines", isOn: $accepted).font(.subheadline.weight(.bold))
                }
                .card()
            }

            ErrorText(message: task.error)
            Button(task.busy ? "SAVING…" : (joining ? "JOIN THE COMMUNITY" : "SAVE")) { save() }
                .buttonStyle(LimeButtonStyle())
                .disabled(!nicknameValid || (joining && !accepted) || task.busy)
                .opacity(!nicknameValid || (joining && !accepted) ? 0.5 : 1)
        }
        .sheet(isPresented: $showGuidelines) { NavigationStack { GuidelinesView() } }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let jpeg = AvatarImage.jpeg(from: data) {
                    photo = jpeg
                    removePhoto = false
                } else {
                    task.error = "That photo could not be used."
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            nickname = profile?.nickname ?? ""
            bio = profile?.bio ?? ""
            visibility = profile?.defaultVisibility ?? .onlyMe
            autoShare = profile?.autoShare ?? false
        }
    }

    private func save() {
        let api = model.api
        let n = nickname.trimmingCharacters(in: .whitespaces)
        let b = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = visibility, a = autoShare, join = joining, newPhoto = photo, remove = removePhoto
        task.run {
            #if DEBUG
            if model.demo {
                onSaved()
                return
            }
            #endif
            var p = try await api.saveCommunityProfile(nickname: n, bio: b, defaultVisibility: v, autoShare: a, acceptGuidelines: join)
            if let newPhoto { p = try await api.uploadAvatar(jpeg: newPhoto) } else if remove, p.avatarUrl != nil { p = try await api.deleteAvatar() }
            Community.shared.setProfile(p)
            if join { await Community.shared.refresh(api: api) }
            onSaved()
        }
    }
}

/// Square, upright, ≤ 512 px JPEG without metadata (re-rendered pixels).
enum AvatarImage {
    static func jpeg(from data: Data) -> Data? {
        guard let img = UIImage(data: data), img.size.width > 0, img.size.height > 0 else { return nil }
        let side = min(img.size.width, img.size.height)
        let target = min(512, max(128, side))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let out = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / side
            let w = img.size.width * scale, h = img.size.height * scale
            img.draw(in: CGRect(x: (target - w) / 2, y: (target - h) / 2, width: w, height: h))
        }
        var q: CGFloat = 0.85
        while q > 0.3 {
            if let d = out.jpegData(compressionQuality: q), d.count <= 500_000 { return d }
            q -= 0.15
        }
        return nil
    }
}

// MARK: - Guidelines

private struct GuidelinesText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Guidelines.rules, id: \.self) { r in
                Label(r, systemImage: "checkmark.seal.fill").font(.footnote.weight(.medium))
            }
        }
    }
}

enum Guidelines {
    static let rules = [
        "Be kind. Cheer effort, never mock anyone's body, level or progress.",
        "No hateful, harassing, sexual, violent or spam content. Zero tolerance.",
        "Share only your own training and photos you have the right to use.",
        "Report anything that breaks these rules; block members you don't want to see.",
    ]
}

struct GuidelinesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GuidelinesText()
                Text("""
                There is no tolerance for objectionable content or abusive members. Text with offensive words is refused. \
                Reported posts are reviewed within 24 hours; a post reported by several members is hidden until reviewed. \
                Content that breaks the rules is removed and repeat offenders are removed from the community.

                You choose who sees each post: only you, members, or public (anyone with the link). \
                You can change it or delete a post at any time. Leaving the community deletes your profile, photo and posts.
                """)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Community guidelines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

// MARK: - Own profile

struct CommunityProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmLeave = false
    @State private var task = FormTask()
    private var community: Community { .shared }

    var body: some View {
        ScrollView {
            if let p = community.profile {
                VStack(alignment: .leading, spacing: 16) {
                    ProfileHero(avatar: model.api.resolve(p.avatarUrl), nickname: p.nickname, bio: p.bio)
                    HStack(spacing: 10) {
                        StatTile(value: "\(community.mine.count)", label: "Wins logged")
                        StatTile(value: "\(p.sharedPosts)", label: "Shared")
                        StatTile(value: "\(p.cheersReceived)", label: "Cheers")
                    }
                    Text("Profile").eyebrow()
                    NavigationLink { editView(p) } label: {
                        ProfileRow(symbol: "pencil", title: "Nickname, photo, bio", detail: nil, category: .strength)
                    }
                    NavigationLink { editView(p) } label: {
                        ProfileRow(symbol: p.defaultVisibility.symbol, title: "Default visibility", detail: p.defaultVisibility.title, category: .cardio)
                    }
                    NavigationLink { editView(p) } label: {
                        ProfileRow(symbol: "bolt.fill", title: "Auto-share workouts", detail: p.autoShare ? "On" : "Off", category: .warmup)
                    }
                    NavigationLink { BlockedMembersView() } label: {
                        ProfileRow(symbol: "hand.raised.fill", title: "Blocked members", detail: nil, category: nil)
                    }
                    NavigationLink { GuidelinesView() } label: {
                        ProfileRow(symbol: "checkmark.seal.fill", title: "Community guidelines", detail: nil, category: nil)
                    }
                    ErrorText(message: task.error)
                    Button("Leave the community", role: .destructive) { confirmLeave = true }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Your profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Leave the community?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave and delete my posts", role: .destructive) { leave() }
        } message: {
            Text("Your community profile, photo, posts and cheers are deleted. Your training data stays.")
        }
    }

    private func editView(_ p: CommunityProfile) -> some View {
        EditCommunityProfileView(profile: p)
    }

    private func leave() {
        let api = model.api
        task.run {
            try await api.leaveCommunity()
            Community.shared.left()
            dismiss()
        }
    }
}

private struct EditCommunityProfileView: View {
    let profile: CommunityProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            CommunityProfileForm(profile: profile) { dismiss() }.padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileHero: View {
    let avatar: URL?
    let nickname: String
    let bio: String?

    var body: some View {
        VStack(spacing: 8) {
            AvatarView(url: avatar, nickname: nickname, size: 104, ring: Theme.lime)
            Text(nickname).font(Theme.display(28))
            if let bio, !bio.isEmpty {
                Text(bio).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct ProfileRow: View {
    let symbol: String
    let title: String
    let detail: String?
    let category: WorkoutEngine.Category?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background {
                    if let category {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(category.gradient)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardStrong)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded).weight(.heavy))
                if let detail { Text(detail).font(.footnote.weight(.medium)).foregroundStyle(Theme.muted) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(.white)
        .card(padding: 12)
    }
}

// MARK: - Member

struct MemberView: View {
    let author: CommunityAuthor
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page: CommunityMemberPage?
    @State private var error: String?
    @State private var reporting = false
    @State private var confirmBlock = false

    private var isMe: Bool { author.userId == (Community.shared.profile?.userId ?? model.user?.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProfileHero(avatar: model.api.resolve(page?.member.avatarUrl ?? author.avatarUrl),
                            nickname: page?.member.nickname ?? author.nickname, bio: page?.member.bio)
                if let m = page?.member {
                    HStack(spacing: 10) {
                        StatTile(value: "\(m.sharedPosts)", label: "Shared")
                        StatTile(value: "\(m.cheersReceived)", label: "Cheers")
                    }
                }
                ErrorText(message: error)
                if let page {
                    if page.blockedByMe {
                        Text("You blocked this member.").font(.subheadline).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(page.posts) { p in PostCard(post: Community.shared.posts(.members).first(where: { $0.id == p.id }) ?? p) }
                        if page.posts.isEmpty {
                            Text("No shared wins yet.").font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(author.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Report \(author.nickname)", systemImage: "flag") { reporting = true }
                        if page?.blockedByMe == true {
                            Button("Unblock", systemImage: "hand.raised.slash") { unblock() }
                        } else {
                            Button("Block", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $reporting) { ReportSheet(postId: nil, userId: author.userId, nickname: author.nickname) }
        .confirmationDialog("Block \(author.nickname)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { block() }
        } message: {
            Text("You won't see each other's posts or profiles.")
        }
        .task { await load() }
    }

    private func load() async {
        #if DEBUG
        if model.demo {
            let posts = Community.shared.posts(.members).filter { $0.author.userId == author.userId }
            page = CommunityMemberPage(member: CommunityMember(userId: author.userId, nickname: author.nickname, bio: nil, avatarUrl: nil,
                                                              sharedPosts: posts.count, cheersReceived: posts.reduce(0) { $0 + $1.totalCheers }),
                                       posts: posts, blockedByMe: false)
            return
        }
        #endif
        do { page = try await model.api.communityMember(author.userId) } catch { self.error = error.localizedDescription }
    }

    private func block() {
        Task {
            do {
                try await model.api.block(author.userId)
                Community.shared.blocked(author.userId)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func unblock() {
        Task {
            do {
                try await model.api.unblock(author.userId)
                await load()
                await Community.shared.refresh(api: model.api)
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Blocked

struct BlockedMembersView: View {
    @Environment(AppModel.self) private var model
    @State private var blocked: [BlockedMember]?
    @State private var error: String?

    var body: some View {
        List {
            ErrorText(message: error)
            if let blocked {
                if blocked.isEmpty { Text("Nobody blocked.").foregroundStyle(Theme.muted) }
                ForEach(blocked) { b in
                    HStack(spacing: 12) {
                        AvatarView(url: model.api.resolve(b.avatarUrl), nickname: b.nickname, size: 36)
                        Text(b.nickname).font(.system(.body, design: .rounded).weight(.bold))
                        Spacer()
                        Button("Unblock") { unblock(b) }.buttonStyle(.bordered)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .themedForm()
        .navigationTitle("Blocked members")
        .task {
            #if DEBUG
            if model.demo {
                blocked = []
                return
            }
            #endif
            do { blocked = try await model.api.blockedMembers() } catch { self.error = error.localizedDescription }
        }
    }

    private func unblock(_ b: BlockedMember) {
        Task {
            do {
                try await model.api.unblock(b.userId)
                blocked?.removeAll { $0.userId == b.userId }
                await Community.shared.refresh(api: model.api)
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Report

struct ReportSheet: View {
    let postId: String?
    let userId: String
    let nickname: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reason: CommunityReportReason?
    @State private var details = ""
    @State private var alsoBlock = false
    @State private var sent = false
    @State private var task = FormTask()

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Thanks. We review reports within 24 hours.", systemImage: "checkmark.seal.fill")
                    }
                } else {
                    Section(postId == nil ? "Why are you reporting \(nickname)?" : "What's wrong with this post?") {
                        ForEach(CommunityReportReason.allCases) { r in
                            Button { reason = r } label: {
                                HStack {
                                    Text(r.title).foregroundStyle(.white)
                                    Spacer()
                                    if reason == r { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
                                }
                            }
                        }
                    }
                    Section("Details (optional)") {
                        TextField("What happened?", text: $details, axis: .vertical).lineLimit(2...5)
                    }
                    Section {
                        Toggle("Also block \(nickname)", isOn: $alsoBlock)
                        ErrorText(message: task.error)
                        BusyButton(title: "Send report", busy: task.busy, disabled: reason == nil) { send() }
                    }
                }
            }
            .themedForm()
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(sent ? "Done" : "Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func send() {
        guard let reason else { return }
        let api = model.api
        let d = String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let block = alsoBlock
        task.run {
            #if DEBUG
            if model.demo {
                sent = true
                return
            }
            #endif
            try await api.report(postId: postId, userId: postId == nil ? userId : nil, reason: reason, details: d.isEmpty ? nil : d)
            if block {
                try await api.block(userId)
                Community.shared.blocked(userId)
            }
            sent = true
        }
    }
}

extension CommunityReportReason {
    var title: String {
        switch self {
        case .spam: "Spam or scam"
        case .harassment: "Bullying or harassment"
        case .hate: "Hate speech"
        case .sexual: "Nudity or sexual content"
        case .violence: "Violence or self-harm"
        case .other: "Something else"
        }
    }
}
