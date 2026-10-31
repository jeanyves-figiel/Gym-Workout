import SwiftUI
import WorkoutEngine

extension OnboardingStep {
    var symbol: String {
        switch self {
        case .gym: "building.2.fill"
        case .machines: "dumbbell.fill"
        case .map: "map.fill"
        case .plan: "calendar.badge.plus"
        case .tour: "sparkles"
        }
    }

    var category: WorkoutEngine.Category {
        switch self {
        case .gym: .power
        case .machines: .strength
        case .map: .cardio
        case .plan: .warmup
        case .tour: .mobility
        }
    }
}

/// New member onboarding (#664, mix of designs A + B + C from `new-member-onboarding/mix.png`): guided steps
/// Gym → Machines → Map → Plan or programme → Tour, each skippable. A new member runs it in place of the plain plan
/// form; Settings → Onboarding runs it again (`rerun`) or one step on its own (`single`).
struct OnboardingFlowView: View {
    enum Mode: Equatable {
        case newMember, rerun
        case single(OnboardingStep)
    }

    let mode: Mode
    var onClose: () -> Void = {}
    @Environment(AppModel.self) private var model
    @State private var step: OnboardingStep
    /// The profile being set up; a new member's is only saved at the plan step.
    @State private var p: Profile
    /// Steps finished before the plan step made the profile (new member).
    @State private var done: [OnboardingStep] = []
    @State private var programme: Programme?
    @State private var keepPlan: Bool
    @State private var building = false
    @State private var tabsPref = TabsPref.shared
    /// Say it once to Coach (#873).
    @State private var talking = false
    @State private var equipmentOpen = false
    @State private var zonesOpen = false
    @State private var floorPlanOpen = false

    /// `startAt`: demo screenshots of one step of the guided flow.
    init(mode: Mode, profile: Profile?, startAt: OnboardingStep = .gym, onClose: @escaping () -> Void = {}) {
        self.mode = mode
        self.onClose = onClose
        if case .single(let s) = mode { _step = State(initialValue: s) } else { _step = State(initialValue: startAt) }
        var draft = profile ?? Profile()
        if profile == nil {
            draft.applyGoal(draft.goal)
            draft.climbs = false
        }
        _p = State(initialValue: draft)
        _keepPlan = State(initialValue: profile != nil)
    }

