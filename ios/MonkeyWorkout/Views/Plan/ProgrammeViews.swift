import SwiftUI
import WorkoutEngine

// MARK: - Training programmes (#255)

/// Pushes a programme's page.
struct ProgrammeRoute: Hashable {
    let id: String
}

extension ProgrammePhaseKind {
    /// Same colours as the week card's phases; the test week is gold.
    var colors: [Color] {
        switch self {
        case .base: WorkoutEngine.Category.cardio.colors
        case .build: WorkoutEngine.Category.strength.colors
        case .peak: WorkoutEngine.Category.power.colors
        case .ease: WorkoutEngine.Category.stretch.colors
        case .test: [Color(red: 1, green: 0.72, blue: 0), Color(red: 1, green: 0.31, blue: 0.63)]
        }
    }
}

extension Programme {
    var gradient: LinearGradient { palette.gradient }
    var plan: String { "\(weeks) weeks · \(sessionsPerWeek)× a week" }
}

/// Explore → Programmes: the running one first, then every programme as a bold card.
struct ProgrammeLibrarySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let a = model.activeProgramme, let p = a.programme {
                Text(a.paused ? "Paused" : "Running").eyebrow()
                NavigationLink(value: ProgrammeRoute(id: p.id)) { ProgrammeCard(programme: p, week: model.programmeWeek, paused: a.paused) }
                    .buttonStyle(.plain)
            }
            Text("Programmes").eyebrow()
            ForEach(Programme.all.filter { $0.id != model.activeProgramme?.programmeId }) { p in
                NavigationLink(value: ProgrammeRoute(id: p.id)) { ProgrammeCard(programme: p) }
                    .buttonStyle(.plain)
            }
            Text("A programme runs your plan for a few weeks toward one goal: phases, signature workouts and a test at the end. Your days, gym and time still shape every week, and your own plan comes back when you pause or finish.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

/// Explore-style programme card: icon tile, name and tagline, big week count (or the current week when running).
struct ProgrammeCard: View {
    let programme: Programme
    var week: Int?
    var paused = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: programme.symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(programme.name).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.7)
                Text(week == nil ? programme.tagline : paused ? "Paused · tap to resume" : programme.phase(week: week!).kind.label + " · " + programme.tagline)
                    .font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(week.map { "\($0)/\(programme.weeks)" } ?? "\(programme.weeks)").font(Theme.display(28)).monospacedDigit()
                Text(week == nil ? "WEEKS" : "WEEK").font(Theme.label(9)).tracking(1.2).opacity(0.8)
            }
            .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(programme.gradient))
        .accessibilityElement(children: .combine)
    }
}

/// Phases as one coloured bar, each segment as wide as its weeks.
struct ProgrammePhaseStrip: View {
    let programme: Programme
    /// Outlines the segment holding this programme week.
    var week: Int?

    var body: some View {
        GeometryReader { g in
            let gap: CGFloat = 3
            let free = g.size.width - gap * CGFloat(programme.phases.count - 1)
            HStack(spacing: gap) {
                ForEach(Array(programme.phaseStarts.enumerated()), id: \.offset) { _, item in
                    segment(item.phase, from: item.week)
                        .frame(width: max(0, free * CGFloat(item.phase.weeks) / CGFloat(programme.weeks)))
                }
            }
        }
        .frame(height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(programme.phases.map { "\($0.kind.label) \($0.weeks) weeks" }.joined(separator: ", "))
    }

    private func segment(_ p: ProgrammePhase, from start: Int) -> some View {
        let current = week.map { $0 >= start && $0 < start + p.weeks } ?? false
        return VStack(alignment: .leading, spacing: 1) {
            Text(p.kind.label).font(Theme.label(12))
            Text(p.weeks == 1 ? "wk \(start)" : "wk \(start)–\(start + p.weeks - 1)")
                .font(.system(size: 9, weight: .bold, design: .rounded)).opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: p.kind.colors, startPoint: .leading, endPoint: .trailing))
        .overlay { if current { Rectangle().strokeBorder(Theme.lime, lineWidth: 3) } }
    }
}

/// Programme page: phases, signature workouts, what it changes while it runs, start / pause / resume / leave.
struct ProgrammeDetailView: View {
    let programme: Programme
    @Environment(AppModel.self) private var model
    @State private var confirmStart = false
    @State private var confirmLeave = false

