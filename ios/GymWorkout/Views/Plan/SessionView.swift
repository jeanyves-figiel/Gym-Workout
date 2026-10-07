import SwiftUI
import UIKit
import WorkoutEngine

struct SessionView: View {
    let sessionId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rest: RestTimer?

    private var session: Session? { model.plan?.sessions.first { $0.id == sessionId } }

    var body: some View {
        if let session {
            List {
                ForEach(session.blocks) { block in
                    Section {
                        if let note = block.note {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(block.items) { item in
                            ExerciseRow(item: item, block: block, sessionId: session.id) { sec in
                                rest = RestTimer(total: sec)
                            }
                        }
                    } header: {
                        HStack {
                            Circle().fill(block.kind.color).frame(width: 8, height: 8)
                            Text(block.title)
                            Spacer()
                            Text("\(block.targetMin)′")
                        }
                    }
                }
                Section {
                    let done = model.state.done[session.id] ?? false
                    Button(done ? "Mark as not done" : "Finish session") {
                        model.toggleDone(session.id)
                        if !done {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    }
                    .bold()
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(session.focus.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Text("≈ \(session.estMin)′").font(.caption.bold()) } }
            .safeAreaInset(edge: .bottom) {
                if let r = rest {
                    RestTimerBar(timer: r) { rest = nil }
                        .padding()
                }
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "questionmark")
        }
    }
}

struct RestTimer: Equatable {
    let total: Int
    let end: Date

    init(total: Int) {
        self.total = total
        end = Date().addingTimeInterval(TimeInterval(total))
    }
}

struct RestTimerBar: View {
    let timer: RestTimer
    let onClose: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let left = max(0, Int(timer.end.timeIntervalSince(ctx.date).rounded(.up)))
            HStack {
                Image(systemName: left == 0 ? "bell.fill" : "timer")
                Text(left == 0 ? "Go!" : "Rest \(Format.rest(left))").monospacedDigit().bold()
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Close timer")
            }
            .padding()
            .background {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(left == 0 ? 0.6 : 0.25))
                            .frame(width: geo.size.width * (1 - CGFloat(left) / CGFloat(max(1, timer.total))))
                    }
                }
            }
        }
        .task(id: timer.end) {
            let wait = timer.end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
    }
}

struct ExerciseRow: View {
    let item: PlannedExercise
    let block: Block
    let sessionId: String
    let startRest: (Int) -> Void
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var kgText = ""

    private var exercise: Exercise { Exercise.get(item.exerciseId) }
    private var ticked: Bool { model.state.ticked[item.uid] ?? false }
    private var weighted: Bool { block.kind == .strength && !exercise.equipment.isEmpty && exercise.unit != .sec }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button { model.toggleTick(item.uid) } label: {
                    Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(ticked ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(ticked ? "Mark not done" : "Mark done")

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).bold().strikethrough(ticked)
                    Text(Format.prescription(item.prescription)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if item.prescription.restSec > 0 {
                    Button { startRest(item.prescription.restSec) } label: { Image(systemName: "timer") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Start \(Format.rest(item.prescription.restSec)) rest")
                }
                swapMenu
                Button { withAnimation { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Details")
            }

            let meta = [item.prescription.intensity, item.prescription.note].compactMap { $0 }
            if !meta.isEmpty {
                Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            if let paired = item.pairedWith.flatMap(Exercise.find) {
                Label("During rest: \(paired.name) · 5–6 slow reps", systemImage: "figure.flexibility")
                    .font(.caption)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.12)))
            }
            if weighted { weightField }
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(exercise.cues, id: \.self) { Text("• \($0)").font(.caption) }
                    Text("Targets: " + (exercise.primary + exercise.secondary).map(\.label).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, item.supersetWith == nil ? 0 : 18)
        .padding(.vertical, 2)
    }

    private var swapMenu: some View {
        Menu {
            let alts = model.profile.map { exercise.alternatives(for: $0) } ?? []
            if alts.isEmpty { Text("No alternatives with your equipment") }
            ForEach(alts) { a in
                Button(a.name) { model.swap(uid: item.uid, to: a.id) }
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .accessibilityLabel("Swap exercise")
    }

    private var weightField: some View {
        HStack(spacing: 8) {
            TextField(model.lastWeight(exercise.id).map(Format.kg) ?? "kg", text: $kgText)
                .keyboardType(.decimalPad)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
            Text("kg").font(.caption)
            Button("Log") {
                let v = Double(kgText.replacingOccurrences(of: ",", with: "."))
                if let v, v >= 0, v <= 1000 {
                    model.logWeight(exerciseId: exercise.id, sessionId: sessionId, kg: v)
                    kgText = ""
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(kgText.isEmpty)
            if let last = model.lastWeight(exercise.id) {
                Text("last \(Format.kg(last)) kg").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
