import SwiftUI

/// Account → Style (#219, #227): one pick sets the iPhone's game look and the Watch home and screens.
/// Also changeable on the Watch (gear on its home).
/// #251: swipe through one full-height card per style, each with real iPhone and Watch screens.
struct WatchHomeView: View {
    private var pref: WatchHomePref { .shared }
    @State private var focused: WatchHomeStyle?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your look on iPhone and Watch").font(Theme.label(13)).tracking(1).textCase(.uppercase)
                .foregroundStyle(Theme.lime)
                .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(WatchHomeStyle.allCases) { style in
                        Button { pref.set(style) } label: {
                            WatchStyleCard(style: style, selected: pref.style == style)
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame(.horizontal) { w, _ in w - 44 }
                        .id(style)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focused)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                ForEach(WatchHomeStyle.allCases) { style in
                    Circle().fill(style == current ? Theme.lime : .white.opacity(0.3)).frame(width: 8, height: 8)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Group {
                if current == pref.style {
                    Label("Your style", systemImage: "checkmark")
                        .foregroundStyle(Theme.lime)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(.white.opacity(0.1)))
                } else {
                    Button { pref.set(current) } label: {
                        Text("Use \(current.phoneTitle)")
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(Theme.display(17))
            .padding(.horizontal)
            .sensoryFeedback(.selection, trigger: pref.style)

            Text("XP, level and badges are the same in every style. You can also change it on the Watch: tap the gear on its home screen.")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Style")
        .onAppear { if focused == nil { focused = pref.style } }
    }

    private var current: WatchHomeStyle { focused ?? pref.style }
}

private struct WatchStyleCard: View {
    let style: WatchHomeStyle
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    // Badge above the title so a long name never truncates (#251).
                    if style == .default {
                        Text("DEFAULT").font(Theme.label(10)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.25)))
                    }
                    Text(style.phoneTitle).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(selected ? Theme.lime : .white.opacity(0.6))
            }
            Text(style.phoneDetail).font(.footnote.weight(.medium)).opacity(0.9)
                .multilineTextAlignment(.leading).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Label("Watch: \(style.title)", systemImage: "applewatch").font(Theme.label(12)).opacity(0.95)
            StylePreview(style: style).padding(.top, 8)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(style.gradient))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0))
        .padding(.vertical, 6)
        .animation(.spring(duration: 0.3), value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Real iPhone and Watch screens of a style (demo screenshots in Assets: StylePreview-Phone/Watch-<style>),
/// the Watch overlapping the iPhone's lower right corner.
private struct StylePreview: View {
    let style: WatchHomeStyle

    var body: some View {
        GeometryReader { geo in
            let phoneH = geo.size.height
            let phoneW = min(phoneH * 368 / 700, geo.size.width * 0.66)
            let watchW = min(phoneW * 0.72, geo.size.width - phoneW * 0.55)
            ZStack(alignment: .bottomTrailing) {
                Image("StylePreview-Phone-\(style.rawValue)").resizable().scaledToFill()
                    .frame(width: phoneW, height: phoneH, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.black.opacity(0.6), lineWidth: 3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Image("StylePreview-Watch-\(style.rawValue)").resizable().scaledToFit()
                    .frame(width: watchW)
                    .clipShape(RoundedRectangle(cornerRadius: watchW * 0.22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: watchW * 0.22, style: .continuous).strokeBorder(Color(white: 0.1), lineWidth: 5))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(minHeight: 220)
        .accessibilityHidden(true)
    }
}
