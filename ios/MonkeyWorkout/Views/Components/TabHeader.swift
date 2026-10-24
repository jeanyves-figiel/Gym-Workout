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
            // Kept on the device (#639): shown at launch, before the profile has loaded.
            if let img = MeAvatar.shared.image(for: ownerId) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let url {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
        .task(id: "\(Community.shared.loaded)-\(url?.absoluteString ?? "")") {
            guard !model.demo, Community.shared.loaded else { return }
            await MeAvatar.shared.update(url, userId: ownerId)
        }
    }

    private var url: URL? { model.api.resolve(Community.shared.me.avatarUrl) }
    private var ownerId: String? { model.user?.id ?? model.state.ownerId }
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

/// Me sheet (#736, design A from `me-sheet/proposals.png`): one hero (photo and name open Your profile, the
/// level bar opens Levels), then the six Settings chapters as square tiles, each opening Settings at that chapter.
struct MeSheet: View {
    @Environment(AppModel.self) private var model
    @State private var community = Community.shared

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero
                HStack {
                    Text("Settings").font(Theme.label(13)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.muted)
                    Spacer()
                    NavigationLink { AccountView() } label: {
                        Text("All ›").font(Theme.label(14)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("All settings")
                    .accessibilityIdentifier("me.settings")
                }
                .padding(.top, 6).padding(.horizontal, 2)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(SettingsChapter.allCases) { chapter in
                        NavigationLink { AccountView(start: chapter) } label: { tile(chapter) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("me.chapter.\(chapter.rawValue)")
                    }
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .titleInContent("You")
    }

    private var hero: some View {
        let g = model.game
        let me = community.me
        return VStack(alignment: .leading, spacing: 12) {
            // One profile (#578): photo and name open Your profile; no second row to the same page.
            NavigationLink { ProfileView() } label: {
                HStack(spacing: 14) {
                    MePhoto(size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.user?.name?.isEmpty == false ? model.user!.name! : "Add your name")
                            .font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(me.nickname.map { "@\($0)" } ?? "@ add a nickname")
                            .font(Theme.label(15)).opacity(0.85)
                    }
                    Spacer(minLength: 4)
                    Text("Edit ›").font(Theme.label(13))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.22)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Your profile: name, photo, posts, followers")
            .accessibilityIdentifier("me.profile")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Level \(g.level) · \(model.rank.title) ›").font(Theme.label(12)).tracking(1.2).textCase(.uppercase)
                    Spacer()
                    Text("\(g.xpInLevel) / \(GameProgress.perLevel) XP").font(Theme.label(12)).monospacedDigit().opacity(0.85)
                }
                XPBarView(progress: g.levelProgress, track: .black.opacity(0.25))
            }
            .opensLevels()
            .accessibilityIdentifier("me.levels")
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(AccountTint.profile))
    }

    private func tile(_ chapter: SettingsChapter) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IconTile(symbol: chapter.symbol, size: 40)
            Spacer(minLength: 8)
            Text(chapter.title).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.8)
            Text(chapter.summary).font(.footnote.weight(.semibold)).opacity(0.85).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(chapter.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
