import Foundation

// MARK: - New gym setup (#162)
//
// A gym is described by zones (barbells, cables, machine circuit…) instead of 43 single items: a place type
// guesses every zone, a few swipe cards confirm the zones that matter for the plan, and "not sure" items are
// kept until the member says otherwise in a workout ("Not here?").

/// An area of a gym; answering one card adds or removes all its items.
public enum GymArea: String, Codable, CaseIterable, Sendable, Identifiable {
    case barbells, dumbbells, cables, machines, stations, functional, cardio
    /// Climbing gym (#366): wall, hangboard, lifting blocks.
    case climbing
    public var id: String { rawValue }

    public var question: String {
        switch self {
        case .barbells: "Barbells & racks?"
        case .dumbbells: "Dumbbells & bench?"
        case .cables: "Cable tower?"
        case .machines: "Machine circuit?"
        case .stations: "Pull-up & dip bars?"
        case .functional: "Functional zone?"
        case .cardio: "Cardio machines?"
        case .climbing: "Climbing wall & hangboard?"
        }
    }

    public var label: String {
        switch self {
        case .barbells: "Barbells"
        case .dumbbells: "Dumbbells"
        case .cables: "Cables"
        case .machines: "Machines"
        case .stations: "Bars & rings"
        case .functional: "Functional"
        case .cardio: "Cardio"
        case .climbing: "Climbing"
        }
    }

    public var items: [Equipment] {
        switch self {
        case .barbells: [.barbell, .trapBar, .rack, .landmine, .ezBar]
        case .dumbbells: [.dumbbells, .bench, .preacherBench]
        case .cables: [.cable, .latPulldown, .seatedRow]
        case .machines: [.smith, .legPress, .hackSquat, .legCurl, .legExtension, .chestPress, .pecDeck, .hipThrustMachine,
                         .seatedCalf, .hipAdAbductor, .abCrunch, .torsoRotation, .shoulderPress, .standingCalf, .tBarRow,
                         .curlMachine, .tricepsMachine, .rowMachine, .backExtensionMachine, .squatMachine, .beltSquat,
                         .gluteMachine, .multiHip, .pulloverMachine]
        case .stations: [.pullupBar, .dipStation, .assistedMachine, .backExtension, .reverseHyper, .rings, .trx, .ghd, .stallBars]
        case .functional: [.kettlebells, .plyoBox, .medBall, .slamBall, .sled, .battleRope, .abWheel, .bands, .stabilityBall, .jumpRope, .dipBelt,
                           .sandbag, .sliders, .balanceTrainer, .massageBall]
        case .cardio: [.treadmill, .bike, .airBike, .rower, .skiErg, .stairClimber, .elliptical]
        case .climbing: [.climbingWall, .hangboard, .liftBlock]
        }
    }

    /// "Covers cable tower, lat pulldown, seated row" (first few items).
    public var covers: String {
        let names = items.prefix(4).map(\.label)
        return "Covers " + names.joined(separator: ", ") + (items.count > 4 ? " and \(items.count - 4) more" : "")
    }

    /// Items every place has: a mat and a foam roller (or a towel and the floor).
    public static let floor: [Equipment] = [.mat, .foamRoller]
}

public enum ZoneAnswer: String, Codable, Sendable {
    case yes, no, unsure
}

/// What kind of place a gym is; each guesses which zones are there.
public enum GymKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case hotel, home, budget
    case bigClub = "big-club"
    case box, park
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hotel: "Hotel gym"
        case .home: "Home"
        case .budget: "Budget chain"
        case .bigClub: "Big club"
        case .box: "CrossFit box"
        case .park: "Park / outdoor"
        }
    }

    public var blurb: String {
        switch self {
        case .hotel: "Dumbbells, bench, a cardio machine"
        case .home: "What you own"
        case .budget: "Racks, cables, machines"
        case .bigClub: "Everything, plus a functional zone"
        case .box: "Barbells, rigs, ergs, kettlebells"
        case .park: "Bars and the ground"
        }
    }

    /// Zones usually there.
    public var zones: Set<GymArea> {
        switch self {
        case .hotel: [.dumbbells, .cardio]
        case .home: [.dumbbells]
        case .budget: [.barbells, .dumbbells, .cables, .machines, .stations, .cardio]
        case .bigClub: Set(GymArea.allCases).subtracting([.climbing])
        case .box: [.barbells, .dumbbells, .stations, .functional, .cardio]
        case .park: [.stations]
        }
    }

    public var guess: [GymArea: ZoneAnswer] {
        Dictionary(uniqueKeysWithValues: GymArea.allCases.map { ($0, zones.contains($0) ? ZoneAnswer.yes : ZoneAnswer.no) })
    }

    public var equipment: [Equipment] { GymSetup.equipment(guess).equipment }
}

