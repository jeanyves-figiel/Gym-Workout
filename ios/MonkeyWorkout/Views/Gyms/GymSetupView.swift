import APIClient
import SwiftUI
import WorkoutEngine

// New gym in under a minute (#162): what members already found there (gym memory), or a place type and one swipe
// card per area of the gym, ordered by what the plan uses most. The picture list stays one tap away to fine-tune.

extension GymKind {
    var symbol: String {
        switch self {
        case .hotel: "bed.double.fill"
        case .home: "house.fill"
        case .budget: "bolt.fill"
        case .bigClub: "building.2.fill"
        case .box: "shippingbox.fill"
        case .park: "tree.fill"
        }
    }

    var category: WorkoutEngine.Category {
        switch self {
        case .hotel: .cardio
        case .home: .warmup
        case .budget: .power
        case .bigClub: .strength
        case .box: .mobility
        case .park: .stretch
        }
    }
}

struct GymSetupView: View {
    enum Step { case kind, swipe, result }

    /// Place picked on the map; nil = a gym without one (home, hotel room), named on the last step.
    let ref: GymRef?
    /// Main button on the last step ("USE THIS GYM", "USE FOR THIS TRIP").
    let actionTitle: String
    let onDone: (SavedGym) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var kind: GymKind?
    @State private var answers: [GymArea: ZoneAnswer] = [:]
    @State private var order: [GymArea] = GymArea.allCases
    @State private var index = 0
    @State private var known: KnownGym?
    @State private var source: String?
    @State private var equipment: [Equipment] = []
    @State private var unsure: [Equipment] = []
    @State private var name: String
    @State private var drag: CGSize = .zero
    @State private var showEquipment = false

