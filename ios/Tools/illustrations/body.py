#!/usr/bin/env python3
"""Athletic figure for the 3D position guide, posed on positions.py joints by linear-blend skinning.

The rest mesh is the MakeHuman base mesh (CC0 1.0, https://github.com/makehumancommunity/makehuman, data/3dobjs)
morphed with its macro and muscle targets (young male, max muscle, min weight, ideal proportions, see TARGETS),
subdivided, carved (abs, pecs, serratus) and dressed in shorts cut from the tights helper; the default rig
(default.mhskel + default_weights.mhw) comes along for rig.py.

    python3 body.py --build MH_DATA_DIR     # bakes body_rest.npz + body_rig.npz (next to this file)
    python3 body.py --bin                   # packs ExerciseBody.bin.z for the app (format: export_bin)

MH_DATA_DIR holds makehuman/data from the repository above (3dobjs/base.obj, targets/, rigs/default.*); the
build downloads nothing. Posing is rig.py, the equipment pass contact.py.
"""
import json, sys, zlib
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
REST = HERE / "body_rest.npz"
DATA = HERE.parent.parent / "Packages/GymCore/Sources/WorkoutEngine/Resources/ExercisePositions.json.z"
TARGETS = {
    "macrodetails/caucasian-male-young.target": 0.34,
    "macrodetails/african-male-young.target": 0.33,
    "macrodetails/asian-male-young.target": 0.33,
    "macrodetails/universal-male-young-maxmuscle-averageweight.target": 0.1,
    "macrodetails/universal-male-young-maxmuscle-minweight.target": 0.9,
    "macrodetails/proportions/male-young-maxmuscle-minweight-idealproportions.target": 1.0,
    "stomach/stomach-tone-incr.target": 1.0,
    "neck/neck-scale-horiz-incr.target": 0.3,
    "head/head-square.target": 0.3,
    **{f"armslegs/{s}-{m}-muscle-incr.target": w for s in "lr" for m, w in (("upperarm", 0.5), ("upperarm-shoulder", 0.5), ("lowerarm", 0.4), ("upperleg", 0.4))},
}
DEFINITION = 0.3
BREAST_FLATTEN = 0.85
CARVE = 1.0
PEC = 3.0
SUBDIV = True
DEF_PASSES = 3
SEGS = ["pelvis", "chest", "head", "uaL", "faL", "hdL", "uaR", "faR", "hdR", "thL", "snL", "ftL", "thR", "snR", "ftR",
        "shL", "shR", "hpL", "hpR"]
# helper segments: shoulder girdle and hip turn halfway between the trunk and the limb
HELPERS = {"sh": ("chest", "ua"), "hp": ("pelvis", "th")}


def seg_of(bone):
    """MakeHuman bone -> {segment: share}."""
    side = bone[-1] if bone[-2:] in (".L", ".R") else ""
    b = bone[:-2] if side else bone
    if b in ("root", "spine05"):
        return {"pelvis": 1}
    if b == "pelvis":
        return {"pelvis": 0.4, "hp" + side: 0.6}
    if b == "spine04":
        return {"pelvis": 0.65, "chest": 0.35}
    if b == "spine03":
        return {"pelvis": 0.3, "chest": 0.7}
    if b in ("spine02", "spine01", "breast"):
        return {"chest": 1}
    if b == "clavicle":
        return {"chest": 0.5, "sh" + side: 0.5}
    if b == "neck01":
        return {"chest": 0.6, "head": 0.4}
    if b == "neck02":
        return {"chest": 0.3, "head": 0.7}
    if b == "shoulder01":
        return {"sh" + side: 0.6, "ua" + side: 0.4}
    if b.startswith("upperarm"):
        return {"ua" + side: 1}
    if b.startswith("lowerarm"):
        return {"fa" + side: 1}
    if b in ("wrist",) or b.startswith(("finger", "metacarpal")):
        return {"hd" + side: 1}
    if b == "upperleg01":
        return {"hp" + side: 0.3, "th" + side: 0.7}
    if b.startswith("upperleg"):
        return {"th" + side: 1}
    if b.startswith("lowerleg"):
        return {"sn" + side: 1}
    if b == "foot" or b.startswith("toe"):
        return {"ft" + side: 1}
    return {"head": 1}   # neck03, head, face


def _smooth(V, tris, n):
    """n passes of umbrella (neighbour average) smoothing."""
    E = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    E = np.concatenate([E, E[:, ::-1]])
    deg = np.bincount(E[:, 0], minlength=len(V)).astype(float)[:, None]
    S = V.copy()
    for _ in range(n):
        acc = np.zeros_like(S)
        np.add.at(acc, E[:, 0], S[E[:, 1]])
        S = 0.5 * S + 0.5 * acc / np.maximum(deg, 1)
    return S


MUSCLES = ["", "chest", "front-delts", "side-delts", "rear-delts", "biceps", "triceps", "brachialis", "forearms",
           "forearm-extensors", "traps", "upper-back", "lats", "lower-back", "abs", "lower-abs", "obliques", "serratus",
           "glutes", "glute-med", "hip-flexors", "adductors", "quads", "hamstrings", "calves", "soleus", "tibialis"]


