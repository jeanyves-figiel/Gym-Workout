import Foundation

/// How it works (#769, design A from `methodology-page/proposals.png`): every number the app computes for the
/// member, in plain words, with its formula and sources, so they can check where it comes from and say when it
/// feels off. Constants are read from the code that uses them, so the page can't drift from the app.
public enum HowItWorks {
    public struct Topic: Identifiable, Sendable, Hashable {
        public let id: String
        public let title: String
        public let symbol: String
        /// One line on the deck card.
        public let summary: String
        /// Gradient, top leading → bottom trailing.
        public let colors: [UInt32]
        /// Where the member meets these numbers in the app.
        public let shows: String
        public let parts: [Part]
        public let sources: [String]
    }

    /// One calculation: what it does in words, then the rule as short lines.
    public struct Part: Sendable, Hashable {
        public let title: String
        public let text: String
        public let rule: [String]

        public init(_ title: String, _ text: String, rule: [String] = []) {
            self.title = title
            self.text = text
            self.rule = rule
        }
    }

    public static func topic(_ id: String) -> Topic? { topics.first { $0.id == id } }

    public static let topics: [Topic] = [xp, move, streaks, plan, methods, load, warmup, readiness, growth, zones, effort,
                                         cardio, fuel, water, caffeine, recovery, pain, lifeStage, body, form, mind, coach]

    /// Sources starting with this are the app's own choices, not backed by a study (#976: each one is tracked on
    /// GitHub until a study backs it or the rule changes). Every topic still names at least one study.
    public static let appDesign = "App design:"

    // MARK: Game

    static let xp = Topic(
        id: "xp", title: "XP & levels", symbol: "star.fill",
        summary: "\(GameProgress.perWorkout) + \(GameProgress.perSet) a set · \(GameProgress.perLevel) XP a level",
        colors: [0x7C3AED, 0xEC4899],
        shows: "Me sheet level bar, Levels, finish sheet, week chest",
        parts: [
            Part("Workout XP", "Every finished workout earns XP from the sets you did. Short sessions still count: a 20-minute Express earns as much as a 10-set session.",
                 rule: ["XP = max(\(GameProgress.minWorkoutXP), \(GameProgress.perWorkout) + \(GameProgress.perSet) × sets done)"]),
            Part("Week chest", "The first time a week reaches your sessions-a-week goal, its chest opens.",
                 rule: ["goal met = +\(GameProgress.weekBonus) XP, once a week"]),
            Part("Comeback quest", "After \(Comeback.gapDays)+ days without training, your first \(Comeback.sessions) sessions back within \(Comeback.windowDays) days earn a bonus.",
                 rule: ["+\(Comeback.xpPerSession) XP per quest session"]),
            Part("Walking", "Daily Move adds XP from steps and stairs (see Daily Move).", rule: []),
            Part("Level and rank", "Levels are equal steps of XP, ranks are names for level bands.",
                 rule: ["level = XP ÷ \(GameProgress.perLevel) + 1",
                        "Rookie 1–2 · Regular 3–7 · Iron 8–14 · Steel 15–24 · Titan 25–39 · Legend 40+"]),
        ],
        sources: ["Mazeas A, Duclos M, Pereira B, Chalabaev A. Evaluating the effectiveness of gamification on physical activity: systematic review and meta-analysis of randomized controlled trials. J Med Internet Res 2022;24(1):e26779 (points, levels and rewards raise activity a little in the short run).",
                  "App design: the XP values are tuned so walking never outweighs a workout and every session counts."])

    static let move = Topic(
        id: "move", title: "Daily Move", symbol: "figure.walk",
        summary: "Steps and stairs vs your own usual",
        colors: [0x22C55E, 0x84CC16],
        shows: "Train Daily Move tile, slow-day nudge, XP",
        parts: [
            Part("Your usual", "Measured against you, not a fixed 10,000. Needs 3 days with steps; until then a typical day is used.",
                 rule: ["usual = median steps of the last \(DailyMove.usualWindow) days with steps",
                        "never under \(DailyMove.usualFloor) · \(DailyMove.fallbackUsual) until known"]),
            Part("Walking XP", "Steps and floors from Apple Health earn XP, capped so walking never outweighs a workout.",
                 rule: ["\(DailyMove.xpPerThousandSteps) XP per 1,000 steps + \(DailyMove.xpPerFloor) XP per floor",
                        "max \(DailyMove.dailyCap) XP a day",
                        "\(DailyMove.activeWeekDays) days at your usual in a week = +\(DailyMove.activeWeekBonus) XP"]),
            Part("Slow-day nudge", "One quiet reminder, only when you are well behind at the hour you usually walk (between \(DailyMove.earliestHour):00 and \(DailyMove.latestHour):00; \(DailyMove.defaultHour):00 until known).",
                 rule: ["nudge when steps < \(Int(DailyMove.behindShare * 100)) % of usual so far and ≥ \(DailyMove.minGap) short",
                        "minutes to walk = steps short ÷ \(DailyMove.stepsPerMinute)"]),
        ],
        sources: ["Paluch AE et al. Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts. Lancet Public Health 2022;7(3):e219-e228."])

    static let streaks = Topic(
        id: "streaks", title: "Streaks & badges", symbol: "flame.fill",
        summary: "Goal weeks in a row, shields, milestones",
        colors: [0xDB2777, 0x7C3AED],
        shows: "Insights, Levels, badges, finish sheet",
        parts: [
            Part("Week streak", "A week counts when you reach your sessions-a-week goal. The running week never breaks the streak.",
                 rule: ["1 shield every \(StreakRun.weeksPerShield) goal weeks in a row, \(StreakRun.maxShields) held at most",
                        "missed week: a shield saves it, else the streak restarts"]),
            Part("Badges", "Milestones from your history: sessions (1, 10, 25, 50, 100), streaks (2, 4, 8 weeks), total lifted (10, 50, 100 t = sets × reps × kg), hours trained (10, 50), beaten bests (1, 10), 100 shoulder-health sets, and one-offs like a full 4-week cycle.",
                 rule: []),
            Part("Personal bests", "A best is beaten when a set is heavier than any before for that exercise, whatever the reps. Strength trends use the estimated 1RM (see Load).", rule: []),
        ],
        sources: ["Lally P, van Jaarsveld CHM, Potts HWW, Wardle J. How are habits formed: modelling habit formation in the real world. Eur J Soc Psychol 2010;40(6):998-1009 (missing one chance did not undo a habit, hence shields).",
                  "Mazeas A et al. Evaluating the effectiveness of gamification on physical activity. J Med Internet Res 2022;24(1):e26779.",
                  "App design: badge milestones and the shield rate."])

