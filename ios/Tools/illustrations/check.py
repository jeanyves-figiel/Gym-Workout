#!/usr/bin/env python3
"""Coherence check of every exercise animation (#229).

    python3 ios/Tools/illustrations/check.py [ids…]

Renders each exercise's frames (SVG only, no PNG) and flags: a joint jumping between two frames, a body part
stretching or shrinking, the figure leaving the picture or sinking into the floor, an angle that turns the
long way round (> 180° between key poses), and the motion data (tracked point, phase labels). Exit 1 on any
flag that is not listed in ALLOWED with a reason.
"""
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import art  # noqa: E402
import generate  # noqa: E402

BONES = [("hip", "kneeN"), ("kneeN", "ankleN"), ("hip", "kneeF"), ("kneeF", "ankleF"), ("hip", "shoulder"),
         ("shoulder", "elbowN"), ("elbowN", "wristN"), ("shoulder", "elbowF"), ("elbowF", "wristF")]
# Reviewed on contact sheets (#229, 2026-10-13): the flag is expected for these movements.
FAST = "fast, large movement: big steps between frames"
VIEWED = "reviewed frame by frame: reads correctly (foreshortened 3D arm, wide swing, or pre-existing key pose)"
ALLOWED = {
    "battle-rope-slams": FAST,
    "box-jump": FAST,
    "broad-jump": FAST,
    "burpee": FAST,
    "db-snatch": FAST,
    "depth-jump": FAST,
    "hang-power-clean": FAST,
    "kb-high-pull": FAST,
    "kb-snatch": FAST,
    "kb-swing": FAST,
    "man-maker": FAST,
    "med-ball-scoop-toss": FAST,
    "overhead-back-throw": FAST,
    "power-clean": FAST,
    "rotational-throw": FAST,
    "squat-jump": FAST,
    "squat-to-stand": FAST,
    "back-lever": VIEWED,
    "cable-external-rotation": VIEWED,
    "cable-low-high-chop": VIEWED,
    "cable-rear-delt-fly": VIEWED,
    "curtsy-lunge": VIEWED,
    "hip-90-90": VIEWED,
    "kb-halo": VIEWED,
    "landmine-rotation": VIEWED,
    "lunge-twist": VIEWED,
    "mountain-climber": VIEWED,
    "russian-twist": VIEWED,
    "shoulder-car": VIEWED,
    "side-lying-external-rotation": VIEWED,
    "thread-needle": VIEWED,
    "turkish-get-up": VIEWED,
    "wall-sit": VIEWED,
    "windshield-wipers": VIEWED,
    "worlds-greatest": VIEWED,
}


def angle_wraps(poses):
    keys = art.keyframes(poses)
    out = []
    if not any(p.get("front") for p in keys):
        return out  # side view: limbs interpolate as joint angles within their range (art.JOINT_WINDOWS)
    for a, b in zip(keys, keys[1:]):
        for k, va in a.items():
            vb = b.get(k)
            if k in ("lift", "scale", "curl", "pin", "inset", "front", "lit_sides"):
                continue
            vals = list(zip(va, vb)) if isinstance(va, tuple) and isinstance(vb, tuple) else [(va, vb)]
            for x, y in vals:
                if k in art.ANGLES and isinstance(x, (int, float)) and isinstance(y, (int, float)):
                    turn = art._turn(x, y) - x
                    if abs(turn) > 150:
                        out.append(f"{k} turns {turn:+.0f}° (ambiguous direction)")
    return out


def check(ex_id, cat, scenes):
    joints = []
    generate.render(ex_id, cat, scenes, joints)
    flags = []
    if len(joints) != art.FRAMES:
        return [f"{len(joints)} frames"], None
    view = joints[0][1]
    x0, y0, w = view
    h = w * art.H / art.W
    fr = [j for j, _ in joints]
    # Joints a scene parks off-screen (an arm redrawn by the scene, e.g. open-book) are not checked.
    names = [k for k in fr[0] if not k.startswith("_") and isinstance(fr[0][k], tuple)
             and all(k in j and j[k][0] > -1000 for j in fr)]
    for k in names:
        steps = [math.dist(a[k], b[k]) for a, b in zip(fr, fr[1:]) if k in a and k in b]
        if steps and max(steps) > 0.25 * w:
            flags.append(f"{k} jumps {max(steps) / w:.0%} of the picture in one frame")
    keys = [fr[i] for i in art.KEYS]
    # In-betweens must stay within what the key poses (the reviewed art) already do.
    for a, b in BONES:
        if not all(a in j and b in j for j in fr):
            continue
        kl = [math.dist(j[a], j[b]) for j in keys]
        for i, j in enumerate(fr):
            ln = math.dist(j[a], j[b])
            if ln > max(kl) * 1.12 + 1 or ln < min(kl) / 1.12 - 1:
                flags.append(f"{a}–{b} length {ln:.0f} in frame {i} (keys {min(kl):.0f}–{max(kl):.0f})")
                break
    m = 0.02 * w

    def outside(j):
        return [k for k in names if not (x0 - m <= j[k][0] <= x0 + w + m and y0 - m <= j[k][1] <= y0 + h + m)]

    def low(j):
        return max(j[k][1] for k in names if k.startswith(("ankle", "toe", "knee", "hip", "hand", "head")))
    key_out = {k for j in keys for k in outside(j)}
    key_low = max(low(j) for j in keys)
    for i, j in enumerate(fr):
        out = [k for k in outside(j) if k not in key_out]
        if out:
            flags.append(f"{out[0]} leaves the picture in frame {i}")
        if low(j) > max(key_low, art.GROUND) + 6:
            flags.append(f"sinks {low(j) - max(key_low, art.GROUND):.0f}px into the floor in frame {i}")
    entry = scenes[ex_id]
    if not callable(entry):
        flags += angle_wraps(entry[1])
    return sorted(set(flags)), generate.motion_of(ex_id, joints)


def main(ids):
    cat = generate.catalog()
    scenes = generate.scenes()
    bad = 0
    rows = []
    for ex_id in ids or sorted(cat):
        flags, mo = check(ex_id, cat, scenes)
        if mo:
            eff = mo["first"] if mo["effort_first"] else mo["second"]
            rows.append(f"{ex_id:34} {cat[ex_id]['category']:9} {mo['track']:8} {mo['first']:>4}/{mo['second']:<4} "
                        f"effort {eff:4} path {'yes' if mo['path'] else 'no '}")
        if flags and ex_id not in ALLOWED:
            bad += 1
            print(f"FLAG {ex_id}: " + "; ".join(flags))
    Path(HERE / "motion-table.txt").write_text("\n".join(rows) + "\n") if not ids else print("\n".join(rows))
    print(f"{bad} flagged")
    return bad


if __name__ == "__main__":
    sys.exit(1 if main(sys.argv[1:]) else 0)
