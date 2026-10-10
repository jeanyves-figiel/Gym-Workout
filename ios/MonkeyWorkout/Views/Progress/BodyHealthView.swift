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
    @State private var loaded = false

    private var snap: HealthSnapshot { health.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AccountHeader(symbol: "heart.text.square.fill", title: "Body & Health",
                              subtitle: health.connected ? "Connected to Apple Health" : "Connect Apple Health or enter your numbers.",
                              gradient: AccountTint.body) {
                    if let kg = snap.weightKg ?? number(weight) {
                        AccountValue(value: Format.kg((kg * 10).rounded() / 10), unit: "kg")
                    }
                }

                section("Apple Health")
                VStack(alignment: .leading, spacing: 12) {
                    if health.connected {
                        Label("Connected to Apple Health", systemImage: "heart.fill").font(.subheadline.weight(.bold)).foregroundStyle(.pink)
                        Toggle("Save workouts to Health", isOn: Binding(get: { health.writeWorkouts }, set: { health.setWriteWorkouts($0) }))
                            .tint(Theme.lime)
                        Button { Task { await health.refresh() } } label: {
                            Label("Refresh Health data", systemImage: "arrow.clockwise").font(Theme.label(14))
                        }
                        .foregroundStyle(Theme.lime)
                    } else {
                        LimeActionButton(title: "Connect Apple Health", symbol: "heart.text.square.fill", disabled: !health.available) {
                            Task { await health.connect() }
                        }
                    }
                    ErrorText(message: health.error)
                }
                .card()
                AccountNote(text: "Reads weight, height, age, sex, resting heart rate, HRV, VO₂max, sleep, heart rate during sessions and climbing workouts. Writes your sessions and, if you choose, weight and height. Health data stays on this iPhone.")

                section("Body")
                VStack(spacing: 0) {
                    metricRow("Height", unit: "cm", text: $height, health: snap.heightCm.map { String(format: "%.0f", $0) })
                    Divider().overlay(Theme.stroke)
                    metricRow("Weight", unit: "kg", text: $weight, health: snap.weightKg.map { String(format: "%.1f", $0) })
                    Divider().overlay(Theme.stroke)
                    metricRow("Birth year", unit: "", text: $birthYear, health: snap.birthYear.map(String.init))
                    if health.connected && (snap.heightCm == nil || snap.weightKg == nil) {
                        Divider().overlay(Theme.stroke)
                        Toggle("Also save height & weight to Health", isOn: $writeToHealth).tint(Theme.lime).padding(.vertical, 12)
                    }
                }
                .card(padding: 14)
                AccountNote(text: "Used for calorie estimates and progress. Values from Apple Health are shown in green and used first; enter the rest here.")

                section("About you (optional)")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Gender").font(.body.weight(.semibold))
                        Spacer()
                        Picker("Gender", selection: $gender) {
                            Text("Not set").tag(BodyMetrics.Gender?.none)
                            ForEach(BodyMetrics.Gender.allCases) { Text($0.label).tag(BodyMetrics.Gender?.some($0)) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.lime)
                    }
                    if gender == .selfDescribe {
                        TextField("How do you describe your gender?", text: $genderText)
                            .textInputAutocapitalization(.never)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                    }
                }
                .card(padding: 14)
                AccountNote(text: "Only for you — never used in calculations or shared.")

                section("For estimates (optional)")
                HStack {
                    Text("Sex").font(.body.weight(.semibold))
                    Spacer()
                    if let healthSex = snap.sex {
                        Text(healthSex.label).foregroundStyle(.green)
                        Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
                    } else {
                        Picker("Sex", selection: $sex) {
                            Text("Not set").tag(BodyMetrics.Sex?.none)
                            ForEach(BodyMetrics.Sex.allCases) { Text($0.label).tag(BodyMetrics.Sex?.some($0)) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.lime)
                    }
                }
                .card(padding: 14)
                AccountNote(text: "Physiological sex can slightly refine calorie and heart-rate estimates. Leave unset or choose “Prefer not to say” and the app uses neutral defaults.")

                LimeActionButton(title: "Save") { save() }
                    .padding(.top, 14)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .themedForm()
        .navigationTitle("Body & Health")
        .toolbarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .task { await health.refresh() }
    }

    private func section(_ title: String) -> some View {
        Text(title).eyebrow().padding(.leading, 4).padding(.top, 12)
    }

    @ViewBuilder
    private func metricRow(_ title: String, unit: String, text: Binding<String>, health value: String?) -> some View {
        HStack {
            Text(title).font(.body.weight(.semibold))
            Spacer()
            if let value {
                Text("\(value) \(unit)").font(Theme.label(17)).foregroundStyle(.green)
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
            } else {
                TextField(unit.isEmpty ? "e.g. 1990" : unit, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.label(17))
                    .frame(width: 100)
                if !unit.isEmpty { Text(unit).foregroundStyle(Theme.muted) }
            }
        }
        .padding(.vertical, 12)
    }

    /// Once only: onAppear also fires when returning from a picker's pushed list, which would reset the selection.
    private func load() {
        guard !loaded else { return }
        loaded = true
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
        dismiss()
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
