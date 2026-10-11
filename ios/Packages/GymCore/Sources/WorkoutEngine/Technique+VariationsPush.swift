// Technique content for the catalog extension (#174): chest and shoulders.

extension Technique {
    static let variationsPush: [String: Technique] = [
        "decline-bench-press": Technique(
            setup: ["Set the decline bench about 15–30°, hook the feet under the rollers", "Eyes under the bar, take a grip just wider than the shoulders", "Have a spotter hand the bar out"],
            position: [
                Checkpoint(.shoulders, "Blades pinned back and down against the pad"),
                Checkpoint(.hands, "Lower the bar to the bottom of the chest, wrists stacked over the elbows"),
                Checkpoint(.elbows, "About 45–60° from the body, not flared straight out"),
                Checkpoint(.feet, "Locked under the rollers so you don't slide"),
            ],
            mistakes: ["Bouncing the bar off the chest", "Bringing the bar too high, to the neck", "Training without a spotter"],
            breathing: "Inhale and brace as you lower, exhale as you press"
        ),
        "smith-bench-press": Technique(
            setup: ["Place the flat bench so the bar lands on your mid-chest", "Set the safety stops just above chest height", "Grip just wider than the shoulders, rotate the bar off the hooks"],
            position: [
                Checkpoint(.shoulders, "Blades squeezed together and pinned to the bench"),
                Checkpoint(.elbows, "About 45° from the body on the way down"),
                Checkpoint(.hands, "Wrists straight, stacked over the elbows"),
                Checkpoint(.feet, "Flat on the floor, pushing you into the bench"),
            ],
            mistakes: ["Bench in the wrong spot so the bar hits the neck or belly", "Forgetting to set the stops", "Shoulders rolling forward at the top"],
            breathing: "Inhale on the way down, exhale as you press"
        ),
        "smith-incline-press": Technique(
            setup: ["Set the bench to about 30° and slide it so the bar lands on the upper chest", "Set the safety stops", "Grip just wider than the shoulders, rotate the bar off the hooks"],
            position: [
                Checkpoint(.hands, "Lower to the upper chest, just under the collarbones"),
                Checkpoint(.shoulders, "Pinned back and down on the pad"),
                Checkpoint(.elbows, "Slightly tucked, under the bar"),
                Checkpoint(.back, "Natural arch, hips stay on the seat"),
            ],
            mistakes: ["Bench too steep, turning it into a shoulder press", "Hips lifting off the seat", "Bouncing off the stops"],
            breathing: "Inhale as you lower, exhale as you press"
        ),
        "barbell-floor-press": Technique(
            setup: ["Set the hooks low in a rack, lie on the floor under the bar", "Knees bent or legs straight, grip just wider than the shoulders", "Unrack with straight arms over the chest"],
            position: [
                Checkpoint(.elbows, "Lower until the upper arms touch the floor, about 45° from the body"),
                Checkpoint(.hands, "Wrists stacked over the elbows"),
                Checkpoint(.shoulders, "Blades pulled together on the floor"),
            ],
            mistakes: ["Slamming the elbows into the floor", "Bouncing instead of pausing", "Elbows flared straight out"],
            breathing: "Inhale as you lower, pause, exhale as you press"
        ),
        "db-fly": Technique(
            setup: ["Lie on a flat bench, feet on the floor", "Press the dumbbells over the chest, palms facing each other"],
            position: [
                Checkpoint(.elbows, "Slightly bent and locked at that angle the whole rep"),
                Checkpoint(.hands, "Open in a wide arc until you feel a chest stretch, about chest level"),
                Checkpoint(.shoulders, "Blades pinned to the bench, no shrugging"),
            ],
            mistakes: ["Bending and straightening the elbows, turning it into a press", "Dropping the weights too low", "Going too heavy"],
            breathing: "Inhale as you open, exhale as you bring the weights together"
        ),
        "incline-db-fly": Technique(
            setup: ["Set the bench to about 30°", "Press the dumbbells over the upper chest, palms facing each other"],
            position: [
                Checkpoint(.elbows, "Soft and fixed; the movement is at the shoulder"),
                Checkpoint(.hands, "Lower in an arc to a stretch, then squeeze back up over the chest"),
                Checkpoint(.back, "Against the pad, hips on the seat"),
            ],
            mistakes: ["Bench too steep", "Overstretching the shoulders at the bottom", "Clanking the weights at the top"],
            breathing: "Inhale on the way down, exhale as you squeeze up"
        ),
        "low-high-cable-fly": Technique(
            setup: ["Set both pulleys at the lowest position, D-handles", "Stand in the middle, a small step forward, slight forward lean"],
            position: [
                Checkpoint(.hands, "Sweep up and in until they meet at chin height"),
                Checkpoint(.elbows, "Slightly bent, angle fixed"),
                Checkpoint(.shoulders, "Down, away from the ears"),
                Checkpoint(.core, "Braced, ribs down"),
            ],
            mistakes: ["Lifting with the shoulders and traps", "Bending the elbows to curl the handles up", "Leaning back"],
            breathing: "Exhale as the hands come together, inhale on the way back"
        ),
        "high-low-cable-fly": Technique(
            setup: ["Set both pulleys high, D-handles", "Stand in the middle, staggered stance, slight forward lean"],
            position: [
                Checkpoint(.hands, "Sweep down and in until they meet in front of the hips"),
                Checkpoint(.elbows, "Slightly bent, angle fixed"),
                Checkpoint(.shoulders, "Pulled back and down, chest proud"),
                Checkpoint(.core, "Braced so the torso stays still"),
            ],
            mistakes: ["Pressing the handles down instead of hugging", "Rounding the shoulders forward", "Letting the cables yank the arms back"],
            breathing: "Exhale as you bring the hands down, inhale on the return"
        ),
        "incline-push-up": Technique(
            setup: ["Hands on the edge of a bench or bar, a little wider than the shoulders", "Walk the feet back until the body is in one line"],
            position: [
                Checkpoint(.core, "Tight, body straight from head to heels"),
                Checkpoint(.elbows, "About 45° from the body"),
                Checkpoint(.hips, "In line, not sagging or piked"),
                Checkpoint(.head, "Neutral, the chest reaches the edge first"),
            ],
            mistakes: ["Hips sagging", "Only going halfway down", "Head poking forward"],
            breathing: "Inhale as you lower, exhale as you push away"
        ),
        "knee-push-up": Technique(
            setup: ["Hands on the floor just wider than the shoulders", "Knees on a mat, walk the hands forward until knees, hips and shoulders line up"],
            position: [
                Checkpoint(.hips, "In line between knees and shoulders, not bent"),
                Checkpoint(.elbows, "About 45° from the body"),
                Checkpoint(.core, "Braced, no sagging"),
                Checkpoint(.knees, "On the mat behind the hips, not under them"),
            ],
            mistakes: ["Sticking the hips up", "Knees too close to the hands", "Partial range"],
            breathing: "Inhale on the way down, exhale as you press up"
        ),
        "decline-push-up": Technique(
            setup: ["Feet on a bench or box behind you, hands on the floor just wider than the shoulders", "Body rigid from head to heels"],
            position: [
                Checkpoint(.core, "Braced, no sagging in the lower back"),
                Checkpoint(.hands, "Under or slightly ahead of the shoulders"),
                Checkpoint(.elbows, "About 45° from the body"),
                Checkpoint(.head, "Neutral; lower until the nose nears the floor"),
            ],
            mistakes: ["Hips sagging toward the floor", "Piking the hips up", "Elbows flaring wide"],
            breathing: "Inhale as you lower, exhale as you press"
        ),
        "archer-push-up": Technique(
            setup: ["Plank with the hands very wide, fingers turned out slightly", "Feet a little apart for balance"],
            position: [
                Checkpoint(.shoulders, "Shift over one hand as you lower"),
                Checkpoint(.elbows, "Working arm bends close to the body, the other arm stays straight"),
                Checkpoint(.core, "Body straight, hips level"),
                Checkpoint(.hips, "Square to the floor, no twisting"),
            ],
            mistakes: ["Bending both arms equally", "Twisting the hips", "Rushing the side-to-side shift"],
            breathing: "Inhale as you lower to one side, exhale as you press up"
        ),
        "bench-dip": Technique(
            setup: ["Sit on the edge of a bench, hands beside the hips, fingers forward", "Slide the hips off, feet flat with knees bent (or legs straight for harder)"],
            position: [
                Checkpoint(.hips, "Close to the bench, moving straight down"),
                Checkpoint(.elbows, "Point back, not out; stop at about 90°"),
                Checkpoint(.shoulders, "Down and back, chest up"),
            ],
            mistakes: ["Dipping too deep and straining the shoulders", "Drifting away from the bench", "Pushing with the legs"],
            breathing: "Inhale as you lower, exhale as you press up"
        ),
        "single-arm-db-press": Technique(
            setup: ["Stand tall, feet hip-width, one dumbbell at the shoulder", "Free hand on the hip"],
            position: [
                Checkpoint(.core, "Braced; don't lean away from the weight"),
                Checkpoint(.hands, "Press up and slightly in, finishing over the shoulder"),
                Checkpoint(.elbows, "Start under the wrist, slightly in front of the body"),
                Checkpoint(.hips, "Level, glutes squeezed"),
            ],
            mistakes: ["Side-bending to push the weight up", "Arching the lower back", "Pressing out in front instead of overhead"],
            breathing: "Exhale as you press, inhale as you lower"
        ),
        "kb-press": Technique(
            setup: ["Clean the bell to the rack: handle in the palm, bell on the back of the forearm", "Feet hip-width, glutes and abs tight"],
            position: [
                Checkpoint(.hands, "Wrist straight, knuckles to the ceiling"),
                Checkpoint(.elbows, "Start tucked in front of the ribs, finish locked out"),
                Checkpoint(.head, "Arm finishes by the ear"),
                Checkpoint(.core, "Braced, ribs down"),
            ],
            mistakes: ["Bent wrist letting the bell flop back", "Leaning back to press", "Elbow flaring out from the start"],
            breathing: "Exhale as you press, inhale as you lower to the rack"
        ),
        "z-press": Technique(
            setup: ["Sit on the floor in a rack, legs straight in front", "Set the hooks at shoulder height while seated, unrack to the front of the shoulders"],
            position: [
                Checkpoint(.back, "Tall and upright, no leaning back"),
                Checkpoint(.core, "Braced hard; nothing to push against"),
                Checkpoint(.hands, "Press straight up, bar over the hips"),
                Checkpoint(.head, "Pull the head back, then through once the bar passes"),
            ],
            mistakes: ["Leaning back and turning it into an incline press", "Rounding the lower back", "Going too heavy too soon"],
            breathing: "Big breath and brace at the bottom, exhale past the sticking point"
        ),
        "smith-shoulder-press": Technique(
            setup: ["Set the bench upright under the bar so it passes just in front of the face", "Set the safety stops at chin height", "Grip just wider than the shoulders"],
            position: [
                Checkpoint(.back, "Against the pad, no arching"),
                Checkpoint(.hands, "Lower the bar to about chin level"),
                Checkpoint(.elbows, "Under the wrists, slightly in front of the body"),
                Checkpoint(.feet, "Planted, not pushing you off the bench"),
            ],
            mistakes: ["Bench set so the bar hits the face or goes behind the neck", "Arching off the pad", "Locking out hard at the top"],
            breathing: "Exhale as you press, inhale as you lower"
        ),
        "wall-hspu": Technique(
            setup: ["Place a folded mat by the wall, hands a hand-length from the wall", "Kick up to a handstand with the heels against the wall"],
            position: [
                Checkpoint(.hands, "Shoulder-width or a bit wider, fingers spread"),
                Checkpoint(.head, "Lowers to the mat in front of the hands, making a tripod"),
                Checkpoint(.elbows, "Stay over the wrists, no wild flaring"),
                Checkpoint(.core, "Tight, ribs down, legs together"),
            ],
            mistakes: ["Crashing the head onto the mat", "Excessive arching against the wall", "Trying it without being able to hold a wall handstand"],
            breathing: "Inhale on the way down, exhale as you press back up"
        ),
        "db-front-raise": Technique(
            setup: ["Stand tall, a dumbbell in each hand in front of the thighs", "Feet hip-width, knees soft"],
            position: [
                Checkpoint(.hands, "Raise to eye height, thumbs slightly up"),
                Checkpoint(.elbows, "Almost straight, a soft bend"),
                Checkpoint(.shoulders, "Down, no shrugging"),
                Checkpoint(.core, "Braced so the body doesn't swing"),
            ],
            mistakes: ["Swinging with the hips", "Lifting above head height", "Dropping the weights fast"],
            breathing: "Exhale as you lift, inhale as you lower"
        ),
        "cable-front-raise": Technique(
            setup: ["Set the pulley low, stand facing away with the cable running between the feet", "Handle or bar in front of the thighs"],
            position: [
                Checkpoint(.hands, "Raise in front to eye height"),
                Checkpoint(.elbows, "Straight with a soft bend"),
                Checkpoint(.core, "Braced; don't lean forward or back"),
                Checkpoint(.shoulders, "Down, away from the ears"),
            ],
            mistakes: ["Leaning back to lift", "Shrugging at the top", "Letting the stack pull the arm down fast"],
            breathing: "Exhale on the way up, inhale on the slow way down"
        ),
        "seated-lateral-raise": Technique(
            setup: ["Sit tall on the end of a bench, feet flat", "Dumbbells at the sides, palms facing in"],
            position: [
                Checkpoint(.elbows, "Lead the movement, slightly bent"),
                Checkpoint(.hands, "Stop at shoulder height, never above the elbows"),
                Checkpoint(.back, "Tall, no rocking"),
                Checkpoint(.shoulders, "Down, no shrugging"),
            ],
            mistakes: ["Swinging the torso", "Lifting above shoulder height", "Shrugging the traps up"],
            breathing: "Exhale as you raise, inhale as you lower"
        ),
        "lean-away-lateral-raise": Technique(
            setup: ["Hold a sturdy post with one hand, feet close to it", "Lean away until the working arm hangs free, dumbbell in that hand"],
            position: [
                Checkpoint(.hands, "Raise out to the side to shoulder height"),
                Checkpoint(.elbows, "Soft and fixed, leading the dumbbell"),
                Checkpoint(.core, "Body stays still in the lean"),
                Checkpoint(.feet, "Together and planted by the post"),
            ],
            mistakes: ["Pulling on the post to swing the weight", "Cutting the stretch short at the bottom", "Lifting above shoulder height"],
            breathing: "Exhale as you raise, inhale as you lower to a full stretch"
        ),
        "band-lateral-raise": Technique(
            setup: ["Stand on the middle of the band, feet hip-width", "A handle or end in each hand at the sides"],
            position: [
                Checkpoint(.elbows, "Soft, leading the hands out to the sides"),
                Checkpoint(.hands, "Up to shoulder height, pause at the top"),
                Checkpoint(.shoulders, "Down, away from the ears"),
                Checkpoint(.feet, "Firmly on the band so it can't slip"),
            ],
            mistakes: ["Letting the band snap the arms down", "Shrugging", "Leaning to help the lift"],
            breathing: "Exhale as you raise, inhale as you lower"
        ),
        "cable-y-raise": Technique(
            setup: ["Set both pulleys low, cross the cables: left hand holds the right cable and vice versa", "Stand in the middle, slight hinge, arms crossed in front"],
            position: [
                Checkpoint(.hands, "Raise up and out into a Y, thumbs up"),
                Checkpoint(.elbows, "Nearly straight"),
                Checkpoint(.shoulders, "Blades back and down, not shrugged"),
                Checkpoint(.core, "Ribs down, no arching to finish"),
            ],
            mistakes: ["Arching the lower back at the top", "Shrugging the traps", "Going too heavy and losing the Y"],
            breathing: "Exhale as you raise, inhale on the way back"
        ),
        "cable-upright-row": Technique(
            setup: ["Low pulley with a straight bar, wide grip", "Stand close to the pulley, bar at the thighs"],
            position: [
                Checkpoint(.elbows, "Lead and rise out to the sides, to chest height"),
                Checkpoint(.hands, "Stay close to the body, below the elbows"),
                Checkpoint(.shoulders, "Stop below shoulder height to keep them happy"),
                Checkpoint(.back, "Tall, no leaning back"),
            ],
            mistakes: ["Narrow grip and pulling to the chin", "Lifting the elbows above the shoulders", "Jerking the bar with the hips"],
            breathing: "Exhale as you pull up, inhale as you lower"
        ),
        "incline-reverse-fly": Technique(
            setup: ["Set a bench to about 30–45°, lie chest-down with the head past the top", "Dumbbells hanging straight down, palms facing in"],
            position: [
                Checkpoint(.hands, "Open wide, pinkies leading, to about shoulder height"),
                Checkpoint(.elbows, "Soft and fixed"),
                Checkpoint(.shoulders, "Down, no shrugging toward the ears"),
                Checkpoint(.back, "Chest stays on the pad"),
            ],
            mistakes: ["Lifting the chest off the pad", "Bending the elbows to row", "Swinging heavy weights"],
            breathing: "Exhale as you open, inhale as you lower"
        ),
        "cable-rear-delt-fly": Technique(
            setup: ["Set both pulleys at shoulder height, hold the cable ends or D-handles", "Cross the cables: right hand holds the left cable, left hand the right"],
            position: [
                Checkpoint(.hands, "Pull out wide in a straight line at shoulder height"),
                Checkpoint(.elbows, "Slightly bent and fixed"),
                Checkpoint(.shoulders, "Down, no shrugging"),
                Checkpoint(.core, "Tall and braced, no leaning back"),
            ],
            mistakes: ["Rowing with bent arms", "Leaning back to finish", "Letting the cables snap back"],
            breathing: "Exhale as you pull apart, inhale on the slow return"
        ),
    ]
}
