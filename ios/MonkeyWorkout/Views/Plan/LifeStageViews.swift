import SwiftUI
import WorkoutEngine

// Life-stage programmes (#625, designs A + B + C from `apple-tech-radar/batch4.html`).

/// On a life-stage programme's page: A the check-in (doctor's OK needed to start), B what the safety guard swaps and
/// why, C pace by feel.
struct LifeStageSetup: View {
    let stage: LifeStage
    let running: Bool
    @Environment(AppModel.self) private var model
    @State private var due = Calendar.current.date(byAdding: .weekOfYear, value: 20, to: .now)!
    @State private var birth = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: .now)!
    @State private var weeksOff = 8
    @State private var doctorOK = false

    private var check: LifeStageCheckIn {
        LifeStageCheckIn(stage: stage, dueDate: stage == .pregnancy ? due : nil, birthDate: stage == .postpartum ? birth : nil,
                         weeksOff: stage == .backToTraining ? weeksOff : nil, doctorOK: doctorOK, at: .distantPast)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            checkIn
            guardCard
            byFeel
        }
        .onAppear {
            guard let c = model.lifeStageCheckIn, c.stage == stage else { return }
            due = c.dueDate ?? due
            birth = c.birthDate ?? birth
            weeksOff = c.weeksOff ?? weeksOff
            doctorOK = c.doctorOK
        }
        .onChange(of: check) { _, c in
            // Kept as they change: Start reads the doctor's OK, the guard reads the dates.
            var c = c
            c.at = model.lifeStageCheckIn?.at ?? .now
            model.setLifeStageCheckIn(c)
        }
    }

    private var checkIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check-in").font(Theme.display(20))
            switch stage {
            case .pregnancy:
                DatePicker("Due date", selection: $due, in: Date.now..., displayedComponents: .date)
                Text("\(LifeStage.ordinal(check.trimester(now: .now))) trimester").font(Theme.label(14)).opacity(0.9)
            case .postpartum:
                DatePicker("Baby's birthday", selection: $birth, in: ...Date.now, displayedComponents: .date)
                Text("\(check.weeksSinceBirth(now: .now)) weeks since birth").font(Theme.label(14)).opacity(0.9)
            case .backToTraining:
                Stepper("Weeks without training: \(weeksOff)", value: $weeksOff, in: 1...104)
            case .fiftyPlus:
                Text("Tell us about any joint you protect in your profile; the plan keeps power controlled.").font(.footnote).opacity(0.9)
            }
            Toggle(isOn: $doctorOK) {
                Text(stage == .pregnancy || stage == .postpartum ? "My doctor or midwife said exercise is OK" : "My doctor said exercise is OK")
                    .font(Theme.label(14))
            }
            .tint(Theme.lime)
            if !doctorOK && !running {
                Label("Get a doctor's OK first. Start unlocks with it.", systemImage: "stethoscope").font(.caption.weight(.semibold))
            }
        }
        .font(Theme.label(14))
        .foregroundStyle(.white)
        .tint(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFF4D8D), Color(hex: 0x8A2BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var guardCard: some View {
        let rules = stage.rules(check, now: .now)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Swapped for you", systemImage: "shield.lefthalf.filled").font(Theme.display(18))
            if rules.isEmpty {
                Text("Nothing to swap now: your plan's moves fit.").font(.footnote).opacity(0.9)
            }
            ForEach(Array(rules.prefix(6).enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Exercise.find(r.from)?.name ?? r.from) → \(Exercise.find(r.to)?.name ?? r.to)").font(Theme.label(14))
                    Text(r.why).font(.caption).opacity(0.85)
                }
            }
            if rules.count > 6 { Text("+ \(rules.count - 6) more, shown in each workout").font(.caption).opacity(0.85) }
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.lime))
    }

    private var byFeel: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 20, weight: .bold))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Pace by feel").font(Theme.display(17))
                Text("Can you talk? Keep it there. No PR attempts in this programme; your streak counts showing up.")
                    .font(.caption.weight(.semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(WorkoutEngine.Category.cardio.gradient))
    }
}