    // MARK: Training

    static let plan = Topic(
        id: "plan", title: "Your plan", symbol: "calendar",
        summary: "\(Generator.mesocycleWeeks)-week blocks, split, session length, dose",
        colors: [0x8A3DF0, 0xFF4D8A],
        shows: "Train week, day cards, My plan",
        parts: [
            Part("4-week block", "Plans run in \(Generator.mesocycleWeeks)-week blocks so effort builds, then fatigue drops.",
                 rule: (1...Generator.mesocycleWeeks).map { "Week \($0): \(Generator.weekLabel($0))" }),
            Part("Split", "How the week is cut depends on sessions a week; each movement pattern gets at least 2 sessions a week.",
                 rule: ["2–3×: full body · 4×: upper / lower", "5×: upper / lower + conditioning · 6×: push / pull / legs"]),
            Part("Session length", "Fewer sessions are longer; total weekly time still grows with frequency.",
                 rule: ["minutes = goal base × frequency factor ± experience − climbing",
                        "factor: " + Rules.frequencyFactor.sorted { $0.key < $1.key }.map { "\($0.key)× \(fmt($0.value))" }.joined(separator: " · "),
                        "beginner −10 · advanced +10 · −2 per climbing day after the first",
                        "kept \(Rules.minSession)–\(Rules.maxSession) min, rounded to 5, under your own cap"]),
            Part("Dose by goal", "Your goal sets sets × reps, rest and target effort for the main lift and accessories.",
                 rule: Goal.allCases.map { g in
                     let c = g.config
                     return "\(c.label): \(c.main.sets)×\(c.main.reps) @ RPE \(c.main.rpe), \(c.main.restSec) s · \(c.accessory.sets)×\(c.accessory.reps)"
                 }),
            Part("Effort scale", "Effort is RPE (1–10) or reps left in the tank (RIR).",
                 rule: ["RIR = 10 − RPE"]),
            Part("Missed sessions", "A session planned before today and not done is missed; Next up is the first not-done session from today on.", rule: []),
        ],
        sources: ["Williams TD et al. Comparison of periodized and non-periodized resistance training on maximal strength: a meta-analysis. Sports Med 2017;47(10):2083-2100.",
                  "Bell L et al. Integrating deloading into strength and physique sports training programmes: an international Delphi consensus approach. Sports Med Open 2023;9:87.",
                  "Helms ER, Cronin J, Storey A, Zourdos MC. Application of the repetitions in reserve-based RPE scale for resistance training. Strength Cond J 2016;38(4):42-49.",
                  "Schoenfeld BJ, Ogborn D, Krieger JW. Effects of resistance training frequency on measures of muscle hypertrophy: a systematic review and meta-analysis. Sports Med 2016;46(11):1689-1697 (each muscle at least twice a week).",
                  "Schoenfeld BJ, Grgic J, Ogborn D, Krieger JW. Strength and hypertrophy adaptations between low- vs. high-load resistance training: a systematic review and meta-analysis. J Strength Cond Res 2017;31(12):3508-3523 (heavy for strength, any load near failure for muscle).",
                  "Grgic J, Schoenfeld BJ, Skrepnik M, Davies TB, Mikulic P. Effects of rest interval duration in resistance training on measures of muscular strength: a systematic review. Sports Med 2018;48(1):137-151 (longer rests on heavy lifts).",
                  "American College of Sports Medicine. Progression models in resistance training for healthy adults. Med Sci Sports Exerc 2009;41(3):687-708.",
                  "App design: the session-length factors."])

    static let methods = Topic(
        id: "methods", title: "Training methods", symbol: "slider.horizontal.3",
        summary: "How load and volume change over the block",
        colors: [0x6366F1, 0xA855F7],
        shows: "My plan → Method",
        parts: TrainingMethod.allCases.map { Part($0.label, $0.detail, rule: [$0.blurb]) }
            + [Part("Volume targets", "Volume progression counts hard sets per major muscle per week.",
                    rule: ["Base \(VolumeTargets.byPhase[0]) · Build \(VolumeTargets.byPhase[1]) · Peak \(VolumeTargets.byPhase[2]) · Deload \(VolumeTargets.byPhase[3]) sets",
                           "max \(Int(VolumeTargets.perSessionCap)) hard sets per muscle per session"])],
        sources: ["Sources are named in each method above."])