public enum GymSetup {
    /// Equipment for zone answers, in catalog order. "Not sure" zones are included and listed as unsure.
    public static func equipment(_ answers: [GymArea: ZoneAnswer]) -> (equipment: [Equipment], unsure: [Equipment]) {
        var on = Set(GymArea.floor)
        var unsure = Set<Equipment>()
        for zone in GymArea.allCases {
            switch answers[zone] ?? .no {
            case .yes: on.formUnion(zone.items)
            case .unsure:
                on.formUnion(zone.items)
                unsure.formUnion(zone.items)
            case .no: break
            }
        }
        return (Equipment.allCases.filter { on.contains($0) }, Equipment.allCases.filter { unsure.contains($0) })
    }

    /// Zone answers that best describe an equipment list: yes when most of a zone is there.
    public static func answers(for equipment: [Equipment]) -> [GymArea: ZoneAnswer] {
        let have = Set(equipment)
        return Dictionary(uniqueKeysWithValues: GymArea.allCases.map { z in
            (z, z.items.filter { have.contains($0) }.count * 2 >= z.items.count ? ZoneAnswer.yes : ZoneAnswer.no)
        })
    }

    /// Exercises of a plan that use a zone's items.
    public static func uses(_ zone: GymArea, in plan: WeekPlan?) -> Int {
        let items = Set(zone.items)
        return (plan?.sessions ?? []).flatMap { $0.blocks.flatMap(\.items) }
            .filter { item in Exercise.find(item.exerciseId)?.equipment.contains { items.contains($0) } ?? false }.count
    }

    /// Zones to ask, most used by the plan first (ties in catalog order).
    public static func order(for plan: WeekPlan?) -> [GymArea] {
        let counts = Dictionary(uniqueKeysWithValues: GymArea.allCases.map { ($0, uses($0, in: plan)) })
        return GymArea.allCases.enumerated().sorted { a, b in
            (counts[a.element]!, -a.offset) > (counts[b.element]!, -b.offset)
        }.map(\.element)
    }

    /// Planned exercises that need an item missing from `equipment`: what a new gym changes in the plan.
    public static func misfits(_ plan: WeekPlan?, equipment: [Equipment]) -> [Exercise] {
        let have = Set(equipment)
        var seen = Set<String>()
        return (plan?.sessions ?? []).flatMap { $0.blocks.flatMap(\.items) }.compactMap { item in
            guard let e = Exercise.find(item.exerciseId), !Selector.isAvailable(e, have), seen.insert(e.id).inserted else { return nil }
            return e
        }
    }
}

// MARK: - Saved gyms

/// A gym the member set up, with its own equipment: switching gyms (home, holiday, office day pass) is one tap.
public struct SavedGym: Codable, Hashable, Sendable, Identifiable {
    public var ref: GymRef
    public var kind: GymKind?
    public var equipment: [Equipment]
    /// Items kept because the member wasn't sure; dropped one by one with "Not here?" in a workout.
    public var unsure: [Equipment]?
    public var updated: Date
    /// Where its equipment sits (#274); nil = not set up.
    public var layout: GymLayout?

    public var id: String { ref.id }

    public init(ref: GymRef, kind: GymKind? = nil, equipment: [Equipment], unsure: [Equipment]? = nil, updated: Date = Date(),
                layout: GymLayout? = nil) {
        self.ref = ref
        self.kind = kind
        self.equipment = equipment
        self.unsure = unsure?.isEmpty == true ? nil : unsure
        self.updated = updated
        self.layout = layout
    }

