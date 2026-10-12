// Technique content for the gym app comparison (#182): sandbag, sliders and BOSU.

extension Technique {
    static let gymProps: [String: Technique] = [
        // MARK: Sandbag
        "sandbag-squat": Technique(
            setup: ["Stand the bag on end, hug it and lift it to the chest", "Feet shoulder-width, toes turned out slightly"],
            position: [
                Checkpoint(.hands, "Arms wrapped around the bag, hands clasped or gripping the far side"),
                Checkpoint(.elbows, "Tucked under the bag, pointing down"),
                Checkpoint(.back, "Tall chest, bag stays pressed to the sternum"),
                Checkpoint(.knees, "Track over the toes as you sit between the heels"),
            ],
            mistakes: ["Letting the bag slide down to the belly", "Rounding the upper back under the load", "Heels lifting at the bottom"],
            breathing: "Big breath and brace before you sit down, exhale as you stand"
        ),
        "sandbag-shouldering": Technique(
            setup: ["Bag lying across between your feet, feet a little wider than the hips", "Squat down and wrap both arms under and around the bag"],
            position: [
                Checkpoint(.hips, "Pull the bag up onto the lap first, then drive the hips through hard"),
                Checkpoint(.hands, "Bear-hug the bag as it rolls up the chest"),
                Checkpoint(.shoulders, "Dip and catch the bag on one shoulder, alternate each rep"),
                Checkpoint(.back, "Flat during the lap, upright at the finish"),
            ],
            mistakes: ["Trying to curl the bag up with the arms", "Pulling with a rounded back from the floor", "Always using the same shoulder"],
            breathing: "Brace before the pick, exhale as the bag lands on the shoulder"
        ),
        "sandbag-lunge": Technique(
            setup: ["Lift the bag into the crooks of the elbows, hands together in front", "Stand tall, feet hip-width"],
            position: [
                Checkpoint(.elbows, "Bent, bag held in the elbow crease close to the body"),
                Checkpoint(.back, "Torso tall, no leaning over the front leg"),
                Checkpoint(.knees, "Back knee lowers toward the floor, front knee over the mid-foot"),
                Checkpoint(.feet, "Long step back, push through the front heel to return"),
            ],
            mistakes: ["Bag drifting away from the chest", "Short step that drives the front knee far forward", "Torso collapsing forward"],
            breathing: "Inhale as you step back and lower, exhale as you drive up"
        ),
        // MARK: Sliders
        "slider-leg-curl": Technique(
            setup: ["Lie on your back on a mat, heels on the sliders, legs nearly straight", "Arms on the floor by your sides, lift the hips into a bridge"],
            position: [
                Checkpoint(.hips, "Stay up for the whole set, no sagging as the legs straighten"),
                Checkpoint(.feet, "Heels dig into the sliders, toes pointing up"),
                Checkpoint(.knees, "Pull the heels toward the glutes until the shins are near vertical"),
                Checkpoint(.core, "Ribs down, no arching the lower back"),
            ],
            mistakes: ["Hips dropping to the floor between reps", "Shooting the legs out fast", "Pushing up through the lower back instead of the glutes"],
            breathing: "Exhale as you curl in, inhale as you slide out slowly"
        ),
        "slider-lateral-lunge": Technique(
            setup: ["Stand tall with one foot on a slider, feet hip-width", "Hands together in front of the chest"],
            position: [
                Checkpoint(.feet, "Slide the slider foot straight out to the side, standing foot flat"),
                Checkpoint(.hips, "Sit back and down into the standing hip"),
                Checkpoint(.knees, "Standing knee tracks over the toes, sliding leg stays straight"),
                Checkpoint(.back, "Chest up, spine long"),
            ],
            mistakes: ["Bending the sliding leg instead of the standing one", "Standing knee caving in", "Pulling back in with momentum instead of the inner thigh"],
            breathing: "Inhale as you slide out, exhale as you pull back in"
        ),
        "slider-reverse-lunge": Technique(
            setup: ["Ball of the back foot on a slider, feet hip-width", "Hands on the hips, weight on the front foot"],
            position: [
                Checkpoint(.feet, "Slide the back foot straight back, front foot stays flat"),
                Checkpoint(.knees, "Lower until the back knee nearly touches the floor"),
                Checkpoint(.back, "Torso tall with a slight forward lean"),
                Checkpoint(.hips, "Square to the front, drive up through the front heel"),
            ],
            mistakes: ["Putting weight on the sliding foot", "Front heel lifting", "Hips twisting open"],
            breathing: "Inhale as you slide back, exhale as you stand"
        ),
        // MARK: BOSU
        "bosu-squat": Technique(
            setup: ["Flip the BOSU dome-down, step on with one foot then the other", "Feet wide near the edges of the flat side, find your balance first"],
            position: [
                Checkpoint(.feet, "Wide and even on the platform, keep it level"),
                Checkpoint(.knees, "Track over the toes, no caving in"),
                Checkpoint(.hips, "Sit back and down slowly, arms forward for balance"),
                Checkpoint(.core, "Braced to stop the platform rocking"),
            ],
            mistakes: ["Rushing the reps and losing balance", "Platform tipping to one side", "Knees falling inward"],
            breathing: "Inhale as you lower, exhale as you stand"
        ),
        "bosu-push-up": Technique(
            setup: ["Flip the BOSU dome-down, grip the edges of the flat side", "Walk the feet back to a straight plank"],
            position: [
                Checkpoint(.hands, "Grip the platform edges, wrists under the shoulders"),
                Checkpoint(.elbows, "About 45 degrees from the body on the way down"),
                Checkpoint(.core, "Body straight from heels to head, platform stays level"),
                Checkpoint(.shoulders, "Lower until the chest nearly touches the platform"),
            ],
            mistakes: ["Letting the platform tip side to side", "Hips sagging", "Cutting the range short"],
            breathing: "Inhale as you lower, exhale as you push away"
        ),
    ]
}
