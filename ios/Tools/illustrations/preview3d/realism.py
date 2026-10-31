#!/usr/bin/env python3
"""Realism check of the 3D position guide (#1020): poses the skinned body takes from ExercisePositions.json.z.

    python3 realism.py [DATA] [ex ...]          # report, exit 1 when any key fails
    REALISM_JSON=out.json python3 realism.py    # also write the per-key findings
    python3 realism.py --ratchet                # CI: exit 1 only on a finding not in realism-baseline.json
    python3 realism.py --write-baseline         # accept the current findings as the baseline
    JOBS=4 ...                                  # parallel workers (default: CPU count)

Per key pose (start / middle / end) it flags:
  grip      a hand that holds a bar / handle / weight but whose fist is not on it (> 6 off the bar axis, > r + 6
            off a weight), and a free hand right next to a bar the exercise lifts with both hands
  through   a bar, plate, dumbbell or kettlebell passing through the body (points of the object inside the skin)
  limb      forearm / hand sunk into the trunk or legs, shin / foot sunk into the other leg
  stretch   an arm or leg scaled past 1.12 (rig stretches a limb to reach a target the figure could not)
  floor     body or equipment sunk below the floor
"""
import json
import os
import sys
import zlib
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import rig as rigmod  # noqa: E402

rigmod.MUSH = 0
DEFAULT = HERE.parent.parent.parent / "Packages/GymCore/Sources/WorkoutEngine/Resources/ExercisePositions.json.z"

STRETCH = 1.06
GRIP_ROD = 6.0
INSIDE = 1.5          # depth (units ≈ cm) below the skin that counts as inside


class Body:
    def __init__(self):
        self.R = R = rigmod.Rig()
        names = R.names

        def mask(pred):
            return np.isin(R.bi[:, 0], [R.ix[n] for n in names if pred(n)])
        self.fing = {s: mask(lambda n, s=s: n.startswith("finger") and n.endswith("." + s)) for s in "LR"}
        self.hand = {s: mask(lambda n, s=s: n.startswith(("finger", "metacarpal", "wrist")) and n.endswith("." + s)) for s in "LR"}
        self.fore = {s: mask(lambda n, s=s: n.startswith(("lowerarm", "wrist", "finger", "metacarpal")) and n.endswith("." + s)) for s in "LR"}
        self.arm = {s: mask(lambda n, s=s: n.startswith(("upperarm", "lowerarm", "wrist", "finger", "metacarpal", "shoulder", "clavicle"))
                             and n.endswith("." + s)) for s in "LR"}
        self.shin = {s: mask(lambda n, s=s: n.startswith(("lowerleg", "foot", "toe")) and n.endswith("." + s)) for s in "LR"}
        self.leg = {s: mask(lambda n, s=s: n.startswith(("upperleg", "lowerleg", "foot", "toe")) and n.endswith("." + s)) for s in "LR"}
        self.F = R.F

    def normals(self, V):
        F = self.F
        fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        N = np.zeros_like(V)
        for c in range(3):
            np.add.at(N, F[:, c], fn)
        return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)


def inside_depth(tree, V, N, idx, P):
    """Depth of points P below the skin of the vertex subset (tree over V[idx]): > 0 inside."""
    d, i = tree.query(P)
    v = idx[i]
    s = -np.einsum("ij,ij->i", P - V[v], N[v])
    return np.where(d < 14, s, -1.0)


def rod_points(p, step=1.2):
    a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
    n = max(2, int(np.linalg.norm(b - a) / step))
    return a + np.linspace(0, 1, n)[:, None] * (b - a)


def disc_points(p):
    c = np.asarray(p["c"], float); ax = np.array([1.0, 0, 0]) if p.get("ax") == "x" else np.array([0, 0, 1.0])
    u = rigmod.nrm(np.cross(ax, [0.3, 1.0, 0.1])); w = np.cross(ax, u)
    r = float(p.get("r", 10))
    out = [c]
    for rr in (r * 0.5, r * 0.95):
        for t in np.linspace(0, 2 * np.pi, 16, endpoint=False):
            out.append(c + rr * (np.cos(t) * u + np.sin(t) * w))
    return np.array(out)


def ball_points(p, frac=0.8):
    c = np.asarray(p["c"], float); r = float(p.get("r", 8)) * frac
    dirs = np.array([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], float)
    return np.vstack([c, c + r * dirs])


def side_map(J):
    up = J["shoulder"] - J["hip"]; toe = rigmod.facing(J)
    chir = np.linalg.det(np.stack([rigmod.perp(toe, rigmod.nrm(up)), up, J["shoulderF"] - J["shoulderN"]]))
    return {"N": "L", "F": "R"} if chir > 0 else {"N": "R", "F": "L"}