    /// Gym without a map place (home, hotel room, a gym Apple Maps doesn't know, #680): an id of its own.
    public static func customRef(name: String, address: String = "", latitude: Double? = nil, longitude: Double? = nil) -> GymRef {
        GymRef(id: "custom:" + UUID().uuidString.lowercased(), name: name, address: address, latitude: latitude, longitude: longitude)
    }

    /// Map places and scoped gyms can be shared with other members (gym memory); custom ones can't.
    public var isPlace: Bool { !ref.id.hasPrefix("custom:") }

    /// The list without `item`, also no longer unsure.
    public func removing(_ items: [Equipment]) -> SavedGym {
        var g = self
        g.equipment.removeAll { items.contains($0) }
        g.unsure = g.unsure?.filter { !items.contains($0) }
        if g.unsure?.isEmpty == true { g.unsure = nil }
        g.updated = Date()
        return g
    }
}

extension Exercise {
    /// Equipment of this exercise missing from `equipment`.
    public func missing(from equipment: [Equipment]) -> [Equipment] {
        let have = Set(equipment)
        return self.equipment.filter { !have.contains($0) }
    }
}

// MARK: - Equipment pictures and search

extension Equipment {
    /// Exercise whose picture shows this equipment in use: the tile picture on the equipment page.
    public var pictureExerciseId: String {
        switch self {
        case .barbell: "deadlift"
        case .trapBar: "trap-bar-deadlift"
        case .rack: "back-squat"
        case .bench: "db-bench"
        case .dumbbells: "db-curl"
        case .kettlebells: "kb-swing"
        case .cable: "cable-fly"
        case .smith: "smith-squat"
        case .legPress: "leg-press"
        case .hackSquat: "hack-squat"
        case .legCurl: "leg-curl"
        case .legExtension: "leg-extension"
        case .latPulldown: "lat-pulldown"
        case .seatedRow: "seated-cable-row"
        case .chestPress: "chest-press-machine"
        case .pecDeck: "pec-deck-fly"
        case .hipThrustMachine: "hip-thrust-machine"
        case .backExtension: "back-extension"
        case .pullupBar: "pull-up"
        case .dipStation: "dips"
        case .rings: "ring-push-up"
        case .trx: "trx-body-saw"
        case .landmine: "landmine-rotation"
        case .plyoBox: "box-jump"
        case .medBall: "med-ball-chest-pass"
        case .slamBall: "ball-slam"
        case .sled: "sled-sprint"
        case .battleRope: "battle-rope-slams"
        case .abWheel: "ab-wheel"
        case .bands: "band-pull-apart"
        case .foamRoller: "t-spine-roller"
        case .mat: "plank"
        case .treadmill: "treadmill-run"
        case .bike: "bike"
        case .airBike: "air-bike"
        case .rower: "rower"
        case .skiErg: "ski-erg"
        case .stairClimber: "stair-climber"
        case .elliptical: "elliptical"
        case .seatedCalf: "seated-calf-raise"
        case .hipAdAbductor: "hip-abduction"
        case .abCrunch: "crunch-machine"
        case .torsoRotation: "torso-rotation"
        case .ezBar: "ez-bar-curl"
        case .preacherBench: "db-preacher-curl"
        case .shoulderPress: "machine-shoulder-press"
        case .standingCalf: "machine-calf-raise"
        case .tBarRow: "t-bar-row"
        case .ghd: "glute-ham-raise"
        case .stabilityBall: "ball-crunch"
        case .jumpRope: "jump-rope"
        case .assistedMachine: "assisted-dip"
        case .reverseHyper: "reverse-hyper"
        case .curlMachine: "machine-curl"
        case .tricepsMachine: "machine-triceps-extension"
        case .dipBelt: "weighted-dip"
        case .rowMachine: "machine-row"
        case .backExtensionMachine: "back-extension-machine"
        case .squatMachine: "pendulum-squat"
        case .beltSquat: "belt-squat"
        case .gluteMachine: "glute-kickback-machine"
        case .multiHip: "multi-hip-extension"
        case .pulloverMachine: "machine-pullover"
        case .sandbag: "sandbag-shouldering"
        case .sliders: "slider-leg-curl"
        case .balanceTrainer: "bosu-squat"
        case .massageBall: "massage-ball-glute"
        case .stallBars: "human-flag"
        case .hangboard: "max-hangs"
        case .climbingWall: "easy-traverse"
        case .liftBlock: "block-lift"
        }
    }

