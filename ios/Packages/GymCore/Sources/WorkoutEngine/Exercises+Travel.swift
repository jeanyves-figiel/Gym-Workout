// Travel kit exercises (#68): bodyweight, dumbbell-only and band versions of the main patterns, so sessions at a
// temporary location (hotel room, hotel gym) still train every pattern. Picked only with a travel kit
// (see `Selector.isTravelKit`), so plans at a full gym are unchanged.

extension Exercise {
    static let travelCatalog: [Exercise] = [
        Exercise(id: "bw-squat", name: "Bodyweight squat", category: .strength, pattern: .squat, primary: [.quads, .glutes], secondary: [.adductors], equipment: [], level: 1, secPerRep: 3, cues: ["3 s down, 1 s pause", "Full depth, heels down"], generator: false),
        Exercise(id: "bw-split-squat", name: "Split squat (bodyweight)", category: .strength, pattern: .singleLeg, primary: [.quads, .glutes], secondary: [.adductors], equipment: [], level: 1, unilateral: true, secPerRep: 3, cues: ["Back knee to floor", "Front shin vertical-ish"], generator: false),
        Exercise(id: "bw-reverse-lunge", name: "Reverse lunge (bodyweight)", category: .strength, pattern: .singleLeg, primary: [.quads, .glutes], equipment: [], level: 1, unilateral: true, secPerRep: 3, cues: ["Long step back", "Drive through front heel"], generator: false),
        Exercise(id: "sl-hip-thrust", name: "Single-leg hip thrust", category: .strength, pattern: .hinge, primary: [.glutes], secondary: [.hamstrings], equipment: [.mat], level: 1, unilateral: true, secPerRep: 3, cues: ["Shoulders on sofa or bed edge", "2 s squeeze at top"], generator: false),
        Exercise(id: "bw-sl-rdl", name: "Single-leg RDL (bodyweight)", category: .strength, pattern: .hinge, primary: [.hamstrings, .glutes], secondary: [.obliques], equipment: [], level: 1, unilateral: true, secPerRep: 4, cues: ["Hips square", "Slow 3 s lower"], generator: false),
        Exercise(id: "table-row", name: "Table inverted row", category: .strength, pattern: .hPull, primary: [.upperBack, .lats], secondary: [.biceps, .rearDelts], equipment: [], level: 2, secPerRep: 3, cues: ["Sturdy table only", "Chest to edge, body rigid"], generator: false),
        Exercise(id: "prone-pulldown", name: "Prone floor pulldown", category: .strength, pattern: .vPull, primary: [.lats, .upperBack], secondary: [.rearDelts], equipment: [.mat], level: 1, secPerRep: 3, cues: ["Arms overhead, lift off floor", "Pull elbows to ribs, squeeze 2 s"], generator: false),
        Exercise(id: "pike-push-up", name: "Pike push-up", category: .strength, pattern: .vPush, primary: [.frontDelts, .triceps], secondary: [.upperBack], equipment: [], level: 2, secPerRep: 3, cues: ["Hips high, head between hands", "Head to floor in a triangle"], generator: false),
        Exercise(id: "bw-calf-raise", name: "Single-leg calf raise", category: .strength, pattern: .calves, primary: [.calves], equipment: [], level: 1, unilateral: true, secPerRep: 3, cues: ["Full stretch at bottom", "1 s pause at top"], generator: false),
        Exercise(id: "db-bent-row", name: "Dumbbell bent-over row", category: .strength, pattern: .hPull, primary: [.upperBack, .lats], secondary: [.biceps, .rearDelts], equipment: [.dumbbells], level: 1, secPerRep: 3, main: true, cues: ["Hinge to 45°, flat back", "Elbows to hips"], generator: false),
        Exercise(id: "db-floor-press", name: "Dumbbell floor press", category: .strength, pattern: .hPush, primary: [.chest, .triceps], secondary: [.frontDelts], equipment: [.dumbbells], level: 1, secPerRep: 3, main: true, cues: ["Upper arms touch floor softly", "Elbows ~45°"], generator: false),
        Exercise(id: "db-standing-press", name: "Standing dumbbell press", category: .strength, pattern: .vPush, primary: [.frontDelts, .triceps], secondary: [.abs], equipment: [.dumbbells], level: 1, secPerRep: 3, main: true, cues: ["Glutes tight, ribs down", "Press to lockout by the ears"], generator: false),
        Exercise(id: "db-floor-pullover", name: "Dumbbell floor pullover", category: .strength, pattern: .vPull, primary: [.lats], secondary: [.chest, .triceps], equipment: [.dumbbells, .mat], level: 1, secPerRep: 3, cues: ["Ribs down", "Stop where the back would arch"], generator: false),
        Exercise(id: "band-row", name: "Band row", category: .strength, pattern: .hPull, primary: [.upperBack, .lats], secondary: [.biceps], equipment: [.bands], level: 1, secPerRep: 3, cues: ["Anchor at chest height", "Shoulder blades back first"], generator: false),
        Exercise(id: "band-pulldown", name: "Band lat pulldown", category: .strength, pattern: .vPull, primary: [.lats], secondary: [.biceps], equipment: [.bands], level: 1, secPerRep: 3, cues: ["Anchor high (door top)", "Elbows down to ribs"], generator: false),
        Exercise(id: "band-chest-press", name: "Band chest press", category: .strength, pattern: .hPush, primary: [.chest, .triceps], secondary: [.frontDelts], equipment: [.bands], level: 1, secPerRep: 3, cues: ["Band behind the back or anchored", "Press straight out"], generator: false),
        Exercise(id: "band-overhead-press", name: "Band overhead press", category: .strength, pattern: .vPush, primary: [.frontDelts, .triceps], equipment: [.bands], level: 1, secPerRep: 3, cues: ["Stand on the band", "Ribs down, press overhead"], generator: false),
        Exercise(id: "band-good-morning", name: "Band good morning", category: .strength, pattern: .hinge, primary: [.hamstrings, .glutes], secondary: [.lowerBack], equipment: [.bands], level: 1, secPerRep: 3, cues: ["Band under feet, over neck", "Hips back, flat back"], generator: false),
    ]

    /// Ids of the travel kit exercises.
    static let travelIds: Set<String> = Set(travelCatalog.map(\.id))
}

extension Selector {
    /// No barbell, cable or machine: a hotel room, hotel gym or a pair of dumbbells.
    static func isTravelKit(_ equipment: Set<Equipment>) -> Bool {
        let gym: Set<Equipment> = [.barbell, .cable, .smith, .legPress, .latPulldown, .seatedRow, .chestPress]
        return equipment.isDisjoint(with: gym)
    }
}
