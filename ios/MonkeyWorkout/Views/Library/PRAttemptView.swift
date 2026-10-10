import SwiftUI
import WorkoutEngine

/// Personal-record attempt (#60): pick the kind, get a target + warm-up ramp from history, try up to three times,
/// then log the result and celebrate a new record.
struct PRAttemptView: View {
    let exerciseId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case setup, live, result }

    @State private var stage: Stage = .setup
    @State private var kind: PRKind = .oneRepMax
    @State private var repTarget = 5
    @State private var kg: Double = 0
    /// Rep goal for max reps; also the reps entered when finishing a max-reps set.
    @State private var reps = 1
    @State private var plan: PRPlan?
    @State private var rampDone: Set<Int> = []
    @State private var tries: [PRSet] = []
    @State private var result: PRAttempt?

    private var e: Exercise { Exercise.get(exerciseId) }
    private var step: Double { LoadAdvisor.steps(for: e, kg: kg).granularity }
    private var increment: Double { LoadAdvisor.steps(for: e, kg: kg).increment }
    private var targetReps: Int { kind == .oneRepMax ? 1 : repTarget }

    /// `showing` opens straight on a saved result (demo screenshots).
    init(exerciseId: String, initialKind: PRKind? = nil, showing saved: PRAttempt? = nil) {
        self.exerciseId = exerciseId
        let kinds = PRPlanner.kinds(for: Exercise.get(exerciseId))
        _kind = State(initialValue: saved?.kind ?? initialKind.flatMap { kinds.contains($0) ? $0 : nil } ?? kinds.first ?? .maxReps)
        _result = State(initialValue: saved)
        _stage = State(initialValue: saved == nil ? .setup : .result)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .setup: setup
                case .live: live
                case .result: resultView
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                if stage != .result {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                if stage == .live && !tries.isEmpty && kind != .maxReps {
                    ToolbarItem(placement: .confirmationAction) { Button("Finish") { finish() }.bold() }
                }
            }
        }
        .onAppear { if result == nil { replan(keepKg: false) } }
        .sensoryFeedback(.success, trigger: result?.isRecord == true)
    }

    // MARK: Setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.name.uppercased()).font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.muted)
                    Text("Attempt a PR").font(Theme.display(34))
                }
                Text("Type").eyebrow()
                ForEach(PRPlanner.kinds(for: e)) { k in kindCard(k) }
                if let plan {
                    Text("Target").eyebrow()
                    targetCard(plan)
                    if !plan.ramp.isEmpty {
                        Text("Warm-up").eyebrow()
                        rampList(plan.ramp, interactive: false)
                    }
                    safetyCard(plan.safety)
                }
                Button(plan?.ramp.isEmpty == false ? "Start warm-up" : "Start") {
                    rampDone = []
                    tries = []
                    stage = .live
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(kind != .maxReps && kg <= 0)
                .padding(.top, 6)
            }
            .padding(16)
        }
    }

    private func kindCard(_ k: PRKind) -> some View {
        let (title, sub, big, colors): (String, String, String, [Color]) = switch k {
        case .oneRepMax: ("1 rep max", "Heaviest single", "1RM", WorkoutEngine.Category.strength.colors)
        case .repMax: ("Rep max", "Heaviest for \(repTarget) reps", "\(repTarget)RM", WorkoutEngine.Category.power.colors)
        case .maxReps: ("Max reps", PRPlanner.isBodyweight(e) ? "Most reps, bodyweight" : "Most reps at a load", "AMRAP", WorkoutEngine.Category.warmup.colors)
        }
        let symbol = switch k {
        case .oneRepMax: "trophy.fill"
        case .repMax: "repeat"
        case .maxReps: "infinity"
        }
        return Button {
            kind = k
            replan(keepKg: false)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.2)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.display(20))
                        Text(sub).font(.footnote.weight(.medium)).opacity(0.85)
                    }
                    Spacer()
                    Text(big).font(Theme.display(26))
                }
                if k == .repMax && kind == .repMax {
                    HStack(spacing: 8) {
                        ForEach(PRPlanner.repMaxChoices, id: \.self) { n in
                            Button("\(n) reps") {
                                repTarget = n
                                replan(keepKg: false)
                            }
                            .font(Theme.label(14))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(repTarget == n ? Color.white : Color.white.opacity(0.2)))
                            .foregroundStyle(repTarget == n ? Theme.ink : Color.white)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.lime, lineWidth: kind == k ? 3 : 0))
            .opacity(kind == k ? 1 : 0.6)
        }
        .buttonStyle(.plain)
    }

    private func targetCard(_ plan: PRPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LoadAdvisor.formatKg(kg)).font(Theme.display(44)).monospacedDigit()
                Text(kind == .maxReps && PRPlanner.isBodyweight(e) ? "kg added" : "kg").font(Theme.label(16))
                Spacer()
                stepper(minus: { kg = max(0, kg - step); replan(keepKg: true) }, plus: { kg += step; replan(keepKg: true) })
            }
            if kind == .maxReps {
                Text("Goal: \(plan.reps) reps").font(Theme.label(16)).foregroundStyle(Theme.lime)
            } else if let best = plan.best {
                let delta = kg - best
                Text(delta > 0 ? "+\(LoadAdvisor.formatKg(delta)) kg vs best \(LoadAdvisor.formatKg(best))" : "Best \(LoadAdvisor.formatKg(best)) kg × \(targetReps)")
                    .font(Theme.label(14))
                    .foregroundStyle(delta > 0 ? Theme.lime : Theme.muted)
            }
            Text(plan.basis).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stepper(minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            stepButton("minus", minus)
            stepButton("plus", plus)
        }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .heavy))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.cardStrong))
        }
        .buttonStyle(.plain)
    }

    private func safetyCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
            Text(text).font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.orange.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.orange.opacity(0.5)))
    }

    private func rampList(_ ramp: [RampStep], interactive: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(ramp.enumerated()), id: \.offset) { i, s in
                Button {
                    if rampDone.contains(i) { rampDone.remove(i) } else { rampDone.insert(i) }
                } label: {
                    HStack {
                        if interactive {
                            Image(systemName: rampDone.contains(i) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(rampDone.contains(i) ? Theme.lime : Theme.muted)
                        }
                        Text("\(LoadAdvisor.formatKg(s.kg)) kg").font(.body.weight(.bold)).monospacedDigit()
                        Spacer()
                        Text("× \(s.reps)").font(Theme.label(15)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!interactive)
                if i < ramp.count - 1 { Divider().overlay(Theme.stroke) }
            }
        }
        .card(padding: 14)
    }

    // MARK: Live

    private var live: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(e.name) · \(PRPlanner.label(kind, reps: targetReps))".uppercased())
                        .font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.muted)
                    Text(tries.isEmpty ? "Warm up, then go" : "Next attempt").font(Theme.display(30))
                }
                if let ramp = plan?.ramp, !ramp.isEmpty, tries.isEmpty {
                    rampList(ramp, interactive: true)
                }
                attemptCard
                if !tries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Attempts").eyebrow()
                        ForEach(Array(tries.enumerated()), id: \.offset) { i, t in
                            HStack {
                                Text("#\(i + 1)").font(Theme.label(13)).foregroundStyle(Theme.muted)
                                Text("\(LoadAdvisor.formatKg(t.kg)) kg × \(t.reps)").font(.body.weight(.bold)).monospacedDigit()
                                Spacer()
                                Text(t.made ? "MADE" : "MISSED").font(Theme.label(11)).tracking(1)
                                    .foregroundStyle(t.made ? Theme.lime : Color.orange)
                            }
                        }
                    }
                    .card()
                }
                if let safety = plan?.safety { safetyCard(safety) }
            }
            .padding(16)
        }
    }

    private var attemptCard: some View {
        VStack(spacing: 12) {
            if kind != .maxReps {
                Text("Attempt \(tries.count + 1) of \(PRPlanner.maxAttempts)").eyebrow()
            } else {
                Text("One all-out set").eyebrow()
            }
            Text(LoadAdvisor.formatKg(kg)).font(Theme.display(76)).monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 14) {
                stepper(minus: { kg = max(0, kg - step) }, plus: { kg += step })
                Text(kind == .maxReps ? "KG" : "KG × \(targetReps)").font(Theme.label(15)).foregroundStyle(Theme.muted)
            }
            if kind == .maxReps {
                VStack(spacing: 6) {
                    Text("Reps done").eyebrow()
                    HStack(spacing: 18) {
                        Text("\(reps)").font(Theme.display(48)).monospacedDigit().frame(minWidth: 70)
                        stepper(minus: { reps = max(0, reps - 1) }, plus: { reps += 1 })
                    }
                    if let goal = plan?.reps { Text("Goal \(goal)").font(Theme.label(13)).foregroundStyle(Theme.lime) }
                }
                Button("Save result") {
                    tries.append(PRSet(kg: kg, reps: reps, made: reps > 0))
                    finish()
                }
                .buttonStyle(LimeButtonStyle())
            } else {
                HStack(spacing: 10) {
                    Button { record(made: false) } label: {
                        Text("Missed").font(Theme.label(17)).frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(Capsule().fill(Theme.cardStrong))
                    }
                    .buttonStyle(.plain)
                    Button("Made it") { record(made: true) }
                        .buttonStyle(LimeButtonStyle())
                }
                Text("Rest 3–5 min between attempts").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }

    private func record(made: Bool) {
        tries.append(PRSet(kg: kg, reps: targetReps, made: made))
        if tries.count >= PRPlanner.maxAttempts {
            finish()
            return
        }
        // After a make, suggest going up one increment; after a miss, stay.
        if made { withAnimation { kg = LoadAdvisor.round(kg + increment, to: step) } }
    }

    // MARK: Result

    private func finish() {
        guard result == nil else { return }
        let warmups = (plan?.ramp ?? []).enumerated().filter { rampDone.contains($0.offset) }
            .map { PRSet(kg: $0.element.kg, reps: $0.element.reps, warmup: true) }
        let firstKg = tries.first?.kg ?? kg
        let previous = model.prBest(exerciseId, kind: kind, reps: targetReps, kg: firstKg)
        let attempt = PRPlanner.finish(exerciseId: exerciseId, kind: kind, targetReps: targetReps,
                                       sets: warmups + tries, previousBest: previous)
        guard !tries.isEmpty else {
            dismiss()
            return
        }
        model.savePRAttempt(attempt)
        result = attempt
        stage = .result
    }

    private var resultView: some View {
        let r = result
        let record = r?.isRecord == true
        let colors = record ? WorkoutEngine.Category.strength.colors : [Color(white: 0.22), Color(white: 0.12)]
        return ScrollView {
            VStack(spacing: 14) {
                Image(systemName: record ? "trophy.fill" : (r?.success == true ? "checkmark.seal.fill" : "flame.fill"))
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(record ? Color.yellow : Theme.lime)
                    .symbolEffect(.bounce, value: record)
                    .padding(.top, 20)
                Text(record ? "NEW PERSONAL RECORD" : (r?.success == true ? "SOLID WORK" : "GOOD EFFORT"))
                    .font(Theme.label(14)).tracking(1.6)
                if let r {
                    Text(r.kind == .maxReps ? "\(r.reps)" : LoadAdvisor.formatKg(r.kg))
                        .font(Theme.display(84)).monospacedDigit()
                    Text(resultCaption(r)).font(Theme.label(14)).multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        if let delta = improvement(r) {
                            Text(delta).font(Theme.label(14)).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(.white.opacity(0.18))).foregroundStyle(Theme.lime)
                        }
                        if r.success {
                            ShareLink(item: shareText(r)) {
                                Label("Share", systemImage: "square.and.arrow.up").font(Theme.label(14))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(Capsule().fill(.white.opacity(0.18)))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    if !r.success {
                        Text("Missed lifts are part of the process. Your best stays \(previousText(r)).")
                            .font(.footnote).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                    }
                }
                PRHistoryList(exerciseId: exerciseId, limit: 6)
                    .padding(.top, 8)
                Button("Done") { dismiss() }.buttonStyle(LimeButtonStyle()).padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .background(
            LinearGradient(colors: colors + [Theme.bg], startPoint: .top, endPoint: .center).ignoresSafeArea()
        )
    }

    private func resultCaption(_ r: PRAttempt) -> String {
        switch r.kind {
        case .maxReps: "REPS AT \(LoadAdvisor.formatKg(r.kg)) KG · \(e.name.uppercased())"
        default: "KG × \(r.targetReps ?? 1) · \(e.name.uppercased()) \(r.label)"
        }
    }

    private func improvement(_ r: PRAttempt) -> String? {
        guard r.isRecord, let prev = r.previousBest else { return r.isRecord ? "First record" : nil }
        return r.kind == .maxReps ? "+\(r.reps - Int(prev)) reps" : "+\(LoadAdvisor.formatKg(r.kg - prev)) kg"
    }

    private func previousText(_ r: PRAttempt) -> String {
        guard let p = r.previousBest else { return "to be set" }
        return r.kind == .maxReps ? "\(Int(p)) reps" : "\(LoadAdvisor.formatKg(p)) kg"
    }

    private func shareText(_ r: PRAttempt) -> String {
        let what = r.kind == .maxReps
            ? "\(r.reps) reps at \(LoadAdvisor.formatKg(r.kg)) kg"
            : "\(LoadAdvisor.formatKg(r.kg)) kg × \(r.targetReps ?? 1)"
        return "\(r.isRecord ? "New PR" : "Lifted") on \(e.name): \(what) 💪 #MonkeyWorkout"
    }

    // MARK: Plan

    private func replan(keepKg: Bool) {
        let p = model.prPlan(e, kind: kind, reps: targetReps, kg: keepKg ? kg : nil)
        plan = p
        if !keepKg { kg = p.kg }
        reps = p.kind == .maxReps ? p.reps : targetReps
    }
}

/// Records per kind and recent attempts for one exercise (exercise page and attempt result).
struct PRHistoryList: View {
    let exerciseId: String
    var limit = 10
    @Environment(AppModel.self) private var model

    var body: some View {
        let attempts = model.prAttempts(exerciseId)
        if !attempts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("PR history").eyebrow()
                ForEach(attempts.prefix(limit)) { a in
                    HStack {
                        Text(a.date.formatted(.dateTime.day().month(.abbreviated))).font(.subheadline.weight(.bold))
                        Text(a.label).font(Theme.label(11)).tracking(1).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(summary(a)).font(Theme.label(14)).monospacedDigit()
                            .foregroundStyle(a.isRecord ? Theme.lime : (a.success ? Color.white : Theme.muted))
                        if a.isRecord { Image(systemName: "trophy.fill").foregroundStyle(.yellow).font(.caption) }
                    }
                    .contextMenu {
                        Button("Delete attempt", systemImage: "trash", role: .destructive) { model.deletePRAttempt(a.id) }
                    }
                    Divider().overlay(Theme.stroke)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func summary(_ a: PRAttempt) -> String {
        if !a.success { return "\(LoadAdvisor.formatKg(a.kg)) kg missed" }
        return "\(LoadAdvisor.formatKg(a.kg)) kg × \(a.reps)"
    }
}

/// Exercise page card: current records and the "Attempt a PR" entry.
struct PRCard: View {
    let exerciseId: String
    @Environment(AppModel.self) private var model
    @State private var attempting = false

    var body: some View {
        let e = Exercise.get(exerciseId)
        if !PRPlanner.kinds(for: e).isEmpty {
            let records = PRPlanner.records(model.prAttempts(exerciseId))
            VStack(alignment: .leading, spacing: 10) {
                Button { attempting = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 24, weight: .bold))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Attempt a PR").font(Theme.display(22))
                            Text(records.isEmpty ? "Test your 1RM, rep max or max reps" : "Beat your best")
                                .font(.footnote.weight(.medium)).opacity(0.85)
                        }
                        Spacer()
                        if let top = records.first {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(top.kind == .maxReps ? "\(top.reps)" : LoadAdvisor.formatKg(top.kg)).font(Theme.display(28))
                                Text(top.label).font(Theme.label(10)).opacity(0.85)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
                }
                .buttonStyle(.plain)
                if records.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(records) { r in
                            StatTile(value: r.kind == .maxReps ? "\(r.reps)" : LoadAdvisor.formatKg(r.kg), label: r.label)
                        }
                    }
                }
                PRHistoryList(exerciseId: exerciseId, limit: 5)
            }
            .fullScreenCover(isPresented: $attempting) { PRAttemptView(exerciseId: exerciseId) }
        }
    }
}
