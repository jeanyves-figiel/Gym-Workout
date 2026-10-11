import SwiftUI
import WorkoutEngine

/// New workout builder (#119): entry card that opens the generator.
struct GenerateWorkoutCard: View {
    let regenerate: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconTile(symbol: "wand.and.stars", size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(regenerate ? "Generate again" : "Generate from muscles").font(Theme.display(20))
                            .lineLimit(1).minimumScaleFactor(0.75)
                        ProBadge()
                    }
                    Text("Pick muscles · rest & grouping from your goal")
                        .font(.footnote.weight(.semibold)).opacity(0.88)
                }
                Spacer(minLength: 4)
                AccountChevron()
            }
            .gradientCard(WorkoutEngine.Category.power.gradient, padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(regenerate ? "Generate again from muscles" : "Generate a workout from muscle groups")
    }
}

/// Generator sheet (#119): muscle groups, duration, rest between sets and grouping (goal defaults marked REC).
/// Exercises fit the training profile's equipment and level; the result opens in the builder to edit before saving.
struct MuscleWorkoutGeneratorSheet: View {
    let profile: Profile
    let replacing: Bool
    let onGenerate: (CustomWorkout, MuscleWorkoutOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options: MuscleWorkoutOptions
    @State private var nothingFits = false

    init(profile: Profile, options: MuscleWorkoutOptions?, replacing: Bool, onGenerate: @escaping (CustomWorkout, MuscleWorkoutOptions) -> Void) {
        self.profile = profile
        self.replacing = replacing
        self.onGenerate = onGenerate
        _options = State(initialValue: options ?? MuscleWorkoutOptions(profile: profile))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Generate workout").font(Theme.display(30))
                    Text("Exercises fit your equipment and level; sets and reps follow your goal. You can edit everything before saving.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)

                    Text("Muscles").eyebrow().padding(.top, 10)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(MuscleGroup.allCases) { g in groupTile(g) }
                    }

                    Text("Duration").eyebrow().padding(.top, 10)
                    HStack(spacing: 8) {
                        ForEach(MuscleWorkoutOptions.durations, id: \.self) { m in
                            Button { options.minutes = m } label: {
                                VStack(spacing: 0) {
                                    Text("\(m)").font(Theme.display(20)).monospacedDigit()
                                    Text("MIN").font(Theme.label(8)).tracking(1).opacity(0.85)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .selectableGradient(WorkoutEngine.Category.cardio.gradient, selected: options.minutes == m, cornerRadius: 16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(m) minutes")
                            .accessibilityAddTraits(options.minutes == m ? .isSelected : [])
                        }
                    }

                    Text("Rest between sets").eyebrow().padding(.top, 10)
                    ForEach(RestStyle.allCases) { r in
                        StyleCard(
                            title: r.label, subtitle: r.blurb, symbol: r.symbol, big: r.range, gradient: r.gradient,
                            selected: options.rest == r, recommended: profile.goal.defaultRest == r
                        ) { options.rest = r }
                    }

                    Text("Group exercises").eyebrow().padding(.top, 10)
                    ForEach(Grouping.allCases) { g in
                        StyleCard(
                            title: g.label, subtitle: g.blurb, symbol: g.symbol, big: g.size, gradient: g.gradient,
                            selected: options.grouping == g, recommended: profile.goal.defaultGrouping == g
                        ) { options.grouping = g }
                    }
                    Text("REC = best for your goal. Main lifts stay straight sets with at least 90 s rest.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)

                    if nothingFits {
                        Text("Nothing fits your equipment for these muscles. Pick other muscles or update your gym in the training profile.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.lime)
                    }

                    Button(action: generate) {
                        Label(replacing ? "Generate (replaces exercises)" : "Generate", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(options.groups.isEmpty)
                    .opacity(options.groups.isEmpty ? 0.5 : 1)
                    .padding(.top, 8)
                }
                .padding(16)
                .animation(.spring(duration: 0.3), value: options)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func groupTile(_ g: MuscleGroup) -> some View {
        let on = options.groups.contains(g)
        return Button {
            if on { options.groups.remove(g) } else { options.groups.insert(g) }
            nothingFits = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: g.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                    .overlay(alignment: .topTrailing) {
                        if on {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.ink, Theme.lime)
                                .offset(x: 6, y: -6)
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.label).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(g.muscles.prefix(3).map(\.name).joined(separator: " · "))
                        .font(.caption2.weight(.semibold)).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .selectableGradient(g.gradient, selected: on, cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(g.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func generate() {
        let w = CustomWorkout.generate(options, profile: profile, seed: UInt32.random(in: .min ... .max))
        guard !w.items.isEmpty else { nothingFits = true; return }
        onGenerate(w, options)
        dismiss()
    }
}

extension MuscleGroup {
    var symbol: String {
        switch self {
        case .shoulders: "figure.arms.open"
        case .chest: "figure.strengthtraining.traditional"
        case .arms: "dumbbell.fill"
        case .back: "figure.rower"
        case .core: "figure.core.training"
        case .hips: "figure.step.training"
        case .legs: "figure.run"
        }
    }

    var gradient: LinearGradient {
        let c: WorkoutEngine.Category = switch self {
        case .shoulders: .power
        case .chest: .strength
        case .arms: .warmup
        case .back: .mobility
        case .core: .cardio
        case .hips: .stretch
        case .legs: .strength
        }
        return c.gradient
    }
}
