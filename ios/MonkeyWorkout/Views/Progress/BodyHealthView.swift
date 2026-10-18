import SwiftUI
import WorkoutEngine

/// Apple Health connection + body metrics. Health values win; manual entry fills the gaps.
struct BodyHealthView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    /// Values brought back by Undo (#285).
    var restoring: Draft?

    /// What's entered, kept for Undo (#285).
    struct Draft: Equatable {
        var height: String
        var weight: String
        var birthYear: String
        var sex: BodyMetrics.Sex?
        var gender: BodyMetrics.Gender?
        var genderText: String
        var figure: BodyFigure?
        var writeToHealth: Bool
        var pronouns: Pronouns? = nil
        var pronounsCustom = ""
        var coachCall: CoachCall? = nil
        var showPronouns = false
    }

    @State private var height = ""
    @State private var weight = ""
    @State private var birthYear = ""
    @State private var sex: BodyMetrics.Sex?
    @State private var gender: BodyMetrics.Gender?
    @State private var genderText = ""
    /// How we talk to you (#415).
    @State private var pronouns: Pronouns?
    @State private var pronounsCustom = ""
    @State private var coachCall: CoachCall?
    @State private var showPronouns = false
    /// Picked body figure (#110); nil = suggested from sex until the user picks.
    @State private var figure: BodyFigure?
    @State private var writeToHealth = true
    @State private var loaded = false
    @State private var showAccess = false
    @State private var start: Draft?
    @State private var closeGuard = CloseGuard()
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
                    AccountCard(symbol: "heart.fill", title: "Apple Health", subtitle: "Connected · Only session summaries are synced",
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
                    Button { showAccess = true } label: {
                        AccountCard(symbol: "key.fill", title: "Manage Health access",
                                    subtitle: "Turn data back on you declined", gradient: HealthAccessSheet.gradient) {
                            AccountChevron()
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    LimeActionButton(title: "Connect Apple Health", symbol: "heart.text.square.fill", disabled: !health.available) {
                        Task { await health.connect() }
                    }
                }
                ErrorText(message: health.error)
                AccountNote(text: "Reads weight, height, body fat, lean mass, waist, age, sex, resting heart rate, HRV, VO₂max, sleep, heart rate during sessions and climbing workouts. Writes your sessions and, if you choose, weight, height, body fat, lean mass and waist. Health data you allow stays on this iPhone, except each session's summary (duration, calories, average and max heart rate) saved with your history.")

                section("Body figure")
                BodyFigurePicker(selection: Binding(
                    get: { figure ?? BodyMetrics.suggestedFigure(sex: snap.sex ?? sex) },
                    set: { figure = $0 }))
                AccountNote(text: "The figure drawn on muscle maps. Display only: separate from gender and sex below.")

                section("Body map")
                BodyMapModeCard()
                AccountNote(text: "How Explore → Muscles shows the body: flat front and back (2D), or a figure you can turn and zoom (3D). Also switchable on the map.")

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

                section("Measurements")
                MeasurementsCard()
                AccountNote(text: "Girths, body weight and body fat over time. Logged values also fine-tune first suggested weights.")

                section("About you (optional)")
                TalkToYouCard(gender: $gender, pronouns: $pronouns, pronounsCustom: $pronounsCustom, call: $coachCall,
                              showPronouns: $showPronouns, name: model.callableName,
                              nickname: Community.shared.me.nickname ?? model.callableName ?? "You",
                              avatar: model.api.resolve(Community.shared.me.avatarUrl))
                if gender == .selfDescribe {
                    AccountField(label: "In your words") {
                        TextField("How do you describe your gender?", text: $genderText)
                            .textInputAutocapitalization(.never)
                    }
                }
                AccountNote(text: "Gender stays on your device and account, never in calculations. Pronouns are used by the coach and Ask Coach, and shown in Community only if you turn it on.")

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
                        AccountCard(symbol: "figure.stand", title: "Sex", subtitle: sex?.label ?? "Not set",
                                    gradient: WorkoutEngine.Category.stretch.gradient) {
                            menuChevron
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
        .readableWidth()
        .themedForm()
        .sheet(isPresented: $showAccess) { HealthAccessSheet() }
        .navigationTitle("Body & Health")
        .toolbarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .task { await health.refresh() }
        .undoableClose(closeGuard, offer: undoOffer)
    }

    private var draft: Draft {
        Draft(height: height, weight: weight, birthYear: birthYear, sex: sex, gender: gender, genderText: genderText,
              figure: figure, writeToHealth: writeToHealth, pronouns: pronouns, pronounsCustom: pronounsCustom,
              coachCall: coachCall, showPronouns: showPronouns)
    }

    /// Undo bar when something was changed since the screen opened (#285).
    private var undoOffer: UndoOffer? {
        guard let start, draft != start else { return nil }
        let kept = draft
        let detail = undoDetail(kept.height.isEmpty ? nil : "\(kept.height) cm", kept.weight.isEmpty ? nil : "\(kept.weight) kg",
                                kept.birthYear.isEmpty ? nil : "born \(kept.birthYear)")
        return UndoOffer(title: "Body & Health closed", detail: detail.isEmpty ? "Changes not saved" : detail,
                         symbol: "heart.text.square.fill", colors: WorkoutEngine.Category.power.colors) {
            AnyView(UndoReopenedPush { BodyHealthView(restoring: kept) })
        }
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
    /// Menu cards show the picked value under the title (#281), so long values never squeeze beside it.
    private var menuChevron: some View {
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .heavy)).opacity(0.8)
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
        figure = b.figure
        pronouns = b.pronouns
        pronounsCustom = b.pronounsCustom ?? ""
        coachCall = b.coachCall
        showPronouns = b.showPronouns ?? false
        start = draft
        if let restoring {
            height = restoring.height
            weight = restoring.weight
            birthYear = restoring.birthYear
            sex = restoring.sex
            gender = restoring.gender
            genderText = restoring.genderText
            figure = restoring.figure
            writeToHealth = restoring.writeToHealth
            pronouns = restoring.pronouns
            pronounsCustom = restoring.pronounsCustom
            coachCall = restoring.coachCall
            showPronouns = restoring.showPronouns
        }
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
        b.figure = figure
        b.pronouns = pronouns
        let custom = pronounsCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        b.pronounsCustom = pronouns == .custom && !custom.isEmpty ? String(custom.prefix(24)) : nil
        b.coachCall = coachCall
        b.showPronouns = showPronouns ? true : nil
        model.saveBody(b)
        if health.connected && writeToHealth {
            var toHealth = BodyMetrics()
            if snap.heightCm == nil { toHealth.heightCm = b.heightCm }
            if snap.weightKg == nil { toHealth.weightKg = b.weightKg }
            Task { await health.saveBody(toHealth) }
        }
        closeGuard.done()
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

/// iOS shows the Health permission sheet only once; declined data is turned back on in Health (#212).
struct HealthAccessSheet: View {
    static let gradient = LinearGradient(colors: [Color(red: 1, green: 0.18, blue: 0.46), Color(red: 1, green: 0.48, blue: 0.24)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let steps = [
        "Open the Health app and tap your profile picture",
        "Tap Apps, then MonkeyWorkout",
        "Tap Turn On All, or switch on what you need under Read and Write",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AccountHeader(symbol: "key.fill", title: "Turn Health data back on",
                                  subtitle: "iOS asks only once. Anything you declined is turned back on in Health.",
                                  gradient: Self.gradient) { EmptyView() }
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(spacing: 12) {
                            Text("\(i + 1)")
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(Color(red: 1, green: 0.18, blue: 0.46))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.white))
                            Text(step).font(.body.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .card(padding: 14)
                    }
                    LimeActionButton(title: "Open Health", symbol: "arrow.up.right") {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    }
                    .padding(.top, 6)
                    AccountNote(text: "Or iPhone Settings → Health → Data Access & Devices → MonkeyWorkout. Come back here and the data shows on its own.")
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Health access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
