import type { Category, Equipment, Exercise, Level, Muscle, Pattern } from '../domain/types';

type Extra = Partial<Omit<Exercise, 'id' | 'name' | 'category' | 'pattern' | 'primary' | 'equipment' | 'level'>>;

const ex = (
  id: string,
  name: string,
  category: Category,
  pattern: Pattern,
  primary: Muscle[],
  equipment: Equipment[],
  level: Level,
  cues: string[],
  extra: Extra = {},
): Exercise => ({ id, name, category, pattern, primary, equipment, level, cues, ...extra });

const S = 'strength' as const;
const P = 'power' as const;
const M = 'mobility' as const;
const W = 'warmup' as const;
const C = 'cardio' as const;
const X = 'stretch' as const;

export const EXERCISES: Exercise[] = [
  // ───────────── Strength · squat
  ex('back-squat', 'Barbell back squat', S, 'squat', ['quads', 'glutes'], ['barbell', 'rack'], 2,
    ['Brace before descent', 'Knees track over toes', 'Hips and chest rise together'],
    { secondary: ['adductors', 'lower-back'], main: true, secPerRep: 4 }),
  ex('front-squat', 'Barbell front squat', S, 'squat', ['quads', 'glutes'], ['barbell', 'rack'], 3,
    ['Elbows high', 'Upright torso', 'Sit between the heels'], { secondary: ['abs', 'upper-back'], main: true, secPerRep: 4 }),
  ex('goblet-squat', 'Goblet squat', S, 'squat', ['quads', 'glutes'], ['dumbbells'], 1,
    ['Weight at sternum', 'Elbows inside knees at bottom', 'Pause 1 s in the hole'], { secondary: ['adductors', 'abs'], main: true, secPerRep: 4 }),
  ex('hack-squat', 'Hack squat', S, 'squat', ['quads', 'glutes'], ['hack-squat'], 1,
    ['Full depth', 'Control 3 s eccentric', 'Don\'t lock knees hard'], { main: true, secPerRep: 4 }),
  ex('leg-press', 'Leg press', S, 'squat', ['quads', 'glutes'], ['leg-press'], 1,
    ['Lower back stays on pad', 'Deep but no butt-wink', '3 s eccentric'], { secondary: ['adductors'], main: true, secPerRep: 4 }),

  // ───────────── Strength · hinge
  ex('deadlift', 'Barbell deadlift', S, 'hinge', ['hamstrings', 'glutes', 'lower-back'], ['barbell'], 2,
    ['Bar over mid-foot', 'Lats tight, push floor away', 'Lock out with glutes, not lower back'],
    { secondary: ['upper-back', 'forearms'], main: true, gripHeavy: true, secPerRep: 4 }),
  ex('trap-bar-deadlift', 'Trap bar deadlift', S, 'hinge', ['glutes', 'quads', 'hamstrings'], ['trap-bar'], 1,
    ['Hips slightly higher than squat', 'Neutral spine', 'Drive through whole foot'],
    { secondary: ['upper-back', 'forearms'], main: true, gripHeavy: true, secPerRep: 4 }),
  ex('rdl', 'Romanian deadlift', S, 'hinge', ['hamstrings', 'glutes'], ['barbell'], 2,
    ['Soft knees, hips back', 'Bar grazes thighs', 'Stop at hamstring tension'],
    { secondary: ['lower-back', 'forearms'], main: true, secPerRep: 4 }),
  ex('db-rdl', 'Dumbbell Romanian deadlift', S, 'hinge', ['hamstrings', 'glutes'], ['dumbbells'], 1,
    ['Hips back', 'Dumbbells close to legs', 'Neutral neck'], { secondary: ['lower-back'], secPerRep: 4 }),
  ex('hip-thrust', 'Barbell hip thrust', S, 'hinge', ['glutes'], ['barbell', 'bench'], 1,
    ['Chin tucked, ribs down', 'Shins vertical at top', '1 s squeeze at top'], { secondary: ['hamstrings'], main: true, secPerRep: 3 }),
  ex('hip-thrust-machine', 'Hip thrust machine', S, 'hinge', ['glutes'], ['hip-thrust-machine'], 1,
    ['Posterior pelvic tilt at top', 'Pause 1 s'], { secondary: ['hamstrings'], secPerRep: 3 }),
  ex('back-extension', '45° back extension', S, 'hinge', ['glutes', 'hamstrings', 'lower-back'], ['back-extension'], 1,
    ['Hinge at hips', 'Squeeze glutes to rise', 'Hold plate if easy'], { secPerRep: 3 }),
  ex('cable-pull-through', 'Cable pull-through', S, 'hinge', ['glutes', 'hamstrings'], ['cable'], 1,
    ['Hips back, arms passive', 'Snap hips through'], { secPerRep: 3 }),

  // ───────────── Strength · single leg
  ex('bulgarian-split-squat', 'Bulgarian split squat', S, 'single-leg', ['quads', 'glutes'], ['dumbbells', 'bench'], 2,
    ['Long stance for glutes', 'Front knee forward for quads', 'Control the descent'],
    { secondary: ['adductors', 'hip-flexors'], unilateral: true, secPerRep: 4 }),
  ex('reverse-lunge', 'Dumbbell reverse lunge', S, 'single-leg', ['quads', 'glutes'], ['dumbbells'], 1,
    ['Step back softly', 'Torso tall', 'Drive through front heel'], { unilateral: true, secPerRep: 4 }),
  ex('walking-lunge', 'Walking lunge', S, 'single-leg', ['quads', 'glutes'], ['dumbbells'], 1,
    ['Long strides', 'Back knee kisses floor'], { secondary: ['adductors'], unilateral: true, secPerRep: 3 }),
  ex('step-up', 'Dumbbell step-up', S, 'single-leg', ['quads', 'glutes'], ['dumbbells', 'plyo-box'], 1,
    ['High box (knee ≥ hip)', 'No push-off from back leg — climber high-step pattern'], { unilateral: true, secPerRep: 4 }),
  ex('single-leg-rdl', 'Single-leg RDL', S, 'single-leg', ['hamstrings', 'glutes'], ['dumbbells'], 2,
    ['Square hips', 'Reach long through back heel'], { secondary: ['obliques'], unilateral: true, secPerRep: 4 }),
  ex('cossack-squat', 'Goblet Cossack squat', S, 'single-leg', ['adductors', 'quads', 'glutes'], ['kettlebells'], 2,
    ['Heel down on working side', 'Straight-leg toes up', 'Great for drop-knees & wide stems'], { unilateral: true, secPerRep: 4 }),

  // ───────────── Strength · knee flex / ext
  ex('leg-curl', 'Leg curl (machine)', S, 'knee-flex', ['hamstrings'], ['leg-curl'], 1,
    ['Hips pinned', '3 s eccentric'], { secondary: ['calves'], secPerRep: 3 }),
  ex('nordic-curl', 'Nordic curl (assisted)', S, 'knee-flex', ['hamstrings'], ['bands'], 2,
    ['Anchor heels', 'Lower as slow as possible', 'Push-up back'], { secPerRep: 5 }),
  ex('leg-extension', 'Leg extension', S, 'knee-ext', ['quads'], ['leg-extension'], 1,
    ['1 s squeeze at top', 'Slow lower'], { secPerRep: 3 }),

  // ───────────── Strength · horizontal push
  ex('bench-press', 'Barbell bench press', S, 'h-push', ['chest', 'triceps'], ['barbell', 'bench', 'rack'], 2,
    ['Shoulder blades back & down', 'Bar to lower chest', 'Feet drive'], { secondary: ['front-delts'], main: true, secPerRep: 3 }),
  ex('db-bench', 'Dumbbell bench press', S, 'h-push', ['chest', 'triceps'], ['dumbbells', 'bench'], 1,
    ['45° elbow angle', 'Full stretch at bottom'], { secondary: ['front-delts'], main: true, secPerRep: 3 }),
  ex('incline-db-press', 'Incline dumbbell press', S, 'h-push', ['chest', 'front-delts'], ['dumbbells', 'bench'], 1,
    ['30° incline', 'Control the stretch'], { secondary: ['triceps'], secPerRep: 3 }),
  ex('chest-press-machine', 'Chest press machine', S, 'h-push', ['chest', 'triceps'], ['chest-press'], 1,
    ['Handles at mid-chest', 'Slow eccentric'], { secondary: ['front-delts'], secPerRep: 3 }),
  ex('push-up', 'Push-up', S, 'h-push', ['chest', 'triceps'], [], 1,
    ['Rigid plank', 'Push floor away at top (serratus)'], { secondary: ['front-delts', 'abs'], secPerRep: 2 }),
  ex('ring-push-up', 'Ring push-up', S, 'h-push', ['chest', 'triceps'], ['rings'], 2,
    ['Rings turned out at top', 'Elbows tucked'], { secondary: ['front-delts', 'rotator-cuff', 'abs'], secPerRep: 3 }),
  ex('dips', 'Parallel bar dips', S, 'h-push', ['chest', 'triceps'], ['dip-station'], 2,
    ['Slight forward lean', 'Shoulders down — mantle strength'], { secondary: ['front-delts'], secPerRep: 3 }),
  ex('cable-fly', 'Cable fly', S, 'h-push', ['chest'], ['cable'], 1,
    ['Soft elbows', 'Hug a tree'], { secondary: ['front-delts'], secPerRep: 3 }),

  // ───────────── Strength · vertical push
  ex('ohp', 'Standing overhead press', S, 'v-push', ['front-delts', 'triceps'], ['barbell', 'rack'], 2,
    ['Squeeze glutes', 'Head through at top'], { secondary: ['side-delts', 'abs', 'upper-back'], main: true, secPerRep: 3 }),
  ex('seated-db-press', 'Seated dumbbell press', S, 'v-push', ['front-delts', 'triceps'], ['dumbbells', 'bench'], 1,
    ['Back on pad', 'Press slightly in front of face'], { secondary: ['side-delts'], main: true, secPerRep: 3 }),
  ex('landmine-press', 'Half-kneeling landmine press', S, 'v-push', ['front-delts', 'chest'], ['landmine', 'barbell'], 1,
    ['Glute of down-knee tight', 'Reach at top (serratus)', 'Shoulder-friendly'], { secondary: ['triceps', 'obliques'], unilateral: true, secPerRep: 3 }),
  ex('arnold-press', 'Arnold press', S, 'v-push', ['front-delts', 'side-delts'], ['dumbbells', 'bench'], 2,
    ['Rotate smoothly', 'No lower-back arch'], { secondary: ['triceps'], secPerRep: 3 }),

  // ───────────── Strength · horizontal pull
  ex('barbell-row', 'Barbell row', S, 'h-pull', ['upper-back', 'lats'], ['barbell'], 2,
    ['Hinge ~45°', 'Bar to lower ribs'], { secondary: ['biceps', 'rear-delts', 'lower-back', 'forearms'], main: true, gripHeavy: true, secPerRep: 3 }),
  ex('chest-supported-row', 'Chest-supported dumbbell row', S, 'h-pull', ['upper-back', 'lats'], ['dumbbells', 'bench'], 1,
    ['Chest stays on pad', 'Lead with elbows'], { secondary: ['rear-delts', 'biceps'], main: true, secPerRep: 3 }),
  ex('seated-cable-row', 'Seated cable row', S, 'h-pull', ['upper-back', 'lats'], ['seated-row'], 1,
    ['Tall spine', 'Squeeze shoulder blades'], { secondary: ['biceps', 'rear-delts'], secPerRep: 3 }),
  ex('one-arm-db-row', 'One-arm dumbbell row', S, 'h-pull', ['lats', 'upper-back'], ['dumbbells', 'bench'], 1,
    ['Pull to hip', 'No torso twist'], { secondary: ['biceps', 'rear-delts'], unilateral: true, secPerRep: 3 }),
  ex('inverted-row', 'TRX / ring row', S, 'h-pull', ['upper-back', 'lats'], ['trx'], 1,
    ['Body rigid', 'Chest to handles'], { secondary: ['biceps', 'rear-delts', 'abs'], secPerRep: 3 }),

  // ───────────── Strength · vertical pull
  ex('pull-up', 'Pull-up', S, 'v-pull', ['lats', 'upper-back'], ['pullup-bar'], 2,
    ['Start from active hang', 'Chest to bar'], { secondary: ['biceps', 'forearms', 'abs'], main: true, gripHeavy: true, secPerRep: 3 }),
  ex('weighted-pull-up', 'Weighted pull-up', S, 'v-pull', ['lats', 'upper-back'], ['pullup-bar'], 3,
    ['Belt or DB between feet', 'Full ROM, no kipping'], { secondary: ['biceps', 'forearms'], main: true, gripHeavy: true, secPerRep: 3 }),
  ex('lat-pulldown', 'Lat pulldown', S, 'v-pull', ['lats'], ['lat-pulldown'], 1,
    ['Lean back slightly', 'Elbows to back pockets'], { secondary: ['biceps', 'upper-back'], main: true, secPerRep: 3 }),
  ex('single-arm-pulldown', 'Single-arm cable pulldown', S, 'v-pull', ['lats'], ['cable'], 1,
    ['Kneeling', 'Full stretch overhead'], { secondary: ['biceps'], unilateral: true, secPerRep: 3 }),

  // ───────────── Strength · core
  ex('plank', 'Plank', S, 'core-anti-ext', ['abs'], ['mat'], 1,
    ['Squeeze glutes', 'Ribs down'], { secondary: ['obliques'], unit: 'sec' }),
  ex('dead-bug', 'Dead bug', S, 'core-anti-ext', ['abs'], ['mat'], 1,
    ['Lower back glued to floor', 'Exhale fully'], { secondary: ['hip-flexors'], secPerRep: 3 }),
  ex('ab-wheel', 'Ab wheel rollout', S, 'core-anti-ext', ['abs'], ['ab-wheel'], 2,
    ['Hollow body', 'Only as far as you hold neutral'], { secondary: ['lats'], secPerRep: 4 }),
  ex('trx-body-saw', 'TRX body saw', S, 'core-anti-ext', ['abs'], ['trx'], 2,
    ['Forearm plank, feet in straps', 'Rock back and forth'], { secondary: ['front-delts'], secPerRep: 3 }),
  ex('pallof-press', 'Pallof press', S, 'core-anti-rot', ['obliques', 'abs'], ['cable'], 1,
    ['Resist rotation', '2 s hold at full extension'], { unilateral: true, secPerRep: 4 }),
  ex('side-plank', 'Side plank', S, 'core-anti-rot', ['obliques'], ['mat'], 1,
    ['Hips high', 'Stacked feet'], { secondary: ['abs', 'glutes'], unit: 'sec', unilateral: true }),
  ex('landmine-rotation', 'Landmine rotation', S, 'core-anti-rot', ['obliques', 'abs'], ['landmine', 'barbell'], 2,
    ['Rotate from hips', 'Arms long'], { secPerRep: 3 }),
  ex('hanging-knee-raise', 'Hanging knee raise', S, 'core-flex', ['abs', 'hip-flexors'], ['pullup-bar'], 1,
    ['Curl pelvis up', 'No swing'], { gripHeavy: true, secPerRep: 3 }),
  ex('toes-to-bar', 'Strict toes-to-bar', S, 'core-flex', ['abs', 'hip-flexors'], ['pullup-bar'], 3,
    ['Lats engaged', 'Slow lower — climbing toe-hook strength'], { secondary: ['lats'], gripHeavy: true, secPerRep: 4 }),
  ex('cable-crunch', 'Kneeling cable crunch', S, 'core-flex', ['abs'], ['cable'], 1,
    ['Round spine', 'Hips still'], { secPerRep: 3 }),
  ex('hollow-hold', 'Hollow body hold', S, 'core-flex', ['abs'], ['mat'], 1,
    ['Lower back pressed down', 'Arms by ears'], { secondary: ['hip-flexors'], unit: 'sec' }),

  // ───────────── Strength · carries
  ex('farmer-carry', 'Farmer carry', S, 'carry', ['forearms', 'upper-back'], ['dumbbells'], 1,
    ['Tall posture', 'Short fast steps'], { secondary: ['abs', 'glutes'], gripHeavy: true, unit: 'sec' }),
  ex('suitcase-carry', 'Suitcase carry', S, 'carry', ['obliques'], ['kettlebells'], 1,
    ['Don\'t lean', 'One side then switch'], { secondary: ['forearms'], unilateral: true, unit: 'sec' }),
  ex('overhead-carry', 'Overhead kettlebell carry', S, 'carry', ['side-delts', 'rotator-cuff'], ['kettlebells'], 2,
    ['Biceps by ear', 'Ribs down'], { secondary: ['abs', 'upper-back'], unilateral: true, unit: 'sec' }),

  // ───────────── Strength · arms & delts
  ex('db-curl', 'Dumbbell curl', S, 'arms-flex', ['biceps'], ['dumbbells'], 1, ['No swing', 'Supinate at top'], { secondary: ['forearms'], secPerRep: 3 }),
  ex('hammer-curl', 'Hammer curl', S, 'arms-flex', ['biceps', 'forearms'], ['dumbbells'], 1, ['Neutral grip', 'Elbows pinned'], { secPerRep: 3 }),
  ex('cable-curl', 'Cable curl', S, 'arms-flex', ['biceps'], ['cable'], 1, ['Constant tension'], { secPerRep: 3 }),
  ex('triceps-pushdown', 'Cable triceps pushdown', S, 'arms-ext', ['triceps'], ['cable'], 1, ['Elbows fixed', 'Full lockout'], { secPerRep: 3 }),
  ex('overhead-triceps', 'Overhead cable triceps extension', S, 'arms-ext', ['triceps'], ['cable'], 1, ['Deep stretch', 'Ribs down'], { secPerRep: 3 }),
  ex('db-lateral-raise', 'Dumbbell lateral raise', S, 'lateral-raise', ['side-delts'], ['dumbbells'], 1, ['Lead with elbows', 'Stop at shoulder height'], { secPerRep: 3 }),
  ex('cable-lateral-raise', 'Cable lateral raise', S, 'lateral-raise', ['side-delts'], ['cable'], 1, ['Cable behind body', 'Slow down'], { unilateral: true, secPerRep: 3 }),

  // ───────────── Strength · shoulder health / antagonist (climber)
  ex('face-pull', 'Face pull', S, 'shoulder-health', ['rear-delts', 'rotator-cuff'], ['cable'], 1,
    ['Rope to forehead', 'Externally rotate at end'], { secondary: ['upper-back'], secPerRep: 3 }),
  ex('cable-external-rotation', 'Cable external rotation', S, 'shoulder-health', ['rotator-cuff'], ['cable'], 1,
    ['Towel under elbow', 'Slow and light'], { unilateral: true, secPerRep: 3 }),
  ex('band-pull-apart', 'Band pull-apart', S, 'shoulder-health', ['rear-delts', 'upper-back'], ['bands'], 1,
    ['Arms straight', 'Squeeze 1 s'], { secPerRep: 2 }),
  ex('prone-ytw', 'Prone Y-T-W', S, 'shoulder-health', ['upper-back', 'rotator-cuff'], ['dumbbells', 'bench'], 1,
    ['Very light', 'Thumbs up', '5 reps each letter'], { secondary: ['rear-delts'], secPerRep: 3 }),
  ex('reverse-pec-deck', 'Reverse pec deck', S, 'shoulder-health', ['rear-delts'], ['pec-deck'], 1,
    ['Lead with pinkies', 'Don\'t shrug'], { secondary: ['upper-back'], secPerRep: 3 }),
  ex('scap-pull-up', 'Scapular pull-up', S, 'shoulder-health', ['upper-back', 'lats'], ['pullup-bar'], 1,
    ['Straight arms', 'Depress & retract only'], { gripHeavy: true, secPerRep: 3 }),
  ex('push-up-plus', 'Push-up plus', S, 'shoulder-health', ['chest', 'rotator-cuff'], [], 1,
    ['Extra protraction at top', 'Serratus — protects climbing shoulders'], { secPerRep: 3 }),

  // ───────────── Strength · calves & forearm antagonists
  ex('standing-calf-raise', 'Standing calf raise', S, 'calves', ['calves'], ['smith'], 1, ['Full stretch at bottom', '1 s pause top'], { secPerRep: 3 }),
  ex('db-calf-raise', 'Single-leg dumbbell calf raise', S, 'calves', ['calves'], ['dumbbells'], 1, ['Step edge', 'Slow lower'], { unilateral: true, secPerRep: 3 }),
  ex('reverse-wrist-curl', 'Reverse wrist curl', S, 'forearm-antagonist', ['forearms'], ['dumbbells'], 1,
    ['Light weight', 'Balances crimp-heavy flexors'], { secPerRep: 2 }),
  ex('finger-extensions', 'Band finger extensions', S, 'forearm-antagonist', ['forearms'], ['bands'], 1,
    ['Band around fingertips', 'Open hand fully'], { secPerRep: 2 }),
  ex('pronation-supination', 'DB pronation / supination', S, 'forearm-antagonist', ['forearms'], ['dumbbells'], 1,
    ['Hold DB at one end', 'Slow arcs'], { secPerRep: 3 }),

  // ───────────── Power · jumps
  ex('box-jump', 'Box jump', P, 'jump', ['quads', 'glutes', 'calves'], ['plyo-box'], 1,
    ['Max intent', 'Land soft, step down'], { secondary: ['hamstrings'], secPerRep: 6 }),
  ex('broad-jump', 'Broad jump', P, 'jump', ['glutes', 'quads', 'hamstrings'], [], 1,
    ['Big arm swing', 'Stick the landing'], { secondary: ['calves'], secPerRep: 6 }),
  ex('squat-jump', 'Squat jump', P, 'jump', ['quads', 'glutes'], [], 1, ['Quarter dip, explode', 'Reset each rep'], { secondary: ['calves'], secPerRep: 5 }),
  ex('lateral-bound', 'Lateral bound', P, 'jump', ['glutes', 'adductors'], [], 2,
    ['Push sideways', 'Stick 1 s on landing leg'], { secondary: ['quads'], unilateral: true, secPerRep: 4 }),
  ex('depth-jump', 'Depth jump', P, 'jump', ['quads', 'glutes', 'calves'], ['plyo-box'], 3,
    ['Step off, minimal ground contact', 'Rebound vertically'], { secPerRep: 8 }),
  ex('trap-bar-jump', 'Trap bar jump', P, 'jump', ['quads', 'glutes'], ['trap-bar'], 2,
    ['~20–30% DL 1RM', 'Land soft, reset'], { secondary: ['hamstrings', 'upper-back'], secPerRep: 6 }),

  // ───────────── Power · throws
  ex('med-ball-chest-pass', 'Med ball chest pass (wall)', P, 'throw', ['chest', 'triceps'], ['med-ball'], 1,
    ['Step and throw', 'Max speed'], { secondary: ['front-delts'], secPerRep: 3 }),
  ex('rotational-throw', 'Rotational med ball throw', P, 'throw', ['obliques', 'glutes'], ['med-ball'], 1,
    ['Load back hip', 'Hips lead, arms follow'], { secondary: ['abs'], unilateral: true, secPerRep: 4 }),
  ex('ball-slam', 'Slam ball slam', P, 'throw', ['lats', 'abs'], ['slam-ball'], 1,
    ['Full extension overhead', 'Slam through floor'], { secondary: ['triceps'], secPerRep: 3 }),
  ex('overhead-back-throw', 'Overhead backward throw', P, 'throw', ['glutes', 'hamstrings'], ['med-ball'], 2,
    ['Dip and drive', 'Throw over head behind'], { secondary: ['lower-back', 'front-delts'], secPerRep: 6 }),

  // ───────────── Power · ballistic
  ex('kb-swing', 'Kettlebell swing', P, 'ballistic', ['glutes', 'hamstrings'], ['kettlebells'], 1,
    ['Hike pass', 'Snap hips, bell floats'], { secondary: ['lower-back', 'forearms'], secPerRep: 2 }),
  ex('kb-snatch', 'Kettlebell snatch', P, 'ballistic', ['glutes', 'hamstrings', 'side-delts'], ['kettlebells'], 3,
    ['Punch through at top', 'No bell flop'], { secondary: ['upper-back'], unilateral: true, secPerRep: 3 }),
  ex('hang-power-clean', 'Hang power clean', P, 'ballistic', ['glutes', 'quads', 'upper-back'], ['barbell'], 3,
    ['Jump & shrug', 'Fast elbows'], { secondary: ['hamstrings', 'forearms'], gripHeavy: true, secPerRep: 6 }),
  ex('sled-sprint', 'Sled push sprint', P, 'ballistic', ['quads', 'glutes'], ['sled'], 1,
    ['Low body angle', '10–15 m all-out'], { secondary: ['calves'], unit: 'sec' }),

  // ───────────── Power · upper plyo
  ex('plyo-push-up', 'Plyometric push-up', P, 'upper-plyo', ['chest', 'triceps'], [], 2,
    ['Hands leave floor', 'Absorb landing'], { secondary: ['front-delts'], secPerRep: 3 }),
  ex('explosive-pull-up', 'Explosive pull-up', P, 'upper-plyo', ['lats', 'upper-back'], ['pullup-bar'], 2,
    ['Max speed up — dyno power', 'Slow 3 s lower'], { secondary: ['biceps', 'forearms'], gripHeavy: true, secPerRep: 5 }),
  ex('battle-rope-slams', 'Battle rope slams', P, 'upper-plyo', ['front-delts', 'lats'], ['battle-rope'], 1,
    ['Hips loaded', 'Max power each wave'], { secondary: ['abs'], unit: 'sec' }),

  // ───────────── Cardio machines (also used for warm-up raise)
  ex('rower', 'Rower', C, 'general', ['lats', 'quads'], ['rower'], 1, ['Legs-body-arms', 'Damper 4–6'], { secondary: ['hamstrings', 'upper-back'] }),
  ex('ski-erg', 'SkiErg', C, 'general', ['lats', 'triceps'], ['ski-erg'], 1, ['Hinge & crunch', 'Arms stay long'], { secondary: ['abs'] }),
  ex('air-bike', 'Air bike', C, 'general', ['quads'], ['air-bike'], 1, ['Push & pull arms'], { secondary: ['front-delts'] }),
  ex('bike', 'Bike', C, 'general', ['quads'], ['bike'], 1, ['Cadence 85–95'], { secondary: ['calves'] }),
  ex('treadmill-run', 'Treadmill run', C, 'general', ['quads', 'calves'], ['treadmill'], 1, ['1% incline', 'Relaxed shoulders'], { secondary: ['hamstrings'] }),
  ex('incline-walk', 'Incline treadmill walk', C, 'general', ['glutes', 'calves'], ['treadmill'], 1, ['10–12% incline', 'No holding rails — approach hikes'], { secondary: ['hamstrings'] }),
  ex('stair-climber', 'Stair climber', C, 'general', ['glutes', 'quads'], ['stair-climber'], 1, ['Tall posture', 'Hands off rails'], { secondary: ['calves'] }),
  ex('elliptical', 'Cross-trainer', C, 'general', ['quads'], ['elliptical'], 1, ['Low impact', 'Use arms'], { secondary: ['glutes'] }),

  // ───────────── Warm-up drills
  ex('worlds-greatest', 'World\'s greatest stretch', W, 'general', ['hip-flexors', 'adductors'], [], 1, ['Lunge, elbow to instep, rotate up'],
    { regions: ['hips', 'thoracic'], unit: 'reps' }),
  ex('leg-swings', 'Leg swings (front & side)', W, 'general', ['hamstrings', 'adductors'], [], 1, ['Relaxed, growing range'], { regions: ['hips'], unit: 'reps' }),
  ex('hip-90-90', '90/90 hip switches', W, 'general', ['glutes', 'hip-flexors'], ['mat'], 1, ['Tall spine', 'No hands if possible'], { regions: ['hips'], unit: 'reps' }),
  ex('inchworm', 'Inchworm', W, 'general', ['hamstrings', 'abs'], [], 1, ['Walk out to plank, walk back'], { regions: ['spine', 'shoulders'], unit: 'reps' }),
  ex('band-dislocates', 'Band shoulder dislocates', W, 'general', ['rotator-cuff', 'chest'], ['bands'], 1, ['Wide grip', 'Arms straight'], { regions: ['shoulders'], unit: 'reps' }),
  ex('cat-cow', 'Cat-cow', W, 'general', ['lower-back', 'abs'], ['mat'], 1, ['Segment by segment'], { regions: ['spine'], unit: 'reps' }),
  ex('glute-bridge', 'Glute bridge', W, 'general', ['glutes'], ['mat'], 1, ['Squeeze 2 s top'], { regions: ['hips'], unit: 'reps' }),
  ex('scap-push-up', 'Scapular push-up', W, 'general', ['chest', 'rotator-cuff'], [], 1, ['Arms straight, move shoulder blades only'], { regions: ['shoulders'], unit: 'reps' }),
  ex('squat-to-stand', 'Squat-to-stand', W, 'general', ['hamstrings', 'adductors'], [], 1, ['Grab toes, drop hips, lift chest'], { regions: ['hips', 'ankles'], unit: 'reps' }),
  ex('arm-circles', 'Arm circles & swings', W, 'general', ['front-delts', 'side-delts'], [], 1, ['Small to big'], { regions: ['shoulders'], unit: 'reps' }),
  ex('lunge-twist', 'Walking lunge with twist', W, 'general', ['quads', 'obliques'], [], 1, ['Rotate over front leg'], { regions: ['hips', 'thoracic'], unit: 'reps' }),
  ex('wrist-prep', 'Wrist & finger prep', W, 'general', ['forearms'], [], 1, ['Circles, rocks, finger flicks'], { regions: ['wrists'], unit: 'reps' }),

  // ───────────── Mobility (climber focus)
  ex('frog-rockback', 'Frog rock-backs', M, 'general', ['adductors'], ['mat'], 1, ['Knees wide, rock hips back', 'Drop-knee & bridging range'], { regions: ['hips'], unit: 'reps' }),
  ex('deep-squat-pry', 'Deep squat hold with pry', M, 'general', ['adductors', 'calves'], [], 1, ['Elbows push knees out', 'Shift side to side'], { regions: ['hips', 'ankles'], unit: 'sec' }),
  ex('bw-cossack', 'Bodyweight Cossack shifts', M, 'general', ['adductors', 'hamstrings'], [], 1, ['Slow, heel down'], { regions: ['hips'], unit: 'reps' }),
  ex('pancake-gm', 'Pancake good morning', M, 'general', ['hamstrings', 'adductors'], ['mat'], 2, ['Wide straddle seated', 'Hinge forward, active reach'], { regions: ['hips', 'spine'], unit: 'reps' }),
  ex('hip-flexor-lift', 'Active hip flexor lift-offs', M, 'general', ['hip-flexors'], ['mat'], 1, ['Seated, lift straight leg', 'High-step strength'], { regions: ['hips'], unit: 'reps' }),
  ex('hip-car', 'Hip CARs', M, 'general', ['glutes', 'hip-flexors'], [], 1, ['Slow full circles', 'Pelvis still'], { regions: ['hips'], unit: 'reps' }),
  ex('wall-slide', 'Wall slides', M, 'general', ['rotator-cuff', 'upper-back'], [], 1, ['Low back on wall', 'Forearms stay on wall'], { regions: ['shoulders'], unit: 'reps' }),
  ex('shoulder-car', 'Shoulder CARs', M, 'general', ['rotator-cuff'], [], 1, ['Fist tight, ribs down', 'Biggest painless circle'], { regions: ['shoulders'], unit: 'reps' }),
  ex('open-book', 'Open book', M, 'general', ['upper-back', 'chest'], ['mat'], 1, ['Knees stacked', 'Follow hand with eyes'], { regions: ['thoracic'], unit: 'reps' }),
  ex('thread-needle', 'Thread the needle', M, 'general', ['upper-back', 'rear-delts'], ['mat'], 1, ['Reach under then open up'], { regions: ['thoracic', 'shoulders'], unit: 'reps' }),
  ex('t-spine-roller', 'T-spine extension on roller', M, 'general', ['upper-back'], ['foam-roller'], 1, ['Hands behind head', 'Segment by segment'], { regions: ['thoracic'], unit: 'reps' }),
  ex('wrist-car', 'Wrist CARs & finger stretch', M, 'general', ['forearms'], [], 1, ['Slow circles', 'Open fingers wide'], { regions: ['wrists'], unit: 'reps' }),
  ex('knee-to-wall', 'Knee-to-wall ankle mobilisation', M, 'general', ['calves'], [], 1, ['Heel down', 'Knee over toes'], { regions: ['ankles'], unit: 'reps' }),
  ex('jefferson-curl', 'Jefferson curl (light)', M, 'general', ['hamstrings', 'lower-back'], ['dumbbells', 'plyo-box'], 3, ['Very light', 'Roll down one vertebra at a time'], { regions: ['spine'], unit: 'reps' }),

  // ───────────── Cool-down stretches
  ex('pec-stretch', 'Doorway / rack pec stretch', X, 'general', ['chest', 'front-delts'], [], 1, ['Elbow at shoulder height', 'Step through'], { unit: 'sec', unilateral: true }),
  ex('lat-stretch', 'Kneeling lat stretch on bench', X, 'general', ['lats', 'triceps'], ['bench'], 1, ['Elbows on bench, sink chest'], { unit: 'sec' }),
  ex('childs-pose-reach', 'Child\'s pose side reach', X, 'general', ['lats', 'lower-back', 'upper-back'], ['mat'], 1, ['Walk hands to one side'], { unit: 'sec' }),
  ex('cross-body', 'Cross-body shoulder stretch', X, 'general', ['rear-delts', 'rotator-cuff', 'upper-back'], [], 1, ['Pull arm at elbow'], { unit: 'sec', unilateral: true }),
  ex('sleeper-stretch', 'Sleeper stretch', X, 'general', ['rotator-cuff'], ['mat'], 1, ['Gentle — no pinch'], { unit: 'sec', unilateral: true }),
  ex('triceps-stretch', 'Overhead triceps stretch', X, 'general', ['triceps', 'lats'], [], 1, ['Elbow to ceiling'], { unit: 'sec', unilateral: true }),
  ex('biceps-wall', 'Wall biceps stretch', X, 'general', ['biceps', 'front-delts'], [], 1, ['Thumb down, turn away'], { unit: 'sec', unilateral: true }),
  ex('forearm-flexor', 'Forearm flexor stretch', X, 'general', ['forearms'], [], 1, ['Fingers back, arm straight', 'Essential after crimping'], { unit: 'sec', unilateral: true }),
  ex('forearm-extensor', 'Forearm extensor stretch', X, 'general', ['forearms'], [], 1, ['Fist down, arm straight'], { unit: 'sec', unilateral: true }),
  ex('couch-stretch', 'Couch stretch', X, 'general', ['quads', 'hip-flexors'], ['bench'], 1, ['Squeeze glute', 'Torso upright'], { unit: 'sec', unilateral: true }),
  ex('half-kneeling-hf', 'Half-kneeling hip flexor stretch', X, 'general', ['hip-flexors', 'quads'], ['mat'], 1, ['Tuck pelvis', 'Reach arm up'], { unit: 'sec', unilateral: true }),
  ex('hamstring-stretch', 'Supine hamstring stretch', X, 'general', ['hamstrings', 'calves'], ['bands'], 1, ['Band around foot', 'Straight leg'], { unit: 'sec', unilateral: true }),
  ex('pigeon', 'Pigeon pose', X, 'general', ['glutes', 'hip-flexors'], ['mat'], 1, ['Square hips', 'Fold forward'], { unit: 'sec', unilateral: true }),
  ex('figure-4', 'Supine figure-4', X, 'general', ['glutes'], ['mat'], 1, ['Pull thigh to chest'], { unit: 'sec', unilateral: true }),
  ex('butterfly', 'Butterfly stretch', X, 'general', ['adductors'], ['mat'], 1, ['Tall spine, knees down'], { unit: 'sec' }),
  ex('frog-stretch', 'Frog stretch', X, 'general', ['adductors', 'hip-flexors'], ['mat'], 1, ['Knees wide, shins parallel'], { unit: 'sec' }),
  ex('calf-wall', 'Wall calf stretch', X, 'general', ['calves'], [], 1, ['Straight then bent knee'], { unit: 'sec', unilateral: true }),
  ex('supine-twist', 'Supine twist', X, 'general', ['lower-back', 'obliques', 'glutes'], ['mat'], 1, ['Shoulders flat'], { unit: 'sec', unilateral: true }),
  ex('sphinx', 'Sphinx / cobra', X, 'general', ['abs', 'hip-flexors'], ['mat'], 1, ['Relax glutes', 'Long neck'], { unit: 'sec' }),
  ex('side-bend', 'Standing side bend', X, 'general', ['obliques', 'lats'], [], 1, ['Reach up and over'], { unit: 'sec', unilateral: true }),
  ex('behind-back-clasp', 'Behind-back clasp', X, 'general', ['front-delts', 'chest', 'biceps'], [], 1, ['Clasp, lift hands, open chest'], { unit: 'sec' }),
  ex('upper-trap', 'Neck & upper-trap stretch', X, 'general', ['upper-back'], [], 1, ['Ear to shoulder, opposite hand down'], { unit: 'sec', unilateral: true }),
  ex('breathing', '90/90 breathing (down-regulate)', X, 'general', [], ['mat'], 1, ['Feet on bench, 4 s in / 6–8 s out', 'Shift into recovery'], { unit: 'sec' }),
];

export const EXERCISE_BY_ID: Record<string, Exercise> = Object.fromEntries(EXERCISES.map((e) => [e.id, e]));

export const getExercise = (id: string): Exercise => {
  const e = EXERCISE_BY_ID[id];
  if (!e) throw new Error(`Unknown exercise: ${id}`);
  return e;
};
