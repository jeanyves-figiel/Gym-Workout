import SwiftUI
import WorkoutEngine

/// Gradients for Account areas (#71). Reuse category colors so Account matches Explore.
enum AccountTint {
    static let profile = LinearGradient(colors: [Color(red: 0.48, green: 0.24, blue: 1), Color(red: 1, green: 0.30, blue: 0.85)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let body = WorkoutEngine.Category.power.gradient
    static let password = WorkoutEngine.Category.strength.gradient
    static let email = WorkoutEngine.Category.cardio.gradient
    static let devices = WorkoutEngine.Category.mobility.gradient
    static let export = WorkoutEngine.Category.stretch.gradient
    static let danger = LinearGradient(colors: [Color(red: 1, green: 0.23, blue: 0.19), Color(red: 1, green: 0.45, blue: 0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Explore-style row: icon tile left, heavy title + subtitle, trailing value or chevron.
/// Other features (Community profile, Notifications, Training calendar) add Account rows with this.
struct AccountCard<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var gradient: LinearGradient?
    var ink = false
    var textColor: Color?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(gradient == nil ? (textColor ?? Theme.lime).opacity(0.15) : .white.opacity(0.2)))
                .foregroundStyle(gradient == nil ? (textColor ?? Theme.lime) : (ink ? Theme.ink : .white))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle).font(.footnote.weight(.medium)).opacity(0.85).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .foregroundStyle(textColor ?? (ink ? Theme.ink : .white))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let gradient {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(gradient)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(textColor.map { $0.opacity(0.45) } ?? Theme.stroke))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

extension AccountCard where Trailing == AccountChevron {
    init(symbol: String, title: String, subtitle: String? = nil, gradient: LinearGradient?, ink: Bool = false) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, gradient: gradient, ink: ink) { AccountChevron() }
    }
}

struct AccountChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).opacity(0.8)
    }
}

/// Big number with a small unit under it, right side of a card.
struct AccountValue: View {
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(unit.uppercased()).font(Theme.label(9)).tracking(1).opacity(0.8)
        }
    }
}

/// Gradient header for Account sub-screens.
struct AccountHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    let gradient: LinearGradient
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .bold))
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle).font(.footnote.weight(.medium)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
    }
}

extension AccountHeader where Trailing == EmptyView {
    init(symbol: String, title: String, subtitle: String? = nil, gradient: LinearGradient) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, gradient: gradient) { EmptyView() }
    }
}

/// Lime full-width action with busy spinner; dims when disabled.
struct LimeActionButton: View {
    let title: String
    var symbol: String?
    var busy = false
    var disabled = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if busy {
                ProgressView().tint(destructive ? .white : Theme.ink)
            } else if let symbol {
                Label(title.uppercased(), systemImage: symbol)
            } else {
                Text(title.uppercased())
            }
        }
        .buttonStyle(LimeButtonStyle(fill: destructive ? Color(red: 1, green: 0.23, blue: 0.19) : Theme.lime,
                                     text: destructive ? .white : Theme.ink))
        .disabled(busy || disabled)
        .opacity(disabled && !busy ? 0.4 : 1)
    }
}

/// Input field on a dark card with an eyebrow label above.
struct AccountField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow().padding(.leading, 4)
            content()
                .font(.body.weight(.semibold))
                .card(padding: 14)
        }
    }
}

/// Secondary capsule button (Sign out, Resend…).
struct AccountPillButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(Theme.label(14))
                .foregroundStyle(role == .destructive ? Color.red : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(Theme.cardStrong))
        }
        .buttonStyle(.plain)
    }
}

/// Small grey explanatory text under a group.
struct AccountNote: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
