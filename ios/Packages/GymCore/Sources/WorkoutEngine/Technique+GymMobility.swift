// Technique content for the gym app comparison (#182): foam rolling, massage ball and mat mobility.

extension Technique {
    static let gymMobility: [String: Technique] = [
        // MARK: Foam roller
        "foam-roll-upper-back": Technique(
            setup: ["Lie back with the roller across the mid back, feet flat, knees bent", "Hands behind the head, elbows in"],
            position: [
                Checkpoint(.hips, "Lifted off the floor, push through the feet to roll"),
                Checkpoint(.back, "Roll between the shoulder blades and the bottom of the ribs"),
                Checkpoint(.head, "Supported in the hands, chin slightly tucked"),
            ],
            mistakes: ["Rolling down onto the lower back", "Pulling on the neck with the hands", "Rushing big fast passes"],
            breathing: "Slow, steady breaths, exhale as you sink over a stiff spot"
        ),
        "foam-roll-glutes": Technique(
            setup: ["Sit on the roller, hands on the floor behind you", "Cross one ankle over the other knee"],
            position: [
                Checkpoint(.hips, "Tilt toward the crossed-leg side to load that glute"),
                Checkpoint(.hands, "Planted behind, arms take some of the weight"),
                Checkpoint(.feet, "Standing foot flat, drives the small rolls"),
            ],
            mistakes: ["Sitting square instead of leaning into the glute", "Rolling onto the lower back", "Moving too fast to feel anything"],
            breathing: "Breathe slowly and let the muscle relax on each exhale"
        ),
        "foam-roll-lats": Technique(
            setup: ["Lie on your side with the roller under the armpit", "Bottom arm straight overhead, thumb up"],
            position: [
                Checkpoint(.shoulders, "Bottom arm long and relaxed on the floor"),
                Checkpoint(.back, "Roll from the armpit to the middle of the ribs"),
                Checkpoint(.hips, "Turn slightly forward or back to find the tight spot"),
            ],
            mistakes: ["Rolling onto the shoulder joint", "Going down into the lower ribs", "Holding the breath"],
            breathing: "Long exhales while you pause on a tender spot"
        ),
        "foam-roll-hamstrings": Technique(
            setup: ["Sit with the roller under the back of the thighs", "Hands on the floor behind you, lift the hips"],
            position: [
                Checkpoint(.hands, "Push through the hands to move the body"),
                Checkpoint(.knees, "Legs long, roll from just above the knee to the glute"),
                Checkpoint(.feet, "Relaxed, cross one leg over the other for more pressure"),
            ],
            mistakes: ["Rolling over the back of the knee", "Shrugging the shoulders up", "Going too fast"],
            breathing: "Breathe easy, exhale as you slow down on tight spots"
        ),
        "foam-roll-adductors": Technique(
            setup: ["Lie face down on the forearms", "Bring one knee out to the side with the inner thigh on the roller"],
            position: [
                Checkpoint(.elbows, "Under the shoulders, forearms on the floor"),
                Checkpoint(.hips, "Shift slowly sideways to roll groin to knee"),
                Checkpoint(.knees, "Bent and out to the side, leg relaxed"),
            ],
            mistakes: ["Rolling over the knee joint", "Sagging the lower back", "Too much pressure too soon"],
            breathing: "Slow exhales, let the inner thigh soften"
        ),

        // MARK: Massage ball
        "massage-ball-chest": Technique(
            setup: ["Stand facing a wall", "Ball just under the collarbone, near the front of the shoulder"],
            position: [
                Checkpoint(.shoulders, "Lean into the wall to pin the ball on the chest"),
                Checkpoint(.hands, "Slide the hand slowly up the wall and back down"),
                Checkpoint(.feet, "A small step back so you can lean in"),
            ],
            mistakes: ["Pressing on the collarbone or the armpit", "Moving the arm fast", "Leaning in so hard it hurts"],
            breathing: "Calm breaths, exhale as the arm moves"
        ),
        "massage-ball-glute": Technique(
            setup: ["Sit on the floor with the ball under one glute", "Hands behind you, knees bent"],
            position: [
                Checkpoint(.hips, "Lean onto the ball side, find a tender spot"),
                Checkpoint(.hands, "Planted behind, control how much weight goes on the ball"),
                Checkpoint(.feet, "Cross the ankle over the other knee to go deeper"),
            ],
            mistakes: ["Sitting on the tailbone or a bony point", "Rolling around without pausing", "Tensing up against the pressure"],
            breathing: "Exhale slowly and let the hip sink into the ball"
        ),
        "massage-ball-foot": Technique(
            setup: ["Stand tall next to a wall or support", "Ball under the arch of one foot"],
            position: [
                Checkpoint(.feet, "Roll slowly from the heel to the toes"),
                Checkpoint(.knees, "Soft, lean in to add pressure"),
                Checkpoint(.hips, "Level, most weight on the standing leg"),
            ],
            mistakes: ["Putting all the body weight on the ball", "Rolling too fast", "Standing on the ball with the heel bone only"],
            breathing: "Relaxed breathing throughout"
        ),

        // MARK: Mat mobility and stretches
        "windshield-wipers": Technique(
            setup: ["Sit with knees bent and feet wider than the hips", "Hands on the floor behind you"],
            position: [
                Checkpoint(.knees, "Drop both knees to one side, then to the other"),
                Checkpoint(.feet, "Stay planted where they started"),
                Checkpoint(.back, "Tall chest, lean slightly back on the hands"),
            ],
            mistakes: ["Rushing from side to side", "Feet sliding in", "Slumping the chest"],
            breathing: "Exhale as the knees drop, inhale back to the middle"
        ),
        "straddle-stretch": Technique(
            setup: ["Sit with the legs wide, knees and toes pointing up", "Hands on the floor in front"],
            position: [
                Checkpoint(.hips, "Tip the pelvis forward to start the hinge"),
                Checkpoint(.back, "Long, lead with the chest, not the head"),
                Checkpoint(.hands, "Walk forward only as far as the back stays long"),
                Checkpoint(.knees, "Straight, kneecaps to the ceiling"),
            ],
            mistakes: ["Rounding the back to get lower", "Knees rolling in", "Bouncing"],
            breathing: "Exhale to walk the hands out, breathe slowly in the hold"
        ),
        "downward-dog": Technique(
            setup: ["Start in a high plank, hands shoulder-width", "Push the hips up and back into an upside-down V"],
            position: [
                Checkpoint(.hands, "Spread fingers, press the floor away"),
                Checkpoint(.back, "Long spine from hands to hips"),
                Checkpoint(.hips, "High, reaching up and back"),
                Checkpoint(.feet, "Hip-width, heels sinking toward the floor"),
            ],
            mistakes: ["Rounding the back to get the heels down", "Shoulders shrugged to the ears", "Feet too close to the hands"],
            breathing: "Slow, deep breaths through the nose"
        ),
        "warrior-2": Technique(
            setup: ["Wide stance, front foot forward, back foot turned in slightly", "Arms out at shoulder height"],
            position: [
                Checkpoint(.knees, "Front knee bent, stacked over the ankle"),
                Checkpoint(.hips, "Open to the side, sink low"),
                Checkpoint(.shoulders, "Relaxed down, arms long"),
                Checkpoint(.head, "Gaze over the front hand"),
            ],
            mistakes: ["Front knee caving in", "Leaning the torso over the front leg", "Back leg bending"],
            breathing: "Steady breaths, stay tall on the inhale"
        ),
        "brettzel": Technique(
            setup: ["Lie on your side, top knee forward to hip height and resting on the floor", "Bend the bottom knee and hold that foot with the top hand"],
            position: [
                Checkpoint(.hands, "Bottom hand holds the top knee down"),
                Checkpoint(.knees, "Top knee stays pinned to the floor"),
                Checkpoint(.shoulders, "Rotate the chest open toward the ceiling"),
                Checkpoint(.hips, "Bottom foot pulled back to stretch the front of the hip"),
            ],
            mistakes: ["Top knee lifting off the floor", "Forcing the rotation", "Arching the lower back to reach the foot"],
            breathing: "Exhale to rotate a little further each breath"
        ),
        "adductor-rock-back": Technique(
            setup: ["On all fours, hands under shoulders", "Straighten one leg out to the side, foot flat"],
            position: [
                Checkpoint(.hips, "Rock back toward the heel until the inner thigh stretches"),
                Checkpoint(.back, "Flat, no rounding at the end of the range"),
                Checkpoint(.feet, "Whole foot stays on the floor"),
            ],
            mistakes: ["Rounding the lower back to go further", "Bending the straight leg", "Bouncing at the end"],
            breathing: "Exhale as you rock back, inhale forward"
        ),
        "boat-pose": Technique(
            setup: ["Sit with knees bent, feet on the floor", "Lean back slightly and lift the feet"],
            position: [
                Checkpoint(.hips, "Balance on the sit bones"),
                Checkpoint(.back, "Chest tall, no slumping"),
                Checkpoint(.knees, "Shins level, or legs straight when strong enough"),
                Checkpoint(.hands, "Arms reach forward at shoulder height"),
            ],
            mistakes: ["Rounding the back", "Rolling onto the tailbone", "Holding the breath"],
            breathing: "Short, steady breaths while bracing the core"
        ),
    ]
}
