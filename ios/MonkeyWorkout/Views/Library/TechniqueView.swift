import SwiftUI
import WorkoutEngine

extension Equipment {
    var symbol: String {
        switch self {
        case .dumbbells: "dumbbell.fill"
        case .kettlebells: "scalemass.fill"
        case .barbell, .trapBar, .rack, .smith, .landmine: "figure.strengthtraining.traditional"
        case .bench: "rectangle.split.3x1.fill"
        case .cable, .legPress, .hackSquat, .legCurl, .legExtension, .latPulldown, .seatedRow, .chestPress, .pecDeck,
             .hipThrustMachine, .backExtension, .seatedCalf, .hipAdAbductor, .abCrunch, .torsoRotation: "gearshape.fill"
        case .pullupBar, .dipStation: "figure.climbing"
        case .rings: "circle.circle"
        case .trx: "figure.strengthtraining.functional"
        case .plyoBox: "shippingbox.fill"
        case .medBall, .slamBall: "basketball.fill"
        case .sled: "arrow.right.to.line"
        case .battleRope: "water.waves"
        case .abWheel: "circle.circle.fill"
        case .bands: "lasso"
        case .foamRoller: "cylinder.fill"
        case .mat: "rectangle.fill"
        case .treadmill: "figure.run"
        case .bike, .airBike: "figure.indoor.cycle"
        case .rower: "figure.rower"
        case .skiErg: "figure.skiing.crosscountry"
        case .stairClimber: "figure.stair.stepper"
        case .elliptical: "figure.elliptical"
        }
    }
}

/// Compact equipment line for cards: icons + names.
struct EquipmentLine: View {
    let equipment: [Equipment]

    var body: some View {
        if equipment.isEmpty {
            Label("Bodyweight", systemImage: "figure.stand").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        } else {
            HStack(spacing: 10) {
                ForEach(equipment) { e in
                    Label(e.label, systemImage: e.symbol).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
        }
    }
}

/// Equipment cards: what, where in the gym, how to adjust.
struct EquipmentSection: View {
    let equipment: [Equipment]

    var body: some View {
        GradientSection(symbol: "dumbbell.fill", title: "Equipment", gradient: WorkoutEngine.Category.warmup.gradient) {
            if equipment.isEmpty {
                row(symbol: "figure.stand", title: "Bodyweight", zone: "Anywhere with space", text: "No equipment needed — a mat if you're on the floor.")
            }
            ForEach(equipment) { e in
                row(symbol: e.symbol, title: e.label, zone: e.zone.label, text: e.adjustment)
            }
        }
    }

    private func row(symbol: String, title: String, zone: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.headline, design: .rounded).weight(.heavy))
                Text(zone.uppercased()).font(Theme.label(10)).tracking(1).opacity(0.85)
                Text(text).font(.footnote.weight(.medium)).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Set up → body position → avoid → breathe, each on its own gradient card.
struct TechniqueView: View {
    let exercise: Exercise

    var body: some View {
        if let t = exercise.technique {
            VStack(alignment: .leading, spacing: 16) {
                setup(t)
                position(t)
                avoid(t)
                breathe(t)
            }
        } else {
            GradientSection(symbol: "text.bubble.fill", title: "Key cues", gradient: exercise.category.gradient) {
                ForEach(exercise.cues, id: \.self) { Text("• \($0)").font(.body.weight(.medium)) }
            }
        }
    }

    private func setup(_ t: Technique) -> some View {
        GradientSection(symbol: "list.number", title: "Set up", gradient: exercise.category.gradient) {
            ForEach(Array(t.setup.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(i + 1)")
                        .font(Theme.display(16))
                        .foregroundStyle(exercise.category.color)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white))
                    Text(step).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func position(_ t: Technique) -> some View {
        GradientSection(symbol: "figure.stand", title: "Body position", gradient: WorkoutEngine.Category.mobility.gradient) {
            ForEach(t.position, id: \.self) { c in
                CheckpointRow(checkpoint: c, accent: Color.white.opacity(0.8))
            }
            if !exercise.cues.isEmpty {
                Divider().overlay(Color.white.opacity(0.35))
                Text("Key cues: " + exercise.cues.joined(separator: " · "))
                    .font(.footnote.weight(.semibold))
                    .opacity(0.9)
            }
        }
    }

    private func avoid(_ t: Technique) -> some View {
        GradientSection(symbol: "xmark.octagon.fill", title: "Avoid", gradient: AccountTint.danger) {
            ForEach(t.mistakes, id: \.self) { m in
                Label {
                    Text(m).font(.body.weight(.medium))
                } icon: {
                    Image(systemName: "xmark").font(.body.weight(.heavy))
                }
            }
        }
    }

    private func breathe(_ t: Technique) -> some View {
        GradientSection(symbol: "wind", title: "Breathe", gradient: WorkoutEngine.Category.cardio.gradient) {
            Text(t.breathing).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CheckpointRow: View {
    let checkpoint: Checkpoint
    let accent: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(checkpoint.part.label.uppercased())
                .font(Theme.label(10))
                .tracking(1)
                .foregroundStyle(accent)
                .frame(width: 74, alignment: .leading)
            Text(checkpoint.cue).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Sheet used from the workout player: equipment + full technique.
struct FormSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(exercise.name).font(Theme.display(30))
                    EquipmentSection(equipment: exercise.equipment)
                    TechniqueView(exercise: exercise)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
