#!/usr/bin/env python3
"""Generate MonkeyWorkout's own exercise illustrations (SVG, two frames: start + end).

Writes ios/MonkeyWorkout/Resources/Illustrations.xcassets/<id>-<frame>.imageset and the Swift id
list ios/Packages/GymCore/Sources/WorkoutEngine/Exercise+Illustrations.swift, then the media
ledger ios/EXERCISE_MEDIA.md (source + license of every exercise's media).

    python3 ios/Tools/illustrations/generate.py            # write assets
    python3 ios/Tools/illustrations/generate.py --preview out.png   # + contact sheet (needs cairosvg, Pillow)
"""
import json
import math
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import figure  # noqa: E402
from poses import POSES  # noqa: E402

IOS = HERE.parent.parent
CATALOG = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercises+Catalog.swift"
PHOTOS = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercise+Images.swift"
ASSETS = IOS / "MonkeyWorkout/Resources/Illustrations.xcassets"
SWIFT_OUT = IOS / "Packages/GymCore/Sources/WorkoutEngine/Exercise+Illustrations.swift"
LEDGER = IOS / "EXERCISE_MEDIA.md"

# Highlight colour per category (lime, except where the gradient itself is lime/yellow).
ACCENT = {"strength": "#CCFF3D", "power": "#CCFF3D", "cardio": "#CCFF3D", "mobility": "#CCFF3D",
          "warmup": "#B84A00", "stretch": "#0B7A4B"}
GRADIENT = {"warmup": ("#FF8A00", "#FFC93D"), "power": ("#FF2D55", "#FF6FB5"),
            "strength": ("#2F6BFF", "#8A4DFF"), "mobility": ("#A64DFF", "#FF4DD8"),
            "cardio": ("#00C9A7", "#2EC5FF"), "stretch": ("#1ED98A", "#B6FF6B")}


def catalog():
    src = CATALOG.read_text()
    out = {}
    for m in re.finditer(r'Exercise\(id: "([^"]+)", name: "([^"]+)", category: \.(\w+), pattern: \.\w+, '
                         r'primary: \[([^\]]*)\]', src):
        out[m.group(1)] = dict(name=m.group(2), category=m.group(3),
                               primary=[p.strip().lstrip(".") for p in m.group(4).split(",") if p.strip()])
    return out


def photo_ids():
    return dict(re.findall(r'^\s+"([^"]+)":\s+"([^"]+)",', PHOTOS.read_text(), re.M))


def svg_doc(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {figure.W} {figure.H}" '
            f'width="{figure.W}" height="{figure.H}">' + "".join(body) + "</svg>\n")


def render_pose(pose, ex):
    j = figure.place(pose)
    lit = {seg for m in ex["primary"] for seg in figure.MUSCLE_SEGMENTS.get(m, [])}
    body = [] if pose.get("top_down") else figure.p_floor(j)
    body += figure.props_svg(j, pose.get("props", []))
    body += figure.figure_svg(j, lit, ACCENT[ex["category"]], front=pose.get("front", False))
    s = pose.get("scale")
    if s:  # shrink tall poses about the floor centre so they fit the frame
        cx, cy = figure.W / 2, figure.FLOOR + 8
        body = [f'<g transform="translate({cx} {cy}) scale({s}) translate({-cx} {-cy})">'] + body + ["</g>"]
    return svg_doc(body)


def hand_closeup(spread):
    """Finger extensions against a band: a large hand, fingers together (0) or spread (1)."""
    W = "#FFFFFF"
    cx, cy = 200, 190
    body = [figure._line((cx, cy + 20), (cx, 300), 46, W, 0.9)]  # forearm
    body.append(f'<ellipse cx="{cx}" cy="{cy}" rx="38" ry="34" fill="{W}"/>')
    tips = []
    for i, base_ang in enumerate([-120, -100, -80, -60]):
        ang = base_ang + (i - 1.5) * (14 if spread else 0)
        if not spread:
            ang = -90 + (i - 1.5) * 4
        a = math.radians(ang)
        base = (cx + (i - 1.5) * 18, cy - 24)
        tip = (base[0] + math.cos(a) * 70, base[1] + math.sin(a) * 70)
        tips.append(tip)
        body.append(figure._line(base, tip, 15, W))
    thumb_ang = math.radians(-150 if spread else -125)
    tb = (cx - 30, cy + 2)
    thumb = (tb[0] + math.cos(thumb_ang) * 50, tb[1] + math.sin(thumb_ang) * 50)
    body.append(figure._line(tb, thumb, 16, W))
    # Band looped round the finger tips.
    pts = tips + [thumb]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    bx, by = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2 + 12
    rx, ry = (max(xs) - min(xs)) / 2 + 10, 14
    body.append(f'<ellipse cx="{bx:.1f}" cy="{by:.1f}" rx="{rx:.1f}" ry="{ry}" fill="none" stroke="#0A0D10" '
                f'stroke-opacity="0.55" stroke-width="6"/>')
    if spread:
        for side in (-1, 1):
            x0 = bx + side * (rx + 12)
            body += figure.p_motion({}, (x0, by), 0 if side > 0 else 180, 18)
    return svg_doc(body)


