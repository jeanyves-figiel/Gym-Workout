#!/usr/bin/env python3
"""Generate MonkeyWorkout's exercise pictures (#170): 17 to 49 frames per exercise (#229: start, middle and end
key poses + eased in-betweens; tweens.py adds hand-made in-betweens; #256: as many frames as the movement needs,
see frame_count) and the movement data (motion.py).

Each catalog exercise has a scene (scenes*.py: poses + drawn equipment) rendered by art.py: a shaded
anatomical figure with the worked muscles in the app's load colours, the machine or equipment, and a
small front/back muscle map. Frames are rasterised to palette PNGs (transparent background; the app
draws the category gradient behind them).

Writes ios/MonkeyWorkout/Resources/Illustrations.xcassets/illustration-<id>-<frame>.imageset, the
Swift id list ios/Packages/GymCore/Sources/WorkoutEngine/Exercise+Illustrations.swift, the movement table
ExerciseMotion+Table.swift next to it and the media ledger ios/EXERCISE_MEDIA.md. Check every animation first:
python3 ios/Tools/illustrations/check.py

    python3 ios/Tools/illustrations/generate.py              # write assets (needs cairosvg, Pillow)
    python3 ios/Tools/illustrations/sample.py out.png ids…   # contact sheet for review
"""
import importlib
import io
import json
import math
import re
import shutil
from concurrent.futures import ProcessPoolExecutor
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import art  # noqa: E402
import cycles  # noqa: E402
import motion  # noqa: E402
import tweens  # noqa: E402

IOS = HERE.parent.parent
CATALOG = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+Catalog.swift"
TRAVEL = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+Travel.swift"
VARIATIONS = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+Variations.swift"
GYMAPP = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+GymApp.swift"
CLIMBING = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+Climbing.swift"
ASSETS = IOS / "MonkeyWorkout/Resources/Illustrations.xcassets"
SWIFT_OUT = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercise+Illustrations.swift"
MOTION_OUT = IOS / "Packages/GymCore/Sources/WorkoutEngine/ExerciseMotion+Table.swift"
LEDGER = IOS / "EXERCISE_MEDIA.md"

SCENE_MODULES = ["scenes", "scenes_lower", "scenes_upper", "scenes_arms_core", "scenes_power", "scenes_mobility",
                 "scenes_extra", "scenes_var_lower", "scenes_var_push", "scenes_var_pull", "scenes_var_core",
                 "scenes_gym_machines", "scenes_gym_free", "scenes_gym_props", "scenes_gym_calis",
                 "scenes_gym_mobility", "scenes_climb", "scenes_gym_gaps"]
FRAMES = art.FRAMES  # the default; fast, large movements get more (TIERS)
# #256: an exercise gets the fewest frames of TIERS at which no joint moves more than MAX_STEP of the picture's
# width between two frames (a bigger jump reads as flicker while the movement plays).
TIERS = (17, 25, 33, 49)
MAX_STEP = 0.035
SIZE = (720, 540)
# In-betweens show for a fraction of a second while the movement plays: drawn smaller to keep the app light.
TWEEN_SIZE = (540, 405)

# Category gradients (Theme.swift), for contact sheets.
GRADIENT = {"warmup": ("#FF8A00", "#FFC93D"), "power": ("#FF2D55", "#FF6FB5"),
            "strength": ("#2F6BFF", "#8A4DFF"), "mobility": ("#A64DFF", "#FF4DD8"),
            "cardio": ("#00C9A7", "#2EC5FF"), "stretch": ("#1ED98A", "#B6FF6B")}


def catalog():
    src = CATALOG.read_text() + TRAVEL.read_text() + VARIATIONS.read_text() + GYMAPP.read_text() + CLIMBING.read_text()
    out = {}
    for m in re.finditer(r'Exercise\(id: "([^"]+)", name: "([^"]+)", category: \.(\w+), pattern: \.[\w`]+, '
                         r'primary: \[([^\]]*)\](?:, secondary: \[([^\]]*)\])?', src):
        mus = lambda s: [p.strip().lstrip(".") for p in (s or "").split(",") if p.strip()]
        out[m.group(1)] = dict(name=m.group(2), category=m.group(3), primary=mus(m.group(4)),
                               secondary=mus(m.group(5)))
    return out


def scenes():
    out = {}
    for name in SCENE_MODULES:
        for ex_id, scene in importlib.import_module(name).SCENES.items():
            if ex_id in out:
                raise SystemExit(f"{ex_id}: scene defined twice")
            out[ex_id] = scene
    return out


