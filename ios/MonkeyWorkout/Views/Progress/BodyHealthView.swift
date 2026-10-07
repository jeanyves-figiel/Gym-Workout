import SwiftUI
import WorkoutEngine

/// Apple Health connection + body metrics. Health values win; manual entry fills the gaps.
struct BodyHealthView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var height = ""
    @State private var weight = ""
    @State private var birthYear = ""
    @State private var sex: BodyMetrics.Sex?
    @State private var gender: BodyMetrics.Gender?
    @State private var genderText = ""
    @State private var writeToHealth = true
    @State private var saved = false

    private var snap: HealthSnapshot { health.snapshot }

    var body: some View {
        Form {
            Section {
                if health.connected {
                    Label("Connected to Apple Health", systemImage: "heart.fill").foregroundStyle(.pink)
                    Toggle("Save workouts to Health", isOn: Binding(get: { health.writeWorkouts }, set: { health.setWriteWorkouts($0) }))
                    Button("Refresh Health data") { Task { await health.refresh() } }
                } else {
                    Button {
                        Task { await health.connect() }
                    } label: {
                        Label("Connect Apple Health", systemImage: "heart.text.square.fill")
                    }
                    .disabled(!health.available)
                }
                ErrorText(message: health.error)
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Reads weight, height, age, sex, resting heart rate, HRV, VO₂max, sleep, heart rate during sessions and climbing workouts. Writes your sessions and, if you choose, weight and height. Health data stays on this iPhone.")
            }

            Section {
                metricRow("Height", unit: "cm", text: $height, health: snap.heightCm.map { String(format: "%.0f", $0) })
                metricRow("Weight", unit: "kg", text: $weight, health: snap.weightKg.map { String(format: "%.1f", $0) })
                metricRow("Birth year", unit: "", text: $birthYear, health: snap.birthYear.map(String.init))
                if health.connected && (snap.heightCm == nil || snap.weightKg == nil) {
                    Toggle("Also save height & weight to Health", isOn: $writeToHealth)
                }
            } header: {
                Text("Body")
            } footer: {
                Text("Used for calorie estimates and progress. Values from Apple Health are shown in green and used first; enter the rest here.")
            }

            Section {
                Picker("Gender", selection: $gender) {
                    Text("Not set").tag(BodyMetrics.Gender?.none)
                    ForEach(BodyMetrics.Gender.allCases) { Text($0.label).tag(BodyMetrics.Gender?.some($0)) }
                }
                .pickerStyle(.navigationLink)
                if gender == .selfDescribe {
                    TextField("How do you describe your gender?", text: $genderText)
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text("About you (optional)")
            } footer: {
                Text("Only for you — never used in calculations or shared.")
            }

            Section {
                if let healthSex = snap.sex {
                    metricRow("Sex", unit: "", text: .constant(""), health: healthSex.label)
                } else {
                    Picker("Sex", selection: $sex) {
                        Text("Not set").tag(BodyMetrics.Sex?.none)
                        ForEach(BodyMetrics.Sex.allCases) { Text($0.label).tag(BodyMetrics.Sex?.some($0)) }
                    }
                    .pickerStyle(.navigationLink)
                }
            } header: {
                Text("For estimates (optional)")
            } footer: {
                Text("Physiological sex can slightly refine calorie and heart-rate estimates. Leave unset or choose “Prefer not to say” and the app uses neutral defaults.")
            }

            Section {
                Button {
                    save()
                } label: {
                    Text(saved ? "Saved" : "Save").bold().frame(maxWidth: .infinity)
                }
            }
        }
        .themedForm()
        .navigationTitle("Body & Health")
        .onAppear(perform: load)
        .task { await health.refresh() }
    }

    @ViewBuilder
    private func metricRow(_ title: String, unit: String, text: Binding<String>, health value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let value {
                Text("\(value) \(unit)").foregroundStyle(.green)
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
            } else {
                TextField(unit.isEmpty ? "e.g. 1990" : unit, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                if !unit.isEmpty { Text(unit).foregroundStyle(Theme.muted) }
            }
        }
    }

    private func load() {
        let b = model.body
        height = b.heightCm.map { String(format: "%.0f", $0) } ?? ""
        weight = b.weightKg.map { String(format: "%.1f", $0) } ?? ""
        birthYear = b.birthYear.map(String.init) ?? ""
        sex = b.sex
        gender = b.gender
        genderText = b.genderDescription ?? ""
    }

    private func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    private func save() {
        var b = BodyMetrics()
        if let h = number(height), (100...250).contains(h) { b.heightCm = h }
        if let w = number(weight), (30...300).contains(w) { b.weightKg = w }
        if let y = Int(birthYear), (1900...2020).contains(y) { b.birthYear = y }
        b.sex = sex
        b.gender = gender
        let described = genderText.trimmingCharacters(in: .whitespacesAndNewlines)
        b.genderDescription = gender == .selfDescribe && !described.isEmpty ? String(described.prefix(60)) : nil
        model.saveBody(b)
        if health.connected && writeToHealth {
            var toHealth = BodyMetrics()
            if snap.heightCm == nil { toHealth.heightCm = b.heightCm }
            if snap.weightKg == nil { toHealth.weightKg = b.weightKg }
            Task { await health.saveBody(toHealth) }
        }
        saved = true
    }
}