    private var isNew: Bool { mode == .newMember }
    private var single: Bool { if case .single = mode { true } else { false } }
    private var steps: [OnboardingStep] { OnboardingStep.allCases }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    content
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                }
                .readableWidth()
            }
            .background(Theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottom }
            .toolbar {
                if !isNew { CloseToolbarItem { close() } }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $building) {
                ProfileFormView(initial: p, newMember: isNew) { made in finishPlan(made) }
                    .navigationTitle("Your training")
            }
            .navigationDestination(isPresented: $talking) {
                CoachPlanSetupView(base: p) { made, protect in
                    talking = false
                    finishPlan(made)
                    // Protect (#873) turns on train around pain (#870) for that spot.
                    if let protect { model.setPainProtect(protect) }
                }
            }
        }
        .onAppear { if isNew, !model.demo { model.onboardingOpen = true } }
        // Signed out mid-way: the next account starts clean.
        .onDisappear { if isNew, !model.demo { model.onboardingOpen = false } }
        .sheet(isPresented: $equipmentOpen) { EquipmentSheet(equipment: $p.equipment) }
        .sheet(isPresented: $zonesOpen) { EquipmentSheet(equipment: $p.equipment, layout: $p.gymLayout) }
        .sheet(isPresented: $floorPlanOpen) {
            FloorPlanSheet(layout: Binding(get: { p.gymLayout ?? .starter }, set: { p.gymLayout = $0 }), equipment: p.equipment)
        }
    }

    // MARK: Header and bottom

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(step.title).font(Theme.display(32)).foregroundStyle(.white)
                Spacer()
                if !single || step == .tour {
                    Button(step == .tour ? "Skip tour" : "Skip") { skip() }
                        .font(Theme.label(15)).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("onboarding.skip")
                }
            }
            if !single {
                HStack(spacing: 10) {
                    // Back (#822, design A from `full-app-audit-3/mockups/proposals-6.png`): steps 2–4 go to the step
                    // before, answers kept.
                    if let previous {
                        Button { withAnimation(.snappy) { step = previous } } label: {
                            Text("‹ Back").font(Theme.label(15)).foregroundStyle(Theme.lime)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to \(previous.title)")
                        .accessibilityIdentifier("onboarding.back")
                    }
                    HStack(spacing: 4) {
                        ForEach(steps) { s in
                            Capsule().fill(s.number <= step.number ? Theme.lime : Color.white.opacity(0.14)).frame(height: 6)
                        }
                    }
                }
                Text("Step \(step.number) of \(steps.count) · \(subtitle)")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            } else {
                Text(subtitle).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, isNew ? 12 : 0)
        .padding(.bottom, 10)
    }

    /// The step Back returns to: on steps 2–4 of the guided flow (#822); the plan is made once the tour starts.
    private var previous: OnboardingStep? {
        guard !single, (2...4).contains(step.number) else { return nil }
        return steps[step.number - 2]
    }

    private var subtitle: String {
        switch step {
        case .gym: p.gym == nil ? "pick yours: near me, by name or home" : "the plan is built for it"
        case .machines: "tick what \(p.gym?.name ?? "your gym") has"
        case .map: "optional · supersets stay in one zone"
        case .plan: "build your own or follow a programme"
        case .tour: "one minute round the app"
        }
    }

    @ViewBuilder private var bottom: some View {
        if step != .tour {
            Button { next() } label: { Text(nextTitle).lineLimit(1).minimumScaleFactor(0.7) }
                .buttonStyle(LimeButtonStyle())
                .accessibilityIdentifier("onboarding.next")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .readableColumn()
                .background(Theme.bg.opacity(0.92).ignoresSafeArea())
        }
    }

    private var nextTitle: String {
        if step == .plan {
            if let programme { return "START \(programme.name.uppercased())" }
            return keepPlan ? (single ? "DONE" : "KEEP MY PLAN") : "BUILD MY PLAN"
        }
        if single { return "DONE" }
        return "NEXT · \((step.next ?? .tour).title.uppercased())"
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .gym:
            GymPicker(profile: $p, openAdd: isNew)
        case .machines:
            machines
        case .map:
            map
        case .plan:
            plan
        case .tour:
            tour
        }
    }

    private var machines: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { equipmentOpen = true } label: {
                bigCard(symbol: "dumbbell.fill", title: "Tick your machines", line: "Pictures of every machine, rack and bench. Tap what's there.",
                        number: "\(p.equipment.count)", unit: "ITEMS · \(AppModel.machineCount(p.equipment)) MACHINES", category: .strength)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.machines")
            Text("Every exercise in your plan needs what you tick here. Change it any time in Your gym.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    private var map: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { zonesOpen = true } label: {
                bigCard(symbol: "square.grid.3x3.fill", title: "Zones", line: "Paint each machine into the part of the gym it sits in.",
                        number: "\(p.gymLayout?.zones.count ?? 0)", unit: "ZONES", category: .cardio)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.zones")
            Button { floorPlanOpen = true } label: {
                bigCard(symbol: "map.fill", title: "Floor plan", line: "Place the zones: blocks that touch count as next to each other.",
                        number: p.gymLayout?.hasPlan == true ? "✓" : "–", unit: "PLAN", category: .strength)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.floorPlan")
            Text("Supersets and circuits then stay in one zone, so you don't cross the gym between sets.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isNew {
                Button { programme = nil; keepPlan = true } label: {
                    bigCard(symbol: "checkmark.circle.fill", title: "Keep my plan", line: "Your week as it is, with this gym.",
                            number: nil, unit: nil, category: .stretch)
                        .overlay { picked(keepPlan && programme == nil) }
                }
                .buttonStyle(.plain)
            }
            // Say it once (#873, design B from `ai-epic/a3.png`): Coach fills the plan in from one sentence.
            Button { talking = true } label: {
                bigCard(symbol: "mic.fill", title: "Tell Coach your goal", line: "Say it once in your own words. Coach fills in your plan, you fix and build.",
                        number: "🐵", unit: nil, category: .cardio)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.coachPlan")
            Button { programme = nil; keepPlan = false } label: {
                bigCard(symbol: "bolt.fill", title: "Build my plan", line: "Goal, days, session flow and method. Made for your gym.",
                        number: nil, unit: nil, category: .power)
                    .overlay { picked(!keepPlan && programme == nil) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.build")
            Text("OR A PROGRAMME").eyebrow().padding(.top, 6)
            ForEach(Self.programmes, id: \.id) { prog in
                Button { programme = prog } label: {
                    ProgrammeCard(programme: prog).overlay { picked(programme?.id == prog.id) }
                }
                .buttonStyle(.plain)
            }
            Text("More programmes, Snow ready and Hyrox in Explore → Programmes.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    /// Programmes that start in one tap (no race days, first day on snow or check-in to fill in first).
    static var programmes: [Programme] {
        ["strength-foundation", "muscle-builder", "climbers-power", "athletic-engine"].compactMap { Programme.find($0) }
    }

    private var tour: some View {
        VStack(spacing: 18) {
            Text("🐵").font(.system(size: 88)).padding(.top, 20)
            Text("Want me to show you round?").font(Theme.display(26)).multilineTextAlignment(.center)
            // The names the tabs and the tour bubbles use (#822).
            // Pick your tabs (#1004 C): tap a tab you won't use to hide it; Settings → My tabs brings it back.
            Text("Tap a tab you won't use to hide it. Run the tour again any time in Settings → Onboarding.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(AppTour.all) { s in tourRow(s) }
            }
            Button { startTour() } label: { Text("SHOW ME ROUND") }
                .buttonStyle(LimeButtonStyle())
                .accessibilityIdentifier("onboarding.tour")
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    // MARK: Pieces

    /// A tour stop; hideable tabs toggle on tap (#1004 C), Train and Coach stay.
    private func tourRow(_ s: AppTourStep) -> some View {
        let tab = s.tab.flatMap { TabsPref.hideable.contains($0) ? $0 : nil }
        let on = tab.map(tabsPref.shows) ?? true
        return Button {
            guard let tab else { return }
            withAnimation(.snappy) { tabsPref.set(tab, shown: !on) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: s.symbol).font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                Text(s.title).font(Theme.display(17)).strikethrough(!on)
                Spacer()
                if tab != nil {
                    Image(systemName: on ? "eye.fill" : "eye.slash.fill").font(.subheadline.weight(.bold))
                }
            }
            .foregroundStyle(on ? s.category.ink : Theme.muted)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(on ? AnyShapeStyle(s.category.gradient) : AnyShapeStyle(Color.white.opacity(0.08))))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(tab == nil)
        .accessibilityLabel(tab == nil ? s.title : "\(s.title), \(on ? "shown" : "hidden")")
        .accessibilityHint(tab == nil ? "" : "Shows or hides this tab")
        .accessibilityIdentifier("onboarding.tab.\(s.id)")
    }

    /// Explore-style card: icon tile left, title and line, big number right.
    private func bigCard(symbol: String, title: String, line: String, number: String?, unit: String?,
                         category: WorkoutEngine.Category) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.7)
                Text(line).font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(3)
            }
            Spacer(minLength: 4)
            if let number {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(number).font(Theme.display(30)).monospacedDigit()
                    if let unit { Text(unit).font(Theme.label(9)).tracking(1.2).opacity(0.8) }
                }
                .fixedSize()
            }
        }
        .foregroundStyle(category.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(category.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder private func picked(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.lime, lineWidth: 4)
        }
    }

    // MARK: Actions

    private func next() {
        switch step {
        case .plan:
            if let programme { finishPlan(p, programme: programme) } else if keepPlan { finishPlan(nil) } else { building = true }
            return
        case .gym, .machines, .map:
            saveGym()
            markDone(step)
        case .tour:
            break
        }
        advance()
    }

    private func skip() {
        switch step {
        case .plan:
            // A new member can't go on without a plan: the draft as it is becomes the starter plan.
            if isNew {
                makeFirstPlan(p, programme: nil, planDone: false)
            }
            advance()
        case .tour:
            endWithoutTour()
        default:
            advance()
        }
    }

    private func advance() {
        if single { return close() }
        if let n = step.next { withAnimation(.snappy) { step = n } }
    }

    private func markDone(_ s: OnboardingStep) {
        if model.profile != nil, !isNew { model.completeOnboarding(s) } else if !done.contains(s) { done.append(s) }
    }

    /// Settings re-run or a single step: gym, machines and zones are kept as soon as the step is done.
    private func saveGym() {
        guard !isNew, model.profile != nil else { return }
        model.editGym(p)
        model.setGymLayout(p.gymLayout)
    }

    /// `made` = a profile from the plan form; nil = keep the plan as it is.
    private func finishPlan(_ made: Profile?, programme: Programme? = nil) {
        building = false
        if isNew {
            makeFirstPlan(made ?? p, programme: programme, planDone: true)
        } else {
            if let made { model.updateProfile(made); p = made }
            if let programme { model.startProgramme(programme) }
            model.completeOnboarding(.plan)
        }
        advance()
    }

    /// The first plan: the profile is saved, the steps done so far recorded, the rest wait on the set-up card.
    private func makeFirstPlan(_ profile: Profile, programme: Programme?, planDone: Bool) {
        model.applyProfile(profile)
        if let programme { model.startProgramme(programme) }
        // New accounts start on this release: no "What's new" for them (#183).
        WhatsNew.markSeen()
        // Pro (#126): one offer after the first plan, skippable; now once the tour is over.
        model.proAfterTour = ProStore.shared.badged
        model.startOnboarding(done: done + (planDone ? [.plan] : []))
    }

    private func startTour() {
        if !isNew { onClose() }
        model.startTour()
    }

    private func endWithoutTour() {
        if isNew {
            model.onboardingOpen = false
            if model.proAfterTour {
                model.proAfterTour = false
                model.offerPro = true
            }
        } else {
            close()
        }
    }

    private func close() {
        if !isNew { saveGym() }
        onClose()
    }
}

/// Train set-up card (#664, design B): the onboarding steps not done yet, each one tap away; ✕ (the notice slot's)
/// hides it, Settings → Onboarding keeps them.
struct SetupCard: View {
    let progress: OnboardingProgress
    @Environment(AppModel.self) private var model
    @State private var open: OnboardingStep?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Finish set-up").font(Theme.display(22))
                Spacer()
                Text("\(OnboardingStep.allCases.count - progress.later.count) / \(OnboardingStep.allCases.count)")
                    .font(Theme.display(18)).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.2))
                    Capsule().fill(Theme.ink).frame(width: g.size.width * progress.fraction)
                }
            }
            .frame(height: 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(progress.later) { s in
                    Button { tap(s) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: s.symbol).font(.system(size: 13, weight: .bold))
                            Text(s.short).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right").font(.caption.bold()).opacity(0.8)
                        }
                        .foregroundStyle(s.category.ink)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(s.category.gradient))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup.\(s.rawValue)")
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [Theme.lime, Color(hex: 0x1ED98A)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .sheet(item: $open) { s in
            OnboardingFlowView(mode: .single(s), profile: model.profile) { open = nil }
        }
    }

    private func tap(_ s: OnboardingStep) {
        if s == .tour { model.startTour() } else { open = s }
    }
}

