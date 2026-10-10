// Technique content for the travel kit exercises (Exercises+Travel.swift) (#68).

extension Technique {
    static let travel: [String: Technique] = [
        "bw-squat": Technique(
            setup: [
                "Feet shoulder-width, toes slightly out",
                "Arms forward for balance",
            ],
            position: [
                Checkpoint(.head, "Eyes forward, neutral neck"),
                Checkpoint(.back, "Chest up, back flat"),
                Checkpoint(.knees, "Track over the toes"),
                Checkpoint(.feet, "Whole foot on the floor"),
            ],
            mistakes: [
                "Heels lifting",
                "Knees caving in",
                "Rushing the reps",
            ],
            breathing: "Inhale down, exhale up"
        ),
        "bw-split-squat": Technique(
            setup: [
                "Long stance, one foot forward, back heel up",
                "Hands on hips or a chair for balance",
            ],
            position: [
                Checkpoint(.back, "Torso upright"),
                Checkpoint(.hips, "Square to the front"),
                Checkpoint(.knees, "Back knee drops toward the floor"),
                Checkpoint(.feet, "Front foot flat"),
            ],
            mistakes: [
                "Stance too short",
                "Pushing off the back foot",
            ],
            breathing: "Inhale down, exhale up"
        ),
        "bw-reverse-lunge": Technique(
            setup: [
                "Stand tall, feet hip-width",
                "Clear space behind you",
            ],
            position: [
                Checkpoint(.back, "Tall torso"),
                Checkpoint(.hips, "Level, no twist"),
                Checkpoint(.knees, "Front knee over the mid-foot"),
                Checkpoint(.feet, "Back foot lands on the ball"),
            ],
            mistakes: [
                "Short step",
                "Front heel lifting",
            ],
            breathing: "Inhale as you step back, exhale as you return"
        ),
        "sl-hip-thrust": Technique(
            setup: [
                "Upper back on the edge of a sofa or bed",
                "One foot flat, other leg lifted",
            ],
            position: [
                Checkpoint(.head, "Chin tucked, eyes forward at the top"),
                Checkpoint(.core, "Ribs down"),
                Checkpoint(.hips, "Level, full lockout at the top"),
                Checkpoint(.feet, "Working heel under the knee at the top"),
            ],
            mistakes: [
                "Arching the lower back",
                "Hips dropping on the free side",
            ],
            breathing: "Exhale as you drive up, inhale down"
        ),
        "bw-sl-rdl": Technique(
            setup: [
                "Stand on one leg, soft knee",
                "Arms hang or reach forward",
            ],
            position: [
                Checkpoint(.back, "Flat from head to free heel"),
                Checkpoint(.hips, "Square to the floor"),
                Checkpoint(.knees, "Standing knee slightly bent"),
                Checkpoint(.feet, "Grip the floor with the toes"),
            ],
            mistakes: [
                "Rounding the back",
                "Opening the hips sideways",
            ],
            breathing: "Inhale as you hinge, exhale as you stand"
        ),
        "table-row": Technique(
            setup: [
                "Use only a sturdy table that can't tip",
                "Lie under it, grip the edge shoulder-width",
            ],
            position: [
                Checkpoint(.shoulders, "Blades pull back first"),
                Checkpoint(.elbows, "About 45° from the body"),
                Checkpoint(.core, "Rigid plank"),
                Checkpoint(.feet, "Heels on the floor, knees bent to make it easier"),
            ],
            mistakes: [
                "Hips sagging",
                "Using a light or wobbly table",
            ],
            breathing: "Exhale as you pull, inhale as you lower"
        ),
        "prone-pulldown": Technique(
            setup: [
                "Lie face down, arms overhead",
                "Thumbs up, forehead on a towel",
            ],
            position: [
                Checkpoint(.head, "Neutral, looking down"),
                Checkpoint(.shoulders, "Down and back"),
                Checkpoint(.elbows, "Pull down to the ribs"),
                Checkpoint(.hands, "Lift slightly off the floor"),
            ],
            mistakes: [
                "Arching the lower back",
                "Shrugging",
            ],
            breathing: "Exhale as you pull, inhale as you reach"
        ),
        "pike-push-up": Technique(
            setup: [
                "Push-up position, walk the feet in, hips high",
                "Hands slightly wider than the shoulders",
            ],
            position: [
                Checkpoint(.head, "Lowers between the hands"),
                Checkpoint(.shoulders, "Over the hands at the bottom"),
                Checkpoint(.elbows, "Track back, not flared"),
                Checkpoint(.hips, "Stay high"),
            ],
            mistakes: [
                "Hips dropping into a push-up",
                "Flaring the elbows",
            ],
            breathing: "Inhale down, exhale as you press"
        ),
        "bw-calf-raise": Technique(
            setup: [
                "Ball of one foot on a step, hold a wall",
                "Heel hangs free",
            ],
            position: [
                Checkpoint(.knees, "Straight"),
                Checkpoint(.feet, "Push through the big toe"),
            ],
            mistakes: [
                "Bouncing at the bottom",
                "Short range",
            ],
            breathing: "Exhale up, inhale down"
        ),
        "db-bent-row": Technique(
            setup: [
                "Dumbbells in hand, hinge to about 45°",
                "Soft knees, arms hang",
            ],
            position: [
                Checkpoint(.head, "Neutral"),
                Checkpoint(.back, "Flat"),
                Checkpoint(.elbows, "Drive toward the hips"),
                Checkpoint(.feet, "Hip-width"),
            ],
            mistakes: [
                "Standing up during the pull",
                "Rounding the back",
            ],
            breathing: "Exhale as you row, inhale as you lower"
        ),
        "db-floor-press": Technique(
            setup: [
                "Lie on the floor, knees bent, dumbbells over the chest",
            ],
            position: [
                Checkpoint(.shoulders, "Pinned to the floor"),
                Checkpoint(.elbows, "About 45°, touch down softly"),
                Checkpoint(.hands, "Over the elbows"),
                Checkpoint(.feet, "Flat"),
            ],
            mistakes: [
                "Bouncing the elbows off the floor",
                "Flaring to 90°",
            ],
            breathing: "Inhale down, exhale as you press"
        ),
        "db-standing-press": Technique(
            setup: [
                "Stand, dumbbells at the shoulders, palms forward or in",
            ],
            position: [
                Checkpoint(.head, "Moves back, then through"),
                Checkpoint(.core, "Ribs down, glutes tight"),
                Checkpoint(.elbows, "Under the wrists"),
                Checkpoint(.hands, "Lock out by the ears"),
            ],
            mistakes: [
                "Leaning back",
                "Pressing forward instead of up",
            ],
            breathing: "Brace, press, exhale at the top"
        ),
        "db-floor-pullover": Technique(
            setup: [
                "Lie on the floor, knees bent, one dumbbell held with both hands over the chest",
            ],
            position: [
                Checkpoint(.back, "Lower back stays down"),
                Checkpoint(.elbows, "Slightly bent, fixed"),
                Checkpoint(.hands, "Lower behind the head"),
            ],
            mistakes: [
                "Arching the lower back",
                "Bending the elbows into a press",
            ],
            breathing: "Inhale as you lower, exhale as you pull back"
        ),
        "band-row": Technique(
            setup: [
                "Anchor the band at chest height (door anchor or post)",
                "Step back until there is tension",
            ],
            position: [
                Checkpoint(.shoulders, "Blades back first"),
                Checkpoint(.elbows, "Close to the body"),
                Checkpoint(.core, "Tall, no leaning back"),
            ],
            mistakes: [
                "Leaning back to pull",
                "Shrugging",
            ],
            breathing: "Exhale as you pull, inhale as you return"
        ),
        "band-pulldown": Technique(
            setup: [
                "Anchor the band high (top of a door)",
                "Kneel facing the anchor",
            ],
            position: [
                Checkpoint(.back, "Tall, slight lean back"),
                Checkpoint(.shoulders, "Down first"),
                Checkpoint(.elbows, "Pull to the ribs"),
            ],
            mistakes: [
                "Pulling with the arms only",
                "Letting the band snap back",
            ],
            breathing: "Exhale as you pull, inhale up"
        ),
        "band-chest-press": Technique(
            setup: [
                "Band behind the back under the arms, or anchored behind you",
                "Staggered stance",
            ],
            position: [
                Checkpoint(.shoulders, "Down, not shrugged"),
                Checkpoint(.elbows, "About 45°"),
                Checkpoint(.hands, "Press straight ahead"),
            ],
            mistakes: [
                "Flaring the elbows",
                "Arching the back",
            ],
            breathing: "Exhale as you press, inhale back"
        ),
        "band-overhead-press": Technique(
            setup: [
                "Stand on the band, handles at the shoulders",
            ],
            position: [
                Checkpoint(.core, "Ribs down, glutes tight"),
                Checkpoint(.elbows, "Under the wrists"),
                Checkpoint(.hands, "Lock out overhead"),
            ],
            mistakes: [
                "Leaning back",
                "Half reps",
            ],
            breathing: "Exhale as you press, inhale down"
        ),
        "band-good-morning": Technique(
            setup: [
                "Stand on the band, loop it behind the neck on the upper back",
                "Soft knees",
            ],
            position: [
                Checkpoint(.back, "Flat from neck to hips"),
                Checkpoint(.hips, "Push back"),
                Checkpoint(.knees, "Slight bend, fixed"),
            ],
            mistakes: [
                "Rounding the back",
                "Squatting instead of hinging",
            ],
            breathing: "Inhale as you hinge, exhale as you stand"
        ),
    ]
}
