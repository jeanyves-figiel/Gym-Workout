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
             .hipThrustMachine, .backExtension: "gearshape.fill"
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
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equipment").eyebrow()
            if equipment.isEmpty {
                row(symbol: "figure.stand", title: "Bodyweight", zone: "Anywhere with space", text: "No equipment needed — a mat if you're on the floor.")
            }
            ForEach(equipment) { e in
                row(symbol: e.symbol, title: e.label, zone: e.zone.label, text: e.adjustment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(symbol: String, title: String, zone: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.headline, design: .rounded).weight(.heavy))
                Text(zone.uppercased()).font(Theme.label(10)).tracking(1).foregroundStyle(Theme.lime)
                Text(text).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Set up → body position → avoid → breathe.
struct TechniqueView: View {
    let exercise: Exercise

    private var accent: Color { exercise.category.color }

    var body: some View {
        if let t = exercise.technique {
            VStack(alignment: .leading, spacing: 16) {
                setup(t)
                position(t)
                avoid(t)
                breathe(t)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Key cues").eyebrow()
                ForEach(exercise.cues, id: \.self) { Text("• \($0)") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func setup(_ t: Technique) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up").eyebrow()
            ForEach(Array(t.setup.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(i + 1)")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(accent))
                    Text(step).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func position(_ t: Technique) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Body position").eyebrow()
            ForEach(t.position, id: \.self) { c in
                CheckpointRow(checkpoint: c, accent: accent)
            }
            if !exercise.cues.isEmpty {
                Divider().overlay(Theme.stroke)
                Text("Key cues: " + exercise.cues.joined(separator: " · "))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func avoid(_ t: Technique) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Avoid").eyebrow()
            ForEach(t.mistakes, id: \.self) { m in
                Label {
                    Text(m).font(.body.weight(.medium))
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func breathe(_ t: Technique) -> some View {
        Label {
            Text(t.breathing).font(.body.weight(.medium))
        } icon: {
            Image(systemName: "wind").foregroundStyle(WorkoutEngine.Category.cardio.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
                    EquipmentSection(equipment: exercise.equipment, accent: exercise.category.color)
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