    init(ref: GymRef?, name: String = "", actionTitle: String, startStep: Step = .kind, startKind: GymKind? = nil,
         onDone: @escaping (SavedGym) -> Void) {
        self.ref = ref
        self.actionTitle = actionTitle
        self.onDone = onDone
        _step = State(initialValue: startStep)
        _kind = State(initialValue: startKind)
        _name = State(initialValue: ref?.name ?? name)
        if let k = startKind {
            _answers = State(initialValue: k.guess)
            let r = GymSetup.equipment(k.guess)
            _equipment = State(initialValue: r.equipment)
            _unsure = State(initialValue: r.unsure)
        }
        if startStep == .swipe { _index = State(initialValue: 2) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .kind: kindStep
                case .swipe: swipeStep
                case .result: resultStep
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
                if step != .kind {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { back() } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Back")
                    }
                }
            }
            .sheet(isPresented: $showEquipment) { EquipmentSheet(equipment: $equipment, unsure: unsure) }
            .task {
                if step == .swipe { order = GymSetup.order(for: model.plan) }
                if let ref { known = await model.knownGym(ref) }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(duration: 0.35), value: step)
        .animation(.spring(duration: 0.35), value: index)
    }

    private var title: String {
        switch step {
        case .kind: ref?.name ?? "New gym"
        case .swipe: "\(kind?.label ?? "Gym") · \(min(index + 1, order.count)) of \(order.count)"
        case .result: "Ready"
        }
    }

    // MARK: Place type

    private var kindStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let place = known?.place {
                    memoryCard(place, title: "Known gym", line: "Set up by \(members(place.members)) · \(place.equipment.count) items",
                               source: "From \(members(place.members))")
                }
                if let chain = known?.chain {
                    memoryCard(chain, title: "\((chain.name ?? "Chain").capitalized) template",
                               line: "From \(members(chain.members)) at \(chain.gyms ?? 1) other \(chain.gyms == 1 ? "branch" : "branches")",
                               source: "\((chain.name ?? "Chain").capitalized) template")
                }
                Text(known?.place == nil && known?.chain == nil ? "What kind of place?" : "Or set it up yourself")
                    .font(Theme.display(26)).padding(.top, known == nil ? 0 : 8)
                Text("Then a few quick cards, one per area of the gym.").font(.subheadline).foregroundStyle(Theme.muted)
                ForEach(GymKind.allCases) { k in
                    Button { start(k) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: k.symbol)
                                .font(.system(size: 22, weight: .bold))
                                .frame(width: 50, height: 50)
                                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.22)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.label).font(Theme.display(19))
                                Text(k.blurb).font(.footnote.weight(.medium)).opacity(0.85)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(k.equipment.count)").font(Theme.display(24))
                                Text("ITEMS").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(k.category.gradient))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func members(_ n: Int) -> String { n == 1 ? "1 member" : "\(n) members" }

    private func memoryCard(_ t: GymTally, title: String, line: String, source: String) -> some View {
        Button { useMemory(t, source: source) } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(line).font(.footnote.weight(.medium)).opacity(0.85)
                }
                Spacer(minLength: 4)
                Text("USE").font(Theme.label(13)).tracking(1).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.lime))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(WorkoutEngine.Category.cardio.gradient))
        }
        .buttonStyle(.plain)
    }

    private func useMemory(_ t: GymTally, source: String) {
        let items = Set(t.equipment.compactMap(Equipment.init(rawValue:)) + GymArea.floor)
        equipment = Equipment.allCases.filter { items.contains($0) }
        unsure = []
        kind = nil
        self.source = source
        step = .result
    }

    private func start(_ k: GymKind) {
        kind = k
        answers = k.guess
        order = GymSetup.order(for: model.plan)
        index = 0
        source = nil
        step = .swipe
    }

    // MARK: Swipe cards

    private var swipeStep: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(order.indices, id: \.self) { i in
                    Capsule().fill(i <= index ? Theme.lime : Theme.stroke).frame(height: 4)
                }
            }
            if order.indices.contains(index) {
                ZStack {
                    if order.indices.contains(index + 1) {
                        areaCard(order[index + 1]).scaleEffect(0.94).offset(y: 14).opacity(0.5).allowsHitTesting(false)
                    }
                    areaCard(order[index])
                        .offset(x: drag.width, y: drag.height * 0.2)
                        .rotationEffect(.degrees(Double(drag.width) / 18))
                        .overlay(alignment: drag.width > 0 ? .topLeading : .topTrailing) { stamp }
                        .gesture(DragGesture()
                            .onChanged { drag = $0.translation }
                            .onEnded { v in
                                if v.translation.width > 110 { answer(.yes) } else if v.translation.width < -110 { answer(.no) }
                                else { withAnimation(.spring(duration: 0.3)) { drag = .zero } }
                            })
                        .id(order[index])
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                }
                .frame(maxHeight: .infinity)
            }
            HStack(spacing: 10) {
                answerButton("✕  NO", fill: Color.red.opacity(0.22), ink: Color(red: 1, green: 0.42, blue: 0.53)) { answer(.no) }
                answerButton("NOT SURE", fill: Theme.cardStrong, ink: Theme.muted) { answer(.unsure) }
                answerButton("✓  YES", fill: Theme.lime, ink: Theme.ink) { answer(.yes) }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var stamp: some View {
        if abs(drag.width) > 30 {
            Text(drag.width > 0 ? "YES" : "NO")
                .font(Theme.display(28))
                .foregroundStyle(drag.width > 0 ? Theme.lime : .red)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(drag.width > 0 ? Theme.lime : .red, lineWidth: 3))
                .rotationEffect(.degrees(drag.width > 0 ? -12 : 12))
                .padding(24)
                .opacity(min(1, abs(drag.width) / 110))
        }
    }

    private func areaCard(_ area: GymArea) -> some View {
        let uses = GymSetup.uses(area, in: model.plan)
        let usually = kind.map { $0.zones.contains(area) ? "Usually yes at a \($0.label.lowercased())" : "Usually not at a \($0.label.lowercased())" }
        return VStack(alignment: .leading, spacing: 12) {
            Image(systemName: area.symbol)
                .font(.system(size: 40, weight: .bold))
                .frame(width: 76, height: 76)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.22)))
            Text(area.question).font(Theme.display(34)).lineLimit(2).minimumScaleFactor(0.7)
            Text(area.covers).font(.subheadline.weight(.semibold)).opacity(0.9)
            // Three of its items as pictures, so the card is recognisable without knowing the names.
            HStack(spacing: 8) {
                ForEach(area.items.prefix(3)) { e in
                    ExerciseImage(exercise: Exercise.get(e.pictureExerciseId))
                        .frame(maxWidth: .infinity).frame(height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            Spacer(minLength: 0)
            if let usually { Text(usually).font(.footnote.weight(.semibold)).opacity(0.85) }
            Text(uses == 0 ? "NOT IN THIS WEEK'S PLAN" : "USED BY \(uses) EXERCISE\(uses == 1 ? "" : "S") IN YOUR PLAN")
                .font(Theme.label(11)).tracking(1.1).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: 520, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(area.category.gradient))
        .accessibilityElement(children: .combine)
    }

    private func answerButton(_ title: String, fill: Color, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(14)).foregroundStyle(ink)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }

    private func answer(_ a: ZoneAnswer) {
        guard order.indices.contains(index) else { return }
        answers[order[index]] = a
        drag = .zero
        if index + 1 < order.count {
            index += 1
        } else {
            let r = GymSetup.equipment(answers)
            equipment = r.equipment
            unsure = r.unsure
            step = .result
        }
    }

    private func back() {
        switch step {
        case .kind: break
        case .swipe:
            if index > 0 { index -= 1 } else { step = .kind }
        case .result:
            if kind == nil { step = .kind } else { index = order.count - 1; step = .swipe }
        }
    }

    // MARK: Result

    private var resultStep: some View {
        let misfits = GymSetup.misfits(model.plan, equipment: equipment)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .heavy))
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.3)))
                    VStack(alignment: .leading, spacing: 3) {
                        if ref == nil {
                            TextField("Name it (Home, Hotel Adlon…)", text: $name)
                                .font(Theme.display(20))
                                .submitLabel(.done)
                        } else {
                            Text(name).font(Theme.display(20)).lineLimit(2).minimumScaleFactor(0.7)
                        }
                        Text([source ?? kind?.label, unsure.isEmpty ? nil : "\(unsure.count) not sure"].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote.weight(.semibold)).opacity(0.85)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(equipment.count)").font(Theme.display(28))
                        Text("ITEMS").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                    }
                    .fixedSize()
                }
                .foregroundStyle(Theme.ink)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.stretch.gradient))

                Text("This week's plan").eyebrow().padding(.top, 4)
                VStack(alignment: .leading, spacing: 8) {
                    if misfits.isEmpty {
                        Label("Every planned exercise fits this gym", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold))
                    } else {
                        Text("\(misfits.count) exercise\(misfits.count == 1 ? "" : "s") get another pick here:")
                            .font(.subheadline.weight(.semibold))
                        ForEach(misfits.prefix(4)) { e in
                            HStack(spacing: 10) {
                                ExerciseThumbnail(exercise: e, size: 40)
                                Text(e.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                Spacer()
                                Text(e.missing(from: equipment).first?.label ?? "").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .card(padding: 14)

                Button { showEquipment = true } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled").foregroundStyle(Theme.lime)
                        Text("Fine-tune with pictures").bold()
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(.white)
                    .card(padding: 14)
                }
                .buttonStyle(.plain)

                Text(unsure.isEmpty ? "Something missing on the day? Tap \"Not here?\" on the exercise and it's fixed for next time."
                     : "Items you weren't sure about stay on. If one isn't there, tap \"Not here?\" on the exercise in your workout.")
                    .font(.footnote).foregroundStyle(Theme.muted)

                Button(actionTitle) {
                    let r = ref ?? SavedGym.customRef(name: trimmedName.isEmpty ? (kind?.label ?? "My gym") : trimmedName)
                    onDone(SavedGym(ref: r, kind: kind, equipment: equipment, unsure: unsure.filter { equipment.contains($0) }))
                    dismiss()
                }
                .buttonStyle(LimeButtonStyle())
                .padding(.top, 4)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
