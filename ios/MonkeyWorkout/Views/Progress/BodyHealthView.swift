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
    @FocusState private var focus: Metric?

    private enum Metric: Hashable { case height, weight, birthYear }

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
                if health.connected {
                    AccountCard(symbol: "heart.fill", title: "Apple Health", subtitle: "Connected · Health data stays on this iPhone",
                                gradient: nil, textColor: .pink) {
                        Button { Task { await health.refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17, weight: .heavy))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.pink.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Refresh Health data")
                    }
                    Toggle(isOn: Binding(get: { health.writeWorkouts }, set: { health.setWriteWorkouts($0) })) {
                        Text("Save workouts to Health").font(.body.weight(.semibold))
                    }
                    .tint(Theme.lime)
                    .card(padding: 16)
                } else {
                    LimeActionButton(title: "Connect Apple Health", symbol: "heart.text.square.fill", disabled: !health.available) {
                        Task { await health.connect() }
                    }
                }
                ErrorText(message: health.error)
                AccountNote(text: "Reads weight, height, age, sex, resting heart rate, HRV, VO₂max, sleep, heart rate during sessions and climbing workouts. Writes your sessions and, if you choose, weight and height. Health data stays on this iPhone.")

                section("Body")
                metricCard(.height, title: "Height", symbol: "ruler.fill", unit: "cm", gradient: WorkoutEngine.Category.strength.gradient,
                           text: $height, health: snap.heightCm.map { String(format: "%.0f", $0) })
                metricCard(.weight, title: "Weight", symbol: "scalemass.fill", unit: "kg", gradient: WorkoutEngine.Category.cardio.gradient,
                           text: $weight, health: snap.weightKg.map { String(format: "%.1f", $0) })
                metricCard(.birthYear, title: "Birth year", symbol: "birthday.cake.fill", unit: "", gradient: WorkoutEngine.Category.warmup.gradient,
                           text: $birthYear, health: snap.birthYear.map(String.init))
                if health.connected && (snap.heightCm == nil || snap.weightKg == nil) {
                    Toggle(isOn: $writeToHealth) {
                        Text("Also save height & weight to Health").font(.body.weight(.semibold))
                    }
                    .tint(Theme.lime)
                    .card(padding: 16)
                }
                AccountNote(text: "Used for calorie estimates and progress. Values from Apple Health are marked with a heart and used first; enter the rest here.")

                section("About you (optional)")
                Menu {
                    Picker("Gender", selection: $gender) {
                        Text("Not set").tag(BodyMetrics.Gender?.none)
                        ForEach(BodyMetrics.Gender.allCases) { Text($0.label).tag(BodyMetrics.Gender?.some($0)) }
                    }
                } label: {
                    AccountCard(symbol: "person.fill", title: "Gender", subtitle: "Only for you", gradient: AccountTint.profile) {
                        menuValue(gender?.label ?? "Not set")
                    }
                }
                if gender == .selfDescribe {
                    AccountField(label: "In your words") {
                        TextField("How do you describe your gender?", text: $genderText)
                            .textInputAutocapitalization(.never)
                    }
                }
                AccountNote(text: "Only for you — never used in calculations or shared.")

                section("For estimates (optional)")
                if let healthSex = snap.sex {
                    AccountCard(symbol: "figure.stand", title: "Sex", subtitle: "From Apple Health",
                                gradient: WorkoutEngine.Category.stretch.gradient) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill").font(.caption)
                            Text(healthSex.label).font(Theme.label(15))
                        }
                    }
                } else {
                    Menu {
                        Picker("Sex", selection: $sex) {
                            Text("Not set").tag(BodyMetrics.Sex?.none)
                            ForEach(BodyMetrics.Sex.allCases) { Text($0.label).tag(BodyMetrics.Sex?.some($0)) }
                        }
                    } label: {
                        AccountCard(symbol: "figure.stand", title: "Sex", subtitle: "Refines calories & heart rate",
                                    gradient: WorkoutEngine.Category.stretch.gradient) {
                            menuValue(sex?.label ?? "Not set")
                        }
                    }
                }
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

    /// Explore-style metric card: gradient, icon tile, big value on the right. Health values win and are
    /// read-only; otherwise the big number is the input and tapping anywhere on the card focuses it.
    private func metricCard(_ metric: Metric, title: String, symbol: String, unit: String, gradient: LinearGradient,
                            text: Binding<String>, health value: String?) -> some View {
        AccountCard(symbol: symbol, title: title, subtitle: value != nil ? "From Apple Health" : text.wrappedValue.isEmpty ? "Tap to enter" : "Tap to edit",
                    gradient: gradient) {
            if let value {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.caption)
                    AccountValue(value: value, unit: unit.isEmpty ? "born" : unit)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel((unit.isEmpty ? value : "\(value) \(unit)") + ", from Apple Health")
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    TextField(title, text: text, prompt: Text(unit.isEmpty ? "1990" : "–").foregroundStyle(.white.opacity(0.6)))
                        .keyboardType(unit.isEmpty ? .numberPad : .decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(Theme.display(24).monospacedDigit())
                        .focused($focus, equals: metric)
                        .frame(width: 110)
                    Text((unit.isEmpty ? "born" : unit).uppercased()).font(Theme.label(9)).tracking(1).opacity(0.8)
                }
            }
        }
        .onTapGesture { if value == nil { focus = metric } }
    }

    /// Current choice + up/down chevron on the right of a menu card.
    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text).font(Theme.label(15)).lineLimit(2).multilineTextAlignment(.trailing)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .heavy)).opacity(0.8)
        }
        .frame(maxWidth: 130, alignment: .trailing)
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
