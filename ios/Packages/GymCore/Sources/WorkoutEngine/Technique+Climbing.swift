// Technique content for the climbing gym exercises (#366).

extension Technique {
    static let climbing: [String: Technique] = [
        "finger-ramp": Technique(
            setup: ["Stand tall, arms out in front at shoulder height", "Start with the hands fully open, fingers spread"],
            position: [
                Checkpoint(.hands, "Open wide, then close into a fist; each round a little firmer"),
                Checkpoint(.elbows, "Straight but not locked"),
                Checkpoint(.shoulders, "Relaxed, down away from the ears"),
            ],
            mistakes: ["Squeezing hard from the first round", "Pushing through finger pain", "Rushing: it should take a full minute"],
            breathing: "Easy, steady breathing"
        ),
        "forearm-waves": Technique(
            setup: ["Arms out in front, palms down", "Hands loose"],
            position: [
                Checkpoint(.hands, "Wave the hands slowly up and down from the wrists"),
                Checkpoint(.elbows, "Still and straight"),
                Checkpoint(.shoulders, "Relaxed"),
            ],
            mistakes: ["Flapping fast", "Moving the whole arm instead of the wrist"],
            breathing: "Easy, steady breathing"
        ),
        "band-external-rotation": Technique(
            setup: ["Anchor a light band at elbow height to your side", "Hold it with the far hand, elbow tucked at your side, bent 90°"],
            position: [
                Checkpoint(.elbows, "Glued to the ribs, a towel under it helps"),
                Checkpoint(.hands, "Forearm rotates outward like a door opening"),
                Checkpoint(.shoulders, "Down and back, no shrug"),
                Checkpoint(.core, "Torso still, no twisting"),
            ],
            mistakes: ["Elbow drifting away from the body", "Rotating the torso to move the band", "Band too heavy"],
            breathing: "Exhale as you rotate out, inhale on the way back"
        ),
        "hang-ramp": Technique(
            setup: ["Biggest edge or jug on the hangboard", "Feet on a chair or box take weight off for the first hangs"],
            position: [
                Checkpoint(.hands, "Open or half crimp, thumbs off on edges"),
                Checkpoint(.shoulders, "Engaged, pulled slightly down"),
                Checkpoint(.elbows, "Straight but soft"),
                Checkpoint(.core, "Lightly braced, no swing"),
            ],
            mistakes: ["Starting on a small edge", "Full body weight before the fingers are warm", "Going until it hurts"],
            breathing: "Slow breathing through each hang"
        ),
        "recruitment-pulls": Technique(
            setup: ["Good edge on the hangboard, warm fingers", "Half crimp, feet just off the ground"],
            position: [
                Checkpoint(.hands, "Half crimp, all four fingers loaded"),
                Checkpoint(.shoulders, "Pull down hard for 2–3 s, then let go"),
                Checkpoint(.elbows, "Barely bend"),
            ],
            mistakes: ["Turning it into a max effort", "Short rest between pulls", "Crimping hard on a small edge"],
            breathing: "Exhale through the pull"
        ),
        "easy-traverse": Technique(
            setup: ["Pick a wall section with big holds and space to move sideways", "Check nobody is climbing above"],
            position: [
                Checkpoint(.hands, "Relaxed grip, as light as the holds allow"),
                Checkpoint(.elbows, "Straight arms, hang from the skeleton"),
                Checkpoint(.hips, "Close to the wall"),
                Checkpoint(.feet, "Precise, quiet foot placements"),
            ],
            mistakes: ["Over-gripping", "Climbing hard moves while still cold", "Moving into the landing zone of others"],
            breathing: "Breathe steadily, never hold the breath"
        ),
        "max-hangs": Technique(
            setup: ["20 mm edge, warmed up with the hang ramp", "Add weight with a belt or remove it with a pulley only when 10 s is easy"],
            position: [
                Checkpoint(.hands, "Half crimp, fingers stay put the whole hang"),
                Checkpoint(.shoulders, "Engaged, not shrugged to the ears"),
                Checkpoint(.elbows, "Slightly bent, never locked"),
                Checkpoint(.core, "Braced, legs still"),
            ],
            mistakes: ["Full crimping", "Short rest: take 2–3 minutes", "Training it more than twice a week", "Hanging through pain"],
            breathing: "Breathe out as you load, keep breathing during the hang"
        ),
        "repeaters": Technique(
            setup: ["Medium edge you can hang for about 15 s", "Timer ready: 7 s on, 3 s off, six times"],
            position: [
                Checkpoint(.hands, "Same grip and edge every rep"),
                Checkpoint(.shoulders, "Engaged on each hang"),
                Checkpoint(.feet, "Step down quietly on the 3 s off"),
            ],
            mistakes: ["Changing grip mid-set", "Pushing on when the fingers open", "Starting on an edge that's too small"],
            breathing: "Breathe through the hangs; deep breaths on each rest"
        ),
        "open-hand-hang": Technique(
            setup: ["Rounded edge or sloper on the hangboard", "Feet on a chair if you need help"],
            position: [
                Checkpoint(.hands, "Three-finger drag, thumb off"),
                Checkpoint(.shoulders, "Engaged"),
                Checkpoint(.elbows, "Soft, not locked"),
            ],
            mistakes: ["Letting the fingers crimp up", "Swinging", "Holding the breath"],
            breathing: "Slow, steady breathing"
        ),
        "block-lift": Technique(
            setup: ["Clip plates or a kettlebell to the block's pin", "Stand tall beside it, block by the hip"],
            position: [
                Checkpoint(.hands, "Half crimp on the edge, thumb off"),
                Checkpoint(.shoulders, "Set, not shrugged"),
                Checkpoint(.back, "Neutral, lift with the legs"),
                Checkpoint(.feet, "Hip-width, planted"),
            ],
            mistakes: ["Jerking the weight off the floor", "Letting the wrist bend", "Too much weight too soon"],
            breathing: "Exhale as you lift, breathe through the hold"
        ),
        "pinch-block-lift": Technique(
            setup: ["Light weight on the pinch block", "Stand beside it, feet hip-width"],
            position: [
                Checkpoint(.hands, "Thumb on one side, fingers flat on the other"),
                Checkpoint(.shoulders, "Set, arm straight"),
                Checkpoint(.back, "Tall, no leaning"),
            ],
            mistakes: ["Wrist bent", "Hinging over to reach the block", "Dropping it instead of lowering"],
            breathing: "Exhale as you lift, breathe through the hold"
        ),
        "wrist-flexor-floor": Technique(
            setup: ["Kneel on a mat on all fours", "Turn the hands so the fingers point back toward the knees, palms flat"],
            position: [
                Checkpoint(.hands, "Palms stay flat on the floor"),
                Checkpoint(.elbows, "Straight"),
                Checkpoint(.hips, "Ease back slowly until the forearms stretch"),
            ],
            mistakes: ["Rocking back too far", "Lifting the palms", "Bouncing"],
            breathing: "Slow breaths, relax a little further on each exhale"
        ),
    ]
}