/// Recovery card on the Train tab (only when Health has data).
struct ReadinessCard: View {
    let snapshot: HealthSnapshot

    var body: some View {
        if let assessed = Readiness.assess(snapshot) {
            content(assessed.0, assessed.1)
        }
    }

    private func content(_ r: Readiness, _ reasons: [String]) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Readiness").eyebrow()
                    Spacer()
                    Image(systemName: "heart.text.square.fill").foregroundStyle(.pink)
                }
                Text(r.title).font(Theme.display(26)).foregroundStyle(color(r))
                Text(reasons.isEmpty ? r.advice : reasons.joined(separator: " · ") + ". " + r.advice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    if let s = snapshot.sleepHours { metric(String(format: "%.1f h", s), "Sleep") }
                    if let h = snapshot.hrv { metric("\(Int(h)) ms", "HRV") }
                    if let r = snapshot.restingHR { metric("\(Int(r))", "Rest HR") }
                    if let v = snapshot.vo2Max { metric(String(format: "%.0f", v), "VO₂max") }
                }
            }
            .card()
    }

    private func color(_ r: Readiness) -> Color {
        switch r {
        case .ready: Theme.lime
        case .normal: .yellow
        case .easy: .orange
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.display(18)).monospacedDigit()
            Text(label).eyebrow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Prompt shown until weight/height are known (from Health or entered).
struct BodyPromptCard: View {
    var body: some View {
        NavigationLink {
            BodyHealthView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "heart.text.square.fill").font(.system(size: 30)).foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Apple Health").font(.system(.headline, design: .rounded).weight(.heavy))
                    Text("Or enter height & weight for calories, readiness and progress.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

/// Climbing count from Health vs profile.
struct ClimbingSyncHint: View {
    let healthPerWeek: Double
    let profileDays: Int
    let onApply: (Int) -> Void

    var body: some View {
        let suggested = Int(healthPerWeek.rounded())
        if suggested != profileDays {
            HStack(spacing: 12) {
                Image(systemName: "figure.climbing").font(.title2).foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health shows ~\(String(format: "%.1f", healthPerWeek)) climbing sessions / week").font(.footnote.weight(.bold))
                    Text("Your plan assumes \(profileDays).").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Use \(suggested)") { onApply(suggested) }
                    .font(Theme.label(13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.lime))
                    .foregroundStyle(Theme.ink)
            }
            .card(padding: 14)
        }
    }
}
