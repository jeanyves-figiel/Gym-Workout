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
                Picker("Climbing days / week", selection: $p.climbingDaysPerWeek) {
                    ForEach(0...4, id: \.self) { Text("\($0)").tag($0) }
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
    }
}
