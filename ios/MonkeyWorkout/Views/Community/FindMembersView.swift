import APIClient
import SwiftUI
import WorkoutEngine

/// Feed entry to Find members (#152): who you follow, at a glance.
struct FindMembersCard: View {
    private var community: Community { .shared }

    var body: some View {
        NavigationLink { FindMembersView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find members").font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.75)
                    Text("Search nicknames or gyms, see who trains at yours").font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(community.profile?.following ?? 0)").font(Theme.display(26)).monospacedDigit()
                    Text("FOLLOWING").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
                .fixedSize()
                Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.cardio.gradient))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Find members. Following \(community.profile?.following ?? 0).")
    }
}

/// Search members by nickname or gym (#152). Empty search: members at your gym, who you follow, then suggestions.
/// The server leaves out you, anyone blocked either way and members hidden by reports. Gyms show only when the member opts in.
struct FindMembersView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [CommunityMemberSummary]?
    @State private var following: [CommunityMemberSummary] = []
    @State private var atGym: [CommunityMemberSummary] = []
    @State private var savingGym = false
    @State private var error: String?

    private var community: Community { .shared }
    private var showsGym: Bool { community.profile?.showGym == true }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            // Not lazy: one member can sit in several sections (gym, following), and a lazy stack would collide their ids.
            VStack(alignment: .leading, spacing: 12) {
                ErrorText(message: error)
                if let results {
                    if searching {
                        section("Results", results, empty: "No member or gym matching “\(query.trimmingCharacters(in: .whitespaces))”.")
                    } else {
                        gymSection
                        if !following.isEmpty { section("Following", following, empty: nil) }
                        section("Suggested", results, empty: following.isEmpty ? "No other members yet." : nil)
                    }
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Find members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nickname or gym")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task(id: query) { await load() }
    }

    /// Members at your gym, or the opt-in card while you don't show yours.
    @ViewBuilder
    private var gymSection: some View {
        if showsGym {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("AT \((community.profile?.gym ?? "YOUR GYM").uppercased())")
                        .font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    Button("Hide my gym") { setShowGym(false) }.font(.caption.bold()).foregroundStyle(Theme.lime).disabled(savingGym)
                }
                .padding(.top, 4)
                if atGym.isEmpty {
                    Text("Nobody else there shows their gym yet.").font(.subheadline).foregroundStyle(Theme.muted)
                }
                ForEach(atGym) { m in MemberRow(member: m) { toggleFollow(m) } }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Who trains at your gym").font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("Show \(community.profile?.gym ?? "your gym") on your profile to see members who show the same gym.")
                            .font(.footnote.weight(.semibold)).opacity(0.88)
                    }
                }
                Button("SHOW MY GYM") { setShowGym(true) }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(savingGym || community.profile?.gym == nil)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
        }
    }

    private func setShowGym(_ on: Bool) {
        savingGym = true
        Task {
            defer { savingGym = false }
            #if DEBUG
            if model.demo { return }
            #endif
            do {
                community.setProfile(try await model.api.setShowGym(on))
                atGym = try await gymList()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func section(_ title: String, _ rows: [CommunityMemberSummary], empty: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !rows.isEmpty || empty != nil {
                Text(title.uppercased()).font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 4)
            }
            if rows.isEmpty, let empty {
                Text(empty).font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(rows) { m in
                MemberRow(member: m) { toggleFollow(m) }
            }
        }
    }

    private func load() async {
        #if DEBUG
        if model.demo {
            let all = FindMembersView.demoMembers
            following = all.filter(\.followedByMe)
            atGym = all.filter { $0.gym != nil }
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            results = q.isEmpty ? all.filter { !$0.followedByMe }
                : all.filter { $0.nickname.lowercased().contains(q) || ($0.gym?.lowercased().contains(q) ?? false) }
            return
        }
        #endif
        if searching { try? await Task.sleep(for: .milliseconds(300)) }
        guard !Task.isCancelled else { return }
        do {
            if searching {
                results = try await model.api.searchMembers(query)
            } else {
                async let f = model.api.followingMembers()
                async let s = model.api.searchMembers("")
                async let g = gymList()
                (following, results, atGym) = try await (f, s, g)
            }
            error = nil
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func gymList() async throws -> [CommunityMemberSummary] {
        guard showsGym else { return [] }
        return try await model.api.gymMembers()
    }

    private func toggleFollow(_ m: CommunityMemberSummary) {
        let on = m.followedByMe
        apply(m.userId, followed: !on)
        Task {
            do {
                #if DEBUG
                if model.demo { return }
                #endif
                if on {
                    try await model.api.unfollow(m.userId)
                    Community.shared.unfollowed(m.userId)
                } else {
                    try await model.api.follow(m.userId)
                    Community.shared.followed()
                    await Community.shared.refresh(api: model.api)
                }
            } catch {
                apply(m.userId, followed: on)
                self.error = error.localizedDescription
            }
        }
    }

    /// Optimistic follow state in every list the member appears in.
    private func apply(_ userId: String, followed: Bool) {
        func update(_ rows: inout [CommunityMemberSummary]) {
            for i in rows.indices where rows[i].userId == userId {
                guard rows[i].followedByMe != followed else { continue }
                rows[i].followedByMe = followed
                rows[i].followers += followed ? 1 : -1
            }
        }
        if results != nil { update(&results!) }
        update(&following)
        update(&atGym)
    }

    #if DEBUG
    static let demoMembers: [CommunityMemberSummary] = [
        CommunityMemberSummary(userId: "u-bea", nickname: "bench_bea", bio: "Powerlifter. Bench day is the best day.", gym: "Fitnesspark Puls 5", sharedPosts: 14, followers: 38, followedByMe: true),
        CommunityMemberSummary(userId: "u-crimpy", nickname: "crimpy", bio: "Boulderer building pulling strength.", sharedPosts: 9, followers: 21),
        CommunityMemberSummary(userId: "u-squat", nickname: "squat_sara", bio: nil, gym: "Fitnesspark Puls 5", sharedPosts: 6, followers: 12),
        CommunityMemberSummary(userId: "u-kb", nickname: "kettle.ken", bio: "Kettlebells at 6am.", sharedPosts: 3, followers: 4),
    ]
    #endif
}

/// Explore-style member card: avatar left, nickname + about, follow button right. Tap opens their page.
private struct MemberRow: View {
    let member: CommunityMemberSummary
    let toggleFollow: () -> Void
    @Environment(AppModel.self) private var model

    private static let gradients: [WorkoutEngine.Category] = [.strength, .power, .cardio, .mobility, .stretch]
    private var gradient: LinearGradient {
        let i = member.userId.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Self.gradients[i % Self.gradients.count].gradient
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: member.author) {
                HStack(spacing: 12) {
                    AvatarView(url: model.api.resolve(member.avatarUrl), nickname: member.nickname, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.nickname).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                        if let gym = member.gym {
                            Label(gym, systemImage: "building.2.fill").font(Theme.label(11)).lineLimit(1).opacity(0.95)
                        }
                        Text(member.bio ?? "\(member.sharedPosts) shared · \(member.followers) followers")
                            .font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(member.nickname), \(member.followers) followers")
            Button(action: toggleFollow) {
                Text(member.followedByMe ? "FOLLOWING" : "FOLLOW")
                    .font(Theme.label(12)).tracking(1)
                    .foregroundStyle(member.followedByMe ? .white : Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(member.followedByMe ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(Theme.lime)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(member.followedByMe ? "Unfollow \(member.nickname)" : "Follow \(member.nickname)")
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
    }
}
