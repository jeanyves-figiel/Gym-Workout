// Technique content for the machine gaps (#796): seated and standing leg curl, lateral raise, incline press,
// seated dip and high row machines.

extension Technique {
    static let machineGaps: [String: Technique] = [
        "seated-leg-curl": Technique(
            setup: [
                "Sit back so your knee joint lines up with the machine's pivot",
                "Ankle pad behind the lower calf, just above the heel",
                "Lower the thigh pad until it pins the legs just above the knees",
            ],
            position: [
                Checkpoint(.hands, "Holding the handles to keep the hips in the seat"),
                Checkpoint(.back, "Back flat on the backrest, chest up"),
                Checkpoint(.knees, "Aligned with the pivot through the whole range"),
                Checkpoint(.feet, "Toes pulled up toward the shins"),
            ],
            mistakes: [
                "Thigh pad too loose, hips sliding forward",
                "Letting the stack slam back up between reps",
                "Stopping halfway instead of curling the pad under the seat",
            ],
            breathing: "Exhale as you push the pad down, inhale on the slow 3 s return"
        ),
        "standing-leg-curl": Technique(
            setup: [
                "Stand on the platform, front of the working thigh on the knee pad",
                "Ankle pad behind the lower calf, knee level with the pivot",
                "Hold the handles, standing leg soft",
            ],
            position: [
                Checkpoint(.back, "Neutral, no arching as the heel comes up"),
                Checkpoint(.hips, "Square and still, no twisting toward the working side"),
                Checkpoint(.knees, "Working knee stays on the pad, aligned with the pivot"),
                Checkpoint(.feet, "Working foot flexed, toes toward the shin"),
            ],
            mistakes: [
                "Lifting the thigh off the pad to swing the weight",
                "Arching the lower back at the top",
                "Dropping the pad fast on the way down",
            ],
            breathing: "Exhale as you curl, inhale as you lower slowly"
        ),
        "machine-lateral-raise": Technique(
            setup: [
                "Set the seat so your shoulders line up with the machine's pivots",
                "Pads on the outside of the arms, just above the elbows",
                "Grip the handles lightly, chest against the pad or back on the rest",
            ],
            position: [
                Checkpoint(.shoulders, "Down and away from the ears"),
                Checkpoint(.elbows, "Lead the movement, slightly bent, lifting into the pads"),
                Checkpoint(.hands, "Loose grip; the arms do the work, not the hands"),
                Checkpoint(.back, "Tall, no leaning back to start the lift"),
            ],
            mistakes: [
                "Shrugging the shoulders up toward the ears",
                "Raising the arms above shoulder height",
                "Letting the stack drop between reps",
            ],
            breathing: "Exhale as you raise, inhale as you lower"
        ),
        "incline-chest-press-machine": Technique(
            setup: [
                "Set the seat so the handles start level with the upper chest",
                "Back and head on the pad, feet flat",
                "Grip just outside shoulder width, wrists straight",
            ],
            position: [
                Checkpoint(.shoulders, "Blades back and down on the pad"),
                Checkpoint(.elbows, "About 45° from the body, under the handles"),
                Checkpoint(.hands, "Press up and out, wrists stacked over the elbows"),
                Checkpoint(.back, "Natural arch, hips stay on the seat"),
            ],
            mistakes: [
                "Seat too low, turning it into a shoulder press",
                "Shoulders rolling forward at lockout",
                "Bouncing out of the stretch",
            ],
            breathing: "Exhale as you press, inhale on the slow return"
        ),
        "seated-dip-machine": Technique(
            setup: [
                "Set the seat so the handles start beside the lower ribs",
                "Fasten the thigh pad or belt, sit tall against the back pad",
                "Grip the handles with a neutral or overhand grip",
            ],
            position: [
                Checkpoint(.shoulders, "Down, chest proud"),
                Checkpoint(.elbows, "Point back, close to the body"),
                Checkpoint(.hands, "Push straight down to full lockout by the hips"),
                Checkpoint(.back, "Stays on the pad, no leaning forward"),
            ],
            mistakes: [
                "Elbows flaring out to the sides",
                "Shoulders rolling forward and up at the top",
                "Short, bouncy reps that skip the lockout",
            ],
            breathing: "Exhale as you push down, inhale as the handles rise"
        ),
        "machine-high-row": Technique(
            setup: [
                "Set the seat so the handles are overhead and in front at full reach",
                "Thighs locked under the pad, feet flat",
                "Grip the handles, arms long",
            ],
            position: [
                Checkpoint(.shoulders, "Blades squeeze down and together at the end"),
                Checkpoint(.elbows, "Drive down and back toward the hips"),
                Checkpoint(.hands, "Handles finish just in front of the shoulders"),
                Checkpoint(.back, "Chest up, slight lean back, no swinging"),
            ],
            mistakes: [
                "Leaning far back to move the weight",
                "Shrugging at the start of the pull",
                "Letting the arms snap up on the return",
            ],
            breathing: "Exhale as you pull, inhale as the arms reach up"
        ),
    ]
}