    static let load = Topic(
        id: "load", title: "Load & progression", symbol: "scalemass.fill",
        summary: "Starting load, double progression, 1RM",
        colors: [0xF97316, 0xEF4444],
        shows: "Player weight suggestions, exercise history, PRs",
        parts: [
            Part("Starting load", "Never logged? From a related lift you did log (bench → incline), else from your body. Deliberately light: the first session calibrates, it doesn't test.",
                 rule: ["1RM ≈ body kg × pattern ratio × sex × level × age × implement",
                        "sex (upper / lower): men 1 · women 0.6 / 0.75",
                        "level: beginner 0.65 · intermediate 1 · advanced 1.3",
                        "age: −1 % a year after 40 (min 0.7) · under 18: 0.85",
                        "lean mass ±\(Int(StartingLoad.maxLeanShift * 100)) % · arm / thigh girth ±\(Int(StartingLoad.maxGirthShift * 100)) %",
                        "load = 1RM ÷ (1 + (reps + RIR) ÷ 30) × 0.85, rounded down"]),
            Part("Double progression", "Reps first, then load.",
                 rule: ["all sets at the top of the range → +1 step (+2 if every set had ≥ 4 RIR, not in Base week)",
                        "best set under the range → −5 %",
                        "else same load, one more rep",
                        "deload week → −10 % · back after \(Int(LoadAdvisor.easeInDays)) days off the lift → −10 %"]),
            Part("Steps", "The smallest jump per kit.",
                 rule: ["barbell 2.5 kg · dumbbells 1 kg (< 10 kg) or 2 kg · kettlebell 4 kg · machines and cables 2.5 kg"]),
            Part("Estimated 1RM", "Used for bests, Growth and PR attempts, from sets of 1–12 reps.",
                 rule: ["1RM = kg × (1 + reps ÷ 30)  (Epley)"]),
        ],
        sources: ["LeSuer DA, McCormick JH, Mayhew JL, Wasserstein RL, Arnold MD. The accuracy of prediction equations for estimating 1-RM performance in the bench press, squat, and deadlift. J Strength Cond Res 1997;11(4):211-213 (Epley among the closest under 10 reps).",
                  "Epley B. Poundage chart. Boyd Epley Workout. Lincoln, NE: Body Enterprises; 1985.",
                  "Miller AE, MacDougall JD, Tarnopolsky MA, Sale DG. Gender differences in strength and muscle fiber characteristics. Eur J Appl Physiol Occup Physiol 1993;66(3):254-262 (women about 52 % of men's upper and 66 % of lower-body strength).",
                  "Keller K, Engelhardt M. Strength and muscle mass loss with aging process. Age and strength loss. Muscles Ligaments Tendons J 2013;3(4):346-350.",
                  "Mujika I, Padilla S. Detraining: loss of training-induced physiological and performance adaptations. Part I. Sports Med 2000;30(2):79-87 (strength dips after weeks off, hence −10 %).",
                  "App design: the pattern and level ratios, set light on purpose; the first session calibrates.",
                  "Helms ER et al. RPE vs. percentage 1RM loading in periodized programs matched for sets and repetitions. Front Physiol 2018;9:247.",
                  "Graham T, Cleather DJ. Autoregulation by \"repetitions in reserve\" leads to greater improvements in strength over a 12-week training program than fixed loading. J Strength Cond Res 2021;35(9):2451-2456."])

    static let warmup = Topic(
        id: "warmup", title: "Warm-up & PR tests", symbol: "flame",
        summary: "Raise, drills, then a ramp to the top set",
        colors: [0xF59E0B, 0xEF4444],
        shows: "Every workout's warm-up, Test a PR",
        parts: [
            Part("Warm-up", "Every workout starts with a few easy minutes on a cardio machine that suits the day (rower or bike), then drills that wake up the joints the session loads (glutes, shoulder blades, rotator cuff). You can pick drills only, activation, or your own moves.",
                 rule: ["raise (easy cardio) → mobility and activation drills → the first lift's lighter sets"]),
            Part("PR test ramp", "Before a 1RM or rep-max test you build up in lighter sets, fewer reps as the weight climbs, so the attempt is warm but not tired.",
                 rule: ["1RM: 40 % × 8 · 55 % × 5 · 70 % × 3 · 80 % × 2 · 90 % × 1",
                        "3RM / 5RM: 40 % × 8 · 60 % × 5 · 75 % × 3 · 85 % × 1",
                        "max reps: 50 % × 8 · 70 % × 3",
                        "\(PRPlanner.maxAttempts) attempts at most · target = best + one step, or from your estimated 1RM"]),
            Part("Safety", "Each test names its own safety cue: pins or a spotter for bench and squat, drop a deadlift rather than grind it. A failed rep is fine, an injury is not.", rule: []),
        ],
        sources: ["Fradkin AJ, Zazryn TR, Smoliga JM. Effects of warming-up on physical performance: a systematic review with meta-analysis. J Strength Cond Res 2010;24(1):140-148 (warming up improved performance in 79 % of criteria).",
                  "McCrary JM, Ackermann BJ, Halaki M. A systematic review of the effects of upper body warm-up on performance and injury. Br J Sports Med 2015;49(14):935-942.",
                  "Grgic J, Lazinica B, Schoenfeld BJ, Pedisic Z. Test-retest reliability of the one-repetition maximum (1RM) strength assessment: a systematic review. Sports Med Open 2020;6:31 (tested with a graded warm-up ramp).",
                  "App design: the exact ramp percentages, in line with common 1RM test protocols."])

    static let readiness = Topic(
        id: "readiness", title: "Readiness & auto-tune", symbol: "heart.text.square.fill",
        summary: "HRV, resting HR, sleep, soreness → today",
        colors: [0x10B981, 0x0EA5E9],
        shows: "Train readiness pill, Auto-tune card",
        parts: [
            Part("Auto-tune score", "Starts at \(AutoTune.base); each factor adds or takes points. Health values are compared with your own normal.",
                 rule: ["HRV: 7-day average % vs 30-day normal, −30…+10 (a single reading is too noisy)",
                        "resting HR: −3 per bpm over normal, −20…+5",
                        "sleep: −10 per hour under 7 h (max −25), +5 from 8 h",
                        "last workout near failure (RIR ≤ 1) −8 · easy (RIR ≥ 3) +3",
                        "days in a row: −6 per day after the first (max −12)",
                        "sore muscle groups: −6 each (max −18)",
                        "score kept 5–100"]),
            Part("Today's level", "What the score does to today's session. Every change can be undone.",
                 rule: ["< \(AutoTune.lightBelow): \(TuneLevel.light.title), \(TuneLevel.light.rule)",
                        "\(AutoTune.lightBelow)–\(AutoTune.pushFrom - 1): \(TuneLevel.medium.title), \(TuneLevel.medium.rule)",
                        "≥ \(AutoTune.pushFrom) with Health data: \(TuneLevel.push.title), \(TuneLevel.push.rule)",
                        "sore group: its moves swap to ones that spare it"]),
            Part("Readiness pill", "A quick read of Apple Health markers; advice only.",
                 rule: ["flags: 7-day HRV < 85 % of 30-day normal · resting HR > normal + 5 · sleep < 6 h",
                        "0 flags Ready · 1 Normal · 2+ Easy"]),
        ],
        sources: ["Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M. Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring. Sports Med 2013;43(9):773-781.",
                  "Fullagar HH et al. Sleep and athletic performance: the effects of sleep loss on exercise performance, and physiological and cognitive responses to exercise. Sports Med 2015;45(2):161-186.",
                  "Larsen S, Kristiansen E, van den Tillaar R. Effects of subjective and objective autoregulation methods for intensity and volume on enhancing maximal strength during resistance-training interventions: a systematic review. PeerJ 2021;9:e10663.",
                  "Kiviniemi AM, Hautala AJ, Kinnunen H, Tulppo MP. Endurance training guided individually by daily heart rate variability measurements. Eur J Appl Physiol 2007;101(6):743-751 (easier days when HRV drops beat a fixed plan).",
                  "Buchheit M. Monitoring training status with HR measures: do all roads lead to Rome? Front Physiol 2014;5:73 (resting HR up and HRV down as fatigue markers).",
                  "Watson NF et al. Recommended amount of sleep for a healthy adult: a joint consensus statement of the AASM and SRS. Sleep 2015;38(6):843-844 (7 h or more).",
                  "Cheung K, Hume P, Maxwell L. Delayed onset muscle soreness: treatment strategies and performance factors. Sports Med 2003;33(2):145-164 (sore muscles are weaker for days).",
                  "App design: the point values and the 85 % HRV and +5 bpm flags."])

