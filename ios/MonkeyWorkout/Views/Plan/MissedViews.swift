import SwiftUI
import WorkoutEngine

// Missed sessions (#266): what a member can do with a session of an earlier day this week that wasn't done.

/// Log it · Mark done · Do today · Skip, as one row of buttons.
struct MissedActionsRow: View {
    let session: Session
    var primary: Color = .white
    var primaryInk: Color = Color(red: 0.91, green: 0.2, blue: 0.35)
    let onLog: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            action("Log it", "square.and.pencil", fill: primary, ink: primaryInk, onLog)
            action("Mark done", "checkmark") { withAnimation { model.markMissedDone(session) } }
            action("Do today", "arrow.uturn.forward") { withAnimation { model.doMissedToday(session.id) } }
            action("Skip", "xmark") { withAnimation { model.skipMissed(session.id) } }
        }
    }

    private func action(_ title: String, _ symbol: String, fill: Color = .black.opacity(0.3), ink: Color = .white,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 13, weight: .heavy))
                Text(title).font(Theme.label(11)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(session.displayTitle)")
    }
}

/// Logs a missed session after the fact on its day: when, how long, sets done and kg per exercise.
struct MissedLogSheet: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var minutes = 60
    @State private var sets: [String: Int] = [:]
    @State private var kg: [String: Double] = [:]

    private struct Row: Identifiable {
        let item: PlannedExercise
        let block: Block
        var id: String { item.uid }
        var exercise: Exercise { Exercise.get(item.exerciseId) }
        var loaded: Bool {
            [.strength, .power].contains(block.kind) && !exercise.equipment.isEmpty && exercise.unit != .sec
        }
    }

    private var rows: [Row] {
        session.blocks.filter { ![.warmup, .mobility, .cooldown].contains($0.kind) }
            .flatMap { b in b.items.map { Row(item: $0, block: b) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    VStack(spacing: 10) {
                        DatePicker("Started", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .font(Theme.label(15))
                        Stepper(value: $minutes, in: 5...240, step: 5) {
                            Text("\(minutes) min").font(Theme.label(15)).monospacedDigit()
                        }
                    }
                    .card()
                    Text("Sets done").font(Theme.label(13)).foregroundStyle(Theme.muted).textCase(.uppercase)
                    ForEach(rows) { r in row(r) }
                    Text("Warm-up and cool-down count as done. Weights update your next starting loads.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Log workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .onAppear(perform: prefill)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Missed · \(session.dayLabel)").font(Theme.label(12)).tracking(1.4).textCase(.uppercase).opacity(0.85)
            Text(session.displayTitle).font(Theme.display(30)).lineLimit(1).minimumScaleFactor(0.6)
            Text("Planned \(session.estMin) min").font(.subheadline.weight(.semibold)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(MissedStyle.gradient))
    }

    private func row(_ r: Row) -> some View {
        let planned = max(1, r.item.prescription.sets)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.exercise.name).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(planned) × \(r.item.prescription.reps)").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Stepper(value: Binding(get: { sets[r.id] ?? planned }, set: { sets[r.id] = $0 }), in: 0...planned) {
                    Text("\(sets[r.id] ?? planned)/\(planned)").font(Theme.label(15)).monospacedDigit()
                }
                .fixedSize()
            }
            if r.loaded {
                HStack {
                    Text("kg").font(Theme.label(13)).foregroundStyle(Theme.muted)
                    TextField("–", value: Binding(get: { kg[r.exercise.id] }, set: { kg[r.exercise.id] = $0 }), format: .number)
                        .keyboardType(.decimalPad)
                        .font(Theme.label(15))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.cardStrong))
                }
            }
        }
        .card(padding: 14)
    }

    private var saveBar: some View {
        Button {
            var done: [String: Int] = [:]
            for b in session.blocks { for it in b.items { done[it.uid] = max(1, it.prescription.sets) } }
            for (uid, n) in sets { done[uid] = n }
            model.logMissed(session, setsDone: done, weights: kg.filter { $0.value > 0 }, start: start, minutes: minutes)
            dismiss()
        } label: {
            Label("Save workout", systemImage: "checkmark")
                .font(Theme.label(17)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.bg)
    }

    private func prefill() {
        start = model.defaultStart(of: session)
        minutes = max(5, (session.estMin + 4) / 5 * 5)
        for r in rows where r.loaded { if kg[r.exercise.id] == nil { kg[r.exercise.id] = model.lastWeight(r.exercise.id) } }
    }
}

enum MissedStyle {
    static let gradient = LinearGradient(colors: [Color(hex: 0xFF3D6E), Color(hex: 0xFF8A3D)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}
