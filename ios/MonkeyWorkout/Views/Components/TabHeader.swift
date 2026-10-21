import SwiftUI
import WorkoutEngine

// MARK: - Unified tab header (#560, design B from `header-menu/proposals.png`)

/// Rounded square for a tab's own action at the top right (Train and Progress widgets, Fuel settings,
/// Community Share a win), 44 pt on every tab.
struct HeaderTile: View {
    let symbol: String
    var lime = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(lime ? Theme.ink : .white)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(lime ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.14))))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// Square profile photo, initials on lime when there is none.
struct MePhoto: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 34

    private var initials: String {
        let name = model.user?.name ?? ""
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        if !parts.isEmpty { return String(parts).uppercased() }
        if let n = Community.shared.me.nickname, let f = n.first { return String(f).uppercased() }
        return "🐵"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        ZStack {
            shape.fill(Theme.lime)
            Text(initials).font(Theme.label(size * 0.4)).foregroundStyle(Theme.ink)
            if let url = model.api.resolve(Community.shared.me.avatarUrl) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// The one way to you from every tab: gradient pill with the level and your photo. Opens the Me sheet
/// (profile, level, Settings). Replaces the LV chip, the gear avatar and Community's second photo.
struct MePill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.meOpen = true } label: {
            HStack(spacing: 6) {
                Text("LV \(model.game.level)").font(Theme.label(14)).tracking(0.5).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
                MePhoto(size: 36)
            }
            .padding(.leading, 11).padding(.trailing, 4).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(AccountTint.profile))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("You, level \(model.game.level)")
        .accessibilityHint("Your profile, level and Settings")
        .accessibilityIdentifier("me.pill")
    }
}

/// Me sheet: photo hero with the level bar, then Edit profile, Community profile (members) and Settings.
struct MeSheet: View {
    @Environment(AppModel.self) private var model
    @State private var community = Community.shared

    var body: some View {
        let g = model.game
        let me = community.me
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink { ProfileView() } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            MePhoto(size: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.user?.name?.isEmpty == false ? model.user!.name! : "Add your name")
                                    .font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.7)
                                Text(me.nickname.map { "@\($0)" } ?? "@ add a nickname")
                                    .font(Theme.label(15)).opacity(0.85)
                            }
                            Spacer(minLength: 0)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Level \(g.level) · \(model.rank.title)").font(Theme.label(12)).tracking(1.2).textCase(.uppercase)
                                Spacer()
                                Text("\(g.xpInLevel) / \(GameProgress.perLevel) XP").font(Theme.label(12)).monospacedDigit().opacity(0.85)
                            }
                            XPBarView(progress: g.levelProgress, track: .black.opacity(0.25))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(AccountTint.profile))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit your profile")

                row("Levels", detail: "What each level brings", symbol: "star.fill", gradient: WorkoutEngine.Category.power.gradient)
                    .opensLevels()
                NavigationLink { ProfileView() } label: {
                    row("Edit profile", detail: "Name, photo, about, pronouns", symbol: "person.fill", gradient: AccountTint.publicProfile)
                }
                .buttonStyle(.plain)
                if community.profile != nil {
                    NavigationLink { CommunityProfileView() } label: {
                        row("Community profile", detail: "Your posts and followers", symbol: "person.3.fill", gradient: WorkoutEngine.Category.mobility.gradient)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink { AccountView() } label: {
                    row("Settings", detail: "Account, plan, devices, notifications", symbol: "gearshape.fill", gradient: WorkoutEngine.Category.strength.gradient)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("me.settings")
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .titleInContent("You")
    }

    private func row(_ title: String, detail: String, symbol: String, gradient: LinearGradient) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(19))
                Text(detail).font(.footnote.weight(.semibold)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
