// Technique content for the gym app comparison (#182): advanced calisthenics.

extension Technique {
    static let gymCalis: [String: Technique] = [
        // MARK: Muscle-ups
        "muscle-up": Technique(
            setup: ["Hang from the bar with a false grip or a firm overhand grip", "Legs together, body slightly hollow"],
            position: [
                Checkpoint(.elbows, "Pull hard and high, bar to the lower chest"),
                Checkpoint(.shoulders, "Lean over the bar fast as the chest passes it"),
                Checkpoint(.hands, "Wrists roll over the top of the bar"),
                Checkpoint(.core, "Tight, legs together, no big leg kick"),
            ],
            mistakes: ["Pulling only to the chin, too low to get over", "One arm getting over before the other", "Swinging wildly instead of pulling"],
            breathing: "Breathe in at the hang, hold through the pull and transition, exhale on the press out"
        ),
        "weighted-muscle-up": Technique(
            setup: ["Hang a small plate or kettlebell from a dip belt", "Master clean strict muscle-ups first"],
            position: [
                Checkpoint(.elbows, "Same explosive pull, bar to the lower chest"),
                Checkpoint(.shoulders, "Fast lean over the bar, chest leads"),
                Checkpoint(.hips, "Keep the weight still, no swinging"),
                Checkpoint(.hands, "Press out to straight arms at the top"),
            ],
            mistakes: ["Using too much load and losing the transition", "Letting the weight swing the body", "Dropping straight down from the top"],
            breathing: "Brace before the pull, exhale as you press out"
        ),

        // MARK: Levers
        "front-lever": Technique(
            setup: ["Overhand grip, shoulder-width, from a dead hang", "Work from the tuck to one leg to the full lever"],
            position: [
                Checkpoint(.elbows, "Locked straight the whole time"),
                Checkpoint(.shoulders, "Pulled down, press the bar toward the hips"),
                Checkpoint(.hips, "In line with the shoulders, no sag or pike"),
                Checkpoint(.feet, "Legs together and pointed, glutes squeezed"),
            ],
            mistakes: ["Bending the arms", "Hips dropping below the line", "Arching the lower back"],
            breathing: "Short steady breaths, keep the core braced"
        ),
        "tuck-front-lever": Technique(
            setup: ["Overhand grip, shoulder-width, from a dead hang", "Pull the knees to the chest and lean back"],
            position: [
                Checkpoint(.back, "Flat and horizontal, parallel to the floor"),
                Checkpoint(.elbows, "Straight, press the bar toward the hips"),
                Checkpoint(.knees, "Tucked tight to the chest"),
                Checkpoint(.shoulders, "Down away from the ears"),
            ],
            mistakes: ["Rounding the back into a ball", "Bent arms doing the work", "Hips hanging below the shoulders"],
            breathing: "Breathe shallow and steady, don't hold your breath"
        ),
        "back-lever": Technique(
            setup: ["Rings at hip height or above, false grip not needed", "Enter from an inverted hang, lower face down"],
            position: [
                Checkpoint(.elbows, "Locked straight, arms behind you"),
                Checkpoint(.shoulders, "Pulled down, chest pressed forward"),
                Checkpoint(.hips, "In line, body flat and horizontal"),
                Checkpoint(.feet, "Legs together and pointed"),
            ],
            mistakes: ["Dropping fast into the shoulder stretch", "Piking at the hips", "Bending the elbows"],
            breathing: "Calm, steady breaths, core braced"
        ),
        "tuck-back-lever": Technique(
            setup: ["Rings set high, start in an inverted tuck hang", "Lower slowly until the back is horizontal"],
            position: [
                Checkpoint(.knees, "Tucked to the chest"),
                Checkpoint(.elbows, "Straight, arms behind the body"),
                Checkpoint(.back, "Face down and close to horizontal"),
                Checkpoint(.shoulders, "Stay active, don't sink into the stretch"),
            ],
            mistakes: ["Dropping into the bottom too fast", "Bending the arms", "Going deeper than the shoulders can handle"],
            breathing: "Breathe steadily, exhale as you ease in"
        ),
        "human-flag": Technique(
            setup: ["Grip the stall bar upright, top hand overhand, bottom hand underneath", "Hands a bit wider than shoulders apart"],
            position: [
                Checkpoint(.hands, "Top hand pulls, bottom hand pushes"),
                Checkpoint(.elbows, "Both arms locked straight"),
                Checkpoint(.hips, "Lifted up into line with the shoulders"),
                Checkpoint(.feet, "Legs together, straight and pointed"),
            ],
            mistakes: ["Bending the bottom arm", "Hips sagging toward the floor", "Hands too close together"],
            breathing: "Brace hard, take short breaths during the hold"
        ),

        // MARK: Rings
        "iron-cross": Technique(
            setup: ["Start in a support on still rings", "Rings turned out, arms straight"],
            position: [
                Checkpoint(.elbows, "Locked straight from start to finish"),
                Checkpoint(.hands, "Rings turned out, wrists firm"),
                Checkpoint(.shoulders, "Pressed down, arms straight out to the sides"),
                Checkpoint(.core, "Body still and vertical under the hands"),
            ],
            mistakes: ["Bending the elbows", "Dropping into the cross too fast", "Body swinging or piking"],
            breathing: "Breathe steadily, brace before you lower"
        ),
        "band-iron-cross": Technique(
            setup: ["Loop a band over each ring and under the feet", "Start in a ring support, arms straight"],
            position: [
                Checkpoint(.elbows, "Locked straight the whole time"),
                Checkpoint(.shoulders, "Lower slowly as the arms spread out"),
                Checkpoint(.hands, "Rings turned out"),
                Checkpoint(.feet, "Hold the bands down, body still"),
            ],
            mistakes: ["Bending the arms to cheat the band", "Dropping fast into the bottom", "Using too light a band too early"],
            breathing: "Inhale as you lower, exhale as you press back up"
        ),

        // MARK: Pull-up variations
        "one-arm-pull-up": Technique(
            setup: ["Hang from one hand, slight turn of the body", "Free hand off the bar and away from the arm"],
            position: [
                Checkpoint(.shoulders, "Set the shoulder down before you pull"),
                Checkpoint(.elbows, "Drive the elbow down to the ribs"),
                Checkpoint(.core, "Tight, legs together to stop spinning"),
                Checkpoint(.head, "Chin clears the bar"),
            ],
            mistakes: ["Grabbing the working wrist with the free hand", "Kipping or swinging", "Starting from bent arms"],
            breathing: "Brace at the hang, exhale at the top, inhale as you lower"
        ),
        "archer-pull-up": Technique(
            setup: ["Wide overhand grip", "Hang with straight arms"],
            position: [
                Checkpoint(.elbows, "Pulling arm bends, the other stays almost straight"),
                Checkpoint(.head, "Chin goes over the pulling hand"),
                Checkpoint(.shoulders, "Down and back on both sides"),
                Checkpoint(.core, "Body tight, no swinging"),
            ],
            mistakes: ["Bending the straight arm to help", "Kicking the legs", "Short range at the bottom"],
            breathing: "Exhale as you pull, inhale as you lower"
        ),
        "bar-static-hold": Technique(
            setup: ["Overhand grip, shoulder-width", "Jump or pull up until the chin is over the bar"],
            position: [
                Checkpoint(.head, "Chin over the bar, neck neutral"),
                Checkpoint(.elbows, "Tight to the sides, fully bent"),
                Checkpoint(.shoulders, "Down, not shrugged to the ears"),
                Checkpoint(.core, "Legs still, no swinging"),
            ],
            mistakes: ["Chin resting on the bar", "Dropping fast at the end", "Shrugging the shoulders up"],
            breathing: "Short steady breaths during the hold, exhale slowly as you lower"
        ),
        "monkey-bar-traverse": Technique(
            setup: ["Hang from the first rung, arms straight", "Look ahead to the next rung"],
            position: [
                Checkpoint(.hands, "One hand moves at a time, full grip on each rung"),
                Checkpoint(.hips, "Swing from the hips to reach forward"),
                Checkpoint(.shoulders, "Active, not hanging loose"),
                Checkpoint(.feet, "Legs together, off the floor"),
            ],
            mistakes: ["Letting go before the next hand is set", "Hanging on loose shoulders", "Big kicks that cause swinging"],
            breathing: "Breathe with the rhythm of each reach"
        ),
        "hanging-shoulder-circles": Technique(
            setup: ["Dead hang from a bar, shoulder-width grip", "Arms stay straight the whole time"],
            position: [
                Checkpoint(.shoulders, "Draw slow small circles: up, forward, down, back"),
                Checkpoint(.elbows, "Locked straight"),
                Checkpoint(.core, "Lightly braced, body quiet"),
                Checkpoint(.head, "Neutral, eyes forward"),
            ],
            mistakes: ["Bending the arms", "Swinging the body instead of moving the shoulders", "Going too fast"],
            breathing: "Breathe slowly and evenly"
        ),

        // MARK: Push-up variations
        "one-arm-push-up": Technique(
            setup: ["Feet wide apart for balance", "Working hand under the chest, free hand behind the back"],
            position: [
                Checkpoint(.hips, "Square to the floor, no twisting"),
                Checkpoint(.elbows, "Stay close to the body as you lower"),
                Checkpoint(.core, "Tight from head to heels"),
                Checkpoint(.hands, "Spread fingers, push the floor away"),
            ],
            mistakes: ["Rotating the hips open", "Feet too close together", "Shallow reps"],
            breathing: "Inhale as you lower, exhale as you press"
        ),
        "shoulder-tap-push-up": Technique(
            setup: ["High plank, hands under the shoulders", "Feet a bit wider than usual"],
            position: [
                Checkpoint(.core, "Braced so the hips stay still"),
                Checkpoint(.elbows, "About 45 degrees from the body on the way down"),
                Checkpoint(.hands, "After each rep, tap the opposite shoulder"),
                Checkpoint(.hips, "Level, no rocking side to side"),
            ],
            mistakes: ["Hips swaying on the tap", "Rushing the push-up", "Feet too narrow"],
            breathing: "Inhale down, exhale up, breathe easy on the taps"
        ),
        "spiderman-push-up": Technique(
            setup: ["High plank, hands just outside the shoulders", "Body in one straight line"],
            position: [
                Checkpoint(.knees, "Bring one knee toward the same elbow as you lower"),
                Checkpoint(.hips, "Stay low and level"),
                Checkpoint(.elbows, "About 45 degrees from the body"),
                Checkpoint(.feet, "Alternate sides each rep"),
            ],
            mistakes: ["Hips piking up when the knee moves", "Short range on the push-up", "Dragging the foot on the floor"],
            breathing: "Inhale as you lower, exhale as you press"
        ),
        "wall-push-up": Technique(
            setup: ["Stand an arm's length from the wall", "Hands on the wall at chest height, shoulder-width"],
            position: [
                Checkpoint(.back, "Body straight from head to heels"),
                Checkpoint(.elbows, "Bend to bring the chest close to the wall"),
                Checkpoint(.hands, "Push back to straight arms"),
                Checkpoint(.feet, "Planted, heels may lift slightly"),
            ],
            mistakes: ["Bending at the hips", "Head poking toward the wall", "Hands too high"],
            breathing: "Inhale as you lean in, exhale as you push away"
        ),

        // MARK: Handstand push-ups
        "freestanding-hspu": Technique(
            setup: ["Kick up to a balanced handstand on a mat", "Hands shoulder-width, fingers spread"],
            position: [
                Checkpoint(.hands, "Balance with the fingers and palms"),
                Checkpoint(.head, "Lowers to form a triangle with the hands"),
                Checkpoint(.elbows, "Track forward, not flared out"),
                Checkpoint(.core, "Tight, legs together and straight"),
            ],
            mistakes: ["Banana back to stay balanced", "Elbows flaring wide", "Crashing the head into the mat"],
            breathing: "Inhale as you lower, exhale as you press"
        ),
        "kipping-hspu": Technique(
            setup: ["Hands shoulder-width, a hand span from the wall, on a mat", "Kick up to a handstand with heels on the wall"],
            position: [
                Checkpoint(.head, "Lower to rest lightly on the mat"),
                Checkpoint(.knees, "Pull them down to the chest"),
                Checkpoint(.hips, "Kick the legs up hard and extend the hips"),
                Checkpoint(.elbows, "Press out to lock as the hips open"),
            ],
            mistakes: ["Slamming the head into the mat", "Pressing before the kick", "Hands too far from the wall"],
            breathing: "Inhale at the top, exhale as you kick and press"
        ),

        // MARK: Pistols
        "pistol-squat": Technique(
            setup: ["Stand on one leg, other leg straight out in front", "Arms reach forward for balance"],
            position: [
                Checkpoint(.feet, "Whole foot down, heel stays on the floor"),
                Checkpoint(.knees, "Tracks over the toes"),
                Checkpoint(.hips, "Sit all the way down between the heel and the knee"),
                Checkpoint(.core, "Lean the chest forward to balance"),
            ],
            mistakes: ["Heel lifting at the bottom", "Knee caving inward", "Bouncing out of the bottom"],
            breathing: "Inhale on the way down, exhale as you stand"
        ),
        "weighted-pistol": Technique(
            setup: ["Hold a kettlebell by the horns at chest height", "Free leg straight out in front"],
            position: [
                Checkpoint(.hands, "Bell held out in front as a counterweight"),
                Checkpoint(.knees, "Tracks over the toes"),
                Checkpoint(.feet, "Heel down the whole way"),
                Checkpoint(.back, "Long spine, chest up"),
            ],
            mistakes: ["Rocking to get up", "Free leg touching the floor", "Knee caving inward"],
            breathing: "Inhale as you sit down, exhale as you drive up"
        ),

        // MARK: Dip station
        "dip-bar-leg-raise": Technique(
            setup: ["Support yourself on the dip bars with straight arms", "Legs hang straight below you"],
            position: [
                Checkpoint(.elbows, "Locked straight"),
                Checkpoint(.shoulders, "Pushed down, away from the ears"),
                Checkpoint(.knees, "Straight as the legs rise to hip height"),
                Checkpoint(.core, "Controls the lift and the lowering"),
            ],
            mistakes: ["Swinging the legs up", "Shrugging the shoulders", "Dropping the legs fast"],
            breathing: "Exhale as you lift, inhale as you lower"
        ),
    ]
}
