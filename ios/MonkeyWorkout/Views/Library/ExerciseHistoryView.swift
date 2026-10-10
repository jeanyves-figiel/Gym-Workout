import Charts
import SwiftUI
import WorkoutEngine

/// On the exercise page: next-session load suggestion (when opened from a planned item) and a link to the history.
struct ExerciseProgressCard: View {
    let exerciseId: String
    var plannedUid: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        let sessions = model.exerciseSessions(exerciseId)
        let suggestion = plannedUid.flatMap { model.plannedItem(uid: $0) }.flatMap { model.loadSuggestion(for: $0.item, sessionId: $0.sessionId) }
        let fromRecords = !Progression.oneRepMaxTrend(exerciseId, records: model.state.history).isEmpty
        if suggestion != nil || !sessions.isEmpty || fromRecords {
            VStack(alignment: .leading, spacing: 12) {
                Text("Progression").eyebrow()
                if let suggestion { SuggestionLine(suggestion: suggestion) }
                NavigationLink {
                    ExerciseHistoryView(exerciseId: exerciseId)
                } label: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.lime)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("History").font(.body.weight(.bold))
                            Text(summary(sessions)).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.muted)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func summary(_ sessions: [ExerciseSession]) -> String {
        guard !sessions.isEmpty else { return "Sessions & est. 1RM trend" }
        var parts = ["\(sessions.count) session\(sessions.count == 1 ? "" : "s")"]
        if let best = sessions.compactMap(\.bestOneRepMax).max() { parts.append("best e1RM \(Int(best.rounded())) kg") }
        return parts.joined(separator: " · ")
    }
}

/// Per-exercise history: best estimated 1RM trend and every logged session with its sets.
struct ExerciseHistoryView: View {
    let exerciseId: String
    @Environment(AppModel.self) private var model

    private struct Point: Identifiable {
        let date: Date
        let kg: Double
        var id: Date { date }
    }

    var body: some View {
        let sessions = model.exerciseSessions(exerciseId)
        let points = trend(sessions)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(Exercise.find(exerciseId)?.name ?? exerciseId)
                    .font(Theme.display(30))
                    .fixedSize(horizontal: false, vertical: true)
                if !points.isEmpty { chart(points) }
                if sessions.isEmpty {
                    Text("No sets logged yet. Log kg × reps in the workout player to see your progression here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .card()
                } else {
                    stats(sessions)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sessions").eyebrow()
                        ForEach(Array(sessions.reversed())) { s in
                            sessionRow(s)
                            Divider().overlay(Theme.stroke)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Best e1RM per logged session (actual reps); falls back to the weekly trend from completed workouts.
    private func trend(_ sessions: [ExerciseSession]) -> [Point] {
        let logged = sessions.compactMap { s in s.bestOneRepMax.map { Point(date: s.date, kg: $0) } }
        if !logged.isEmpty { return logged }
        return Progression.oneRepMaxTrend(exerciseId, records: model.state.history).map { Point(date: $0.0, kg: $0.1) }
    }

    private func chart(_ points: [Point]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Best est. 1RM").eyebrow()
            Chart(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("kg", p.kg))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(WorkoutEngine.Category.strength.gradient)
                PointMark(x: .value("Date", p.date), y: .value("kg", p.kg)).foregroundStyle(Theme.lime)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 160)
            if let first = points.first, let last = points.last, points.count > 1 {
                Text(String(format: "%+.1f kg since %@", last.kg - first.kg, first.date.formatted(.dateTime.day().month())))
                    .font(Theme.label(13))
                    .foregroundStyle(last.kg >= first.kg ? Theme.lime : .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stats(_ sessions: [ExerciseSession]) -> some View {
        let best = sessions.compactMap(\.bestOneRepMax).max()
        let top = sessions.map(\.topKg).max() ?? 0
        return HStack(spacing: 10) {
            StatTile(value: "\(sessions.count)", label: "Sessions")
            StatTile(value: LoadAdvisor.formatKg(top), label: "Top kg")
            StatTile(value: best.map { "\(Int($0.rounded()))" } ?? "–", label: "Best e1RM")
        }
    }

    private func sessionRow(_ s: ExerciseSession) -> some View {
        let title: String? = PRPlanner.isPRSession(s.sessionId) ? "PR attempt" : model.state.history.first(where: {
            $0.sessionId == s.sessionId && Calendar.current.isDate($0.startedAt, inSameDayAs: s.date)
        })?.title
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.date.formatted(.dateTime.weekday(.abbreviated).day().month())).font(.body.weight(.bold))
                    if let title { Text(title).font(.caption).foregroundStyle(Theme.muted) }
                }
                if s.deload {
                    Text("DELOAD").font(Theme.label(10)).tracking(1).foregroundStyle(.mint)
                }
                Spacer()
                if let orm = s.bestOneRepMax {
                    Text("e1RM \(Int(orm.rounded()))").font(Theme.label(13)).foregroundStyle(Theme.lime)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(Array(s.sets.enumerated()), id: \.offset) { _, entry in
                    Text(label(entry))
                        .font(Theme.label(12))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.cardStrong))
                }
            }
        }
    }

    private func label(_ entry: SetLog) -> String {
        var t = "\(LoadAdvisor.formatKg(entry.kg)) kg"
        if let r = entry.reps { t += " × \(r)" }
        if let rir = entry.rir { t += " @\(rir) RIR" }
        return t
    }
}