/// Settings → You → Onboarding (#664): run it all again or one step; steps not done read "Later".
struct OnboardingHubView: View {
    @Environment(AppModel.self) private var model
    @State private var rerun = false
    @State private var open: OnboardingStep?
    @State private var fuel = false
    @State private var fuelStore = FuelStore.shared

    private var progress: OnboardingProgress? { model.onboarding }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button { rerun = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 22, weight: .bold))
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Run it all again").font(Theme.display(21))
                            Text("Gym, machines, map, plan and the tour, each one skippable.")
                                .font(.footnote.weight(.semibold)).opacity(0.8)
                        }
                        Spacer(minLength: 4)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.lime, Color(hex: 0x1ED98A)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.rerun")

                Text("OR ONE STEP").eyebrow().padding(.top, 6)
                ForEach(OnboardingStep.allCases) { s in
                    Button { if s == .tour { model.startTour() } else { open = s } } label: { row(s) }
                        .buttonStyle(.plain)
                }
                // Fuel set-up (#686): left for later from the Set up Fuel card.
                Button { fuel = true } label: { fuelRow }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.fuel")

                if let progress, !progress.finished {
                    Toggle(isOn: Binding(get: { !progress.cardHidden }, set: { model.hideSetupCard(!$0) })) {
                        Text("Set-up card on Train").font(.subheadline.weight(.semibold))
                    }
                    .tint(Theme.lime)
                    .padding(14)
                    .card(padding: 0)
                    .padding(.top, 6)
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Onboarding")
        .fullScreenCover(isPresented: $rerun) {
            OnboardingFlowView(mode: .rerun, profile: model.profile) { rerun = false }
        }
        .sheet(item: $open) { s in
            OnboardingFlowView(mode: .single(s), profile: model.profile) { open = nil }
        }
        .sheet(isPresented: $fuel) { NavigationStack { FuelSetupView(sheet: true) } }
    }

    private var fuelRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
            Text("Fuel").font(Theme.display(19)).lineLimit(1)
            Spacer(minLength: 4)
            Text(fuelStore.saved.setUp ? "DONE ✓" : "LATER")
                .font(Theme.label(11)).tracking(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.18)))
            Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
        }
        .foregroundStyle(Theme.ink)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.lime))
    }

    private func row(_ s: OnboardingStep) -> some View {
        let isDone = progress?.isDone(s) ?? false
        return HStack(spacing: 14) {
            Image(systemName: s.symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
            Text(s.title).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(isDone ? "DONE ✓" : progress == nil ? "OPEN" : "LATER")
                .font(Theme.label(11)).tracking(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.18)))
            Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
        }
        .foregroundStyle(s.category.ink)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(s.category.gradient))
    }
}