def classify(V, W, J):
    """Muscle (index into MUSCLES) under each rest vertex: anatomical regions in rest coordinates for the trunk and
    the shoulder caps, position around the bone for the limbs. 0 = no highlighted muscle (face, hands, feet...)."""
    F = _frames(J, {"L": "L", "R": "R"})
    seg = W.argmax(1)
    out = np.zeros(len(V), int)
    M = MUSCLES.index
    # outward normals of the rest mesh (for front/back) from the stored faces are not at hand here: use the
    # trunk frame instead, x forward in rest coordinates
    sh = np.asarray(J["shoulder"]); shL = np.asarray(J["shoulderL"])
    sw = abs(shL[2] - sh[2])
    for i, v in enumerate(V):
        x, y, z = v
        az = abs(z)
        sname = SEGS[seg[i]]
        if sname[:2] in HELPERS:
            sname = HELPERS[sname[:2]][1] + sname[-1]
        side = "L" if z < 0 else "R"
        # deltoid cap around the shoulder joint
        sj = np.asarray(J["shoulder" + side])
        d = v - sj
        if np.linalg.norm(d * np.array([1.0, 0.8, 1.0])) < 13.5 and y > sj[1] - 13 and az > sw - 9:
            fwd, lat = d[0], abs(d[2])
            out[i] = M("front-delts") if fwd > 3.5 else (M("rear-delts") if fwd < -4.5 else M("side-delts"))
            continue
        if sname in ("chest", "pelvis"):
            front = x > 0.5
            if front:
                yc, zc = 165.5 + 0.12 * (az - 9), 9.5
                ry = 7.0 if y < yc else 12.0
                if ((y - yc) / ry) ** 2 + ((az - zc) / 9.6) ** 2 <= 1.12 and az > 1.0:
                    out[i] = M("chest")
                elif 124 < y < 161 and az < 8.8:
                    out[i] = M("abs") if y > 136 else M("lower-abs")
                elif 147 < y < 163 and 10.5 < az < 19.5:
                    out[i] = M("serratus")
                elif 117 < y < 152 and 8.8 <= az < 19.5:
                    out[i] = M("obliques")
                elif y <= 124 and az < 12 and y > 104:
                    out[i] = M("hip-flexors")
            else:
                back = x < -1.0
                if back and ((y > 176 and az < 6 + 24 * max(0.0, 1 - (y - 176) / 20)) or (165 < y <= 176 and az < 7 + (y - 165) * 1.9)
                             or (148 < y <= 165 and az < 7.5 - (165 - y) * 0.2)):
                    out[i] = M("traps")
                elif back and 156 < y < 179 and 7 < az < 22:
                    out[i] = M("upper-back")
                elif 124 < y < 176 and (4 + (y - 124) * 0.22) < az < (8 + (y - 124) * 0.45) and (back or az > 11):
                    out[i] = M("lats")
                elif back and 116 < y < 152 and az < 8.5:
                    out[i] = M("lower-back")
                elif 94 < y < 125 and (back or az > 13):
                    out[i] = M("glute-med") if az > 13.5 and y > 108 and not back else M("glutes")
            continue
        if sname[:2] not in ("ua", "fa", "th", "sn"):
            continue
        S = sname[-1]
        o2, B2, L = F[sname]
        u, a, s_ = (v - o2) @ B2
        out_dir = np.asarray(J["shoulder" + S]) - sh
        s_ *= np.sign(B2[:, 2] @ out_dir) or 1     # positive = away from the midline
        ang = np.degrees(np.arctan2(s_, a))       # 0 front, 90 outside, +-180 back, -90 inside
        t = u / L
        if sname.startswith("ua"):
            if t > 0.15:
                out[i] = M("biceps") if -75 < ang < 45 else (M("brachialis") if 45 <= ang < 95 and t > 0.55 else M("triceps"))
        elif sname.startswith("fa"):
            if t < 0.8:
                out[i] = M("forearms") if -125 < ang < 35 else M("forearm-extensors")
        elif sname.startswith("th"):
            if -70 < ang < 80:
                out[i] = M("quads") if t > 0.1 else M("hip-flexors")
            elif -140 < ang <= -70 and t < 0.65:
                out[i] = M("adductors")
            else:
                out[i] = M("hamstrings") if t > 0.15 else M("glutes")
        elif sname.startswith("sn"):
            if abs(ang) > 110:
                out[i] = M("calves") if t < 0.6 else (M("soleus") if t < 0.85 else 0)
            elif 10 < ang < 85 and t < 0.75:
                out[i] = M("tibialis")
            elif t < 0.75 and abs(ang) >= 70:
                out[i] = M("soleus")
    return out


def _seg_dist(P, a, b):
    a = np.asarray(a, float); b = np.asarray(b, float); d = b - a
    t = np.clip(((P - a) @ d) / (d @ d), 0, 1)
    return np.linalg.norm(P - (a + np.outer(t, d)), axis=1)


def carve(V, N):
    """Lean-athlete surface detail on the rest body (our coords, y up, x forward): six-pack, linea alba, pecs,
    adonis lines, serratus. Returns a displacement along the normals."""
    y, z = V[:, 1], np.abs(V[:, 2])
    front = np.clip((N[:, 0] - 0.35) / 0.4, 0, 1) * (V[:, 0] > 0)
    g = lambda d, w: np.exp(-(d / w) ** 2)
    P2 = np.stack([y, z], 1)
    groove = np.zeros(len(V))
    bulge = np.zeros(len(V))
    abs_zone = (y > 124) & (y < 161) & (z < 9.5)
    groove += 0.75 * g(z, 0.9) * abs_zone                                    # linea alba
    for yl in (137.5, 145.5, 153.0):                                          # tendinous lines
        groove += 0.55 * g(y - yl - 0.08 * z, 0.9) * (z < 8.5) * abs_zone
    groove += 0.6 * g(z - 8.6, 1.1) * abs_zone                               # rectus outer edge
    for seg in (((129, 12.5), (114, 3.5)),):                                  # adonis (iliac) lines
        groove += 0.8 * g(_seg_dist(P2, *seg), 1.1) * (y < 131)
    # pectoralis major: a rounded mound, crisp but soft lower border, fading into the clavicle and the armpit
    yc, zc = 165.5 + 0.12 * (z - 9), 9.5
    ry = np.where(y < yc, 7.0, 12.0)
    q = ((y - yc) / ry) ** 2 + ((z - zc) / 9.0) ** 2
    mound = np.clip(1 - q, 0, 1) ** np.where(y < yc, 0.85, 1.5)
    mound *= np.clip((z - 0.8) / 1.6, 0, 1)
    bulge += PEC * mound
    groove += 0.25 * g(np.sqrt(q) - 1.0, 0.2) * (y < yc) * np.clip((z - 1.0) / 2, 0, 1) * np.clip((17 - z) / 3, 0, 1)
    groove += 0.5 * g(z, 1.0) * (y > 160) * (y < 176)                         # sternum
    for yb in (141.5, 149.5, 157.0, 131.5):                                   # ab blocks
        bulge += 0.35 * g(np.hypot((y - yb) / 1.6, (z - 4.3) / 1.4), 1.6) * abs_zone
    for i, yb in enumerate((150.0, 154.5, 159.0)):                            # serratus fingers
        groove += 0.4 * g(_seg_dist(P2, (yb, 14.5 - i * 0.6), (yb + 2.5, 17.5 - i * 0.6)), 0.8)
    return (bulge - groove) * front


