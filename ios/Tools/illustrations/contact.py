#!/usr/bin/env python3
"""Realism pass over ExercisePositions.json.z with the real body (rig.py): equipment the 2D scenes placed for the
stick figure is fitted to the skinned body, and gym machines get their real size.

- pads / blocks the body rests on move to touch it (same shift for every key of an exercise, so benches stay put);
  what is left floating lowers the body (key "dy") unless its feet are on the floor or it hangs from a bar
- a body sunk into the floor is lifted
- cable towers: full-height uprights, top cap, guide rods and a plate stack; racks get base feet
- writes the JSON back and a report of what changed

    python3 contact.py            # whole catalog (minutes)
    python3 contact.py bench-press cable-fly

After any scene change: positions.py (writes the raw export), copy it to RAW, then contact.py over the whole catalog;
committing a bare positions.py export ships bodies off their equipment (#959). Check with preview3d/.
"""
import json, sys, zlib
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import rig as rigmod

DATA = rigmod.DATA
RAW = Path("/tmp/claude-0/positions-raw.json.z")     # pristine positions.py export; contact.py is re-run from it
TOWER_H = 232.0          # ~2.0 m cable tower / rack upright


def pad_frame(p):
    a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
    along = b - a
    L = np.linalg.norm(along)
    n = np.array([p["n"][0], p["n"][1], 0.0])
    t = np.linalg.norm(n)
    nh = n / t if t > 1e-6 else np.array([0, 1.0, 0])
    return a, b, along / max(L, 1e-6), L, nh, t


def support_gap(V, J, p):
    """Gap between the body and a pad/block it lies or sits on (positive = floating), or None when nothing rests there.
    Returns (gap, unit shift direction toward the body)."""
    mid = (np.asarray(J["hip"]) + np.asarray(J["shoulder"])) / 2
    if p["k"] == "pad":
        a, b, u, L, nh, t = pad_frame(p)
        s = 1.0 if (mid - (a + b) / 2) @ nh >= 0 else -1.0
        rel = V - a
        al = rel @ u
        lat = rel[:, 2] - (a[2] + 0 * al)
        w = p.get("w", 0) or 20
        # the pad is drawn from the a→b line out along n (PositionGuideView): its far face is t out on the n side
        dn = (rel @ nh) * s - (t if s > 0 else 0.0)
        cand = (al > -3) & (al < L + 3) & (np.abs(lat) < w + 4) & (dn > -t) & (dn < 14)
        if cand.sum() < 12:
            return None
        return float(dn[cand].min()), nh * s
    if p["k"] in ("block", "mat"):
        lo, hi = np.asarray(p["lo"], float), np.asarray(p["hi"], float)
        if p["k"] == "mat" or hi[1] - lo[1] < 2:
            return None
        top = hi[1]
        cand = (V[:, 0] > lo[0] - 3) & (V[:, 0] < hi[0] + 3) & (V[:, 2] > lo[2] - 3) & (V[:, 2] < hi[2] + 3) \
            & (V[:, 1] > top - 6) & (V[:, 1] < top + 14)
        if cand.sum() < 12:
            return None
        return float(V[cand, 1].min() - top), np.array([0, 1.0, 0])
    return None


def shift_prop(p, dv):
    dv = [float(x) for x in dv]
    if p["k"] == "pad":
        p["a"] = [round(x + d, 1) for x, d in zip(p["a"], dv)]
        p["b"] = [round(x + d, 1) for x, d in zip(p["b"], dv)]
    elif p["k"] in ("block", "mat"):
        p["hi"] = [round(x + d, 1) for x, d in zip(p["hi"], dv)]
        if p["hi"][1] < p["lo"][1] + 2:
            p["lo"][1] = round(p["hi"][1] - 2, 1)


def attach_rods(props, p, dv):
    """Rods that end at a pad's underside (bench legs, frames) follow it."""
    if p["k"] != "pad":
        return
    a, b, u, L, nh, t = pad_frame(p)
    for q in props:
        if q["k"] != "rod":
            continue
        for end in ("a", "b"):
            e = np.asarray(q[end], float)
            rel = e - (a - dv)
            al = rel @ u
            if -4 < al < L + 4 and min(abs(rel @ nh), abs(rel @ nh - t)) < 4 and abs(rel[2]) < (p.get("w") or 20) + 4:
                q[end] = [round(float(x), 1) for x in e + dv]


def is_vertical(p):
    a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
    d = b - a
    return abs(d[1]) > 0.95 * np.linalg.norm(d) + 1e-9 or (abs(d[0]) < 2 and abs(d[2]) < 2 and abs(d[1]) > 60)


