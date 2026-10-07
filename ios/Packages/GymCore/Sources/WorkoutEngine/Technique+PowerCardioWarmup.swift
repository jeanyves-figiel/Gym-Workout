// Technique content: setup, body position, mistakes, breathing.

extension Technique {
    static let powerCardioWarmup: [String: Technique] = [
        // MARK: - Jumps

        "box-jump": Technique(
            setup: [
                "Pick a stable box you can land on in a quarter squat – start at 50–60 cm",
                "Place it on a non-slip floor with clear space all around",
                "Stand one foot-length from the box, feet hip-width apart",
            ],
            position: [
                Checkpoint(.head, "Eyes on the top of the box, chin neutral"),
                Checkpoint(.hands, "Swing arms back on the dip, then drive them up hard"),
                Checkpoint(.hips, "Land with hips back, as high as or higher than the knees"),
                Checkpoint(.knees, "Land soft and track the knees over the toes"),
                Checkpoint(.feet, "Whole foot lands on the box, then step down – never jump down"),
            ],
            mistakes: [
                "Choosing a box so tall you land in a deep squat",
                "Jumping back down off the box between reps",
                "Knees caving inward on the landing",
            ],
            breathing: "Sharp inhale on the dip, exhale on the jump; reset breathing before each rep"
        ),
        "broad-jump": Technique(
            setup: [
                "Clear a 3–4 m runway on a non-slip floor or turf",
                "Stand behind a line with feet hip-width apart, arms relaxed at your sides",
            ],
            position: [
                Checkpoint(.hands, "Swing arms back on the load, then throw them forward and up"),
                Checkpoint(.back, "Flat back as you hinge to load"),
                Checkpoint(.hips, "Drive hips fully forward at take-off; sit them back on landing"),
                Checkpoint(.knees, "Land soft, knees bent and pointing over the toes"),
                Checkpoint(.feet, "Take off and land on both feet at once; stick and hold 2 s"),
            ],
            mistakes: [
                "Landing with straight legs or falling forward",
                "Skipping the arm swing",
                "Knees caving in on take-off or landing",
            ],
            breathing: "Inhale as you load, exhale through the jump; reset before the next rep"
        ),
        "squat-jump": Technique(
            setup: [
                "Clear a spot on a non-slip floor",
                "Stand with feet hip- to shoulder-width apart, toes slightly out",
            ],
            position: [
                Checkpoint(.head, "Eyes forward, chin neutral"),
                Checkpoint(.hands, "Swing arms down on the dip and up hard on the jump"),
                Checkpoint(.hips, "Dip to a quarter squat, hips back; extend fully in the air"),
                Checkpoint(.knees, "Land soft and track the knees over the toes"),
                Checkpoint(.feet, "Land on the balls of the feet, then whole foot, same spot"),
            ],
            mistakes: [
                "Dropping into a deep squat and losing speed",
                "Bouncing straight into the next rep instead of resetting",
                "Stiff, loud landings",
            ],
            breathing: "Inhale on the dip, exhale on the jump; reset each rep"
        ),
        "lateral-bound": Technique(
            setup: [
                "Clear 2–3 m of space to each side on a non-slip floor",
                "Stand on one leg, slight knee bend, opposite foot off the floor",
            ],
            position: [
                Checkpoint(.shoulders, "Stay over the landing leg, chest facing forward"),
                Checkpoint(.core, "Braced so the torso does not tip sideways on landing"),
                Checkpoint(.hips, "Push off sideways from the outside leg; sit hips back on landing"),
                Checkpoint(.knees, "Landing knee tracks over the toes, never caves in"),
                Checkpoint(.feet, "Land on the far foot and stick it for 1 s before bounding back"),
            ],
            mistakes: [
                "Bounding farther than you can control the landing",
                "Knee collapsing inward on the landing leg",
                "Rushing into the next bound without sticking",
            ],
            breathing: "Exhale on the push-off, breathe in during the 1 s stick"
        ),
        "depth-jump": Technique(
            setup: [
                "Use a stable box of 30–45 cm; only go higher once contacts stay short",
                "Place it on a non-slip floor with a clear landing space in front",
                "Stand at the edge of the box with toes just over the edge",
            ],
            position: [
                Checkpoint(.head, "Eyes forward, not down at the floor"),
                Checkpoint(.hands, "Arms ready to drive up the instant you land"),
                Checkpoint(.hips, "Step off, land with hips slightly back, then rebound up"),
                Checkpoint(.knees, "Slight bend on contact, knees over toes, no deep squat"),
                Checkpoint(.feet, "Both feet land together on the balls; spend minimal time on the floor"),
            ],
            mistakes: [
                "Jumping up off the box instead of stepping off",
                "Long, sinking ground contact that kills the rebound",
                "Using a box too high to rebound quickly",
            ],
            breathing: "Inhale on the box, exhale sharply on the rebound"
        ),
        "trap-bar-jump": Technique(
            setup: [
                "Load the trap bar to about 20–30% of your deadlift 1RM",
                "Use high handles if available; stand centred, feet hip-width",
                "Grip the middle of the handles, arms long",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes a few metres ahead"),
                Checkpoint(.back, "Flat and braced from dip to landing"),
                Checkpoint(.hips, "Quarter dip with hips back, then drive up to full extension"),
                Checkpoint(.knees, "Land soft with knees bent and tracking over the toes"),
                Checkpoint(.feet, "Leave and land on both feet; settle fully before the next rep"),
            ],
            mistakes: [
                "Loading too heavy so the jump is slow",
                "Rounding the back on the landing",
                "Bouncing reps without a reset",
            ],
            breathing: "Inhale and brace before the dip, exhale at the top or after landing"
        ),

        // MARK: - Throws and ballistics

        "med-ball-chest-pass": Technique(
            setup: [
                "Pick a 3–5 kg med ball that bounces back safely",
                "Stand 1–2 m from a solid wall in a split stance",
                "Hold the ball at chest height, hands on the sides, elbows out",
            ],
            position: [
                Checkpoint(.shoulders, "Down and back as you load the ball"),
                Checkpoint(.elbows, "Drive them straight forward until arms are fully extended"),
                Checkpoint(.hands, "Push through the ball and finish with thumbs pointing down"),
                Checkpoint(.core, "Braced so the push comes from a stable trunk"),
                Checkpoint(.feet, "Step into the throw with the front foot"),
            ],
            mistakes: [
                "Pushing slowly instead of throwing at max speed",
                "Standing so close the rebound hits your face",
                "Flaring the lower back as you throw",
            ],
            breathing: "Sharp exhale on each throw, inhale on the catch"
        ),
        "rotational-throw": Technique(
            setup: [
                "Pick a 3–6 kg med ball and stand side-on to a solid wall, 1–2 m away",
                "Feet wider than hips, hold the ball at hip height on the far side",
            ],
            position: [
                Checkpoint(.shoulders, "Follow the hips, turning through to face the wall"),
                Checkpoint(.hands, "Arms long and relaxed, releasing at chest height"),
                Checkpoint(.core, "Braced; rotation comes through the hips and mid back"),
                Checkpoint(.hips, "Load the back hip, then turn it hard toward the wall first"),
                Checkpoint(.feet, "Pivot the back foot so the heel turns out on release"),
            ],
            mistakes: [
                "Throwing with the arms instead of the hips",
                "Twisting from the low back with feet locked",
                "Going too heavy and losing speed",
            ],
            breathing: "Inhale as you load the back hip, exhale sharply on release"
        ),
        "ball-slam": Technique(
            setup: [
                "Use a dead-bounce slam ball of 6–10 kg",
                "Clear the floor around you; stand feet shoulder-width apart",
                "Hold the ball at chest height with both hands",
            ],
            position: [
                Checkpoint(.head, "Neutral; eyes follow the ball down"),
                Checkpoint(.hands, "Reach the ball fully overhead before slamming"),
                Checkpoint(.core, "Crunch hard as the ball comes down"),
                Checkpoint(.hips, "Hinge back as you slam, then squat down to pick it up"),
                Checkpoint(.knees, "Soft and bent; never lock the legs"),
            ],
            mistakes: [
                "Using a bouncy ball that rebounds into your face",
                "Rounding the back to pick up the ball",
                "Slamming with arms only, no full overhead reach",
            ],
            breathing: "Inhale reaching overhead, forceful exhale on the slam"
        ),
        "overhead-back-throw": Technique(
            setup: [
                "Use an outdoor area or large open space with 10 m clear behind you",
                "Pick a 3–5 kg med ball and check nobody is behind you",
                "Stand feet shoulder-width apart, ball held at arm's length",
            ],
            position: [
                Checkpoint(.head, "Neutral; do not throw the head back"),
                Checkpoint(.hands, "Swing the ball down between the legs, then up and overhead"),
                Checkpoint(.back, "Flat during the dip; open up only at release"),
                Checkpoint(.hips, "Hinge to load, then drive the hips forward hard"),
                Checkpoint(.feet, "Drive through the floor; finish up on the toes"),
            ],
            mistakes: [
                "Throwing with the arms instead of the hips",
                "Over-arching the lower back at release",
                "Throwing without checking the landing area",
            ],
            breathing: "Inhale on the dip, exhale sharply on release"
        ),
        "kb-swing": Technique(
            setup: [
                "Pick a bell you can snap hard – often 16–24 kg",
                "Place it about 30 cm in front of you; feet just wider than hips",
                "Hinge, grip the handle and tilt the bell toward you",
            ],
            position: [
                Checkpoint(.head, "Neutral; eyes a few metres ahead on the floor at the bottom"),
                Checkpoint(.hands, "Arms long and loose, the bell floats to chest height"),
                Checkpoint(.back, "Flat throughout; the hinge happens at the hips"),
                Checkpoint(.hips, "Hike the bell high between the legs, then snap hips forward"),
                Checkpoint(.feet, "Whole foot planted, weight mid-foot to heel"),
            ],
            mistakes: [
                "Squatting the swing instead of hinging",
                "Lifting the bell with the arms",
                "Leaning back at the top instead of standing tall",
            ],
            breathing: "Inhale on the backswing, sharp exhale at the hip snap"
        ),
        "kb-snatch": Technique(
            setup: [
                "Pick a light bell, often 12–16 kg, and master one-arm swings first",
                "Place the bell in front; feet just wider than hips",
                "Hinge and grip the handle with one hand, thumb back",
            ],
            position: [
                Checkpoint(.shoulders, "Packed down at the top, biceps by the ear"),
                Checkpoint(.elbows, "Keep the bell close, elbow high on the way up"),
                Checkpoint(.hands, "Punch the hand through at the top so the bell rolls softly"),
                Checkpoint(.back, "Flat during the hinge, tall and locked out at the top"),
                Checkpoint(.hips, "Snap the hips to power the bell; they do the work"),
            ],
            mistakes: [
                "Letting the bell flop over and bang the forearm",
                "Swinging the bell wide in an arc away from the body",
                "Pressing the bell up instead of punching through",
            ],
            breathing: "Exhale on the hip snap, inhale at the top or on the drop"
        ),
        "hang-power-clean": Technique(
            setup: [
                "Start light – an empty bar or 20–40 kg – and learn the pattern first",
                "Deadlift the bar to standing, hands just outside the thighs, hook grip",
                "Lower to the hang: bar at mid-thigh, hips back, shoulders over the bar",
            ],
            position: [
                Checkpoint(.shoulders, "Over the bar at the hang, then shrug up hard"),
                Checkpoint(.elbows, "Whip them fast around the bar into the front rack"),
                Checkpoint(.back, "Flat and braced from hang to catch"),
                Checkpoint(.hips, "Jump: drive them forward fully to make the bar float"),
                Checkpoint(.feet, "Catch in a quarter squat, feet flat, slightly wider stance"),
            ],
            mistakes: [
                "Pulling early with the arms",
                "Swinging the bar out away from the body",
                "Catching with low elbows and the bar on the wrists",
            ],
            breathing: "Inhale and brace at the hang, exhale after catching the bar"
        ),
        "sled-sprint": Technique(
            setup: [
                "Load the sled so you can drive fast – start light, about body weight",
                "Check a clear 10–15 m lane on the turf",
                "Grip the high or low poles with arms nearly straight",
            ],
            position: [
                Checkpoint(.head, "Neutral, in line with the spine, eyes on the floor ahead"),
                Checkpoint(.hands, "Firm grip on the poles, arms locked or slightly bent"),
                Checkpoint(.back, "Long and straight, body angled about 45 degrees"),
                Checkpoint(.knees, "Drive them forward and up with each step"),
                Checkpoint(.feet, "Push through the balls of the feet, short powerful steps"),
            ],
            mistakes: [
                "Loading so heavy it becomes a slow grind",
                "Rounding the back or dropping the head",
                "Standing upright and losing the drive angle",
            ],
            breathing: "Quick, rhythmic breaths with each step; never hold the breath"
        ),
        "plyo-push-up": Technique(
            setup: [
                "Use a mat; progress from knees or hands on a bench if needed",
                "Start in a high plank, hands just wider than shoulders",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes just ahead of the hands"),
                Checkpoint(.elbows, "About 45 degrees from the body, soft on landing"),
                Checkpoint(.hands, "Push hard so they leave the floor, land under the shoulders"),
                Checkpoint(.core, "Braced so the body moves as one plank"),
                Checkpoint(.hips, "In line with shoulders and heels, no sag"),
            ],
            mistakes: [
                "Landing with locked elbows",
                "Hips sagging or piking during the push",
                "Doing reps after speed drops off",
            ],
            breathing: "Inhale on the way down, exhale sharply on the push"
        ),
        "explosive-pull-up": Technique(
            setup: [
                "Check the bar is secure and you can do 5+ strict pull-ups",
                "Grip the bar just wider than shoulders and hang with straight arms",
                "Set the shoulders down before each rep",
            ],
            position: [
                Checkpoint(.head, "Neutral; aim to get the chest to the bar, not the chin"),
                Checkpoint(.shoulders, "Engaged, never fully slack at the bottom"),
                Checkpoint(.elbows, "Drive them down and back as fast as possible"),
                Checkpoint(.core, "Tight, legs together, no kipping swing"),
                Checkpoint(.feet, "Together and slightly forward to keep a hollow body"),
            ],
            mistakes: [
                "Kipping or swinging to get height",
                "Dropping fast from the top instead of a 3 s lower",
                "Continuing reps once speed clearly slows",
            ],
            breathing: "Exhale on the explosive pull, inhale during the slow lower"
        ),
        "battle-rope-slams": Technique(
            setup: [
                "Anchor the rope securely; take one end in each hand",
                "Step back until there is a little slack in the rope",
                "Stand feet shoulder-width apart in an athletic half squat",
            ],
            position: [
                Checkpoint(.shoulders, "Down, not shrugged up to the ears"),
                Checkpoint(.hands, "Lift the ropes overhead, then slam them down together"),
                Checkpoint(.core, "Braced; crunch down with each slam"),
                Checkpoint(.hips, "Loaded back and low; use them to drive each wave"),
                Checkpoint(.knees, "Soft and bent; absorb each slam"),
            ],
            mistakes: [
                "Standing upright with straight legs",
                "Small waves with arms only",
                "Standing too close so the rope goes slack",
            ],
            breathing: "Exhale on every slam, short inhales as you lift"
        ),

        // MARK: - Cardio machines

        "rower": Technique(
            setup: [
                "Set the damper to 4–6 and strap feet so the strap crosses the widest part of the foot",
                "Sit tall at the catch: shins vertical, arms straight, handle at the toes",
            ],
            position: [
                Checkpoint(.shoulders, "Relaxed and down, never shrugged"),
                Checkpoint(.back, "Long spine, lean back ~11 o'clock at the finish"),
                Checkpoint(.hands, "Handle to lower ribs, wrists flat"),
                Checkpoint(.knees, "Stay down until the hands pass them on the recovery"),
            ],
            mistakes: [
                "Pulling with the arms before the legs have pushed",
                "Rushing the slide forward on the recovery",
            ],
            breathing: "Exhale on the drive, inhale on the recovery; settle into a steady rhythm"
        ),
        "ski-erg": Technique(
            setup: [
                "Set the damper to 4–6 and use the monitor's just-row or interval mode",
                "Stand a short step back from the machine, feet hip-width apart",
                "Grab the handles overhead, arms nearly straight",
            ],
            position: [
                Checkpoint(.shoulders, "Pull down using the lats, not by shrugging"),
                Checkpoint(.elbows, "Slight bend, stay fixed; arms stay long"),
                Checkpoint(.hands, "Drive down close to the body and finish past the hips"),
                Checkpoint(.hips, "Hinge back as the hands come down"),
                Checkpoint(.knees, "Soft bend, just following the hinge"),
            ],
            mistakes: [
                "Squatting deep instead of hinging",
                "Bending the elbows like a tricep pushdown",
                "Rushing back up before the full finish",
            ],
            breathing: "Exhale on the pull down, inhale as you rise"
        ),
        "air-bike": Technique(
            setup: [
                "Set seat height so the knee keeps a slight bend at the bottom of the pedal stroke",
                "Set the seat fore-aft so your knee sits over the pedal axle",
                "Hold the handles at mid-height with a relaxed grip",
            ],
            position: [
                Checkpoint(.shoulders, "Relaxed and down; arms push and pull evenly"),
                Checkpoint(.hands, "Push one handle as you pull the other"),
                Checkpoint(.core, "Braced; hips stay level on the seat"),
                Checkpoint(.knees, "Track straight up and down over the feet"),
                Checkpoint(.feet, "Balls of the feet on the pedals, pushing through the whole circle"),
            ],
            mistakes: [
                "Seat too low, with knees jamming at the top",
                "Using only legs or only arms",
                "Starting all-out and fading after 10 seconds",
            ],
            breathing: "Breathe rhythmically with the pedal; on sprints breathe fast and deep"
        ),
        "bike": Technique(
            setup: [
                "Set seat height so the knee keeps a slight bend at the bottom of the pedal stroke",
                "Set the handlebar to a height you can reach with a slight elbow bend",
                "Tighten pedal straps or clip in; choose manual or interval mode",
            ],
            position: [
                Checkpoint(.shoulders, "Relaxed, away from the ears"),
                Checkpoint(.hands, "Light grip on the bars, not holding body weight"),
                Checkpoint(.hips, "Level and still on the seat; no rocking"),
                Checkpoint(.knees, "Track in line with the feet throughout the stroke"),
                Checkpoint(.feet, "Balls of the feet over the pedals, cadence 85–95 rpm"),
            ],
            mistakes: [
                "Seat too low or too high, with hips rocking",
                "Pushing big resistance at low cadence for easy rides",
                "Hunching and leaning heavily on the bars",
            ],
            breathing: "Steady, deep breathing through nose and mouth, matched to the effort"
        ),
        "treadmill-run": Technique(
            setup: [
                "Clip the safety key to your clothing before starting",
                "Set the incline to 1% to mimic outdoor running",
                "Start at walking pace and build speed over the first minute",
            ],
            position: [
                Checkpoint(.head, "Eyes forward on the horizon, not down at the belt"),
                Checkpoint(.shoulders, "Relaxed and down"),
                Checkpoint(.elbows, "Bent about 90 degrees, swinging forward and back"),
                Checkpoint(.hips, "Tall, slight forward lean from the ankles"),
                Checkpoint(.feet, "Land under the hips with quick, light steps"),
            ],
            mistakes: [
                "Over-striding and landing heel-first out in front",
                "Holding the rails",
                "Running too close to the front or back of the belt",
            ],
            breathing: "Relaxed, rhythmic breathing; easy runs should allow talking"
        ),
        "incline-walk": Technique(
            setup: [
                "Clip the safety key to your clothing before starting",
                "Set the incline to 10–12% and speed to 4.5–6 km/h",
                "Walk without holding the rails, mimicking an approach hike",
            ],
            position: [
                Checkpoint(.head, "Eyes forward, chin neutral"),
                Checkpoint(.shoulders, "Relaxed, arms swinging naturally"),
                Checkpoint(.hips, "Slight forward lean from the ankles, hips under you"),
                Checkpoint(.knees, "Soft and straightening as you push through each step"),
                Checkpoint(.feet, "Whole foot lands, push off through the heel and mid-foot"),
            ],
            mistakes: [
                "Holding the rails, which removes most of the work",
                "Leaning far forward from the waist",
                "Setting the speed so high you must hang on",
            ],
            breathing: "Steady nasal or relaxed mouth breathing; you should be able to talk"
        ),
        "stair-climber": Technique(
            setup: [
                "Step on while the stairs are stopped, holding the rails",
                "Choose a slow level to start, then let go of the rails once settled",
            ],
            position: [
                Checkpoint(.head, "Eyes forward, not down at the steps"),
                Checkpoint(.shoulders, "Stacked over the hips, relaxed"),
                Checkpoint(.hands, "Off the rails; touch lightly only for balance"),
                Checkpoint(.hips, "Tall; drive up through the glute of the stepping leg"),
                Checkpoint(.feet, "Whole foot on each step, not just the toes"),
            ],
            mistakes: [
                "Leaning on the rails and hunching over",
                "Taking tiny steps on the toes",
                "Choosing a speed too fast to stand tall",
            ],
            breathing: "Steady rhythmic breathing matched to your step pace"
        ),
        "elliptical": Technique(
            setup: [
                "Step on with the pedals at their lowest point, holding the static grips",
                "Choose a resistance and incline that let you keep 60+ strides per minute",
                "Move your hands to the moving handles once you are moving",
            ],
            position: [
                Checkpoint(.head, "Eyes forward, chin neutral"),
                Checkpoint(.shoulders, "Relaxed, stacked over the hips"),
                Checkpoint(.hands, "Push and pull the handles to use the upper body"),
                Checkpoint(.knees, "Track over the toes, never locked"),
                Checkpoint(.feet, "Flat on the pedals, pushing through the heels"),
            ],
            mistakes: [
                "Leaning on the handles and slouching",
                "Riding up on the toes",
                "Resistance so low the pedals freewheel",
            ],
            breathing: "Steady, relaxed breathing matched to the stride"
        ),

        // MARK: - Warm-up drills

        "worlds-greatest": Technique(
            setup: [
                "Start in a high plank on a mat",
                "Step the right foot outside the right hand into a long lunge",
            ],
            position: [
                Checkpoint(.head, "Follows the top hand as you rotate"),
                Checkpoint(.shoulders, "Stack top shoulder over bottom as you open up"),
                Checkpoint(.elbows, "Inside elbow drops toward the front instep before rotating"),
                Checkpoint(.hips, "Low and square; sink the back hip toward the floor"),
                Checkpoint(.knees, "Back knee straight and lifted; front knee over the ankle"),
            ],
            mistakes: [
                "Rushing through the positions",
                "Rotating from the low back instead of the mid back",
                "Letting the back knee collapse to the floor",
            ],
            breathing: "Exhale as you rotate up; breathe slowly in each position"
        ),
        "leg-swings": Technique(
            setup: [
                "Stand side-on to a wall or rack and hold it for balance",
                "Stand tall on one leg, slight bend in the standing knee",
            ],
            position: [
                Checkpoint(.shoulders, "Level and still, not twisting with the swing"),
                Checkpoint(.core, "Lightly braced so the torso stays upright"),
                Checkpoint(.hips, "Square; the swing comes from the hip joint"),
                Checkpoint(.knees, "Swinging leg relaxed and nearly straight"),
                Checkpoint(.feet, "Standing foot flat and stable"),
            ],
            mistakes: [
                "Swinging hard and full range from the first rep",
                "Leaning back or rounding to fake range",
            ],
            breathing: "Relaxed, natural breathing in rhythm with the swing"
        ),
        "hip-90-90": Technique(
            setup: [
                "Sit on a mat with both knees bent to 90 degrees",
                "Front leg out to the side, back leg behind you, feet roughly in line",
            ],
            position: [
                Checkpoint(.head, "Tall, crown reaching to the ceiling"),
                Checkpoint(.hands, "Off the floor if you can; lightly behind you if not"),
                Checkpoint(.back, "Long and upright throughout the switch"),
                Checkpoint(.hips, "Rotate both knees over to the other side together"),
                Checkpoint(.knees, "Return to 90 degrees each side, knees down"),
            ],
            mistakes: [
                "Slumping and rounding the back",
                "Using the hands to push yourself around",
                "Forcing the knee down with pain",
            ],
            breathing: "Exhale as you switch sides; breathe slowly at each end"
        ),
        "inchworm": Technique(
            setup: [
                "Stand tall with feet hip-width apart",
                "Hinge and place your hands on the floor in front of your feet",
            ],
            position: [
                Checkpoint(.head, "Neutral, in line with the spine"),
                Checkpoint(.shoulders, "Stacked over the hands in the plank"),
                Checkpoint(.hands, "Walk out in small steps to a full plank, then walk back"),
                Checkpoint(.core, "Braced in the plank; no sagging hips"),
                Checkpoint(.knees, "As straight as you comfortably can; bend them if needed"),
            ],
            mistakes: [
                "Hips sagging in the plank",
                "Rushing and walking out too far",
            ],
            breathing: "Exhale as you hinge down, steady breathing as you walk"
        ),
        "band-dislocates": Technique(
            setup: [
                "Use a light band; hold it with a wide overhand grip",
                "Stand tall, band in front of your hips, arms straight",
            ],
            position: [
                Checkpoint(.shoulders, "Down, not shrugged, as the band passes overhead"),
                Checkpoint(.elbows, "Straight throughout the circle"),
                Checkpoint(.hands, "Wide enough to pass overhead without pain; narrow over time"),
                Checkpoint(.core, "Braced; ribs down, no arching to get the band past"),
            ],
            mistakes: [
                "Gripping too narrow and bending the elbows",
                "Arching the low back to get the band behind",
                "Moving fast and jerky",
            ],
            breathing: "Inhale as the band goes overhead, exhale as it comes down"
        ),
        "cat-cow": Technique(
            setup: [
                "Get on all fours on a mat",
                "Hands under shoulders, knees under hips",
            ],
            position: [
                Checkpoint(.head, "Moves with the spine: look up in cow, tuck in cat"),
                Checkpoint(.shoulders, "Push the floor away in cat, relax in cow"),
                Checkpoint(.back, "Move one segment at a time from tailbone to neck"),
                Checkpoint(.hips, "Tilt the pelvis to start each movement"),
            ],
            mistakes: [
                "Moving only the neck or low back",
                "Rushing without full, controlled range",
            ],
            breathing: "Inhale into cow, exhale into cat"
        ),
        "glute-bridge": Technique(
            setup: [
                "Lie on your back on a mat, knees bent, feet flat, hip-width apart",
                "Heels about a hand's length from your glutes, arms by your sides",
            ],
            position: [
                Checkpoint(.head, "Resting on the mat, chin slightly tucked"),
                Checkpoint(.core, "Ribs down; no arching the lower back"),
                Checkpoint(.hips, "Drive up until shoulders, hips and knees line up; squeeze 2 s"),
                Checkpoint(.knees, "Pointing forward, in line with the feet"),
                Checkpoint(.feet, "Flat, pushing through the heels"),
            ],
            mistakes: [
                "Arching the lower back at the top",
                "Pushing through the toes",
                "Knees caving in",
            ],
            breathing: "Exhale on the way up, inhale on the way down"
        ),
        "scap-push-up": Technique(
            setup: [
                "Start in a high plank; drop to the knees if needed",
                "Hands under the shoulders, fingers spread",
            ],
            position: [
                Checkpoint(.head, "Neutral, eyes just ahead of the hands"),
                Checkpoint(.shoulders, "Pinch the blades together, then push them apart"),
                Checkpoint(.elbows, "Locked straight throughout"),
                Checkpoint(.core, "Braced; body in a straight line"),
            ],
            mistakes: [
                "Bending the elbows into a mini push-up",
                "Letting the hips sag",
            ],
            breathing: "Inhale as the blades come together, exhale as you push away"
        ),
        "squat-to-stand": Technique(
            setup: [
                "Stand with feet shoulder-width apart, toes slightly out",
                "Hinge and grab under your toes with both hands",
            ],
            position: [
                Checkpoint(.head, "Lifts with the chest as you sink into the squat"),
                Checkpoint(.elbows, "Push the knees outward from the inside"),
                Checkpoint(.back, "Lift the chest to a long spine at the bottom"),
                Checkpoint(.hips, "Drop low between the heels, then lift up to straighten the legs"),
                Checkpoint(.feet, "Flat, heels down throughout"),
            ],
            mistakes: [
                "Heels lifting at the bottom",
                "Letting go of the toes",
                "Bouncing into the end range",
            ],
            breathing: "Inhale as you lift the chest, exhale as you straighten the legs"
        ),
        "arm-circles": Technique(
            setup: [
                "Stand tall with feet hip-width apart",
                "Arms out to the sides at shoulder height",
            ],
            position: [
                Checkpoint(.shoulders, "Relaxed; let them move freely without shrugging"),
                Checkpoint(.elbows, "Straight but not locked"),
                Checkpoint(.hands, "Start with small circles, grow them to full swings"),
                Checkpoint(.core, "Braced so the torso stays still"),
            ],
            mistakes: [
                "Starting with big, fast swings",
                "Arching the back to get the arms further",
            ],
            breathing: "Relaxed, natural breathing throughout"
        ),
        "lunge-twist": Technique(
            setup: [
                "Clear a lane of about 10 m",
                "Stand tall with arms out in front at chest height or hands together",
            ],
            position: [
                Checkpoint(.shoulders, "Rotate toward the front leg side"),
                Checkpoint(.back, "Tall; rotate through the mid back"),
                Checkpoint(.hips, "Square to the front while the torso turns"),
                Checkpoint(.knees, "Front knee over the ankle; back knee lowers toward the floor"),
                Checkpoint(.feet, "Hip-width tracks, not on one line"),
            ],
            mistakes: [
                "Front knee collapsing inward during the twist",
                "Rotating the hips instead of the torso",
                "Stepping too short so the knee shoots forward",
            ],
            breathing: "Exhale as you twist, inhale as you return and step"
        ),
        "wrist-prep": Technique(
            setup: [
                "Kneel on a mat or stand with hands free",
                "Start gently; work only in a comfortable range",
            ],
            position: [
                Checkpoint(.shoulders, "Stacked over the hands when weight bearing on all fours"),
                Checkpoint(.elbows, "Straight but soft for wrist rocks"),
                Checkpoint(.hands, "Do circles, palms-down and palms-up rocks, then finger flicks"),
            ],
            mistakes: [
                "Loading full body weight right away",
                "Pushing into painful positions",
            ],
            breathing: "Slow, relaxed breathing throughout"
        ),
    ]
}
