#!/usr/bin/env python3
"""Kit contact check of every 2D exercise animation (#1020, next to check.py).

    python3 ios/Tools/illustrations/kit2d.py [ids…]
    python3 ios/Tools/illustrations/kit2d.py --shard 0/4    # every 4th exercise from the first (CI runs 4)

Draws each frame's equipment alone (no figure, floor or muscle map), rasterises it and measures how far each
hand and foot is from the nearest drawn kit. Flags:
  grip   a hand that holds kit in a key pose (within GRIP px) drifts more than LOST px off it in another frame
  feet   a foot that stands on kit in a key pose (plate, platform, step) drifts more than LOST px off it
  float  no hand, foot, knee or hip touches the floor or the kit in a frame (the figure hangs in the air)
Exit 1 on any flag not listed in KIT_ALLOWED with a reason.
"""
import io
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import art  # noqa: E402
import generate  # noqa: E402

GRIP = 4.0  # px (scene units): a hand this close to kit holds it
LOST = 9.0  # px: further than this from all kit in another frame = grip or footing lost
REST = 6.0  # px: a body point this close to the floor or kit is supported
SCALE = 2  # raster pixels per scene unit
# Reviewed on frame sheets (#1020, 2026-10-31): the flag is expected for these movements.
AIR = "airborne by design: jump, throw follow-through or running stride"
ROLL = "rests on the foam roller and the hands: the roller sits under the calf or thigh, not a joint"
HELD = "kit drawn end-on (plate, sandbag) a few px from the hand: reads as held"
KIT_ALLOWED = {**{k: AIR for k in ("box-jump", "depth-jump", "overhead-back-throw", "treadmill-run")},
               **{k: ROLL for k in ("foam-roll-calves", "foam-roll-hamstrings")},
               **{k: HELD for k in ("barbell-thruster", "overhead-triceps", "sandbag-shouldering")}}

HANDS = ("handN", "handF")
FEET = ("ankleN", "ankleF", "toeN", "toeF")
SUPPORT = HANDS + FEET + ("kneeN", "kneeF", "hip", "shoulder", "head", "elbowN", "elbowF")
# Joint centre to skin (scene px): a lying or sitting body rests on its seat, back or skull, not on the joint centre.
FLESH = {"hip": 18, "shoulder": 16, "head": 16, "kneeN": 8, "kneeF": 8, "elbowN": 6, "elbowF": 6}


def _kit_only(fn):
    noop = lambda *a, **k: None  # noqa: E731
    saved = {n: getattr(art, n) for n in ("draw_figure", "inset", "floor", "shadow", "motion")}
    for n in saved:
        setattr(art, n, noop)
    try:
        return fn()
    finally:
        for n, f in saved.items():
            setattr(art, n, f)


def _field(svg, view):
    """Distance (scene units) to the nearest kit pixel, as a function of a scene point."""
    import cairosvg
    x0, y0, w = view
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=art.W * SCALE, output_height=art.H * SCALE)
    a = np.asarray(Image.open(io.BytesIO(png)).convert("RGBA"))[:, :, 3] > 60
    if not a.any():
        return None
    d = ndimage.distance_transform_edt(~a)
    px = art.W * SCALE / w

    def at(p):
        c, r = int(round((p[0] - x0) * px)), int(round((p[1] - y0) * px))
        if 0 <= r < d.shape[0] and 0 <= c < d.shape[1]:
            return d[r, c] / px
        return math.inf
    return at


def check(ex_id, cat, scenes):
    joints = []
    svgs = _kit_only(lambda: generate.render(ex_id, cat, scenes, joints))
    fields = [_field(s, v) for s, (_, v) in zip(svgs, joints)]
    if not any(fields):
        return []
    fr = [j for j, _ in joints]
    keys = [k for k in art.KEYS if k < len(fr)]
    flags = []

    def dist(i, k):
        return fields[i](fr[i][k]) if fields[i] and k in fr[i] and isinstance(fr[i][k], tuple) else math.inf

    def on_floor(i, k):
        return k in fr[i] and isinstance(fr[i][k], tuple) and fr[i][k][1] >= art.GROUND - REST - 4 - FLESH.get(k, 0)
    for group, kind in ((HANDS, "grip"), (FEET[:2], "feet")):
        for k in group:
            held = [i for i in keys if dist(i, k) <= GRIP and not on_floor(i, k)]
            if len(held) < len(keys):
                continue  # only a contact every key pose keeps must hold through the in-betweens
            worst = max(((dist(i, k), i) for i in range(len(fr)) if not on_floor(i, k)), default=None)
            if worst and worst[0] > LOST:
                flags.append(f"{kind} {k} {worst[0]:.0f}px off the kit in frame {worst[1]}")
    for i, j in enumerate(fr):
        pts = [k for k in SUPPORT if k in j and isinstance(j[k], tuple)]
        if any(on_floor(i, k) or dist(i, k) <= REST + FLESH.get(k, 0) for k in pts):
            continue
        low = min(art.GROUND - j[k][1] for k in pts)
        flags.append(f"float {low:.0f}px above the floor, off the kit in frame {i}")
        break
    return flags


def main(ids):
    cat = generate.catalog()
    scenes = generate.scenes()
    bad = 0
    if ids[:1] == ["--shard"]:
        i, n = map(int, ids[1].split("/"))
        ids = sorted(cat)[i::n]
    for ex_id in ids or sorted(cat):
        try:
            flags = check(ex_id, cat, scenes)
        except Exception as e:  # noqa: BLE001
            flags = [f"error {e!r}"]
        if flags and ex_id not in KIT_ALLOWED:
            bad += 1
            print(f"FLAG {ex_id}: " + "; ".join(flags), flush=True)
    print(f"{bad} flagged")
    return bad


if __name__ == "__main__":
    sys.exit(1 if main(sys.argv[1:]) else 0)
