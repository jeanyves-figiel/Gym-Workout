import SwiftUI
import WorkoutEngine

/// Training style (#78) in the training profile: rest between sets and grouping, as Explore-style cards.
/// The goal's recommendation carries a REC badge; picking it stores nil so the style keeps following the goal.
struct TrainingStyleSection: View {
    @Binding var profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rest between sets").eyebrow().padding(.top, 14)
            Text("Long rests build mass and strength; short rests keep you lean. REC = best for your goal.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            ForEach(RestStyle.allCases) { r in
                StyleCard(
                    title: r.label, subtitle: r.blurb, symbol: r.symbol, big: r.range,
                    gradient: r.gradient, selected: profile.rest == r, recommended: profile.goal.defaultRest == r
                ) { profile.restStyle = r == profile.goal.defaultRest ? nil : r }
            }
            Text("Main lifts always keep at least 90 s; prehab and core stay short.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            Text("Group exercises").eyebrow().padding(.top, 14)
            Text("Same muscle group back to back, rest after the round. Saves time, keeps the heart rate up.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            ForEach(Grouping.allCases) { g in
                StyleCard(
                    title: g.label, subtitle: g.blurb, symbol: g.symbol, big: g.size,
                    gradient: g.gradient, selected: profile.group == g, recommended: profile.goal.defaultGrouping == g
                ) { profile.grouping = g == profile.goal.defaultGrouping ? nil : g }
            }
        }
        .animation(.spring(duration: 0.3), value: profile.rest)
        .animation(.spring(duration: 0.3), value: profile.group)
    }
}

extension RestStyle {
    var symbol: String {
        switch self {
        case .long: "hourglass"
        case .standard: "timer"
        case .short: "bolt.fill"
        }
    }

    var gradient: LinearGradient {
        let c: WorkoutEngine.Category = switch self {
        case .long: .strength
        case .standard: .cardio
        case .short: .power
        }
        return c.gradient
    }
}

extension Grouping {
    var symbol: String {
        switch self {
        case .straight: "list.bullet"
        case .supersets: "arrow.left.arrow.right"
        case .circuits: "arrow.triangle.2.circlepath"
        }
    }

    var gradient: LinearGradient {
        let c: WorkoutEngine.Category = switch self {
        case .straight: .warmup
        case .supersets: .mobility
        case .circuits: .stretch
        }
        return c.gradient
    }
}

/// One vivid option card: icon tile, heavy title, big number on the right, REC badge for the goal's pick.
private struct StyleCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let big: (value: String, unit: String)
    let gradient: LinearGradient
    let selected: Bool
    let recommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.ink, Theme.lime)
                                .offset(x: 7, y: -7)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(subtitle).font(.footnote.weight(.semibold)).opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(big.value).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(big.unit).font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(gradient))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white, lineWidth: selected ? 3 : 0))
            .overlay(alignment: .topLeading) {
                if recommended {
                    Text("REC")
                        .font(Theme.label(9))
                        .tracking(1)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.lime))
                        .offset(x: 62, y: -8)
                }
            }
            .opacity(selected ? 1 : 0.55)
            .saturation(selected ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)\(recommended ? ". Recommended for your goal" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
