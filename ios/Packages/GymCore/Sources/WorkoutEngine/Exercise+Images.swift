import Foundation

/// Exercise illustrations from free-exercise-db (https://github.com/yuhonas/free-exercise-db),
/// released into the public domain under the Unlicense. Each mapped exercise has two frames:
/// `0.jpg` (start position) and `1.jpg` (end position).
///
/// URLs are pinned to one commit of that repository so the pictures can't change under us.
/// Only exercises whose picture shows genuinely the same movement (equipment + movement) are mapped;
/// every other exercise has one of the app's own illustrations (`ExerciseIllustrations`).
/// Source + license of each exercise's media: ios/EXERCISE_MEDIA.md.
public enum ExerciseImages {
    /// Credit line shown wherever an illustration is displayed in full.
    public static let attribution = "Image: free-exercise-db (public domain)"
    public static let sourceURL = URL(string: "https://github.com/yuhonas/free-exercise-db")!
    /// Commit of yuhonas/free-exercise-db the image URLs are pinned to.
    public static let commit = "f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5"
    /// Frames per illustration (start + end position).
    public static let frameCount = 2

    static let baseURL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/\(commit)/exercises/"

    /// URL of one frame (0 or 1) of a free-exercise-db exercise.
    public static func url(imageId: String, frame: Int) -> URL? {
        guard !imageId.isEmpty, (0..<frameCount).contains(frame) else { return nil }
        return URL(string: baseURL + imageId + "/\(frame).jpg")
    }