def max_step(joints):
    """Largest distance (share of the picture's width) any joint moves between two frames."""
    fr = [j for j, _ in joints]
    w = joints[0][1][2]
    names = [k for k in fr[0] if not k.startswith("_") and isinstance(fr[0][k], tuple)
             and all(k in j and j[k][0] > -1000 for j in fr)]
    return max((math.dist(a[k], b[k]) for a, b in zip(fr, fr[1:]) for k in names), default=0) / w


_COUNTS = {}


def frame_count(ex_id, cat, all_scenes):
    """Frames the exercise is drawn with: the first of TIERS whose largest step stays within MAX_STEP."""
    if ex_id not in _COUNTS:
        for n in TIERS:
            joints = []
            _render(ex_id, cat, all_scenes, joints, n)
            if max_step(joints) <= MAX_STEP:
                break
        _COUNTS[ex_id] = n
    return _COUNTS[ex_id]


def render(ex_id, cat, all_scenes, joints=None):
    """Frames of the exercise at its frame count (frame_count); art.FRAMES / art.KEYS are set to it."""
    return _render(ex_id, cat, all_scenes, joints, frame_count(ex_id, cat, all_scenes))


def _render(ex_id, cat, all_scenes, joints, n):
    """SVG strings for the exercise's n frames (start, eased in-betweens, end; middle key at n // 2).
    `joints` (a list) receives each frame's (joints, view) as drawn, for motion.py."""
    art.use_frames(n)
    if joints is not None:
        joints.clear()
    entry = all_scenes[ex_id]
    if callable(entry):  # custom renderer (3D arm states): returns the frames itself
        out = []
        art_render = art.render

        def rec(*a, **k):
            svg = art_render(*a, **k)
            if joints is not None:
                joints.append(art.LAST)
            return svg
        art.render = rec
        try:
            out = entry(cat[ex_id])
        finally:
            art.render = art_render
        return out
    scene, poses, view = entry
    out = []
    extra = tweens.EXTRA[ex_id](art.keyframes(poses)) if ex_id in tweens.EXTRA else None
    # A gait or a machine that turns (#719): one whole cycle, played forward and wrapped, evenly worked.
    cyclic = ex_id in cycles.CYCLIC
    for i, p in enumerate(cycles.poses(ex_id, poses) if cyclic else art.frames(poses, extra)):
        out.append(art.render(p, cat[ex_id], scene, prefix=f"f{i}", view=view, heat=1.0 if cyclic else art.glow(i)))
        if joints is not None:
            joints.append(art.LAST)
    return out


def motion_of(ex_id, joints):
    frames = [j for j, _ in joints]
    return motion.analyse(ex_id, frames, joints[0][1], front="hipN" in frames[0])  # frontal() adds hipN


def to_png(svg, size=SIZE):
    import cairosvg
    from PIL import Image

    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=size[0], output_height=size[1])
    im = Image.open(io.BytesIO(png)).convert("RGBA")
    out = io.BytesIO()
    im.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(out, "PNG", optimize=True)
    return out.getvalue()


def build():
    cat = catalog()
    all_scenes = scenes()
    missing = sorted(set(cat) - set(all_scenes))
    if missing:
        raise SystemExit(f"no scene for: {missing}")
    stale = sorted(set(all_scenes) - set(cat))
    if stale:
        raise SystemExit(f"scenes for exercises not in the catalog: {stale}")
    frames, motions = {}, {}
    for ex_id in cat:
        joints = []
        f = render(ex_id, cat, all_scenes, joints)
        if len(f) != art.FRAMES:
            raise SystemExit(f"{ex_id}: {len(f)} frames, want {art.FRAMES}")
        frames[ex_id] = f
        motions[ex_id] = motion_of(ex_id, joints)
    return cat, frames, motions