def machines(props):
    """Full-size cable towers and racks. Returns the number of uprights completed."""
    done = 0
    uprights = [p for p in props if p["k"] == "rod" and p.get("r", 0) >= 3.5 and is_vertical(p)
                and max(p["a"][1], p["b"][1]) >= 150 and min(p["a"][1], p["b"][1]) <= 8]
    stacks = [p for p in props if p["k"] == "block" and p["hi"][1] - p["lo"][1] >= 90]
    new = []
    for up in uprights:
        top = "a" if up["a"][1] > up["b"][1] else "b"
        x, z = up[top][0], up[top][2]
        near = [s for s in stacks if s["lo"][0] - 14 < x < s["hi"][0] + 14 and s["lo"][2] - 14 < z < s["hi"][2] + 14]
        if near:
            st = near[0]
            if st.get("_done"):
                continue
            st["_done"] = True
            up[top][1] = TOWER_H
            cx, cz = (st["lo"][0] + st["hi"][0]) / 2, (st["lo"][2] + st["hi"][2]) / 2
            # top cap from the upright over the stack, guide rods, plate stack with a pin
            new.append(dict(k="rod", a=[x, TOWER_H, z], b=[cx, TOWER_H, cz], r=3.5))
            new.append(dict(k="block", lo=[min(x, cx) - 5, TOWER_H - 3, min(z, cz) - 5], hi=[max(x, cx) + 5, TOWER_H + 2, max(z, cz) + 5]))
            d = 0.35 * (st["hi"][0] - st["lo"][0])
            for g in (-d, d):
                new.append(dict(k="rod", a=[cx + g, st["lo"][1], cz], b=[cx + g, TOWER_H - 3, cz], r=0.9))
            plate_h, gap = 4.2, 1.0
            n = int(min(12, (st["hi"][1] - st["lo"][1] - 10) // (plate_h + gap)))
            y0 = st["lo"][1]
            lo, hi = st["lo"], st["hi"]
            for i in range(n):
                y = y0 + i * (plate_h + gap)
                new.append(dict(k="block", lo=[lo[0], round(y, 1), lo[2]], hi=[hi[0], round(y + plate_h, 1), hi[2]]))
            pin_y = y0 + 3 * (plate_h + gap) + plate_h / 2
            new.append(dict(k="rod", a=[cx, pin_y, hi[2] + 1], b=[cx, pin_y, hi[2] + 7], r=1.2, s="handle"))
            st["hi"][1] = y0 + n * (plate_h + gap) - gap     # the old solid block becomes the base under the plates
            st["lo"][1] = y0 - 0.5; st["hi"][1] = y0 + 0.5
            # base foot on the floor
            new.append(dict(k="rod", a=[x - 22, 1.5, z], b=[max(x, cx) + 22, 1.5, z], r=2.5))
            done += 1
        elif max(up["a"][1], up["b"][1]) >= 200:
            new.append(dict(k="rod", a=[x - 24, 1.5, z], b=[x + 24, 1.5, z], r=2.5))   # rack foot
            done += 1
    props.extend(new)
    for s in stacks:
        s.pop("_done", None)
    return done


def dumbbells(props, J, held, grip):
    """Hand-held weights move into the fist that holds them (the 2D scene put them at the wrist): one weight near
    both hands (goblet, two-hand swing) hangs between them, two of a kind pair up with the hands side by side.
    Dumbbells get the handle axis the hand holds them with (rig.db_axis); a kettlebell hangs below the grip."""
    def place(p, g, d):
        r = min(float(p.get("r", 9)), 9.0)
        if p["k"] == "db":
            if "ax" not in p:
                p["ax"] = [int(x) for x in rigmod.db_axis(J, d)]
            p["r"] = r
            p["c"] = [round(float(x), 1) for x in g]
        elif p["k"] == "kb":
            p["r"] = r
            p["c"] = [round(float(x), 1) for x in g - np.array([0, r + 2.5, 0])]
        else:
            p["c"] = [round(float(x), 1) for x in g]
    hands = [d for d in ("N", "F") if held.get(d) is not None and d in grip]
    kinds = {}
    for p in props:
        if p["k"] in ("db", "kb", "ball") and not (p["k"] == "ball" and p.get("r", 8) > 12):
            kinds.setdefault(p["k"], []).append(p)
    for kind, ps in kinds.items():
        hs = [d for d in hands if held[d][0] == kind]
        if not hs:
            continue
        if len(ps) == 1:
            p = ps[0]; c = np.asarray(p["c"], float)
            close = [d for d in hs if np.linalg.norm(J["hand" + d] - c) < p.get("r", 8) + 16]
            if len(close) == 2:
                place(p, (grip["N"] + grip["F"]) / 2, close[0])
            else:
                d = min(hs, key=lambda d: np.linalg.norm(J["hand" + d] - c))
                place(p, grip[d], d)
        else:
            for p, d in zip(sorted(ps, key=lambda p: p["c"][2]), sorted(hs, key=lambda d: J["hand" + d][2])):
                place(p, grip[d], d)


def hanging(J, held):
    """Hands on a bar above the shoulders, or on rings / straps hanging from overhead."""
    return any(h is not None and h[0] == "rod" and (J["hand" + d][1] > J["shoulder"][1] + 10 or max(h[2][0][1], h[2][1][1]) > 300)
               for d, h in held.items())


UNILATERAL = ("lunge", "split", "step", "single", "one", "pistol", "bulgarian", "skater", "curtsy", "shrimp",
              "side", "traverse", "climb", "crossover", "kick", "bird", "fire", "clamshell", "sprint", "skip", "march")


def mirror_legs(ex, j):
    """A bilateral pose keeps both legs the same: the 2D depth guess scissored them a little."""
    if any(w in ex.split("-") for w in UNILATERAL):
        return False
    J = {n: np.asarray(v, float) for n, v in j.items() if not n.startswith("_")}
    asym = max(np.linalg.norm((J[a + "N"] - J[a + "F"]) * [1, 1, 0]) for a in ("knee", "ankle", "toe"))
    if asym < 0.5 or asym > 12:
        return False
    for a in ("knee", "ankle", "toe"):
        n = J[a + "N"]
        j[a + "F"] = [round(float(n[0]), 1), round(float(n[1]), 1), round(float(-abs(n[2])), 1)]
        j[a + "N"] = [round(float(n[0]), 1), round(float(n[1]), 1), round(float(abs(n[2])), 1)]
    return True


HANG = ("pull-up", "chin-up", "hang", "muscle-up", "toes-to-bar", "static-hold", "repeaters", "recruitment-pulls",
        "monkey-bar", "max-hangs")
NOT_HANG = ("assisted", "lever", "flag", "l-sit", "dip-bar", "archer", "clean", "snatch")


def hangs(ex):
    """Exercises whose body hangs from the hands with the legs free (not kneeling on an assist pad)."""
    return any(w in ex for w in HANG) and not any(w in ex for w in NOT_HANG)


def hang_legs(j, J):
    """Legs trailing under a bar hang: feet together, toes pointed. The 2D scenes drew them as a kneeling
    silhouette with the feet on the floor. Nearly straight 2D legs stay straight (slightly behind the hip);
    bent ones become the classic bent-knee hang, shins back, ankles crossed. Raised legs are left alone."""
    hip = J["hip"]
    th, sn = J["kneeN"] - J["hipN"], J["ankleN"] - J["kneeN"]
    if th[1] > -0.4 * LEG[0] or sn[1] > 0.3 * LEG[1]:
        return False          # knees up, legs forward: a raise or lever, authored by the scene
    if not (J["ankleN"][1] > 15 or abs(sn[0]) > 0.4 * abs(sn[1])):
        return False          # feet planted under the knees: a standing lockout
    straight = np.degrees(np.arccos(np.clip(nrm3(th) @ nrm3(sn), -1, 1))) < 25
    if straight and hip[1] - LEG[0] - LEG[1] + 4 > 12:
        kn = hip + np.array([-2.0, -LEG[0], 0])
        an = kn + np.array([-4.0, -LEG[1] + 2, 0])
        to = an + np.array([4.0, -11.0, 0])
    else:
        kn = hip + np.array([7.0, -LEG[0] + 2, 0])
        an = kn + np.array([-LEG[1] + 4, 5.0, 0])
        to = an + np.array([3.0, -11.0, 0])     # pointed down, a touch forward: the rig reads facing from the feet
    for a, v, z in (("knee", kn, 7.0), ("ankle", an, 4.0), ("toe", to, 4.0)):
        j[a + "N"] = [round(float(v[0]), 1), round(float(v[1]), 1), z]
        j[a + "F"] = [round(float(v[0]), 1), round(float(v[1]), 1), -z]
    return True


LEG = rigmod.LIMB["leg"]


SIDE_FIX = ("prone-ytw", "supine-twist", "archer-push-up", "open-book")


def nrm3(v):
    return v / max(np.linalg.norm(v), 1e-9)


def _rot90(v):
    """Scene drawn lying across the screen but exported as a front/back view: turn it so the body lies along x."""
    return [round(float(v[2]), 1), round(float(v[1]), 1), round(-float(v[0]), 1)]


def lying_scenes(ex, e):
    """Four lying exercises were drawn from the side but exported as front/back views with no depth: every joint sat
    on x = 0 and the body lay along z. Turn them onto the x axis, give near/far limbs their width, and author what
    the drawing could not say (the archer push-up on the floor, the prone YTW's bench and arms, the supine twist's
    legs, the open book's top arm)."""
    if ex not in SIDE_FIX:
        return
    e["v"] = "s"
    for k in e["k"]:
        J = k["j"]
        for n, v in list(J.items()):
            if not n.startswith("_"):
                J[n] = _rot90(v)
        for p in k["p"]:
            for a in ("a", "b", "c"):
                if a in p:
                    p[a] = _rot90(p[a])
            if "lo" in p:
                lo, hi = _rot90(p["lo"]), _rot90(p["hi"])
                p["lo"] = [min(x, y) for x, y in zip(lo, hi)]; p["hi"] = [max(x, y) for x, y in zip(lo, hi)]
            if "n" in p and abs(p["n"][0]) > 1e-6:
                p["n"] = [0.0, p["n"][1] if abs(p["n"][1]) > 1e-6 else 8.0]
        # near / far limbs get the body's width (the figure's near side is +z); lying on the side (open book) the
        # far side is on top instead
        if ex == "open-book":
            for jn in ("shoulder", "elbow", "wrist", "hand"):
                J[jn + "F"] = [J[jn + "N"][0], round(J[jn + "N"][1] + 34, 1), J[jn + "N"][2]]
            for jn in ("hip", "knee", "ankle", "toe"):
                J[jn + "F"] = [J[jn + "N"][0], round(J[jn + "N"][1] + 18, 1), J[jn + "N"][2]]
            J["shoulder"] = [J["shoulderN"][0], round(J["shoulderN"][1] + 17, 1), J["shoulderN"][2]]
            J["hip"] = [J["hipN"][0], round(J["hipN"][1] + 9, 1), J["hipN"][2]]
            continue
        for chain, w in ((("shoulder", "elbow", "wrist", "hand"), 17.0), (("hip", "knee", "ankle", "toe"), 9.0)):
            if abs(J[chain[0] + "N"][2] - J[chain[0] + "F"][2]) < 2:
                for jn in chain:
                    J[jn + "N"][2] = round(J[jn + "N"][2] + w, 1); J[jn + "F"][2] = round(J[jn + "F"][2] - w, 1)
    if ex == "archer-push-up":
        # a push-up with one arm straight out to the side: the standard push-up keys, near arm reaching sideways
        src = json.loads(zlib.decompress(RAW.read_bytes(), -15))["push-up"]
        e["v"] = src.get("v", "s")
        for k, sk in zip(e["k"], src["k"]):
            k["j"] = json.loads(json.dumps(sk["j"])); k["p"] = json.loads(json.dumps(sk["p"]))
            J = k["j"]
            sh = J["shoulderN"]
            J["handN"] = [round(sh[0] + 6, 1), 4.0, round(sh[2] + 62, 1)]
            J["wristN"] = [round(sh[0] + 4, 1), 5.0, round(sh[2] + 54, 1)]
            J["elbowN"] = [round(sh[0] + 2, 1), round(sh[1] * 0.55 + 4, 1), round(sh[2] + 30, 1)]
    if ex == "prone-ytw":
        # face down on a high bench (top under the belly), head toward +x; arms make the Y, T and W
        arms = (((0.8, -0.25, 0.55), (0.85, -0.1, 0.5)), ((0.0, -0.15, 1.0), (0.0, 0.0, 1.0)), ((-0.45, -0.3, 0.85), (0.7, 0.3, 0.6)))
        for (ue, fe), k in zip(arms, e["k"]):
            J = k["j"]; hip, sh = J["hip"], J["shoulder"]
            for d, sgn in (("N", 1.0), ("F", -1.0)):
                S = np.asarray(J["shoulder" + d], float)
                u = nrm3(np.array([ue[0], ue[1], ue[2] * sgn])); f = nrm3(np.array([fe[0], fe[1], fe[2] * sgn]))
                E = S + 42 * u; W = E + 38 * f; H = W + 10 * f
                J["elbow" + d], J["wrist" + d], J["hand" + d] = [[float(x) for x in np.round(v, 1)] for v in (E, W, H)]
            top = min(hip[1], sh[1]) - 9
            k["p"] = [p for p in k["p"] if p["k"] not in ("rod", "db")]
            k["p"].append(dict(k="pad", a=[round(hip[0] - 30, 1), top - 4, 0.0], b=[round(sh[0] + 10, 1), top - 4, 0.0], n=[0.0, 8.0], w=16))
            for x in (hip[0] - 22, sh[0] + 2):
                for z in (-12.0, 12.0):
                    k["p"].append(dict(k="rod", a=[round(x, 1), 0.0, z], b=[round(x, 1), top - 8, z], r=2.0))
    if ex == "supine-twist":
        # on the back, head toward +x, arms out on the floor; bent knees drop to the near side
        for i, k in enumerate(e["k"]):
            J = k["j"]
            hx = J["hip"][0]; sx = J["shoulder"][0]
            J["hip"] = [hx, 10.0, 0.0]; J["shoulder"] = [sx, 14.0, 0.0]
            J["neck"] = [round(sx + 10, 1), 14.0, 0.0]; J["head"] = [round(sx + 28, 1), 15.0, 0.0]
            a = (0.0, 0.5, 1.0)[i] * np.pi / 2

            def drop(v):          # rotate a leg offset about the x axis toward +z (the near side)
                return np.array([v[0], v[1] * np.cos(a) - v[2] * np.sin(a), v[1] * np.sin(a) + v[2] * np.cos(a)])
            for d, sgn in (("N", 1.0), ("F", -1.0)):
                J["shoulder" + d] = [sx, 14.0, 17.0 * sgn]; J["hip" + d] = [hx, 10.0, 9.0 * sgn]
                J["elbow" + d] = [sx, 7.0, 59.0 * sgn]; J["wrist" + d] = [sx, 5.0, 97.0 * sgn]; J["hand" + d] = [sx, 4.0, 107.0 * sgn]
                hp = np.array([hx, 10.0, 9.0 * sgn])
                K = hp + drop(np.array([-40.0, 40.0, 0.0]))
                A = K + drop(np.array([-36.0, -40.0, 0.0]))
                T = A + drop(np.array([14.0, 6.0, 0.0]))
                J["knee" + d], J["ankle" + d], J["toe" + d] = [[float(x) for x in np.round(v, 1)] for v in (K, A, T)]
            k["p"] = [p for p in k["p"] if p["k"] == "mat"]
    if ex == "open-book":
        # lying on the side, knees bent; the top arm sweeps from the under arm over to the floor behind
        for i, k in enumerate(e["k"]):
            J = k["j"]; sh = J["shoulderF"]
            ang = (0.0, 0.5, 1.0)[i] * np.pi
            J["elbowF"] = [round(sh[0], 1), round(sh[1] - 20 * np.cos(ang) + 18 * np.sin(ang), 1), round(sh[2] + 8 + 20 * np.sin(ang), 1)]
            J["wristF"] = [round(sh[0], 1), round(sh[1] - 40 * np.cos(ang) + 30 * np.sin(ang), 1), round(sh[2] + 12 + 40 * np.sin(ang), 1)]
            J["handF"] = [round(sh[0] + 2, 1), round(sh[1] - 48 * np.cos(ang) + 34 * np.sin(ang), 1), round(sh[2] + 14 + 48 * np.sin(ang), 1)]
            J["head"] = [round(J["neck"][0] - 8 - 6 * np.sin(ang), 1), round(J["neck"][1] + 3, 1), round(J["neck"][2] + 10 * np.sin(ang), 1)]


NEUTRAL = ("hammer", "neutral", "farmer", "suitcase", "carry")
ACROSS = ("curl", "press", "bench", "row", "front-raise", "pullover", "skull", "french", "thruster", "snatch", "clean",
          "overhead", "upright", "shrug", "spider", "preacher", "drag", "zottman", "concentration", "jm", "tate")


def grip_axes(ex, keys):
    """Dumbbell handle axis from the grip the exercise uses: palms up or down (curls, presses, rows) hold it
    across the body, neutral grips (hammer curls, carries) along the forearm's swing plane."""
    parts = ex.split("-")
    neutral = any(w in ex for w in NEUTRAL)
    across = any(w in parts or w in ex for w in ACROSS) and not neutral
    sup = "curl" in parts and not neutral and "reverse" not in parts and not any(w in ex for w in ("leg-curl", "nordic", "hamstring", "jefferson", "zottman"))
    for k in keys:
        J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
        if sup:
            for p in k["p"]:
                if p["k"] in ("db", "rod") and p.get("s") != "cable":
                    pts = [np.asarray(p["c"], float)] if p["k"] == "db" else [np.asarray(p["a"], float), np.asarray(p["b"], float)]
                    if p["k"] == "rod":
                        a, b = pts; ab = b - a
                        near = min(np.linalg.norm(a + np.clip(((J["hand" + d] - a) @ ab) / max(ab @ ab, 1e-6), 0, 1) * ab - J["hand" + d]) for d in "NF")
                    else:
                        near = min(np.linalg.norm(pts[0] - J["hand" + d]) for d in "NF")
                    if near < 18:
                        p["pm"] = "sup"
        for p in k["p"]:
            if p["k"] != "db":
                continue
            c = np.asarray(p["c"], float)
            d = min(("N", "F"), key=lambda d: np.linalg.norm(J["hand" + d] - c))
            fa = nrm3(J["wrist" + d] - J["elbow" + d])
            if neutral:
                ax = np.cross(fa, [0, 0, 1.0])
            elif across:
                ax = np.array([0, 0, 1.0])
            else:
                continue
            p["ax"] = [round(float(x), 3) for x in nrm3(ax)]


def cable_bar(ex, keys):
    """A cable handle gripped by both hands close together is a straight bar across both fists, the cable
    clipped to its middle (cable curls, pushdowns, straight-arm pulldowns). Ropes stay ropes."""
    if "rope" in ex or "single" in ex or "one" in ex.split("-"):
        return
    if not any(p["k"] == "rod" and p.get("s") == "cable" for k in keys for p in k["p"]):
        return          # machine handles (leg press side grips) are not a cable bar
    if not any(p["k"] == "rod" and p.get("s") == "handle" for k in keys for p in k["p"]):
        # the scene ran the cable straight into the hands: clip a handle to it where both hands meet
        def cable_end(k, mid):
            ends = [np.asarray(p[e], float) for p in k["p"] if p["k"] == "rod" and p.get("s") == "cable" for e in ("a", "b")]
            return min((np.linalg.norm(e - mid) for e in ends), default=99)
        mids = []
        for k in keys:
            J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
            mid = (J["handN"] + J["handF"]) / 2
            if abs(J["handN"][1] - J["handF"][1]) > 8 or abs(J["handN"][0] - J["handF"][0]) > 10 or cable_end(k, mid) > 20:
                return
            mids.append(mid)
        for k, mid in zip(keys, mids):
            k["p"].append(dict(k="rod", a=[round(float(x), 1) for x in mid], b=[round(float(x), 1) for x in mid + [0, 0, 1]],
                               r=1.6, s="handle"))
    for k in keys:
        J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
        hN, hF = J["handN"], J["handF"]
        if abs(hN[1] - hF[1]) > 8 or abs(hN[0] - hF[0]) > 10 or abs(hN[2] - hF[2]) > 60:
            continue
        mid = (hN + hF) / 2
        hs = [p for p in k["p"] if p["k"] == "rod" and p.get("s") == "handle"
              and min(np.linalg.norm(np.asarray(p[e], float) - mid) for e in ("a", "b")) < 40]
        if not hs:
            continue
        w = abs(hN[2] - hF[2]) / 2 + 10
        h = hs[0]
        h["a"] = [round(float(mid[0]), 1), round(float(mid[1]), 1), round(float(mid[2] - w), 1)]
        h["b"] = [round(float(mid[0]), 1), round(float(mid[1]), 1), round(float(mid[2] + w), 1)]
        h["r"] = 1.6
        if "curl" in ex.split("-"):
            h["pm"] = "sup"
        for p in k["p"]:
            if p["k"] == "rod" and p.get("s") == "cable":
                a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
                e = "a" if np.linalg.norm(a - mid) < np.linalg.norm(b - mid) else "b"
                if np.linalg.norm(np.asarray(p[e], float) - mid) < 50:
                    p[e] = [round(float(x), 1) for x in mid]
        for p in hs[1:]:            # a second handle becomes part of the bar (keys keep the same prop list)
            p["a"], p["b"], p["r"] = list(h["a"]), list(h["b"]), h["r"]
            if "pm" in h:
                p["pm"] = h["pm"]


def _equipment():
    """Catalog equipment per exercise id, read from the GymCore catalog sources."""
    import re
    out = {}
    for f in (HERE.parent.parent / "Packages/GymCore/Sources/WorkoutEngine").glob("Exercises*.swift"):
        for m in re.finditer(r'Exercise\(id: "([^"]+)".*?equipment: \[([^\]]*)\]', f.read_text()):
            out[m.group(1)] = m.group(2)
    return out


EQUIP = _equipment()


def bar_clear(ex, keys, clear=22.0):
    """At the top of a pull-up the 2D head sits against the bar; the body's head is bigger, so the body moves
    back (hands stay on the bar) until the head clears it."""
    if not hangs(ex):
        return
    for k in keys:
        j = k["j"]
        head = np.asarray(j["head"], float)
        for p in k["p"]:
            if p["k"] != "rod" or abs(p["a"][1] - p["b"][1]) > 1 or abs(p["a"][1] - head[1]) > 16:
                continue
            dx = head[0] - p["a"][0]
            if abs(dx) >= clear:
                continue
            shift = (clear - abs(dx)) * (1 if dx >= 0 else -1)
            for n, v in j.items():
                if n.startswith("_") or n.startswith(("hand", "wrist")):
                    continue
                j[n] = [round(v[0] + shift, 1), v[1], v[2]]
            break


def complete(ex, keys):
    """Equipment the 2D scenes drew in shorthand gets its real kind: a short bar in a dumbbell exercise is the
    dumbbell, a ball in a kettlebell exercise is the kettlebell, the ball crunch gets its ball."""
    parts = ex.split("-")
    for k in keys:
        # a scene exported far from the origin (depth recovery ran away) comes back under the camera
        hip = np.asarray(k["j"]["hip"], float)
        if abs(hip[0]) > 200 or abs(hip[2]) > 200:
            off = np.array([hip[0], 0.0, hip[2]])
            for n, v in k["j"].items():
                if not n.startswith("_"):
                    k["j"][n] = [round(float(x), 1) for x in np.asarray(v, float) - off]
            for p in k["p"]:
                for a in ("lo", "hi", "a", "b", "c"):
                    if a in p:
                        p[a] = [round(float(x), 1) for x in np.asarray(p[a], float) - off]
        J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
        P = k["p"]
        kinds = {p["k"] for p in P}
        hands = [J["handN"], J["handF"]]
        dumbbell = "db" in parts or "dumbbell" in parts or (".dumbbells" in EQUIP.get(ex, "") and ".barbell" not in EQUIP.get(ex, ""))
        if dumbbell and "db" not in kinds:
            for p in list(P):
                if p["k"] != "rod" or p.get("s") == "cable":
                    continue
                a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
                L = np.linalg.norm(b - a)
                if L > 34:
                    continue
                mid = (a + b) / 2
                if min(np.linalg.norm(h - mid) for h in hands) < 14:
                    ax = (b - a) / max(L, 1e-6)
                    P.remove(p)
                    P.append(dict(k="db", c=[round(float(x), 1) for x in mid], r=7.0,
                                  ax=[int(round(float(x))) for x in ax]))
        if ("kb" in parts or "kettlebell" in parts) and "kb" not in kinds:
            for p in P:
                if p["k"] == "ball" and min(np.linalg.norm(h - np.asarray(p["c"], float)) for h in hands) < p.get("r", 8) + 8:
                    p["k"] = "kb"; p["r"] = min(float(p.get("r", 9)), 9.0)
        for p in P:          # a mat drawn with depth came out as a wall: flatten it
            if p["k"] == "block" and p["hi"][1] - p["lo"][1] > 60 and J["hip"][1] < 120 \
                    and (p["hi"][2] - p["lo"][2] > 120 or p["hi"][0] - p["lo"][0] > 120):
                p["k"] = "mat"; p["lo"][1] = 0.0; p["hi"][1] = 1.5
        if "goblet" in parts and "kb" not in kinds:
            mid = (J["handN"] + J["handF"]) / 2
            P.append(dict(k="kb", c=[round(float(x), 1) for x in mid - np.array([0, 11.5, 0])], r=9.0))
        if ex == "ball-crunch" and "ball" not in kinds:
            r = 32.0
            P.append(dict(k="ball", c=[round(float(J["hip"][0]), 1), r, 0.0], r=r))
            k["dy"] = round(float(2 * r - 10 - J["hip"][1]), 1)
            k["_ballfix"] = True


def frames(props):
    """A free-hanging pull-up bar gets two uprights to the floor and feet."""
    bars = [p for p in props if p["k"] == "rod" and p.get("s") != "cable" and abs(p["a"][1] - p["b"][1]) < 2
            and min(p["a"][1], p["b"][1]) > 170 and np.linalg.norm(np.asarray(p["a"]) - np.asarray(p["b"])) > 40]
    verts = [p for p in props if p["k"] == "rod" and is_vertical(p) and max(p["a"][1], p["b"][1]) > 150]
    new = []
    for bar in bars:
        y = bar["a"][1]
        for end in ("a", "b"):
            e = np.asarray(bar[end], float)
            if any(min(np.linalg.norm(e - np.asarray(v[q], float)) for q in ("a", "b")) < 10 for v in verts):
                continue
            new.append(dict(k="rod", a=[e[0], 0.0, e[2]], b=[e[0], y, e[2]], r=3.5))
            new.append(dict(k="rod", a=[e[0] - 22, 1.5, e[2]], b=[e[0] + 22, 1.5, e[2]], r=2.5))
    props.extend(new)
    return len(new) // 2


DARK_PART = ("#1C1F24", "#1D2125", "#262A30", "#2A2E34", "#2C3137")
FLYWHEEL = ("air-bike", "rower", "ski-erg")


def machine_parts(ex, keys):
    """Round machine parts the 2D scenes drew as dots become what they are: leg / hip rollers, pivots and pedals are
    padded rollers across the machine, foam rollers are foam cylinders, a fan or flywheel is a wheel (the guide
    showed them as red balls)."""
    for k in keys:
        for p in k["p"]:
            if p["k"] != "ball":
                continue
            col = p.get("col")
            if col in DARK_PART and p.get("r", 8) <= 12:
                p["k"] = "roller"; p["ax"] = [0, 0, 1]
            elif col == "#2B6FB8":
                p["k"] = "foam"; p["ax"] = [0, 0, 1]
            elif p.get("r", 8) > 12 and any(w in ex for w in FLYWHEEL):
                p["k"] = "disc"


def straps(ex, keys):
    """Rings and straps hanging from overhead end in the hands that hold them (the 2D scene stopped them a ring's
    height above the fist)."""
    for k in keys:
        J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
        for p in k["p"]:
            if p["k"] != "rod" or p.get("r", 3) >= 2.5:
                continue
            lo, hi = ("a", "b") if p["a"][1] < p["b"][1] else ("b", "a")
            if p[hi][1] < 300:
                continue
            e = np.asarray(p[lo], float)
            d = min("NF", key=lambda d: np.linalg.norm(J["hand" + d] - e))
            if np.linalg.norm(J["hand" + d] - e) < 16:
                fist = J["hand" + d] + 0.25 * (J["hand" + d] - J["wrist" + d])
                p[lo] = [round(float(x), 1) for x in fist]


HANG_CLEAR = 8.0


def lift_hang(ex, keys):
    """A dead hang with straight legs needs the bar high enough for the feet to clear the floor: the 2D scenes drew
    a low bar and folded the legs into a kneel. The whole scene goes up (frame feet stay on the floor)."""
    if not hangs(ex):
        return 0.0
    low = min(k["j"]["hip"][1] for k in keys)
    lift = LEG[0] + LEG[1] + 11 + HANG_CLEAR - low
    if lift <= 1:
        return 0.0
    for k in keys:
        for n, v in k["j"].items():
            if not n.startswith("_"):
                k["j"][n] = [v[0], round(v[1] + lift, 1), v[2]]
        for p in k["p"]:
            if p["k"] == "rod":
                for e in ("a", "b"):
                    if p[e][1] > 3:                       # uprights keep their foot on the floor
                        p[e] = [p[e][0], round(p[e][1] + lift, 1), p[e][2]]
            elif p["k"] in ("block", "mat"):
                if p["lo"][1] > 3:
                    p["lo"][1] = round(p["lo"][1] + lift, 1)
                    p["hi"][1] = round(p["hi"][1] + lift, 1)
                elif p["hi"][1] > 40:                    # a box to step from grows with the bar
                    p["hi"][1] = round(p["hi"][1] + lift, 1)
            else:
                for e in ("a", "b", "c"):
                    if e in p:
                        p[e] = [p[e][0], round(p[e][1] + lift, 1), p[e][2]]
    return lift


def parallel_grips(ex, keys):
    """Parallel (neutral) grips drawn on the frame's sides, a hand's width outside the fists: each grip moves in
    under its fist, the rods that hang it follow at their lower end."""
    for k in keys:
        J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
        P = k["p"]
        for d in "NF":
            h = J["hand" + d]
            for p in P:
                if p["k"] != "rod" or p.get("s") == "cable":
                    continue
                a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
                if abs(a[1] - b[1]) > 1 or abs(a[2] - b[2]) > 1 or abs(a[0] - b[0]) < 15:
                    continue
                dz = h[2] - a[2]
                if not (min(a[0], b[0]) - 4 < h[0] < max(a[0], b[0]) + 4 and abs(h[1] - a[1]) < 9 and 3 < abs(dz) < 14):
                    continue
                for q in P:
                    if q is p or q["k"] != "rod":
                        continue
                    for e in ("a", "b"):
                        if min(np.linalg.norm(np.asarray(q[e], float) - x) for x in (a, b)) < 3:
                            q[e] = [q[e][0], q[e][1], round(q[e][2] + dz, 1)]
                p["a"] = [p["a"][0], p["a"][1], round(p["a"][2] + dz, 1)]
                p["b"] = [p["b"][0], p["b"][1], round(p["b"][2] + dz, 1)]


def handles(ex, keys):
    """Machine handles the hands hold (leg press side handles, seat grips) sit in the fists. The 2D scene drew one
    handle on the far side, or a short bar from the seat to the near hand that came out running across the lap: each
    gripping hand gets its own upright handle through the fist, mirrored to the other side when only one was drawn."""
    for k in keys:
        J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
        P = k["p"]
        fist = {d: J["hand" + d] + 0.25 * (J["hand" + d] - J["wrist" + d]) for d in "NF"}
        # a short bar that starts at one hand and crosses to the other side of the body: a mis-depthed handle
        for p in list(P):
            if p["k"] != "rod" or p.get("s") == "cable":
                continue
            a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
            if np.linalg.norm(b - a) < 45 and abs(a[2] - b[2]) > 20 and \
                    min(np.linalg.norm(e - J["hand" + d]) for e in (a, b) for d in "NF") < 3:
                P.remove(p)
        hs = [p for p in P if p["k"] == "rod" and p.get("s") == "handle"]
        if not hs:
            continue
        own = {}
        for d in "NF":
            best = None
            for p in hs:
                a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
                ab = b - a
                t = np.clip(((fist[d] - a) @ ab) / max(ab @ ab, 1e-6), 0, 1)
                dist = np.linalg.norm(fist[d] - (a + t * ab))
                if dist < 22 and (best is None or dist < best[0]):
                    best = (dist, p, a + t * ab)
            if best:
                own[d] = best
        if len(own) == 2 and own["N"][1] is own["F"][1]:
            # one handle between both hands: a bar (cable_bar shapes those) unless the hands are far apart
            if abs(J["handN"][2] - J["handF"][2]) < 40:
                continue
            p = own["N"][1]
            q = dict(p); q["a"] = list(p["a"]); q["b"] = list(p["b"])
            P.append(q); own["F"] = (own["F"][0], q, own["F"][2])
        if len(own) == 1:
            d = next(iter(own)); o = "F" if d == "N" else "N"
            mirrored = abs(J["hand" + d][2] + J["hand" + o][2]) < 8 and np.linalg.norm((J["hand" + d] - J["hand" + o])[:2]) < 8
            if mirrored:
                p = own[d][1]
                q = dict(p); q["a"] = [p["a"][0], p["a"][1], -p["a"][2]]; q["b"] = [p["b"][0], p["b"][1], -p["b"][2]]
                P.append(q)
                own[o] = (0.0, q, None)
        for d, (dist, p, _) in own.items():
            a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
            ab = b - a
            t = np.clip(((fist[d] - a) @ ab) / max(ab @ ab, 1e-6), 0, 1)
            dv = fist[d] - (a + t * ab)
            if np.linalg.norm(dv) > 0.5:
                p["a"] = [round(float(x), 1) for x in a + dv]
                p["b"] = [round(float(x), 1) for x in b + dv]


def _sole_gap(V, foot, p):
    """Signed gap between a foot's vertices and a pad (positive = apart), and the pad's unit normal toward the foot."""
    a, b, u, L, nh, t = pad_frame(p)
    r = V[foot] - a
    al = r @ u
    lat = r[:, 2] - a[2]
    w = p.get("w", 0) or 17
    dn = r @ nh
    near = (al > -4) & (al < L + 4) & (np.abs(lat) < w + 6)
    if near.sum() < 10:
        return None
    side = 1.0 if np.median(dn[near]) > t / 2 else -1.0
    gap = (dn[near] - t).min() if side > 0 else (-dn[near]).min()
    return float(gap), nh * side


def _moving(keys, i):
    """Prop i moves between keys (a sled, a lever arm): the props that move with it are the ones that move too."""
    return any(json.dumps(k["p"][i]) != json.dumps(keys[0]["p"][i]) for k in keys[1:] if i < len(k["p"]))


def foot_plates(ex, keys, poses, feet):
    """Feet that push a plate (leg press sled, cable-row foot plate, calf block, sit-up rollers) touch it: the plate
    moves onto the soles along its normal. A sled moves with everything that moves with it (carriage, plates, bar)."""
    if not keys or any(len(k["p"]) != len(keys[0]["p"]) for k in keys):
        return 0
    moved = 0
    for i, p0 in enumerate(keys[0]["p"]):
        if p0["k"] != "pad":
            continue
        per = []
        for (J, V, held, grip), k in zip(poses, keys):
            p = k["p"][i]
            hip_zone = abs((np.asarray(p["a"]) + np.asarray(p["b"]))[1] / 2 - J["hip"][1]) < 25 and \
                min(abs(np.asarray(p["a"])[0] - J["hip"][0]), abs(np.asarray(p["b"])[0] - J["hip"][0]), 999) < 60
            gs = [g for g in (_sole_gap(V, feet[s], p) for s in "LR") if g is not None]
            dy = k.get("dy", 0)
            gs = [(g - (dy * n[1]), n) for g, n in gs]          # the body is drawn shifted by dy
            if not gs or hip_zone:
                per.append(None); continue
            g, n = min(gs, key=lambda x: x[0])
            per.append((g, n) if -8 < g < 24 and abs(g) > 1.0 else None)
        if not any(per):
            continue
        if _moving(keys, i):
            group = [j for j in range(len(keys[0]["p"])) if _moving(keys, j)]
            for (gn, k) in zip(per, keys):
                if gn is None:
                    continue
                dv = gn[1] * gn[0]
                for j in group:
                    shift_any(k["p"][j], dv)
        else:
            vals = [g for g in per if g is not None]
            g = float(np.median([v[0] for v in vals])); dv = vals[0][1] * g
            for k in keys:
                shift_any(k["p"][i], dv)
                attach_rods(k["p"], k["p"][i], dv)
        moved += 1
    return moved


def clear_blocks(ex, keys, poses, hands):
    """A back pad or frame drawn in a front / back view got its depth around the body's middle: the body stood inside
    it. Such a block moves back (−x, the figure faces +x) until it clears the body, the same in every key."""
    if not keys or any(len(k["p"]) != len(keys[0]["p"]) for k in keys):
        return 0
    moved = 0
    for i, p0 in enumerate(keys[0]["p"]):
        if p0["k"] != "block":
            continue
        need = 0.0
        for (J, V, held, grip), k in zip(poses, keys):
            lo, hi = np.asarray(k["p"][i]["lo"], float), np.asarray(k["p"][i]["hi"], float)
            inside = np.all((V > lo + 1) & (V < hi - 1), axis=1) & ~hands
            if inside.sum() < 800 or hi[1] - lo[1] < 20:
                continue
            foot = (V[:, 1] > lo[1]) & (V[:, 1] < hi[1]) & (V[:, 2] > lo[2]) & (V[:, 2] < hi[2]) & ~hands
            need = min(need, float(V[foot, 0].min()) - hi[0] - 0.5)
        if need < -0.5:
            for k in keys:
                shift_any(k["p"][i], [need, 0.0, 0.0])
            moved += 1
    return moved


def shift_any(p, dv):
    dv = np.asarray(dv, float)
    for a in ("a", "b", "c", "lo", "hi"):
        if a in p:
            p[a] = [round(float(x + d), 1) for x, d in zip(p[a], dv)]


def run(ids=None):
    if not RAW.exists():
        RAW.write_bytes(DATA.read_bytes())
    d = json.loads(zlib.decompress(RAW.read_bytes(), -15))
    R = rigmod.Rig()
    rigmod.MUSH = 0
    fingers = np.isin(R.bi[:, 0], [R.ix[n] for n in R.names if n.startswith("finger")])
    palms = np.isin(R.bi[:, 0], [R.ix[n] for n in R.names if n.startswith(("metacarpal", "wrist"))])
    feet = {s: np.isin(R.bi[:, 0], [R.ix[n] for n in R.names if n.startswith(("foot", "toe")) and n.endswith("." + s)]) for s in "LR"}
    report = []
    for ex in (ids or sorted(d)):
        e = d[ex]
        keys = e["k"]
        lying_scenes(ex, e)
        complete(ex, keys)
        grip_axes(ex, keys)
        cable_bar(ex, keys)
        bar_clear(ex, keys)
        handles(ex, keys)
        parallel_grips(ex, keys)
        machine_parts(ex, keys)
        straps(ex, keys)
        lift_hang(ex, keys)
        # every key must list the same static props; shifts are decided per exercise
        poses = []
        for k in keys:
            mirror_legs(ex, k["j"])
            J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
            V = R.pose(k["j"], k["p"])
            if hangs(ex) and hanging(J, R.held) and hang_legs(k["j"], J):
                J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
                V = R.pose(k["j"], k["p"])
            poses.append((J, V, dict(R.held), dict(R.grip)))
        n_props = min(len(k["p"]) for k in keys)
        shifts = {}
        for i in range(n_props):
            gaps = []
            for (J, V, held, grip), k in zip(poses, keys):
                p = k["p"][i]
                if p["k"] not in ("pad", "block"):
                    break
                g = support_gap(V, J, p)
                if g is not None:
                    gaps.append(g)
            if gaps:
                gap = float(np.median([g[0] for g in gaps]))
                if abs(gap) > 0.8:
                    shifts[i] = (gap, gaps[0][1])
        for i, (gap, nh) in shifts.items():
            dv = nh * gap
            for k in keys:
                if i < len(k["p"]) and k["p"][i]["k"] in ("pad", "block"):
                    attach_rods(k["p"], k["p"][i], dv) if k["p"][i]["k"] == "pad" else None
                    shift_prop(k["p"][i], dv)
        # residual: floating body comes down unless standing or hanging; sunk body comes up
        for (J, V, held, grip), k in zip(poses, keys):
            dy = 0.0
            min_y = float(V[~fingers, 1].min())      # fingertips may tuck under a flat hand
            supported = False
            resid = []
            for p in k["p"]:
                if p["k"] in ("pad", "block"):
                    g = support_gap(V, J, p)
                    if g is not None:
                        supported = True
                        resid.append(g[0] * g[1][1])      # vertical part of the residual gap
            if k.pop("_ballfix", False):
                dy = k["dy"]
            elif min_y < -2.0:
                dy = -min_y
            elif supported and resid and min(resid) > 1.0 and min_y > 2.0:
                dy = -min(resid)
            elif not supported and min_y > 2.5 and not hanging(J, held) and not hangs(ex):    # over the bar (muscle-up) is still on it
                dy = -min_y
            if abs(dy) > 0.5:
                k["dy"] = round(dy, 1)
            else:
                k.pop("dy", None)
        plates = foot_plates(ex, keys, poses, feet) + clear_blocks(ex, keys, poses, fingers | palms)
        done = 0
        for (J, V, held, grip), k in zip(poses, keys):
            dumbbells(k["p"], J, held, grip)
            done += machines(k["p"]) + frames(k["p"])
        if shifts or done or plates or any("dy" in k for k in keys):
            report.append((ex, {i: round(g, 1) for i, (g, _) in shifts.items()}, [k.get("dy", 0) for k in keys], done))
        print(ex, "shifts", {i: round(g, 1) for i, (g, _) in shifts.items()}, "dy", [k.get("dy", 0) for k in keys], "machines", done, "plates", plates, flush=True)
    z = zlib.compressobj(9, zlib.DEFLATED, -15)
    DATA.write_bytes(z.compress(json.dumps(d, separators=(",", ":")).encode()) + z.flush())
    Path("/tmp/claude-0/contact-report.json").write_text(json.dumps(report))
    print(len(report), "exercises changed;", DATA.stat().st_size, "bytes")


if __name__ == "__main__":
    run(sys.argv[1:] or None)