    static let growth = Topic(
        id: "growth", title: "Block review & growth", symbol: "chart.line.uptrend.xyaxis",
        summary: "What each 4-week block changes next",
        colors: [0x0EA5E9, 0x6366F1],
        shows: "Growth path, block review, Lift lab",
        parts: [
            Part("Level up", "Each finished block is compared with the 4 weeks before it.",
                 rule: ["≥ \(Int(Growth.levelUpAdherence * 100)) % of planned sessions done and main lifts ≥ +\(Int(Growth.levelUpGain * 100)) % estimated 1RM → growth level +1 (needs 2+ workouts in the block)",
                        "growth level 3 → intermediate · 6 → advanced"]),
            Part("Plateau", "A lift is flat when 3 or more weekly bests in a row stay within 1 % of its best before; the next block swaps in a variation.", rule: []),
            Part("Lagging muscle", "A muscle group well behind its counterpart (e.g. back vs chest) is offered as a focus for the next block.",
                 rule: ["lagging = < \(Int(Growth.laggingRatio * 100)) % of its counterpart's hard sets (counterpart ≥ 12)"]),
            Part("Effort trending easy", "Flagged in the review when your logged sets end with 3+ reps in reserve on average (6+ sets logged).", rule: []),
        ],
        sources: ["Kraemer WJ, Ratamess NA. Fundamentals of resistance training: progression and exercise prescription. Med Sci Sports Exerc 2004;36(4):674-688.",
                  "Kassiano W et al. Does varying resistance exercises promote superior muscle hypertrophy and strength gains? A systematic review. J Strength Cond Res 2022;36(6):1753-1762 (swapping variations helps when gains stall).",
                  "Helms ER et al. Application of the repetitions in reserve-based RPE scale for resistance training. Strength Cond J 2016;38(4):42-49.",
                  "App design: the level-up, plateau and lagging thresholds."])

    // MARK: Heart and cardio

    static let zones = Topic(
        id: "zones", title: "Heart zones", symbol: "heart.fill",
        summary: "Heart-rate reserve, 208 − 0.7 × age",
        colors: [0x3D6BFF, 0x22D3EE],
        shows: "Player heart rate, Zone 2 week, run sessions",
        parts: [
            Part("Your zones", "Apple's zones are used when Health has all five; otherwise they come from your age and resting heart rate.",
                 rule: ["max HR = 208 − 0.7 × age",
                        "reserve = max HR − resting HR",
                        "zone 2…5 start at resting + 60 / 70 / 80 / 90 % of reserve",
                        "age unknown: 35 · resting HR unknown: 60"]),
            Part("Zone 2 week", "Easy aerobic minutes worth aiming for each week.",
                 rule: ["goal \(HeartZones.zone2Goal) min a week",
                        "each heart-rate reading counts until the next, at most 30 s"]),
        ],
        sources: ["Tanaka H, Monahan KD, Seals DR. Age-predicted maximal heart rate revisited. J Am Coll Cardiol 2001;37(1):153-156.",
                  "Karvonen MJ, Kentala E, Mustala O. The effects of training on heart rate; a longitudinal study. Ann Med Exp Biol Fenn 1957;35(3):307-315.",
                  "Bull FC et al. World Health Organization 2020 guidelines on physical activity and sedentary behaviour. Br J Sports Med 2020;54(24):1451-1462 (150 min a week).",
                  "Garber CE et al. American College of Sports Medicine position stand: quantity and quality of exercise for developing and maintaining cardiorespiratory, musculoskeletal, and neuromotor fitness in apparently healthy adults. Med Sci Sports Exerc 2011;43(7):1334-1359 (intensity by heart-rate reserve)."])

    static let effort = Topic(
        id: "effort", title: "Workout effort", symbol: "gauge.with.dots.needle.67percent",
        summary: "1–10 effort for Apple Health",
        colors: [0xF43F5E, 0xF97316],
        shows: "Finish sheet, Mood vs effort widget",
        parts: [
            Part("Prefilled effort", "Taken from the reps you left in the tank; you can change it.",
                 rule: ["effort = 10 − average RIR of the session, 1–10"]),
            Part("Bands", "Apple's words for the score.",
                 rule: ["1–3 \(WorkoutEffort.word(2)) · 4–6 \(WorkoutEffort.word(5)) · 7–8 \(WorkoutEffort.word(8)) · 9–10 \(WorkoutEffort.word(10))"]),
        ],
        sources: ["Foster C et al. A new approach to monitoring exercise training. J Strength Cond Res 2001;15(1):109-115.",
                  "Helms ER et al. Application of the repetitions in reserve-based RPE scale for resistance training. Strength Cond J 2016;38(4):42-49 (RPE = 10 − RIR)."])

