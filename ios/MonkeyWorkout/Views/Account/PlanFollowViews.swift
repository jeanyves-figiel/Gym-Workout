import SwiftUI
import WorkoutEngine

// MARK: - Part of a plan (#1052 D, `usage-levels/d.png`)

extension PlanScope {
    var category: WorkoutEngine.Category {
        switch self {
        case .whole: .cardio
        case .someDays: .warmup
        case .oneAtATime: .mobility
        case .ownWorkouts: .power
        }
    }
}

/// What the member follows: scope cards, the days for Some days and the workout cut. Used at sign up, in
/// Settings → My app and on My plan.
struct PlanFollowEditor: View {
    @Binding var follow: PlanFollow
    /// Plan weekdays to pick from with Some days; empty = Monday to Sunday.
    let weekdays: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(PlanScope.allCases) { scope in
                Button { withAnimation(.snappy) { pick(scope) } } label: { card(scope) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(follow.scope == scope ? .isSelected : [])
                    .accessibilityIdentifier("follow.\(scope.rawValue)")
                if scope == .someDays, follow.scope == .someDays { days }
            }
            Text("Each workout").eyebrow().padding(.leading, 4).padding(.top, 6)
            Picker("Each workout", selection: Binding(get: { follow.cut }, set: { c in follow.cut = c })) {
                ForEach(WorkoutCut.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("follow.cut")
            Text(cutLine).font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    private var cutLine: String {
        switch follow.cut {
        case .full: "Warm-up, lifts, extras and cool-down, as planned."
        case .lifts: "Only the lifting blocks: no warm-up, cardio or cool-down. Warm up on your own."
        case .quick: "Each workout fitted to \(WorkoutCut.quickMinutes) minutes, main lift kept."
        }
    }

    private func pick(_ scope: PlanScope) {
        follow.scope = scope
        if scope == .someDays, follow.days.isEmpty { follow.days = Array(dayList.prefix(2)) }
    }

    private var dayList: [Int] { weekdays.isEmpty ? Array(1...7) : weekdays }

    private var days: some View {
        HStack(spacing: 6) {
            ForEach(dayList, id: \.self) { d in
                let on = follow.days.contains(d)
                Button {
                    var set = Set(follow.days)
                    if on { set.remove(d) } else { set.insert(d) }
                    follow.days = set.sorted()
                } label: {
                    Text(WeekSchedule.shortName(d))
                        .font(Theme.label(13))
                        .foregroundStyle(on ? Theme.ink : .white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.1))))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WeekSchedule.name(d))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func card(_ scope: PlanScope) -> some View {
        HStack(spacing: 12) {
            Image(systemName: scope.symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(scope.title).font(Theme.display(17))
                Text(scope.detail).font(.footnote.weight(.semibold)).opacity(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .foregroundStyle(scope.category.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(scope.category.gradient))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.white, lineWidth: follow.scope == scope ? 3 : 0))
        .contentShape(Rectangle())
    }
}

/// Settings → My app → Your plan, and My plan: auto-saves each change.
struct PlanFollowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AccountHeader(symbol: "pin.fill", title: "What you follow",
                              subtitle: "Follow all of your plan or part of it. Your plan stays as it is underneath.",
                              gradient: SettingsChapter.training.gradient)
                PlanFollowEditor(follow: Binding(get: { model.planFollow }, set: { model.setPlanFollow($0) }),
                                 weekdays: model.planWeekdays)
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("What you follow")
        .navigationBarTitleDisplayMode(.inline)
    }
}
