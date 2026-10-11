// Technique content for the catalog extension (#174): back, arms and grip.

extension Technique {
    static let variationsPull: [String: Technique] = [
        // MARK: Rows
        "pendlay-row": Technique(
            setup: ["Bar over mid-foot, feet hip-width", "Hinge until the torso is about flat, grip just outside the knees"],
            position: [
                Checkpoint(.back, "Flat and parallel to the floor for every rep"),
                Checkpoint(.elbows, "Drive up and back, bar to the lower chest"),
                Checkpoint(.hands, "Bar returns to the floor and settles each rep"),
                Checkpoint(.hips, "Stay high and still, no standing up into the pull"),
            ],
            mistakes: ["Torso rising as the weight gets heavy", "Bouncing the bar off the floor", "Rounding the lower back"],
            breathing: "Brace before each pull, exhale at the top, reset on the floor"
        ),
        "yates-row": Technique(
            setup: ["Underhand grip, hands shoulder-width", "Stand tall, then hinge to a torso angle of about 30 degrees"],
            position: [
                Checkpoint(.hands, "Palms up, wrists straight"),
                Checkpoint(.elbows, "Close to the sides, pull toward the hips"),
                Checkpoint(.back, "Neutral and fixed at the same angle"),
                Checkpoint(.knees, "Soft, shins near vertical"),
            ],
            mistakes: ["Turning it into a biceps curl", "Rocking the torso up to move the bar", "Shrugging at the top"],
            breathing: "Exhale as you row, inhale as you lower"
        ),
        "meadows-row": Technique(
            setup: ["Landmine bar loaded, stand side-on to its end in a staggered stance", "Front forearm on the front knee, grip the sleeve overhand with the other hand"],
            position: [
                Checkpoint(.elbows, "Drive high and back, away from the body"),
                Checkpoint(.back, "Flat, chest stays square to the floor"),
                Checkpoint(.hips, "Hinged and still, no twisting to lift"),
                Checkpoint(.hands, "Full stretch at the bottom, strong grip on the thick sleeve"),
            ],
            mistakes: ["Rotating the torso open", "Short range with no stretch", "Rounding the upper back"],
            breathing: "Exhale as you row, inhale on the stretch"
        ),
        "landmine-t-bar-row": Technique(
            setup: ["Straddle the landmine bar facing the plates", "Hook a V-handle under the bar behind the plates, hinge and grip it"],
            position: [
                Checkpoint(.back, "Flat at about 45 degrees, chest up"),
                Checkpoint(.elbows, "Pull back along the ribs, handle to the chest"),
                Checkpoint(.knees, "Bent and still, weight mid-foot"),
                Checkpoint(.shoulders, "Squeeze the shoulder blades together at the top"),
            ],
            mistakes: ["Standing up as you pull", "Rounding the back to reach the bar", "Jerking the weight with the hips"],
            breathing: "Exhale as you row, inhale as you lower"
        ),
        "single-arm-cable-row": Technique(
            setup: ["Set the pulley at chest height with a D-handle", "Split stance, opposite leg forward, arm long toward the pulley"],
            position: [
                Checkpoint(.shoulders, "Let the shoulder reach forward, then pull it back first"),
                Checkpoint(.elbows, "Travel past the ribs, hand finishes by the hip"),
                Checkpoint(.hips, "Square to the machine, no twisting"),
                Checkpoint(.core, "Braced so only the arm and shoulder blade move"),
            ],
            mistakes: ["Rotating the trunk to finish the rep", "Shrugging toward the ear", "Letting the stack yank the arm forward"],
            breathing: "Exhale as you row, inhale on the reach"
        ),
        "wide-grip-cable-row": Technique(
            setup: ["Attach a long straight bar, sit with feet on the platform", "Overhand grip wider than the shoulders, knees soft"],
            position: [
                Checkpoint(.elbows, "Out at about 60 degrees from the body"),
                Checkpoint(.hands, "Bar to the upper chest"),
                Checkpoint(.shoulders, "Pinch the shoulder blades together, keep them down"),
                Checkpoint(.back, "Tall and still, no rocking"),
            ],
            mistakes: ["Leaning far back to move the weight", "Shrugging the shoulders up", "Elbows dropping to the sides"],
            breathing: "Exhale as you row, inhale as you return"
        ),
        "renegade-row": Technique(
            setup: ["Push-up position, hands on two dumbbells under the shoulders", "Feet wider than the hips"],
            position: [
                Checkpoint(.core, "Braced in a straight line from head to heels"),
                Checkpoint(.hips, "Square to the floor while one hand rows"),
                Checkpoint(.elbows, "Row toward the hip, close to the body"),
                Checkpoint(.hands, "Support hand pushes into its dumbbell"),
            ],
            mistakes: ["Hips twisting or sagging", "Feet too close together", "Rushing and dropping the dumbbell"],
            breathing: "Exhale as you row, inhale as you set it down"
        ),
        "smith-inverted-row": Technique(
            setup: ["Lock the Smith bar at about hip height", "Hang under it with an overhand grip, heels on the floor"],
            position: [
                Checkpoint(.core, "Body in one straight line, glutes tight"),
                Checkpoint(.hands, "Just wider than the shoulders"),
                Checkpoint(.shoulders, "Pull the shoulder blades back, chest to the bar"),
                Checkpoint(.feet, "Heels planted; bend the knees to make it easier"),
            ],
            mistakes: ["Hips sagging", "Reaching with the chin", "Half reps short of the bar"],
            breathing: "Exhale as you pull up, inhale as you lower"
        ),

        // MARK: Pull-ups and pulldowns
        "assisted-pull-up": Technique(
            setup: ["Pick an assist that allows clean, full reps", "Kneel on the pad and grip the handles"],
            position: [
                Checkpoint(.shoulders, "Pull them down and back before the arms bend"),
                Checkpoint(.elbows, "Drive down toward the ribs"),
                Checkpoint(.head, "Chest up to the bar, chin clears it"),
                Checkpoint(.core, "Braced, knees steady on the pad"),
            ],
            mistakes: ["Too much assist", "Stopping short of a full hang", "Swinging or bouncing on the pad"],
            breathing: "Exhale as you pull up, inhale as you lower"
        ),
        "negative-pull-up": Technique(
            setup: ["Box under the bar", "Jump or step up so the chin is over the bar"],
            position: [
                Checkpoint(.shoulders, "Stay pulled down as you lower"),
                Checkpoint(.elbows, "Straighten slowly, about 5 seconds"),
                Checkpoint(.hands, "Grip hard all the way to a full hang"),
                Checkpoint(.core, "Tight, legs still"),
            ],
            mistakes: ["Dropping fast through the bottom half", "Shrugging into the ears", "Kicking to slow down"],
            breathing: "Breathe steadily during the lower, inhale at the top"
        ),
        "neutral-grip-pull-up": Technique(
            setup: ["Grip the parallel handles, palms facing each other", "Hang with arms straight"],
            position: [
                Checkpoint(.shoulders, "Set down and back to start the pull"),
                Checkpoint(.elbows, "Drive down in front of the body"),
                Checkpoint(.head, "Chest rises to the handles"),
                Checkpoint(.core, "Braced, no swinging"),
            ],
            mistakes: ["Kipping", "Half reps without a full hang", "Craning the neck over the handles"],
            breathing: "Exhale as you pull up, inhale as you lower"
        ),
        "close-grip-pulldown": Technique(
            setup: ["Attach a V-handle, thighs snug under the pads", "Arms straight, slight lean back"],
            position: [
                Checkpoint(.back, "Lean back slightly and hold that angle"),
                Checkpoint(.elbows, "Pull down close to the body"),
                Checkpoint(.hands, "Handle to the upper chest"),
                Checkpoint(.shoulders, "Down, away from the ears"),
            ],
            mistakes: ["Rocking back to move the weight", "Pulling with the arms only", "Letting the stack slam at the top"],
            breathing: "Exhale as you pull, inhale as you return"
        ),
        "reverse-grip-pulldown": Technique(
            setup: ["Underhand grip at shoulder width", "Thighs under the pads, chest up"],
            position: [
                Checkpoint(.hands, "Palms toward you, wrists straight"),
                Checkpoint(.elbows, "Drive down to the ribs"),
                Checkpoint(.shoulders, "Pull the shoulder blades down first"),
                Checkpoint(.back, "Slight lean, no swinging"),
            ],
            mistakes: ["Grip too wide for an underhand pull", "Leaning far back", "Rushing the way up"],
            breathing: "Exhale as you pull, inhale on the slow return"
        ),
        "straight-arm-pulldown": Technique(
            setup: ["High pulley with a straight bar or rope", "Step back and hinge slightly, arms long and up"],
            position: [
                Checkpoint(.elbows, "Almost straight and locked in place"),
                Checkpoint(.hands, "Sweep in an arc down to the thighs"),
                Checkpoint(.core, "Ribs down, no arching"),
                Checkpoint(.hips, "Hinged and still"),
            ],
            mistakes: ["Bending the elbows into a pushdown", "Arching the back at the bottom", "Using body weight to move the bar"],
            breathing: "Exhale as you sweep down, inhale as the arms rise"
        ),

        // MARK: Curls
        "concentration-curl": Technique(
            setup: ["Sit on the end of a bench, feet wide", "Lean in and brace the back of the elbow on the inner thigh"],
            position: [
                Checkpoint(.elbows, "Stays on the thigh, only the forearm moves"),
                Checkpoint(.hands, "Curl toward the shoulder, palm up"),
                Checkpoint(.shoulders, "Relaxed, no shrugging"),
                Checkpoint(.back, "Leaned in and still"),
            ],
            mistakes: ["Lifting the elbow off the thigh", "Swinging the torso", "Dropping the weight fast"],
            breathing: "Exhale as you curl, inhale as you lower slowly"
        ),
        "spider-curl": Technique(
            setup: ["Lie chest-down on an incline bench", "Let the arms hang straight down in front of the pad"],
            position: [
                Checkpoint(.elbows, "Fixed under the shoulders"),
                Checkpoint(.hands, "Curl up and squeeze at the top"),
                Checkpoint(.shoulders, "Down, not rolling forward"),
                Checkpoint(.core, "Chest stays on the pad"),
            ],
            mistakes: ["Elbows swinging forward", "Lifting the chest off the pad", "Partial reps at the bottom"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "ez-preacher-curl": Technique(
            setup: ["Set the seat so the armpits sit on the top of the pad", "Grip the EZ bar on the angled handles"],
            position: [
                Checkpoint(.elbows, "Flat on the pad; stop just short of lockout"),
                Checkpoint(.hands, "Wrists straight on the angled grip"),
                Checkpoint(.shoulders, "Down and still"),
                Checkpoint(.back, "Chest against the pad, no rocking"),
            ],
            mistakes: ["Dropping into a locked elbow", "Lifting the elbows off the pad", "Fast lowering"],
            breathing: "Exhale as you curl, inhale over a 3 second lower"
        ),
        "bayesian-curl": Technique(
            setup: ["Low pulley with a D-handle, face away from the machine", "Step forward until the arm is pulled behind the body"],
            position: [
                Checkpoint(.elbows, "Stay behind the torso and do not move"),
                Checkpoint(.hands, "Curl up, palm facing up"),
                Checkpoint(.shoulders, "Open and back, feel the stretch"),
                Checkpoint(.feet, "Staggered stance for balance"),
            ],
            mistakes: ["Elbow drifting forward", "Leaning forward to cut the stretch", "Shrugging the shoulder"],
            breathing: "Exhale as you curl, inhale on the stretch"
        ),
        "drag-curl": Technique(
            setup: ["Stand tall, barbell at the thighs, shoulder-width underhand grip"],
            position: [
                Checkpoint(.elbows, "Drift back behind the body as you curl"),
                Checkpoint(.hands, "Bar stays in contact with the torso"),
                Checkpoint(.shoulders, "Down, no shrugging"),
                Checkpoint(.core, "Braced, no swing"),
            ],
            mistakes: ["Elbows moving forward like a normal curl", "Bar drifting away from the body", "Leaning back"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "zottman-curl": Technique(
            setup: ["Stand tall, a dumbbell in each hand, palms forward"],
            position: [
                Checkpoint(.hands, "Curl palms up, turn them down at the top"),
                Checkpoint(.elbows, "Pinned to the sides"),
                Checkpoint(.hands, "Lower slowly with the palms down"),
                Checkpoint(.core, "Braced, no swinging"),
            ],
            mistakes: ["Rushing the lowering phase", "Turning the palms before the top", "Elbows drifting forward"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "band-curl": Technique(
            setup: ["Stand on the middle of the band, feet hip-width", "Hold the ends or handles, palms forward"],
            position: [
                Checkpoint(.elbows, "Pinned to the sides"),
                Checkpoint(.hands, "Curl up and squeeze at the top"),
                Checkpoint(.feet, "Planted on the band so it cannot slip"),
                Checkpoint(.core, "Tall and braced"),
            ],
            mistakes: ["Letting the band snap the arms down", "Leaning back at the top", "Elbows moving forward"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "rope-hammer-curl": Technique(
            setup: ["Rope on a low pulley", "Stand facing the machine, thumbs up on the rope"],
            position: [
                Checkpoint(.hands, "Thumbs up the whole way"),
                Checkpoint(.elbows, "Pinned to the sides"),
                Checkpoint(.shoulders, "Down and still"),
                Checkpoint(.core, "Braced, no leaning back"),
            ],
            mistakes: ["Swinging the hips", "Elbows drifting forward", "Wrists bending back"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "cross-body-hammer-curl": Technique(
            setup: ["Stand tall, dumbbells at the sides, palms facing in"],
            position: [
                Checkpoint(.hands, "Thumb up, curl toward the opposite shoulder"),
                Checkpoint(.elbows, "Stays low and close to the body"),
                Checkpoint(.shoulders, "Square, no twisting"),
                Checkpoint(.core, "Braced as you alternate arms"),
            ],
            mistakes: ["Rotating the torso to swing it across", "Elbow lifting forward", "Rushing the lower"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "reverse-ez-curl": Technique(
            setup: ["Overhand grip on the EZ bar, hands about shoulder-width", "Stand tall, bar at the thighs"],
            position: [
                Checkpoint(.hands, "Palms down, wrists straight"),
                Checkpoint(.elbows, "Still at the sides"),
                Checkpoint(.shoulders, "Down, no shrugging"),
                Checkpoint(.core, "Braced, no swing"),
            ],
            mistakes: ["Wrists bending back", "Going too heavy and swinging", "Elbows flaring"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),

        // MARK: Triceps
        "rope-pushdown": Technique(
            setup: ["Rope on a high pulley", "Stand close, slight forward lean, elbows at the sides"],
            position: [
                Checkpoint(.elbows, "Pinned to the sides"),
                Checkpoint(.hands, "Split the rope apart at the bottom"),
                Checkpoint(.shoulders, "Down and still"),
                Checkpoint(.core, "Braced, no rocking"),
            ],
            mistakes: ["Elbows drifting forward", "Leaning over the weight", "Letting the rope fly back up"],
            breathing: "Exhale as you push down, inhale as you return"
        ),
        "single-arm-pushdown": Technique(
            setup: ["D-handle on a high pulley", "Stand side-on or facing it, working elbow at the side"],
            position: [
                Checkpoint(.elbows, "Fixed at the side"),
                Checkpoint(.hands, "Push to full lockout"),
                Checkpoint(.shoulders, "Square, no dipping toward the handle"),
                Checkpoint(.core, "Braced"),
            ],
            mistakes: ["Elbow flaring out", "Leaning onto the handle", "Stopping short of lockout"],
            breathing: "Exhale as you push down, inhale as you return"
        ),
        "band-pushdown": Technique(
            setup: ["Anchor the band high, over a bar or door", "Grip the ends, elbows at the sides"],
            position: [
                Checkpoint(.elbows, "Pinned to the sides"),
                Checkpoint(.hands, "Squeeze at full lockout"),
                Checkpoint(.shoulders, "Down and still"),
                Checkpoint(.core, "Braced, slight forward lean"),
            ],
            mistakes: ["Elbows moving forward", "Letting the band snap back", "Shrugging"],
            breathing: "Exhale as you push down, inhale as you return"
        ),
        "db-kickback": Technique(
            setup: ["One hand and knee on a flat bench, other foot on the floor", "Dumbbell in the free hand, upper arm parallel to the floor"],
            position: [
                Checkpoint(.elbows, "Upper arm stays parallel to the floor and still"),
                Checkpoint(.hands, "Straighten the arm fully behind you"),
                Checkpoint(.back, "Flat, parallel to the floor"),
                Checkpoint(.shoulders, "Level, no twisting"),
            ],
            mistakes: ["Upper arm dropping as you tire", "Swinging the weight", "Partial lockout"],
            breathing: "Exhale as you straighten, inhale as you return"
        ),
        "cable-kickback": Technique(
            setup: ["Low pulley, handle or cuff in one hand", "Hinge forward, upper arm alongside the body"],
            position: [
                Checkpoint(.elbows, "Upper arm fixed by the torso"),
                Checkpoint(.hands, "Straighten back fully"),
                Checkpoint(.back, "Flat in the hinge"),
                Checkpoint(.hips, "Hinged and still"),
            ],
            mistakes: ["Swinging the upper arm", "Standing up during the rep", "Short range"],
            breathing: "Exhale as you straighten, inhale as you return"
        ),
        "jm-press": Technique(
            setup: ["Lie on a flat bench in the rack, feet planted", "Close grip, just inside shoulder-width"],
            position: [
                Checkpoint(.hands, "Lower the bar toward the chin"),
                Checkpoint(.elbows, "Point forward toward the feet as they bend"),
                Checkpoint(.shoulders, "Pinned to the bench"),
                Checkpoint(.back, "Natural arch, butt on the bench"),
            ],
            mistakes: ["Turning it into a bench press", "Elbows flaring out", "Dropping the bar fast toward the face"],
            breathing: "Inhale as you lower, exhale as you press up"
        ),
        "tate-press": Technique(
            setup: ["Lie on a flat bench, dumbbells pressed up", "Turn them so they sit end to end over the chest"],
            position: [
                Checkpoint(.elbows, "Point out to the sides and stay high"),
                Checkpoint(.hands, "Lower the dumbbells to touch the chest"),
                Checkpoint(.shoulders, "Still, no pressing with the chest"),
                Checkpoint(.feet, "Planted for stability"),
            ],
            mistakes: ["Elbows dropping to the sides", "Going too heavy", "Bouncing the dumbbells off the chest"],
            breathing: "Inhale as you lower, exhale as you press up"
        ),
        "ez-overhead-triceps": Technique(
            setup: ["Sit on an upright bench, back supported", "Press the EZ bar overhead on the narrow grip"],
            position: [
                Checkpoint(.elbows, "Narrow and pointing up"),
                Checkpoint(.hands, "Lower behind the head for a deep stretch"),
                Checkpoint(.back, "Against the pad, ribs down"),
                Checkpoint(.head, "Neutral, bar travels behind it"),
            ],
            mistakes: ["Elbows flaring out", "Arching off the pad", "Short range at the bottom"],
            breathing: "Inhale as you lower, exhale as you extend"
        ),

        // MARK: Grip and shrugs
        "wrist-curl": Technique(
            setup: ["Kneel or sit at a bench, forearms along the pad, palms up", "Hands just past the edge, light dumbbells"],
            position: [
                Checkpoint(.elbows, "Forearms stay flat on the bench"),
                Checkpoint(.hands, "Roll the dumbbell to the fingertips, then curl the wrist up"),
                Checkpoint(.shoulders, "Relaxed, arms do not lift"),
            ],
            mistakes: ["Lifting the forearms off the bench", "Going too heavy", "Bouncing at the bottom"],
            breathing: "Exhale as you curl up, inhale as you lower"
        ),
        "dead-hang": Technique(
            setup: ["Grip the bar overhand, about shoulder-width", "Lift the feet and hang with arms straight"],
            position: [
                Checkpoint(.hands, "Full grip, thumbs wrapped"),
                Checkpoint(.shoulders, "Active, pulled slightly away from the ears"),
                Checkpoint(.core, "Lightly braced, legs still"),
                Checkpoint(.elbows, "Straight"),
            ],
            mistakes: ["Fully slumped, shoulders jammed into the ears", "Swinging", "Holding the breath"],
            breathing: "Slow, steady breathing throughout the hold"
        ),
        "trap-bar-shrug": Technique(
            setup: ["Stand in the centre of the trap bar", "Deadlift it up and stand tall"],
            position: [
                Checkpoint(.shoulders, "Straight up toward the ears, hold 1 second"),
                Checkpoint(.elbows, "Straight, arms just hang"),
                Checkpoint(.head, "Neutral, chin level"),
                Checkpoint(.core, "Braced and tall"),
            ],
            mistakes: ["Rolling the shoulders", "Bending the elbows to help", "Jutting the head forward"],
            breathing: "Exhale as you shrug, inhale as you lower"
        ),
        "cable-shrug": Technique(
            setup: ["Straight bar on a low pulley", "Stand close, arms straight, bar at the thighs"],
            position: [
                Checkpoint(.shoulders, "Shrug up and slightly back"),
                Checkpoint(.elbows, "Straight throughout"),
                Checkpoint(.head, "Neutral"),
                Checkpoint(.core, "Tall and braced"),
            ],
            mistakes: ["Rolling the shoulders", "Pulling with the arms", "Dropping the bar quickly"],
            breathing: "Exhale as you shrug, inhale as you lower slowly"
        ),
    ]
}
