import Foundation

/// Sport prep on planned sport days (#523, design A): a short no-kit warm-up before the sport and a stretch after,
/// like climbing's Wall session (#366). One pair per sport family; climbing keeps its Wall session.
public enum SportPrep {
    public enum Family: String, CaseIterable, Sendable {
        case snow, ride, feet, water, court, combat, general
    }

    public static func family(_ sport: Sport) -> Family? {
        switch sport {
        case .climbing: nil
        case .snowboard, .ski, .crossCountrySki: .snow
        case .mountainBike, .roadBike: .ride
        case .run, .trailRun, .hike, .mountaineering: .feet
        case .swim, .rowing, .surf, .scubaDiving: .water
        case .football, .basketball, .volleyball, .tennis, .padel, .squash: .court
        case .martialArts, .boxing: .combat
        case .hyrox, .crossfit, .skate, .golf, .yoga, .other: .general
        }
    }

    /// Warm-up before the sport, nil for climbing.
    public static func before(_ sport: Sport) -> WorkoutTemplate? { family(sport).map { pairs[$0]!.before } }
    /// Stretch after the sport, nil for climbing.
    public static func after(_ sport: Sport) -> WorkoutTemplate? { family(sport).map { pairs[$0]!.after } }

    /// Every prep template, so `WorkoutTemplate.find(sessionId:)` resolves them (session view, player, history).
    public static let templates: [WorkoutTemplate] = Family.allCases.flatMap { [pairs[$0]!.before, pairs[$0]!.after] }

    typealias Item = WorkoutTemplate.Item

    private static func warm(_ id: String, _ reps: Int) -> Item { Item(id, sets: 1, reps: reps, rest: 0, block: .warmup) }
    private static func cool(_ id: String, _ sec: Int = 30) -> Item { Item(id, sets: 1, reps: sec, rest: 0, block: .cooldown) }

    private static func warmUp(_ f: Family, _ name: String, _ focus: Focus, _ items: [Item]) -> WorkoutTemplate {
        WorkoutTemplate(id: "prep-\(f.rawValue)-before", name: name, focus: focus, goal: .mobility, kit: "No kit", level: 1,
                        main: .warmup, items: items)
    }

    private static func coolDown(_ f: Family, _ name: String, _ focus: Focus, _ items: [Item]) -> WorkoutTemplate {
        WorkoutTemplate(id: "prep-\(f.rawValue)-after", name: name, focus: focus, goal: .mobility, kit: "Mat", level: 1,
                        main: .cooldown, items: items)
    }

    static let pairs: [Family: (before: WorkoutTemplate, after: WorkoutTemplate)] = [
        .snow: (
            warmUp(.snow, "Slope warm-up", .lower, [
                warm("leg-swings", 10), warm("hip-car", 5), warm("knee-to-wall", 10), warm("squat-to-stand", 8),
                warm("lunge-twist", 8), warm("arm-circles", 10), warm("worlds-greatest", 5),
            ]),
            coolDown(.snow, "Après stretch", .lower, [
                cool("standing-quad-stretch"), cool("half-kneeling-hf"), cool("calf-wall"), cool("figure-4"),
                cool("supine-twist"), cool("childs-pose-reach"),
            ])),
        .ride: (
            warmUp(.ride, "Ride warm-up", .lower, [
                warm("leg-swings", 10), warm("hip-car", 5), warm("squat-to-stand", 8), warm("worlds-greatest", 5),
                warm("arm-circles", 10), warm("wrist-car", 5),
            ]),
            coolDown(.ride, "Ride cool-down", .lower, [
                cool("standing-quad-stretch"), cool("half-kneeling-hf"), cool("seated-forward-fold"), cool("pigeon"),
                cool("sphinx"), cool("pec-stretch"), cool("upper-trap"),
            ])),
        .feet: (
            warmUp(.feet, "Run & hike warm-up", .lower, [
                warm("leg-swings", 10), warm("hip-car", 5), warm("knee-to-wall", 10), warm("lunge-twist", 8),
                warm("squat-to-stand", 8), warm("inchworm", 5),
            ]),
            coolDown(.feet, "Legs cool-down", .lower, [
                cool("calf-wall"), cool("standing-quad-stretch"), cool("half-kneeling-hf"), cool("figure-4"),
                cool("seated-forward-fold"),
            ])),
        .water: (
            warmUp(.water, "Water warm-up", .upper, [
                warm("arm-circles", 10), warm("shoulder-car", 5), warm("wall-slide", 10), warm("scap-push-up", 10),
                warm("inchworm", 5), warm("worlds-greatest", 5),
            ]),
            coolDown(.water, "Shoulders cool-down", .upper, [
                cool("childs-pose-reach"), cool("cross-body"), cool("triceps-stretch"), cool("pec-stretch"),
                cool("sphinx"), cool("upper-trap"),
            ])),
        .court: (
            warmUp(.court, "Court warm-up", .fullLower, [
                warm("leg-swings", 10), warm("lunge-twist", 8), warm("hip-car", 5), warm("arm-circles", 10),
                warm("shoulder-car", 5), warm("squat-to-stand", 8), warm("inchworm", 5),
            ]),
            coolDown(.court, "Court cool-down", .fullLower, [
                cool("standing-quad-stretch"), cool("calf-wall"), cool("lizard-stretch"), cool("figure-4"),
                cool("cross-body"), cool("side-bend"),
            ])),
        .combat: (
            warmUp(.combat, "Fight warm-up", .fullUpper, [
                warm("arm-circles", 10), warm("shoulder-car", 5), warm("wrist-car", 5), warm("hip-car", 5),
                warm("leg-swings", 10), warm("lunge-twist", 8), warm("inchworm", 5),
            ]),
            coolDown(.combat, "Fight cool-down", .fullUpper, [
                cool("pec-stretch"), cool("cross-body"), cool("triceps-stretch"), cool("pigeon"), cool("butterfly"),
                cool("breathing", 60),
            ])),
        .general: (
            warmUp(.general, "Sport warm-up", .fullLower, [
                warm("worlds-greatest", 5), warm("leg-swings", 10), warm("arm-circles", 10), warm("inchworm", 5),
                warm("squat-to-stand", 8), warm("lunge-twist", 8),
            ]),
            coolDown(.general, "Sport cool-down", .fullLower, [
                cool("childs-pose-reach"), cool("half-kneeling-hf"), cool("figure-4"), cool("calf-wall"),
                cool("pec-stretch"), cool("supine-twist"),
            ])),
    ]
}
