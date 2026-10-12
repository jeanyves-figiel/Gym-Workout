// Technique content for the gym app comparison (#182): machines and the bench pullover.

extension Technique {
    static let gymMachines: [String: Technique] = [
        // MARK: Rows
        "machine-row": Technique(
            setup: ["Set the seat so the handles line up with the lower chest", "Chest on the pad, feet planted, grab both handles"],
            position: [
                Checkpoint(.back, "Chest stays on the pad for every rep"),
                Checkpoint(.elbows, "Pull back past the ribs, close to the sides"),
                Checkpoint(.shoulders, "Squeeze the shoulder blades together at the end"),
                Checkpoint(.hands, "Arms reach long on the way back, without losing the pad"),
            ],
            mistakes: ["Leaning back off the pad to move the weight", "Shrugging the shoulders up", "Letting the stack slam between reps"],
            breathing: "Exhale as you pull, inhale as the arms go long"
        ),
        "machine-row-single": Technique(
            setup: ["Set the seat so the handle lines up with the lower chest", "Chest on the pad, one hand on the handle, the other braced on the pad or the other handle"],
            position: [
                Checkpoint(.back, "Chest stays square on the pad"),
                Checkpoint(.elbows, "Working elbow drives back close to the side"),
                Checkpoint(.shoulders, "Level, no rotating toward the handle"),
                Checkpoint(.core, "Braced so the trunk does not twist"),
            ],
            mistakes: ["Twisting the torso to finish the rep", "Pulling with the biceps only", "Short range at the front"],
            breathing: "Exhale as you pull, inhale on the way back"
        ),
        // MARK: Hinge machines
        "back-extension-machine": Technique(
            setup: ["Sit with the hips against the back of the seat, feet on the platform", "Set the pad high across the shoulder blades, arms crossed on the chest"],
            position: [
                Checkpoint(.back, "Long spine, extend from the hips to upright"),
                Checkpoint(.hips, "Stay pressed into the seat"),
                Checkpoint(.head, "Neutral, eyes follow the torso"),
                Checkpoint(.feet, "Flat on the platform, legs still"),
            ],
            mistakes: ["Leaning back past upright", "Jerking the pad with momentum", "Pad set low on the lower back"],
            breathing: "Exhale as you sit up, inhale as you lean forward"
        ),
        "glute-kickback-machine": Technique(
            setup: ["Chest on the pad, hands on the handles", "Working foot on the foot plate, standing leg slightly bent"],
            position: [
                Checkpoint(.hips, "Square to the floor, no opening to the side"),
                Checkpoint(.feet, "Drive the heel back and up into the plate"),
                Checkpoint(.back, "Neutral, stop before the lower back arches"),
                Checkpoint(.knees, "Bend stays about the same through the rep"),
            ],
            mistakes: ["Arching the lower back to get the leg higher", "Rotating the hip open", "Swinging the leg with momentum"],
            breathing: "Exhale as you kick back, inhale as the knee returns"
        ),
        "multi-hip-extension": Technique(
            setup: ["Line the machine's pivot up with the working hip", "Pad behind the lower thigh, stand tall on the other leg and hold the handle"],
            position: [
                Checkpoint(.hips, "Push the leg back from the hip, pelvis level"),
                Checkpoint(.back, "Tall and still, no leaning forward"),
                Checkpoint(.knees, "Working leg nearly straight"),
                Checkpoint(.feet, "Standing foot flat, knee soft"),
            ],
            mistakes: ["Arching the back to push further", "Leaning the torso forward", "Pivot not lined up with the hip"],
            breathing: "Exhale as the leg goes back, inhale on the return"
        ),
        "multi-hip-abduction": Technique(
            setup: ["Line the machine's pivot up with the working hip", "Pad on the outer thigh above the knee, hold the handle, stand tall"],
            position: [
                Checkpoint(.hips, "Level, no hiking the working side"),
                Checkpoint(.feet, "Toes point forward as the leg lifts sideways"),
                Checkpoint(.back, "Upright, no leaning away from the leg"),
                Checkpoint(.knees, "Working leg straight"),
            ],
            mistakes: ["Leaning the trunk to lift higher", "Turning the toes up to the ceiling", "Letting the weight drop back"],
            breathing: "Exhale as the leg lifts, inhale as it lowers"
        ),
        // MARK: Squat machines
        "machine-squat": Technique(
            setup: ["Step under the pads so they sit on the top of the shoulders", "Feet mid-platform about shoulder-width, hands on the handles"],
            position: [
                Checkpoint(.feet, "Whole foot pushes, heels down"),
                Checkpoint(.knees, "Track over the toes"),
                Checkpoint(.back, "Pressed into the pads, chest up"),
                Checkpoint(.hips, "Sit deep before driving up"),
            ],
            mistakes: ["Heels lifting at the bottom", "Knees caving in", "Locking the knees hard at the top"],
            breathing: "Inhale and brace on the way down, exhale as you drive up"
        ),
        "pendulum-squat": Technique(
            setup: ["Back flat on the pad, shoulders under the shoulder pads", "Feet mid-platform, hip-width, release the safety"],
            position: [
                Checkpoint(.back, "Flat on the pad the whole rep"),
                Checkpoint(.knees, "Travel far forward over the toes"),
                Checkpoint(.feet, "Heels stay down on the platform"),
                Checkpoint(.hips, "Reach full depth, then drive up smoothly"),
            ],
            mistakes: ["Bouncing out of the bottom", "Heels lifting", "Cutting depth short"],
            breathing: "Inhale on the way down, exhale as you push up"
        ),
        "belt-squat": Technique(
            setup: ["Clip the belt low on the hips, feet on the platform either side of the chain", "Hands on the front rail, stand up to take the load"],
            position: [
                Checkpoint(.back, "Torso upright, no leaning on the rail"),
                Checkpoint(.hips, "Sit straight down between the heels"),
                Checkpoint(.knees, "Push out over the toes"),
                Checkpoint(.hands, "Rest lightly on the rail for balance only"),
            ],
            mistakes: ["Pulling on the rail to stand up", "Belt riding up to the waist", "Knees caving in"],
            breathing: "Inhale on the way down, exhale as you stand"
        ),
        // MARK: Pullovers
        "machine-pullover": Technique(
            setup: ["Set the seat so the shoulders line up with the machine's pivot", "Elbows on the pads, hands resting lightly on the bar, belt on"],
            position: [
                Checkpoint(.elbows, "Drive the pads down with the elbows, not the hands"),
                Checkpoint(.back, "Stays against the back pad"),
                Checkpoint(.hands, "Open and relaxed on the bar"),
                Checkpoint(.shoulders, "Let the lats stretch fully as the arms go up"),
            ],
            mistakes: ["Pulling with the hands and forearms", "Arching off the back pad", "Rushing the stretch at the top"],
            breathing: "Exhale as the arms sweep down, inhale as they return"
        ),
        "db-bench-pullover": Technique(
            setup: ["Lie across the bench with the upper back on it, feet flat on the floor", "Hold one dumbbell under its top plate with both hands over the chest"],
            position: [
                Checkpoint(.elbows, "Softly bent and fixed for the whole rep"),
                Checkpoint(.core, "Ribs down as the weight goes back"),
                Checkpoint(.hips, "Stay low and still, no bridging up"),
                Checkpoint(.shoulders, "Lower only as far as stays pain-free"),
            ],
            mistakes: ["Bending and straightening the elbows like a triceps extension", "Flaring the ribs and arching the back", "Dropping the weight too far behind the head"],
            breathing: "Inhale as the weight goes back, exhale as you pull it over the chest"
        ),
    ]
}
