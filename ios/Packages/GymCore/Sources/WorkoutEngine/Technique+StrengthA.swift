// Technique content: setup, body position, mistakes, breathing.

extension Technique {
    static let strengthA: [String: Technique] = [
        "back-squat": Technique(
            setup: [
                "Set the J-hooks at mid-chest height and safety pins just below your bottom position",
                "Bar on upper traps, hands just outside shoulders, walk out 2–3 steps",
                "Set your stance before the first rep, then brace",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes on a spot 2 m ahead on the floor"),
                Checkpoint(.back, "Neutral spine; chest proud, upper back tight"),
                Checkpoint(.hips, "Sit down and slightly back to at least parallel"),
                Checkpoint(.knees, "Track over 2nd–3rd toe, never caving in"),
                Checkpoint(.feet, "Shoulder-width, toes out 15–30°, whole foot grounded"),
            ],
            mistakes: [
                "Knees collapsing inward on the way up",
                "Heels lifting or weight drifting to the toes",
                "Hips shooting up first so the squat turns into a good morning",
            ],
            breathing: "Big breath and brace at the top, hold through the descent, exhale past the hardest point"
        ),
        "front-squat": Technique(
            setup: [
                "Set the J-hooks at upper-chest height and safety pins just below your bottom position",
                "Bar on the front delts against the throat, fingertips under the bar just outside shoulders",
                "Lift elbows high, stand up to unrack and take 2–3 steps back",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes straight ahead"),
                Checkpoint(.elbows, "High and pointing forward, upper arms near parallel to the floor"),
                Checkpoint(.back, "Torso stays upright, upper back tight"),
                Checkpoint(.knees, "Travel forward over the toes, tracking with the feet"),
                Checkpoint(.feet, "Shoulder-width, toes out 15–30°, heels down"),
            ],
            mistakes: [
                "Elbows dropping so the bar rolls forward",
                "Wrists forced into a full grip when fingertips would do",
                "Rounding the upper back out of the bottom",
            ],
            breathing: "Breathe in and brace at the top, hold through the rep, exhale near lockout"
        ),
        "goblet-squat": Technique(
            setup: [
                "Pick a dumbbell you can hold vertically by the top bell with both hands",
                "Hold it against the sternum, elbows pointing down",
                "Stand with feet slightly wider than shoulders",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.elbows, "Pointing down, finishing inside the knees at the bottom"),
                Checkpoint(.back, "Tall chest, neutral spine through the whole range"),
                Checkpoint(.knees, "Pushed out in line with the toes"),
                Checkpoint(.feet, "Toes out 15–30°, heels and big toe planted"),
            ],
            mistakes: [
                "Letting the dumbbell drift away from the chest",
                "Heels lifting at the bottom",
                "Bouncing out of the hole instead of pausing",
            ],
            breathing: "Inhale and brace before lowering, exhale as you stand through the top half"
        ),
        "hack-squat": Technique(
            setup: [
                "Set the shoulder pads so they sit on top of the shoulders with the back flat on the pad",
                "Place feet mid-platform, shoulder-width; higher stresses glutes, lower stresses quads",
                "Load plates evenly, stand up and release the safety handles",
            ],
            position: [
                Checkpoint(.head, "Resting back against the pad, eyes forward"),
                Checkpoint(.back, "Whole back stays in contact with the pad"),
                Checkpoint(.hips, "Stay on the pad; no tucking under at the bottom"),
                Checkpoint(.knees, "Track over the toes, bend to at least 90°"),
                Checkpoint(.feet, "Flat on the platform, heels never lift"),
            ],
            mistakes: [
                "Slamming the knees into hard lockout at the top",
                "Cutting depth short as the weight goes up",
                "Forgetting to re-engage the safety handles before stepping out",
            ],
            breathing: "Inhale on the way down, exhale as you drive through the sticking point"
        ),
        "leg-press": Technique(
            setup: [
                "Adjust the backrest so your hips are fully on the seat and lower back flat",
                "Feet mid-platform, shoulder-width, toes slightly out",
                "Press the sled up, then release the safety handles",
            ],
            position: [
                Checkpoint(.hands, "Holding the side handles lightly to stay pinned"),
                Checkpoint(.back, "Lower back stays on the pad the whole set"),
                Checkpoint(.hips, "Stop before the pelvis starts to roll off the seat"),
                Checkpoint(.knees, "Track over the toes, never caving in"),
                Checkpoint(.feet, "Whole foot pressing, heels stay down"),
            ],
            mistakes: [
                "Going so deep the lower back rounds off the pad",
                "Locking the knees out hard at the top",
                "Pushing through the toes with heels lifting",
            ],
            breathing: "Inhale as the sled lowers, exhale as you press past the hardest part"
        ),
        "deadlift": Technique(
            setup: [
                "Stand with the bar over mid-foot, about 3 cm from the shins",
                "Hinge down and grip just outside the legs, double overhand or with straps",
                "Drop hips until shins touch the bar, pull the slack out before lifting",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes on the floor about 2 m ahead"),
                Checkpoint(.shoulders, "Slightly in front of the bar, lats pulling it to the body"),
                Checkpoint(.back, "Neutral spine from setup to lockout"),
                Checkpoint(.hips, "Between knee and shoulder height at the start"),
                Checkpoint(.feet, "Hip-width, bar over mid-foot, push the floor away"),
            ],
            mistakes: [
                "Jerking the bar off the floor without taking the slack out",
                "Rounding the lower back as the bar breaks the floor",
                "Leaning back at lockout instead of finishing with the glutes",
            ],
            breathing: "Big breath and brace before each rep, hold to lockout, reset at the bottom"
        ),
        "trap-bar-deadlift": Technique(
            setup: [
                "Step into the centre of the trap bar, feet hip-width",
                "Use the high handles if mobility is limited, low handles for full range",
                "Grip the middle of the handles so the bar is balanced",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward and slightly down"),
                Checkpoint(.shoulders, "Pulled down, arms straight like hooks"),
                Checkpoint(.back, "Neutral spine, chest proud"),
                Checkpoint(.hips, "Slightly higher than a squat, lower than a deadlift"),
                Checkpoint(.feet, "Hip-width, pressing through the whole foot"),
            ],
            mistakes: [
                "Squatting the lift so the hips start too low",
                "Gripping off-centre so the bar tilts",
                "Shrugging or bending the elbows during the pull",
            ],
            breathing: "Inhale and brace at the bottom, hold through the pull, exhale at the top"
        ),
        "rdl": Technique(
            setup: [
                "Take the bar from a rack set at mid-thigh height or deadlift it up first",
                "Grip just outside the thighs, double overhand or with straps",
                "Stand tall with feet hip-width, knees softly bent",
            ],
            position: [
                Checkpoint(.head, "Neutral, follows the torso; no looking up"),
                Checkpoint(.shoulders, "Pulled back and down, lats keep the bar close"),
                Checkpoint(.back, "Neutral spine throughout"),
                Checkpoint(.hips, "Push straight back until hamstrings are tight"),
                Checkpoint(.knees, "Soft bend set at the top, stays the same all rep"),
            ],
            mistakes: [
                "Rounding the back to chase more depth",
                "Bending the knees more as you go down, turning it into a squat",
                "Letting the bar drift away from the thighs",
            ],
            breathing: "Inhale and brace at the top, lower under control, exhale as hips come through"
        ),
        "db-rdl": Technique(
            setup: [
                "Pick up the dumbbells and stand tall, feet hip-width",
                "Hold them in front of the thighs, palms facing you",
                "Unlock the knees slightly before starting",
            ],
            position: [
                Checkpoint(.head, "Neutral neck, eyes follow the floor"),
                Checkpoint(.shoulders, "Back and down, arms hanging straight"),
                Checkpoint(.hands, "Dumbbells slide close to the legs the whole way"),
                Checkpoint(.back, "Neutral spine, no rounding at the bottom"),
                Checkpoint(.hips, "Drive back as far as the hamstrings allow"),
            ],
            mistakes: [
                "Reaching the dumbbells forward away from the legs",
                "Rounding the back to touch the floor",
                "Squatting down instead of hinging back",
            ],
            breathing: "Inhale as you hinge down, exhale as you stand and squeeze the glutes"
        ),
        "hip-thrust": Technique(
            setup: [
                "Sit with the lower edge of the shoulder blades on a flat bench",
                "Roll a padded bar into the hip crease",
                "Feet flat, hip-width, so shins are vertical at the top",
            ],
            position: [
                Checkpoint(.head, "Chin tucked, eyes forward over the knees"),
                Checkpoint(.hands, "Hold the bar just outside the hips to keep it steady"),
                Checkpoint(.core, "Ribs down, no arching at lockout"),
                Checkpoint(.hips, "Rise to a straight line from shoulders to knees"),
                Checkpoint(.feet, "Flat, drive through the heels"),
            ],
            mistakes: [
                "Arching the lower back instead of extending the hips",
                "Feet too far forward so hamstrings take over",
                "Rushing the top without a squeeze",
            ],
            breathing: "Inhale at the bottom, exhale as you drive up, hold the squeeze for 1 s"
        ),
        "hip-thrust-machine": Technique(
            setup: [
                "Adjust the back pad so it sits under the shoulder blades",
                "Position the hip pad or belt across the hip crease",
                "Select the weight pin and place feet so shins are vertical at the top",
            ],
            position: [
                Checkpoint(.head, "Chin tucked, gaze forward"),
                Checkpoint(.core, "Ribs down, pelvis tucked slightly at the top"),
                Checkpoint(.hips, "Full extension, straight line shoulders to knees"),
                Checkpoint(.knees, "Pushed slightly out, in line with the toes"),
                Checkpoint(.feet, "Flat on the platform, heels driving"),
            ],
            mistakes: [
                "Hyperextending the lower back at the top",
                "Bouncing the stack at the bottom",
                "Skipping the 1 s pause",
            ],
            breathing: "Exhale as you drive up and squeeze, inhale as you lower"
        ),
        "back-extension": Technique(
            setup: [
                "Set the thigh pad so its top edge sits just below the hip crease",
                "Hook heels under the ankle pads, feet flat on the platform",
                "Start straight in line, arms crossed or holding a plate to the chest",
            ],
            position: [
                Checkpoint(.head, "Neutral, in line with the spine"),
                Checkpoint(.back, "Neutral spine, hinge happens at the hips"),
                Checkpoint(.hips, "Fold over the pad, rise by squeezing the glutes"),
                Checkpoint(.knees, "Straight but not locked"),
                Checkpoint(.feet, "Pressed into the platform"),
            ],
            mistakes: [
                "Pad too high so you can't hinge at the hips",
                "Hyperextending past a straight line at the top",
                "Swinging up with momentum",
            ],
            breathing: "Inhale as you lower, exhale as you rise to a straight line"
        ),
        "cable-pull-through": Technique(
            setup: [
                "Set the pulley at the lowest position with a rope attachment",
                "Face away from the stack, rope between the legs, walk out 2 steps",
                "Stand slightly wider than hips, soft knees",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes on the floor ahead"),
                Checkpoint(.hands, "Rope held between the legs, arms passive"),
                Checkpoint(.back, "Neutral spine as you hinge"),
                Checkpoint(.hips, "Push back to load, snap forward to a full squeeze"),
                Checkpoint(.feet, "Planted, weight through mid-foot and heels"),
            ],
            mistakes: [
                "Pulling with the arms instead of the hips",
                "Squatting down instead of hinging back",
                "Leaning back at the top",
            ],
            breathing: "Inhale as you hinge back, exhale as you drive the hips through"
        ),
        "bulgarian-split-squat": Technique(
            setup: [
                "Bench at knee height behind you, rear laces resting on it",
                "Hop the front foot out so the back knee lands under the hip at the bottom",
                "Hold dumbbells at your sides, arms long",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.back, "Tall, or slight forward lean for more glute"),
                Checkpoint(.hips, "Square to the front, dropping straight down"),
                Checkpoint(.knees, "Front knee tracks over the middle toes"),
                Checkpoint(.feet, "Front foot flat, rear foot relaxed on the bench"),
            ],
            mistakes: [
                "Stance too short so the front heel lifts",
                "Front knee caving inward",
                "Pushing off the back leg",
            ],
            breathing: "Inhale as you lower, exhale as you drive up through the front foot"
        ),
        "reverse-lunge": Technique(
            setup: [
                "Hold dumbbells at your sides, feet hip-width",
                "Clear 1 m of floor behind you",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.back, "Torso tall, slight forward lean is fine"),
                Checkpoint(.hips, "Level, dropping straight down"),
                Checkpoint(.knees, "Front knee over mid-foot, back knee just above the floor"),
                Checkpoint(.feet, "Front heel planted, step back onto the ball of the foot"),
            ],
            mistakes: [
                "Stepping back too short so the front knee shoots forward",
                "Slamming the back knee into the floor",
                "Pushing off the back foot instead of the front heel",
            ],
            breathing: "Inhale as you step back and lower, exhale as you drive up"
        ),
        "walking-lunge": Technique(
            setup: [
                "Hold dumbbells at your sides, arms long",
                "Find a clear 10–15 m lane with a non-slip floor",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes on the lane ahead"),
                Checkpoint(.back, "Torso tall, shoulders over hips"),
                Checkpoint(.hips, "Square, dropping straight down each step"),
                Checkpoint(.knees, "Front knee over the toes, back knee lightly kisses the floor"),
                Checkpoint(.feet, "Long stride, feet hip-width apart like on rails"),
            ],
            mistakes: [
                "Walking on a tightrope so balance wobbles",
                "Short choppy steps with knees jutting forward",
                "Torso folding forward when tired",
            ],
            breathing: "Inhale as you step and lower, exhale as you rise into the next step"
        ),
        "step-up": Technique(
            setup: [
                "Choose a box high enough that the thigh is at or above hip level",
                "Stand close to the box, dumbbells at your sides",
                "Place the whole working foot on the box",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.back, "Lean slightly forward over the front foot"),
                Checkpoint(.hips, "Rise to full extension at the top"),
                Checkpoint(.knees, "Working knee tracks over the toes"),
                Checkpoint(.feet, "Back foot passive with toes up – no push-off, like a high step"),
            ],
            mistakes: [
                "Bouncing off the back foot",
                "Only the toes on the box",
                "Dropping down fast instead of lowering under control",
            ],
            breathing: "Exhale as you drive up, inhale as you lower slowly"
        ),
        "single-leg-rdl": Technique(
            setup: [
                "Hold a dumbbell in the hand opposite the standing leg",
                "Stand on one leg with a soft knee, free hand out for balance",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes on the floor as you hinge"),
                Checkpoint(.back, "Long, flat line from head to back heel"),
                Checkpoint(.hips, "Square to the floor, no opening up to the side"),
                Checkpoint(.knees, "Standing knee softly bent and stable"),
                Checkpoint(.feet, "Standing foot rooted; back heel reaching long"),
            ],
            mistakes: [
                "Hip of the free leg rotating up toward the ceiling",
                "Rounding the back to reach lower",
                "Rushing so balance is lost",
            ],
            breathing: "Inhale as you hinge, exhale as you return to standing"
        ),
        "cossack-squat": Technique(
            setup: [
                "Hold a kettlebell at the chest by the horns",
                "Take a wide stance, about twice shoulder-width, toes slightly out",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.back, "Chest up, neutral spine"),
                Checkpoint(.hips, "Shift and sit down over the working leg"),
                Checkpoint(.knees, "Working knee tracks over the toes; straight leg stays long"),
                Checkpoint(.feet, "Working heel stays down, straight-leg toes point up"),
            ],
            mistakes: [
                "Working heel lifting at the bottom",
                "Forcing depth before the hips allow it",
                "Rounding forward over the kettlebell",
            ],
            breathing: "Inhale as you shift down, exhale as you push back to centre"
        ),
        "leg-curl": Technique(
            setup: [
                "Align your knee joint with the machine's pivot axis",
                "Set the ankle pad just above the ankle, on the lower calf",
                "Adjust the thigh pad to pin the legs, select the weight pin",
            ],
            position: [
                Checkpoint(.hands, "Gripping the handles to keep the hips down"),
                Checkpoint(.hips, "Pinned to the pad, no lifting"),
                Checkpoint(.knees, "Aligned with the pivot through the whole range"),
                Checkpoint(.feet, "Toes pulled up toward the shins"),
            ],
            mistakes: [
                "Hips lifting to cheat the weight up",
                "Dropping the weight fast on the way back",
                "Ankle pad sitting on the heel or calf belly",
            ],
            breathing: "Exhale as you curl, inhale on the slow 3 s return"
        ),
        "nordic-curl": Technique(
            setup: [
                "Kneel on a pad with heels anchored under a Nordic bench or a partner",
                "Loop a band from a high anchor around the chest for assistance",
                "Start tall, hips extended, arms ready in front",
            ],
            position: [
                Checkpoint(.head, "Neutral, in line with the torso"),
                Checkpoint(.hands, "Ready to catch you in a push-up position"),
                Checkpoint(.core, "Braced so the body moves as one plank"),
                Checkpoint(.hips, "Extended, no bending at the waist"),
                Checkpoint(.knees, "On a soft pad, the only joint that moves"),
            ],
            mistakes: [
                "Bending at the hips to shorten the lever",
                "Dropping the last half instead of fighting the descent",
                "Too little band help so form breaks immediately",
            ],
            breathing: "Inhale at the top, slow exhale through the lowering"
        ),
        "leg-extension": Technique(
            setup: [
                "Adjust the backrest so your knee joint lines up with the pivot axis",
                "Set the ankle pad just above the ankle on the front of the shin",
                "Select the weight pin and hold the side handles",
            ],
            position: [
                Checkpoint(.back, "Pressed against the backrest"),
                Checkpoint(.hips, "Seated deep, no lifting off the seat"),
                Checkpoint(.knees, "Aligned with the pivot, extend to straight"),
                Checkpoint(.feet, "Toes pointing up, slightly pulled back"),
            ],
            mistakes: [
                "Kicking the weight up with momentum",
                "Hips lifting off the seat",
                "Letting the stack crash down",
            ],
            breathing: "Exhale as you extend and squeeze, inhale on the slow lower"
        ),
        "bench-press": Technique(
            setup: [
                "Set the J-hooks so you unrack with arms nearly straight; safety arms just below chest",
                "Lie with eyes under the bar, grip slightly wider than shoulders",
                "Pull the shoulder blades back and down, plant the feet, then unrack",
            ],
            position: [
                Checkpoint(.head, "On the bench, stays down throughout"),
                Checkpoint(.shoulders, "Blades squeezed back and down, pinned to the bench"),
                Checkpoint(.elbows, "About 45–70° from the torso, under the bar"),
                Checkpoint(.hands, "Wrists stacked over elbows, bar in the heel of the palm"),
                Checkpoint(.feet, "Flat on the floor, driving for leg tension"),
            ],
            mistakes: [
                "Flaring elbows to 90°, irritating the shoulders",
                "Bouncing the bar off the chest",
                "Butt lifting off the bench",
            ],
            breathing: "Inhale and brace as the bar lowers, exhale through the press"
        ),
        "db-bench": Technique(
            setup: [
                "Sit on a flat bench with dumbbells on the thighs",
                "Lie back, kicking the dumbbells up to the chest as you go",
                "Set the shoulder blades back and down before the first rep",
            ],
            position: [
                Checkpoint(.head, "On the bench"),
                Checkpoint(.shoulders, "Blades pinned back and down"),
                Checkpoint(.elbows, "About 45° from the torso, under the wrists"),
                Checkpoint(.hands, "Dumbbells over the lower chest at the top"),
                Checkpoint(.feet, "Flat, pressing into the floor"),
            ],
            mistakes: [
                "Lowering beyond a comfortable shoulder stretch",
                "Clanging the dumbbells together at the top",
                "Dropping the dumbbells to the floor straight from the press",
            ],
            breathing: "Inhale on the way down, exhale as you press up"
        ),
        "incline-db-press": Technique(
            setup: [
                "Set the bench to 30°",
                "Sit with dumbbells on the thighs, kick them up as you lie back",
                "Set shoulder blades back and down against the pad",
            ],
            position: [
                Checkpoint(.head, "Resting on the pad"),
                Checkpoint(.shoulders, "Blades pinned, no shrugging toward the ears"),
                Checkpoint(.elbows, "About 45° from the torso"),
                Checkpoint(.hands, "Press up over the upper chest"),
                Checkpoint(.feet, "Flat on the floor"),
            ],
            mistakes: [
                "Bench set too steep so it becomes a shoulder press",
                "Shoulders rolling forward at the bottom",
                "Arching the back off the pad",
            ],
            breathing: "Inhale as you lower into the stretch, exhale as you press"
        ),
        "chest-press-machine": Technique(
            setup: [
                "Adjust seat height so the handles are at mid-chest",
                "Set the handle depth so you feel a light stretch at the start, not a strain",
                "Select the weight pin, sit with back flat against the pad",
            ],
            position: [
                Checkpoint(.head, "Against the pad, neutral"),
                Checkpoint(.shoulders, "Blades back and down, no shrugging"),
                Checkpoint(.elbows, "Slightly below the shoulders, about 45° out"),
                Checkpoint(.hands, "Full grip, wrists straight"),
                Checkpoint(.feet, "Flat on the floor"),
            ],
            mistakes: [
                "Seat too low so you press upward",
                "Shoulders rolling forward at full extension",
                "Letting the stack slam between reps",
            ],
            breathing: "Exhale as you press, inhale on the slow return"
        ),
        "push-up": Technique(
            setup: [
                "Hands on the floor slightly wider than shoulders, fingers spread",
                "Walk the feet back to a straight plank",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes just ahead of the hands"),
                Checkpoint(.shoulders, "At the top, push the floor away to spread the blades"),
                Checkpoint(.elbows, "About 45° from the torso"),
                Checkpoint(.core, "Rigid plank, glutes and abs tight"),
                Checkpoint(.feet, "Together or hip-width, on the balls of the feet"),
            ],
            mistakes: [
                "Hips sagging toward the floor",
                "Elbows flared straight out to the side",
                "Partial reps that stop short of the floor",
            ],
            breathing: "Inhale as you lower, exhale as you push up"
        ),
        "ring-push-up": Technique(
            setup: [
                "Set the rings 10–30 cm above the floor; higher is easier",
                "Grip the rings, walk the feet back into a plank",
            ],
            position: [
                Checkpoint(.shoulders, "Depressed, blades spread at the top"),
                Checkpoint(.elbows, "Tucked close to the ribs"),
                Checkpoint(.hands, "Rings turned out at the top, knuckles forward at bottom"),
                Checkpoint(.core, "Rigid plank, no sag"),
                Checkpoint(.feet, "Together, on the balls of the feet"),
            ],
            mistakes: [
                "Rings drifting wide so the shoulders strain",
                "Hips sagging when the rings start to shake",
                "Going deeper than shoulders allow",
            ],
            breathing: "Inhale as you lower between the rings, exhale as you press"
        ),
        "dips": Technique(
            setup: [
                "Grip the parallel bars, jump or step up to straight arms",
                "Use the assisted dip machine or a band if you can't do 5 clean reps",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.shoulders, "Pulled down away from the ears – mantle position"),
                Checkpoint(.elbows, "Point back, lower until about 90°"),
                Checkpoint(.back, "Slight forward lean"),
                Checkpoint(.feet, "Crossed behind or together, legs quiet"),
            ],
            mistakes: [
                "Sinking too deep with shoulders rolling forward",
                "Shrugging the shoulders up to the ears",
                "Kipping with the legs",
            ],
            breathing: "Inhale as you lower, exhale as you press to lockout"
        ),
        "cable-fly": Technique(
            setup: [
                "Set both pulleys at shoulder height with D-handles",
                "Grip a handle in each hand, step forward into a split stance",
                "Arms open with a soft bend before the first rep",
            ],
            position: [
                Checkpoint(.shoulders, "Down and back, chest proud"),
                Checkpoint(.elbows, "Soft bend locked in place for the whole rep"),
                Checkpoint(.hands, "Meet in front of the chest in a hugging arc"),
                Checkpoint(.core, "Braced, no rocking"),
                Checkpoint(.feet, "Staggered stance for balance"),
            ],
            mistakes: [
                "Bending the elbows so it turns into a press",
                "Letting the arms go too far back and stressing the shoulders",
                "Leaning forward to move more weight",
            ],
            breathing: "Exhale as the hands come together, inhale as the arms open"
        ),
        "ohp": Technique(
            setup: [
                "Set the J-hooks at upper-chest height",
                "Grip just outside shoulders, step under so the bar rests on the front delts",
                "Unrack, step back 1–2 steps, squeeze glutes",
            ],
            position: [
                Checkpoint(.head, "Moves back to clear the bar, then through at lockout"),
                Checkpoint(.elbows, "Slightly in front of the bar at the start"),
                Checkpoint(.hands, "Wrists stacked over elbows, bar in the heel of the palm"),
                Checkpoint(.core, "Glutes and abs tight, ribs down"),
                Checkpoint(.feet, "Hip-width, planted"),
            ],
            mistakes: [
                "Leaning back and arching the lower back",
                "Pressing the bar forward around the face instead of straight up",
                "Not finishing with the head through and arms by the ears",
            ],
            breathing: "Inhale and brace at the bottom, exhale as you pass the forehead"
        ),
        "seated-db-press": Technique(
            setup: [
                "Set the bench to 80–90° with the seat slightly raised",
                "Sit with dumbbells on the thighs, kick them up to shoulder height",
            ],
            position: [
                Checkpoint(.head, "Against the pad or neutral, eyes forward"),
                Checkpoint(.shoulders, "Down, not shrugging into the ears"),
                Checkpoint(.elbows, "Slightly forward of the body, under the wrists"),
                Checkpoint(.back, "Pressed into the pad, no big arch"),
                Checkpoint(.feet, "Flat and wide for stability"),
            ],
            mistakes: [
                "Arching off the pad to finish the rep",
                "Lowering too far so the shoulders roll forward",
                "Dumbbells drifting behind the head",
            ],
            breathing: "Inhale as you lower, exhale as you press overhead"
        ),
        "landmine-press": Technique(
            setup: [
                "Load a barbell in the landmine",
                "Half-kneel with the down knee on the same side as the pressing hand",
                "Hold the bar end at the shoulder, other hand on the hip or out",
            ],
            position: [
                Checkpoint(.shoulders, "Reach forward at the top to let the blade glide"),
                Checkpoint(.elbows, "Start under the bar, about 45° from the body"),
                Checkpoint(.core, "Braced, ribs down, no twisting"),
                Checkpoint(.hips, "Glute of the down knee squeezed, hips stacked"),
                Checkpoint(.knees, "Front and back knee both at 90°"),
            ],
            mistakes: [
                "Arching the back to push the bar higher",
                "Hips shifting back so the glute switches off",
                "Shrugging the shoulder instead of reaching",
            ],
            breathing: "Exhale as you press and reach, inhale as you lower"
        ),
        "arnold-press": Technique(
            setup: [
                "Set the bench at 80–90°",
                "Kick the dumbbells up to chin height, palms facing you",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.shoulders, "Down, no shrug at the top"),
                Checkpoint(.elbows, "Open out as the palms rotate forward"),
                Checkpoint(.hands, "Rotate smoothly to face forward at lockout"),
                Checkpoint(.back, "Against the pad, no lower-back arch"),
            ],
            mistakes: [
                "Rotating fast and jerky",
                "Arching the lower back off the pad",
                "Using too much weight for the shoulder to control the turn",
            ],
            breathing: "Exhale as you rotate and press, inhale as you lower"
        ),
        "barbell-row": Technique(
            setup: [
                "Deadlift the bar to standing first",
                "Grip just outside the thighs, overhand",
                "Hinge to about 45° with soft knees",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes on the floor ahead"),
                Checkpoint(.elbows, "Drive back past the torso"),
                Checkpoint(.hands, "Pull the bar to the lower ribs"),
                Checkpoint(.back, "Neutral spine, angle stays the same all set"),
                Checkpoint(.knees, "Softly bent, stable"),
            ],
            mistakes: [
                "Torso rising each rep so it turns into a shrug",
                "Rounding the lower back",
                "Jerking the weight with the legs",
            ],
            breathing: "Exhale as you row, inhale as the bar lowers"
        ),
        "chest-supported-row": Technique(
            setup: [
                "Set the bench to 30–45°",
                "Lie face down with chest on the top of the pad, feet on the floor",
                "Let the dumbbells hang straight under the shoulders",
            ],
            position: [
                Checkpoint(.head, "Neutral, chin off the pad"),
                Checkpoint(.shoulders, "Pull blades back and down, no shrug"),
                Checkpoint(.elbows, "Lead the pull, finish beside the ribs"),
                Checkpoint(.back, "Chest stays on the pad"),
                Checkpoint(.feet, "Toes or balls of the feet on the floor for support"),
            ],
            mistakes: [
                "Lifting the chest off the pad to swing",
                "Shrugging the shoulders to the ears",
                "Short reps without full arm extension at the bottom",
            ],
            breathing: "Exhale as you pull, inhale as you lower"
        ),
        "seated-cable-row": Technique(
            setup: [
                "Attach a close-grip handle, select the weight pin",
                "Sit with feet on the footplates, knees softly bent",
                "Grab the handle and sit tall, arms straight",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes forward"),
                Checkpoint(.shoulders, "Squeeze blades together at the end of the pull"),
                Checkpoint(.elbows, "Close to the body, drive back past the ribs"),
                Checkpoint(.back, "Tall spine, no rocking back and forth"),
                Checkpoint(.feet, "Pressed into the footplates"),
            ],
            mistakes: [
                "Leaning far back to move the weight",
                "Rounding forward at the stretch",
                "Shrugging instead of pulling the blades back",
            ],
            breathing: "Exhale as you pull, inhale as the arms extend"
        ),
        "one-arm-db-row": Technique(
            setup: [
                "Place one knee and the same hand on a flat bench",
                "Other foot on the floor out to the side, dumbbell hanging under the shoulder",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes on the floor"),
                Checkpoint(.shoulders, "Level, no rotating the torso open"),
                Checkpoint(.elbows, "Pull toward the hip, close to the body"),
                Checkpoint(.back, "Flat, parallel to the floor"),
                Checkpoint(.feet, "Standing foot planted wide for balance"),
            ],
            mistakes: [
                "Twisting the torso to heave the weight",
                "Pulling to the chest instead of the hip",
                "Rounding the back",
            ],
            breathing: "Exhale as you row, inhale as you lower"
        ),
    ]
}
