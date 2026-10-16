import SwiftUI
import WorkoutEngine

// Usual workout time (#377, design C from `workout-time/proposals.png`): its own card on the Training profile hub and an
// editor with a time slider. Mornings get one more minute of warm-up cardio; the time can drive reminders later.

/// Morning (before 11:00), midday (11:00–15:00) or evening, from the profile's usual workout time.
enum WorkoutTimeOfDay {
    case unset, morning, midday, evening

    init(_ minutes: Int?) {
        guard let m = minutes else { self = .unset; return }
        self = m < 11 * 60 ? .morning : m < 15 * 60 ? .midday : .evening
    }

    var symbol: String {
        switch self {
        case .unset: "clock.fill"
        case .morning: "sunrise.fill"
        case .midday: "sun.max.fill"
        case .evening: "moon.stars.fill"
        }
    }

    var label: String {
        switch self {
        case .unset: "Not set"
        case .morning: "Mornings"
        case .midday: "Midday"
        case .evening: "Evenings"
        }
    }

    var summary: String { self == .morning ? "Mornings · +1 min warm-up" : self == .unset ? "Not set · any time" : label }

    var gradient: LinearGradient {
        switch self {
        case .unset, .morning: WorkoutEngine.Category.warmup.gradient
        case .midday: WorkoutEngine.Category.cardio.gradient
        case .evening: WorkoutEngine.Category.mobility.gradient
        }
    }

    /// "07:00" in the member's clock format.
    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Editor: the time large, a slider from 05:00 to 22:00 in 15-minute steps, and what the time changes.
struct WorkoutTimeSection: View {
    @Binding var profile: Profile

    static let range = 5 * 60...22 * 60
    static let step = 15
    /// First value when the member sets a time.
    static let suggested = 7 * 60

    private var minutes: Binding<Double> {
        Binding(get: { Double(profile.workoutTime ?? Self.suggested) },
                set: { profile.workoutTime = Int($0 / Double(Self.step)) * Self.step })
    }

    var body: some View {
        let part = WorkoutTimeOfDay(profile.workoutTime)
        VStack(alignment: .leading, spacing: 12) {
            Text("When do you usually train? Morning workouts start with one more minute of easy cardio: muscles are cooler early in the day.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(part.label.uppercased(), systemImage: part.symbol).font(Theme.label(12)).tracking(1.2)
                    Spacer()
                    if profile.workoutTime != nil {
                        Text("Usually").font(Theme.label(11)).opacity(0.85)
                    }
                }
                Text(profile.workoutTime.map(WorkoutTimeOfDay.clock) ?? "Any time")
                    .font(Theme.display(44))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if profile.workoutTime != nil {
                    Slider(value: minutes, in: Double(Self.range.lowerBound)...Double(Self.range.upperBound), step: Double(Self.step))
                        .tint(.white)
                        .accessibilityLabel("Usual workout time")
                        .accessibilityValue(profile.workoutTime.map(WorkoutTimeOfDay.clock) ?? "")
                    HStack {
                        ForEach([5, 11, 15, 22], id: \.self) { h in
                            Text(WorkoutTimeOfDay.clock(h * 60)).font(Theme.label(10)).opacity(0.8)
                            if h != 22 { Spacer() }
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(part.gradient))
            .animation(.spring(duration: 0.3), value: part)

            if profile.workoutTime == nil {
                Button { profile.workoutTime = Self.suggested } label: {
                    Label("Set a time", systemImage: "clock.badge.checkmark")
                        .font(Theme.label(15))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            } else {
                Button { profile.workoutTime = nil } label: {
                    Label("It varies · no usual time", systemImage: "xmark.circle")
                        .font(Theme.label(13))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
            Text("Before 11:00 counts as morning. Plans are the same at midday and in the evening.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }
}
