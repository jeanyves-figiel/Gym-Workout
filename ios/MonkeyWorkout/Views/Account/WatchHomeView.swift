import SwiftUI

/// Account → Style (#219, #227): one pick sets the iPhone's game look and the Watch home and screens.
/// Also changeable on the Watch (gear on its home).
struct WatchHomeView: View {
    private var pref: WatchHomePref { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your look on iPhone and Watch").font(Theme.label(13)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Theme.lime)
                ForEach(WatchHomeStyle.allCases) { style in
                    Button { pref.set(style) } label: {
                        WatchStyleCard(style: style, selected: pref.style == style)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: pref.style)
                }
                Text("XP, level and badges are the same in every style. You can also change it on the Watch: tap the gear on its home screen.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Style")
    }
}

private struct WatchStyleCard: View {
    let style: WatchHomeStyle
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: style.phoneSymbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(style.phoneTitle).font(Theme.display(21))
                    if style == .default {
                        Text("DEFAULT").font(Theme.label(10)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.25)))
                    }
                }
                Text(style.phoneDetail).font(.footnote.weight(.medium)).opacity(0.9).multilineTextAlignment(.leading)
                Label("Watch: \(style.title)", systemImage: "applewatch").font(Theme.label(12)).opacity(0.95)
            }
            Spacer(minLength: 4)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(selected ? Theme.lime : .white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(
            LinearGradient(colors: [rgb(style.tint.0), rgb(style.tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0))
        .shadow(color: selected ? Theme.lime.opacity(0.35) : .clear, radius: 10)
        .scaleEffect(selected ? 1 : 0.97)
        .animation(.spring(duration: 0.3), value: selected)
    }

    private func rgb(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
