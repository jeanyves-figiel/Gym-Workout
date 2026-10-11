// Technique content for the muscle audit exercises (#112).

extension Technique {
    static let audit: [String: Technique] = [
        "barbell-shrug": Technique(
            setup: [
                "Bar in a rack at mid-thigh height, overhand grip just outside the thighs",
                "Lift it out and stand tall, arms straight",
            ],
            position: [
                Checkpoint(.shoulders, "Straight up toward the ears, then straight down"),
                Checkpoint(.elbows, "Locked straight: the arms only hold the bar"),
                Checkpoint(.head, "Neutral, chin level"),
                Checkpoint(.core, "Braced, no leaning back"),
            ],
            mistakes: [
                "Rolling the shoulders in circles",
                "Bending the elbows to pull the bar up",
                "Bouncing heavy reps without a pause at the top",
            ],
            breathing: "Exhale as you shrug up, inhale as you lower"
        ),
        "db-shrug": Technique(
            setup: [
                "Stand tall with a dumbbell in each hand at your sides",
                "Palms facing the thighs, feet hip-width",
            ],
            position: [
                Checkpoint(.shoulders, "Lift straight up, hold 1 s, lower fully"),
                Checkpoint(.elbows, "Straight throughout"),
                Checkpoint(.head, "Neutral, don't jut the chin forward"),
                Checkpoint(.hands, "Firm grip, wrists straight"),
            ],
            mistakes: [
                "Rolling the shoulders",
                "Cutting the range short at the bottom",
                "Letting the head drop forward",
            ],
            breathing: "Exhale on the shrug, inhale on the way down"
        ),
        "reverse-curl": Technique(
            setup: [
                "Stand tall with a dumbbell in each hand, palms facing back",
                "Arms straight, elbows close to the sides",
            ],
            position: [
                Checkpoint(.elbows, "Pinned to the sides, only the forearms move"),
                Checkpoint(.hands, "Palms down, wrists straight in line with the forearm"),
                Checkpoint(.shoulders, "Down and back, no swinging"),
                Checkpoint(.back, "Upright, no leaning back"),
            ],
            mistakes: [
                "Going too heavy and swinging the torso",
                "Letting the wrists bend back",
                "Elbows drifting forward",
            ],
            breathing: "Exhale as you curl, inhale as you lower slowly"
        ),
        "lying-leg-raise": Technique(
            setup: [
                "Lie on a flat bench, hips at the end or legs on the bench",
                "Hold the bench behind your head for support",
            ],
            position: [
                Checkpoint(.back, "Lower back pressed down at the start"),
                Checkpoint(.knees, "Straight or softly bent, legs together"),
                Checkpoint(.hips, "At the top, curl the hips off the bench"),
                Checkpoint(.core, "Ribs down, abs tight all the way down"),
            ],
            mistakes: [
                "Arching the lower back as the legs lower",
                "Swinging the legs up with momentum",
                "Stopping at vertical without curling the pelvis",
            ],
            breathing: "Exhale as the legs rise, inhale as they lower"
        ),
        "monster-walk": Technique(
            setup: [
                "Mini band just above the knees or around the ankles",
                "Feet hip-width, sit into a quarter squat",
            ],
            position: [
                Checkpoint(.knees, "Pushed out against the band, never caving in"),
                Checkpoint(.hips, "Level, stay low the whole set"),
                Checkpoint(.feet, "Small steps forward and out, toes forward"),
                Checkpoint(.back, "Flat, chest up"),
            ],
            mistakes: [
                "Standing up between steps",
                "Letting the knees cave in",
                "Rocking the torso side to side",
            ],
            breathing: "Steady breathing, one breath every two steps"
        ),
        "tib-raise": Technique(
            setup: [
                "Back and hips on a wall, heels about a foot from the wall",
                "Legs straight, feet hip-width",
            ],
            position: [
                Checkpoint(.feet, "Lift the toes as high as you can, heels stay down"),
                Checkpoint(.knees, "Straight, no bending to help"),
                Checkpoint(.hips, "Stay on the wall"),
                Checkpoint(.back, "Relaxed against the wall"),
            ],
            mistakes: [
                "Feet too close to the wall so it's too easy",
                "Dropping the toes fast",
                "Bending the knees",
            ],
            breathing: "Breathe normally, exhale on each lift"
        ),
    ]
}
