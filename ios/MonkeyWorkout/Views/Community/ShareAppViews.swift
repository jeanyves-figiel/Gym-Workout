import SwiftUI
import UIKit

// Share MonkeyWorkout (#1113, placement 3 from `share-preview/ios-proposals.png`): a gradient tile on Invite and on
// the You hub opens a sheet to pick Story (1080×1920), Post (1080×1080) or Link. Story and Post send the bundled
// share art (design C, same files as the server's `/og/story.jpg` and `/og/post.jpg`) with the `/app` link in the
// text, so Instagram, TikTok and WhatsApp get a picture. Link sends `/app`, whose preview is the big design A card.

enum ShareAppFormat: String, CaseIterable, Identifiable {
    case story, post, link
    var id: String { rawValue }
    var title: String {
        switch self {
        case .story: "Story"
        case .post: "Post"
        case .link: "Link"
        }
    }
    var hint: String {
        switch self {
        case .story: "Instagram or TikTok story. Add the link with a sticker."
        case .post: "Square picture for a feed post."
        case .link: "Messages, WhatsApp, Slack: shows a big preview."
        }
    }
    /// Asset name of the bundled art; Link has no picture of its own.
    var asset: String? {
        switch self {
        case .story: "share-story"
        case .post: "share-post"
        case .link: nil
        }
    }
}

enum ShareApp {
    static let gradient = LinearGradient(colors: [Color(hex: 0x6A3CFF), Color(hex: 0x2D7BFF), Color(hex: 0x00D1B2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Public web base, never localhost (#823).
    static var link: URL? { AppConfig.publicLink("/app") }
    static var message: String {
        "Train with me on MonkeyWorkout 🐵 Gym plans, AI Coach and Apple Watch" + (link.map { ": \($0.absoluteString)" } ?? "")
    }
}

/// Gradient tile that opens the Share MonkeyWorkout sheet.
struct ShareAppTile: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 14) {
                Image("share-story").resizable().scaledToFill()
                    .frame(width: 46, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Share MonkeyWorkout").font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("Story, post or link with a big preview").font(.footnote.weight(.semibold)).opacity(0.9)
                }
                Spacer(minLength: 4)
                Image(systemName: "square.and.arrow.up").font(.system(size: 18, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gradientCard(ShareApp.gradient, padding: 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shareApp.tile")
        .sheet(isPresented: $open) { ShareAppSheet() }
    }
}

/// Pick Story, Post or Link, see what goes out, then the iOS share sheet.
struct ShareAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var format: ShareAppFormat = .story

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(ShareAppFormat.allCases) { f in
                            Button { format = f } label: {
                                Text(f.title).font(Theme.label(14))
                                    .foregroundStyle(format == f ? Theme.ink : .white)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(format == f ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(format == f ? .isSelected : [])
                        }
                    }
                    preview
                    Text(format.hint).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                    shareButton
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Share MonkeyWorkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var preview: some View {
        if let asset = format.asset {
            Image(asset).resizable().scaledToFit()
                .frame(maxHeight: format == .story ? 380 : 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("MonkeyWorkout share picture")
        } else {
            // What Messages shows for the link: the server's design A card (`/og/link.jpg`).
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: AppConfig.publicLink("/og/link.jpg")) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Rectangle().fill(Color(hex: 0xFF6A3C)).aspectRatio(1200.0 / 630.0, contentMode: .fit)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MonkeyWorkout: gym plans, AI Coach, Apple Watch").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(ShareApp.link?.host() ?? "").font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(10)
            }
            .background(Theme.cardStrong)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder private var shareButton: some View {
        let label = Label("Share", systemImage: "square.and.arrow.up").font(Theme.label(16))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
        if let asset = format.asset, let ui = UIImage(named: asset) {
            let image = Image(uiImage: ui)
            ShareLink(item: image, message: Text(ShareApp.message), preview: SharePreview("MonkeyWorkout", image: image)) { label }
                .accessibilityIdentifier("shareApp.share")
        } else if let url = ShareApp.link {
            ShareLink(item: url, message: Text("Train with me on MonkeyWorkout 🐵")) { label }
                .accessibilityIdentifier("shareApp.share")
        }
    }
}