    static let cardio = Topic(
        id: "cardio", title: "Runs & HIIT", symbol: "figure.run",
        summary: "Where runs and intervals land in your week",
        colors: [0x06B6D4, 0x10B981],
        shows: "Train week, run sessions, HIIT days",
        parts: [
            Part("Runs around lifting", "Long run on Saturday, never on or the day after a legs day; hard runs not the day after legs; gym-free days first.",
                 rule: ["run day: lift first, the run replaces the cardio block",
                        "legs before a long run or intervals: −1 set on leg work",
                        "Hybrid: Zone 2 +5′ and intervals +2 reps a week, eased in the deload"]),
            Part("HIIT days", "On free days away from leg days and from each other; formats rotate weekly, the deload week is easy intervals.",
                 rule: ["low readiness eases HIIT like any session"]),
        ],
        sources: ["Wilson JM et al. Concurrent training: a meta-analysis examining interference of aerobic and resistance exercises. J Strength Cond Res 2012;26(8):2293-2307 (running interferes more than cycling, hence spacing runs from leg days).",
                  "Schumann M et al. Compatibility of concurrent aerobic and strength training for skeletal muscle size and function: an updated systematic review and meta-analysis. Sports Med 2022;52(3):601-612 (lifting and cardio in the same session costs explosive strength, not size or max strength).",
                  "Gibala MJ, Little JP, MacDonald MJ, Hawley JA. Physiological adaptations to low-volume, high-intensity interval training in health and disease. J Physiol 2012;590(5):1077-1084.",
                  "Tabata I et al. Effects of moderate-intensity endurance and high-intensity intermittent training on anaerobic capacity and VO2max. Med Sci Sports Exerc 1996;28(10):1327-1330 (20 s / 10 s × 8).",
                  "App design: which weekday each run or HIIT lands on."])

    // MARK: Fuel

    static let fuel = Topic(
        id: "fuel", title: "Fuel targets", symbol: "fork.knife",
        summary: "Protein, carbs and fat in g/kg by day",
        colors: [0xEAB308, 0xF97316],
        shows: "Fuel tank, meal timeline, portions",
        parts: [
            Part("Day load", "How hard the day is, from the training on it.",
                 rule: ["rest: < 150 kcal and < 25 min of training",
                        "big: ≥ 600 kcal, ≥ 90 min, or two sessions of 45+ min",
                        "normal: in between"]),
            Part("Training energy", "Measured calories from the Watch or Health when known, else estimated.",
                 rule: ["kcal = MET × kg × hours (gym MET 5, sports their own)",
                        "× (0.6 + 0.07 × effort) when effort is rated"]),
            Part("Protein", "By goal, on lean mass when you logged body fat (so high body fat doesn't inflate it).",
                 rule: ["g/kg: " + FuelGoal.allCases.map { "\($0.rawValue) \(fmt(Fuel.proteinPerKg($0)))" }.joined(separator: " · "),
                        "base kg = weight, or min(weight, lean × 1.25)",
                        "big day +0.2 g/kg · rounded to 5 g"]),
            Part("Carbs", "By day load, shifted by goal.",
                 rule: ["g/kg rest \(fmt(Fuel.carbsPerKg(.rest, goal: .maintain))) · normal \(fmt(Fuel.carbsPerKg(.normal, goal: .maintain))) · big \(fmt(Fuel.carbsPerKg(.big, goal: .maintain)))",
                        "lose −1 · build +0.5 · perform +1 (never under 2)",
                        "big day tomorrow +1 g/kg · carb loading 1–2 days before a long event \(fmt(Fuel.carbLoadPerKg)) g/kg",
                        "rounded to 10 g"]),
            Part("Fat and calories", "Fat stays steady; calories follow from the three.",
                 rule: ["fat \(fmt(Fuel.fatPerKg(.lose))) g/kg to lose, else \(fmt(Fuel.fatPerKg(.maintain)))",
                        "kcal = 4 × protein + 4 × carbs + 9 × fat"]),
            Part("Hand portions", "No scale needed.",
                 rule: ["palm ≈ \(Int(Portions.proteinPerPalm)) g protein · cupped hand ≈ \(Int(Portions.carbsPerCup)) g carbs · thumb ≈ \(Int(Portions.fatPerThumb)) g fat · fist = veg"]),
            Part("No weight logged", "A typical body is used and Fuel says so.",
                 rule: ["\(Int(Fuel.typicalKg)) kg · \(Int(Fuel.typicalFemaleKg)) kg for women"]),
        ],
        sources: ["Jäger R et al. International Society of Sports Nutrition position stand: protein and exercise. J Int Soc Sports Nutr 2017;14:20.",
                  "Thomas DT, Erdman KA, Burke LM. American College of Sports Medicine joint position statement: nutrition and athletic performance. Med Sci Sports Exerc 2016;48(3):543-568.",
                  "Ainsworth BE et al. 2011 Compendium of Physical Activities: a second update of codes and MET values. Med Sci Sports Exerc 2011;43(8):1575-1581.",
                  "Helms ER, Zinn C, Rowlands DS, Brown SR. A systematic review of dietary protein during caloric restriction in resistance trained lean athletes: a case for higher intakes. Int J Sport Nutr Exerc Metab 2014;24(2):127-138 (more protein when losing).",
                  "Burke LM, Hawley JA, Wong SHS, Jeukendrup AE. Carbohydrates for training and competition. J Sports Sci 2011;29(Suppl 1):S17-S27 (carbs by training load, 10–12 g/kg to load).",
                  "App design: hand portions are a rule of thumb; the lean × 1.25 cap."])

    static let water = Topic(
        id: "water", title: "Water", symbol: "drop.fill",
        summary: "35 ml/kg plus training and steps",
        colors: [0x0EA5E9, 0x2563EB],
        shows: "Fuel tank water, water reminders",
        parts: [
            Part("Daily target", "From your weight, the day's training and your steps, in glasses of your size.",
                 rule: ["ml = 35 × kg + 500 per training hour (750 for sweaty endurance) + 250 per 5,000 steps",
                        "glasses = ml ÷ glass size, at least 4",
                        "creatine day: +1 glass"]),
            Part("Pace", "Reminders spread the target from waking to sleep, never during training, and recompute after every glass.", rule: []),
        ],
        sources: ["Sawka MN et al. American College of Sports Medicine position stand: exercise and fluid replacement. Med Sci Sports Exerc 2007;39(2):377-390.",
                  "EFSA Panel on Dietetic Products, Nutrition and Allergies. Scientific opinion on dietary reference values for water. EFSA J 2010;8(3):1459 (2.0 L women, 2.5 L men a day, food included).",
                  "App design: 35 ml/kg, the training, step and creatine top-ups are a rule of thumb around those references."])

