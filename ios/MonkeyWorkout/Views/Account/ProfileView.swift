import APIClient
import PhotosUI
import SwiftUI
import WorkoutEngine

/// Your profile (#438, design A from `unified-profile/proposals.png`): every "about me" field in one page,
/// opened from the Settings header card and from your Community profile. Name, @nickname, photo, about,
/// How we talk to you and Community options. Auto saves (#437): Saved pill while editing, Undo bar on leave.
struct ProfileView: View {
    @Environment(AppModel.self) private var model

    /// What was there when the page opened; Undo on leave puts it back.
    struct Snapshot: Equatable {
        var name: String
        var nickname: String
        var bio: String
        var gender: BodyMetrics.Gender?
        var genderText: String
        var pronouns: Pronouns?
        var pronounsCustom: String
        var coachCall: CoachCall?
        var showPronouns: Bool
        var visibility: CommunityVisibility?
        var autoShare: Bool?
    }

    @State private var name = ""
    @State private var nickname = ""
    @State private var bio = ""
    @State private var gender: BodyMetrics.Gender?
    @State private var genderText = ""
    @State private var pronouns: Pronouns?
    @State private var pronounsCustom = ""
    @State private var coachCall: CoachCall?
    @State private var showPronouns = false
    @State private var visibility: CommunityVisibility = .members
    @State private var autoShare = false
    @State private var photoItem: PhotosPickerItem?
    /// Photo upload / removal, saved at once (not part of Undo).
    @State private var task = FormTask()
    @State private var loaded = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, nickname, bio }

    private var community: Community { .shared }
    private var member: Bool { community.profile != nil }
    private var nicknameValid: Bool { nickname.range(of: "^[A-Za-z0-9_.]{3,20}$", options: .regularExpression) != nil }
    private var nicknameProblem: String? {
        if nickname.isEmpty { return member ? "Community members need a nickname." : nil }
        return nicknameValid ? nil : "3–20 letters, digits, _ or ."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                hero
                ErrorText(message: task.error)

                section("About you")
                VStack(alignment: .trailing, spacing: 4) {
                    TextField("", text: $bio, prompt: Text("A short description (optional)").foregroundStyle(Theme.muted), axis: .vertical)
                        .lineLimit(2...4)
                        .font(.body.weight(.semibold))
                        .focused($focus, equals: .bio)
                        .onChange(of: bio) { _, v in if v.count > 160 { bio = String(v.prefix(160)) } }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(bio.count)/160").font(.caption).foregroundStyle(Theme.muted)
                }
                .card(padding: 14)
                AccountNote(text: member ? "Shown on your community profile and posts." : "Used when you join the community. Nothing is shared until then.")

                section("Coach & pronouns")
                TalkToYouCard(gender: $gender, pronouns: $pronouns, pronounsCustom: $pronounsCustom, call: $coachCall,
                              showPronouns: $showPronouns, name: model.callableName,
                              nickname: nickname.isEmpty ? (model.callableName ?? "You") : nickname,
                              avatar: model.api.resolve(community.me.avatarUrl))
                if gender == .selfDescribe {
                    AccountField(label: "In your words") {
                        TextField("How do you describe your gender?", text: $genderText)
                            .textInputAutocapitalization(.never)
                    }
                }
                AccountNote(text: "Gender stays on your device and account, never in calculations. Pronouns are used by the coach and Ask Coach, and shown in Community only if you turn it on.")

                section("Community")
                if member {
                    VisibilityPicker(selection: $visibility)
                    Toggle(isOn: $autoShare) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-share workouts").font(.system(.body, design: .rounded).weight(.heavy))
                            Text("Post each finished workout with your default visibility.").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.lime)
                    .card(padding: 14)
                    ShowGymCard()
                    AccountNote(text: "Default visibility of your posts, auto-share and your gym. Blocked members and leaving are on your Community profile.")
                } else {
                    AccountNote(text: "Join from the Community tab to appear there with this nickname, photo and about.")
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .readableWidth()
        .scrollDismissesKeyboard(.interactively)
        .themedForm()
        .navigationTitle("Your profile")
        .toolbarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in if let item { upload(item) } }
        .autoSave(loaded ? snapshot : nil, title: "Profile", symbol: "person.crop.circle.fill",
                  detail: Self.detail, save: { [model] in Self.store($0, model: model) })
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(url: model.api.resolve(community.me.avatarUrl), nickname: nickname.isEmpty ? (name.isEmpty ? "?" : name) : nickname,
                               size: 76, ring: Theme.lime)
                    Image(systemName: "camera.fill").font(.caption.bold()).foregroundStyle(Theme.ink)
                        .padding(6).background(Circle().fill(Theme.lime))
                }
            }
            .accessibilityLabel("Choose profile photo")
            VStack(alignment: .leading, spacing: 4) {
                TextField("", text: $name, prompt: Text("Add your name").foregroundStyle(.white.opacity(0.6)))
                    .font(Theme.display(24))
                    .textContentType(.name)
                    .submitLabel(.done)
                    .focused($focus, equals: .name)
                    .underlined()
                    .accessibilityLabel("Name")
                HStack(spacing: 1) {
                    Text("@").font(Theme.label(16))
                    TextField("", text: $nickname, prompt: Text("add a nickname").foregroundStyle(Theme.lime.opacity(0.6)))
                        .font(Theme.label(16))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.done)
                        .focused($focus, equals: .nickname)
                        .onChange(of: nickname) { _, v in
                            let t = v.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
                            if t != v { nickname = t }
                        }
                }
                .foregroundStyle(Theme.lime)
                .underlined()
                .accessibilityLabel("Nickname")
                if let problem = nicknameProblem {
                    Text(problem).font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.red.opacity(0.75)))
                }
                Text(model.user?.email ?? "Hidden (Apple)").font(.footnote.weight(.medium)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                if community.me.avatarUrl != nil {
                    Button("Remove photo", role: .destructive) { removePhoto() }
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(AccountTint.profile))
    }

    private func section(_ title: String) -> some View {
        Text(title).eyebrow().padding(.leading, 4).padding(.top, 12)
    }

    // MARK: Load + save

    private var snapshot: Snapshot {
        Snapshot(name: name.trimmingCharacters(in: .whitespaces),
                 nickname: nicknameProblem == nil ? nickname : (community.me.nickname ?? ""),
                 bio: bio.trimmingCharacters(in: .whitespacesAndNewlines), gender: gender, genderText: genderText, pronouns: pronouns,
                 pronounsCustom: pronounsCustom, coachCall: coachCall, showPronouns: showPronouns,
                 visibility: member ? visibility : nil, autoShare: member ? autoShare : nil)
    }

    private func load() {
        guard !loaded else { return }
        let me = community.me, b = model.body
        name = model.user?.name ?? ""
        nickname = me.nickname ?? ""
        bio = me.bio ?? ""
        gender = b.gender
        genderText = b.genderDescription ?? ""
        pronouns = b.pronouns
        pronounsCustom = b.pronounsCustom ?? ""
        coachCall = b.coachCall
        showPronouns = b.showPronouns ?? false
        visibility = community.profile?.defaultVisibility ?? .members
        autoShare = community.profile?.autoShare ?? false
        loaded = true
    }

    private static func detail(_ s: Snapshot) -> String {
        undoDetail(s.name.isEmpty ? nil : s.name, s.nickname.isEmpty ? nil : "@\(s.nickname)",
                   Pronouns.text(s.pronouns, custom: s.pronounsCustom))
    }

    /// Writes only what differs from what's stored. Also Undo's revert, so it reads no `@State`.
    private static func store(_ s: Snapshot, model: AppModel) {
        let talk = talk(s, into: model.body)
        if talk != model.body { model.saveBody(talk) }
        #if DEBUG
        if model.demo { return }
        #endif
        let api = model.api, community = Community.shared
        let me = community.me
        Task {
            if (model.user?.name ?? "") != s.name, let user = try? await api.updateName(s.name.isEmpty ? nil : s.name) {
                model.user = user
            }
            if let p = community.profile, let v = s.visibility, let a = s.autoShare, !s.nickname.isEmpty,
               p.nickname != s.nickname || (p.bio ?? "") != s.bio || p.defaultVisibility != v || p.autoShare != a {
                if let saved = try? await api.saveCommunityProfile(nickname: s.nickname, bio: s.bio, defaultVisibility: v,
                                                                   autoShare: a, acceptGuidelines: false) {
                    community.setProfile(saved)
                }
            } else if community.profile == nil, (me.nickname ?? "") != s.nickname || (me.bio ?? "") != s.bio,
                      let saved = try? await api.savePublicProfile(nickname: s.nickname, bio: s.bio) {
                community.setPublic(saved)
            }
        }
    }

    private static func talk(_ s: Snapshot, into body: BodyMetrics) -> BodyMetrics {
        var b = body
        b.gender = s.gender
        let described = s.genderText.trimmingCharacters(in: .whitespacesAndNewlines)
        b.genderDescription = s.gender == .selfDescribe && !described.isEmpty ? String(described.prefix(60)) : nil
        b.pronouns = s.pronouns
        let custom = s.pronounsCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        b.pronounsCustom = s.pronouns == .custom && !custom.isEmpty ? String(custom.prefix(24)) : nil
        b.coachCall = s.coachCall
        b.showPronouns = s.showPronouns ? true : nil
        return b
    }

    private func upload(_ item: PhotosPickerItem) {
        let api = model.api
        task.run {
            guard let data = try? await item.loadTransferable(type: Data.self), let jpeg = AvatarImage.jpeg(from: data) else {
                throw ProfilePhotoError()
            }
            photoItem = nil
            #if DEBUG
            if model.demo { return }
            #endif
            community.setPublic(try await api.uploadPublicAvatar(jpeg: jpeg))
        }
    }

    private func removePhoto() {
        let api = model.api
        task.run {
            #if DEBUG
            if model.demo { return }
            #endif
            community.setPublic(try await api.deletePublicAvatar())
        }
    }
}

private struct ProfilePhotoError: LocalizedError {
    var errorDescription: String? { "That photo could not be used." }
}

private extension View {
    /// Dashed line under an editable header field.
    func underlined() -> some View {
        padding(.bottom, 2).overlay(alignment: .bottom) {
            Rectangle().stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(height: 0.75).opacity(0.55)
        }
    }
}
