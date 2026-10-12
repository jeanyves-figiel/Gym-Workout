// Technique content for the gym app comparison (#182): free weights and bodyweight.

extension Technique {
    static let gymFree: [String: Technique] = [
        // MARK: Thrusters & overhead squats
        "barbell-thruster": Technique(
            setup: ["Unrack the bar in the front rack, hands just outside the shoulders", "Feet shoulder-width, toes slightly out"],
            position: [
                Checkpoint(.elbows, "High in the squat so the bar stays on the shoulders"),
                Checkpoint(.hips, "Squat below parallel, then drive up hard"),
                Checkpoint(.hands, "Press as the hips reach full extension, bar past the face"),
                Checkpoint(.shoulders, "Lock out with the bar over the mid-foot, head through"),
            ],
            mistakes: ["Pressing before the legs finish the drive", "Elbows dropping in the bottom", "Bar finishing in front of the body"],
            breathing: "Breathe and brace at the top, hold through the squat, exhale at lockout"
        ),
        "db-thruster": Technique(
            setup: ["Clean or lift the dumbbells to the shoulders", "Feet shoulder-width, one end of each bell resting on the shoulder"],
            position: [
                Checkpoint(.elbows, "Forward and up in the squat"),
                Checkpoint(.knees, "Track over the toes to full depth"),
                Checkpoint(.hands, "Use the leg drive to send the bells overhead"),
                Checkpoint(.core, "Ribs down at lockout, no leaning back"),
            ],
            mistakes: ["Separate squat and press with a pause", "Bells drifting forward overhead", "Half squats"],
            breathing: "Inhale on the way down, exhale as you drive and press"
        ),
        "kb-thruster": Technique(
            setup: ["Clean both bells to the rack, wrists straight", "Feet shoulder-width, bells resting on the forearms"],
            position: [
                Checkpoint(.elbows, "Tucked in against the ribs in the squat"),
                Checkpoint(.hips, "Sit deep between the heels"),
                Checkpoint(.hands, "Press as you stand, bells finish behind the wrists"),
                Checkpoint(.core, "Braced so the lower back doesn't arch overhead"),
            ],
            mistakes: ["Flaring the elbows in the bottom", "Bent wrists under the bells", "Pressing with a soft lockout"],
            breathing: "Inhale and brace at the top, exhale as you press out"
        ),
        "overhead-squat": Technique(
            setup: ["Wide snatch grip, press or jerk the bar overhead", "Feet shoulder-width, toes out"],
            position: [
                Checkpoint(.hands, "Elbows locked, push up into the bar the whole time"),
                Checkpoint(.shoulders, "Active, armpits facing forward"),
                Checkpoint(.back, "Torso upright, chest proud"),
                Checkpoint(.feet, "Bar stays stacked over the mid-foot"),
            ],
            mistakes: ["Bar drifting forward", "Elbows softening at the bottom", "Heels lifting"],
            breathing: "Big breath and brace at the top, exhale after standing up"
        ),
        "kb-overhead-squat": Technique(
            setup: ["Clean and press one bell overhead", "Feet shoulder-width, free arm out for balance"],
            position: [
                Checkpoint(.hands, "Bell locked out, wrist straight"),
                Checkpoint(.head, "Eyes on the bell"),
                Checkpoint(.core, "Sit straight down, no side lean"),
                Checkpoint(.knees, "Push out over the toes"),
            ],
            mistakes: ["Leaning away from the bell", "Elbow bending on the way down", "Losing sight of the bell"],
            breathing: "Inhale and brace at the top, exhale as you stand"
        ),

        // MARK: Upright rows & high pulls
        "barbell-upright-row": Technique(
            setup: ["Overhand grip just outside shoulder-width", "Stand tall, bar resting on the thighs"],
            position: [
                Checkpoint(.elbows, "Lead the lift, up and out"),
                Checkpoint(.hands, "Bar stays close to the body"),
                Checkpoint(.shoulders, "Stop when the elbows reach shoulder height"),
                Checkpoint(.core, "Braced, no swinging"),
            ],
            mistakes: ["Narrow grip that pinches the shoulders", "Pulling the bar above the chest", "Using the hips to swing it up"],
            breathing: "Exhale as you pull, inhale as you lower"
        ),
        "db-upright-row": Technique(
            setup: ["Bells in front of the thighs, palms facing you", "Stand tall, soft knees"],
            position: [
                Checkpoint(.elbows, "Up and out, above the hands"),
                Checkpoint(.hands, "Bells travel close to the body"),
                Checkpoint(.shoulders, "Stop at shoulder height, no shrugging to the ears"),
            ],
            mistakes: ["Lifting too high", "Leaning back to cheat the weight up", "Wrists curling up"],
            breathing: "Exhale as you lift, inhale on the way down"
        ),
        "sumo-high-pull": Technique(
            setup: ["Wide stance, toes out, bar over the mid-foot", "Narrow grip inside the knees, hips down, chest up"],
            position: [
                Checkpoint(.hips, "Drive first, legs push the floor away"),
                Checkpoint(.back, "Flat from the floor to full extension"),
                Checkpoint(.elbows, "Pull high and outside once the hips open"),
                Checkpoint(.hands, "Bar finishes under the chin, close to the body"),
            ],
            mistakes: ["Pulling with the arms too early", "Rounding the back off the floor", "Bar swinging away from the body"],
            breathing: "Brace before the pull, exhale at the top, reset at the bottom"
        ),
        "kb-high-pull": Technique(
            setup: ["Bell a foot in front, hinge and hike it back between the legs", "Feet just wider than hips"],
            position: [
                Checkpoint(.hips, "Snap forward like a swing to float the bell"),
                Checkpoint(.elbows, "Pull high and back, beside the body"),
                Checkpoint(.hands, "Bell reaches chest height, wrist straight"),
                Checkpoint(.back, "Neutral spine on the hike"),
            ],
            mistakes: ["Squatting instead of hinging", "Lifting with the arm instead of the hips", "Bell flipping onto the wrist"],
            breathing: "Sharp exhale at the top of each pull, inhale on the backswing"
        ),

        // MARK: Kettlebell & dumbbell complexes
        "man-maker": Technique(
            setup: ["Two dumbbells on the floor, shoulder-width", "High plank with hands on the handles, feet wide"],
            position: [
                Checkpoint(.core, "Body in one line for the push-up and the rows"),
                Checkpoint(.elbows, "Row toward the hip, no twisting"),
                Checkpoint(.feet, "Jump in wide, flat feet next to the bells"),
                Checkpoint(.hands, "Clean to the shoulders, then press to lockout"),
            ],
            mistakes: ["Hips rotating during the rows", "Rounding the back to pick up the bells", "Rushing and losing form"],
            breathing: "Exhale on each push, row and press, inhale between parts"
        ),
        "kb-windmill": Technique(
            setup: ["Press one bell overhead, feet a bit wider than hips", "Turn both feet about 45 degrees away from the bell"],
            position: [
                Checkpoint(.hands, "Bell locked out, arm vertical"),
                Checkpoint(.head, "Eyes on the bell throughout"),
                Checkpoint(.hips, "Push out to the bell side as you hinge"),
                Checkpoint(.back, "Long spine, free hand slides down the inside of the leg"),
            ],
            mistakes: ["Arm drifting off vertical", "Bending the bell-side knee", "Rounding the back to go deeper"],
            breathing: "Inhale on the way down, exhale as you rise"
        ),
        "kb-halo": Technique(
            setup: ["Hold the bell upside down by the horns at chest height", "Feet hip-width, glutes squeezed"],
            position: [
                Checkpoint(.hands, "Bell circles close around the head"),
                Checkpoint(.elbows, "Bend to bring the bell behind the head"),
                Checkpoint(.core, "Ribs down, no arching"),
                Checkpoint(.head, "Stay still, bell moves around it"),
            ],
            mistakes: ["Big wide circles", "Arching the lower back", "Leaning the head out of the way"],
            breathing: "Breathe steadily, exhale as the bell passes behind the head"
        ),

        // MARK: Core
        "sit-up": Technique(
            setup: ["Lie on the mat, knees bent, feet hooked under a dumbbell or held", "Arms crossed on the chest"],
            position: [
                Checkpoint(.back, "Curl up, head and shoulders first"),
                Checkpoint(.core, "Sit up tall until the chest nears the knees"),
                Checkpoint(.feet, "Stay anchored on the floor"),
            ],
            mistakes: ["Throwing the arms to get up", "Pulling on the neck", "Dropping back down fast"],
            breathing: "Exhale as you curl up, inhale as you lower"
        ),
        "decline-sit-up": Technique(
            setup: ["Hook the feet under the pads, sit on the decline bench", "Arms crossed on the chest or hands at the temples"],
            position: [
                Checkpoint(.back, "Lower with control, back almost to the pad"),
                Checkpoint(.core, "Curl the spine up, ribs to the hips"),
                Checkpoint(.head, "Chin tucked, neck relaxed"),
            ],
            mistakes: ["Yanking the head forward", "Swinging up with momentum", "Dropping onto the pad"],
            breathing: "Exhale on the way up, inhale on the way down"
        ),

        // MARK: Bodyweight
        "wall-sit": Technique(
            setup: ["Back flat against the wall, feet about two feet out", "Slide down until the thighs are parallel"],
            position: [
                Checkpoint(.back, "Whole back and head touching the wall"),
                Checkpoint(.knees, "Directly over the ankles at 90 degrees"),
                Checkpoint(.feet, "Flat, hip-width, weight in the heels"),
            ],
            mistakes: ["Knees pushing past the toes", "Sitting too high", "Hands pressing on the thighs"],
            breathing: "Slow, steady breaths through the hold"
        ),
        "bear-crawl": Technique(
            setup: ["On all fours, hands under the shoulders, knees under the hips", "Tuck the toes and lift the knees an inch"],
            position: [
                Checkpoint(.knees, "Hover just off the floor"),
                Checkpoint(.back, "Flat, hips level with the shoulders"),
                Checkpoint(.hands, "Short steps, opposite hand and foot together"),
                Checkpoint(.core, "Braced so the hips don't sway"),
            ],
            mistakes: ["Hips popping up high", "Big steps that twist the body", "Holding the breath"],
            breathing: "Short, steady breaths while moving"
        ),
        "donkey-kick": Technique(
            setup: ["On all fours, hands under the shoulders, knees under the hips", "Keep one knee bent at 90 degrees"],
            position: [
                Checkpoint(.feet, "Heel presses toward the ceiling"),
                Checkpoint(.hips, "Square to the floor, no rolling open"),
                Checkpoint(.back, "Flat, stop before the lower back arches"),
            ],
            mistakes: ["Arching the lower back to lift higher", "Swinging the leg", "Letting the knee angle open"],
            breathing: "Exhale as you kick up, inhale as you lower"
        ),
        "frog-pump": Technique(
            setup: ["Lie on your back, soles together, knees out to the sides", "Heels close to the glutes, arms on the floor"],
            position: [
                Checkpoint(.hips, "Drive up fast, squeeze hard at the top"),
                Checkpoint(.knees, "Stay wide the whole time"),
                Checkpoint(.back, "Ribs down, no arching at the top"),
            ],
            mistakes: ["Lifting with the lower back", "Knees closing", "Skipping the squeeze"],
            breathing: "Exhale as you drive up, inhale as you lower"
        ),
        "deficit-push-up": Technique(
            setup: ["Hands on plates, blocks or push-up handles, a bit wider than shoulders", "Body straight, feet together"],
            position: [
                Checkpoint(.core, "Body in one line from head to heels"),
                Checkpoint(.shoulders, "Lower until the chest sinks below the hands"),
                Checkpoint(.elbows, "About 45 degrees from the body"),
                Checkpoint(.hands, "Grip the plates and push them away"),
            ],
            mistakes: ["Cutting the extra range short", "Hips sagging at the bottom", "Elbows flared wide"],
            breathing: "Inhale on the way down, exhale as you push up"
        ),
    ]
}
