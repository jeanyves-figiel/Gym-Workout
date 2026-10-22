import SwiftUI
import WorkoutEngine

// Sport season blocks (#620, designs B + C from `apple-tech-radar/batch4.html`).

/// B: the Coach saw a sport played 3+ times in two weeks and offers its add-on twice a week.
struct SportAddOnSuggestCard: View {
    let sport: SeasonSport
    let count: Int
    var onNo: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(sport.emoji).font(.system(size: 22))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Coach · you played \(sport.label.lowercased()) \(count)×").font(Theme.label(10)).tracking(1.2)
                        .textCase(.uppercase).opacity(0.85)
                    Text("Add \(SportAddOn.title(sport).lowercased())?").font(.system(size: 16, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text(SportAddOn.summary(sport)).font(Theme.label(11)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("No", action: onNo)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.22)))
                Button("Add 2× week") {
                    Haptics.success()
                    withAnimation(.snappy) { model.setSportAddOn(SportAddOnPref(sport: sport, perWeek: 2)) }
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.white))
                .foregroundStyle(Theme.ink)
                .accessibilityHint("Adds a \(SportAddOn.minutes)-minute \(sport.label.lowercased()) block to two gym sessions a week")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(WorkoutEngine.Category.power.gradient))
    }
}

/// C: the add-on running, under "Get ready for…": sessions a week and Remove; else a tile per sport to add it.
struct SportAddOnRow: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        if let pref = model.sportAddOn {
            HStack(spacing: 10) {
                Text(pref.sport.emoji).font(.system(size: 22))
                VStack(alignment: .leading, spacing: 1) {
                    Text(SportAddOn.title(pref.sport)).font(Theme.display(16)).lineLimit(1)
                    Text("\(SportAddOn.minutes)′ · \(SportAddOn.summary(pref.sport))").font(Theme.label(11)).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 0)
                Stepper("\(pref.perWeek)× week", value: Binding(get: { pref.perWeek },
                                                               set: { model.setSportAddOn(SportAddOnPref(sport: pref.sport, perWeek: $0)) }),
                        in: 1...3)
                    .labelsHidden()
                Text("\(pref.perWeek)×").font(Theme.display(18)).monospacedDigit()
                Button { withAnimation(.snappy) { model.setSportAddOn(nil) } } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.heavy)).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(SportAddOn.title(pref.sport))")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.18)))
        } else {
            Button { picking = true } label: {
                Label("Add a 15′ sport add-on to your sessions", systemImage: "plus.square.fill")
                    .font(Theme.label(13)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Sport add-on", isPresented: $picking, titleVisibility: .visible) {
                ForEach(SeasonSport.allCases) { s in
                    Button("\(s.emoji) \(s.label) · \(SportAddOn.summary(s))") { model.setSportAddOn(SportAddOnPref(sport: s)) }
                }
            } message: {
                Text("15 minutes at the end of two gym sessions a week. Your plan stays as it is.")
            }
        }
    }
}
