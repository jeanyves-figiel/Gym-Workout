#!/usr/bin/env python3
"""Generate MonkeyWorkout's exercise pictures (#170): three frames (start, middle, end) per exercise.

Each catalog exercise has a scene (scenes*.py: poses + drawn equipment) rendered by art.py: a shaded
anatomical figure with the worked muscles in the app's load colours, the machine or equipment, and a
small front/back muscle map. Frames are rasterised to palette PNGs (transparent background; the app
draws the category gradient behind them).

Writes ios/MonkeyWorkout/Resources/Illustrations.xcassets/illustration-<id>-<frame>.imageset, the
Swift id list ios/Packages/GymCore/Sources/WorkoutEngine/Exercise+Illustrations.swift and the media
ledger ios/EXERCISE_MEDIA.md.

    python3 ios/Tools/illustrations/generate.py              # write assets (needs cairosvg, Pillow)
    python3 ios/Tools/illustrations/sample.py out.png ids…   # contact sheet for review
"""
import importlib
import io
import json
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import art  # noqa: E402

IOS = HERE.parent.parent
CATALOG = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+Catalog.swift"
TRAVEL = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+Travel.swift"
VARIATIONS = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+Variations.swift"
ASSETS = IOS / "MonkeyWorkout/Resources/Illustrations.xcassets"
SWIFT_OUT = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercise+Illustrations.swift"
LEDGER = IOS / "EXERCISE_MEDIA.md"

SCENE_MODULES = ["scenes", "scenes_lower", "scenes_upper", "scenes_arms_core", "scenes_power", "scenes_mobility",
                 "scenes_extra", "scenes_var_lower", "scenes_var_push", "scenes_var_pull", "scenes_var_core"]
FRAMES = 3
SIZE = (720, 540)

# Category gradients (Theme.swift), for contact sheets.
GRADIENT = {"warmup": ("#FF8A00", "#FFC93D"), "power": ("#FF2D55", "#FF6FB5"),
            "strength": ("#2F6BFF", "#8A4DFF"), "mobility": ("#A64DFF", "#FF4DD8"),
            "cardio": ("#00C9A7", "#2EC5FF"), "stretch": ("#1ED98A", "#B6FF6B")}


def catalog():
    src = CATALOG.read_text() + TRAVEL.read_text() + VARIATIONS.read_text()
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


def render(ex_id, cat, all_scenes):
    """SVG strings for the exercise's frames (start, middle, end)."""
    entry = all_scenes[ex_id]
    if callable(entry):  # custom renderer (e.g. a hand close-up): returns the frames itself
        return entry(cat[ex_id])
    scene, poses, view = entry
    return [art.render(p, cat[ex_id], scene, prefix=f"f{i}", view=view) for i, p in enumerate(art.frames(poses))]


def to_png(svg):
    import cairosvg
    from PIL import Image

    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=SIZE[0], output_height=SIZE[1])
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
    frames = {}
    for ex_id in cat:
        f = render(ex_id, cat, all_scenes)
        if len(f) != FRAMES:
            raise SystemExit(f"{ex_id}: {len(f)} frames, want {FRAMES}")
        frames[ex_id] = f
    return cat, frames


def write(cat, frames):
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir(parents=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for ex_id, svgs in sorted(frames.items()):
        for f, svg in enumerate(svgs):
            name = f"illustration-{ex_id}-{f}"
            d = ASSETS / f"{name}.imageset"
            d.mkdir()
            (d / f"{name}.png").write_bytes(to_png(svg))
            (d / "Contents.json").write_text(json.dumps({
                "images": [{"filename": f"{name}.png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }, indent=2) + "\n")

    ids = ",\n".join(f'        "{i}"' for i in sorted(frames))
    SWIFT_OUT.write_text(f"""// Generated by ios/Tools/illustrations/generate.py — do not edit by hand.

/// Every catalog exercise is illustrated with MonkeyWorkout's own art (#170): start, middle and end of the
/// movement, worked muscles highlighted, equipment drawn. Asset names: `illustration-<id>-<frame>` in the
/// app's Illustrations.xcassets. Source + license of each exercise's media: ios/EXERCISE_MEDIA.md.
public enum ExerciseIllustrations {{
    /// Frames per illustration: start, middle, end position.
    public static let frameCount = {FRAMES}
    public static let credit = "Illustration: MonkeyWorkout"

    public static let ids: Set<String> = [
{ids},
    ]

    public static func assetName(_ exerciseId: String, frame: Int) -> String {{
        "illustration-\\(exerciseId)-\\(frame)"
    }}
}}

extension Exercise {{
    /// True when the exercise has one of the app's illustrations (every catalog exercise does).
    public var hasIllustration: Bool {{ ExerciseIllustrations.ids.contains(id) }}

    /// Asset names of the illustration frames (start, middle, end). Empty without an illustration.
    public var illustrationAssets: [String] {{
        guard hasIllustration else {{ return [] }}
        return (0..<ExerciseIllustrations.frameCount).map {{ ExerciseIllustrations.assetName(id, frame: $0) }}
    }}

    /// Every catalog exercise has media.
    public var hasMedia: Bool {{ hasIllustration }}
}}
""")

    rows = [f"| `{ex_id}` | {ex['name']} | Illustration ({FRAMES} frames) | Own work, `ios/Tools/illustrations` | "
            f"MonkeyWorkout (own) |" for ex_id, ex in cat.items()]
    LEDGER.write_text(f"""# Exercise media ledger

Generated by `ios/Tools/illustrations/generate.py`. Every catalog exercise is illustrated with the app's
own art (#170): a shaded anatomical figure in three frames (start, middle, end of the movement), the
worked muscles in the app's load colours (primary red, secondary amber), the machine or equipment drawn
in the scene, and a small front/back muscle map. No third-party images or video.

Illustrations: {len(frames)} · Total: {len(cat)}

| Id | Exercise | Media | Source | License |
|---|---|---|---|---|
""" + "\n".join(rows) + "\n")


if __name__ == "__main__":
    cat, frames = build()
    write(cat, frames)
    print(f"{len(frames)} illustrated, {len(cat)} total")