def check_key(B, ex, k):
    R = B.R
    V = R.pose(k["j"], k["p"]) + np.array([0, k.get("dy", 0), 0])
    N = B.normals(V)
    J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
    S = side_map(J)
    out = []
    fists = {}
    for d in "NF":
        s = S[d]
        g = V[B.fing[s]].mean(0)
        fists[d] = g
        h = R.held[d]
        if h and h[0] == "rod":
            a, b = h[2]; ab = b - a
            t = np.clip(((g - a) @ ab) / (ab @ ab), 0, 1)
            gap = np.linalg.norm(g - (a + t * ab))
            if gap > GRIP_ROD:
                out.append(("grip", f"hand{d} {gap:.0f} off bar"))
        elif h and h[0] in ("db", "kb", "ball"):
            c = np.asarray(h[2], float)
            r = next((float(p.get("r", 8)) for p in k["p"] if p["k"] == h[0] and np.allclose(p["c"], c)), 8.0)
            gap = np.linalg.norm(g - c) - r
            if gap > 7:
                out.append(("grip", f"hand{d} {gap:.0f} off {h[0]}"))
        else:
            for p in k["p"]:
                if p["k"] == "rod" and p.get("s") not in ("cable", "band"):
                    P = rod_points(p, 2.0)
                    dist = np.linalg.norm(P - g, axis=1).min()
                    if dist < 9 and p.get("s") == "handle":
                        out.append(("grip", f"free hand{d} on handle {dist:.0f}"))
    # equipment through the body (fists and 9 around them may touch)
    idx = np.arange(len(V))
    tree = cKDTree(V)
    near_fist = lambda P: np.min([np.linalg.norm(P - f, axis=1) for f in fists.values()], 0) < 11
    for i, p in enumerate(k["p"]):
        if p["k"] == "rod" and p.get("s") not in ("cable", "band"):
            P = rod_points(p)
        elif p["k"] == "disc":
            P = disc_points(p)
        elif p["k"] in ("db", "kb"):
            P = ball_points(p)
        else:
            continue
        P = P[~near_fist(P)]
        if not len(P):
            continue
        dep = inside_depth(tree, V, N, idx, P)
        n_in = int((dep > INSIDE).sum())
        if n_in >= 3:
            out.append(("through", f"{p['k']}{i}{'/' + p['s'] if 's' in p else ''} {n_in}pts {dep.max():.0f}deep"))
    # limbs inside trunk / legs
    for s in "LR":
        other = np.where(~B.arm[s])[0]
        t2 = cKDTree(V[other])
        P = V[B.fore[s]]
        dep = inside_depth(t2, V, N, other, P)
        n_in = int((dep > 2.5).sum())
        if n_in > 40:
            out.append(("limb", f"arm{s} {n_in}v {dep.max():.0f}deep"))
    for s, o in (("L", "R"), ("R", "L")):
        other = np.where(B.leg[o])[0]
        t2 = cKDTree(V[other])
        dep = inside_depth(t2, V, N, other, V[B.shin[s]])
        n_in = int((dep > 2.5).sum())
        if n_in > 40:
            out.append(("limb", f"leg{s} in leg{o} {n_in}v {dep.max():.0f}deep"))
    for lk, kv in R.stretch.items():
        if kv > STRETCH:
            out.append(("stretch", f"{lk} x{kv:.2f}"))
    y0 = float(V[~(B.fing["L"] | B.fing["R"]), 1].min())      # fingertips may tuck under a flat hand
    if y0 < -3:
        out.append(("floor", f"body {y0:.0f} below floor"))
    for i, p in enumerate(k["p"]):
        lo = None
        if p["k"] in ("block",):
            lo = p["lo"][1]
        elif p["k"] in ("disc", "db", "kb", "ball", "roller"):
            lo = p["c"][1] - p.get("r", 8)
        if lo is not None and lo < -3:
            out.append(("floor", f"{p['k']}{i} {lo:.0f} below floor"))
    return out


BASELINE = HERE / "realism-baseline.json"


def _run(args):
    data, ids = args
    d = json.loads(zlib.decompress(Path(data).read_bytes(), -15))
    B = Body()
    return {ex: [check_key(B, ex, k) for k in d[ex]["k"]] for ex in ids}


def main():
    args = sys.argv[1:]
    flags = {a for a in args if a.startswith("--")}
    args = [a for a in args if not a.startswith("--")]
    data = Path(args.pop(0)) if args and args[0].endswith(".z") else DEFAULT
    d = json.loads(zlib.decompress(data.read_bytes(), -15))
    ids = args or sorted(d)
    jobs = int(os.environ.get("JOBS", os.cpu_count() or 1))
    if jobs > 1 and len(ids) > 8:
        from multiprocessing import Pool
        with Pool(jobs) as pool:
            parts = pool.map(_run, [(str(data), ids[i::jobs]) for i in range(jobs)])
        res = {k: v for part in parts for k, v in part.items()}
    else:
        res = _run((str(data), ids))
    res = {ex: res[ex] for ex in ids}
    bad, counts = 0, {}
    found = {}
    for ex, keys in res.items():
        if any(keys):
            bad += 1
            kinds = sorted({c for ks in keys for c, _ in ks})
            found[ex] = kinds
            for c in kinds:
                counts[c] = counts.get(c, 0) + 1
            print(ex, " | ".join(f"k{i}: " + ", ".join(m for _, m in ks) for i, ks in enumerate(keys) if ks), flush=True)
    print(f"{bad}/{len(ids)} exercises flagged", counts)
    if os.environ.get("REALISM_JSON"):
        Path(os.environ["REALISM_JSON"]).write_text(json.dumps(res))
    if "--write-baseline" in flags:
        BASELINE.write_text(json.dumps(found, indent=0, sort_keys=True) + "\n")
        print("baseline written:", BASELINE)
        return
    if "--ratchet" in flags:
        base = json.loads(BASELINE.read_text())
        new = [(ex, c) for ex, kinds in found.items() for c in kinds if c not in base.get(ex, [])]
        fixed = [(ex, c) for ex, kinds in base.items() if ex in res for c in kinds if c not in found.get(ex, [])]
        for ex, c in new:
            print(f"NEW {c}: {ex}")
        if fixed:
            print(f"{len(fixed)} baseline findings fixed: run with --write-baseline to lock them in")
        sys.exit(1 if new else 0)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
