import SwiftUI

/// "What's new" (#183): Explore-style gradient card per improvement of this release.
struct WhatsNewView: View {
    let notes: WhatsNew
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This update").eyebrow()
                    Text("What's new").font(Theme.display(40))
                }
                .padding(.bottom, 6)
                ForEach(notes.items) { item in
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
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
