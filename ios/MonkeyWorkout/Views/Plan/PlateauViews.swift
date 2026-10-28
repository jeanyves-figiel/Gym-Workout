import SwiftUI
import WorkoutEngine

// Plateau explainer (#875, design A + C from `ai-epic/c2.png`): a stalled lift, why (on-device Coach) and one set
// style to apply. Hidden without Apple Intelligence.

private let dayMonth: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("d MMM")
    return f
}()

/// "3rd week".
private func ordinalWeek(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .ordinal
    return (f.string(from: NSNumber(value: n)) ?? "\(n)") + " week"
}

/// Why the lift is stuck, in Coach's words, and the set style to switch to.
struct PlateauExplainer: View {
    let lift: StalledLift
    @Environment(AppModel.self) private var model
    @State private var why: String?
    @State private var loading = true
    @State private var applied = false

    private var name: String { Exercise.get(lift.exerciseId).name }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(Theme.lime).accessibilityHidden(true)
                if loading && why == nil {
                    ProgressView().tint(Theme.lime)
                } else {
                    Text(why ?? "Likely: " + lift.causes.map(\.short).joined(separator: ", ") + ".")
                        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            if let fix = lift.fix {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch to \(fix.label.lowercased())").font(.subheadline.weight(.heavy))
                        Text(fix.blurb).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Button {
                        withAnimation { model.setSetStyle(fix, for: lift.exerciseId); applied = true }
                    } label: {
                        Text(applied ? "Applied" : "Apply").font(Theme.label(12)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .disabled(applied)
                    .accessibilityHint("Your next \(name) sets use \(fix.label.lowercased())")
                }
                .card()
            }
        }
        .task(id: lift.exerciseId) {
            why = await OnDeviceCoach.plateau(lift, lift: name, fix: lift.fix.map { "switch to \($0.label.lowercased()): \($0.blurb)" })
            loading = false
        }
    }
}

/// Exercise page (A): "Stuck 3 weeks at 85 kg", tap WHY? for the cause and the fix.
struct PlateauCard: View {
    let exercise: Exercise
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        if let lift = model.stalledLift(exercise.id) {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.snappy) { open.toggle() } } label: {
                    SmartRow(symbol: "chart.line.flattrend.xyaxis", title: "Stuck \(lift.weeks) weeks at \(Format.kg(lift.kg.rounded())) kg",
                             detail: "est. 1RM flat since \(dayMonth.string(from: lift.since))", colors: SmartColors.warmup) {
                        Text(open ? "HIDE" : "WHY?").font(Theme.label(13))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(open ? "Hides why" : "Coach explains why and suggests a fix")
                if open { PlateauExplainer(lift: lift).transition(.opacity) }
            }
        }
    }
}

/// Finish screen (C): one line when a lift of this workout is stalled; FIX opens the cause and the fix.
struct PlateauNudge: View {
    let record: WorkoutRecord
    @Environment(AppModel.self) private var model
    @State private var lift: StalledLift?
    @State private var open = false

    var body: some View {
        Group {
            if let lift {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coach noticed").eyebrow()
                    Button { open = true } label: {
                        SmartRow(symbol: "pause.fill",
                                 title: "\(Exercise.get(lift.exerciseId).name) stuck at \(Format.kg(lift.kg.rounded())) kg, \(ordinalWeek(lift.weeks))",
                                 detail: "likely: " + lift.causes.prefix(2).map(\.short).joined(separator: ", "),
                                 colors: SmartColors.warmup, compact: true) {
                            Text("FIX").font(Theme.label(13))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Coach explains why and suggests a fix")
                }
                .sheet(isPresented: $open) {
                    NavigationStack {
                        ScrollView { PlateauExplainer(lift: lift).padding(20) }
                            .background(Theme.bg.ignoresSafeArea())
                            .navigationTitle(Exercise.get(lift.exerciseId).name)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { CloseToolbarItem { open = false } }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
        }
        .task(id: record.id) { lift = model.stalledLift(in: record) }
    }
}
