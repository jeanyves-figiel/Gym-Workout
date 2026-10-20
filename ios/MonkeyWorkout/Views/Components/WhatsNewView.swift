import SwiftUI

/// "What's new" (#183) on first open after an update: this release's cards, closed with Let's train.
struct WhatsNewView: View {
    let notes: WhatsNew
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WhatsNewHeader(eyebrow: "This update")
                ForEach(notes.items) { WhatsNewCard(item: $0) }
            }
            .padding(16)
            .padding(.top, 24)
        }
        .readableWidth()
        .safeAreaInset(edge: .bottom) {
            Button { dismiss() } label: {
                Text("LET'S TRAIN").frame(maxWidth: .infinity)
            }
            .buttonStyle(LimeButtonStyle())
            .padding(16)
            .readableColumn()
            .background(Theme.bg.opacity(0.92).ignoresSafeArea())
        }
        .background(Theme.bg.ignoresSafeArea())
        // Sheets close with the X top right too, not only Let's train.
        .toolbar { CloseToolbarItem { dismiss() } }
    }
}

/// Account → What's new (#245): every release, newest first, each under its day and build.
struct WhatsNewHistoryView: View {
    let latest: WhatsNew?
    let history: [WhatsNew]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                WhatsNewHeader(eyebrow: "All updates")
                if let latest {
                    release(latest, label: ["Latest", latest.day].compactMap { $0 }.joined(separator: " · "))
                }
                ForEach(history) { r in
                    release(r, label: [r.day, r.build.map { "Build \($0)" }].compactMap { $0 }.joined(separator: " · "))
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
    }

    private func release(_ r: WhatsNew, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).eyebrow().padding(.leading, 4).padding(.top, 14)
            ForEach(r.items) { WhatsNewCard(item: $0) }
        }
    }
}

private struct WhatsNewHeader: View {
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow).eyebrow()
            Text("What's new").font(Theme.display(40))
        }
        .padding(.bottom, 6)
    }
}

/// One improvement: icon tile, heavy title, one-line body on the item's category gradient.
struct WhatsNewCard: View {
    let item: WhatsNew.Item

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            IconTile(symbol: item.symbol, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(Theme.display(22)).lineLimit(2).minimumScaleFactor(0.8)
                Text(item.body).font(.subheadline.weight(.medium)).opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(item.tint.gradient, padding: 18)
    }
}
