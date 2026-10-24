import SwiftUI
import WorkoutEngine

/// Swap a planned exercise (#101): variations of it (#174), best matches for the same muscles with the member's equipment, or any
/// exercise from the full library (custom ones included). This session only, or kept for that day in future weeks.
struct SwapExerciseSheet: View {
    let exerciseId: String
    let uid: String
    /// Called after a swap or a kept swap removed, before the sheet closes.
    var onDone: (() -> Void)? = nil
    /// "Taken?" (#406): this zone is busy, so only exercises done elsewhere (or anywhere) are offered, quiet zones first.
    var busyZone: GymLayout.Zone? = nil
    /// Picks for a workout's own exercise list (#295) instead of swapping in the plan: no keep, no gym change.
    var onPick: ((String) -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var keep = false
    @State private var searching = false
    @State private var picked: String?
    @State private var notHere = false

    private var exercise: Exercise { Exercise.get(exerciseId) }

    private var session: Session? {
        model.plannedItem(uid: uid).flatMap { model.session($0.sessionId) }
    }

    private var dayName: String {
        session?.weekday.map(WeekSchedule.name) ?? "this day"
    }

    /// Same exercise, another variation (#174): offered first, then the best matches.
    private var variations: [Exercise] {
        guard let profile = model.profile else { return [] }
        return exercise.variationOptions(for: profile).filter(freeZone)
    }

    private var options: [Exercise] {
        guard let profile = model.profile else { return [] }
        let all = exercise.swapOptions(for: profile, excluding: Set(variations.map(\.id)))
        let list = Array((busyZone == nil ? all : all.filter(freeZone)).prefix(12))
        if busyZone != nil {
            // Quiet zones first: ones not usually busy around now.
            let quiet = { (e: Exercise) in model.gymZone(e.id).map { !model.zoneBusy($0) } ?? true }
            return list.filter(quiet) + list.filter { !quiet($0) }
        }
        // Gym zones (#274): moves done near the rest of its superset / circuit first.
        return list.filter { nearHere($0) != false } + list.filter { nearHere($0) == false }
    }

    /// Not in the busy zone ("Taken?", #406); always true otherwise.
    private func freeZone(_ e: Exercise) -> Bool {
        guard let busyZone else { return true }
        return model.gymZone(e.id)?.id != busyZone.id
    }

    /// The rest of its superset / circuit.
    private var partners: [Exercise] {
        guard let b = session?.blocks.first(where: { $0.items.contains { $0.uid == uid } }) else { return [] }
        return b.groupMembers(of: uid).filter { $0.uid != uid }.compactMap { Exercise.find($0.exerciseId) }
    }

    /// Done near its group (or near the exercise it replaces); nil without gym zones.
    private func nearHere(_ e: Exercise) -> Bool? {
        guard let layout = model.profile?.gymLayout else { return nil }
        return (partners.isEmpty ? [exercise] : partners).allSatisfy { layout.near(e, $0) }
    }

    private func row(_ e: Exercise) -> some View {
        let near = nearHere(e)
        return OptionRow(exercise: e, zone: model.gymZone(e.id), near: near,
                         warning: near == false && !partners.isEmpty ? "Would split its group across the gym" : nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    current
                    if onPick == nil, !exercise.equipment.isEmpty {
                        // The gym doesn't have it (#162): fix the gym's list, not just this session.
                        Button { notHere = true } label: {
                            HStack {
                                Image(systemName: "questionmark.circle.fill").foregroundStyle(Theme.lime)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Not at this gym?").bold()
                                    Text("Remove it from the gym and swap it everywhere this week").font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Theme.muted)
                            }
                            .foregroundStyle(.white)
                            .card(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }
                    if onPick == nil { keepToggle }
                    if onPick == nil, let rule = model.keptSwap(uid: uid), let original = Exercise.find(rule.from) {
                        Button {
                            model.removeKeptSwap(rule)
                            onDone?()
                            dismiss()
                        } label: {
                            Label("Back to \(original.name) every \(dayName)", systemImage: "arrow.uturn.backward")
                                .font(Theme.label(14))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .card(padding: 0)
                        }
                        .buttonStyle(.plain)
                    }
                    if !variations.isEmpty {
                        GradientSection(symbol: "square.stack.3d.down.right.fill", title: "Variations", gradient: exercise.category.gradient,
                                        ink: exercise.category.ink) {
                            ForEach(variations) { e in
                                Button { apply(e.id) } label: { row(e) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if !options.isEmpty {
                        GradientSection(symbol: "arrow.triangle.2.circlepath", title: "Best matches", gradient: exercise.category.gradient,
                                        ink: exercise.category.ink) {
                            ForEach(options) { e in
                                Button { apply(e.id) } label: { row(e) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    Button { searching = true } label: {
                        Label("Search all exercises", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(LimeButtonStyle())
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(busyZone == nil ? "Swap exercise" : "Free zone swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            .sheet(isPresented: $notHere) {
                NotHereSheet(exerciseId: exerciseId, uid: uid) {
                    onDone?()
                    dismiss()
                }
            }
            .sheet(isPresented: $searching, onDismiss: {
                if let picked { apply(picked) }
            }) {
                ExercisePickerView(limit: 1) { list in
                    picked = list.first { $0.id != exerciseId }?.id
                }
            }
        }
        .presentationDetents([.large])
    }

    private var current: some View {
        HStack(spacing: 14) {
            ExerciseThumbnail(exercise: exercise, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(busyZone.map { "\($0.name) taken · same muscles, free zone" } ?? "Replacing").font(Theme.label(12)).opacity(0.8)
                Text(exercise.name).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.8)
                Text(exercise.primary.map(\.name).joined(separator: " · ")).font(.caption.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(exercise.category.gradient, ink: exercise.category.ink)
    }

    private var keepToggle: some View {
        Toggle(isOn: Binding(get: { keep }, set: { on in
            keep = on
        })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Keep for \(dayName) in future weeks").font(.body.weight(.bold))
                }
                Text(keep ? "Replaces it every week it comes up on \(dayName)." : "Only this session.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.lime)
        .card(padding: 14)
    }

    private func apply(_ id: String) {
        if let onPick { onPick(id) } else { model.swap(uid: uid, to: id, keep: keep) }
        onDone?()
        dismiss()
    }
}

private struct OptionRow: View {
    let exercise: Exercise
    /// Gym zone it's done in (#274); `near` = next to its group, shown as "here".
    var zone: GymLayout.Zone?
    var near: Bool?
    var warning: String?

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.body.weight(.bold)).multilineTextAlignment(.leading)
                Text(exercise.primary.map(\.name).joined(separator: " · ")).font(.caption.weight(.medium)).opacity(0.85)
                Text(exercise.equipment.isEmpty ? "Bodyweight" : exercise.equipment.map(\.label).joined(separator: " · "))
                    .font(.caption2.weight(.semibold)).opacity(0.7)
                if let zone { ZoneTag(zone: zone, text: near == true ? "here · \(zone.name)" : zone.name) }
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption2.weight(.bold)).foregroundStyle(.yellow)
                }
            }
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath").font(.body.weight(.bold))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
        .contentShape(Rectangle())
    }
}
