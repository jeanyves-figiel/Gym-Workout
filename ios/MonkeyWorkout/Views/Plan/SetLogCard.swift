import SwiftUI
import UIKit
import WorkoutEngine

/// Per-set logging in the workout player: kg × reps and optional RIR for every set, prefilled from the load suggestion.
/// Give it `.id(item.uid)` at the call site so its rows reset when the player moves to another exercise.
struct SetLogCard: View {
    let item: PlannedExercise
    let sessionId: String
    /// Sets completed in the player. Completing a set ("SET n DONE") logs that row with its current values.
    let done: Int
    @Environment(AppModel.self) private var model
    @State private var rows: [Row] = []
    @State private var suggestion: LoadSuggestion?
    @FocusState private var focus: Field?
    @State private var explaining = false

    struct Row: Equatable {
        var kg = ""
        var reps = ""
        var rir = ""
        var logged = false
    }

    enum Field: Hashable {
        case kg(Int), reps(Int), rir(Int)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Log sets").eyebrow()
                Spacer()
                Button { explaining = true } label: {
                    HStack(spacing: 4) {
                        Text("kg × reps · RIR")
                        Image(systemName: "info.circle.fill")
                    }
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Explains RIR and RPE")
            }
            if let s = suggestion { SuggestionLine(suggestion: s) }
            ForEach(rows.indices, id: \.self) { i in row(i) }
        }
        .card(padding: 14)
        .sheet(isPresented: $explaining) {
            ScrollView { RPEExplainer().padding(16) }
                .background(Theme.bg.ignoresSafeArea())
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
        .onAppear(perform: load)
        .onChange(of: done) { old, new in
            let end = min(new, rows.count)
            guard old >= 0, old < end else { return }
            for i in old..<end where !rows[i].logged { log(i) }
        }
    }

    private func row(_ i: Int) -> some View {
        let current = i == done && !rows[i].logged
        return HStack(spacing: 8) {
            Text("\(i + 1)")
                .font(Theme.label(14))
                .foregroundStyle(current ? Theme.lime : Theme.muted)
                .frame(width: 20)
            field($rows[i].kg, placeholder: "kg", keyboard: .decimalPad, focus: .kg(i), width: 70)
            Text("×").font(Theme.label(14)).foregroundStyle(Theme.muted)
            field($rows[i].reps, placeholder: "reps", keyboard: .numberPad, focus: .reps(i), width: 50)
            field($rows[i].rir, placeholder: "RIR", keyboard: .numberPad, focus: .rir(i), width: 46)
            Spacer(minLength: 0)
            Button { log(i) } label: {
                Image(systemName: rows[i].logged ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(rows[i].logged ? Theme.lime : Color.white.opacity(0.5))
            }
            .disabled(parse(rows[i]) == nil)
            .accessibilityLabel(rows[i].logged ? "Update set \(i + 1)" : "Log set \(i + 1)")
        }
    }

    private func field(_ text: Binding<String>, placeholder: String, keyboard: UIKeyboardType, focus f: Field, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .focused($focus, equals: f)
            .multilineTextAlignment(.center)
            .font(Theme.display(18))
            .frame(width: width)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardStrong))
    }

    private struct Values {
        var kg: Double
        var reps: Int
        var rir: Int?
    }

    private func parse(_ r: Row) -> Values? {
        guard let kg = Double(r.kg.replacingOccurrences(of: ",", with: ".")), kg >= 0, kg <= 1000,
              let reps = Int(r.reps), reps >= 0, reps <= 1000 else { return nil }
        return Values(kg: kg, reps: reps, rir: Int(r.rir).map { min(10, max(0, $0)) })
    }

    private func log(_ i: Int) {
        guard rows.indices.contains(i), let v = parse(rows[i]) else { return }
        model.logSet(exerciseId: item.exerciseId, sessionId: sessionId, setIndex: i, kg: v.kg, reps: v.reps, rir: v.rir)
        rows[i].logged = true
        // Carry the load forward to the sets not logged yet.
        for j in rows.indices where j > i && !rows[j].logged { rows[j].kg = rows[i].kg }
        focus = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func load() {
        let s = model.loadSuggestion(for: item, sessionId: sessionId)
        suggestion = s
        let logged = model.todaysSets(exerciseId: item.exerciseId, sessionId: sessionId)
        let kg = s.map { LoadAdvisor.formatKg($0.kg) } ?? model.lastWeight(item.exerciseId).map { LoadAdvisor.formatKg($0) } ?? ""
        var reps = ""
        if let r = s?.reps ?? item.prescription.repRange?.low { reps = String(r) }
        rows = (0..<max(1, item.prescription.sets)).map { i in
            guard let l = logged[i] else { return Row(kg: kg, reps: reps) }
            return Row(
                kg: l.weightKg.map { LoadAdvisor.formatKg($0) } ?? kg,
                reps: l.reps.map { String($0) } ?? reps,
                rir: l.rir.map { String($0) } ?? "",
                logged: true)
        }
    }
}

/// "82.5 kg × 8" with the reason behind it.
struct SuggestionLine: View {
    let suggestion: LoadSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.label(15))
                Text(suggestion.reason).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        var t = "Suggested \(LoadAdvisor.formatKg(suggestion.kg)) kg"
        if let r = suggestion.reps { t += " × \(r)" }
        return t
    }

    private var symbol: String {
        switch suggestion.action {
        case .increase: "arrow.up.circle.fill"
        case .hold: "equal.circle.fill"
        case .decrease: "arrow.down.circle.fill"
        case .deload: "leaf.circle.fill"
        }
    }

    private var color: Color {
        switch suggestion.action {
        case .increase: Theme.lime
        case .hold: .white
        case .decrease: .orange
        case .deload: .mint
        }
    }
}