def subdivide(V, F):
    """One midpoint subdivision of every face (quads -> 4 quads, triangles -> 4 triangles).
    Returns new vertices, faces per group and the sparse map new <- old used to carry weights over."""
    import scipy.sparse as sp
    rows, cols, vals = list(range(len(V))), list(range(len(V))), [1.0] * len(V)
    pts = [V]
    edge = {}
    n = [len(V)]

    def newv(ids):
        i = n[0]; n[0] += 1
        for j in ids:
            rows.append(i); cols.append(j); vals.append(1.0 / len(ids))
        pts.append(V[list(ids)].mean(0, keepdims=True))
        return i

    def mid(a, b):
        k = (a, b) if a < b else (b, a)
        if k not in edge:
            edge[k] = newv(k)
        return edge[k]
    out = {}
    for g, faces in F.items():
        nf = []
        for f in faces:
            if len(f) == 4:
                v0, v1, v2, v3 = f
                c = newv(tuple(f))
                m01, m12, m23, m30 = mid(v0, v1), mid(v1, v2), mid(v2, v3), mid(v3, v0)
                nf += [[v0, m01, c, m30], [m01, v1, m12, c], [c, m12, v2, m23], [m30, c, m23, v3]]
            elif len(f) == 3:
                v0, v1, v2 = f
                m01, m12, m20 = mid(v0, v1), mid(v1, v2), mid(v2, v0)
                nf += [[v0, m01, m20], [m01, v1, m12], [m20, m12, v2], [m01, m12, m20]]
        out[g] = nf
    S = sp.csr_matrix((vals, (rows, cols)), shape=(n[0], len(V)))
    return np.concatenate(pts), out, S


def _taubin(V, tris, idx, passes=2):
    for lam in [0.5, -0.53] * passes:
        S = _smooth(V, tris, 1)          # 0.5 * V + 0.5 * neighbour mean
        D = 2 * (S - V)                   # umbrella vector
        V[idx] += lam * D[idx]
    return V