    /// Other names people use, for search ("guided bar", "swiss ball").
    public var aliases: [String] {
        switch self {
        case .barbell: ["olympic bar", "plates", "weights"]
        case .rack: ["power rack", "squat rack", "cage"]
        case .bench: ["flat bench", "incline bench"]
        case .cable: ["cable crossover", "pulley", "functional trainer"]
        case .smith: ["guided bar"]
        case .latPulldown: ["pulldown", "lat machine"]
        case .seatedRow: ["cable row", "low row"]
        case .pecDeck: ["butterfly", "fly machine", "rear delt"]
        case .backExtension: ["roman chair", "hyperextension"]
        case .pullupBar: ["chin-up bar"]
        case .trx: ["suspension trainer"]
        case .plyoBox: ["jump box"]
        case .medBall: ["wall ball"]
        case .abWheel: ["ab roller"]
        case .bands: ["resistance bands", "elastic"]
        case .bike: ["spin bike", "exercise bike"]
        case .airBike: ["assault bike", "fan bike"]
        case .rower: ["rowing machine", "erg"]
        case .stairClimber: ["stairmaster", "stepper"]
        case .elliptical: ["cross trainer"]
        case .hipAdAbductor: ["adductor", "abductor", "inner thigh", "outer thigh"]
        case .ezBar: ["curl bar"]
        case .tBarRow: ["chest-supported row"]
        case .ghd: ["glute ham"]
        case .stabilityBall: ["swiss ball", "exercise ball", "gym ball"]
        case .jumpRope: ["skipping rope"]
        case .assistedMachine: ["gravitron", "assisted chin-up", "assisted dip"]
        case .reverseHyper: ["reverse hyperextension"]
        case .curlMachine: ["arm curl machine"]
        case .tricepsMachine: ["triceps press machine", "triceps dip machine"]
        case .dipBelt: ["weight belt", "weighted vest", "chain belt", "weighted pull-up"]
        case .rowMachine: ["row machine", "chest-supported row machine", "iso-lateral row", "low row machine"]
        case .backExtensionMachine: ["lower back machine", "lumbar machine", "seated back extension"]
        case .squatMachine: ["pendulum squat", "v-squat", "squat press"]
        case .beltSquat: ["hip belt squat"]
        case .gluteMachine: ["glute machine", "kickback machine", "glute isolator"]
        case .multiHip: ["hip machine", "pendulum hip", "4-way hip"]
        case .pulloverMachine: ["pullover", "lat pullover"]
        case .sandbag: ["core bag", "bulgarian bag", "power bag"]
        case .sliders: ["gliders", "slide pads", "valslide"]
        case .balanceTrainer: ["bosu", "balance pad", "airex", "wobble board"]
        case .massageBall: ["lacrosse ball", "foam ball", "trigger point ball"]
        case .stallBars: ["swedish ladder", "wall bars", "pole"]
        case .hangboard: ["fingerboard", "beastmaker", "edges"]
        case .climbingWall: ["bouldering wall", "climbing", "bouldering"]
        case .liftBlock: ["tension block", "no-hang", "pinch block", "lifting edge"]
        default: []
        }
    }

    /// Whether this item matches a search text (label, other names or the area it's in).
    public func matches(_ text: String) -> Bool {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return ([label] + aliases + [GymArea.of(self).label]).contains { $0.lowercased().contains(q) }
    }
}

extension GymArea {
    public static func of(_ item: Equipment) -> GymArea {
        allCases.first { $0.items.contains(item) } ?? .functional
    }
}