    static let caffeine = Topic(
        id: "caffeine", title: "Caffeine & supplements", symbol: "cup.and.saucer.fill",
        summary: "\(Supplements.caffeineGuideMg) mg a day, cut-off before bed",
        colors: [0x92400E, 0xF59E0B],
        shows: "Fuel tank caffeine, My stack",
        parts: [
            Part("Caffeine", "Logged drinks and supplements add up; Fuel warns past the guide or too close to bed.",
                 rule: ["guide \(Supplements.caffeineGuideMg) mg a day for healthy adults",
                        "last caffeine \(Supplements.caffeineHoursBeforeSleep) h before your bedtime"]),
            Part("Supplement schedule", "Doses land on your meals; cycles count weeks on and off from the start date you set.", rule: []),
        ],
        sources: ["EFSA Panel on Dietetic Products, Nutrition and Allergies. Scientific opinion on the safety of caffeine. EFSA J 2015;13(5):4102.",
                  "Drake C, Roehrs T, Shambroom J, Roth T. Caffeine effects on sleep taken 0, 3, or 6 hours before going to bed. J Clin Sleep Med 2013;9(11):1195-1200.",
                  "Gardiner C et al. The effect of caffeine on subsequent sleep: a systematic review and meta-analysis. Sleep Med Rev 2023;69:101764 (a coffee about 9 h and a pre-workout about 13 h before bed still cost sleep).",
                  "Guest NS et al. International Society of Sports Nutrition position stand: caffeine and exercise performance. J Int Soc Sports Nutr 2021;18(1):1 (3–6 mg/kg about an hour before).",
                  "Kreider RB et al. International Society of Sports Nutrition position stand: safety and efficacy of creatine supplementation in exercise, sport, and medicine. J Int Soc Sports Nutr 2017;14:18."])

    // MARK: Body

    static let recovery = Topic(
        id: "recovery", title: "Recovery days", symbol: "figure.cooldown",
        summary: "Rest-day routine for what you loaded most",
        colors: [0x14B8A6, 0x22C55E],
        shows: "Train rest-day Recover card, cool-downs",
        parts: [
            Part("Area pick", "This week's load per muscle group (sets × weight) decides the rest-day routine.",
                 rule: ["area with the most load: hips & back, legs or upper body",
                        "no area above 40 % of the total → full body"]),
            Part("Cool-down", "A workout without one gets 5′: 4 mat stretches for its most-loaded muscles. Optional: it feels good and eases you out of the session, but studies don't show it cuts soreness or injuries, so skip it when short on time.", rule: []),
        ],
        sources: ["Van Hooren B, Peake JM. Do we need a cool-down after exercise? A narrative review of the psychophysiological effects and the effects on performance, injuries and the long-term adaptive response. Sports Med 2018;48(7):1575-1595.",
                  "Behm DG et al. Acute effects of muscle stretching on physical performance, range of motion, and injury incidence in healthy active individuals: a systematic review. Appl Physiol Nutr Metab 2016;41(1):1-11.",
                  "Dupuy O, Douzi W, Theurot D, Bosquet L, Dugué B. An evidence-based approach for choosing post-exercise recovery techniques to reduce markers of muscle damage, soreness, fatigue, and inflammation: a systematic review with meta-analysis. Front Physiol 2018;9:403 (active recovery and massage-like work ease soreness a little).",
                  "App design: the 40 % rule for picking an area."])

    static let pain = Topic(
        id: "pain", title: "Train around pain", symbol: "cross.case.fill",
        summary: "Moves that load a sore joint swap out",
        colors: [0xE11D48, 0xF59E0B],
        shows: "Body figure, Ask Coach, 🛡 swapped moves",
        parts: [
            Part("Three levels", "Tell the app where it hurts and how bad. Each level swaps more; training the rest of the body goes on, pain-free range only.",
                 rule: ["mild: the harshest moves for that joint (legs: jumps and running · shoulder: overhead · back: swings and barbell hinges)",
                        "sore when loaded: also the moves that load it most (knee: lunges, leg extensions, free squats)",
                        "sharp: every move that loads the joint"]),
            Part("Swap", "Each risky move swaps to the closest one that spares the joint (same role, most muscles in common, your kit), or goes when nothing fits.", rule: []),
            Part("When to see someone", PainProtect.notAdvice,
                 rule: ["still on after 14 days → Still hurts after 2 weeks? card with Get advice"]),
        ],
        sources: ["Smith BE et al. Should exercises be painful in the management of chronic musculoskeletal pain? A systematic review and meta-analysis. Br J Sports Med 2017;51(23):1679-1687 (some pain during exercise is acceptable, hence mild only swaps the harshest moves).",
                  "Silbernagel KG, Thomeé R, Eriksson BI, Karlsson J. Continued sports activity, using a pain-monitoring model, during rehabilitation in patients with Achilles tendinopathy: a randomized controlled study. Am J Sports Med 2007;35(6):897-906 (keep training while pain stays low).",
                  "App design: which moves load which joint, and the 14-day check-in."])