def build(mh, only=None):
    mh = Path(mh)
    V, F = [], {}
    group = None
    for line in open(mh / "3dobjs/base.obj"):
        if line.startswith("v "):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("g "):
            group = line.split()[1]
        elif line.startswith("f "):
            F.setdefault(group, []).append([int(t.split("/")[0]) - 1 for t in line.split()[1:]])
    V = np.array(V)
    for t, w in (TARGETS if only is None else only).items():
        for line in open(mh / "targets" / t):
            if line[0].isdigit():
                i, dx, dy, dz = line.split()
                V[int(i)] += w * np.array([float(dx), float(dy), float(dz)])

    skel = json.load(open(mh / "rigs/default.mhskel"))
    names = list(skel["bones"])
    WB = np.zeros((len(V), len(names)), np.float32)
    for bone, vw in json.load(open(mh / "rigs/default_weights.mhw"))["weights"].items():
        for i, w in vw:
            WB[i, names.index(bone)] += w
    if SUBDIV:
        V, F, Smap = subdivide(V, F)
        WB = np.asarray(Smap @ WB, np.float32)
    col = lambda b: WB[:, names.index(b)] if b in names else np.zeros(len(V))

    def tri(groups):
        out = []
        for g in groups:
            for f in F[g]:
                for k in range(1, len(f) - 1):
                    out.append((f[0], f[k], f[k + 1]))
        return np.array(out)
    body, eyes, tights = tri(["body"]), tri(["helper-l-eye", "helper-r-eye"]), tri(["helper-tights"])
    if SUBDIV:
        V = _taubin(V, body, np.unique(body), 3)
    # muscle definition: unsharp mask (push the surface away from its smoothed self)
    bi = np.unique(body)
    # male chest: iron out the base mesh's breast mound and its under-crease (pecs stay from the muscle targets)
    wb = np.clip((col("breast.L") + col("breast.R")) * 1.6, 0, 1)
    S = _smooth(V, body, 25 * (4 if SUBDIV else 1))
    V += (BREAST_FLATTEN * wb)[:, None] * (S - V)
    S = _smooth(V, body, DEF_PASSES * (4 if SUBDIV else 1))
    V[bi] += DEFINITION * (V[bi] - S[bi])
    joint = lambda name: V[skel["joints"][name]].mean(0)
    jh = lambda bone: joint(skel["bones"][bone]["head"])
    jt = lambda bone: joint(skel["bones"][bone]["tail"])
    J = {"hip": (jh("upperleg01.L") + jh("upperleg01.R")) / 2, "neck": jh("neck01"), "head": jh("head") + (jt("head") - jh("head")) * 0.35}
    J["shoulder"] = (jh("upperarm01.L") + jh("upperarm01.R")) / 2
    for s in "LR":
        J["shoulder" + s] = jh(f"upperarm01.{s}")
        J["elbow" + s] = jh(f"lowerarm01.{s}")
        J["wrist" + s] = jh(f"wrist.{s}")
        J["hand" + s] = jh(f"finger3-1.{s}")
        J["hip" + s] = jh(f"upperleg01.{s}")
        J["knee" + s] = jh(f"lowerleg01.{s}")
        J["ankle" + s] = jh(f"foot.{s}")
        J["toe" + s] = jh(f"toe3-1.{s}")
    # shorts: the tights helper between mid-thigh and the waist (covers the crotch; no genitals in the model)
    top, bottom = J["hip"][1] + 0.62, (J["hipL"][1] + J["kneeL"][1]) / 2 + 0.3
    ty = V[tights][:, :, 1]
    shorts = tights[np.all((ty < top) & (ty > bottom), axis=1)]
    sv = np.unique(shorts)
    # straight hems: boundary vertices onto the waist and leg planes
    E = np.sort(np.concatenate([shorts[:, [0, 1]], shorts[:, [1, 2]], shorts[:, [2, 0]]]), 1)
    ue, cnt = np.unique(E, axis=0, return_counts=True)
    bv = np.unique(ue[cnt == 1])
    mid = (top + bottom) / 2
    V[bv, 1] = np.where(V[bv, 1] > mid, top - 0.02, np.maximum(V[bv, 1], bottom + 0.02) * 0 + bottom + 0.02)
    V = _taubin(V, shorts, sv, 2)
    tris = np.concatenate([body, eyes, shorts])
    mat = np.concatenate([np.zeros(len(body), int), np.full(len(eyes), 2), np.ones(len(shorts), int)])
    # fist: curl fingers 2-5 at each joint toward the palm (stored as an alternative position for hand vertices)
    Vf = V.copy()
    palms = {}
    for s in "LR":
        across = jh(f"finger5-1.{s}") - jh(f"finger2-1.{s}")
        fdir = jt(f"finger3-1.{s}") - jh(f"finger3-1.{s}")
        palm = -np.cross(fdir, across)                 # toward the palm (MakeHuman's A-pose palms face the body)
        palm_dir = palm / np.linalg.norm(palm)
        if palm_dir[0] * jh(f"wrist.{s}")[0] > 0:      # the cross product mirrors with the side: keep it inward
            palm_dir = -palm_dir
        palms[s] = palm_dir
        for f in (2, 3, 4, 5):
            for p, ang in ((3, 75), (2, 85), (1, 70)):
                o = jh(f"finger{f}-{p}.{s}")
                d = jt(f"finger{f}-{p}.{s}") - o
                ax = np.cross(d, palm_dir); ax /= np.linalg.norm(ax)
                w = sum(col(f"finger{f}-{q}.{s}") for q in range(p, 4))
                idx = np.nonzero(w > 1e-4)[0]
                th = np.radians(ang) * np.clip(w[idx], 0, 1)
                q = Vf[idx] - o
                c, si = np.cos(th)[:, None], np.sin(th)[:, None]
                # Rodrigues: rotate q around ax by th
                q = q * c + np.cross(ax, q) * si + np.outer(q @ ax, ax) * (1 - c)
                Vf[idx] = o + q
        # thumb: folds over the curled fingers (bent at each joint and swung across toward the index)
        def turn(o, ax, ang, w):
            idx = np.nonzero(w > 1e-4)[0]
            th = np.radians(ang) * np.clip(w[idx], 0, 1)
            q = Vf[idx] - o
            c, si = np.cos(th)[:, None], np.sin(th)[:, None]
            Vf[idx] = o + q * c + np.cross(ax, q) * si + np.outer(q @ ax, ax) * (1 - c)
        for p, ang in ((3, 45), (2, 30)):               # distal first: each pivot is still at its rest position
            o = jh(f"finger1-{p}.{s}"); d = jt(f"finger1-{p}.{s}") - o
            ax = np.cross(d, palm_dir); ax /= np.linalg.norm(ax)
            turn(o, ax, ang, sum(col(f"finger1-{q}.{s}") for q in range(p, 4)))
        # then the whole thumb turns about its base to lie across the curled fingers: over the middle finger's
        # second phalanx, on the palm side of the fist
        o = jh(f"finger1-1.{s}")
        d = jt(f"finger1-1.{s}") - o
        w32 = col(f"finger3-2.{s}"); over = (Vf[w32 > 0.3].mean(0) + 2.5 * palm_dir) - o
        tgt = over / np.linalg.norm(over)
        ax = np.cross(d, tgt); ang = np.degrees(np.arctan2(np.linalg.norm(ax), d @ tgt))
        turn(o, ax / max(np.linalg.norm(ax), 1e-9), ang, sum(col(f"finger1-{q}.{s}") for q in range(1, 4)))
    used = np.unique(tris)
    remap = -np.ones(len(V), int); remap[used] = np.arange(len(used))
    W = np.zeros((len(V), len(SEGS)))
    for bi_, bone in enumerate(names):
        for seg, share in seg_of(bone).items():
            W[:, SEGS.index(seg)] += WB[:, bi_] * share
    W = W[used]
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    # MakeHuman: decimetres, y up, z forward, x = character's left -> ours: x forward, y up, z lateral (right +)
    conv = lambda p: np.array([p[..., 2], p[..., 1], -p[..., 0]]).T if p.ndim > 1 else np.array([p[2], p[1], -p[0]])
    Vr = conv(V[used])
    floor = Vr[:, 1].min()
    scale = 224.0 / (Vr[:, 1].max() - floor)   # same height as the 2D figure (top of head ~224)
    off = np.array([0, floor, 0])
    Vr = (Vr - off) * scale
    Vfist = (conv(Vf[used]) - off) * scale
    Jr = {k: (conv(v) - off) * scale for k, v in J.items()}
    T0 = remap[tris]
    nr0 = np.zeros_like(Vr); t0 = Vr[T0]; f0 = np.cross(t0[:, 1] - t0[:, 0], t0[:, 2] - t0[:, 0])
    for k in range(3):
        np.add.at(nr0, T0[:, k], f0)
    nr0 /= np.maximum(np.linalg.norm(nr0, axis=1, keepdims=True), 1e-9)
    # iron the base mesh's chest (its breast mound and creases) before sculpting the pecs
    cm = np.clip((Vr[:, 0] - 3) / 4, 0, 1) * np.clip((181 - Vr[:, 1]) / 4, 0, 1) * np.clip((Vr[:, 1] - 150) / 4, 0, 1) \
        * np.clip((21 - np.abs(Vr[:, 2])) / 4, 0, 1)
    Sm = _smooth(Vr, T0, 60)
    Vr = Vr + cm[:, None] * (Sm - Vr); Vfist = Vfist + cm[:, None] * (Sm - Vfist) * 0 + (cm[:, None] * (Sm - Vr)) * 0
    Vfist[cm > 0] = Vr[cm > 0]
    nr0 = np.zeros_like(Vr); t0 = Vr[T0]; f0 = np.cross(t0[:, 1] - t0[:, 0], t0[:, 2] - t0[:, 0])
    for k in range(3):
        np.add.at(nr0, T0[:, k], f0)
    nr0 /= np.maximum(np.linalg.norm(nr0, axis=1, keepdims=True), 1e-9)
    D = carve(Vr, nr0)[:, None] * nr0 * CARVE
    Vr = Vr + D; Vfist = Vfist + D
    # shoulder girdle / hip: trunk weight close to the joint moves to the helper that turns halfway with the limb
    for S in "LR":
        for trunk, helper, jn, r0, r1 in (("chest", "sh", "shoulder", 9.0, 22.0), ("pelvis", "hp", "hip", 8.0, 20.0)):
            d = np.linalg.norm(Vr - Jr[jn + S], axis=1)
            other = np.linalg.norm(Vr - Jr[jn + ("R" if S == "L" else "L")], axis=1)
            f = np.clip((r1 - d) / (r1 - r0), 0, 1) * (d < other)
            ti, hi = SEGS.index(trunk), SEGS.index(helper + S)
            move = W[:, ti] * f
            W[:, ti] -= move; W[:, hi] += move
    # full MakeHuman rig for forward-kinematics posing (rig.py): bones, rest heads/tails, top-4 weights per vertex
    BWm = WB[used]
    top = np.argsort(-BWm, 1)[:, :4]
    tw = np.take_along_axis(BWm, top, 1); tw /= np.maximum(tw.sum(1, keepdims=True), 1e-9)
    heads = np.array([(conv(jh(b)) - off) * scale for b in names])
    tails = np.array([(conv(jt(b)) - off) * scale for b in names])
    parents = [names.index(skel["bones"][b]["parent"]) if skel["bones"][b]["parent"] else -1 for b in names]
    np.savez_compressed(HERE / "body_rig.npz", v=Vr.astype(np.float32), vf=Vfist.astype(np.float32), bi=top.astype(np.int16),
                        bw=tw.astype(np.float16), heads=heads.astype(np.float32), tails=tails.astype(np.float32),
                        parents=np.array(parents, np.int16), names=json.dumps(names),
                        palm=np.stack([conv(palms["L"]), conv(palms["R"])]).astype(np.float32))
    Vr, Vfist, Jr = _proportion(Vr, Vfist, W, Jr)
    mus = classify(Vr, W, Jr)
    # cavity: how far each vertex sits inside its smoothed neighbourhood (muscle separations), along the normal
    T = remap[tris]
    nr = np.zeros_like(Vr); t = Vr[T]; fnr = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    for k in range(3):
        np.add.at(nr, T[:, k], fnr)
    nr /= np.maximum(np.linalg.norm(nr, axis=1, keepdims=True), 1e-9)
    cav = ((Vr - _smooth(Vr, T, 6)) * nr).sum(1)
    cav = np.clip(cav / 1.2, -1, 1)
    band = np.array([(J["hip"][1] + 0.62 - floor) * scale - 2.0, ((J["hipL"][1] + J["kneeL"][1]) / 2 - floor) * scale + 3])
    np.savez_compressed(REST, v=Vr.astype(np.float32), f=remap[tris].astype(np.int32), m=mat.astype(np.int8), vf=Vfist.astype(np.float32), mu=mus.astype(np.int8), cav=cav.astype(np.float16), band=band,
                        w=W.astype(np.float16), j=json.dumps({k: np.round(v, 3).tolist() for k, v in Jr.items()}))
    print(len(Vr), "verts", len(tris), "tris")


