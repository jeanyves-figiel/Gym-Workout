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
        case .barbell, .trapBar, .rack, .bench, .dumbbells, .smith, .landmine, .ezBar, .preacherBench: .freeWeights
        case .cable, .legPress, .hackSquat, .legCurl, .legExtension, .latPulldown, .seatedRow, .chestPress, .pecDeck,
             .hipThrustMachine, .backExtension, .dipStation, .pullupBar, .seatedCalf, .hipAdAbductor, .abCrunch,
             .torsoRotation, .shoulderPress, .standingCalf, .tBarRow, .ghd,
             .assistedMachine, .reverseHyper, .curlMachine, .tricepsMachine, .rowMachine, .backExtensionMachine, .squatMachine,
             .beltSquat, .gluteMachine, .multiHip, .pulloverMachine, .lateralRaiseMachine: .machines
        case .kettlebells, .rings, .trx, .plyoBox, .medBall, .slamBall, .sled, .battleRope, .abWheel, .bands, .stabilityBall, .jumpRope, .dipBelt,
             .sandbag, .sliders, .balanceTrainer, .stallBars, .hangboard, .climbingWall, .liftBlock: .functional
        case .treadmill, .bike, .airBike, .rower, .skiErg, .stairClimber, .elliptical: .cardio
        case .foamRoller, .mat, .massageBall: .stretch
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
        case .ezBar: "Angled grips are easier on the wrists; use collars like any barbell."
        case .preacherBench: "Seat height so the armpits sit snug over the top of the pad."
        case .shoulderPress: "Seat so the handles start at shoulder height; back flat on the pad."
        case .standingCalf: "Shoulder pads set so the knees are just soft at the bottom; balls of the feet on the edge."
        case .tBarRow: "Chest pad high enough that the arms hang straight; feet planted on the platform."
        case .ghd: "Foot plate so the knees sit just behind the pad; ankles locked under the rollers."
        case .stabilityBall: "Pick a size where thighs are level when you sit on it; pumped firm."
        case .jumpRope: "Handles at the armpits when you stand on the middle of the rope."
        case .assistedMachine: "More counterweight = more help; knee or foot pad locked before you step on."
        case .reverseHyper: "Hips at the edge of the pad, grip the handles; strap just above the ankles."
        case .curlMachine: "Seat so the elbows line up with the pivot and the armpits sit over the pad."
        case .tricepsMachine: "Seat so the elbows line up with the pivot; upper arms flat on the pad."
        case .dipBelt: "Hang plates or a kettlebell from the chain; keep it short so it doesn't swing into the knees."
        case .rowMachine: "Seat so the handles sit at mid-chest; chest pad set so the arms are fully extended at the start."
        case .backExtensionMachine: "Seat so the hips line up with the pivot; back pad across the shoulder blades, feet planted."
        case .squatMachine: "Shoulder pads snug; feet mid-platform, a little wider than the hips; set the safety stop below your depth."
        case .beltSquat: "Belt low on the hips, chain short enough that you start standing tall; hold the rail lightly."
        case .gluteMachine: "Chest pad so the hips sit square; foot plate or pad behind the working heel."
        case .multiHip: "Platform height so the pivot lines up with your hip joint; pad just above the knee."
        case .pulloverMachine: "Seat so the shoulders line up with the cam; elbows on the pads, belt across the lap."
        case .lateralRaiseMachine: "Seat so the shoulders line up with the pivots; pads on the outside of the arms, just above the elbows."
        case .sandbag: "Pick a weight you can lap and stand with; check the inner bags are closed tight."
        case .sliders: "Use them on a smooth floor or a mat; cloth side on hard floors, plastic side on carpet."
        case .balanceTrainer: "Dome up for balance work, flat side up for push-ups and squats; centre the feet or hands."
        case .massageBall: "Firm ball against the floor or a wall; let body weight set the pressure."
        case .stallBars: "Grip a rung or the pole at shoulder width; top hand pulls, bottom hand pushes."
        case .hangboard: "Warm up first; a chair or foot loop under the board takes weight off until you can hang it all."
        case .climbingWall: "Stay on the easy holds and keep clear of the landing zone under other climbers."
        case .liftBlock: "Clip plates or a kettlebell to the pin; start light, the edge depth sets the difficulty."
        }
    }
}