/// App tour (#664, design C): the tab behind is the one explained; one gradient bubble per stop, Next / Skip.
struct AppTourOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let i = model.tourStep, AppTour.steps.indices.contains(i) {
            let s = AppTour.steps[i]
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .contentShape(Rectangle())
                    // Only NEXT moves on (#822): a stray tap on the dim layer skipped stops. It still keeps taps off the tabs.
                    .onTapGesture {}
                VStack(alignment: .leading, spacing: 10) {
                    Text("🐵").font(.system(size: 44))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: s.symbol).font(.system(size: 18, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                            Text(s.title).font(Theme.display(24))
                        }
                        Text(s.text).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        tabs(current: s)
                        HStack {
                            Text("\(i + 1) / \(AppTour.steps.count)").font(Theme.label(13)).monospacedDigit()
                            Button("Skip tour") { model.endTour(finished: false) }
                                .font(Theme.label(13))
                                .accessibilityIdentifier("tour.skip")
                            Spacer()
                            Button { model.nextTourStep() } label: {
                                Text(i + 1 == AppTour.steps.count ? "DONE" : "NEXT")
                                    .font(Theme.label(14)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 18).padding(.vertical, 10)
                                    .background(Capsule().fill(.white))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tour.next")
                        }
                    }
                    .foregroundStyle(s.category.ink)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(s.category.gradient))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .frame(maxWidth: 520)
                .id(s.id)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .animation(.snappy, value: i)
        }
    }

    /// The five tabs in a row with the one explained lit (the real tab bar sits under the dim layer).
    private func tabs(current: AppTourStep) -> some View {
        HStack(spacing: 4) {
            ForEach(AppTour.steps.filter { $0.id != "coach" }) { t in
                Image(systemName: t.symbol).font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(t.id == current.id ? Color.white.opacity(0.9) : Color.black.opacity(0.15)))
                    .foregroundStyle(t.id == current.id ? Theme.ink : current.category.ink)
            }
        }
    }
}
