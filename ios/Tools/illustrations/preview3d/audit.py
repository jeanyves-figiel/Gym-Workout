# python3 audit.py DATA [ids] -> per key: contact issues
import os, sys, json, zlib, numpy as np
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent.parent))
import rig as rigmod
rigmod.MUSH = 0
d = json.loads(zlib.decompress(open(sys.argv[1], 'rb').read(), -15))
ids = sys.argv[2:] or sorted(d)
R = rigmod.Rig()
def bones(pref): return np.isin(R.bi[:, 0], [R.ix[n] for n in R.names if n.startswith(pref)])
FOOT = {s: np.isin(R.bi[:, 0], [R.ix[n] for n in R.names if (n.startswith(("foot", "toe")) and n.endswith("." + s))]) for s in "LR"}
HAND = {s: np.isin(R.bi[:, 0], [R.ix[n] for n in R.names if (n.startswith(("finger", "metacarpal", "wrist")) and n.endswith("." + s))]) for s in "LR"}
def pad_box(p):
    a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
    u = b - a; L = np.linalg.norm(u); u /= max(L, 1e-6)
    n = np.array([p["n"][0], p["n"][1], 0.0]); t = np.linalg.norm(n); nh = n / t if t > 1e-6 else np.array([0, 1.0, 0])
    w = p.get("w", 0) or 17
    return a, u, L, nh, max(t, 4), w
def depth_in_pad(V, p):
    """signed distance outside (positive) / inside (negative) the pad box, per vertex (approx: max of slab distances)"""
    a, u, L, nh, t, w = pad_box(p)
    r = V - a
    al = r @ u; dn = r @ nh; lat = r[:, 2] - a[2]
    return np.max(np.stack([-al, al - L, -dn, dn - t, np.abs(lat) - w]), 0)
def depth_in_block(V, p):
    lo, hi = np.asarray(p["lo"], float), np.asarray(p["hi"], float)
    return np.max(np.concatenate([lo - V, V - hi], 1), 1)
def depth_in_rod(V, p):
    a, b = np.asarray(p["a"], float), np.asarray(p["b"], float); ab = b - a
    t = np.clip(((V - a) @ ab) / max(ab @ ab, 1e-6), 0, 1)
    return np.linalg.norm(V - (a + t[:, None] * ab), axis=1) - max(p.get("r", 2), 1.6)
FING = {s: np.isin(R.bi[:, 0], [R.ix[n] for n in R.names if (n.startswith(("finger",)) and n.endswith("." + s))]) for s in "LR"}
res = {}
for ex in ids:
    out = []
    for ki, k in enumerate(d[ex]["k"]):
        V = R.pose(k["j"], k["p"]) + np.array([0, k.get("dy", 0), 0])
        J = {n: np.asarray(v, float) for n, v in k["j"].items() if not n.startswith("_")}
        iss = []
        up = J["shoulder"] - J["hip"]; toe = rigmod.facing(J)
        chir = np.linalg.det(np.stack([rigmod.perp(toe, rigmod.nrm(up)), up, J["shoulderF"] - J["shoulderN"]]))
        SIDE = {"N": "L", "F": "R"} if chir > 0 else {"N": "R", "F": "L"}
        # hands
        for dd in "NF":
            h = R.held[dd]
            if h and h[0] == "rod":
                a, b = h[2]; ab = b - a; g = V[FING[SIDE[dd]]].mean(0)
                t = np.clip(((g - a) @ ab) / (ab @ ab), 0, 1); gap = np.linalg.norm(g - (a + t * ab))
                if gap > 6: iss.append(f"grip{dd} off rod {gap:.0f}")
            if not h:
                for p in k["p"]:
                    if p["k"] == "rod" and p.get("s") == "handle":
                        dist = depth_in_rod(J["hand" + dd][None], p)[0]
                        if dist < 25: iss.append(f"free hand{dd} near handle {dist:.0f}")
        # penetration / gaps against static solids
        for i, p in enumerate(k["p"]):
            if p["k"] == "pad": dep = depth_in_pad(V, p)
            elif p["k"] == "block": dep = depth_in_block(V, p)
            elif p["k"] == "rod" and p.get("s") not in ("cable", "handle"): dep = depth_in_rod(V, p)
            else: continue
            hands = HAND["L"] | HAND["R"]
            inside = (dep < -3) & ~hands
            if inside.sum() > 30: iss.append(f"body in {p['k']}{i} {int(inside.sum())}v {-dep[inside].min():.0f}")
            for s in "LR":
                fd = dep[FOOT[s]].min()
                if p["k"] in ("pad", "block") and 2.5 < fd < 22:
                    # only when foot not on floor (gap vs floor)
                    if V[FOOT[s], 1].min() > 3: iss.append(f"foot{s} gap {p['k']}{i} {fd:.0f}")
        # floating body: nothing within 3 of any vertex? (min y > 3 and no support)
        out.append(iss)
    res[ex] = out
    if any(out): print(ex, out, flush=True)
json.dump(res, open(os.environ.get("AUDIT_JSON", "audit.json"), "w"))
