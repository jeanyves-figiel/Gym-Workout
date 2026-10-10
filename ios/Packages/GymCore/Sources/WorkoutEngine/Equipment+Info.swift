/// Where equipment lives in a large club and how to adjust it.
public enum GymZone: String, Sendable, CaseIterable {
    case freeWeights, machines, functional, cardio, stretch

    public var label: String {
        switch self {
        case .freeWeights: "Free-weight area"
        case .machines: "Machine circuit"
        case .functional: "Functional zone"
        case .cardio: "Cardio floor"
        case .stretch: "Stretch area"
        }
    }
}

extension Equipment {
    public var zone: GymZone {
        switch self {
        case .barbell, .trapBar, .rack, .bench, .dumbbells, .smith, .landmine: .freeWeights
        case .cable, .legPress, .hackSquat, .legCurl, .legExtension, .latPulldown, .seatedRow, .chestPress, .pecDeck,
             .hipThrustMachine, .backExtension, .dipStation, .pullupBar, .seatedCalf, .hipAdAbductor, .abCrunch,
             .torsoRotation: .machines
        case .kettlebells, .rings, .trx, .plyoBox, .medBall, .slamBall, .sled, .battleRope, .abWheel, .bands: .functional
        case .treadmill, .bike, .airBike, .rower, .skiErg, .stairClimber, .elliptical: .cardio
        case .foamRoller, .mat: .stretch
        }
    }

    /// Generic adjustment advice shown with the equipment card.
    public var adjustment: String {
        switch self {
        case .barbell: "Load plates evenly and always use collars."
        case .trapBar: "Use the high handles if hips or mobility limit depth."
        case .rack: "Hooks at mid-chest; safety pins just below your lowest position."
        case .bench: "Check the angle pin is locked before loading."
        case .dumbbells: "Pick a weight you can control for every rep; return to the rack in order."
        case .kettlebells: "Start lighter than you think for ballistic moves."
        case .cable: "Set pulley height for the exercise; clip the handle securely."
        case .smith: "Set the safety stops before the first rep."
        case .legPress: "Back pad so hips stay down at depth; release safeties only once set."
        case .hackSquat: "Shoulder pads snug; feet mid-platform; know where the safety lever is."
        case .legCurl: "Knee in line with the pivot; ankle pad just above the heel."
        case .legExtension: "Knee in line with the pivot; shin pad just above the ankle."
        case .latPulldown: "Thigh pad snug so you don't lift off the seat."
        case .seatedRow: "Chest pad so arms are fully extended at the start."
        case .chestPress: "Seat height so handles are at mid-chest."
        case .pecDeck: "Seat so handles are at shoulder height; arms slightly bent."
        case .hipThrustMachine: "Back pad under shoulder blades; belt across the hip crease."
        case .backExtension: "Hip pad just below the hip crease so you can hinge freely."
        case .pullupBar: "Use a box to reach the bar; band for assistance if needed."
        case .dipStation: "Handles about shoulder width; use the assisted machine if needed."
        case .rings: "Strap length so rings hang at the height the exercise needs."
        case .trx: "Adjust strap length; the steeper the body angle, the easier."
        case .landmine: "Bar end seated fully in the sleeve; clear space for the arc."
        case .plyoBox: "Start low; a box you land on quietly beats a tall one."
        case .medBall: "4–6 kg for throws; throw against a solid wall."
        case .slamBall: "Non-bouncing slam ball only; clear space around you."
        case .sled: "Lane clear; load moderate for speed work."
        case .battleRope: "Anchor checked; stand far enough for slight slack."
        case .abWheel: "Kneel on a mat; roll only as far as you hold a neutral spine."
        case .bands: "Check for nicks or tears before use; anchor securely."
        case .foamRoller: "Roll slowly; avoid joints and the lower spine."
        case .mat: "Grab a clean mat in the stretch area."
        case .treadmill: "Start slow, clip the safety key, then build speed."
        case .bike: "Seat at hip height; slight knee bend at the bottom of the stroke."
        case .airBike: "Seat so knee stays slightly bent; arms move with the legs."
        case .rower: "Damper 4–6; foot strap across the widest part of the foot."
        case .skiErg: "Damper 4–7; stand a half step from the machine."
        case .stairClimber: "Light touch on the rails for balance only."
        case .elliptical: "Upright posture; resistance high enough to feel each stride."
        case .seatedCalf: "Knee pad snug on the lower thighs; balls of the feet on the platform edge."
        case .hipAdAbductor: "Set the leg pads to the range you can control; start with a small opening."
        case .abCrunch: "Seat so the chest pad or handles sit at upper-chest height."
        case .torsoRotation: "Lock the start angle to a range you can control; knees pinned by the pads."
        }
    }
}
