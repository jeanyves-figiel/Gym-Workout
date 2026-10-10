import SwiftUI
import WorkoutEngine

struct ProfileFormView: View {
    let onSave: (Profile) -> Void
    @State private var p: Profile
    @State private var showEquipment = false

    init(initial: Profile?, onSave: @escaping (Profile) -> Void) {
        self.onSave = onSave
        _p = State(initialValue: initial ?? Profile())
    }

    private var minutes: Int { Generator.sessionMinutes(p) }

    /// Picking climbing weekdays keeps "Climbing days / week" in sync with them.
    private var climbingDays: Binding<[Int]> {
        Binding(
            get: { p.climbingDays },
            set: { days in
                p.climbingWeekdays = days.isEmpty ? nil : days
                if days.isEmpty {
                    p.climbingDaysPerWeek = min(p.climbingDaysPerWeek, 4)
                } else {
                    p.syncClimbingDays()
                }
            })
    }

    private var gymDays: Binding<[Int]> {
        Binding(get: { p.gymDays }, set: { days in p.gymWeekdays = days.isEmpty ? nil : days })
    }

    private var scheduleHint: String {
        var lines: [String] = []
        if !p.climbingDays.isEmpty {
            lines.append("Sessions are placed around your climbing days: no heavy pulling, grip work or jumps the day before you climb; push and leg days sit next to climbing days.")
        }
        let gym = p.gymDays.count
        if gym > 0 && gym < p.sessionsPerWeek {
            lines.append("\(gym) gym day\(gym == 1 ? "" : "s") picked for \(p.sessionsPerWeek) sessions — the rest go on the best free days.")
        }
        if lines.isEmpty {
            lines.append("Optional: pick the days you climb (and go to the gym) to get each session on a weekday.")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section("Goal") {
                ForEach(Goal.allCases) { g in
                    Button {
                        p.goal = g
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.config.label).bold().foregroundStyle(.primary)
                                Text(g.config.blurb).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if p.goal == g { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                        }
                    }
                }
            }

            Section {
                Picker("Gym sessions / week", selection: $p.sessionsPerWeek) {
                    ForEach(2...6, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Experience", selection: $p.experience) {
                    ForEach(Experience.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                if p.climbingDays.isEmpty {
                    Picker("Climbing days / week", selection: $p.climbingDaysPerWeek) {
                        ForEach(0...4, id: \.self) { Text("\($0)").tag($0) }
                    }
                } else {
                    LabeledContent("Climbing days / week", value: "\(p.climbingDays.count)")
                }
                Picker("Max session length", selection: $p.maxSessionMinutes) {
                    Text("Auto").tag(Int?.none)
                    ForEach([45, 60, 75, 90], id: \.self) { Text("\($0) min").tag(Int?.some($0)) }
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text("≈ **\(minutes) min** × \(p.sessionsPerWeek) = \(String(format: "%.1f", Double(minutes * p.sessionsPerWeek) / 60)) h / week")
            }

            Section {
                WeekdayPicker(title: "I climb on", days: climbingDays)
                WeekdayPicker(title: "Gym days (optional)", days: gymDays)
            } header: {
                Text("Weekly schedule")
            } footer: {
                Text(scheduleHint)
            }

            Section {
                LabeledContent(Gym.puls5.name, value: "\(p.equipment.count) items")
                DisclosureGroup("Equipment", isExpanded: $showEquipment) {
                    ForEach(Equipment.allCases) { e in
                        Toggle(e.label, isOn: Binding(
                            get: { p.equipment.contains(e) },
                            set: { on in
                                if on { p.equipment.append(e) } else { p.equipment.removeAll { $0 == e } }
                            }))
                    }
                }
            } header: {
                Text("Gym")
            } footer: {
                Text(Gym.puls5.note)
            }

            Section {
                Button {
                    onSave(p)
                } label: {
                    Text("Generate plan").bold().frame(maxWidth: .infinity)
                }
            }
        }
        .themedForm()
    }
}

/// Seven Monday-first day toggles in one row.
private struct WeekdayPicker: View {
    let title: String
    @Binding var days: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            HStack(spacing: 6) {
                ForEach(WeekSchedule.weekdays, id: \.self) { d in
                    let on = days.contains(d)
                    Button {
                        if on { days.removeAll { $0 == d } } else { days = (days + [d]).sorted() }
                    } label: {
                        Text(WeekSchedule.initial(d))
                            .font(Theme.label(14))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Circle().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.10))))
                            .foregroundStyle(on ? Theme.ink : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(WeekSchedule.name(d))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}
