import SwiftUI
import WorkoutEngine

// Explore by machine (#456, design A + C from `explore-by-machine/proposals.png`):
// A · Explore → Machines: a gradient card per machine, grouped by area of the gym, opening its exercises.
// C · machine chips on Explore → Muscles and the muscle page: muscle × machine in one view.

extension AppModel {
    /// The member's gym equipment for the machine filters; nil when the gym isn't set up (nothing hidden).
    var exploreGym: Set<Equipment>? {
        guard let eq = profile?.equipment, !eq.isEmpty else { return nil }
        return Set(eq)
    }
}

/// Remembered machine chip (Explore → Muscles and every muscle page share it).
enum MachineFilterStore {
    static let key = "explore.machineFilter"
}

/// Chip row: My gym pinned on the left (#662) · All · Barbells · Dumbbells · Cables · Machines · Bars & rings · Functional ·
/// Body weight sliding under it.
struct MachineChips: View {
    @AppStorage(MachineFilterStore.key) private var stored = MachineFilter.all.key

    var body: some View {
        let current = MachineFilter(key: stored)
        HStack(spacing: 8) {
            GymChipTile(on: current == .gym) {
                withAnimation(.snappy(duration: 0.25)) { stored = (current == .gym ? MachineFilter.all : .gym).key }
            }
            .zIndex(1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MachineFilter.chips.filter { $0 != .gym }, id: \.key) { f in
                        let on = f == current
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { stored = (on && f != .all ? MachineFilter.all : f).key }
                        } label: {
                            HStack(spacing: 5) {
                                Text(f.label)
                                if on && f != .all { Image(systemName: "xmark").font(.system(size: 10, weight: .heavy)) }
                            }
                            .font(Theme.label(13))
                            .foregroundStyle(on ? Theme.ink : .white)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? Color.clear : Theme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 1)
            }
            // Chips slide under the pinned tile, fading in at its edge.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .sensoryFeedback(.selection, trigger: stored)
    }
}

/// Explore → Machines: areas of the gym, each with its machines as gradient cards.
struct MachinesSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage("explore.machines.myGym") private var onlyMine = false

    var body: some View {
        let gym = model.exploreGym
        VStack(alignment: .leading, spacing: 20) {
            if gym != nil {
                Toggle(isOn: $onlyMine) {
                    Label("Only what's in my gym", systemImage: "mappin.and.ellipse").font(.body.weight(.bold))
                }
                .tint(Theme.lime)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            }
            ForEach(GymArea.allCases) { area in
                let items = area.browsable().filter { !onlyMine || gym?.contains($0.item) ?? true }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(area.label) · \(items.count)").eyebrow()
                        ForEach(items, id: \.item) { row in
                            NavigationLink(value: row.item) {
                                MachineCard(item: row.item, area: area, count: row.count, have: gym?.contains(row.item))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// Picture of the machine in use, name, what it trains, and its exercise count on the right.
private struct MachineCard: View {
    let item: Equipment
    let area: GymArea
    let count: Int
    /// nil = gym not set up.
    let have: Bool?

    var body: some View {
        HStack(spacing: 14) {
            ExerciseImage(exercise: Exercise.get(item.pictureExerciseId))
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 2))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.label).font(Theme.display(19)).lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                let trains = Exercise.muscles(using: item).prefix(3).map(\.name).joined(separator: " · ")
                if !trains.isEmpty {
                    Text(trains).font(Theme.label(11)).opacity(0.9).lineLimit(1)
                }
                if have == true {
                    Label("In your gym", systemImage: "checkmark.circle.fill")
                        .font(Theme.label(10)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(count)").font(Theme.display(30)).monospacedDigit()
                Text(count == 1 ? "exercise" : "exercises").font(Theme.label(10)).opacity(0.85)
            }
            .lineLimit(1)
            .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(area.category.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Machine page: picture, where it is and how to adjust it, what it trains, and every exercise using it.
struct MachineDetailView: View {
    let item: Equipment
    @Environment(AppModel.self) private var model
    @State private var open: ExerciseRef?

    var body: some View {
        let _ = model.customExercises.count
        let area = GymArea.allCases.first { $0.items.contains(item) }
        let gradient = area?.category.gradient ?? WorkoutEngine.Category.strength.gradient
        let muscles = Exercise.muscles(using: item)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    ExerciseImage(exercise: Exercise.get(item.pictureExerciseId))
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    if let area { Text(area.label.uppercased()).font(Theme.label(11)).tracking(2).opacity(0.85) }
                    Text(item.label).font(Theme.display(34))
                    Text(item.adjustment).font(.body.weight(.medium)).opacity(0.9).fixedSize(horizontal: false, vertical: true)
                    if let have = model.exploreGym.map({ $0.contains(item) }) {
                        Label(have ? "In your gym" : "Not in your gym", systemImage: have ? "checkmark.circle.fill" : "xmark.circle")
                            .font(Theme.label(12))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.22)))
                    }
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(gradient))

                if !muscles.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Trains").eyebrow()
                        HStack(spacing: 12) {
                            BodyMapPair(heat: Dictionary(uniqueKeysWithValues: muscles.prefix(6).enumerated()
                                .map { ($0.element, $0.offset < 3 ? 1.0 : 0.5) }))
                                .frame(height: 200)
                            FlowLayout(spacing: 6) {
                                ForEach(muscles.prefix(6), id: \.self) { m in
                                    NavigationLink(value: m) {
                                        Text(m.name).font(Theme.label(12)).foregroundStyle(.white)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Capsule().fill(m.group.gradient))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                    }
                }

                NewExerciseButton(prefill: CustomExercise(equipment: [item]))
                ForEach(Exercise.using(item, byCategory: .shared), id: \.0) { category, list in
                    GradientSection(symbol: category.symbol, title: category.label, gradient: category.gradient, ink: category.ink) {
                        ForEach(Exercise.folded(list), id: \.exercise.id) { family in
                            let ex = family.exercise
                            Button { open = ExerciseRef(exerciseId: ex.id) } label: {
                                HStack(spacing: 12) {
                                    ExerciseThumbnail(exercise: ex, size: 48)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                                        Text(ex.primary.prefix(2).map(\.name).joined(separator: " · "))
                                            .font(.caption.weight(.semibold)).opacity(0.85)
                                        VariationCount(count: family.variations.count, color: .white.opacity(0.85))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).opacity(0.8)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Machine")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { ref in NavigationStack { ExerciseDetailView(exerciseId: ref.exerciseId) } }
    }
}
