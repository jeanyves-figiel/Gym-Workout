// Technique content for the gym audit exercises (#162).

extension Technique {
    static let gymAudit: [String: Technique] = [
        "ez-bar-curl": Technique(
            setup: ["Grip the angled handles of the EZ bar, palms up, hands shoulder-width", "Stand tall, bar resting on the thighs"],
            position: [
                Checkpoint(.elbows, "Pinned to the sides, only the forearms move"),
                Checkpoint(.hands, "Wrists straight on the angled grip"),
                Checkpoint(.core, "Braced, no leaning back to swing the bar"),
            ],
            mistakes: ["Swinging with the hips", "Elbows drifting forward at the top", "Dropping the bar on the way down"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "ez-skullcrusher": Technique(
            setup: ["Lie on a flat bench, feet on the floor", "Hold the EZ bar over the chest on the inner angled grip"],
            position: [
                Checkpoint(.elbows, "Point at the ceiling and stay there; bend only at the elbows"),
                Checkpoint(.hands, "Lower the bar to just above the forehead"),
                Checkpoint(.back, "Flat on the bench, no arching"),
            ],
            mistakes: ["Elbows flaring out wide", "Turning it into a press by moving the upper arms", "Going too heavy too soon"],
            breathing: "Inhale as you lower, exhale as you press up"
        ),
        "db-preacher-curl": Technique(
            setup: ["Set the seat so your armpits sit snug over the top of the preacher pad", "A dumbbell in each hand, backs of the arms flat on the pad"],
            position: [
                Checkpoint(.elbows, "Stay on the pad; stop just short of locking out at the bottom"),
                Checkpoint(.hands, "Palms up, wrists straight"),
                Checkpoint(.shoulders, "Down and still, no shrugging"),
            ],
            mistakes: ["Lifting the elbows off the pad", "Dropping fast into a locked elbow", "Rocking the torso"],
            breathing: "Exhale as you curl, inhale as you lower"
        ),
        "machine-shoulder-press": Technique(
            setup: ["Adjust the seat so the handles start at shoulder height", "Sit back flat against the pad, feet planted"],
            position: [
                Checkpoint(.hands, "Grip just outside the shoulders, wrists over the elbows"),
                Checkpoint(.elbows, "Slightly in front of the body, not flared straight out"),
                Checkpoint(.back, "Stays on the pad, no arching"),
            ],
            mistakes: ["Arching the lower back off the pad", "Locking out hard at the top", "Letting the weight stack crash down"],
            breathing: "Exhale as you press, inhale as you lower"
        ),
        "machine-calf-raise": Technique(
            setup: ["Set the shoulder pads so the knees are just soft at the bottom", "Balls of the feet on the edge of the platform"],
            position: [
                Checkpoint(.knees, "Soft but fixed, not bending to help"),
                Checkpoint(.feet, "Full stretch down, then all the way up onto the big toe"),
                Checkpoint(.core, "Tall and braced under the pads"),
            ],
            mistakes: ["Bouncing at the bottom", "Short half reps", "Bending the knees to push"],
            breathing: "Exhale on the way up, inhale on the way down"
        ),
        "t-bar-row": Technique(
            setup: ["Set the chest pad so the arms hang straight to the handles", "Feet flat on the platform, chest on the pad"],
            position: [
                Checkpoint(.back, "Chest stays on the pad the whole set"),
                Checkpoint(.elbows, "Drive back past the ribs"),
                Checkpoint(.shoulders, "Squeeze the shoulder blades together at the top"),
            ],
            mistakes: ["Lifting the chest off to heave the weight", "Shrugging instead of rowing", "Rushing the lowering"],
            breathing: "Exhale as you row, inhale as you lower"
        ),
        "glute-ham-raise": Technique(
            setup: ["Set the foot plate so the knees sit just behind the thigh pad", "Lock the ankles under the rollers, body upright"],
            position: [
                Checkpoint(.hips, "Straight in line with the knees and shoulders, no piking"),
                Checkpoint(.knees, "The only hinge: lower forward slowly from the knees"),
                Checkpoint(.feet, "Push the toes into the plate to pull back up"),
            ],
            mistakes: ["Bending at the hips to make it easier", "Dropping fast through the bottom", "Using the arms to push off"],
            breathing: "Inhale as you lower, exhale as you pull back up"
        ),
        "ball-crunch": Technique(
            setup: ["Sit on the ball and walk the feet out until it sits under the lower back", "Feet wide for balance, hands lightly at the temples"],
            position: [
                Checkpoint(.back, "Arch gently over the ball at the bottom"),
                Checkpoint(.core, "Curl the ribs toward the hips"),
                Checkpoint(.head, "Neutral, don't pull on the neck"),
            ],
            mistakes: ["Pulling the head forward with the hands", "Rolling the ball instead of curling", "Feet too close together"],
            breathing: "Exhale as you curl up, inhale as you extend over the ball"
        ),
        "jump-rope": Technique(
            setup: ["Stand on the middle of the rope: handles reach the armpits", "Rope behind the heels, elbows close to the sides"],
            position: [
                Checkpoint(.hands, "Turn the rope from the wrists, not the shoulders"),
                Checkpoint(.feet, "Small hops on the balls of the feet"),
                Checkpoint(.knees, "Soft, absorbing each landing"),
            ],
            mistakes: ["Jumping too high", "Big arm circles", "Landing flat-footed"],
            breathing: "Steady rhythm; breathe through the nose as long as you can"
        ),
    ]
}
