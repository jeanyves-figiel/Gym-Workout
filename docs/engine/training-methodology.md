> Snapshot of the methodology review (October 2026). Code paths and line numbers point at `ios/Packages/GymCore/Sources/WorkoutEngine/` and may have moved; the code is the reference.

# Training methodology: today + switchable options

Code root: `ios/Packages/GymCore/Sources/WorkoutEngine/`. All generation runs on-device in GymCore; backend only stores profile and logs.

## 1. What the app does today

**Model:** goal-driven concurrent training, 4-week block (linear) periodization, RPE/RIR intensity, double progression.

| Area | Rule | Code |
|---|---|---|
| Mesocycle | 4 weeks: Base (RPE −1) → Build (target RPE) → Peak (+1 set main lift) → Deload (−40 % sets) | `Generator.swift:25-31`, `Config.swift:105` |
| Intensity | Prescribed as RPE; week 1 −1, deload −2. RIR = 10 − RPE | `Generator.swift:178-182`, `LoadAdvisor.swift:86-93` |
| Dose per goal | Main / accessory sets × reps × rest × RPE, e.g. Strength 5×3–5 @8, 180 s; Build 4×6–10 + 3×10–15 @9 | `Config.swift:41-89` |
| Beginners | −1 set (non-light), no Peak extra set, exercise level filter | `Generator.swift:270-271`, `Select.swift:119-128` |
| Deload | Sets ×0.6, RPE −2, session 80 % length, cardio forced to Zone 2, power −1 set, load −10 % | `Generator.swift:54,230,277,406`, `LoadAdvisor.swift:215-220` |
| Split / frequency | 2–3×: full body; 4×: upper/lower; 5×: U/L + conditioning; 6×: PPL. Each pattern ≥ 2×/week | `Config.swift:107-113` |
| Session length | Goal base × frequency factor ± experience − climbing load, 35–100 min, user cap | `Generator.swift:14-23` |
| Session order | Warm-up (raise + drills) → explosive (fresh) → strength → mobility → cardio → cool-down | `Generator.swift:112-153` |
| Exercise order | Slot list by priority; slot 0 = main compound with 2–3 ramp-up sets; prehab/core last | `Config.swift:116-134`, `Generator.swift:278,313` |
| Grouping | Light prehab/core supersetted into rest of heavy lifts; optional supersets/circuits by muscle group; main lift always straight | `Generator.swift:302-323`, `TrainingStyle.swift:175+` |
| Rest | Goal default; Long/Standard/Short override; main lift never < 90 s | `TrainingStyle.swift:89-96` |
| Volume per muscle | **Implicit only**: time budget × slot list. Muscle load computed for cool-down stretch choice and Progress balance, not as a target | `Generator.swift:423-435` |
| Climbing | Gym days scored away from climb days; day-before: no jumps, light pull/grip; ≥2 climb days: −1 pull set, grip-light picks, prehab moved up | `Schedule.swift:96-136`, `Generator.swift:70-73,246-257,273-276` |
| Week places (#684) | Each weekday can name a saved gym; that day's session is rebuilt from the same week generated with that gym's equipment and zones (same type, same day). Moved sessions take their new day's gym. No places = byte-identical plans | `WeekPlaces.swift`, `PlanCalendar.swift` (`fitPlaces`) |
| Hybrid / runs with lifting (#685) | On a run day the lift comes first and the run replaces its cardio block; a leg-heavy session the day before (or the day of) a long or hard run keeps one set less on leg patterns (never under 2); Hybrid runs grow through the block (+5′ Zone 2, +2 interval reps a week; deload eases off). Changes explained in `Session.synergy` | `RunPlan.swift` (`RunPlanner.blend`, `step`) |
| Starting load | Same-pattern logged lift converted between implements (−10/−15 %), else body weight × pattern ratio × sex × level × age, inverse Epley at target RIR, then −15 % | `StartingLoad.swift:108-156` |
| Progression | Double progression: all sets at top of range → +1 increment (+2 if all ≥ 4 RIR, not Base); best set under range → −5 %; else hold, +1 rep | `LoadAdvisor.swift:128-246` |
| Readiness | HRV < 85 % baseline, resting HR > +5 bpm, sleep < 6 h → Ready / Normal / Easy. Easy on a strength day offers a one-tap swap to a recover day (session moves to the next free day, #619) | `MonkeyWorkout/Health/HealthManager.swift:92-124` |
| Generate from muscles | Round-robin per group, prefer uncovered muscles + new patterns, ≤ 2 main lifts, mains → accessories → light; goal dose; grip-light for climbers | `MuscleWorkout.swift:62-205` |
| Swaps | Same pattern/role, best primary-muscle overlap, same equipment/level | `Swap.swift:58-73` |

**Gaps:** no explicit weekly sets per muscle; readiness does not adjust sessions; no ease-in after time away (away weeks re-plan days only, `PlanCalendar.swift:99-106`); logged RIR only used for the +2 increment.

### HIIT (#693, `Hiit.swift`)

HIIT sessions are timed blocks of library moves: **Tabata** 8 × 20″/10″ (two moves in turn), **EMOM** (reps on the minute, moves alternate), **AMRAP** (capped, rounds counted), **For time** (rounds of the moves, capped), **Pyramid** 20-40-60-40-20″ with 15″ rests, **30/30**. Each has a 3′ warm-up and a 2′ cool-down (30″ moves). Moves come from a HIIT pool tagged by area (full, legs, upper, core), jumps and default reps, filtered by the kit; picks rotate areas and prefer kit moves, never repeating a move within a workout while others remain. Planned HIIT days are half the plan's session length (15–30′, ×0.75 in the deload), placed on free days away from leg days, sport days and each other; formats rotate weekly and the deload week is easy 20″/40″ intervals. Members can pin HIIT weekdays (#757; a lifting day stays the lift's, remaining days are Coach picks), fix one format for every HIIT day (built like Explore's, eased in the deload week) and a length (10–30′, ×0.75 in the deload). Low readiness: a quarter fewer intervals, +5″ rest, shorter caps. HIIT counts as conditioning (MET 9) and logs one set per interval.

## 2. Proposed switchable methodologies (Account → Training profile → "Method")

One setting, orthogonal to Goal. Goal keeps choosing *what* (mix, rep zones); Method chooses *how it progresses*. Default = current behaviour, no plan change for existing members.

| # | Method | What changes in the generator | Evidence |
|---|---|---|---|
| A | **Block / linear** (default, current) | Nothing. Base → Build → Peak → Deload | Williams 2017; Bell 2023 |
| B | **Daily undulating (DUP)** | Each main pattern rotates rep zone across its weekly sessions: Heavy 3–5 @ RPE 8 / Moderate 6–8 / Light 10–12. Weekly wave kept; Peak adds the set to the Heavy day | Rhea 2002; Moesgaard 2022; Harries 2015 (no diff, novices) |
| C | **RIR autoregulated** | Load set from today's top set at target RIR (logged RIR drives ± load each session, not only +2 increments); readiness "Easy" auto-applies −1 RPE and −1 set on accessories | Helms 2018; Graham & Cleather 2021; Larsen 2021 |
| D | **Volume progression (hypertrophy, MEV→MAV)** | Weekly hard-set target per muscle: start ~10 sets (Base), +2 sets/muscle per week to ~16–20 (Peak), deload to ~5. Accessory picker fills under-target muscles; cap ~10 hard sets/muscle/session; RIR 1–3 | Schoenfeld 2017a; Baz-Valle 2022; Schoenfeld 2016a; Refalo 2023 |
| E | **Minimal dose (time-efficient)** | 1–2 hard sets per exercise to RIR 0–2, supersets default, compounds only + 1 accessory, ~30–40 min | Iversen 2021; Androulakis-Korakakis 2020 |

Not proposed as a Method: **strength low-rep** is already Goal = Max strength (`Config.swift:57-63`, 5×3–5, 180 s; supported by Schoenfeld 2017b, Lopez 2021, Schoenfeld 2016b). **Velocity-based** needs hardware.

Safety rails kept for every method: level filter, beginner −1 set, ramp-up sets, deload week, ≤ 2 main lifts per generated workout, climbing-day rules, conservative starting load. Recommended extra rail (all methods): ease-in week after ≥ 2 weeks away (Base dose, −10 % load).

## References (peer-reviewed unless noted)

- Androulakis-Korakakis P, Fisher JP, Steele J. The minimum effective training dose required to increase 1RM strength in resistance-trained men: a systematic review and meta-analysis. *Sports Med* 2020;50(4):751-765.
- Baz-Valle E, Balsalobre-Fernández C, Alix-Fages C, Santos-Concejero J. A systematic review of the effects of different resistance training volumes on muscle hypertrophy. *J Hum Kinet* 2022;81:199-210.
- Bell L, Nolan D, Immonen V, et al. Integrating deloading into strength and physique sports training programmes: an international Delphi consensus approach. *Sports Med Open* 2023;9:87.
- Graham T, Cleather DJ. Autoregulation by "repetitions in reserve" leads to greater improvements in strength over a 12-week training program than fixed loading. *J Strength Cond Res* 2021;35(9):2451-2456.
- Harries SK, Lubans DR, Callister R. Systematic review and meta-analysis of linear and undulating periodized resistance training programs on muscular strength. *J Strength Cond Res* 2015;29(4):1113-1125.
- Helms ER, Byrnes RK, Cooke DM, et al. RPE vs. percentage 1RM loading in periodized programs matched for sets and repetitions. *Front Physiol* 2018;9:247.
- Iversen VM, Norum M, Schoenfeld BJ, Fimland MS. No time to lift? Designing time-efficient training programs for strength and hypertrophy: a narrative review. *Sports Med* 2021;51(10):2079-2095.
- Larsen S, Kristiansen E, van den Tillaar R. Effects of subjective and objective autoregulation methods for intensity and volume on enhancing maximal strength during resistance-training interventions: a systematic review. *PeerJ* 2021;9:e10663.
- Lopez P, Radaelli R, Taaffe DR, et al. Resistance training load effects on muscle hypertrophy and strength gain: systematic review and network meta-analysis. *Med Sci Sports Exerc* 2021;53(6):1206-1216.
- Moesgaard L, Beck MM, Christiansen L, et al. Effects of periodization on strength and muscle hypertrophy in volume-equated resistance training programs: a systematic review and meta-analysis. *Sports Med* 2022;52(7):1647-1666.
- Refalo MC, Helms ER, Trexler ET, et al. Influence of resistance training proximity-to-failure on skeletal muscle hypertrophy: a systematic review with meta-analysis. *Sports Med* 2023;53(3):649-665.
- Rhea MR, Ball SD, Phillips WT, Burkett LN. A comparison of linear and daily undulating periodized programs with equated volume and intensity for strength. *J Strength Cond Res* 2002;16(2):250-255.
- Schoenfeld BJ, Ogborn D, Krieger JW. (2016a) Effects of resistance training frequency on measures of muscle hypertrophy: a systematic review and meta-analysis. *Sports Med* 2016;46(11):1689-1697.
- Schoenfeld BJ, Pope ZK, Benik FM, et al. (2016b) Longer interset rest periods enhance muscle strength and hypertrophy in resistance-trained men. *J Strength Cond Res* 2016;30(7):1805-1812.
- Schoenfeld BJ, Ogborn D, Krieger JW. (2017a) Dose-response relationship between weekly resistance training volume and increases in muscle mass: a systematic review and meta-analysis. *J Sports Sci* 2017;35(11):1073-1082.
- Schoenfeld BJ, Grgic J, Ogborn D, Krieger JW. (2017b) Strength and hypertrophy adaptations between low- vs. high-load resistance training: a systematic review and meta-analysis. *J Strength Cond Res* 2017;31(12):3508-3523.
- Williams TD, Tolusso DV, Fedewa MV, Esco MR. Comparison of periodized and non-periodized resistance training on maximal strength: a meta-analysis. *Sports Med* 2017;47(10):2083-2100.
- MEV/MAV/MRV terms: Israetel M, Hoffmann J, Smith CW. *Scientific Principles of Hypertrophy Training* (Renaissance Periodization, 2021) — practitioner framework, not peer-reviewed; set numbers above follow the meta-analyses cited.

Citations from model knowledge; verify page numbers before quoting in-app.
