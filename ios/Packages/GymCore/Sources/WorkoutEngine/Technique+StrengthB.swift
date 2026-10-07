// Technique content: setup, body position, mistakes, breathing.

extension Technique {
    static let strengthB: [String: Technique] = [
        "inverted-row": Technique(
            setup: [
                "Shorten the TRX straps (or set rings) so handles hang at about hip height",
                "Grip handles with palms facing each other and walk feet forward under the anchor",
                "Lean back until arms are straight; steeper body angle makes it harder",
            ],
            position: [
                Checkpoint(.head, "Neutral neck, eyes toward the anchor point"),
                Checkpoint(.shoulders, "Pull shoulder blades back and down before the arms bend"),
                Checkpoint(.elbows, "Elbows travel back at about 45° from the torso"),
                Checkpoint(.hips, "Glutes squeezed, body one straight line from head to heels"),
                Checkpoint(.feet, "Heels planted, feet together or hip width"),
            ],
            mistakes: [
                "Hips sagging toward the floor during the pull",
                "Shrugging shoulders up toward the ears",
                "Stopping short instead of bringing chest to the handles",
            ],
            breathing: "Exhale as you row up, inhale as you lower under control"
        ),
        "pull-up": Technique(
            setup: [
                "Grip the bar just outside shoulder width, palms facing away",
                "Wrap the thumb around the bar for a secure grip",
                "Hang with straight arms, feet off the floor, legs together",
            ],
            position: [
                Checkpoint(.head, "Neutral neck; chest, not chin, reaches for the bar"),
                Checkpoint(.shoulders, "Start from an active hang: shoulders pulled away from the ears"),
                Checkpoint(.elbows, "Drive elbows down toward the ribs"),
                Checkpoint(.core, "Ribs down, slight hollow to stop swinging"),
                Checkpoint(.feet, "Legs together, slightly in front of the body"),
            ],
            mistakes: [
                "Kipping or swinging the legs to get over the bar",
                "Dropping into a passive dead hang between reps",
                "Cutting the range short at the top or bottom",
            ],
            breathing: "Exhale as you pull up, inhale as you lower slowly"
        ),
        "weighted-pull-up": Technique(
            setup: [
                "Load a dip belt with plates or hold a dumbbell between your feet",
                "Step up on a box and grip the bar just outside shoulder width",
                "Lower into an active hang before the first rep, weight hanging still",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulders packed down and back at the bottom of every rep"),
                Checkpoint(.elbows, "Pull elbows down and back until chest nears the bar"),
                Checkpoint(.core, "Brace hard so the load does not swing"),
                Checkpoint(.feet, "Legs together and still; squeeze the dumbbell if using one"),
            ],
            mistakes: [
                "Adding load before strict bodyweight reps are solid",
                "Dropping fast into the bottom and yanking the shoulders",
                "Kipping or partial reps to finish a set",
            ],
            breathing: "Brace and exhale on the way up, inhale on the slow way down"
        ),
        "lat-pulldown": Technique(
            setup: [
                "Set the thigh pad so your thighs are locked snugly under it",
                "Grip the wide bar just outside shoulder width, palms forward",
            ],
            position: [
                Checkpoint(.shoulders, "Pull shoulder blades down before the elbows bend"),
                Checkpoint(.elbows, "Drive elbows down toward your back pockets"),
                Checkpoint(.back, "Slight lean back (~10–15°), chest up to meet the bar"),
                Checkpoint(.feet, "Flat on the floor, knees at 90°"),
            ],
            mistakes: [
                "Swinging the torso back to move the weight",
                "Pulling the bar behind the neck",
            ],
            breathing: "Exhale as you pull down, inhale as the bar returns overhead"
        ),
        "single-arm-pulldown": Technique(
            setup: [
                "Set the cable pulley to the highest position with a single D-handle",
                "Kneel facing the stack, about an arm's length back from the pulley",
                "Grip the handle with one hand and let it pull the arm into a full overhead stretch",
            ],
            position: [
                Checkpoint(.shoulders, "Start each rep by drawing the shoulder blade down"),
                Checkpoint(.elbows, "Pull the elbow down to the side of the ribs"),
                Checkpoint(.core, "Ribs down, torso tall, no twisting toward the cable"),
                Checkpoint(.knees, "Both knees on a pad, hip width apart for a stable base"),
            ],
            mistakes: [
                "Rotating the torso to finish the pull",
                "Losing the full stretch overhead at the top",
                "Shrugging the working shoulder up",
            ],
            breathing: "Exhale as you pull down, inhale during the overhead stretch"
        ),
        "plank": Technique(
            setup: [
                "Lie face down on a mat, forearms under shoulders, elbows bent 90°",
                "Tuck toes and lift the body off the mat in one line",
            ],
            position: [
                Checkpoint(.head, "Neutral neck, gaze at the floor just ahead of the hands"),
                Checkpoint(.shoulders, "Directly over elbows; push the floor away"),
                Checkpoint(.core, "Ribs pulled down toward the hips, abs braced"),
                Checkpoint(.hips, "Glutes squeezed, hips level with shoulders"),
                Checkpoint(.feet, "Hip width apart, heels pressing back"),
            ],
            mistakes: [
                "Hips sagging and lower back arching",
                "Hips piked high to make it easier",
                "Holding the breath for the whole set",
            ],
            breathing: "Short steady breaths through the nose while keeping the brace"
        ),
        "dead-bug": Technique(
            setup: [
                "Lie on your back on a mat, arms reaching straight up over shoulders",
                "Lift legs so hips and knees are both at 90°",
                "Press the lower back flat into the mat before starting",
            ],
            position: [
                Checkpoint(.head, "Head relaxed on the mat, chin slightly tucked"),
                Checkpoint(.hands, "Reach the opposite arm overhead as one leg extends"),
                Checkpoint(.core, "Lower back stays glued to the floor the whole time"),
                Checkpoint(.hips, "Extend one leg low without letting the pelvis tip"),
            ],
            mistakes: [
                "Lower back lifting off the mat as the leg extends",
                "Moving fast and losing control",
                "Moving same-side arm and leg together",
            ],
            breathing: "Exhale fully as the limbs extend, inhale as they return"
        ),
        "ab-wheel": Technique(
            setup: [
                "Kneel on a mat or pad with the wheel on the floor under your shoulders",
                "Grip both handles, arms straight",
                "Tuck the pelvis and brace before rolling out",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulders active, arms reaching forward"),
                Checkpoint(.core, "Hollow body: ribs down, abs tight, no sag"),
                Checkpoint(.hips, "Hips move forward with the wheel, glutes squeezed"),
                Checkpoint(.knees, "Stay planted on the pad"),
            ],
            mistakes: [
                "Rolling out further than you can hold a neutral spine",
                "Lower back sagging at the far end",
                "Pulling back with the hips first instead of the abs",
            ],
            breathing: "Inhale as you roll out, exhale as you pull the wheel back"
        ),
        "trx-body-saw": Technique(
            setup: [
                "Lower the TRX foot cradles to about 15–20 cm off the floor",
                "Place both feet in the cradles, toes down",
                "Set up in a forearm plank with elbows directly under shoulders",
            ],
            position: [
                Checkpoint(.head, "Neutral neck, eyes on the floor"),
                Checkpoint(.shoulders, "Rock the body back past the elbows, then forward again"),
                Checkpoint(.core, "Ribs down and abs braced through the whole range"),
                Checkpoint(.hips, "Hips stay level with the shoulders, glutes on"),
            ],
            mistakes: [
                "Hips sagging as the body shifts backward",
                "Piking the hips up to shorten the lever",
                "Sawing too far before you can control it",
            ],
            breathing: "Exhale as you push back, inhale as you return forward"
        ),
        "pallof-press": Technique(
            setup: [
                "Set the cable pulley to chest height with a D-handle",
                "Stand side-on to the stack, about one step away so there is tension",
                "Hold the handle at your sternum with both hands, feet hip width",
            ],
            position: [
                Checkpoint(.shoulders, "Square to the front, not turned toward the cable"),
                Checkpoint(.hands, "Press straight out from the chest and hold 2 s"),
                Checkpoint(.core, "Brace against the pull; no rotation"),
                Checkpoint(.hips, "Hips level and facing forward"),
                Checkpoint(.knees, "Soft knees, feet planted"),
            ],
            mistakes: [
                "Letting the torso twist toward the cable",
                "Leaning away to fight the load",
                "Using a weight too heavy to hold still",
            ],
            breathing: "Exhale as you press out, breathe steadily during the hold"
        ),
        "side-plank": Technique(
            setup: [
                "Lie on your side on a mat, elbow directly under the shoulder",
                "Stack the feet, or stagger them for more balance",
                "Lift the hips until the body forms a straight line",
            ],
            position: [
                Checkpoint(.head, "In line with the spine, not dropping"),
                Checkpoint(.shoulders, "Push the floor away so you don't sink into the shoulder"),
                Checkpoint(.core, "Ribs down, obliques tight"),
                Checkpoint(.hips, "High and stacked, not rolling forward or back"),
                Checkpoint(.feet, "Stacked or staggered, pressing into the mat"),
            ],
            mistakes: [
                "Hips sagging toward the floor",
                "Sinking into the bottom shoulder",
                "Upper hip rolling forward",
            ],
            breathing: "Slow steady breaths while keeping the brace"
        ),
        "landmine-rotation": Technique(
            setup: [
                "Load one end of a barbell in the landmine; start light",
                "Stand facing the landmine, feet a bit wider than shoulders",
                "Hold the bar end with both hands at forehead height, arms nearly straight",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulders follow the bar; arms stay long"),
                Checkpoint(.hands, "Interlaced on the sleeve, arcing it to one hip then the other"),
                Checkpoint(.core, "Braced; rotation is controlled, not thrown"),
                Checkpoint(.hips, "Rotate from the hips with the torso"),
                Checkpoint(.feet, "Pivot the back foot as you turn"),
            ],
            mistakes: [
                "Twisting only through the lower back",
                "Bending the elbows to muscle the bar",
                "Letting the bar drop fast at the end of the arc",
            ],
            breathing: "Exhale as you rotate down, inhale as the bar returns to center"
        ),
        "hanging-knee-raise": Technique(
            setup: [
                "Grip the pull-up bar shoulder width, palms facing away",
                "Hang still with straight arms before the first rep",
            ],
            position: [
                Checkpoint(.shoulders, "Active hang: shoulders pulled down from the ears"),
                Checkpoint(.core, "Curl the pelvis up, not just lift the thighs"),
                Checkpoint(.hips, "Knees rise above hip height"),
                Checkpoint(.knees, "Bent, legs together"),
            ],
            mistakes: [
                "Swinging to build momentum",
                "Dropping the legs fast on the way down",
                "Hanging passively from the shoulders",
            ],
            breathing: "Exhale as the knees come up, inhale as they lower"
        ),
        "toes-to-bar": Technique(
            setup: [
                "Grip the pull-up bar shoulder width, palms facing away",
                "Hang still and engage the lats with straight arms",
            ],
            position: [
                Checkpoint(.shoulders, "Lats engaged, press the bar down slightly"),
                Checkpoint(.core, "Curl the pelvis and roll the hips up"),
                Checkpoint(.knees, "As straight as your hamstrings allow"),
                Checkpoint(.feet, "Touch the bar between the hands, then lower slowly"),
            ],
            mistakes: [
                "Kipping instead of strict control",
                "Dropping the legs and swinging into the next rep",
                "Bending the arms to shorten the distance",
            ],
            breathing: "Exhale as you lift the feet, inhale on the slow lower"
        ),
        "cable-crunch": Technique(
            setup: [
                "Set the cable pulley to the top with a rope attachment",
                "Kneel about an arm's length from the stack",
                "Hold the rope ends beside your head, hands near the ears",
            ],
            position: [
                Checkpoint(.head, "Chin tucked, head moves with the torso"),
                Checkpoint(.hands, "Fixed beside the head; arms do not pull"),
                Checkpoint(.back, "Round the spine, bringing the ribs to the pelvis"),
                Checkpoint(.hips, "Stay still above the knees, no sitting back"),
            ],
            mistakes: [
                "Sitting the hips back to move the weight",
                "Pulling with the arms",
                "Keeping the back flat instead of curling",
            ],
            breathing: "Exhale hard as you crunch down, inhale as you return"
        ),
        "hollow-hold": Technique(
            setup: [
                "Lie on your back on a mat, arms overhead, legs straight",
                "Press the lower back into the mat",
                "Lift shoulders and legs off the floor together",
            ],
            position: [
                Checkpoint(.head, "Chin slightly tucked, head off the mat"),
                Checkpoint(.shoulders, "Lifted, arms by the ears"),
                Checkpoint(.core, "Lower back pressed down the whole time"),
                Checkpoint(.feet, "Legs together, toes pointed, low but not touching"),
            ],
            mistakes: [
                "Lower back arching off the mat",
                "Legs too low for your strength level",
                "Holding the breath",
            ],
            breathing: "Short controlled breaths while keeping the back flat"
        ),
        "farmer-carry": Technique(
            setup: [
                "Place two heavy dumbbells beside your feet",
                "Hinge at the hips with a flat back and grip each handle in the center",
                "Stand up tall before walking",
            ],
            position: [
                Checkpoint(.head, "Tall, eyes forward"),
                Checkpoint(.shoulders, "Pulled back and down, not shrugged"),
                Checkpoint(.hands, "Crush the handles; full grip, thumbs wrapped"),
                Checkpoint(.core, "Braced, ribs down"),
                Checkpoint(.feet, "Short fast steps in a straight line"),
            ],
            mistakes: [
                "Rounding the back when lifting or setting down the weights",
                "Shoulders rolling forward",
                "Long, slow strides that make the weights sway",
            ],
            breathing: "Steady breaths behind a light brace while walking"
        ),
        "suitcase-carry": Technique(
            setup: [
                "Place one kettlebell beside one foot",
                "Hinge down with a flat back and grip the handle",
                "Stand tall with the bell at your side",
            ],
            position: [
                Checkpoint(.head, "Tall, eyes forward"),
                Checkpoint(.shoulders, "Level, neither raised nor dropped"),
                Checkpoint(.hands, "Firm grip, arm long by the side"),
                Checkpoint(.core, "Obliques braced so you don't lean"),
                Checkpoint(.feet, "Walk in a straight line, then switch sides"),
            ],
            mistakes: [
                "Leaning away from or toward the weight",
                "Hiking the hip on the loaded side",
                "Rounding the back when picking up the bell",
            ],
            breathing: "Steady breaths behind a light brace while walking"
        ),
        "overhead-carry": Technique(
            setup: [
                "Clean a light kettlebell to the rack position",
                "Press it overhead to lockout, bell resting on the forearm",
            ],
            position: [
                Checkpoint(.head, "Neutral; biceps near the ear"),
                Checkpoint(.shoulders, "Packed, stable, not shrugged high"),
                Checkpoint(.elbows, "Locked straight, wrist stacked over shoulder"),
                Checkpoint(.core, "Ribs down, no arching backward"),
                Checkpoint(.feet, "Short controlled steps"),
            ],
            mistakes: [
                "Arching the lower back to get the bell overhead",
                "Arm drifting forward of the head",
                "Using a weight you can't lock out steadily",
            ],
            breathing: "Steady breaths with ribs held down"
        ),
        "db-curl": Technique(
            setup: [
                "Stand tall with a dumbbell in each hand, arms straight",
                "Palms facing forward or rotating forward as you curl",
            ],
            position: [
                Checkpoint(.shoulders, "Stay still, not rolling forward"),
                Checkpoint(.elbows, "Pinned to the sides of the torso"),
                Checkpoint(.hands, "Supinate (turn pinky up) at the top"),
                Checkpoint(.core, "Braced; no leaning back"),
            ],
            mistakes: [
                "Swinging the torso to lift the weight",
                "Elbows drifting forward",
                "Dropping the weight fast on the way down",
            ],
            breathing: "Exhale as you curl up, inhale as you lower"
        ),
        "hammer-curl": Technique(
            setup: [
                "Stand tall with a dumbbell in each hand, arms straight",
                "Hold with a neutral grip, palms facing your thighs",
            ],
            position: [
                Checkpoint(.shoulders, "Relaxed, not shrugging"),
                Checkpoint(.elbows, "Pinned to the sides"),
                Checkpoint(.hands, "Neutral grip throughout, thumbs up"),
                Checkpoint(.core, "Braced; torso still"),
            ],
            mistakes: [
                "Swinging the weights up",
                "Elbows drifting forward",
                "Wrists bending instead of staying straight",
            ],
            breathing: "Exhale as you curl up, inhale as you lower"
        ),
        "cable-curl": Technique(
            setup: [
                "Set the cable pulley to the lowest position with a straight bar or EZ bar",
                "Grip shoulder width, palms up",
                "Step back slightly so there is tension at the bottom",
            ],
            position: [
                Checkpoint(.shoulders, "Still, not rolling forward"),
                Checkpoint(.elbows, "Pinned to the sides"),
                Checkpoint(.hands, "Wrists straight"),
                Checkpoint(.core, "Braced; no leaning back"),
            ],
            mistakes: [
                "Leaning back to lift the weight",
                "Losing tension at the bottom",
                "Elbows drifting forward",
            ],
            breathing: "Exhale as you curl up, inhale as you lower"
        ),
        "triceps-pushdown": Technique(
            setup: [
                "Set the cable pulley to the top with a rope or straight bar",
                "Grip the attachment and step close to the stack",
                "Bring the elbows to the sides with forearms about parallel to the floor",
            ],
            position: [
                Checkpoint(.shoulders, "Down and back, not rolled forward"),
                Checkpoint(.elbows, "Fixed at the sides; only the forearms move"),
                Checkpoint(.hands, "Press down to full lockout; spread the rope at the bottom"),
                Checkpoint(.core, "Braced, slight forward lean at most"),
            ],
            mistakes: [
                "Elbows flaring or drifting forward",
                "Leaning over the bar to push with body weight",
                "Stopping short of full lockout",
            ],
            breathing: "Exhale as you push down, inhale as the hands return"
        ),
        "overhead-triceps": Technique(
            setup: [
                "Set the cable pulley low or mid with a rope attachment",
                "Face away from the stack and bring the rope overhead",
                "Staggered stance, slight forward lean",
            ],
            position: [
                Checkpoint(.head, "Neutral, between the arms"),
                Checkpoint(.elbows, "Point forward, close to the head"),
                Checkpoint(.hands, "Extend fully, then lower into a deep stretch"),
                Checkpoint(.core, "Ribs down, no arching"),
                Checkpoint(.feet, "Staggered stance for balance"),
            ],
            mistakes: [
                "Elbows flaring out wide",
                "Lower back arching to finish reps",
                "Cutting the stretch short at the bottom",
            ],
            breathing: "Exhale as you extend, inhale as you lower"
        ),
        "db-lateral-raise": Technique(
            setup: [
                "Stand tall with light dumbbells at your sides",
                "Slight bend in the elbows, palms facing in",
            ],
            position: [
                Checkpoint(.shoulders, "Down, not shrugging"),
                Checkpoint(.elbows, "Lead the raise, slightly bent"),
                Checkpoint(.hands, "Stop at shoulder height"),
                Checkpoint(.core, "Braced; no swinging"),
            ],
            mistakes: [
                "Swinging the weights up",
                "Raising above shoulder height",
                "Shrugging the traps",
            ],
            breathing: "Exhale as you raise, inhale as you lower"
        ),
        "cable-lateral-raise": Technique(
            setup: [
                "Set the cable pulley to the lowest position with a D-handle",
                "Stand side-on to the stack, grip with the far hand",
                "Run the cable behind your body",
            ],
            position: [
                Checkpoint(.shoulders, "Down and stable"),
                Checkpoint(.elbows, "Lead the raise, slightly bent"),
                Checkpoint(.hands, "Stop at shoulder height"),
                Checkpoint(.core, "Braced, torso upright"),
            ],
            mistakes: [
                "Leaning away to lift heavier",
                "Shrugging the shoulder up",
                "Letting the weight drop fast",
            ],
            breathing: "Exhale as you raise, inhale on the slow lower"
        ),
        "face-pull": Technique(
            setup: [
                "Set the cable pulley at forehead height or slightly above with a rope",
                "Grip the rope with thumbs pointing back toward you",
                "Step back until the arms are straight and there is tension",
            ],
            position: [
                Checkpoint(.head, "Neutral; pull the rope toward the forehead"),
                Checkpoint(.shoulders, "Pull shoulder blades back, not up"),
                Checkpoint(.elbows, "High, at or above shoulder height"),
                Checkpoint(.hands, "Rotate outward at the end so knuckles point back"),
                Checkpoint(.feet, "Staggered or hip width, stable"),
            ],
            mistakes: [
                "Pulling to the chest instead of the face",
                "Leaning back to move the weight",
                "Skipping the external rotation at the end",
            ],
            breathing: "Exhale as you pull, inhale as you return"
        ),
        "cable-external-rotation": Technique(
            setup: [
                "Set the cable pulley to elbow height with a D-handle",
                "Stand side-on to the stack and grip with the far hand",
                "Tuck a rolled towel between the elbow and your side",
            ],
            position: [
                Checkpoint(.shoulders, "Down and back, not shrugged"),
                Checkpoint(.elbows, "Bent 90°, pinned against the towel"),
                Checkpoint(.hands, "Rotate the forearm outward slowly"),
                Checkpoint(.core, "Torso still, no twisting"),
            ],
            mistakes: [
                "Using too much weight",
                "Elbow drifting away from the body",
                "Rotating the torso instead of the shoulder",
            ],
            breathing: "Exhale as you rotate out, inhale as you return"
        ),
        "band-pull-apart": Technique(
            setup: [
                "Hold a light band with both hands at shoulder width",
                "Arms straight in front at shoulder height",
            ],
            position: [
                Checkpoint(.shoulders, "Pull shoulder blades together, not up"),
                Checkpoint(.elbows, "Straight or very slightly bent"),
                Checkpoint(.hands, "Pull the band apart until it touches the chest"),
                Checkpoint(.core, "Ribs down, no arching"),
            ],
            mistakes: [
                "Bending the elbows to make it easier",
                "Arching the lower back",
                "Letting the band snap back fast",
            ],
            breathing: "Exhale as you pull apart, inhale as you return"
        ),
        "prone-ytw": Technique(
            setup: [
                "Set an adjustable bench to about 30–45°",
                "Lie chest down on the bench with very light dumbbells",
                "Let the arms hang straight down",
            ],
            position: [
                Checkpoint(.head, "Neutral, chin tucked"),
                Checkpoint(.shoulders, "Pull blades back and down before lifting"),
                Checkpoint(.hands, "Thumbs up through Y, T and W"),
                Checkpoint(.core, "Chest stays on the bench"),
            ],
            mistakes: [
                "Using weights that are too heavy",
                "Shrugging the shoulders",
                "Lifting the chest off the bench",
            ],
            breathing: "Exhale as you lift, inhale as you lower"
        ),
        "reverse-pec-deck": Technique(
            setup: [
                "Set the seat so the handles are at shoulder height",
                "Set the handles to the rear position",
                "Sit facing the pad, chest against it",
            ],
            position: [
                Checkpoint(.shoulders, "Down, not shrugging"),
                Checkpoint(.elbows, "Slightly bent, fixed angle"),
                Checkpoint(.hands, "Lead with the pinkies as you open the arms"),
                Checkpoint(.back, "Chest stays on the pad"),
            ],
            mistakes: [
                "Shrugging the shoulders up",
                "Swinging the body to move the weight",
                "Bending the elbows more as you pull",
            ],
            breathing: "Exhale as you open the arms, inhale as you return"
        ),
        "scap-pull-up": Technique(
            setup: [
                "Grip the pull-up bar shoulder width, palms facing away",
                "Hang with straight arms, feet off the floor",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.shoulders, "Pull blades down and back, lifting the body slightly"),
                Checkpoint(.elbows, "Stay straight the whole time"),
                Checkpoint(.core, "Braced to stop swinging"),
            ],
            mistakes: [
                "Bending the arms to pull up",
                "Shrugging up instead of depressing",
                "Swinging the body",
            ],
            breathing: "Exhale as you pull the shoulders down, inhale as you release"
        ),
        "push-up-plus": Technique(
            setup: [
                "Start in a high plank, hands under shoulders",
                "Feet hip width apart",
            ],
            position: [
                Checkpoint(.head, "Neutral neck"),
                Checkpoint(.shoulders, "At the top, push the floor away to spread the blades"),
                Checkpoint(.elbows, "About 45° from the torso on the way down"),
                Checkpoint(.core, "Braced, body in one straight line"),
                Checkpoint(.hips, "Level with the shoulders, glutes squeezed"),
            ],
            mistakes: [
                "Skipping the extra protraction at the top",
                "Hips sagging",
                "Elbows flaring wide",
            ],
            breathing: "Inhale as you lower, exhale as you push and protract"
        ),
        "standing-calf-raise": Technique(
            setup: [
                "Set the Smith bar at shoulder height and place a step under it",
                "Position the bar on the upper back and unhook it",
                "Stand on the step edge with the balls of your feet",
            ],
            position: [
                Checkpoint(.shoulders, "Down and back under the bar"),
                Checkpoint(.core, "Braced, torso upright"),
                Checkpoint(.knees, "Straight but not locked"),
                Checkpoint(.feet, "Full stretch at the bottom, pause 1 s at the top"),
            ],
            mistakes: [
                "Bouncing at the bottom",
                "Bending the knees to push",
                "Cutting the range short",
            ],
            breathing: "Exhale as you rise, inhale as you lower"
        ),
        "db-calf-raise": Technique(
            setup: [
                "Hold a dumbbell in one hand and stand on a step edge",
                "Use the other hand on a rail or wall for balance",
                "Place the ball of the working foot on the step edge",
            ],
            position: [
                Checkpoint(.hands, "Light touch on the support for balance only"),
                Checkpoint(.core, "Braced, torso upright"),
                Checkpoint(.knees, "Straight but not locked"),
                Checkpoint(.feet, "Lower slowly into a full stretch, then rise fully"),
            ],
            mistakes: [
                "Bouncing at the bottom",
                "Pulling yourself up with the support hand",
                "Rushing the lowering phase",
            ],
            breathing: "Exhale as you rise, inhale on the slow lower"
        ),
        "reverse-wrist-curl": Technique(
            setup: [
                "Sit on a bench with forearms resting on your thighs",
                "Hold light dumbbells with palms facing down",
                "Let the wrists hang just past the knees",
            ],
            position: [
                Checkpoint(.elbows, "Forearms stay fixed on the thighs"),
                Checkpoint(.hands, "Lift the back of the hand up, then lower slowly"),
                Checkpoint(.back, "Sit tall, not hunched"),
                Checkpoint(.feet, "Flat on the floor"),
            ],
            mistakes: [
                "Using weight that is too heavy",
                "Lifting the forearms off the thighs",
                "Rushing the reps",
            ],
            breathing: "Exhale as you lift, inhale as you lower"
        ),
        "finger-extensions": Technique(
            setup: [
                "Loop a light rubber band around all fingertips and thumb",
                "Start with fingers bunched together",
            ],
            position: [
                Checkpoint(.shoulders, "Relaxed and down, not tensing up"),
                Checkpoint(.elbows, "Bent and relaxed at the sides"),
                Checkpoint(.hands, "Open all fingers fully against the band"),
                Checkpoint(.hands, "Close slowly back to the start"),
            ],
            mistakes: [
                "Using a band that is too strong",
                "Only partly opening the hand",
                "Letting the band snap closed",
            ],
            breathing: "Breathe naturally throughout"
        ),
        "pronation-supination": Technique(
            setup: [
                "Sit on a bench, forearm resting on your thigh",
                "Hold a light dumbbell by one end, like a hammer",
            ],
            position: [
                Checkpoint(.elbows, "Bent about 90°, forearm resting on the thigh"),
                Checkpoint(.hands, "Rotate the dumbbell slowly from palm up to palm down"),
                Checkpoint(.back, "Sit tall, not leaning"),
            ],
            mistakes: [
                "Moving too fast",
                "Using a weight that is too heavy",
                "Lifting the forearm off the thigh",
            ],
            breathing: "Breathe naturally throughout"
        ),
    ]
}