    /// Our exercise id → free-exercise-db exercise id (its folder name under `exercises/`).
    static let ids: [String: String] = [
        "back-squat":              "Barbell_Squat",
        "front-squat":             "Front_Barbell_Squat",
        "goblet-squat":            "Goblet_Squat",
        "hack-squat":              "Hack_Squat",
        "leg-press":               "Leg_Press",
        "deadlift":                "Barbell_Deadlift",
        "trap-bar-deadlift":       "Trap_Bar_Deadlift",
        "rdl":                     "Romanian_Deadlift",
        "db-rdl":                  "Stiff-Legged_Dumbbell_Deadlift",
        "hip-thrust":              "Barbell_Hip_Thrust",
        "back-extension":          "Hyperextensions_Back_Extensions",
        "cable-pull-through":      "Pull_Through",
        "bulgarian-split-squat":   "Split_Squat_with_Dumbbells",
        "reverse-lunge":           "Dumbbell_Rear_Lunge",
        "walking-lunge":           "Dumbbell_Lunges",
        "step-up":                 "Dumbbell_Step_Ups",
        "single-leg-rdl":          "Kettlebell_One-Legged_Deadlift",
        "leg-curl":                "Lying_Leg_Curls",
        "nordic-curl":             "Floor_Glute-Ham_Raise",
        "leg-extension":           "Leg_Extensions",
        "bench-press":             "Barbell_Bench_Press_-_Medium_Grip",
        "db-bench":                "Dumbbell_Bench_Press",
        "incline-db-press":        "Incline_Dumbbell_Press",
        "chest-press-machine":     "Machine_Bench_Press",
        "push-up":                 "Pushups",
        "dips":                    "Dips_-_Chest_Version",
        "cable-fly":               "Cable_Crossover",
        "ohp":                     "Standing_Military_Press",
        "seated-db-press":         "Seated_Dumbbell_Press",
        "arnold-press":            "Arnold_Dumbbell_Press",
        "barbell-row":             "Bent_Over_Barbell_Row",
        "chest-supported-row":     "Dumbbell_Incline_Row",
        "seated-cable-row":        "Seated_Cable_Rows",
        "one-arm-db-row":          "One-Arm_Dumbbell_Row",
        "inverted-row":            "Inverted_Row_with_Straps",
        "pull-up":                 "Pullups",
        "weighted-pull-up":        "Weighted_Pull_Ups",
        "lat-pulldown":            "Wide-Grip_Lat_Pulldown",
        "single-arm-pulldown":     "One_Arm_Lat_Pulldown",
        "plank":                   "Plank",
        "dead-bug":                "Dead_Bug",
        "ab-wheel":                "Ab_Roller",
        "pallof-press":            "Pallof_Press",
        "side-plank":              "Side_Bridge",
        "landmine-rotation":       "Landmine_180s",
        "toes-to-bar":             "Hanging_Pike",
        "cable-crunch":            "Cable_Crunch",
        "farmer-carry":            "Farmers_Walk",
        "db-curl":                 "Dumbbell_Bicep_Curl",
        "hammer-curl":             "Hammer_Curls",
        "cable-curl":              "Standing_Biceps_Cable_Curl",
        "triceps-pushdown":        "Triceps_Pushdown",
        "overhead-triceps":        "Cable_Rope_Overhead_Triceps_Extension",
        "db-lateral-raise":        "Side_Lateral_Raise",
        "cable-lateral-raise":     "Standing_Low-Pulley_Deltoid_Raise",
        "face-pull":               "Face_Pull",
        "cable-external-rotation": "External_Rotation_with_Cable",
        "band-pull-apart":         "Band_Pull_Apart",
        "reverse-pec-deck":        "Reverse_Machine_Flyes",
        "scap-pull-up":            "Scapular_Pull-Up",
        "standing-calf-raise":     "Smith_Machine_Calf_Raise",
        "db-calf-raise":           "Standing_Dumbbell_Calf_Raise",
        "reverse-wrist-curl":      "Seated_Dumbbell_Palms-Down_Wrist_Curl",
        "box-jump":                "Front_Box_Jump",
        "broad-jump":              "Standing_Long_Jump",
        "squat-jump":              "Freehand_Jump_Squat",
        "lateral-bound":           "Lateral_Bound",
        "depth-jump":              "Linear_Depth_Jump",
        "med-ball-chest-pass":     "Medicine_Ball_Chest_Pass",
        "ball-slam":               "Overhead_Slam",
        "battle-rope-slams":       "Battling_Ropes",
        "overhead-back-throw":     "Backward_Medicine_Ball_Throw",
        "kb-swing":                "One-Arm_Kettlebell_Swings",
        "kb-snatch":               "One-Arm_Kettlebell_Snatch",
        "hang-power-clean":        "Hang_Clean",
        "sled-sprint":             "Prowler_Sprint",
        "plyo-push-up":            "Plyo_Push-up",
        "rower":                   "Rowing_Stationary",
        "bike":                    "Bicycling_Stationary",
        "treadmill-run":           "Running_Treadmill",
        "incline-walk":            "Walking_Treadmill",
        "stair-climber":           "Stairmaster",
        "elliptical":              "Elliptical_Trainer",
        "worlds-greatest":         "Worlds_Greatest_Stretch",
        "leg-swings":              "Front_Leg_Raises",
        "inchworm":                "Inchworm",
        "cat-cow":                 "Cat_Stretch",
        "glute-bridge":            "Butt_Lift_Bridge",
        "arm-circles":             "Arm_Circles",
        "hip-car":                 "Standing_Hip_Circles",
        "wrist-car":               "Wrist_Circles",
        "childs-pose-reach":       "Childs_Pose",
        "cross-body":              "Shoulder_Stretch",
        "triceps-stretch":         "Triceps_Stretch",
        "forearm-flexor":          "Kneeling_Forearm_Stretch",
        "half-kneeling-hf":        "Kneeling_Hip_Flexor",
        "hamstring-stretch":       "Hamstring_Stretch",
        "figure-4":                "Ankle_On_The_Knee",
        "butterfly":               "Groin_and_Back_Stretch",
        "calf-wall":               "Calf_Stretch_Hands_Against_Wall",
        "supine-twist":            "Knee_Across_The_Body",
        "side-bend":               "Standing_Lateral_Stretch",
        "behind-back-clasp":       "Standing_Biceps_Stretch",
        "upper-trap":              "Side_Neck_Stretch",
        "barbell-curl":            "Barbell_Curl",
        "incline-db-curl":         "Incline_Dumbbell_Curl",
        "barbell-french-press":    "Lying_Triceps_Press",
        "db-french-press":         "Lying_Dumbbell_Tricep_Extension",
        "db-reverse-fly":          "Bent_Over_Dumbbell_Rear_Delt_Raise_With_Head_On_Bench",
        "diamond-push-up":         "Push-Ups_-_Close_Triceps_Position",
        "seated-calf-raise":       "Seated_Calf_Raise",
        "hip-adduction":           "Thigh_Adductor",
        "hip-abduction":           "Thigh_Abductor",
        "crunch-machine":          "Ab_Crunch_Machine",
    ]
}

extension Exercise {
    /// free-exercise-db id of this exercise's illustration; nil when no picture matches the movement.
    public var imageId: String? { ExerciseImages.ids[id] }

    /// Illustration frames (start, end), pinned to `ExerciseImages.commit`. Empty when unmapped.
    public var imageURLs: [URL] {
        guard let imageId else { return [] }
        return (0..<ExerciseImages.frameCount).compactMap { ExerciseImages.url(imageId: imageId, frame: $0) }
    }
}

extension Exercise {
    /// True when the exercise uses one of the app's own illustrations (no matching photo).
    public var hasIllustration: Bool { imageId == nil && ExerciseIllustrations.ids.contains(id) }

    /// Asset names of the illustration frames (start, end). Empty when the exercise has a photo instead.
    public var illustrationAssets: [String] {
        guard hasIllustration else { return [] }
        return (0..<ExerciseIllustrations.frameCount).map { ExerciseIllustrations.assetName(id, frame: $0) }
    }

    /// Every catalog exercise has a photo or an illustration.
    public var hasMedia: Bool { imageId != nil || hasIllustration }
}
