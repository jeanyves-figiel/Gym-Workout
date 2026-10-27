import SwiftUI
import WorkoutEngine

/// Side the Explore figure faces (Front / Side / Back snaps; 2D has front and back only).
enum BodyMapFacing: String, CaseIterable, Identifiable {
    case front = "Front", side = "Side", back = "Back"
    var id: String { rawValue }
    var yaw: Double { switch self { case .front: 0; case .side: -65; case .back: 180 } }
}

/// Explore → Muscles hero (#516, design C): the figure on a gradient card, left; this week's most worked muscles
/// and the one that needs work, right. Tapping a muscle on the figure swaps the right column for its card.
struct MuscleHero: View {
    let heat: [Muscle: Double]
    let onOpen: (Muscle) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.bodyMapDemo) private var demo
    @AppStorage(BodyMapMode.storageKey) private var storedMode = BodyMapMode.flat
    @AppStorage(MachineFilterStore.key) private var machineFilter = MachineFilter.all.key
    @State private var picked: Muscle?
    @State private var facing: BodyMapFacing = .front

    private var mode: BodyMapMode { demo?.mode ?? storedMode }
    private var facings: [BodyMapFacing] { mode == .solid ? BodyMapFacing.allCases : [.front, .back] }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                figure
                    .frame(width: 140, height: 300)
                rightColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack(spacing: 8) {
                facingPicker
                Spacer(minLength: 0)
                BodyMapModeToggle(selection: $storedMode, current: mode)
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(LibraryView.Mode.muscles.gradient))
        .onAppear {
            if let demo {
                picked = demo.picked
                facing = demo.facing
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            ForEach(Muscle.allCases) { m in
                Button(m.name) { onOpen(m) }
            }
        }
    }

    private func pick(_ m: Muscle) {
        withAnimation(.spring(duration: 0.3)) { picked = m }
    }

    @ViewBuilder private var figure: some View {
        if mode == .solid {
            // No "52,857 vertices" debug caption under the figure (#823).
            BodyMap3DView(heat: heat, selected: picked, yaw: facing.yaw, onTap: pick)
        } else {
            BodyMapView(side: facing == .back ? .back : .front, heat: heat, selected: picked,
                        showLabel: false, onColor: true, onTap: pick)
        }
    }

    // MARK: Right column

    @ViewBuilder private var rightColumn: some View {
        if let m = picked {
            pickedCard(m)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            summary
        }
    }

    /// Most worked (top 3 by this week's sets) and the tracked muscle with the fewest sets.
    @ViewBuilder private var summary: some View {
        let sets = Dictionary(uniqueKeysWithValues: Muscle.allCases.map { ($0, model.weeklySets(for: $0)) })
        let top = Muscle.allCases.filter { sets[$0, default: 0] > 0 }
            .sorted { sets[$0, default: 0] > sets[$1, default: 0] }
            .prefix(3)
        let low = VolumeTargets.tracked.filter { !top.contains($0) }
            .min { sets[$0, default: 0] < sets[$1, default: 0] }
        VStack(alignment: .leading, spacing: 6) {
            if top.isEmpty {
                label("This week")
                Text("No sets planned yet").font(Theme.display(18)).fixedSize(horizontal: false, vertical: true)
                Text("Tap a muscle to see its exercises").font(.footnote.weight(.semibold)).opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                label("Most worked")
                ForEach(Array(top)) { m in row(m, sets: sets[m, default: 0], strong: true) }
                if let low {
                    label("Needs work").padding(.top, 4)
                    row(low, sets: sets[low, default: 0], strong: false)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.label(10)).tracking(1.6).textCase(.uppercase).opacity(0.85)
    }

    private func row(_ m: Muscle, sets: Int, strong: Bool) -> some View {
        Button { onOpen(m) } label: {
            HStack(spacing: 8) {
                MuscleThumbnail(muscle: m, heat: heat[m] ?? 0)
                    .frame(width: 30, height: 30)
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.22)))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(m.name).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text("\(sets)").font(Theme.display(20)).monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(strong ? Color.white.opacity(0.18) : Color.black.opacity(0.22)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m.name), \(sets) sets this week")
    }

    /// The muscle tapped on the figure: name, sets, exercises, and a button to its page.
    private func pickedCard(_ m: Muscle) -> some View {
        let h = heat[m] ?? 0
        // Same count as the muscle page's list (chip filter, variations folded).
        let n = Exercise.rowCount(m, filter: MachineFilter(key: machineFilter), gym: model.exploreGym)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                MuscleThumbnail(muscle: m, heat: h)
                    .frame(width: 48, height: 48)
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.3)) { picked = nil }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
            Text(m.name).font(Theme.display(22)).lineLimit(2).minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(h >= 0.75 ? "Main mover this week" : h > 0 ? "Assist this week" : "Not this week")
                .font(.caption.weight(.semibold)).opacity(0.9)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                stat("\(model.weeklySets(for: m))", "SETS")
                stat("\(n)", "EXERCISES")
            }
            Spacer(minLength: 0)
            Button { onOpen(m) } label: {
                HStack(spacing: 6) {
                    Text("See exercises").font(Theme.label(14))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(m.name), open exercises")
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(height: 300)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(m.group.gradient))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.display(24)).monospacedDigit()
            Text(unit).font(Theme.label(9)).tracking(1).opacity(0.85)
        }
    }

    // MARK: Controls

    private var facingPicker: some View {
        HStack(spacing: 2) {
            ForEach(facings) { f in
                let on = f == facing || (f == .front && facing == .side && mode != .solid)
                Button {
                    withAnimation(.snappy(duration: 0.25)) { facing = f }
                } label: {
                    Text(f.rawValue).font(Theme.label(12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(on ? Theme.ink : .white.opacity(0.8))
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Color.white : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
        .sensoryFeedback(.selection, trigger: facing)
    }
}

/// Square gradient tiles under the machine chips: one per muscle group, jump to its cards (#516).
struct MuscleGroupJump: View {
    let groups: [MuscleGroup]
    let onJump: (MuscleGroup) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(groups) { g in
                    Button { onJump(g) } label: {
                        Label(g.label, systemImage: g.symbol)
                            .font(Theme.label(13))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(g.gradient))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }
}
