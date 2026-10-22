import SwiftUI

/// Gym buddy link (#626 B): a buddy's set ("Ana · Squat 70 kg × 8 ✓") with 🔥 🍌 🦍 to cheer back, or a cheer for
/// you. Over any screen for a few seconds; the phone relays both while it runs the buddy link.
struct BuddyPingView: View {
    @Environment(WatchStore.self) private var store

    private static let cheers: [(kind: String, emoji: String)] = [("fire", "🔥"), ("banana", "🍌"), ("beast", "🦍")]

    var body: some View {
        if let p = store.buddyPing {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.cheer == nil ? "\(p.name) · LIVE" : "\(p.name) cheered").font(W.label(10)).tracking(1).textCase(.uppercase)
                if let cheer = p.cheer {
                    Text(cheer).font(.system(size: 30))
                } else {
                    Text(p.text ?? "").font(W.display(15)).lineLimit(2).minimumScaleFactor(0.7)
                    HStack(spacing: 4) {
                        ForEach(Self.cheers, id: \.kind) { c in
                            Button {
                                store.send(.buddyCheer(userId: p.userId, kind: c.kind))
                                store.buddyPing = nil
                            } label: {
                                Text(c.emoji).font(.system(size: 18)).frame(maxWidth: .infinity, minHeight: 32)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.22)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cheer \(p.name) \(c.kind)")
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(0x00B86B, 0x1E9BFF)))
            .padding(.horizontal, W.edge)
            .onTapGesture { store.buddyPing = nil }
            .task(id: p.id) {
                try? await Task.sleep(for: .seconds(p.cheer == nil ? 6 : 3))
                if store.buddyPing?.id == p.id { store.buddyPing = nil }
            }
        }
    }
}