BONES = {"ua": 42.0, "fa": 38.0, "th": 56.0, "sn": 54.0}   # figure.py limb lengths


def _proportion(V, Vf, W, J):
    """Stretch the limbs along their bones to the 2D figure's lengths, so posing is rigid per segment."""
    F = _frames(J, {"L": "L", "R": "R"})
    J = {k: np.asarray(v, float) for k, v in J.items()}
    outs = []
    for X in (V, Vf):
        X = X.astype(float)
        out = np.zeros_like(X)
        for i, seg in enumerate(SEGS):
            w = W[:, i]
            if not (w > 1e-4).any():
                continue
            Y = X.copy()
            S = seg[-1]
            chains = {"ua": [], "fa": ["ua"], "hd": ["ua", "fa"], "th": [], "sn": ["th"], "ft": ["th", "sn"]}
            if seg[:2] in chains:
                for p in chains[seg[:2]]:
                    o, B, l = F[p + S]
                    Y += B[:, 0] * (BONES[p] - l)
                if seg[:2] in BONES:
                    o, B, l = F[seg]
                    t = (X - o) @ B[:, 0]
                    Y += np.outer(t * (BONES[seg[:2]] / l - 1), B[:, 0])
                    # keep the muscle volume: a longer bone gets a thicker limb
                    rad = (X - o) - np.outer((X - o) @ B[:, 0], B[:, 0])
                    Y += rad * (np.sqrt(BONES[seg[:2]] / l) - 1)
            out += w[:, None] * Y
        outs.append(out)
    for S in "LR":
        for p, a, b in (("ua", "shoulder", "elbow"), ("th", "hip", "knee")):
            d = F[p + S][1][:, 0] * (BONES[p] - F[p + S][2])
            for j in ((b, "wrist", "hand") if p == "ua" else (b, "ankle", "toe")):
                J[j + S] = J[j + S] + d
        for p, b in (("fa", ("wrist", "hand")), ("sn", ("ankle", "toe"))):
            d = F[p + S][1][:, 0] * (BONES[p] - F[p + S][2])
            for j in b:
                J[j + S] = J[j + S] + d
    return outs[0], outs[1], {k: v for k, v in J.items()}


