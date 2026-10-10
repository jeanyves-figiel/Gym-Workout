// Technique content for exercises used by the example workouts (Templates.swift).

extension Technique {
    static let examples: [String: Technique] = [
        "barbell-curl": Technique(
            setup: [
                "Load a straight or EZ bar light enough for 10 strict reps",
                "Grip shoulder-width, palms up, stand tall with the bar at the thighs",
            ],
            position: [
                Checkpoint(.shoulders, "Down and back, stay still"),
                Checkpoint(.elbows, "Pinned to the sides of the ribs"),
                Checkpoint(.hands, "Wrists straight, not curled back"),
                Checkpoint(.core, "Glutes and abs tight so the hips don't swing"),
            ],
            mistakes: [
                "Swinging the bar up with the hips",
                "Elbows drifting forward at the top",
                "Dropping the bar instead of a 3 s lower",
            ],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "incline-db-curl": Technique(
            setup: [
                "Set the bench to 45–60°",
                "Sit back with a dumbbell in each hand, arms hanging straight down behind the torso",
            ],
            position: [
                Checkpoint(.head, "Resting on or near the pad"),
                Checkpoint(.shoulders, "Back against the pad, don't roll forward"),
                Checkpoint(.elbows, "Stay pointing at the floor; only the forearms move"),
                Checkpoint(.hands, "Palms forward, supinate fully at the top"),
            ],
            mistakes: [
                "Bringing the elbows forward to shorten the range",
                "Cutting the stretch at the bottom",
            ],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "barbell-french-press": Technique(
            setup: [
                "Lie on a flat bench with an EZ or straight bar, feet planted",
                "Press the bar up over the shoulders, then tilt the arms slightly back toward the head",
            ],
            position: [
                Checkpoint(.head, "On the bench; bar lowers toward the forehead or just behind it"),
                Checkpoint(.elbows, "Fixed, shoulder-width, pointing up and slightly back"),
                Checkpoint(.hands, "Narrow grip, wrists straight"),
                Checkpoint(.feet, "Flat on the floor"),
            ],
            mistakes: [
                "Elbows flaring out wide",
                "Turning it into a press by moving the upper arms",
                "Lowering fast toward the face",
            ],
            breathing: "Inhale as you lower, exhale as you extend"
        ),
        "db-french-press": Technique(
            setup: [
                "Lie on a flat bench, dumbbells pressed up over the shoulders",
                "Turn the palms to face each other (neutral grip)",
            ],
            position: [
                Checkpoint(.head, "On the bench; dumbbells lower beside the head"),
                Checkpoint(.elbows, "Point to the ceiling and stay there"),
                Checkpoint(.hands, "Neutral grip, wrists straight"),
                Checkpoint(.feet, "Flat on the floor"),
            ],
            mistakes: [
                "Upper arms swinging back and forth",
                "Partial range at the bottom",
            ],
            breathing: "Inhale as you lower, exhale as you extend"
        ),
        "db-reverse-fly": Technique(
            setup: [
                "Pick light dumbbells",
                "Stand with soft knees and hinge forward to about 45°, arms hanging under the shoulders",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes on the floor ahead"),
                Checkpoint(.shoulders, "Away from the ears, no shrug"),
                Checkpoint(.elbows, "Slightly bent and fixed"),
                Checkpoint(.back, "Flat, hinge held throughout"),
                Checkpoint(.knees, "Soft"),
            ],
            mistakes: [
                "Standing up as you lift",
                "Shrugging instead of opening the arms",
                "Weights too heavy, turning it into a row",
            ],
            breathing: "Exhale as you open the arms, inhale as you lower"
        ),
        "diamond-push-up": Technique(
            setup: [
                "Hands under the sternum, thumbs and index fingers touching to form a diamond",
                "Walk the feet back into a straight plank; drop to the knees to make it easier",
            ],
            position: [
                Checkpoint(.head, "In line with the spine"),
                Checkpoint(.elbows, "Track back close to the ribs"),
                Checkpoint(.hands, "Diamond under the chest, fingers spread"),
                Checkpoint(.core, "Rigid plank, glutes tight"),
                Checkpoint(.feet, "Together or hip-width"),
            ],
            mistakes: [
                "Hips sagging or piking",
                "Elbows flaring out wide",
                "Half reps",
            ],
            breathing: "Inhale as you lower, exhale as you push"
        ),
        "seated-calf-raise": Technique(
            setup: [
                "Sit and place the balls of the feet on the platform edge",
                "Set the knee pad snug on the lower thighs, load plates, release the safety lever",
            ],
            position: [
                Checkpoint(.back, "Upright, hands on the pad"),
                Checkpoint(.knees, "Bent about 90°, under the pad"),
                Checkpoint(.feet, "Hip-width, heels free to drop below the platform"),
            ],
            mistakes: [
                "Bouncing out of the bottom",
                "Short range: no full stretch, no full rise",
                "Forgetting to re-engage the safety before getting out",
            ],
            breathing: "Exhale as you rise, inhale as you lower"
        ),
        "hip-adduction": Technique(
            setup: [
                "Set the machine to adduction (pads on the inside of the knees)",
                "Choose a start width you can control and sit back against the pad",
            ],
            position: [
                Checkpoint(.back, "Against the back pad"),
                Checkpoint(.hands, "On the handles, relaxed grip"),
                Checkpoint(.hips, "Stay down on the seat"),
                Checkpoint(.knees, "Pads on the inner knees, legs press together"),
            ],
            mistakes: [
                "Letting the weight stack slam on the return",
                "Starting wider than you can control",
            ],
            breathing: "Exhale as you squeeze, inhale as you open"
        ),
        "hip-abduction": Technique(
            setup: [
                "Set the machine to abduction (pads on the outside of the knees)",
                "Start with legs together and sit back against the pad",
            ],
            position: [
                Checkpoint(.back, "Against the back pad, or lean slightly forward for more glute"),
                Checkpoint(.hands, "On the handles"),
                Checkpoint(.hips, "Stay down on the seat"),
                Checkpoint(.knees, "Push out against the pads"),
            ],
            mistakes: [
                "Jerky reps using momentum",
                "Rocking the torso to move the weight",
            ],
            breathing: "Exhale as you open, inhale as you return"
        ),
        "crunch-machine": Technique(
            setup: [
                "Adjust the seat so the chest pad or handles sit at upper-chest height",
                "Feet under the rollers, load plates",
            ],
            position: [
                Checkpoint(.head, "Neutral, chin slightly tucked"),
                Checkpoint(.hands, "Hold the handles; the arms don't pull"),
                Checkpoint(.core, "Curl the ribs toward the pelvis"),
                Checkpoint(.feet, "Secured under the rollers"),
            ],
            mistakes: [
                "Pulling with the arms",
                "Hinging at the hips instead of rounding the spine",
            ],
            breathing: "Exhale fully as you crunch, inhale as you return"
        ),
        "torso-rotation": Technique(
            setup: [
                "Set the start angle to a range you can control",
                "Sit with the knees locked in by the pads, chest against the pad, hands on the handles",
            ],
            position: [
                Checkpoint(.head, "Turns with the chest"),
                Checkpoint(.shoulders, "Square to the chest pad"),
                Checkpoint(.core, "Rotation comes from the trunk"),
                Checkpoint(.hips, "Pinned; no movement from the hips or knees"),
            ],
            mistakes: [
                "Swinging fast through the end range",
                "Using the arms to pull the rotation",
            ],
            breathing: "Exhale as you rotate, inhale as you return"
        ),
    ]
}