def write(cat, frames, motions):
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir(parents=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    jobs = [(f"illustration-{ex_id}-{f}", svg, SIZE if f in (0, len(svgs) // 2, len(svgs) - 1) else TWEEN_SIZE)
            for ex_id, svgs in sorted(frames.items()) for f, svg in enumerate(svgs)]
    with ProcessPoolExecutor() as pool:
        pngs = pool.map(to_png, [svg for _, svg, _ in jobs], [size for _, _, size in jobs], chunksize=16)
        for (name, _, _), png in zip(jobs, pngs):
            d = ASSETS / f"{name}.imageset"
            d.mkdir()
            (d / f"{name}.png").write_bytes(png)
            (d / "Contents.json").write_text(json.dumps({
                "images": [{"filename": f"{name}.png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }, indent=2) + "\n")

    ids = ",\n".join(f'        "{i}"' for i in sorted(frames))
    counts = ",\n".join(f'        "{i}": {len(f)}' for i, f in sorted(frames.items()) if len(f) != FRAMES)
    SWIFT_OUT.write_text(f"""// Generated by ios/Tools/illustrations/generate.py — do not edit by hand.

/// Every catalog exercise is illustrated with MonkeyWorkout's own art (#170): the movement in {FRAMES} frames, more
/// for fast, large movements (#256: `frameCounts`) (#229: start, eased in-betweens, middle key, end), worked
/// muscles highlighted, equipment drawn. Asset names: `illustration-<id>-<frame>` in the app's
/// Illustrations.xcassets. Source + license of each exercise's media: ios/EXERCISE_MEDIA.md.
public enum ExerciseIllustrations {{
    /// Frames of most illustrations: start (0), eased in-betweens, end (frameCount - 1).
    public static let frameCount = {FRAMES}
    /// Exercises drawn with more frames than `frameCount` (#256), so a big movement never jumps between frames.
    public static let frameCounts: [String: Int] = [
{counts},
    ]
    public static let credit = "Illustration: MonkeyWorkout"

    public static let ids: Set<String> = [
{ids},
    ]

    /// Frames of the exercise's illustration (0 without one).
    public static func frameCount(of exerciseId: String) -> Int {{
        ids.contains(exerciseId) ? frameCounts[exerciseId] ?? frameCount : 0
    }}

    /// Start, middle and end frames of `count` frames (the hand-drawn key poses).
    public static func keyFrames(_ count: Int) -> [Int] {{
        [0, count / 2, count - 1]
    }}

    public static func assetName(_ exerciseId: String, frame: Int) -> String {{
        "illustration-\\(exerciseId)-\\(frame)"
    }}
}}

extension Exercise {{
    /// True when the exercise has one of the app's illustrations (every catalog exercise does).
    public var hasIllustration: Bool {{ ExerciseIllustrations.ids.contains(id) }}

    /// Asset names of the illustration frames (start … end). Empty without an illustration.
    public var illustrationAssets: [String] {{
        (0..<ExerciseIllustrations.frameCount(of: id)).map {{ ExerciseIllustrations.assetName(id, frame: $0) }}
    }}

    /// Every catalog exercise has media.
    public var hasMedia: Bool {{ hasIllustration }}
}}
""")

    def num(v):
        return f"{v:.3f}".rstrip("0").rstrip(".") if v else "0"
    entries = []
    for ex_id in sorted(motions):
        mo = motions[ex_id]
        path = ", ".join(num(v) for p in mo["path"] for v in p)
        cyclic = ", cyclic: true" if mo.get("cyclic") else ""
        entries.append(f'        "{ex_id}": ExerciseMotion("{mo["first"]}", "{mo["second"]}", '
                       f'effortFirst: {str(mo["effort_first"]).lower()}, path: [{path}]{cyclic}),')
    MOTION_OUT.write_text("// Generated by ios/Tools/illustrations/generate.py (motion.py) — do not edit by hand.\n\n"
                          "extension ExerciseMotion {\n"
                          "    /// Movement of every illustrated exercise (#229), by exercise id.\n"
                          "    public static let table: [String: ExerciseMotion] = [\n"
                          + "\n".join(entries) + "\n    ]\n}\n")

    rows = [f"| `{ex_id}` | {ex['name']} | Illustration ({len(frames[ex_id])} frames) | Own work, `ios/Tools/illustrations` | "
            f"MonkeyWorkout (own) |" for ex_id, ex in cat.items()]
    LEDGER.write_text(f"""# Exercise media ledger

Generated by `ios/Tools/illustrations/generate.py`. Every catalog exercise is illustrated with the app's
own art (#170): a shaded anatomical figure in {FRAMES} to {max(TIERS)} frames (start to end of the movement, #229, #256), the
worked muscles in the app's load colours (primary red, secondary amber), the machine or equipment drawn
in the scene, and a small front/back muscle map. No third-party images or video.

Illustrations: {len(frames)} · Total: {len(cat)}

| Id | Exercise | Media | Source | License |
|---|---|---|---|---|
""" + "\n".join(rows) + "\n")


if __name__ == "__main__":
    cat, frames, motions = build()
    write(cat, frames, motions)
    print(f"{len(frames)} illustrated, {len(cat)} total")
