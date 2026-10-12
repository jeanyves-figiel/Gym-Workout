import SwiftUI
import WorkoutEngine

// Week split, per-day focus and focus muscles on the Goal screen (#200).

extension Focus {
    /// Short name for week strips and day tiles.
    var dayLabel: String {
        switch self {
        case .fullLower: "Full · lower"
        case .fullUpper: "Full · upper"
        case .fullPower: "Full · power"
        case .upper: "Upper"
        case .lower: "Lower"
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .conditioning: "Cardio"
        case .chestTri: "Chest & tri"
        case .backBi: "Back & bi"
        case .shouldersArms: "Shoulders"
        case .chestBack: "Chest & back"
        case .posterior: "Glutes"
        }
    }

    var symbol: String {
        switch self {
        case .fullLower, .fullUpper: "figure.stand"
        case .fullPower: "bolt.fill"
        case .upper: "arrow.up"
        case .lower: "arrow.down"
        case .push: "arrow.up.forward"
        case .pull: "arrow.down.backward"
        case .legs, .posterior: "figure.walk"
        case .conditioning: "heart.fill"
        case .chestTri, .chestBack: "figure.strengthtraining.traditional"
        case .backBi: "figure.rower"
        case .shouldersArms: "dumbbell.fill"
        }
    }
}

extension SplitStyle {
    var symbol: String {
        switch self {
        case .auto: "sparkles"
        case .fullBody: "figure.stand"
        case .upperLower: "arrow.up.arrow.down"
        case .ppl: "arrow.triangle.2.circlepath"
        case .upperLowerFull: "square.stack.3d.up.fill"
        case .pplUpperLower: "rectangle.3.group.fill"
        case .bodyPart: "figure.strengthtraining.traditional"
        case .arnold: "trophy.fill"
        case .hybrid: "heart.fill"
        }
    }
}

/// Split pills, a tappable week strip and focus-muscle chips, drawn on the picked goal's gradient.
struct SplitFocusPanel: View {
    @Binding var profile: Profile
    @State private var editing: DayEdit?

    private struct DayEdit: Identifiable {
        let index: Int
        let weekday: Int?
        let focus: Focus
        var id: Int { index }
    }

    private var preview: [(weekday: Int?, focus: Focus)] { Generator.weekPreview(profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SPLIT").font(Theme.label(10)).tracking(1.6).opacity(0.9)
            FlowLayout(spacing: 6) {
                ForEach(SplitStyle.allCases) { s in
                    pill(s.title, symbol: s.symbol, selected: !profile.customSplit && profile.splitStyle == s) {
                        profile.applySplit(s)
                    }
                }
                if profile.customSplit {
                    pill("Custom", symbol: "hand.tap.fill", selected: true) {}
                }
            }
            Text(profile.customSplit ? "Your own days. Pick a split to reset." : profile.splitStyle.blurb)
                .font(.footnote.weight(.medium)).opacity(0.9)

            Text("YOUR WEEK · TAP A DAY TO CHANGE IT").font(Theme.label(10)).tracking(1.6).opacity(0.9).padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(Array(preview.enumerated()), id: \.offset) { i, day in
                    Button {
                        editing = DayEdit(index: i, weekday: day.weekday, focus: day.focus)
                    } label: {
                        VStack(spacing: 3) {
                            Text(day.weekday.map { WeekSchedule.shortName($0).uppercased() } ?? "DAY \(i + 1)")
                                .font(Theme.label(9)).tracking(1).opacity(0.85)
                            Text(day.focus.dayLabel)
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .padding(.horizontal, 2)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(day.focus.palette.gradient))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.weekday.map(WeekSchedule.name) ?? "Day \(i + 1)"): \(day.focus.label). Double-tap to change.")
                }
            }

            Text("FOCUS MUSCLES").font(Theme.label(10)).tracking(1.6).opacity(0.9).padding(.top, 4)
            FlowLayout(spacing: 6) {
                ForEach(MuscleGroup.allCases) { g in
                    let on = profile.focusGroups.contains(g)
                    pill(g.label, symbol: on ? "checkmark" : nil, selected: on, dark: true) { toggle(g) }
                }
            }
            Text(profile.focusGroups.isEmpty
                 ? "Optional. Pick any muscles you want to grow faster."
                 : "+1 set on every exercise for these muscles, trained first after the main lift.")
                .font(.footnote.weight(.medium)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(profile.goal.gradient))
        .animation(.spring(duration: 0.25), value: profile.splitDays)
        .animation(.spring(duration: 0.25), value: profile.split)
        .sheet(item: $editing) { e in
            DayFocusSheet(weekday: e.weekday, index: e.index, current: e.focus) { f in
                profile.setDay(e.index, to: f)
            }
        }
    }

    private func toggle(_ g: MuscleGroup) {
        var set = profile.focusGroups
        if set.contains(g) { set.remove(g) } else { set.insert(g) }
        let ordered = MuscleGroup.allCases.filter(set.contains)
        profile.focusMuscles = ordered.isEmpty ? nil : ordered
    }

    private func pill(_ title: String, symbol: String?, selected: Bool, dark: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .heavy)) }
                Text(title).font(.system(size: 13, weight: .heavy, design: .rounded)).lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? (dark ? Theme.lime : Theme.ink) : .white)
            .background(Capsule().fill(selected ? (dark ? Color.black : Color.white) : Color.black.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// What one day of the week trains: gradient tiles, tap to pick.
struct DayFocusSheet: View {
    let weekday: Int?
    let index: Int
    let current: Focus
    let onPick: (Focus) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What should this day train?").font(.subheadline).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Generator.dayFoci, id: \.self) { f in
                            Button {
                                onPick(f)
                                dismiss()
                            } label: {
                                tile(f)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(f == current ? .isSelected : [])
                        }
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("\(weekday.map(WeekSchedule.name) ?? "Day \(index + 1)") focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func tile(_ f: Focus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: f.symbol).font(.system(size: 18, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                Spacer()
                if f == current {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.ink, Theme.lime)
                }
            }
            Spacer(minLength: 0)
            Text(f.label).font(Theme.display(16)).lineLimit(2).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(f.palette.gradient))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white, lineWidth: f == current ? 3 : 0))
    }
}

#if DEBUG
extension Demo {
    /// Goal screen demo (#200): body-part split with a custom Saturday and two focus muscles.
    static func splitProfile(_ base: Profile?) -> Profile {
        var p = base ?? Profile()
        p.applyGoal(.build)
        p.sessionsPerWeek = 4
        p.applySplit(.bodyPart)
        p.setDay(3, to: .posterior)
        p.focusMuscles = [.back, .hips]
        return p
    }
}
#endif
