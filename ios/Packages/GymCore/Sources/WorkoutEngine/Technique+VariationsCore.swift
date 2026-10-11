// Technique content for the catalog extension (#174): core, carries, power, cardio, mobility.

extension Technique {
    static let variationsCore: [String: Technique] = [
        // Core
        "hanging-leg-raise": Technique(
            setup: ["Hang from the pull-up bar, hands shoulder-width, arms straight", "Legs together, still, toes pointed slightly"],
            position: [
                Checkpoint(.shoulders, "Pulled down and engaged, not hanging loose at the ears"),
                Checkpoint(.knees, "Straight; the legs rise as one unit"),
                Checkpoint(.hips, "Curl the pelvis up at the top so the abs finish the lift"),
                Checkpoint(.core, "Braced to kill any swing between reps"),
            ],
            mistakes: ["Swinging the body to throw the legs up", "Bending the knees to shorten the lever", "Dropping the legs fast"],
            breathing: "Exhale as the legs rise, inhale as you lower them under control"
        ),
        "bicycle-crunch": Technique(
            setup: ["Lie on your back on a mat, fingertips lightly behind the head", "Lift the shoulders and both feet off the floor"],
            position: [
                Checkpoint(.shoulders, "Off the mat; rotate so one elbow travels to the opposite knee"),
                Checkpoint(.head, "Neck relaxed, hands only support it, never pull"),
                Checkpoint(.knees, "One knee draws in while the other leg extends long and low"),
                Checkpoint(.back, "Lower back stays pressed into the mat"),
            ],
            mistakes: ["Yanking the head forward with the hands", "Rushing, flapping the elbows instead of turning the ribs", "Lower back arching off the mat"],
            breathing: "Exhale on each twist, inhale as you pass through the middle"
        ),
        "v-up": Technique(
            setup: ["Lie flat on a mat, legs straight, arms long overhead", "Press the lower back down before you start"],
            position: [
                Checkpoint(.core, "Lift the arms and legs together, folding at the hips"),
                Checkpoint(.hands, "Reach for the shins or toes at the top"),
                Checkpoint(.knees, "Straight; bend them slightly only if the back arches"),
                Checkpoint(.back, "Lower back comes down first on the way back"),
            ],
            mistakes: ["Flopping back down to the mat", "Leading with the chin and arms only", "Arching the lower back as the legs lower"],
            breathing: "Exhale as you fold up, inhale as you lower"
        ),
        "dragon-flag": Technique(
            setup: ["Lie on a flat bench, head near one end", "Grip the bench behind the head, then roll up onto the upper back"],
            position: [
                Checkpoint(.shoulders, "Only the upper back touches the bench; the body pivots there"),
                Checkpoint(.hips, "Straight in line with the shoulders, no pike"),
                Checkpoint(.core, "Rigid from shoulders to toes as you lower"),
                Checkpoint(.knees, "Straight; tuck them to regress"),
            ],
            mistakes: ["Breaking at the hips into a pike", "Dropping the lower half fast", "Arching the lower back"],
            breathing: "Inhale at the top, exhale slowly as you lower"
        ),
        "l-sit": Technique(
            setup: ["Hands on the dip bars, arms locked, body hanging between them", "Press down to lift the body"],
            position: [
                Checkpoint(.elbows, "Locked straight the whole hold"),
                Checkpoint(.shoulders, "Pushed down away from the ears"),
                Checkpoint(.knees, "Straight, legs at hip height; tuck them to make it easier"),
                Checkpoint(.feet, "Pointed, legs squeezed together"),
            ],
            mistakes: ["Shrugging the shoulders up", "Bent elbows", "Legs drooping below hip height"],
            breathing: "Short steady breaths, keep the brace"
        ),
        "russian-twist": Technique(
            setup: ["Sit on a mat, knees bent, holding a med ball at the chest", "Lean back until the abs switch on, feet down or lifted"],
            position: [
                Checkpoint(.back, "Long spine, chest up, about 45 degrees back"),
                Checkpoint(.shoulders, "Turn the ribs and shoulders, not just the arms"),
                Checkpoint(.hands, "Ball travels beside each hip"),
                Checkpoint(.feet, "Down for an easier version, lifted to progress"),
            ],
            mistakes: ["Rounding the back", "Only swinging the arms", "Going so fast the movement turns into a bounce"],
            breathing: "Exhale on each turn, inhale through the middle"
        ),
        "cable-woodchop": Technique(
            setup: ["Set the pulley high, stand side-on to it", "Both hands on the handle, arms long, feet wider than the hips"],
            position: [
                Checkpoint(.hands, "Pull on a diagonal from high to low across the body"),
                Checkpoint(.elbows, "Stay nearly straight; the trunk does the work"),
                Checkpoint(.hips, "Turn with the torso, finish facing away from the stack"),
                Checkpoint(.feet, "Pivot the back foot as you rotate"),
            ],
            mistakes: ["Pulling with the arms instead of rotating", "Rounding over at the bottom", "Letting the stack yank you back"],
            breathing: "Exhale as you chop down, inhale as you return"
        ),
        "cable-low-high-chop": Technique(
            setup: ["Set the pulley low, stand side-on to it", "Both hands on the handle by the outside knee, hips back"],
            position: [
                Checkpoint(.hands, "Drive up and across to above the opposite shoulder"),
                Checkpoint(.hips, "Extend and turn together with the chest"),
                Checkpoint(.elbows, "Long arms, no curling or pressing"),
                Checkpoint(.feet, "Pivot the back foot as you rise"),
            ],
            mistakes: ["Lifting with the arms only", "Leaning back at the top", "Rushing the return"],
            breathing: "Exhale as you drive up, inhale as you lower"
        ),
        "bird-dog": Technique(
            setup: ["On all fours on a mat, hands under shoulders, knees under hips", "Back flat, neck long"],
            position: [
                Checkpoint(.hands, "Reach one arm long, thumb up, at shoulder height"),
                Checkpoint(.feet, "Push the opposite heel back to hip height"),
                Checkpoint(.hips, "Level, no rotating towards the lifted leg"),
                Checkpoint(.back, "Flat; pause 2 s at full reach"),
            ],
            mistakes: ["Lifting the leg too high and arching", "Hips tipping open", "Rushing between sides"],
            breathing: "Exhale as you reach, inhale as you return"
        ),
        "mountain-climber": Technique(
            setup: ["High plank, hands under the shoulders", "Body straight from head to heels"],
            position: [
                Checkpoint(.hands, "Stay planted under the shoulders"),
                Checkpoint(.knees, "Drive towards the chest one at a time, fast"),
                Checkpoint(.hips, "Low and level, not bouncing up"),
                Checkpoint(.core, "Braced so the trunk stays still"),
            ],
            mistakes: ["Hips piking up", "Shoulders drifting behind the hands", "Short choppy steps that never reach the chest"],
            breathing: "Quick rhythmic breaths, one per couple of steps"
        ),
        "rkc-plank": Technique(
            setup: ["Forearm plank on a mat, elbows under the eyes, fists together", "Feet together, legs straight"],
            position: [
                Checkpoint(.elbows, "Pull them towards the toes without moving them"),
                Checkpoint(.hips, "Tuck the pelvis, squeeze the glutes hard"),
                Checkpoint(.knees, "Locked, quads tight"),
                Checkpoint(.core, "Maximum brace; short, hard sets"),
            ],
            mistakes: ["Relaxed glutes, sagging hips", "Hips piked high", "Holding long and soft instead of short and hard"],
            breathing: "Short breaths behind a tight brace"
        ),
        "stir-the-pot": Technique(
            setup: ["Forearms on a stability ball, hands together", "Walk the feet back into a plank, feet hip-width"],
            position: [
                Checkpoint(.elbows, "Under the shoulders, drawing small circles"),
                Checkpoint(.hips, "Still and level while the ball moves"),
                Checkpoint(.core, "Braced so the lower back does not sag"),
                Checkpoint(.feet, "Wider for stability, narrower to progress"),
            ],
            mistakes: ["Circles so big the hips sway", "Sagging lower back", "Holding the breath"],
            breathing: "Slow breaths through each circle"
        ),
        "db-side-bend": Technique(
            setup: ["Stand tall, one dumbbell at your side", "Other hand behind the head, feet hip-width"],
            position: [
                Checkpoint(.back, "Bend straight sideways, no leaning forward or back"),
                Checkpoint(.hips, "Stay square and still"),
                Checkpoint(.core, "Pull back up with the far side"),
                Checkpoint(.hands, "Dumbbell slides down the side of the leg"),
            ],
            mistakes: ["Twisting or tipping forward", "Holding a dumbbell in each hand", "Using momentum to bounce"],
            breathing: "Inhale as you lower, exhale as you pull up"
        ),
        "turkish-get-up": Technique(
            setup: ["Lie on a mat, bell pressed straight up over the shoulder", "Same-side knee bent, foot flat; other arm and leg out at 45 degrees"],
            position: [
                Checkpoint(.elbows, "Locked out with the bell over the shoulder the whole time"),
                Checkpoint(.head, "Eyes on the bell"),
                Checkpoint(.hands, "Free hand posts on the floor to the tall sit"),
                Checkpoint(.hips, "Bridge up, sweep the leg through, then stand from half-kneeling"),
            ],
            mistakes: ["Bent arm or bell drifting off the shoulder", "Rushing the steps", "Looking away from the bell"],
            breathing: "Breathe at each position; brace before every transition"
        ),
        // Carries
        "trap-bar-carry": Technique(
            setup: ["Step inside the trap bar, grip the handles in the centre", "Stand up like a deadlift: hips and chest together"],
            position: [
                Checkpoint(.shoulders, "Down and back, tall posture"),
                Checkpoint(.hands, "Crush the handles, bar level"),
                Checkpoint(.core, "Braced, no side to side sway"),
                Checkpoint(.feet, "Short, quick steps"),
            ],
            mistakes: ["Picking the bar up with a rounded back", "Shrugging and leaning forward", "Long strides that tip the bar"],
            breathing: "Short breaths behind the brace while walking"
        ),
        "front-rack-carry": Technique(
            setup: ["Clean two kettlebells to the rack", "Bells on the outside of the forearms, fists by the chin"],
            position: [
                Checkpoint(.elbows, "Tucked in front of the ribs"),
                Checkpoint(.hands, "Wrists straight, fists close to the chest"),
                Checkpoint(.core, "Ribs down, no leaning back under the load"),
                Checkpoint(.feet, "Steady, controlled steps"),
            ],
            mistakes: ["Leaning back and arching", "Elbows flaring out", "Bent wrists"],
            breathing: "Short breaths, stay braced"
        ),
        "sled-drag": Technique(
            setup: ["Face the sled, a handle or strap in each hand", "Arms long, sit into a quarter squat"],
            position: [
                Checkpoint(.elbows, "Straight; the legs pull, not the arms"),
                Checkpoint(.knees, "Bent and tracking over the toes"),
                Checkpoint(.feet, "Reach back with each step, land on the ball of the foot"),
                Checkpoint(.back, "Neutral, chest up"),
            ],
            mistakes: ["Standing up tall", "Rowing with the arms", "Tiny shuffling steps"],
            breathing: "Steady rhythmic breaths, one per step or two"
        ),
        // Power
        "power-clean": Technique(
            setup: ["Mid-foot under the bar, hands just outside the legs", "Hips low, chest up, shoulders slightly in front of the bar"],
            position: [
                Checkpoint(.back, "Flat from the floor until the bar passes the knees"),
                Checkpoint(.hips, "Explode: jump and shrug once the bar reaches the thighs"),
                Checkpoint(.elbows, "Whip around fast to catch the bar in the rack"),
                Checkpoint(.knees, "Catch in a quarter squat, then stand"),
            ],
            mistakes: ["Pulling with the arms too early", "Rounding the back off the floor", "Slow elbows, catching on the fingertips"],
            breathing: "Breathe in and brace at the floor, exhale after the catch"
        ),
        "push-press": Technique(
            setup: ["Bar in the front rack from the rack, hands just outside the shoulders", "Feet hip-width, elbows slightly in front of the bar"],
            position: [
                Checkpoint(.knees, "Short dip straight down, knees forward"),
                Checkpoint(.hips, "Drive up hard with the legs to launch the bar"),
                Checkpoint(.head, "Move it back so the bar passes straight up, then through"),
                Checkpoint(.elbows, "Locked out overhead, bar over the mid-foot"),
            ],
            mistakes: ["Deep or slow dip", "Torso tipping forward in the dip", "Pressing before the legs finish"],
            breathing: "Inhale and brace before the dip, exhale at lockout"
        ),
        "db-snatch": Technique(
            setup: ["Dumbbell on the floor between the feet", "Hinge down, back flat, one hand on the handle"],
            position: [
                Checkpoint(.hips, "Explode up like a jump"),
                Checkpoint(.elbows, "Pull high and close, then punch under"),
                Checkpoint(.hands, "Finish locked out overhead, biceps by the ear"),
                Checkpoint(.back, "Flat at the start, tall at the finish"),
            ],
            mistakes: ["Lifting with the arm instead of the hips", "Dumbbell swinging away from the body", "Soft elbow at lockout"],
            breathing: "Inhale at the bottom, exhale sharply at the drive"
        ),
        "kb-clean": Technique(
            setup: ["Bell slightly in front of the feet, feet shoulder-width", "Hinge, grip the handle and hike it back"],
            position: [
                Checkpoint(.hips, "Snap them forward from the hike pass"),
                Checkpoint(.elbows, "Close to the body, zip the bell up"),
                Checkpoint(.hands, "Open the hand and roll the bell softly into the rack"),
                Checkpoint(.core, "Braced at the top, standing tall"),
            ],
            mistakes: ["Swinging the bell out wide so it flips onto the forearm", "Curling it up with the arm", "Leaning back in the rack"],
            breathing: "Exhale sharply as the hips snap, breathe in the rack"
        ),
        "tuck-jump": Technique(
            setup: ["Stand feet hip-width, arms ready", "Dip quickly into a quarter squat"],
            position: [
                Checkpoint(.hips, "Drive up explosively with the arms"),
                Checkpoint(.knees, "Pull them to the chest at the top of the jump"),
                Checkpoint(.feet, "Land softly on the balls, then heels"),
                Checkpoint(.core, "Tight in the air, upright on landing"),
            ],
            mistakes: ["Bringing the chest down to the knees", "Stiff, loud landings", "Chaining reps before you are stable"],
            breathing: "Exhale on the jump, reset your breath each rep"
        ),
        "med-ball-scoop-toss": Technique(
            setup: ["Stand side-on to the wall, an arm's length plus a step away", "Ball low on the outside of the back knee, hips loaded"],
            position: [
                Checkpoint(.hips, "Drive from the back hip, then turn to the wall"),
                Checkpoint(.hands, "Scoop under and release up and across"),
                Checkpoint(.back, "Flat at the load, tall at release"),
                Checkpoint(.feet, "Pivot the back foot as you throw"),
            ],
            mistakes: ["Throwing with the arms only", "Rounding the back to reach the ball", "No hip turn"],
            breathing: "Inhale in the load, exhale sharply on release"
        ),
        "battle-rope-waves": Technique(
            setup: ["One rope end in each hand, step back until the slack is out", "Athletic half squat, chest up"],
            position: [
                Checkpoint(.hands, "Alternate fast, one up while the other goes down"),
                Checkpoint(.elbows, "Slightly bent, arms do short powerful strokes"),
                Checkpoint(.knees, "Bent and still"),
                Checkpoint(.core, "Braced so the torso does not bob"),
            ],
            mistakes: ["Standing up straight", "Waves dying before the anchor", "Big slow arm swings"],
            breathing: "Short rhythmic breaths, don't hold it"
        ),
        // Cardio
        "burpee": Technique(
            setup: ["Stand feet hip-width", "Squat and place the hands flat in front of the feet"],
            position: [
                Checkpoint(.feet, "Jump back to a plank, then jump in to the hands"),
                Checkpoint(.core, "Chest to the floor in one line, no sagging"),
                Checkpoint(.hips, "Jump up tall from the squat"),
                Checkpoint(.hands, "Reach overhead at the top"),
            ],
            mistakes: ["Sagging lower back in the plank", "Landing with straight legs", "Starting too fast to keep the pace"],
            breathing: "Exhale on the jump, inhale on the way down"
        ),
        "jumping-jacks": Technique(
            setup: ["Stand tall, feet together, arms at your sides"],
            position: [
                Checkpoint(.feet, "Jump them out wider than the hips and back in, light on the toes"),
                Checkpoint(.hands, "Swing them overhead as the feet go out"),
                Checkpoint(.knees, "Soft on every landing"),
            ],
            mistakes: ["Landing flat-footed and heavy", "Half arm swings", "Knees caving in"],
            breathing: "Easy rhythmic breaths in time with the jumps"
        ),
        "high-knees": Technique(
            setup: ["Stand tall on the balls of the feet", "Elbows bent at 90 degrees"],
            position: [
                Checkpoint(.knees, "Drive to hip height, one after the other"),
                Checkpoint(.feet, "Stay on the balls, quick light contacts"),
                Checkpoint(.hands, "Pump the arms fast, opposite to the legs"),
                Checkpoint(.core, "Tall, no leaning back"),
            ],
            mistakes: ["Leaning back to lift the knees", "Landing on the heels", "Knees stopping below the hips"],
            breathing: "Quick rhythmic breaths"
        ),
        // Mobility / stretch
        "foam-roll-quads": Technique(
            setup: ["Lie face down, foam roller under the thighs", "Weight on the forearms, elbows under the shoulders"],
            position: [
                Checkpoint(.elbows, "Walk the body slowly over the roller"),
                Checkpoint(.hips, "Roll from hip to just above the knee; turn the hip out to reach the side of the thigh"),
                Checkpoint(.core, "Braced, so the lower back does not sag"),
            ],
            mistakes: ["Rolling too fast", "Rolling over the kneecap", "Holding the breath on tight spots"],
            breathing: "Long breaths out, pause on tight spots"
        ),
        "foam-roll-calves": Technique(
            setup: ["Sit with a foam roller under one calf", "Hands behind you, cross the other leg on top"],
            position: [
                Checkpoint(.hands, "Push through them to lift the hips"),
                Checkpoint(.feet, "Turn the foot in and out to reach both sides of the calf"),
                Checkpoint(.knees, "Roll from just above the ankle to below the knee"),
            ],
            mistakes: ["Rolling too fast", "Rolling behind the knee", "Shoulders shrugged up"],
            breathing: "Slow breaths, exhale on tight spots"
        ),
        "standing-quad-stretch": Technique(
            setup: ["Stand tall, a hand on a wall if needed", "Bend one knee and hold the ankle behind you"],
            position: [
                Checkpoint(.feet, "Pull the heel towards the glute"),
                Checkpoint(.knees, "Together, the bent knee points at the floor"),
                Checkpoint(.hips, "Tuck the pelvis to deepen the stretch"),
            ],
            mistakes: ["Arching the lower back", "Knee drifting forward or out", "Leaning forward"],
            breathing: "Slow breaths, relax into it on each exhale"
        ),
        "seated-forward-fold": Technique(
            setup: ["Sit on a mat, legs straight together, toes up", "Sit tall, arms overhead"],
            position: [
                Checkpoint(.hips, "Hinge forward from the hips"),
                Checkpoint(.back, "Long, don't collapse to reach further"),
                Checkpoint(.hands, "Rest on the shins, ankles or feet"),
                Checkpoint(.knees, "Straight but not locked hard"),
            ],
            mistakes: ["Rounding the back to reach the toes", "Bouncing", "Bent knees with the toes falling out"],
            breathing: "Slow breaths, fold a little deeper on each exhale"
        ),
        "lizard-stretch": Technique(
            setup: ["From a lunge, step the front foot outside the hands", "Lower the back knee to the mat"],
            position: [
                Checkpoint(.hands, "Inside the front foot, or drop to the forearms"),
                Checkpoint(.hips, "Sink them low and forward"),
                Checkpoint(.knees, "Front knee over the ankle, back knee on the mat"),
                Checkpoint(.back, "Long from the head to the back knee"),
            ],
            mistakes: ["Front knee caving inward", "Rounding the back", "Hips stuck high"],
            breathing: "Slow breaths, sink a little lower on each exhale"
        ),
    ]
}
