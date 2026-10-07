// Technique content: setup, body position, mistakes, breathing.

extension Technique {
    static let mobilityStretch: [String: Technique] = [
        // MARK: - Active mobility

        "frog-rockback": Technique(
            setup: [
                "Kneel on a mat on all fours, then slide the knees out wide",
                "Turn the feet out so the inner edges of the feet touch the mat",
                "Hands under the shoulders, knees in line with the hips",
            ],
            position: [
                Checkpoint(.back, "Spine long and neutral – no rounding as the hips move back"),
                Checkpoint(.hands, "Hands stay planted; arms guide the rock but take little weight"),
                Checkpoint(.hips, "Rock the hips back toward the heels, then return to the start"),
                Checkpoint(.knees, "Knees stay wide and still; stretch on the inner thighs 5–6/10"),
                Checkpoint(.feet, "Ankles in line with the knees, inner edges of the feet down"),
            ],
            mistakes: [
                "Rounding the lower back to fake extra depth",
                "Bouncing at the end range instead of moving slowly",
                "Setting the knees wider than the hips can tolerate",
            ],
            breathing: "Exhale as you rock back, inhale as you come forward"
        ),
        "deep-squat-pry": Technique(
            setup: [
                "Stand with feet slightly wider than the hips, toes turned out 15–30°",
                "Sit down into the deepest squat you can hold with heels down",
                "Bring the palms together and place the elbows inside the knees",
            ],
            position: [
                Checkpoint(.back, "Chest tall, spine as long as possible – avoid slumping"),
                Checkpoint(.elbows, "Elbows press the knees out gently to open the hips"),
                Checkpoint(.hips, "Shift slowly side to side, sinking into each hip"),
                Checkpoint(.knees, "Knees track over the toes, never collapsing inward"),
                Checkpoint(.feet, "Whole foot down, heels stay on the floor"),
            ],
            mistakes: [
                "Letting the heels lift off the floor",
                "Collapsing the chest onto the thighs",
                "Prying the knees so hard the inner knee aches",
            ],
            breathing: "Long slow breaths; let each exhale soften the hips a little deeper"
        ),
        "bw-cossack": Technique(
            setup: [
                "Stand in a wide stance, feet about twice shoulder width",
                "Toes slightly out; hands together in front of the chest for balance",
            ],
            position: [
                Checkpoint(.back, "Chest up, spine long as you shift sideways"),
                Checkpoint(.hips, "Sit back and down into one hip, the other leg goes straight"),
                Checkpoint(.knees, "Bent knee tracks over the toes; straight leg relaxed"),
                Checkpoint(.feet, "Heel of the bent leg stays down; straight leg toes can point up"),
            ],
            mistakes: [
                "Rushing the shift and bouncing at the bottom",
                "Letting the working heel lift off the floor",
                "Caving the bent knee inward",
            ],
            breathing: "Inhale at the top, exhale as you sink into the side"
        ),
        "pancake-gm": Technique(
            setup: [
                "Sit on a mat with legs in a wide straddle, as wide as is comfortable",
                "Sit tall, on a folded mat if the lower back rounds",
                "Hands on the floor in front or arms reaching forward",
            ],
            position: [
                Checkpoint(.back, "Keep a flat back; hinge from the hips, not the spine"),
                Checkpoint(.hands, "Reach actively forward to pull the torso down"),
                Checkpoint(.hips, "Tip the pelvis forward; stretch on hamstrings and adductors 5–6/10"),
                Checkpoint(.knees, "Kneecaps point to the ceiling, legs straight but not locked"),
                Checkpoint(.feet, "Toes pulled up, heels heavy on the floor"),
            ],
            mistakes: [
                "Rounding the upper back to get the head lower",
                "Letting the knees roll inward",
                "Bouncing down instead of a controlled hinge",
            ],
            breathing: "Exhale as you hinge forward, inhale as you sit back up tall"
        ),
        "hip-flexor-lift": Technique(
            setup: [
                "Sit on a mat with legs straight out in front",
                "Hands on the floor beside the hips or slightly behind",
            ],
            position: [
                Checkpoint(.back, "Sit tall, chest up – don't lean back to help the lift"),
                Checkpoint(.hips, "Lift one straight leg a few cm using the front of the hip"),
                Checkpoint(.knees, "Knee stays fully straight through the lift"),
                Checkpoint(.feet, "Toes pulled up; pause 1–2 s at the top, lower slowly"),
            ],
            mistakes: [
                "Leaning back to swing the leg up",
                "Bending the knee to get more height",
                "Dropping the leg instead of lowering it",
            ],
            breathing: "Exhale as you lift, inhale as you lower"
        ),
        "hip-car": Technique(
            setup: [
                "Stand tall beside a rack or wall and hold it lightly with one hand",
                "Shift weight onto the standing leg and brace gently",
            ],
            position: [
                Checkpoint(.core, "Brace lightly; keep the ribs and torso still"),
                Checkpoint(.hips, "Pelvis stays level and still – only the thigh moves"),
                Checkpoint(.knees, "Lift knee up, open it out to the side, then rotate it back down"),
                Checkpoint(.feet, "Standing foot rooted, knee soft"),
            ],
            mistakes: [
                "Twisting the pelvis or leaning to make the circle bigger",
                "Moving fast with momentum",
                "Pushing into a pinch at the front of the hip",
            ],
            breathing: "Slow steady breathing through the whole circle; never hold your breath"
        ),
        "wall-slide": Technique(
            setup: [
                "Stand with your back to a wall, feet about 20–30 cm away",
                "Press head, upper back and lower back lightly against the wall",
                "Arms in a goalpost: elbows bent 90°, forearms and backs of hands on the wall",
            ],
            position: [
                Checkpoint(.head, "Head stays in contact with the wall, chin tucked"),
                Checkpoint(.shoulders, "Slide arms up as high as possible without shrugging"),
                Checkpoint(.elbows, "Elbows and forearms stay touching the wall"),
                Checkpoint(.core, "Low back stays on the wall – ribs down"),
                Checkpoint(.knees, "Knees slightly bent to help flatten the lower back"),
            ],
            mistakes: [
                "Arching the lower back off the wall to reach higher",
                "Letting the forearms peel off the wall",
                "Shrugging the shoulders to the ears",
            ],
            breathing: "Exhale as the arms slide up, inhale as they come down"
        ),
        "shoulder-car": Technique(
            setup: [
                "Stand tall with feet hip-width, one arm by your side",
                "Make a tight fist and brace the abs lightly",
            ],
            position: [
                Checkpoint(.shoulders, "Draw the biggest painless circle: forward, up, back, down"),
                Checkpoint(.elbows, "Arm stays straight; turn the palm out as the arm goes overhead"),
                Checkpoint(.hands, "Fist tight throughout to keep tension in the arm"),
                Checkpoint(.core, "Ribs down, torso still – no leaning or twisting"),
            ],
            mistakes: [
                "Arching the back or rotating the trunk to fake range",
                "Moving fast and swinging the arm",
                "Pushing through a pinch at the top or back of the shoulder",
            ],
            breathing: "Slow steady breathing; one circle should take 8–10 seconds"
        ),
        "open-book": Technique(
            setup: [
                "Lie on your side on a mat, hips and knees bent to 90°",
                "Head on a folded mat or pad, arms straight out in front, palms together",
            ],
            position: [
                Checkpoint(.head, "Eyes follow the top hand as it opens"),
                Checkpoint(.shoulders, "Open the top arm in an arc to the other side; mild chest stretch"),
                Checkpoint(.back, "Rotate through the upper back, not the lower back"),
                Checkpoint(.knees, "Knees stay stacked and on the floor"),
            ],
            mistakes: [
                "Letting the top knee lift and roll back",
                "Forcing the hand to the floor",
                "Rushing the arc instead of pausing at the end",
            ],
            breathing: "Exhale as you open, inhale as you close the book"
        ),
        "thread-needle": Technique(
            setup: [
                "Kneel on a mat on all fours, hands under shoulders, knees under hips",
                "Lift one hand off the floor to start the rotation",
            ],
            position: [
                Checkpoint(.head, "Eyes follow the moving hand"),
                Checkpoint(.shoulders, "Reach under the support arm, then open up toward the ceiling"),
                Checkpoint(.back, "Rotation comes from the upper back; mild stretch only"),
                Checkpoint(.hands, "Supporting hand pushes the floor away"),
                Checkpoint(.hips, "Hips stay square over the knees"),
            ],
            mistakes: [
                "Shifting the hips sideways instead of rotating the spine",
                "Sinking into the supporting shoulder",
                "Moving too fast through the range",
            ],
            breathing: "Exhale as you thread under, inhale as you open to the ceiling"
        ),
        "t-spine-roller": Technique(
            setup: [
                "Sit on the floor with a foam roller across the mid back, under the shoulder blades",
                "Feet flat, knees bent, hands behind the head supporting the neck",
                "Lift the hips slightly to position the roller, then lower them",
            ],
            position: [
                Checkpoint(.head, "Hands cradle the head; neck relaxed, no pulling"),
                Checkpoint(.elbows, "Elbows point forward and slightly in"),
                Checkpoint(.back, "Extend back over the roller; move it one segment at a time"),
                Checkpoint(.core, "Ribs stay down; keep the roller above the lower back"),
                Checkpoint(.feet, "Feet flat on the floor, hip-width"),
            ],
            mistakes: [
                "Rolling down onto the lower back",
                "Yanking the head with the hands",
                "Flaring the ribs instead of bending the upper back",
            ],
            breathing: "Exhale as you extend over the roller, inhale as you come back up"
        ),
        "wrist-car": Technique(
            setup: [
                "Stand or sit tall with one forearm held still by the other hand",
                "Make a loose fist with the working hand",
            ],
            position: [
                Checkpoint(.elbows, "Forearm stays still – only the wrist moves"),
                Checkpoint(.hands, "Draw slow, full circles in both directions"),
                Checkpoint(.hands, "Then open the fingers wide and gently extend each one"),
            ],
            mistakes: [
                "Moving the elbow and forearm along with the wrist",
                "Rushing quick circles instead of slow controlled ones",
                "Forcing the fingers into a sharp stretch after hard crimping",
            ],
            breathing: "Relaxed breathing throughout; keep the shoulders loose"
        ),
        "knee-to-wall": Technique(
            setup: [
                "Face a wall in a half-kneel or split stance, front foot a few cm from the wall",
                "Hands on the wall for balance",
                "Move the foot back each round until the knee only just touches",
            ],
            position: [
                Checkpoint(.hips, "Hips square to the wall"),
                Checkpoint(.knees, "Drive the knee forward over the middle toes to touch the wall"),
                Checkpoint(.feet, "Heel stays down the whole time; arch doesn't collapse"),
            ],
            mistakes: [
                "Letting the heel lift as the knee goes forward",
                "Caving the knee inward over the big toe",
                "Bouncing into the end range",
            ],
            breathing: "Exhale as the knee drives forward, inhale as you come back"
        ),
        "jefferson-curl": Technique(
            setup: [
                "Stand on a plyo box with feet hip-width, toes near the edge",
                "Hold a very light dumbbell (2–6 kg) with both hands, arms hanging",
                "Learn it with bodyweight first; only add load once it feels easy",
            ],
            position: [
                Checkpoint(.head, "Tuck the chin first and start rolling down from the neck"),
                Checkpoint(.back, "Roll down one vertebra at a time, then reverse from the bottom"),
                Checkpoint(.hands, "Weight hangs straight down close to the legs"),
                Checkpoint(.knees, "Knees straight but soft, not locked"),
                Checkpoint(.feet, "Weight balanced over the mid-foot; stop at a mild stretch"),
            ],
            mistakes: [
                "Using a heavy weight – this is a mobility drill, not a lift",
                "Hinging at the hips instead of curling through the spine",
                "Going fast or bouncing at the bottom",
            ],
            breathing: "Exhale slowly on the way down, inhale as you roll back up"
        ),

        // MARK: - Static stretches

        "pec-stretch": Technique(
            setup: [
                "Stand beside a rack upright or doorframe",
                "Place the forearm on it with the elbow at shoulder height",
                "Step the same-side foot forward through the gap",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulder down and back, away from the ear"),
                Checkpoint(.elbows, "Elbow at shoulder height or slightly below, bent about 90°"),
                Checkpoint(.back, "Turn the chest gently away; mild stretch across the chest 5–6/10"),
                Checkpoint(.feet, "Step through slowly; stop before any pinch at the front shoulder"),
            ],
            mistakes: [
                "Placing the elbow above shoulder height",
                "Letting the shoulder roll forward",
                "Stepping through too far and straining the joint",
            ],
            breathing: "Slow breaths; ease a little further on each exhale"
        ),
        "lat-stretch": Technique(
            setup: [
                "Kneel on a mat facing a flat bench",
                "Place both elbows on the bench, palms together, hands behind the head",
                "Walk the knees back until the hips are over the knees",
            ],
            position: [
                Checkpoint(.head, "Head sinks between the arms"),
                Checkpoint(.elbows, "Elbows stay on the bench about shoulder-width apart"),
                Checkpoint(.back, "Sink the chest toward the floor; stretch along the sides 5–6/10"),
                Checkpoint(.hips, "Hips stay over the knees, pushed back slightly"),
            ],
            mistakes: [
                "Over-arching the lower back instead of opening the shoulders",
                "Flaring the elbows wide apart",
                "Forcing the chest down into a shoulder pinch",
            ],
            breathing: "Long exhales let the chest sink a little lower each time"
        ),
        "childs-pose-reach": Technique(
            setup: [
                "Kneel on a mat, big toes touching, knees hip-width or wider",
                "Sit the hips back toward the heels and reach the arms forward",
                "Walk both hands to one side to stretch the opposite side",
            ],
            position: [
                Checkpoint(.head, "Forehead rests on the mat, neck relaxed"),
                Checkpoint(.shoulders, "Arms long, shoulders away from the ears"),
                Checkpoint(.hands, "Press lightly through the fingertips to lengthen the side"),
                Checkpoint(.hips, "Hips stay heavy toward the heels"),
            ],
            mistakes: [
                "Letting the hips lift off the heels as you reach",
                "Shrugging the shoulders up",
                "Only stretching one side",
            ],
            breathing: "Breathe into the stretched side ribs; let them expand on each inhale"
        ),
        "cross-body": Technique(
            setup: [
                "Stand or sit tall",
                "Bring one straight arm across the chest at shoulder height",
                "Hold it above the elbow with the other hand",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulder blade stays down and back – don't shrug"),
                Checkpoint(.elbows, "Pull at the elbow, not the wrist; arm relaxed"),
                Checkpoint(.back, "Torso stays square – no twisting; mild stretch at the rear shoulder"),
            ],
            mistakes: [
                "Rotating the torso to follow the arm",
                "Pulling on the wrist or the elbow joint",
                "Hiking the shoulder up to the ear",
            ],
            breathing: "Slow nasal breaths; relax the shoulder on each exhale"
        ),
        "sleeper-stretch": Technique(
            setup: [
                "Lie on your side on a mat, head on a pad",
                "Bottom arm out in front at shoulder height, elbow bent 90°",
                "Roll back slightly (about 20–30°) to take pressure off the shoulder",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulder blade set back, not jammed under you"),
                Checkpoint(.elbows, "Elbow stays at shoulder height, bent 90°"),
                Checkpoint(.hands, "Top hand gently pushes the forearm toward the floor"),
                Checkpoint(.hips, "Hips stacked, knees bent for stability"),
            ],
            mistakes: [
                "Forcing the forearm down – keep it very gentle",
                "Pushing through any pinch at the front of the shoulder",
                "Lying fully on the shoulder instead of slightly rolled back",
            ],
            breathing: "Calm breaths; stop and back off if you feel pinching or pain"
        ),
        "triceps-stretch": Technique(
            setup: [
                "Stand or sit tall",
                "Raise one arm overhead and bend the elbow so the hand drops behind the head",
                "Hold the elbow with the other hand",
            ],
            position: [
                Checkpoint(.head, "Head stays upright, pushed slightly back into the arm"),
                Checkpoint(.elbows, "Elbow points up to the ceiling; gently guide it back"),
                Checkpoint(.hands, "Fingers reach down between the shoulder blades"),
                Checkpoint(.core, "Ribs down – avoid arching the lower back"),
            ],
            mistakes: [
                "Arching the back to make it feel easier",
                "Pulling the head forward with the arm",
                "Yanking on the elbow",
            ],
            breathing: "Slow breaths; ease the elbow back on each exhale"
        ),
        "biceps-wall": Technique(
            setup: [
                "Stand side-on to a wall or rack upright",
                "Place the palm on the wall behind you at shoulder height, thumb down",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulder down and back, not rolling forward"),
                Checkpoint(.elbows, "Arm straight but not locked hard"),
                Checkpoint(.hands, "Thumb points down, whole palm on the wall"),
                Checkpoint(.feet, "Slowly turn the feet and body away until a mild stretch 5–6/10"),
            ],
            mistakes: [
                "Letting the front of the shoulder roll forward",
                "Turning away too far and straining the shoulder",
                "Hyperextending the elbow",
            ],
            breathing: "Slow breaths; turn away a touch more on each exhale"
        ),
        "forearm-flexor": Technique(
            setup: [
                "Stand or kneel; hold one arm straight in front, palm facing up or out",
                "Use the other hand to pull the fingers back gently",
                "Or kneel and place both palms on the floor, fingers pointing to the knees",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulder relaxed and down"),
                Checkpoint(.elbows, "Elbow straight to stretch the full length of the forearm"),
                Checkpoint(.hands, "Pull back from the palm and fingers; mild stretch, never sharp"),
            ],
            mistakes: [
                "Bending the elbow and losing the stretch",
                "Pulling the fingers hard after a crimping session",
                "Holding for too short a time to relax",
            ],
            breathing: "Long slow exhales to relax the forearm after climbing"
        ),
        "forearm-extensor": Technique(
            setup: [
                "Hold one arm straight in front, palm facing down",
                "Make a soft fist or point the fingers down",
                "Use the other hand to gently press the back of the hand toward you",
            ],
            position: [
                Checkpoint(.shoulders, "Shoulder relaxed, not shrugged"),
                Checkpoint(.elbows, "Elbow straight to load the top of the forearm"),
                Checkpoint(.hands, "Wrist flexed down; mild stretch on top of the forearm 5–6/10"),
            ],
            mistakes: [
                "Bending the elbow",
                "Pressing hard into the wrist joint",
                "Lifting the shoulder toward the ear",
            ],
            breathing: "Slow nasal breaths; soften the grip on each exhale"
        ),
        "couch-stretch": Technique(
            setup: [
                "Put a mat against a bench; kneel with one knee on the mat, shin up the bench",
                "Step the other foot forward into a lunge, hands on the front knee",
            ],
            position: [
                Checkpoint(.back, "Torso upright, ribs down – no arching the lower back"),
                Checkpoint(.hips, "Squeeze the glute of the back leg and tuck the pelvis"),
                Checkpoint(.knees, "Front knee stacked over the ankle"),
            ],
            mistakes: [
                "Arching the lower back instead of stretching the hip",
                "Forcing range until the knee is painful",
            ],
            breathing: "Slow nasal breaths; on each exhale sink a little deeper into the hip"
        ),
        "half-kneeling-hf": Technique(
            setup: [
                "Kneel on a mat with one knee down and the other foot flat in front",
                "Both knees bent about 90°, back knee under the hip",
            ],
            position: [
                Checkpoint(.shoulders, "Reach the arm on the kneeling side up and slightly over"),
                Checkpoint(.core, "Ribs down, abs lightly braced"),
                Checkpoint(.hips, "Tuck the pelvis and squeeze the back glute; shift forward a little"),
                Checkpoint(.knees, "Front knee over the ankle; padded back knee"),
            ],
            mistakes: [
                "Leaning far forward and arching the back",
                "Losing the pelvic tuck",
                "Kneeling directly on a hard floor",
            ],
            breathing: "Slow breaths; squeeze the glute a little harder on each exhale"
        ),
        "hamstring-stretch": Technique(
            setup: [
                "Lie on your back on a mat",
                "Loop a band around the ball of one foot and hold the ends",
                "Raise the leg toward the ceiling, other leg straight on the floor",
            ],
            position: [
                Checkpoint(.head, "Head and shoulders relaxed on the mat"),
                Checkpoint(.hands, "Pull the band gently; arms do the work, not the neck"),
                Checkpoint(.hips, "Both hips stay on the floor, pelvis level"),
                Checkpoint(.knees, "Raised leg straight; stop at a mild stretch 5–6/10"),
                Checkpoint(.feet, "Pull the toes toward you to include the calf"),
            ],
            mistakes: [
                "Bending the knee to pull the leg closer",
                "Lifting the hips or bottom leg off the floor",
                "Yanking on the band",
            ],
            breathing: "Long exhales; let the leg drift closer on each one"
        ),
        "pigeon": Technique(
            setup: [
                "Start on all fours on a mat",
                "Bring one knee forward behind the wrist, shin angled across the mat",
                "Slide the other leg straight back",
            ],
            position: [
                Checkpoint(.back, "Long spine; fold forward over the front leg if comfortable"),
                Checkpoint(.hands, "Hands or forearms take weight to control intensity"),
                Checkpoint(.hips, "Square the hips forward; stretch in the outer hip 5–6/10"),
                Checkpoint(.knees, "No pain in the front knee – bring the heel closer to you if so"),
                Checkpoint(.feet, "Back leg straight, top of the foot on the mat"),
            ],
            mistakes: [
                "Letting the hips tip onto one side",
                "Forcing the front shin parallel and twisting the knee",
                "Holding the breath and tensing up",
            ],
            breathing: "Slow nasal breaths; relax the hip a little more on each exhale"
        ),
        "figure-4": Technique(
            setup: [
                "Lie on your back on a mat, knees bent, feet flat",
                "Cross one ankle over the opposite knee",
                "Thread your hands behind the bottom thigh",
            ],
            position: [
                Checkpoint(.head, "Head stays down on the mat, neck relaxed"),
                Checkpoint(.hands, "Pull the bottom thigh gently toward the chest"),
                Checkpoint(.hips, "Low back flat; stretch felt in the glute of the crossed leg"),
                Checkpoint(.knees, "Top knee opens out gently; no pressure on the knee"),
                Checkpoint(.feet, "Flex the top foot to protect the knee"),
            ],
            mistakes: [
                "Lifting the head and shoulders off the mat",
                "Letting the top foot relax and sickle",
                "Pulling too hard into the knee",
            ],
            breathing: "Calm, deep breaths; ease the thigh closer on each exhale"
        ),
        "butterfly": Technique(
            setup: [
                "Sit on a mat, soles of the feet together, knees out to the sides",
                "Hold the ankles or feet; sit on a folded mat if the back rounds",
            ],
            position: [
                Checkpoint(.back, "Tall spine; hinge forward slightly from the hips if you want more"),
                Checkpoint(.elbows, "Elbows can rest on the thighs to add gentle pressure"),
                Checkpoint(.hips, "Pelvis upright, sitting on the sit bones"),
                Checkpoint(.knees, "Let the knees drop toward the floor; mild inner-thigh stretch"),
                Checkpoint(.feet, "Heels a comfortable distance from the groin"),
            ],
            mistakes: [
                "Rounding the back to bring the head down",
                "Pushing the knees down hard",
                "Bouncing the knees",
            ],
            breathing: "Slow breaths; let the knees fall a little lower on each exhale"
        ),
        "frog-stretch": Technique(
            setup: [
                "Kneel on a mat on forearms, then slide the knees out wide",
                "Turn the shins so they run parallel, inner edges of the feet down",
                "Pad the knees with a folded mat if needed",
            ],
            position: [
                Checkpoint(.elbows, "Forearms on the mat, elbows under the shoulders"),
                Checkpoint(.back, "Spine neutral – avoid sagging the lower back"),
                Checkpoint(.hips, "Ease the hips back slowly; inner-thigh stretch 5–6/10"),
                Checkpoint(.knees, "Knees in line with the hips; no pain at the inner knee"),
                Checkpoint(.feet, "Ankles directly behind the knees, shins parallel"),
            ],
            mistakes: [
                "Sliding the knees too wide too soon",
                "Letting the lower back sag",
                "Holding through pain at the inner knee",
            ],
            breathing: "Long exhales to relax the inner thighs – great for drop-knees"
        ),
        "calf-wall": Technique(
            setup: [
                "Face a wall, hands on it at shoulder height",
                "Step one foot back, heel down, front knee bent",
            ],
            position: [
                Checkpoint(.hips, "Hips square to the wall, lean in from the ankle"),
                Checkpoint(.knees, "Back knee straight first, then bend it slightly to reach lower"),
                Checkpoint(.feet, "Back heel on the floor, toes pointing straight at the wall"),
            ],
            mistakes: [
                "Letting the back heel lift",
                "Turning the back foot out",
                "Only doing the straight-knee version",
            ],
            breathing: "Steady slow breaths; lean in a little further on each exhale"
        ),
        "supine-twist": Technique(
            setup: [
                "Lie on your back on a mat, arms out in a T",
                "Bring one knee up toward the chest",
                "Let it fall across the body to the opposite side",
            ],
            position: [
                Checkpoint(.head, "Turn the head away from the knee if comfortable"),
                Checkpoint(.shoulders, "Both shoulders stay flat on the mat"),
                Checkpoint(.back, "Gentle twist through the spine; mild stretch only"),
                Checkpoint(.knees, "Top knee rests on the floor or on a pad"),
            ],
            mistakes: [
                "Lifting the opposite shoulder off the floor",
                "Pushing the knee down with force",
                "Twisting fast instead of easing into it",
            ],
            breathing: "Deep belly breaths; let the twist settle on each exhale"
        ),
        "sphinx": Technique(
            setup: [
                "Lie face down on a mat",
                "Place the forearms on the floor, elbows under the shoulders",
                "For cobra, place hands under the shoulders and press up gently",
            ],
            position: [
                Checkpoint(.head, "Long neck; look slightly forward and down"),
                Checkpoint(.shoulders, "Shoulders down and away from the ears"),
                Checkpoint(.back, "Gentle extension spread along the spine; no pinch in the low back"),
                Checkpoint(.hips, "Hips stay on the mat, glutes relaxed"),
            ],
            mistakes: [
                "Crunching the neck back",
                "Squeezing the glutes hard",
                "Pressing up higher than the low back allows",
            ],
            breathing: "Slow breaths into the belly against the mat"
        ),
        "side-bend": Technique(
            setup: [
                "Stand tall with feet hip-width",
                "Reach one arm overhead, other hand on the hip or thigh",
            ],
            position: [
                Checkpoint(.head, "Head in line with the spine, not dropped"),
                Checkpoint(.shoulders, "Reach up first, then over to the side"),
                Checkpoint(.back, "Bend sideways only – no twisting or leaning forward"),
                Checkpoint(.hips, "Hips stay centred; shift them slightly to the reaching side"),
                Checkpoint(.feet, "Both feet planted evenly"),
            ],
            mistakes: [
                "Rotating the chest toward the floor",
                "Collapsing sideways instead of reaching long",
                "Locking the knees",
            ],
            breathing: "Breathe into the stretched side ribs and reach further on each exhale"
        ),
        "behind-back-clasp": Technique(
            setup: [
                "Stand tall with feet hip-width",
                "Clasp your hands behind your back, or hold a band or towel if hands won't meet",
            ],
            position: [
                Checkpoint(.head, "Neck long, chin level"),
                Checkpoint(.shoulders, "Shoulder blades squeeze together and down"),
                Checkpoint(.elbows, "Straighten the arms and lift the hands slightly"),
                Checkpoint(.core, "Ribs down – open the chest without arching the low back"),
            ],
            mistakes: [
                "Shrugging the shoulders up",
                "Arching the lower back to lift the hands higher",
                "Pushing the head forward",
            ],
            breathing: "Inhale to open the chest, exhale to relax the shoulders down"
        ),
        "upper-trap": Technique(
            setup: [
                "Sit or stand tall",
                "Reach one hand down toward the floor or hold the bench edge",
                "Place the other hand lightly on the side of the head",
            ],
            position: [
                Checkpoint(.head, "Tilt the ear toward the shoulder; hand adds only light weight"),
                Checkpoint(.shoulders, "Opposite shoulder stays down, away from the ear"),
                Checkpoint(.hands, "Down hand reaches long toward the floor"),
                Checkpoint(.back, "Sit tall; mild stretch along the side of the neck 4–5/10"),
            ],
            mistakes: [
                "Pulling the head hard with the hand",
                "Letting the stretched shoulder hike up",
                "Rotating the head instead of tilting it",
            ],
            breathing: "Slow nasal breaths; let the shoulder drop on each exhale"
        ),
        "side-delt-stretch": Technique(
            setup: [
                "Stand tall with feet hip-width",
                "Place one hand behind the lower back",
                "Grab that wrist with the other hand behind you",
            ],
            position: [
                Checkpoint(.head, "Tilt the head away from the stretched side"),
                Checkpoint(.shoulders, "Stretched shoulder stays down and back"),
                Checkpoint(.hands, "Gently pull the wrist across toward the other hip"),
                Checkpoint(.back, "Chest tall, no leaning; mild stretch at the side shoulder"),
            ],
            mistakes: [
                "Shrugging the stretched shoulder",
                "Yanking the wrist across",
                "Slumping forward",
            ],
            breathing: "Slow breaths; release tension a little on each exhale"
        ),
        "breathing": Technique(
            setup: [
                "Lie on your back on a mat in front of a bench",
                "Put your heels on the bench with hips and knees bent 90°",
                "One hand on the chest, one on the belly",
            ],
            position: [
                Checkpoint(.head, "Head relaxed on the mat, jaw loose"),
                Checkpoint(.shoulders, "Shoulders soft and heavy on the floor"),
                Checkpoint(.core, "Ribs down; belly and lower ribs expand on the inhale"),
                Checkpoint(.hips, "Gently press the heels down to tilt the pelvis slightly"),
                Checkpoint(.feet, "Heels rest on the bench, feet relaxed"),
            ],
            mistakes: [
                "Breathing into the upper chest and shoulders",
                "Rushing the exhale",
                "Arching the lower back off the mat",
            ],
            breathing: "Inhale through the nose for 4 s, exhale slowly for 6–8 s"
        ),
    ]
}
