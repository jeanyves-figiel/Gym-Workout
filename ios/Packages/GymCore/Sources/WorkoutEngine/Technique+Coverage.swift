// Technique content for the coverage staples (#77).

extension Technique {
    static let coverage: [String: Technique] = [
        "smith-squat": Technique(
            setup: [
                "Set the bar at upper-chest height and the safety stops just below squat depth",
                "Bar on the upper back, feet a half step in front of the bar, shoulder-width",
            ],
            position: [
                Checkpoint(.back, "Chest up, back flat against the bar path"),
                Checkpoint(.core, "Brace before each rep"),
                Checkpoint(.knees, "Track over the toes, no caving in"),
                Checkpoint(.feet, "Whole foot flat, weight mid-foot to heel"),
            ],
            mistakes: [
                "Feet directly under the bar so the knees jam forward",
                "Half reps above parallel",
                "Bouncing off the safety stops",
            ],
            breathing: "Inhale and brace at the top, exhale as you stand up"
        ),
        "good-morning": Technique(
            setup: [
                "Set the J-hooks at upper-chest height and start with an empty bar",
                "Bar on the upper back as for a squat, feet hip-width, knees soft",
            ],
            position: [
                Checkpoint(.back, "Neutral spine from head to hips, no rounding"),
                Checkpoint(.hips, "Push straight back until the hamstrings stretch"),
                Checkpoint(.knees, "Slightly bent, stay still"),
                Checkpoint(.feet, "Weight on the heels and mid-foot"),
            ],
            mistakes: [
                "Rounding the lower back to go deeper",
                "Bending the knees into a squat",
                "Going heavy before the hinge is solid",
            ],
            breathing: "Inhale and brace before hinging, exhale as the hips come through"
        ),
        "reverse-nordic": Technique(
            setup: [
                "Kneel on a mat with knees hip-width and the tops of the feet flat",
                "Cross the arms on the chest or hold them out in front",
            ],
            position: [
                Checkpoint(.hips, "Locked straight: one line from knees to shoulders"),
                Checkpoint(.core, "Ribs down, glutes squeezed"),
                Checkpoint(.knees, "Stay planted; the bend happens only here"),
                Checkpoint(.head, "Neutral, in line with the torso"),
            ],
            mistakes: [
                "Bending at the hips instead of leaning back as one plank",
                "Dropping further than you can return from",
                "Arching the lower back",
            ],
            breathing: "Inhale as you lean back, exhale as you return upright"
        ),
        "trx-hamstring-curl": Technique(
            setup: [
                "Shorten the TRX so the foot cradles hang about a shin's height above the floor",
                "Lie on your back and put both heels in the cradles, arms by the sides",
            ],
            position: [
                Checkpoint(.hips, "Lifted into a bridge and kept high"),
                Checkpoint(.core, "Ribs down, no arch"),
                Checkpoint(.knees, "Pull toward the hips, then extend slowly"),
                Checkpoint(.feet, "Heels pressed into the straps, toes up"),
            ],
            mistakes: [
                "Hips sagging as the knees bend",
                "Letting the legs drop straight out",
                "Pushing through the arms instead of the hamstrings",
            ],
            breathing: "Exhale as you curl the heels in, inhale as you extend"
        ),
        "leg-press-calf-raise": Technique(
            setup: [
                "Sit in the leg press and set the safety catches",
                "Place the balls of the feet on the bottom edge of the platform, knees straight but not locked",
            ],
            position: [
                Checkpoint(.back, "Flat against the pad"),
                Checkpoint(.knees, "Straight and still throughout"),
                Checkpoint(.feet, "Balls of the feet on the edge, heels free"),
                Checkpoint(.hips, "Stay on the seat"),
            ],
            mistakes: [
                "Bending the knees to push the sled",
                "Short bouncing reps without the stretch",
                "Feet slipping up the platform",
            ],
            breathing: "Exhale as you press up onto the toes, inhale as the heels drop"
        ),
        "incline-bench-press": Technique(
            setup: [
                "Set the bench to 30° and the J-hooks so the bar unracks with nearly straight arms",
                "Grip a little wider than shoulder-width, eyes under the bar",
            ],
            position: [
                Checkpoint(.shoulders, "Blades pinned back and down into the bench"),
                Checkpoint(.elbows, "About 45–60° from the torso"),
                Checkpoint(.hands, "Bar over the wrists, wrists stacked over elbows"),
                Checkpoint(.feet, "Flat on the floor, driving"),
            ],
            mistakes: [
                "Bench set too steep so it turns into a shoulder press",
                "Bouncing the bar off the chest",
                "Hips lifting off the bench",
            ],
            breathing: "Inhale as you lower to the upper chest, exhale as you press"
        ),
        "pec-deck-fly": Technique(
            setup: [
                "Adjust the seat so the handles are at chest height",
                "Sit with the back flat on the pad, arms open with a soft elbow",
            ],
            position: [
                Checkpoint(.back, "Flat on the pad, chest proud"),
                Checkpoint(.shoulders, "Down and back, no shrug"),
                Checkpoint(.elbows, "Soft bend that stays the same"),
                Checkpoint(.hands, "Light grip, push through the forearms or handles"),
            ],
            mistakes: [
                "Letting the handles pull the arms past the shoulders",
                "Bending and straightening the elbows",
                "Shrugging toward the ears",
            ],
            breathing: "Exhale as you bring the handles together, inhale as they open"
        ),
        "chin-up": Technique(
            setup: [
                "Grip the bar palms toward you, shoulder-width",
                "Start from a full hang with the shoulders pulled down",
            ],
            position: [
                Checkpoint(.shoulders, "Pull down first, away from the ears"),
                Checkpoint(.elbows, "Drive down to the ribs"),
                Checkpoint(.core, "Legs together, slight hollow"),
                Checkpoint(.head, "Chin over the bar, neck neutral"),
            ],
            mistakes: [
                "Kipping or swinging the legs",
                "Half reps that stop short of a full hang",
                "Craning the neck to reach the bar",
            ],
            breathing: "Exhale as you pull up, inhale as you lower"
        ),
        "band-assisted-pull-up": Technique(
            setup: [
                "Loop a band over the bar and through itself",
                "Step a knee or foot into the band, grip the bar slightly wider than the shoulders",
            ],
            position: [
                Checkpoint(.shoulders, "Depress before each pull"),
                Checkpoint(.elbows, "Drive down toward the back pockets"),
                Checkpoint(.core, "Body still, no swinging on the band"),
                Checkpoint(.knees, "Stay in the band, legs quiet"),
            ],
            mistakes: [
                "Bouncing out of the bottom using the band",
                "Not reaching a full hang",
                "Always using the same band instead of progressing",
            ],
            breathing: "Exhale as you pull up, inhale as you lower"
        ),
        "close-grip-bench": Technique(
            setup: [
                "Set the J-hooks so the bar unracks with nearly straight arms",
                "Grip shoulder-width, no narrower",
            ],
            position: [
                Checkpoint(.shoulders, "Blades back and down"),
                Checkpoint(.elbows, "Tucked close to the ribs"),
                Checkpoint(.hands, "Wrists straight over the elbows"),
                Checkpoint(.feet, "Flat, driving into the floor"),
            ],
            mistakes: [
                "Hands so close the wrists bend",
                "Elbows flaring out",
                "Bouncing off the chest",
            ],
            breathing: "Inhale as you lower to the lower chest, exhale as you press"
        ),
        "db-overhead-triceps": Technique(
            setup: [
                "Pick one dumbbell and hold it with both hands under the top plate",
                "Press it overhead, feet hip-width, glutes tight",
            ],
            position: [
                Checkpoint(.elbows, "Point up, stay close to the head"),
                Checkpoint(.hands, "Cup the plate, wrists firm"),
                Checkpoint(.core, "Ribs down, no arch"),
                Checkpoint(.back, "Tall and neutral"),
            ],
            mistakes: [
                "Elbows flaring wide",
                "Arching the lower back",
                "Cutting the stretch short at the bottom",
            ],
            breathing: "Inhale as you lower behind the head, exhale as you extend"
        ),
        "reverse-crunch": Technique(
            setup: [
                "Lie on your back on a mat, arms by the sides, palms down",
                "Lift the legs with knees bent at 90°",
            ],
            position: [
                Checkpoint(.back, "Lower back stays pressed into the floor"),
                Checkpoint(.core, "Curl the pelvis toward the ribs"),
                Checkpoint(.hips, "Lift a few centimetres off the mat"),
                Checkpoint(.knees, "Bend stays the same"),
            ],
            mistakes: [
                "Swinging the legs for momentum",
                "Pushing through the arms",
                "Dropping the hips without control",
            ],
            breathing: "Exhale as you curl the hips up, inhale as you lower"
        ),
        "copenhagen-plank": Technique(
            setup: [
                "Lie on your side next to a bench and place the top leg on it (inside of the knee for short lever, ankle for long lever)",
                "Prop up on the forearm, elbow under the shoulder",
            ],
            position: [
                Checkpoint(.shoulders, "Elbow directly under the shoulder, push the floor away"),
                Checkpoint(.hips, "Lifted in line with the shoulders and feet"),
                Checkpoint(.core, "Ribs stacked, no rotation"),
                Checkpoint(.knees, "Top leg presses down into the bench"),
            ],
            mistakes: [
                "Hips sagging toward the floor",
                "Starting with the long lever before the short lever is easy",
                "Rolling the chest toward the floor",
            ],
            breathing: "Slow, steady breaths through the hold"
        ),
        "side-lying-external-rotation": Technique(
            setup: [
                "Lie on your side on a bench or mat with a very light dumbbell in the top hand",
                "Put a folded towel between the elbow and ribs, elbow bent to 90°",
            ],
            position: [
                Checkpoint(.shoulders, "Pulled back, not rolled forward"),
                Checkpoint(.elbows, "Stay pinned on the towel"),
                Checkpoint(.hands, "Wrist straight"),
                Checkpoint(.head, "Resting on the bottom arm"),
            ],
            mistakes: [
                "Lifting the elbow away from the ribs",
                "Going too heavy and swinging",
                "Rolling the torso backward to cheat range",
            ],
            breathing: "Exhale as you rotate up, inhale as you lower"
        ),
    ]
}