def _quat(Rm):
    """Rotation matrix -> unit quaternion (w, x, y, z)."""
    t = np.trace(Rm)
    if t > 0:
        s = np.sqrt(t + 1) * 2
        return np.array([0.25 * s, (Rm[2, 1] - Rm[1, 2]) / s, (Rm[0, 2] - Rm[2, 0]) / s, (Rm[1, 0] - Rm[0, 1]) / s])
    i = int(np.argmax(np.diag(Rm)))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = np.sqrt(1 + Rm[i, i] - Rm[j, j] - Rm[k, k]) * 2
    q = np.zeros(4)
    q[0] = (Rm[k, j] - Rm[j, k]) / s
    q[1 + i] = 0.25 * s
    q[1 + j] = (Rm[j, i] + Rm[i, j]) / s
    q[1 + k] = (Rm[k, i] + Rm[i, k]) / s
    return q


def _qmul(a, b):
    """Hamilton product of quaternion arrays (..., 4)."""
    w1, x1, y1, z1 = np.moveaxis(a, -1, 0)
    w2, x2, y2, z2 = np.moveaxis(b, -1, 0)
    return np.stack([w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2, w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                     w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2, w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2], -1)


def _frames(J, side):
    """Segment frames {seg: (origin, basis 3x3 columns u a s, length)}; side maps L/R to the joint suffix."""
    J = {k: np.asarray(v, float) for k, v in J.items() if not k.startswith("_")}
    nrm = lambda v: v / max(np.linalg.norm(v), 1e-9)
    perp = lambda v, ax: v - (v @ ax) * ax
    L, R = side["L"], side["R"]
    hip, sh = J["hip"], J["shoulder"]
    up = nrm(sh - hip)
    toe = (J["toe" + L] + J["toe" + R]) / 2 - (J["ankle" + L] + J["ankle" + R]) / 2
    out = {}

    def basis(u, a):
        u = nrm(u); a = nrm(perp(a, u))
        return np.stack([u, a, np.cross(u, a)], 1)
    for seg, o, lat in (("pelvis", hip, J["hip" + R] - J["hip" + L]), ("chest", sh, J["shoulder" + R] - J["shoulder" + L])):
        fwd = np.cross(up, nrm(lat))
        if fwd @ toe < 0:
            fwd = -fwd
        out[seg] = (o, basis(up, fwd), np.linalg.norm(sh - hip))
    fwd_c = out["chest"][1][:, 1]
    hu = nrm(J["head"] - J["neck"])
    out["head"] = (J["neck"], basis(hu, fwd_c), None)
    for S in "LR":
        s = side[S]
        sj, el, wr, hd = J["shoulder" + s], J["elbow" + s], J["wrist" + s], J["hand" + s]
        hp, kn, an, to = J["hip" + s], J["knee" + s], J["ankle" + s], J["toe" + s]
        ua, fa = nrm(el - sj), nrm(wr - el)
        bend = np.linalg.norm(perp(fa, ua))
        k = np.clip((bend - 0.15) / 0.3, 0, 1)
        a_ua = nrm(k * nrm(perp(fa, ua) + 1e-9) + (1 - k) * nrm(perp(fwd_c, ua) + 1e-9))
        a_fa = nrm(k * nrm(-perp(ua, fa) + 1e-9) + (1 - k) * nrm(perp(a_ua, fa) + 1e-9))
        th, sn, ft = nrm(kn - hp), nrm(an - kn), nrm(to - an)
        a_sn = nrm(perp(ft, sn) + 1e-9)
        kb = np.linalg.norm(perp(sn, th))
        k = np.clip((kb - 0.1) / 0.3, 0, 1)
        a_th = nrm(k * nrm(-perp(sn, th) + 1e-9) + (1 - k) * nrm(perp(a_sn, th) + 1e-9))
        out["ua" + S] = (sj, basis(ua, a_ua), np.linalg.norm(el - sj))
        out["fa" + S] = (el, basis(fa, a_fa), np.linalg.norm(wr - el))
        out["hd" + S] = (wr, basis(hd - wr, a_fa), None)
        out["th" + S] = (hp, basis(th, a_th), np.linalg.norm(kn - hp))
        out["sn" + S] = (kn, basis(sn, a_sn), np.linalg.norm(an - kn))
        out["ft" + S] = (an, basis(ft, np.array([0.0, 1.0, 0.0])), None)
    return out


_rest = None