    static let lifeStage = Topic(
        id: "life", title: "Life stages", symbol: "figure.and.child.holdinghands",
        summary: "Pregnancy, after birth, 50+, back to training",
        colors: [0xEC4899, 0x8B5CF6],
        shows: "Explore → Plans → Life stages",
        parts: [
            Part("Safety first", "Each programme starts with a short check-in and asks you to confirm a doctor or midwife said exercise is OK. Working sets go by feel.",
                 rule: ["every strength set: \(LifeStage.talkTest)"]),
            Part("Pregnancy", "Strength goes on through all three trimesters, with safer moves as the bump grows.",
                 rule: ["all trimesters: no jumping or bounding",
                        "from the 2nd: no crunching, no lying flat on your back for long, lighter loads without breath holding"]),
            Part("After birth", "Core and pelvic floor first, impact later.",
                 rule: ["no jumps and no crunching until about week 16", "then build up to the hardest jumps"]),
            Part("50+", "Power with control: fast but safe moves, balance and bone loading stay in.",
                 rule: ["depth and tuck jumps, burpees, dragon flags and toes-to-bar swap to controlled versions"]),
            Part("Back to training", "After 4 weeks or more off, rebuild before high-impact jumps and fast lifts.",
                 rule: ["4+ weeks off: depth and tuck jumps and power cleans swap out", "loads start lighter (see Load)"]),
        ],
        sources: ["Mottola MF et al. 2019 Canadian guideline for physical activity throughout pregnancy. Br J Sports Med 2018;52(21):1339-1346.",
                  "ACOG Committee Opinion No. 804. Physical activity and exercise during pregnancy and the postpartum period. Obstet Gynecol 2020;135(4):e178-e188 (avoid lying flat on the back for long, and contact or fall risks).",
                  "Christopher SM et al. Clinical and exercise professional opinion of return-to-running readiness after childbirth: an international Delphi study and consensus statement. Br J Sports Med 2024 (impact from about 12 weeks; the app waits a little longer).",
                  "Fragala MS et al. Resistance training for older adults: position statement from the National Strength and Conditioning Association. J Strength Cond Res 2019;33(8):2019-2052 (power, balance and strength work after 50).",
                  "Persinger R, Foster C, Gibson M, Fater DCW, Porcari JP. Consistency of the talk test for exercise prescription. Med Sci Sports Exerc 2004;36(9):1632-1636.",
                  "Mujika I, Padilla S. Detraining: loss of training-induced physiological and performance adaptations. Part I. Sports Med 2000;30(2):79-87."])

    static let body = Topic(
        id: "body", title: "Body numbers", symbol: "figure.arms.open",
        summary: "Lean mass, measurements, where they're used",
        colors: [0x475569, 0x7C3AED],
        shows: "Body, measurements, Fuel, starting loads",
        parts: [
            Part("Lean mass", "From your latest weight and body fat.",
                 rule: ["lean kg = weight × (1 − body fat %)"]),
            Part("Where it's used", "Lean mass sets protein and nudges starting loads; arm and thigh girths nudge arm and leg starting loads. Each nudge is capped so a typo can't swing a number.", rule: []),
            Part("Change", "Charts show the change from the first to the latest point; Health copies of a logged value are counted once.", rule: []),
        ],
        sources: ["Morton RW et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults. Br J Sports Med 2018;52(6):376-384.",
                  "App design: the caps on lean-mass and girth nudges."])

    static let form = Topic(
        id: "form", title: "Form check", symbol: "video.fill",
        summary: "Camera reps, faults and a score out of 100",
        colors: [0xFF4D6D, 0xFF9A3C],
        shows: "Exercise page Check my form, Coach Watch my form, player camera chip, form report",
        parts: [
            Part("What is read", "Apple's body pose finds 14 joints in each camera frame, on your iPhone. No picture is kept or sent; the report keeps the joints of the worst rep for its replay.", rule: []),
            Part("Reps", "Counted on the joint that moves most in the exercise's 3D position guide, from its start (0 %) to its main position (100 %).",
                 rule: ["rep starts past \(pct(FormModel.Limit.repStart)) of the way, ends back under \(pct(FormModel.Limit.repEnd))",
                        "short rep: under \(pct(FormModel.Limit.fullRange)) of the way",
                        "not finished: stays past \(pct(FormModel.Limit.lockout)) between reps"]),
            Part("Faults", "Only what the camera can see from that side: from the side range, trunk lean and sagging hips; from the front knees caving and one side ahead.",
                 rule: ["trunk lean: \(fmt(FormModel.Limit.torsoLean))° more than the guide at the bottom",
                        "knees caving: knee-to-ankle width under \(pct(FormModel.Limit.kneeWidth)) of the guide's",
                        "hips sag: \(pct(FormModel.Limit.hipSag)) of body length under the shoulder–ankle line",
                        "one side ahead: left and right \(fmt(FormModel.Limit.uneven))° apart",
                        "too fast: rep under \(fmt(FormModel.Limit.minRepSeconds)) s (not jumps or throws)"]),
            Part("Score", "Each rep starts at 100 and loses points once per fault; the set score is the average.",
                 rule: [FormFault.allCases.map { "\($0.title.lowercased()) −\($0.penalty)" }.joined(separator: " · "),
                        "faded from: every rep from there scores \(FormReport.fadeScore) or less"]),
            Part("Match", "How close your joints are to the guide at the bottom of the rep.",
                 rule: ["joint match = 1 − difference ÷ \(fmt(FormModel.Limit.matchZero))°, 0 at worst",
                        "green within \(fmt(FormModel.Limit.angleOK))°, amber within \(fmt(FormModel.Limit.angleOK * 2))°"]),
        ],
        sources: ["Apple Vision framework, VNDetectHumanBodyPoseRequest (2D body pose).",
                  "Myer GD et al. The back squat: a proposed assessment of functional deficits and technical factors that limit performance. Strength Cond J 2014;36(6):4-27.",
                  "Hewett TE et al. Biomechanical measures of neuromuscular control and valgus loading of the knee predict anterior cruciate ligament injury risk in female athletes: a prospective study. Am J Sports Med 2005;33(4):492-501 (why knees caving is flagged).",
                  "App design: the thresholds and points, tuned on the 3D position guide's poses."])