CUSTOM = {"finger-extensions": lambda ex: [hand_closeup(False), hand_closeup(True)]}


def build():
    cat = catalog()
    photos = photo_ids()
    missing = [i for i in cat if i not in photos]
    svgs = {}
    for ex_id in missing:
        ex = cat[ex_id]
        if ex_id in CUSTOM:
            svgs[ex_id] = CUSTOM[ex_id](ex)
        elif ex_id in POSES:
            svgs[ex_id] = [render_pose(p, ex) for p in POSES[ex_id]]
        else:
            raise SystemExit(f"no photo and no pose for {ex_id}")
    stale = set(POSES) - set(missing)
    if stale:
        raise SystemExit(f"poses defined for exercises that already have a photo: {sorted(stale)}")
    return cat, photos, svgs


def write(cat, photos, svgs):
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir(parents=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for ex_id, frames in sorted(svgs.items()):
        for f, svg in enumerate(frames):
            name = f"illustration-{ex_id}-{f}"
            d = ASSETS / f"{name}.imageset"
            d.mkdir()
            (d / f"{name}.svg").write_text(svg)
            (d / "Contents.json").write_text(json.dumps({
                "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
                "properties": {"preserves-vector-representation": True},
            }, indent=2) + "\n")

    ids = ",\n".join(f'        "{i}"' for i in sorted(svgs))
    SWIFT_OUT.write_text(f"""// Generated by ios/Tools/illustrations/generate.py — do not edit by hand.

/// Exercises illustrated with MonkeyWorkout's own drawings (no free-exercise-db photo matches).
/// Asset names: `illustration-<id>-<frame>` in the app's Illustrations.xcassets.
public enum ExerciseIllustrations {{
    /// Frames per illustration (start + end position).
    public static let frameCount = 2
    public static let credit = "Illustration: MonkeyWorkout"

    public static let ids: Set<String> = [
{ids},
    ]

    public static func assetName(_ exerciseId: String, frame: Int) -> String {{
        "illustration-\\(exerciseId)-\\(frame)"
    }}
}}
""")

    rows = []
    for ex_id, ex in cat.items():
        if ex_id in photos:
            src = (f"[free-exercise-db `{photos[ex_id]}`](https://github.com/yuhonas/free-exercise-db/tree/"
                   f"f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5/exercises/{photos[ex_id]})")
            rows.append(f"| `{ex_id}` | {ex['name']} | Photo (2 frames) | {src} | Public domain (Unlicense) |")
        else:
            rows.append(f"| `{ex_id}` | {ex['name']} | Illustration (2 frames) | "
                        f"Own work, `ios/Tools/illustrations` | MonkeyWorkout (own) |")
    LEDGER.write_text(f"""# Exercise media ledger

Generated by `ios/Tools/illustrations/generate.py`. Every catalog exercise has media; this table
records its source and license. Photos are pinned to free-exercise-db commit
`f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5` (Unlicense, public domain: commercial use allowed, no
attribution required; the app still credits it). Illustrations are drawn by the app's own generator.

No video: no free-to-use (public domain / CC0 / CC-BY) video set covers this catalog consistently,
so every exercise animates its two frames (start, end) instead.

Photos: {len(photos)} · Illustrations: {len(svgs)} · Total: {len(cat)}

| Id | Exercise | Media | Source | License |
|---|---|---|---|---|
""" + "\n".join(rows) + "\n")


def preview(svgs, cat, out, size=(200, 150), only=None):
    import io
    import cairosvg
    from PIL import Image, ImageDraw

    items = [(i, f) for i in sorted(svgs) if not only or i in only for f in range(2)]
    cols = 8
    w, h = size
    sheet = Image.new("RGB", (cols * w, math.ceil(len(items) / cols) * (h + 14)), "#090A0E")
    d = ImageDraw.Draw(sheet)
    for n, (i, f) in enumerate(items):
        c0, c1 = GRADIENT[cat[i]["category"]]
        g = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><defs><linearGradient id="g" x2="1" y2="1">'
             f'<stop offset="0" stop-color="{c0}"/><stop offset="1" stop-color="{c1}"/></linearGradient></defs>'
             f'<rect width="400" height="300" fill="url(#g)"/>' + svgs[i][f].split(">", 1)[1])
        png = cairosvg.svg2png(bytestring=g.encode(), output_width=w, output_height=h)
        x, y = (n % cols) * w, (n // cols) * (h + 14)
        sheet.paste(Image.open(io.BytesIO(png)), (x, y + 14))
        d.text((x + 3, y + 1), f"{i} {f}", fill="white")
    sheet.save(out)


if __name__ == "__main__":
    cat, photos, svgs = build()
    if "--preview" in sys.argv:
        only = sys.argv[sys.argv.index("--preview") + 2:] or None
        preview(svgs, cat, sys.argv[sys.argv.index("--preview") + 1], only=only)
    else:
        write(cat, photos, svgs)
        print(f"{len(svgs)} illustrated, {len(photos)} photos, {len(cat)} total")
