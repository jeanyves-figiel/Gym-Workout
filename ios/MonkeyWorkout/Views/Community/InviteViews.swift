import APIClient
import SwiftUI
import UIKit
import WorkoutEngine

// Invite a friend (#745, design A + C from `referral-invites/proposals.png`): the Social Invite tile opens its own
// page. A: code, share buttons, invite stats and Gym buddies on one page. C: the reward ladder. Text only since #777
// (`referral-invites/v2/proposals.png` A): "What you send" shows the message; story posters live on the content
// itself (`StorySharing.swift`).

struct InviteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var friendCode = ""
    @State private var redeeming = false
    @State private var copied = false
    private var store: ReferralStore { .shared }

    private static let pink = LinearGradient(colors: [Color(hex: 0xFF2D87), Color(hex: 0xFF9A3C)], startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let amber = LinearGradient(colors: [Color(hex: 0xFFB800), Color(hex: 0xFF5C3C)], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero
                whatYouSend
                shareButtons
                stats
                if store.summary?.canRedeem == true { redeemCard }
                if let by = store.summary?.invitedBy { invitedBy(by) }
                Text("Rewards").eyebrow().padding(.leading, 4).padding(.top, 8)
                ForEach(InviteReward.allCases) { ladderRow($0) }
                Text("Pro rewards arrive as App Store offer codes once Pro launches. A reward counts when your friend's first paid month starts, not a free trial.")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                ErrorText(message: store.error)
                NavigationLink { BuddiesScreen() } label: { buddiesTile }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Invite")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            #if DEBUG
            if model.demo { store.loadDemo(); return }
            #endif
            await store.load(api: model.api, userId: model.user?.id)
        }
        .refreshable { await store.load(api: model.api, userId: model.user?.id) }
    }

    private var code: String { store.code ?? "·······" }
    private var link: URL? { store.summary.flatMap { AppConfig.publicLink($0.path) } } // public web base, never localhost (#823)
    private var message: String {
        "Train with me on MonkeyWorkout 🐵 Use my code \(code)" + (link.map { ": \($0.absoluteString)" } ?? "")
    }

    // MARK: A · hero + share

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GIVE 1 · GET 1").font(Theme.label(11)).tracking(2).opacity(0.85)
                    Text("Bring a training buddy").font(Theme.display(28)).lineLimit(2).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(store.joined)").font(Theme.display(34)).monospacedDigit()
                    Text("JOINED").font(Theme.label(9)).tracking(1.2).opacity(0.85)
                }
            }
            // No Pro promise while Pro isn't on (#822).
            Text("Friends who join with your code unlock XP and app icons for you."
                 + (ProStore.shared.visible ? " When one subscribes, you both get a month of Pro." : ""))
                .font(.footnote.weight(.semibold)).opacity(0.92)
            Button { copy() } label: {
                HStack {
                    Text(code).font(.system(size: 26, weight: .black, design: .monospaced)).tracking(4)
                    Spacer()
                    Image(systemName: copied ? "checkmark" : "doc.on.doc.fill").font(.system(size: 16, weight: .bold))
                }
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.22)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your code \(code). Copy invite link")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(Self.pink)
    }

    private var shareButtons: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            Button { openShare("sms:&body=") } label: { shareTile("message.fill", "Messages", lime: true) }
            Button { openShare("https://wa.me/?text=") } label: { shareTile("phone.bubble.fill", "WhatsApp", lime: true) }
            Button { copy() } label: { shareTile(copied ? "checkmark" : "link", copied ? "Copied" : "Copy link", lime: false) }
            ShareLink(item: message) { shareTile("square.and.arrow.up", "More…", lime: false) }
        }
        .buttonStyle(.plain)
        .disabled(store.code == nil)
    }

    /// Exactly what every button sends (#777).
    private var whatYouSend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What you send").eyebrow().padding(.leading, 4)
            Text(message).font(.subheadline.weight(.semibold)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
        }
    }

    private func shareTile(_ symbol: String, _ title: String, lime: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(Theme.label(14))
            .foregroundStyle(lime ? Theme.ink : .white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(lime ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
    }

    private func openShare(_ prefix: String) {
        let text = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? ""
        if let url = URL(string: prefix + text) { openURL(url) }
    }

    private func copy() {
        guard store.code != nil else { return }
        UIPasteboard.general.string = message
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    // MARK: Stats, redeem

    private var stats: some View {
        HStack(spacing: 10) {
            GradientStat(symbol: "person.badge.plus", value: "\(store.joined)", label: "Joined", gradient: WorkoutEngine.Category.strength.gradient)
            GradientStat(symbol: "star.fill", value: "\(store.subscribed)", label: "Pro", gradient: WorkoutEngine.Category.mobility.gradient)
            GradientStat(symbol: "bolt.fill", value: "+\(store.xp)", label: "XP earned", gradient: WorkoutEngine.Category.cardio.gradient)
        }
    }

    private var redeemCard: some View {
        GradientSection(symbol: "ticket.fill", title: "Got a friend's code?", gradient: WorkoutEngine.Category.power.gradient) {
            HStack(spacing: 8) {
                TextField("", text: $friendCode, prompt: Text("CODE").foregroundStyle(.white.opacity(0.6)))
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12).frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
                Button("ENTER") { redeem() }
                    .font(Theme.label(14)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lime))
                    .buttonStyle(.plain)
                    .disabled(friendCode.count < 4 || redeeming)
            }
            Text("Works in your first 14 days. You get +\(InviteReward.welcomeXP) XP.").font(.caption.weight(.semibold)).opacity(0.9)
        }
    }

    private func redeem() {
        redeeming = true
        Task {
            if await store.redeem(friendCode, api: model.api) { friendCode = "" }
            redeeming = false
        }
    }

    private func invitedBy(_ by: ReferralSummary.Inviter) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: "hands.clap.fill", size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Invited by \(by.nickname ?? "a friend")").font(Theme.display(17))
                Text("Welcome bonus +\(InviteReward.welcomeXP) XP").font(.footnote.weight(.semibold)).opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(WorkoutEngine.Category.cardio.gradient)
    }

    // MARK: C · ladder

    @ViewBuilder private func ladderRow(_ r: InviteReward) -> some View {
        let earned = r.earned(store)
        let next = !earned && InviteReward.allCases.first(where: { !$0.earned(store) }) == r
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(r == .proMonth ? "⭐" : "\(r.need)")
                    .font(Theme.display(22)).monospacedDigit()
                    .frame(width: 34)
                Text("\(r.emoji) \(r.title)").font(Theme.label(14)).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if earned {
                    Image(systemName: r.isPro ? "clock.badge.checkmark.fill" : "checkmark.circle.fill").font(.system(size: 20, weight: .bold))
                } else if !next {
                    Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold)).opacity(0.7)
                }
            }
            if earned, let rank = r.appIconRank { AppIconPicker(rank: rank) }
        }
        .foregroundStyle(earned || next ? Color.white : Color.white.opacity(0.75))
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
            earned ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3FBF74), Color(hex: 0x3C9DFF)], startPoint: .leading, endPoint: .trailing))
                : next ? AnyShapeStyle(Self.amber) : AnyShapeStyle(Theme.card)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.title). \(earned ? (r.isPro ? "Earned, arrives as an offer code" : "Unlocked") : r == .proMonth ? "When a friend subscribes" : "\(r.need) friends")")
    }

    private var buddiesTile: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "figure.2", size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Gym buddies").font(Theme.display(18))
                Text("Live sets and cheers on your Watch").font(.footnote.weight(.semibold)).opacity(0.88)
            }
            Spacer(minLength: 4)
            Text("\(LiveRoom.shared.paired.count)").font(Theme.display(26)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(LinearGradient(colors: [Color(hex: 0x00B86B), Color(hex: 0x1E9BFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

// MARK: - Socials (S2 square tiles)

enum SocialNetwork: String, CaseIterable, Identifiable {
    case instagram, tiktok, strava, youtube

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .strava: "Strava"
        case .youtube: "YouTube"
        }
    }

    var emoji: String {
        switch self {
        case .instagram: "📸"
        case .tiktok: "🎵"
        case .strava: "🏃"
        case .youtube: "▶️"
        }
    }

    var fill: AnyShapeStyle {
        switch self {
        case .instagram: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFEDA75), Color(hex: 0xFA7E1E), Color(hex: 0xD62976), Color(hex: 0x962FBF)],
                                                      startPoint: .bottomLeading, endPoint: .topTrailing))
        case .tiktok: AnyShapeStyle(Color(hex: 0x111111))
        case .strava: AnyShapeStyle(Color(hex: 0xFC4C02))
        case .youtube: AnyShapeStyle(Color(hex: 0xFF0033))
        }
    }

    var placeholder: String {
        switch self {
        case .strava: "athlete id or name"
        default: "handle"
        }
    }

    func handle(_ s: SocialHandles) -> String? {
        let v: String? = switch self {
        case .instagram: s.instagram
        case .tiktok: s.tiktok
        case .strava: s.strava
        case .youtube: s.youtube
        }
        return (v ?? "").isEmpty ? nil : v
    }

    func set(_ s: inout SocialHandles, _ v: String?) {
        switch self {
        case .instagram: s.instagram = v
        case .tiktok: s.tiktok = v
        case .strava: s.strava = v
        case .youtube: s.youtube = v
        }
    }

    func url(_ handle: String) -> URL? {
        let h = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        return switch self {
        case .instagram: URL(string: "https://instagram.com/\(h)")
        case .tiktok: URL(string: "https://www.tiktok.com/@\(h)")
        case .strava: URL(string: "https://www.strava.com/athletes/\(h)")
        case .youtube: URL(string: "https://www.youtube.com/@\(h)")
        }
    }

    /// Characters each network allows besides ASCII letters and digits (same rules as the server).
    private var extra: String {
        switch self {
        case .instagram, .tiktok: "._"
        case .strava: "_-"
        case .youtube: "._-"
        }
    }

    /// Handle as the server stores it: no "@", spaces or characters the network doesn't allow.
    func clean(_ v: String) -> String {
        String(v.filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || extra.contains($0) }.prefix(self == .strava ? 40 : self == .tiktok ? 24 : 30))
    }
}