    private static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }
    static let mind = Topic(
        id: "mind", title: "Mind score & calm", symbol: "brain.head.profile",
        summary: "Mood, HRV, sleep and training → 0–100",
        colors: [0x7A2CFF, 0x2E8BFF],
        shows: "Train check-in card, Insights Body + Mind and Mind widgets, Explore → Calm, Mind page",
        parts: [
            Part("Mind score", "Your check-in mood, your 7-day HRV average against your 30-day one (a single reading is too noisy), last night's sleep (adults need 7 h or more) and recent training (exercise lifts mood, so a day or two scores best), each scored 0–1 and weighted. A part with no reading drops out and the others count more. No mood, HRV or sleep: no score. The weights are app design, not a validated scale.",
                 rule: ["mood \(fmt(MindScore.moodWeight)) · HRV \(fmt(MindScore.hrvWeight)) · sleep \(fmt(MindScore.sleepWeight)) · training \(fmt(MindScore.loadWeight))",
                        "mood: 1 → 0, 5 → 1",
                        "HRV ÷ baseline: \(fmt(MindScore.hrvLow)) → 0, \(fmt(MindScore.hrvHigh)) → 1",
                        "sleep: \(fmt(MindScore.sleepLow)) h → 0, \(fmt(MindScore.sleepHigh)) h → 1",
                        "workout days in the last \(MindScore.loadDays): " + MindScore.loadPoints.enumerated().map { "\($0.offset) → \(fmt($0.element))" }.joined(separator: ", "),
                        "+1 a calm minute today, max +\(MindScore.calmBonusMax)",
                        "Calm 75+ · Steady 55–74 · Strained 35–54 · Low under 35"]),
            Part("Coach pick", "One breathing session for now, from the hour, your mood and HRV.",
                 rule: ["after 8 pm → 4-7-8", "mood 1–2 → physio sigh", "HRV under 85 % of baseline → box",
                        "before 11 am, mood 3 or no check-in → wake-up", "otherwise → box"]),
            Part("Body + Mind today", "On Insights, your Mind score sits next to the auto-tune ready score (Body), with one line from Coach.",
                 rule: ["Body under \(AutoTune.lightBelow) = low · \(AutoTune.pushFrom)+ = high",
                        "Mind under \(MindScore.Level.steadyFrom) = low",
                        "both low → light + breathe first · body low → light · mind low → breathe first · both high → push"]),
            Part("Patterns", "With \(MindScore.patternMin)+ check-ins in 28 days, Coach compares your mood the day after a workout with other days (0.5 apart or more), then looks at what low days are about, then short nights.", rule: []),
            Part("Breathing", "Sessions repeat one breathing pattern for whole cycles, so they end on a breath out. Box 4-4-4-4, 4-7-8, physio sigh 2 + 1 in / 6 out, wake-up 2.5 in / 1.5 out, body scan and pre-lift focus with slow out-breaths. The counts are a pace to follow, not a test: slower or faster is fine if the ratio stays. Each finished session is saved to Apple Health as mindful minutes; check-ins as State of Mind. Mood and sessions stay on this phone.",
                 rule: ["4-7-8: 4 breaths (about 1¼ min), 8 once it feels easy (Weil); not minutes",
                        "box, physio sigh, wake-up: 5 min a day by default, as tested in Balban 2023 (shorter: 3 min, or 1 min of sighs when stressed); box 10 min for a longer practice",
                        "box 4-4-4-4: equal counts at a comfortable pace, about 4 breaths a minute, inside the slow-breathing range (under 10 a minute) linked to calm",
                        "body scan, pre-lift focus: about 6 breaths a minute, 8–15 min like slow-breathing studies",
                        "dizzy or light-headed: stop and breathe normally"]),
        ],
        sources: ["Balban MY et al. Brief structured respiration practices enhance mood and reduce physiological arousal. Cell Rep Med 2023;4(1):100895.",
                  "Zaccaro A et al. How breath-control can change your life: a systematic review on psycho-physiological correlates of slow breathing. Front Hum Neurosci 2018;12:353.",
                  "Singh B et al. Effectiveness of physical activity interventions for improving depression, anxiety and distress: an overview of systematic reviews. Br J Sports Med 2023;57(18):1203-1209.",
                  "Watson NF et al. Recommended amount of sleep for a healthy adult: a joint consensus statement of the AASM and SRS. Sleep 2015;38(6):843-844.",
                  "Weil A. Breathing: The Master Key to Self Healing. Sounds True, 1999 (4-7-8: four breaths twice a day, up to eight).",
                  "Vierra J, Boonla O, Prasertsri P. Effects of sleep deprivation and 4-7-8 breathing control on heart rate variability, blood pressure, blood glucose, and endothelial function in healthy young adults. Physiol Rep 2022;10(13):e15389.",
                  "Plews DJ, Laursen PB, Kilding AE, Buchheit M. Evaluating training adaptation with heart-rate measures: a methodological comparison. Int J Sports Physiol Perform 2013;8(6):688-694 (7-day HRV average over single readings).",
                  "App design: the score weights and bands; not a validated scale."])

    static let coach = Topic(
        id: "coach", title: "Coach nudges", symbol: "bell.badge.fill",
        summary: "When Coach speaks up, and when it stays quiet",
        colors: [0x84CC16, 0x10B981],
        shows: "Session reminders, comeback offer, workout recap",
        parts: [
            Part("Session reminder", "At your reminder time (never in quiet hours), in your words: what you did last time, the number to beat and when you usually start.",
                 rule: ["usual start = median of your last 12 workouts, once \(CoachNudges.usualMinRecords) are logged"]),
            Part("Drifting", "One kind offer, once, when plans slip, never a guilt trip.",
                 rule: ["\(CoachNudges.driftMissed) planned sessions missed since your last workout, or \(Comeback.gapDays)+ days away → a \(CoachNudges.comebackMinutes)′ comeback workout",
                        "shown at 12:00 or 17:00, outside quiet hours"]),
            Part("Recap", "When a workout ends: two lines on what happened, compared with the last time you did each move, and one tip for next time.", rule: []),
        ],
        sources: ["Gollwitzer PM, Sheeran P. Implementation intentions and goal achievement: a meta-analysis of effects and processes. Adv Exp Soc Psychol 2006;38:69-119 (a set when and where makes doing it more likely).",
                  "Lally P, van Jaarsveld CHM, Potts HWW, Wardle J. How are habits formed: modelling habit formation in the real world. Eur J Soc Psychol 2010;40(6):998-1009 (same time each day builds the habit).",
                  "App design: 2 missed sessions and the 12:00 / 17:00 slots."])

    static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }
}