    private var mine: ActiveProgramme? {
        model.activeProgramme?.programmeId == programme.id ? model.activeProgramme : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ProgrammePhaseStrip(programme: programme, week: mine == nil ? nil : model.programmeWeek)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(programme.phaseStarts.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(LinearGradient(colors: item.phase.kind.colors, startPoint: .top, endPoint: .bottom))
                                .frame(width: 10, height: 10)
                            Text(item.phase.kind.label).font(Theme.label(14))
                            Text(item.phase.note).font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if !programme.signatures.isEmpty {
                    Text("Signature workouts").eyebrow()
                    ForEach(programme.signatures) { SignatureCard(signature: $0, programme: programme) }
                }
                changes
                if programme.hasTest {
                    Text("Finish line").eyebrow()
                    HStack(spacing: 14) {
                        Image(systemName: "trophy.fill").font(.system(size: 24, weight: .bold))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.25)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Test week").font(Theme.display(21))
                            Text("PR attempts: " + programme.lifts.map { Exercise.get($0).name }.joined(separator: ", "))
                                .font(.footnote.weight(.semibold)).opacity(0.9)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: ProgrammePhaseKind.test.colors, startPoint: .leading, endPoint: .trailing)))
                }
                actions
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(programme.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Start \(programme.name)?", isPresented: $confirmStart, titleVisibility: .visible) {
            Button("Start programme") { model.startProgramme(programme) }
        } message: {
            Text(model.activeProgramme == nil
                 ? "It replaces your plan from this week. Your own plan is saved and comes back when you pause, leave or finish."
                 : "It replaces \(model.activeProgramme?.programme?.name ?? "your programme"), which you leave. Your own plan is still saved.")
        }
        .confirmationDialog("Leave \(programme.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave programme", role: .destructive) { model.leaveProgramme() }
        } message: {
            Text("Your own plan comes back. Progress keeps what you trained.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: programme.symbol)
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mine.map { $0.paused ? "PAUSED" : "WEEK \(model.programmeWeek ?? 1) OF \(programme.weeks)" } ?? programme.plan.uppercased())
                        .font(Theme.label(11)).tracking(1.4).opacity(0.85)
                    Text(programme.name).font(Theme.display(28)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            Text(programme.summary).font(.subheadline.weight(.semibold)).opacity(0.92)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(programme.gradient))
    }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("While it runs").eyebrow()
            row("target", "Goal", programme.goal.config.label, locked: true)
            row("rectangle.split.3x1.fill", "Split", programme.split == .auto ? "Built for the goal" : programme.split.title, locked: true)
            row(programme.method.symbol, "Method", programme.method.label, locked: true)
            if !programme.focusMuscles.isEmpty {
                row("scope", "Focus", programme.focusMuscles.map(\.label).joined(separator: ", "), locked: true)
            }
            row("calendar", "Sessions", "\(programme.sessionsPerWeek)× a week to start, your days", locked: false)
            row("building.2.fill", "Gym and time", "Still yours", locked: false)
            Text("Your own plan is saved and comes back when you pause, leave or finish.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func row(_ symbol: String, _ title: String, _ value: String, locked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).frame(width: 30)
            Text(title).font(Theme.label(14))
            Spacer(minLength: 6)
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
            Image(systemName: locked ? "lock.fill" : "checkmark").font(.caption2.bold()).foregroundStyle(locked ? Theme.muted : Theme.lime)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    @ViewBuilder
    private var actions: some View {
        if let a = mine {
            HStack(spacing: 10) {
                if a.paused {
                    bigButton("Resume", "play.fill", fill: Theme.lime) { model.resumeProgramme() }
                } else {
                    bigButton("Pause", "pause.fill", fill: Theme.lime) { model.pauseProgramme() }
                }
                bigButton("Leave", "xmark", fill: Color.white.opacity(0.12), ink: .white) { confirmLeave = true }
            }
            Text(a.paused
                 ? "Paused at week \(model.programmeWeek ?? 1). Resume picks it up there."
                 : "Pause brings your own plan back (holiday, injury) and keeps this programme at week \(model.programmeWeek ?? 1).")
                .font(.caption).foregroundStyle(Theme.muted)
        } else {
            bigButton(model.activeProgramme == nil ? "Start programme" : "Switch to this programme", "flag.checkered", fill: Theme.lime) {
                confirmStart = true
            }
            Text("Starts this week, week 1: \(programme.phases[0].kind.label).").font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func bigButton(_ title: String, _ symbol: String, fill: Color, ink: Color = Theme.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.display(17))
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(ink)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}

/// A signature workout: name, the phases it runs in and its exercises with the first phase's dose.
private struct SignatureCard: View {
    let signature: ProgrammeSignature
    let programme: Programme

    var body: some View {
        let first = programme.phases.first { signature.phases.contains($0.kind) }?.kind ?? .base
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(signature.name).font(Theme.display(20))
                Spacer()
                Text("1× / WEEK").font(Theme.label(10)).tracking(1).opacity(0.85)
            }
            ForEach(signature.items, id: \.exerciseId) { it in
                let d = it.dose(first)
                HStack {
                    Text(Exercise.get(it.exerciseId).name).font(.footnote.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text("\(d.sets) × \(d.reps)").font(Theme.label(13)).monospacedDigit()
                }
            }
            Text(signature.phases.count == programme.phases.count
                 ? "Every week; heavier as the phases go."
                 : "In " + programme.phases.filter { signature.phases.contains($0.kind) }.map(\.kind.label).joined(separator: ", ")
                    + "; heavier as the phases go. Your gym lacks one? The closest exercise it has takes its place.")
                .font(.caption.weight(.medium)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(programme.gradient.opacity(0.9)))
    }
}

/// Train: the running (or paused) programme above the week card. Test week: PR attempt buttons per lift.
struct ProgrammeHeroCard: View {
    @Environment(AppModel.self) private var model
    @State private var attempt: String?

    var body: some View {
        if let a = model.activeProgramme, let p = a.programme, let week = model.programmeWeek {
            let phase = p.phase(week: week)
            NavigationLink(value: ProgrammeRoute(id: p.id)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(a.paused ? "PROGRAMME PAUSED · WEEK \(week) OF \(p.weeks)" : "PROGRAMME · WEEK \(week) OF \(p.weeks) · \(phase.kind.label.uppercased())")
                        .font(Theme.label(10)).tracking(1.4).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
                    Text(p.name).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(a.paused ? "Your own plan runs. Resume to pick it up at week \(week)." : headline(p, week: week, phase: phase))
                        .font(.footnote.weight(.semibold)).opacity(0.92).lineLimit(2)
                    HStack(spacing: 3) {
                        ForEach(1...p.weeks, id: \.self) { w in
                            let k = p.phase(week: w).kind
                            Capsule()
                                .fill(w == week ? AnyShapeStyle(Theme.lime)
                                      : k == .test ? AnyShapeStyle(LinearGradient(colors: k.colors, startPoint: .leading, endPoint: .trailing))
                                      : AnyShapeStyle(Color.white.opacity(w < week ? 0.95 : 0.3)))
                                .frame(height: 7)
                        }
                    }
                    .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(p.gradient))
                .opacity(a.paused ? 0.75 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the programme")
            if !a.paused, phase.kind == .test {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test week · PR attempts").eyebrow()
                    ForEach(p.lifts, id: \.self) { id in
                        Button { attempt = id } label: {
                            HStack {
                                Image(systemName: "trophy.fill")
                                Text(Exercise.get(id).name).font(Theme.label(15)).lineLimit(1)
                                Spacer()
                                Text("Attempt").font(Theme.label(13))
                                Image(systemName: "chevron.right").font(.caption.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: ProgrammePhaseKind.test.colors, startPoint: .leading, endPoint: .trailing)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fullScreenCover(item: Binding(get: { attempt.map(LiftRoute.init) }, set: { attempt = $0?.id })) { r in
                    PRAttemptView(exerciseId: r.id)
                }
            }
        }
    }

    private func headline(_ p: Programme, week: Int, phase: ProgrammePhase) -> String {
        let left = p.weeks - week
        if phase.kind == .test { return "Test week. Go for your PRs 🏆" }
        guard p.hasTest else { return phase.note }
        return "\(phase.note). \(left) week\(left == 1 ? "" : "s") to your PR test."
    }
}

private struct LiftRoute: Identifiable {
    let id: String
}

/// Training profile: the programme setting goal, split and method, with pause / resume.
struct ProgrammeProfileCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let a = model.activeProgramme, let p = a.programme {
            HStack(spacing: 12) {
                NavigationLink(value: ProgrammeRoute(id: p.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.paused ? "PROGRAMME PAUSED" : "PROGRAMME · WEEK \(model.programmeWeek ?? 1) OF \(p.weeks)")
                            .font(Theme.label(10)).tracking(1.3).opacity(0.85)
                        Text(p.name).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(a.paused ? "Your own plan runs" : "Sets goal, split and method while it runs")
                            .font(.caption.weight(.semibold)).opacity(0.9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { a.paused ? model.resumeProgramme() : model.pauseProgramme() } label: {
                    Label(a.paused ? "Resume" : "Pause", systemImage: a.paused ? "play.fill" : "pause.fill")
                        .font(Theme.label(13))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Capsule().fill(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(p.gradient))
        }
    }
}

/// Progress → Programmes: the running one with its lifts start vs now, then finished and left ones.
struct ProgrammeProgressSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let a = model.activeProgramme, let p = a.programme {
                let week = model.programmeWeek ?? 1
                NavigationLink(value: ProgrammeRoute(id: p.id)) {
                    HStack(spacing: 14) {
                        Image(systemName: p.symbol).font(.system(size: 24, weight: .bold))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(a.paused ? "Paused at week \(week)" : "Week \(week) of \(p.weeks) · \(p.phase(week: week).kind.label)")
                                .font(.footnote.weight(.semibold)).opacity(0.9)
                        }
                        Spacer(minLength: 4)
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(Int((Double(week - 1) / Double(p.weeks) * 100).rounded()))").font(Theme.display(30)).monospacedDigit()
                            Text("%").font(Theme.label(13))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(p.gradient))
                }
                .buttonStyle(.plain)
                LiftsCompare(lifts: model.programmeLifts(p, start: a.start))
            } else {
                Text("No programme running. Pick one in Explore → Programmes: phases, signature workouts and a PR test at the end.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
            let done = model.programmeHistory.reversed()
            if !done.isEmpty {
                Text("Finished").eyebrow()
                ForEach(Array(done)) { r in
                    if let p = r.programme {
                        HStack(spacing: 14) {
                            Image(systemName: r.finished ? "trophy.fill" : "flag.fill").font(.system(size: 22, weight: .bold))
                                .frame(width: 48, height: 48)
                                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.2)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name).font(Theme.display(18)).lineLimit(1)
                                Text((r.finished ? "Finished " : "Left after \(r.weeks) week\(r.weeks == 1 ? "" : "s") · ")
                                     + r.end.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .font(.caption.weight(.semibold)).opacity(0.9)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(p.gradient))
                        .opacity(r.finished ? 1 : 0.7)
                    }
                }
            }
        }
    }
}

/// Start → now rows: estimated 1RM before the programme and since.
struct LiftsCompare: View {
    let lifts: [ProgrammeLift]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Start → now").eyebrow()
                Spacer()
                Text("est. 1RM").font(Theme.label(12)).foregroundStyle(Theme.muted)
            }
            ForEach(lifts) { l in
                HStack {
                    Text(Exercise.get(l.exerciseId).name).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    Text("\(l.before.map { Format.kg($0.rounded()) } ?? "–") → \(l.now.map { Format.kg($0.rounded()) } ?? "–") kg")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).monospacedDigit()
                    if let c = l.change {
                        Text("\(c >= 0 ? "+" : "−")\(Format.kg(abs(c).rounded()))")
                            .font(Theme.label(15)).monospacedDigit()
                            .foregroundStyle(c >= 0 ? Theme.lime : Color.red)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            }
        }
    }
}

/// Shown once on Train when a programme ends: trophy, lifts start vs end, own plan back.
struct ProgrammeFinishedSheet: View {
    let record: ProgrammeRecord
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let p = record.programme {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(LinearGradient(colors: ProgrammePhaseKind.test.colors, startPoint: .top, endPoint: .bottom))
                        .padding(.top, 30)
                    Text("Programme complete").font(Theme.label(13)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.muted)
                    Text(p.name).font(Theme.display(32)).multilineTextAlignment(.center)
                    Text("\(p.weeks) weeks done. Your own plan is back on Train; pick another programme in Explore whenever you like.")
                        .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                    LiftsCompare(lifts: model.programmeLifts(p, start: record.start, end: record.end))
                    Button { dismiss() } label: {
                        Text("Let's train").font(Theme.display(17)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
        }
    }
}