def widen(J, Jr):
    """The 2D figure is narrow: move shoulders and hips out to the body's width. Hands that grip or meet in front
    of the body (inside the shoulder line) stay where they are."""
    ws = np.linalg.norm(np.asarray(Jr["shoulderL"]) - Jr["shoulder"])
    wh = np.linalg.norm(np.asarray(Jr["hipL"]) - Jr["hip"])
    for S in ("N", "F"):
        out = J["shoulder" + S] - J["shoulder"]
        w = np.linalg.norm(out); out = out / max(w, 1e-9)
        d = ws - w
        k = float(np.clip(((J["hand" + S] - J["shoulder"]) @ out) / max(w, 1e-9), 0, 1))
        J["shoulder" + S] = J["shoulder" + S] + out * d
        J["elbow" + S] = J["elbow" + S] + out * d * (0.6 + 0.4 * k)
        for j in ("wrist", "hand"):
            J[j + S] = J[j + S] + out * d * k
        out = J["hip" + S] - J["hip"]
        w = np.linalg.norm(out); out = out / max(w, 1e-9)
        for j in ("hip", "knee", "ankle", "toe"):
            J[j + S] = J[j + S] + out * (wh - w)
    return J


def pose(J, fist=("N", "F")):
    """Skin the rest mesh onto positions.py joints; hands on the `fist` sides grip.
    Returns vertices, triangles, material per triangle (0 skin, 1 shorts, 2 eye), muscle per vertex."""
    global _rest
    if _rest is None:
        r = np.load(REST)
        _rest = {k: r[k] for k in ("v", "vf", "f", "m", "w", "mu", "cav", "band")}
        _rest["j"] = json.loads(str(r["j"]))
    R = _rest
    W = R["w"].astype(float)
    Jr = R["j"]
    Jt = widen({k: np.asarray(v, float) for k, v in J.items() if not k.startswith("_")}, Jr)
    up = Jt["shoulder"] - Jt["hip"]
    toe = (Jt["toeN"] + Jt["toeF"]) / 2 - (Jt["ankleN"] + Jt["ankleF"]) / 2
    fwd = toe - (toe @ up) / (up @ up) * up
    chir = np.linalg.det(np.stack([fwd, up, Jt["shoulderF"] - Jt["shoulderN"]]))
    side_t = {"L": "N", "R": "F"} if chir > 0 else {"L": "F", "R": "N"}
    V = R["v"].astype(float).copy()
    for S in "LR":
        if side_t[S] in fist:
            m = W[:, SEGS.index("hd" + S)] > 0.05
            V[m] = R["vf"][m]
    fr, ft = _frames(Jr, {"L": "L", "R": "R"}), _frames(Jt, side_t)
    # dual-quaternion skinning (keeps volume at shoulders, elbows and knees)
    Q0 = np.zeros((len(SEGS), 4)); Qe = np.zeros((len(SEGS), 4))
    for i, seg in enumerate(SEGS):
        if seg[:2] in HELPERS:
            continue
        (o0, B0, _), (o1, B1, _) = fr[seg], ft[seg]
        Rm = B1 @ B0.T
        tr = o1 - Rm @ o0
        q = _quat(Rm)
        Q0[i] = q
        Qe[i] = 0.5 * _qmul(np.array([0, *tr]), q)
    for i, seg in enumerate(SEGS):
        if seg[:2] in HELPERS:
            a, b = (SEGS.index(x if x != "ua" and x != "th" else x + seg[-1]) for x in HELPERS[seg[:2]])
            sg = 1 if Q0[a] @ Q0[b] >= 0 else -1
            Q0[i] = 0.5 * (Q0[a] + sg * Q0[b]); Qe[i] = 0.5 * (Qe[a] + sg * Qe[b])
            nq = np.linalg.norm(Q0[i]); Q0[i] /= nq; Qe[i] /= nq
    piv = Q0[W.argmax(1)]
    sgn = np.sign(np.einsum("vk,sk->vs", piv, Q0)); sgn[sgn == 0] = 1
    Ws = W * sgn
    b0 = Ws @ Q0; be = Ws @ Qe
    n = np.linalg.norm(b0, axis=1, keepdims=True)
    b0 /= n; be /= n
    w0, xyz = b0[:, :1], b0[:, 1:]
    we, xyze = be[:, :1], be[:, 1:]
    t = 2 * (w0 * xyze - we * xyz + np.cross(xyz, xyze))
    out = V + 2 * np.cross(xyz, np.cross(xyz, V) + w0 * V) + t
    legs = W[:, [SEGS.index(x) for x in ("pelvis", "thL", "thR", "hpL", "hpR")]].sum(1) > 0.5
    return out, R["f"], R["m"], R["mu"], R["cav"], np.where(legs, R["v"][:, 1], 999), R["band"]


def fibre_phase(V, mu, J, freq=5.2):
    """Per-vertex phase for the muscle-fibre striation shader: lines run along each muscle's fibre direction
    (rest coords: x forward, y up, z lateral), so the phase advances across the fibres."""
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    az = np.abs(z)
    ph = np.zeros(len(V))
    name = np.array(MUSCLES)[mu]
    planar = {"chest": y - 0.3 * az, "abs": z, "lower-abs": z, "obliques": y + 0.8 * az, "serratus": y - az,
              "traps": 0.6 * y + 0.8 * az, "lats": y + 0.9 * az, "upper-back": 0.3 * y + az, "lower-back": z,
              "glutes": y - 0.8 * az, "glute-med": x + 0.2 * y, "hip-flexors": z}
    for m, coord in planar.items():
        k = name == m
        ph[k] = coord[k] * freq
    F = _frames(J, {"L": "L", "R": "R"})
    limb = {"front-delts": "ua", "side-delts": "ua", "rear-delts": "ua", "biceps": "ua", "triceps": "ua", "brachialis": "ua",
            "forearms": "fa", "forearm-extensors": "fa", "quads": "th", "hamstrings": "th", "adductors": "th",
            "calves": "sn", "soleus": "sn", "tibialis": "sn"}
    for m, seg in limb.items():
        k = np.isin(mu, [MUSCLES.index(m)])
        if not k.any():
            continue
        for S in "LR":
            o, B, L = F[seg + S]
            q = (V[k] - o) @ B
            side = (z[k] < 0) if S == "L" else (z[k] >= 0)
            ang = np.arctan2(q[:, 2], q[:, 1])
            r = np.hypot(q[:, 1], q[:, 2])
            idx = np.nonzero(k)[0][side]
            ph[idx] = (ang * r)[side] * freq
    return ph


