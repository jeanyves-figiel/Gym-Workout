// Technique content for the catalog extension (#174): lower body.

extension Technique {
    static let variationsLower: [String: Technique] = [
        // MARK: Squats
        "box-squat": Technique(
            setup: ["Set a box behind you so the thighs are about parallel when seated", "Bar on the upper back, walk out and stand a foot's length in front of the box"],
            position: [
                Checkpoint(.hips, "Sit back to the box, shins close to vertical"),
                Checkpoint(.core, "Stay braced on the box; pause without relaxing"),
                Checkpoint(.feet, "Drive up through the heels and mid-foot"),
                Checkpoint(.knees, "Push out over the toes"),
            ],
            mistakes: ["Dropping onto the box", "Rocking back and using momentum to stand", "Relaxing the trunk during the pause"],
            breathing: "Inhale and brace before you sit, exhale as you drive up"
        ),
        "zercher-squat": Technique(
            setup: ["Set the bar in the rack at belly height", "Hook the bar into the crease of the elbows, hands clasped in front of the chest"],
            position: [
                Checkpoint(.elbows, "Up and in front, holding the bar tight to the body"),
                Checkpoint(.back, "Chest tall, upper back braced against the load"),
                Checkpoint(.hips, "Sit straight down between the heels"),
                Checkpoint(.knees, "Track over the toes"),
            ],
            mistakes: ["Letting the elbows drop and the chest collapse", "Bar sliding down the forearms", "Rounding the upper back"],
            breathing: "Big breath and brace at the top, exhale past the hardest part on the way up"
        ),
        "kb-front-squat": Technique(
            setup: ["Clean two kettlebells into the rack: handles in the palms, bells resting on the outside of the forearms", "Feet shoulder-width, toes slightly out"],
            position: [
                Checkpoint(.hands, "Wrists straight, fists near the chin"),
                Checkpoint(.elbows, "Tucked in front of the ribs, inside the knees at the bottom"),
                Checkpoint(.back, "Upright torso, chest proud"),
                Checkpoint(.hips, "Sink to full depth"),
            ],
            mistakes: ["Bent wrists letting the bells drag", "Elbows flaring out", "Leaning forward under the bells"],
            breathing: "Inhale and brace before you descend, exhale as you stand"
        ),
        "heel-elevated-goblet-squat": Technique(
            setup: ["Heels on a slant board, small plates or a wedge, toes on the floor", "Hold a dumbbell vertically at the chest"],
            position: [
                Checkpoint(.knees, "Travel well forward over the toes"),
                Checkpoint(.back, "Torso stays upright"),
                Checkpoint(.feet, "Heels stay pressed into the wedge"),
                Checkpoint(.elbows, "Point down between the knees"),
            ],
            mistakes: ["Heels sliding off the plate", "Cutting depth short", "Leaning forward and turning it into a hip squat"],
            breathing: "Inhale on the way down, exhale on the way up"
        ),
        "sumo-db-squat": Technique(
            setup: ["Wide stance, toes turned out about 30-45 degrees", "Hold one dumbbell by the top head, hanging between the legs"],
            position: [
                Checkpoint(.knees, "Push out in line with the toes"),
                Checkpoint(.back, "Chest up, back flat"),
                Checkpoint(.hands, "Let the dumbbell hang straight down; arms stay long"),
                Checkpoint(.hips, "Sit straight down between the feet"),
            ],
            mistakes: ["Knees caving in", "Leaning forward to reach the floor", "Stance so wide the knees can't track the toes"],
            breathing: "Inhale on the way down, exhale as you stand"
        ),
        "landmine-squat": Technique(
            setup: ["Load the free end of a barbell set in a landmine", "Hold the bar end at the chest with both hands, feet shoulder-width"],
            position: [
                Checkpoint(.hands, "Bar end stays at the chest throughout"),
                Checkpoint(.back, "Lean slightly into the bar, chest tall"),
                Checkpoint(.hips, "Sit straight down between the heels"),
                Checkpoint(.feet, "Flat, weight through mid-foot"),
            ],
            mistakes: ["Letting the bar drift away from the chest", "Standing too close so the bar is vertical", "Heels lifting"],
            breathing: "Inhale on the way down, exhale as you stand"
        ),
        "single-leg-press": Technique(
            setup: ["Sit back in the leg press, one foot in the middle of the platform", "Rest the other foot on the frame or the floor"],
            position: [
                Checkpoint(.feet, "Working foot mid-platform, the whole foot pressing"),
                Checkpoint(.hips, "Stay down on the seat; stop before the pelvis tucks"),
                Checkpoint(.knees, "Track over the toes, no caving in"),
            ],
            mistakes: ["Lower back lifting off the pad at the bottom", "Locking the knee hard at the top", "Going deeper on one side than the other"],
            breathing: "Inhale as the sled comes down, exhale as you press"
        ),
        // MARK: Single-leg
        "smith-split-squat": Technique(
            setup: ["Set the bar on the upper back and unhook it", "Take a long split stance, front foot ahead of the bar"],
            position: [
                Checkpoint(.feet, "Long stance; front heel drives, back foot on the toes"),
                Checkpoint(.knees, "Back knee drops straight down towards the floor"),
                Checkpoint(.back, "Torso tall, close to vertical"),
                Checkpoint(.hips, "Square to the front"),
            ],
            mistakes: ["Stance too short so the front heel lifts", "Pushing off the back leg", "Front knee caving in"],
            breathing: "Inhale on the way down, exhale as you drive up"
        ),
        "forward-lunge": Technique(
            setup: ["Stand tall, a dumbbell in each hand at your sides", "Feet hip-width"],
            position: [
                Checkpoint(.feet, "Step long and land heel first"),
                Checkpoint(.knees, "Back knee drops towards the floor; front knee tracks the toes"),
                Checkpoint(.back, "Torso tall throughout"),
                Checkpoint(.hips, "Push back to standing through the front heel"),
            ],
            mistakes: ["Short step so the front heel lifts", "Slamming the front foot down", "Leaning forward over the front knee"],
            breathing: "Inhale as you step and lower, exhale as you push back"
        ),
        "curtsy-lunge": Technique(
            setup: ["Stand tall, dumbbells at your sides", "Feet hip-width"],
            position: [
                Checkpoint(.feet, "Step back and across, landing behind the front heel"),
                Checkpoint(.hips, "Stay square to the front, don't rotate"),
                Checkpoint(.knees, "Front knee over the toes; back knee drops towards the floor"),
                Checkpoint(.back, "Chest up, torso tall"),
            ],
            mistakes: ["Twisting the hips open", "Front knee caving in", "Stepping so far across you lose balance"],
            breathing: "Inhale as you lower, exhale as you return"
        ),
        "barbell-reverse-lunge": Technique(
            setup: ["Bar on the upper back, walk it out of the rack", "Feet hip-width, brace"],
            position: [
                Checkpoint(.feet, "Long step back, land on the ball of the foot"),
                Checkpoint(.knees, "Back knee drops just short of the floor"),
                Checkpoint(.back, "Torso tall under the bar"),
                Checkpoint(.hips, "Drive up through the front heel"),
            ],
            mistakes: ["Short step so the front knee shoots forward", "Leaning forward under the bar", "Losing balance from a narrow, tightrope stance"],
            breathing: "Inhale as you step back, exhale as you return"
        ),
        "lateral-lunge": Technique(
            setup: ["Stand tall, dumbbells at your sides", "Feet together, toes forward"],
            position: [
                Checkpoint(.feet, "Big step to the side, both feet flat"),
                Checkpoint(.hips, "Sit back into the hip of the stepping leg"),
                Checkpoint(.knees, "Bent knee tracks the toes; the other leg stays straight"),
                Checkpoint(.back, "Flat back, chest up"),
            ],
            mistakes: ["Knee caving in", "Heel of the working foot lifting", "Rounding the back to reach down"],
            breathing: "Inhale as you step and sit, exhale as you push off"
        ),
        "ffe-split-squat": Technique(
            setup: ["Front foot on a low step or plate, 5-10 cm high", "Long split stance, dumbbells at your sides"],
            position: [
                Checkpoint(.knees, "Back knee drops below the level of the front foot"),
                Checkpoint(.feet, "Front foot flat on the step; back foot on the toes"),
                Checkpoint(.back, "Torso tall"),
                Checkpoint(.hips, "Square to the front"),
            ],
            mistakes: ["Step so high it limits depth", "Rushing the lowering phase", "Pushing off the back leg"],
            breathing: "Inhale slowly on the way down, exhale as you drive up"
        ),
        "lateral-step-down": Technique(
            setup: ["Stand side-on on a low box, one foot on it", "Let the other leg hang off the side, hands on the hips or reaching forward"],
            position: [
                Checkpoint(.knees, "Standing knee tracks over the toes"),
                Checkpoint(.hips, "Level, sit them back slightly"),
                Checkpoint(.feet, "Tap the free heel down slowly, no weight on it"),
            ],
            mistakes: ["Knee collapsing inwards", "Dropping the hip on the free side", "Landing weight on the free foot"],
            breathing: "Inhale as you lower, exhale as you stand back up"
        ),
        "box-pistol": Technique(
            setup: ["Stand on one leg in front of a box", "Free leg lifted slightly forward, arms out in front"],
            position: [
                Checkpoint(.hips, "Sit back to the box on one leg, under control"),
                Checkpoint(.knees, "Working knee tracks the toes"),
                Checkpoint(.feet, "Whole foot planted, heel down"),
                Checkpoint(.hands, "Reach forward to counterbalance"),
            ],
            mistakes: ["Falling onto the box", "Rocking back to swing up", "Knee caving in"],
            breathing: "Inhale as you sit, exhale as you stand"
        ),
        "skater-squat": Technique(
            setup: ["Stand on one leg, bend the other knee so the foot is behind you", "Arms reach forward; a pad under the back knee helps"],
            position: [
                Checkpoint(.knees, "Back knee lowers to touch lightly behind the front heel"),
                Checkpoint(.feet, "Front heel stays down"),
                Checkpoint(.hips, "Hinge slightly, hips back"),
                Checkpoint(.hands, "Reach forward to balance"),
            ],
            mistakes: ["Slamming the knee into the floor", "Front heel lifting", "Front knee caving in"],
            breathing: "Inhale on the way down, exhale on the way up"
        ),
        // MARK: Hinges
        "sumo-deadlift": Technique(
            setup: ["Wide stance, toes turned out, shins close to the bar", "Grip the bar shoulder-width, hands inside the knees"],
            position: [
                Checkpoint(.feet, "Push the floor apart as you lift"),
                Checkpoint(.knees, "Out over the toes, shins near vertical"),
                Checkpoint(.hips, "Rise together with the chest"),
                Checkpoint(.back, "Flat, lats tight, bar close to the body"),
            ],
            mistakes: ["Hips shooting up first", "Knees caving in", "Stance so wide the hips can't get close to the bar"],
            breathing: "Inhale and brace before the pull, exhale at lockout"
        ),
        "rack-pull": Technique(
            setup: ["Set the safety pins so the bar sits just below the knee", "Stand close, grip just outside the legs"],
            position: [
                Checkpoint(.back, "Flat, lats tight before the bar leaves the pins"),
                Checkpoint(.shoulders, "Slightly in front of the bar at the start"),
                Checkpoint(.hips, "Drive forward to lock out with the glutes"),
                Checkpoint(.hands, "Grip hard, arms straight"),
            ],
            mistakes: ["Jerking the bar off the pins", "Leaning back at lockout", "Bouncing the bar on the pins between reps"],
            breathing: "Brace before each pull, exhale at the top"
        ),
        "deficit-deadlift": Technique(
            setup: ["Stand on a 3-5 cm plate or platform, bar over the mid-foot", "Hinge down with the hips lower than in a normal deadlift"],
            position: [
                Checkpoint(.hips, "Low at the start; push the floor away"),
                Checkpoint(.back, "Flat from neck to pelvis"),
                Checkpoint(.hands, "Arms straight, bar stays on the legs"),
                Checkpoint(.knees, "Clear the bar path as it rises"),
            ],
            mistakes: ["Rounding the lower back to reach the bar", "Deficit too high to keep a flat back", "Bar drifting forward"],
            breathing: "Inhale and brace before each rep, exhale at lockout"
        ),
        "kb-deadlift": Technique(
            setup: ["Kettlebell between the feet, in line with the ankles", "Feet hip-width or slightly wider"],
            position: [
                Checkpoint(.hips, "Push back to reach the bell, shins nearly vertical"),
                Checkpoint(.back, "Flat, chest proud"),
                Checkpoint(.hands, "Both hands on the handle, arms straight"),
                Checkpoint(.feet, "Drive through the whole foot to stand tall"),
            ],
            mistakes: ["Squatting the bell instead of hinging", "Rounding the back to reach the floor", "Leaning back at the top"],
            breathing: "Inhale as you hinge, exhale as you stand"
        ),
        "b-stance-rdl": Technique(
            setup: ["Dumbbells in both hands, one foot forward", "Back foot on its toes beside the front heel, as a kickstand"],
            position: [
                Checkpoint(.feet, "Most of the weight on the front heel"),
                Checkpoint(.hips, "Push back; the shins stay still"),
                Checkpoint(.back, "Flat, dumbbells close to the front leg"),
                Checkpoint(.knees, "Soft front knee, fixed angle"),
            ],
            mistakes: ["Shifting weight onto the back foot", "Bending the front knee into a squat", "Rounding to reach lower"],
            breathing: "Inhale as you hinge, exhale as you stand"
        ),
        // MARK: Glutes
        "db-hip-thrust": Technique(
            setup: ["Shoulder blades on the edge of a bench, feet flat about hip-width", "Hold a dumbbell across the hip crease"],
            position: [
                Checkpoint(.head, "Chin tucked, eyes forward"),
                Checkpoint(.core, "Ribs down, no lower-back arch at the top"),
                Checkpoint(.knees, "About 90 degrees at the top, shins vertical"),
                Checkpoint(.hips, "Squeeze the glutes 1 s at the top"),
            ],
            mistakes: ["Arching the lower back to finish", "Feet too far out so the hamstrings take over", "Dumbbell rolling off the hips"],
            breathing: "Exhale as you drive up, inhale as you lower"
        ),
        "barbell-glute-bridge": Technique(
            setup: ["Lie on your back on a mat, knees bent, feet flat", "Roll a padded barbell over the hip crease"],
            position: [
                Checkpoint(.back, "Upper back stays flat on the floor"),
                Checkpoint(.feet, "Drive through the heels"),
                Checkpoint(.hips, "Lift to a straight line from shoulders to knees, squeeze 1 s"),
                Checkpoint(.hands, "Hold the bar steady over the hips"),
            ],
            mistakes: ["Arching the lower back at the top", "Pushing through the toes", "Bar without a pad digging into the hips"],
            breathing: "Exhale as you lift, inhale as you lower"
        ),
        "single-leg-back-extension": Technique(
            setup: ["Set the hip pad just below the hip crease", "Hook one foot under the ankle roller, the other leg free"],
            position: [
                Checkpoint(.hips, "Hinge at the hip, not the lower back"),
                Checkpoint(.back, "Flat from head to pelvis"),
                Checkpoint(.head, "In line with the spine, no craning up"),
                Checkpoint(.feet, "Working foot presses into the platform"),
            ],
            mistakes: ["Hyperextending past a straight line", "Rounding the back at the bottom", "Pushing with the free leg"],
            breathing: "Inhale as you lower, exhale as you rise"
        ),
        "cable-glute-kickback": Technique(
            setup: ["Ankle cuff on the working leg, low pulley", "Hold the column and hinge slightly forward"],
            position: [
                Checkpoint(.hips, "Kick back and slightly out from the glute"),
                Checkpoint(.back, "Neutral, no lower-back arch as the leg goes back"),
                Checkpoint(.knees, "Soft, fixed angle on the working leg"),
                Checkpoint(.core, "Braced, torso still"),
            ],
            mistakes: ["Arching the back to swing the leg higher", "Rotating the hips open", "Using momentum"],
            breathing: "Exhale as you kick back, inhale as you return"
        ),
        "cable-hip-abduction": Technique(
            setup: ["Stand side-on to a low pulley, ankle cuff on the outside leg", "Hold the column with the near hand"],
            position: [
                Checkpoint(.hips, "Lift the leg out to the side from the hip"),
                Checkpoint(.core, "Torso still and upright, no leaning away"),
                Checkpoint(.feet, "Toes point forward"),
                Checkpoint(.knees, "Working leg straight"),
            ],
            mistakes: ["Leaning the torso to swing the leg", "Turning the toes up", "Letting the cable snap back"],
            breathing: "Exhale as you lift the leg out, inhale on the slow return"
        ),
        "side-lying-hip-abduction": Technique(
            setup: ["Lie on your side on a mat, legs stacked, head on the lower arm", "Bottom knee can bend for balance"],
            position: [
                Checkpoint(.feet, "Toes forward, heel leads the lift"),
                Checkpoint(.hips, "Stacked; top leg slightly behind the body line"),
                Checkpoint(.knees, "Top leg straight"),
                Checkpoint(.core, "Braced so the pelvis doesn't roll back"),
            ],
            mistakes: ["Rolling back onto the glutes", "Swinging the leg forward", "Lifting too high and hiking the hip"],
            breathing: "Exhale as you lift, hold 1 s, inhale as you lower"
        ),
        "band-clamshell": Technique(
            setup: ["Lie on your side, band just above the knees", "Hips and knees bent, feet together in line with the hips"],
            position: [
                Checkpoint(.hips, "Stacked; keep them from rolling back"),
                Checkpoint(.feet, "Stay together as the knee opens"),
                Checkpoint(.knees, "Top knee lifts against the band, pause at the top"),
                Checkpoint(.head, "Rests on the lower arm"),
            ],
            mistakes: ["Rolling the pelvis back to open further", "Feet separating", "Rushing the reps"],
            breathing: "Exhale as the knee opens, inhale as it closes"
        ),
        "cable-hip-adduction": Technique(
            setup: ["Stand side-on to a low pulley, ankle cuff on the inside leg", "Hold the column for balance"],
            position: [
                Checkpoint(.hips, "Sweep the leg across in front of the standing leg"),
                Checkpoint(.core, "Torso upright and still"),
                Checkpoint(.knees, "Working leg straight"),
                Checkpoint(.feet, "Toes forward"),
            ],
            mistakes: ["Leaning the torso to help", "Swinging with momentum", "Letting the weight pull the leg back fast"],
            breathing: "Exhale as you sweep across, inhale on the slow return"
        ),
        "side-lying-adduction": Technique(
            setup: ["Lie on your side, head on the lower arm", "Bend the top leg and plant its foot in front of the bottom knee"],
            position: [
                Checkpoint(.knees, "Bottom leg straight"),
                Checkpoint(.feet, "Lift the bottom leg with the toes forward"),
                Checkpoint(.hips, "Stacked, no rolling"),
                Checkpoint(.core, "Braced, upper body relaxed"),
            ],
            mistakes: ["Rolling forward or back", "Swinging the leg up", "Turning the toes to the ceiling"],
            breathing: "Exhale as you lift, hold 1 s, inhale as you lower"
        ),
        // MARK: Knee flexion / extension
        "single-leg-curl": Technique(
            setup: ["Lie on the leg curl, knees just off the pad edge", "Roller above the heel of the working leg; the other leg rests"],
            position: [
                Checkpoint(.hips, "Pinned to the pad"),
                Checkpoint(.knees, "Curl as far as the hamstring allows"),
                Checkpoint(.feet, "Flexed, toes towards the shin"),
            ],
            mistakes: ["Hips lifting off the pad", "Dropping the weight", "Twisting to help the working side"],
            breathing: "Exhale as you curl, inhale on a 3 s lower"
        ),
        "ball-hamstring-curl": Technique(
            setup: ["Lie on your back, heels on a stability ball, arms out on the floor", "Lift the hips into a straight line"],
            position: [
                Checkpoint(.hips, "Stay high as you curl and as you extend"),
                Checkpoint(.feet, "Heels pull the ball towards the glutes"),
                Checkpoint(.shoulders, "Planted on the floor"),
                Checkpoint(.core, "Ribs down, no arching"),
            ],
            mistakes: ["Hips sagging on the way out", "Arching the lower back", "Rushing so the ball wobbles"],
            breathing: "Exhale as you curl in, inhale as you roll out"
        ),
        "single-leg-extension": Technique(
            setup: ["Knee lined up with the machine pivot", "Roller on the lower shin of the working leg"],
            position: [
                Checkpoint(.knees, "Extend fully, squeeze 1 s at the top"),
                Checkpoint(.hips, "Stay on the seat"),
                Checkpoint(.hands, "Hold the handles to stay in place"),
            ],
            mistakes: ["Kicking the weight up", "Hips lifting off the seat", "Dropping the weight on the way down"],
            breathing: "Exhale as you extend, inhale on a 3 s lower"
        ),
        "sissy-squat": Technique(
            setup: ["Stand next to a rack upright and hold it with one hand", "Feet hip-width"],
            position: [
                Checkpoint(.knees, "Travel forward and down towards the floor"),
                Checkpoint(.hips, "Stay open; straight line from knees to shoulders"),
                Checkpoint(.feet, "Heels lift as you lower, weight on the balls of the feet"),
                Checkpoint(.core, "Braced to hold the line"),
            ],
            mistakes: ["Bending at the hips into a normal squat", "Going deeper than the knees tolerate", "Letting go and losing balance"],
            breathing: "Inhale as you lean back and lower, exhale as you rise"
        ),
        "spanish-squat": Technique(
            setup: ["Loop a heavy band behind both knees, anchored low to a rack in front", "Step back until the band is taut, feet hip-width"],
            position: [
                Checkpoint(.knees, "Band pulls them forward; shins stay vertical"),
                Checkpoint(.hips, "Sit back and down against the band"),
                Checkpoint(.back, "Torso fairly upright"),
                Checkpoint(.feet, "Flat, heels down"),
            ],
            mistakes: ["Standing too close so the band goes slack", "Knees drifting forward past the toes", "Leaning forward to sit back"],
            breathing: "Inhale on the way down, exhale on the way up"
        ),
        // MARK: Calves
        "seated-db-calf-raise": Technique(
            setup: ["Sit on a bench, balls of the feet on a plate or step", "Rest dumbbells on the knees and hold them in place"],
            position: [
                Checkpoint(.feet, "Full stretch at the bottom, rise high onto the big toe"),
                Checkpoint(.knees, "Bent about 90 degrees under the dumbbells"),
                Checkpoint(.hands, "Steady the weights, don't push with the arms"),
            ],
            mistakes: ["Bouncing out of the bottom", "Half reps", "Feet rolling out"],
            breathing: "Exhale as you rise, hold 1 s, inhale as you lower"
        ),
    ]
}