/// Square tiles on a member page; each opens the app or site.
struct SocialTiles: View {
    let socials: SocialHandles
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SocialNetwork.allCases) { n in
                if let h = n.handle(socials) {
                    Button { if let u = n.url(h) { openURL(u) } } label: {
                        VStack(spacing: 4) {
                            Text(n.emoji).font(.system(size: 24))
                            Text(n == .strava ? "Strava" : "@\(h)").font(Theme.label(10)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(n.fill))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n.title) \(h)")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Your profile: handles and who sees them. Saved with the page (auto save).
struct SocialsEditor: View {
    @Binding var socials: SocialHandles
    @Binding var visibility: SocialsVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            handles
            GradientSegments(selection: $visibility, items: [
                SegmentItem(value: .everyone, title: "Everyone", symbol: "globe"),
                SegmentItem(value: .following, title: "Followers", symbol: "person.2.fill"),
                SegmentItem(value: .nobody, title: "Nobody", symbol: "eye.slash.fill"),
            ])
        }
    }

    private var handles: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SocialNetwork.allCases) { n in
                HStack(spacing: 10) {
                    Text(n.emoji).font(.system(size: 18))
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(n.fill))
                    Text(n.title).font(Theme.label(14))
                    Spacer(minLength: 8)
                    TextField("", text: Binding(get: { n.handle(socials) ?? "" }, set: { v in
                        let c = n.clean(v)
                        n.set(&socials, c.isEmpty ? nil : c)
                    }), prompt: Text(n.placeholder).foregroundStyle(Theme.muted))
                    .multilineTextAlignment(.trailing)
                    .font(.body.weight(.semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("\(n.title) handle")
                }
            }
        }
        .card(padding: 14)
    }
}