def export_json(V, Fc, M, mu, cav, ry, band, path, ph=None):
    n = np.zeros_like(V); t = V[Fc]; fn = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    for k in range(3):
        np.add.at(n, Fc[:, k], fn)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    order = np.argsort(M, kind="stable")
    Path(path).write_text(json.dumps({"v": np.round(V, 2).ravel().tolist(), "n": np.round(n, 3).ravel().tolist(),
                                      "f": Fc[order].ravel().tolist(), "fm": np.bincount(M, minlength=3).tolist(),
                                      "mu": mu.tolist(), "muscles": MUSCLES,
                                      "cav": np.round(cav.astype(float), 3).tolist(), "ry": np.round(ry.astype(float), 2).tolist(),
                                      "band": band.tolist(),
                                      "ph": None if ph is None else np.round(ph, 2).tolist()}))


def export_bin(path):
    """ExerciseBody.bin.z for the app (raw deflate). Little-endian:
    "MWB2", u32 nv, u32 nt, u32 nb, u32 nf;
    nv x [i16 x,y,z (x100), u8 cavity (0..255 = -1..1), u8 muscle | 0x80 shorts, u16 fibre phase (0..65535 = 0..2pi),
          u8 bone[4], u8 weight[4]];
    nf x [u16 vertex, i16 x,y,z (x100)]  fist positions for hand vertices;
    nt x [u16 a,b,c];
    nb x [u8 parent (255 = none), f32 head[3], f32 tail[3], u8 len, ascii name];
    f32 palmL[3], f32 palmR[3]."""
    import struct
    r = np.load(HERE / "body_rig.npz"); b = np.load(REST)
    V, Vf, bi, bw = r["v"], r["vf"], r["bi"].astype(int), r["bw"].astype(float)
    names = json.loads(str(r["names"]))
    F, mu, cav, band = b["f"], b["mu"].astype(int), b["cav"].astype(float), b["band"]
    hips = np.isin(bi[:, 0], [i for i, nm in enumerate(names) if nm.startswith(("upperleg", "pelvis", "root", "spine05", "spine04"))])
    shorts = hips & (V[:, 1] > band[1]) & (V[:, 1] < band[0])
    ph = fibre_phase(V.astype(float), mu, Rig_rest_joints(r, names))
    out = bytearray(b"MWB2")
    fist = np.nonzero(np.any(np.abs(Vf - V) > 1e-3, axis=1))[0]
    out += struct.pack("<4I", len(V), len(F), len(names), len(fist))
    q = lambda x: int(np.clip(round(x * 100), -32768, 32767))
    w8 = np.clip(np.round(bw * 255), 0, 255).astype(int)
    for i in range(len(V)):
        out += struct.pack("<3hBBH4B4B", q(V[i, 0]), q(V[i, 1]), q(V[i, 2]), int(np.clip((cav[i] + 1) * 127.5, 0, 255)),
                           mu[i] | (0x80 if shorts[i] else 0), int((ph[i] % (2 * np.pi)) / (2 * np.pi) * 65535) & 0xFFFF,
                           *bi[i].tolist(), *w8[i].tolist())
    for i in fist:
        out += struct.pack("<H3h", int(i), q(Vf[i, 0]), q(Vf[i, 1]), q(Vf[i, 2]))
    out += F.astype("<u2").tobytes()
    for i, nm in enumerate(names):
        p = int(r["parents"][i])
        out += struct.pack("<B6fB", 255 if p < 0 else p, *r["heads"][i].tolist(), *r["tails"][i].tolist(), len(nm)) + nm.encode()
    out += r["palm"].astype("<f4").tobytes()
    z = zlib.compressobj(9, zlib.DEFLATED, -15)
    data = z.compress(bytes(out)) + z.flush()
    Path(path).write_bytes(data)
    print(len(out), "bytes raw,", len(data), "packed,", len(fist), "fist verts")


def Rig_rest_joints(r, names):
    ix = {n: i for i, n in enumerate(names)}
    h = lambda n: r["heads"][ix[n]].astype(float)
    J = {"hip": (h("upperleg01.L") + h("upperleg01.R")) / 2, "shoulder": (h("upperarm01.L") + h("upperarm01.R")) / 2,
         "neck": h("neck01"), "head": h("head") + (r["tails"][ix["head"]] - h("head")) * 0.35}
    for s in "LR":
        J["shoulder" + s] = h(f"upperarm01.{s}"); J["elbow" + s] = h(f"lowerarm01.{s}")
        J["wrist" + s] = h(f"wrist.{s}"); J["hand" + s] = h(f"finger3-1.{s}")
        J["hip" + s] = h(f"upperleg01.{s}"); J["knee" + s] = h(f"lowerleg01.{s}")
        J["ankle" + s] = h(f"foot.{s}"); J["toe" + s] = h(f"toe3-1.{s}")
    return J


if __name__ == "__main__" and sys.argv[1] == "--bin":
    export_bin(sys.argv[2] if len(sys.argv) > 2 else DATA.parent / "ExerciseBody.bin.z")
    sys.exit()

if __name__ == "__main__" and sys.argv[1] != "--build":
    d = json.loads(zlib.decompress(DATA.read_bytes(), -15))
    export_json(*pose(d[sys.argv[1]]["k"][int(sys.argv[2])]["j"]), sys.argv[3])

if __name__ == "__main__" and sys.argv[1] == "--build":
    build(sys.argv[2], {t: 1.0 for t in sys.argv[3:]} or None)
