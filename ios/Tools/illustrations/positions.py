#!/usr/bin/env python3
"""3D key positions of every exercise for the position guide (#399).

    python3 ios/Tools/illustrations/positions.py          # write ExercisePositions.json.z
    python3 ios/Tools/illustrations/positions.py --check  # range-of-motion check only (exit 1 on a flag)

The animation and the guide share one source: each scene's start, middle and end key poses (the same joints
art.render draws, after the scene moved them) are lifted to 3D. Side view: the drawing gives forward and up,
near limbs sit on the viewer's side, far limbs on the other (shoulder / hip width). Front and back views: the
drawing gives sideways and up. The figure always faces +x, y is up, the floor is y = 0 (px of the 400×300
drawing, ~190 px tall standing).

Equipment drawn by the scene (pads, frame tubes, plates, dumbbells, boxes…) is recorded the same way and given
a depth: pads and boxes span the bench width, plates sit on a bar across the body, frames stand on both sides.

The check flags key poses a real body cannot take (knee or elbow bent backwards, joints past their range):
the 2D art can hide those in a side view, the 3D guide cannot.
"""
import json
import re
import math
import sys
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import art  # noqa: E402
import generate  # noqa: E402
import kit  # noqa: E402

OUT = generate.IOS / "Packages/GymCore/Sources/WorkoutEngine/Resources/ExercisePositions.json.z"
FLOOR = art.GROUND - 4
SHOULDER = art.PROFILES["torso"][-1][1] * 1.45 * 0.9  # half shoulder width, as art.frontal
HIP = 9.0
SIDES = {"N": 1, "F": -1}
LIMB = ("elbow", "wrist", "hand", "knee", "ankle", "toe")

# Reviewed in the 3D preview (#399): deep tucks and crossed legs the quarter-turn rule misreads.
ALLOWED = {
    "figure-4": "ankle crossed over the other knee: the far shin is drawn across the thigh",
    "front-lever": "tuck to straight lever, knees pulled to the chest",
    "tuck-back-lever": "inverted tuck: knees fully bent, shin direction flips with the body",
    "tuck-front-lever": "knees pulled to the chest under the bar",
}

# Equipment recorded while a key frame draws: (kind, points, size).
_rec = None


_depth = 0  # inside a recorded primitive: its own drawing is not parsed again
_in_scene = False  # the scene (or pose props) is drawing, not the figure


def _hook(mod, name, kind, pts):
    orig = getattr(mod, name)

    def wrapped(doc, *a, **k):
        global _depth
        if _rec is not None and _depth == 0:
            try:
                _rec.append((kind,) + pts(*a, **k))
            except Exception:  # noqa: BLE001 - a prop we cannot read is just left out of the guide
                pass
        _depth += 1
        try:
            return orig(doc, *a, **k)
        finally:
            _depth -= 1
    setattr(mod, name, wrapped)
    if mod is art and name in art.PRIMS:  # pose props call through this table
        art.PRIMS[name] = wrapped


NUM = r'(-?[\d.]+)'


def _attr(frag, name):
    m = re.search(rf'\b{name}="{NUM}"', frag)
    return float(m.group(1)) if m else None


def _parse(frag):
    """Equipment a scene drew straight into the SVG (its own helpers): circles, thick lines, plain rects."""
    out = []
    if "transform=" in frag or 'fill-opacity="0.' in frag:
        return out
    fill = re.search(r'fill="(#[0-9A-Fa-f]{6})"', frag)
    col = fill.group(1) if fill else None
    for m in re.finditer(r'<circle [^>]*>', frag):
        c = m.group(0)
        r = _attr(c, "r")
        if r and r >= 5:
            f = re.search(r'fill="(#[0-9A-Fa-f]{6})"', c)
            out.append(("orb", [(_attr(c, "cx"), _attr(c, "cy"))], r, f.group(1) if f else None))
    for m in re.finditer(r'<line [^>]*>', frag):
        ln = m.group(0)
        w = _attr(ln, "stroke-width") or 1
        if w >= 2.5:
            out.append(("tube", [(_attr(ln, "x1"), _attr(ln, "y1")), (_attr(ln, "x2"), _attr(ln, "y2"))], w))
    for m in re.finditer(r'<rect [^>]*>', frag):
        rc = m.group(0)
        x, y, w, h = (_attr(rc, k) for k in ("x", "y", "width", "height"))
        if None in (x, y, w, h) or w < 4 or h < 4 or w > 300:
            continue
        out.append(("block", [(x, y), (x + w, y + h)], 30))
    return out


_add = art.Doc.add


def _doc_add(self, frag):
    if _rec is not None and _depth == 0 and _in_scene:
        for p in _parse(frag):
            _rec.append(p[:3] + (({"col": p[3]},) if len(p) > 3 else ()))
    return _add(self, frag)


art.Doc.add = _doc_add


_hook(art, "tube", "tube", lambda a, b, w=7, cap=None: ([a, b], w))
_hook(art, "pad", "pad", lambda a, b, t=11, stitch=True: ([a, b], t))
_hook(art, "plate", "plate", lambda c, r=30, hub=True: ([c], r))
_hook(art, "db_end", "db", lambda c, r=10: ([c], r))
_hook(art, "stack", "block", lambda x, top, bottom, w=34, plates=12, lifted=0: ([(x, top), (x + w, bottom)], 34))
_hook(art, "shroud", "block", lambda x, top, bottom, w: ([(x, top), (x + w, bottom)], 34))
_hook(kit, "box", "block", lambda x, w, h, color=None: ([(x, art.GROUND - h), (x + w, art.GROUND)], 60))
_hook(kit, "mat", "mat", lambda x0, x1, color=None: ([(x0, art.GROUND - 3), (x1, art.GROUND)], 70))
_hook(kit, "kettlebell", "kb", lambda c, up=False, r=11: ([c], r))
_hook(kit, "ball", "ball", lambda c, r=13, color=None: ([c], r))
_hook(kit, "strap", "tube", lambda c, anchor, handle=True, color=None: ([c, anchor], 3))
_hook(kit, "ring", "tube", lambda c, anchor: ([c, anchor], 3))
_hook(art, "cable", "cable", lambda pts: (list(pts), 1.2))
_hook(art, "pulley", "pulley", lambda c, r=6.5: ([c], r))
_hook(kit, "handle", "handle", lambda c, kind="d": ([c], 7))
_hook(kit, "band", "cable", lambda a, b, color=None: ([a, b], 2.4))
_hook(kit, "pullup_bar", "bar", lambda c, top=4, half=34: ([c], 60))

_render = art.render
_frames = []


def _scene_flag(fn):
    def run(*a, **k):
        global _in_scene
        _in_scene = True
        try:
            return fn(*a, **k)
        finally:
            _in_scene = False
    return run


art.draw_props = _scene_flag(art.draw_props)


def _capture(pose, ex, scene=None, *a, **k):
    global _rec
    _rec = []
    svg = _render(pose, ex, _scene_flag(scene) if scene else None, *a, **k)
    _frames.append((art.LAST[0], art.LAST[1], _rec))
    _rec = None
    return svg


art.render = _capture


WIDE = {"squat", "hinge", "jump", "carry", "throw"}  # patterns standing with feet about shoulder-width apart
GRIP = 28  # half grip width on a barbell or pull-up bar (about 1.5x shoulder width)


def patterns():
    src = "".join(f.read_text() for f in (generate.CATALOG, generate.TRAVEL, generate.VARIATIONS, generate.GYMAPP,
                                          generate.CLIMBING))
    return dict(re.findall(r'Exercise\(id: "([^"]+)", name: "[^"]+", category: \.\w+, pattern: \.`?(\w+)`?', src))


def on_bar(j, rec):
    """Both hands on a bar running across the body (barbell plates or a pull-up bar near the hands)."""
    bars = [r[1][0] for r in rec if r[0] in ("plate", "bar")]
    return bool(bars) and all(min(math.dist(j["wrist" + s], b) for b in bars) < 40 for s in SIDES)


def lift(j, view, cx, stance=HIP, grip=None):
    """3D joints (figure facing +x, y up, floor 0) from a drawn frame's joints. `stance`: half the distance
    between the feet; `grip`: half the distance between the hands when they hold a bar."""
    out = {}

    def p(u, v, z=0.0):
        return [u, FLOOR - v, z]
    if view == "side":
        for k in ("hip", "shoulder", "neck", "head"):
            out[k] = p(j[k][0] - cx, j[k][1])
        for s, sign in SIDES.items():
            out["shoulder" + s] = p(j["shoulder"][0] - cx, j["shoulder"][1], sign * SHOULDER)
            out["hip" + s] = p(j["hip"][0] - cx, j["hip"][1], sign * HIP)
            for k in LIMB:
                if k in ("wrist", "hand"):
                    w = grip or SHOULDER
                elif k == "elbow":
                    w = SHOULDER + ((grip or SHOULDER) - SHOULDER) * 0.7
                elif k == "knee":
                    w = HIP + (stance - HIP) * 0.9
                else:
                    w = stance + (4 if k == "toe" else 0)
                out[k + s] = p(j[k + s][0] - cx, j[k + s][1], sign * w)
    else:
        flip = -1 if view == "front" else 1  # seen from +x (front) or -x (back)
        for k in ("hip", "shoulder", "neck", "head"):
            out[k] = [0.0, FLOOR - j[k][1], flip * (j[k][0] - cx)]
        for s in SIDES:
            for k in ("shoulder", "hip") + LIMB:
                q = j.get(k + s, j.get(k))
                out[k + s] = [0.0, FLOOR - q[1], flip * (q[0] - cx)]
        if view == "front":  # toes point at the viewer
            for s in SIDES:
                out["toe" + s][0] += 12
        else:
            for s in SIDES:
                out["toe" + s][0] += 12
    return out


F = art.F
BONES = {"elbow": ("shoulder", F.UPPER_ARM), "wrist": ("elbow", F.FOREARM), "hand": ("wrist", F.HAND),
         "knee": ("hip", F.THIGH), "ankle": ("knee", F.SHIN), "toe": ("ankle", F.FOOT)}


def recover_depth(J, view):
    """Limbs drawn shorter than they are point out of the picture: give them back the missing depth (#401).
    Front / back views: forwards (+x), arms reaching, knees over the toes, a torso leaning in. Side view: across
    the body (the near arm crossing to the far side), as pec deck and cable crossovers are drawn."""
    flat = (lambda v: (v[0], v[1])) if view == "side" else (lambda v: (v[2], v[1]))
    axis = 2 if view == "side" else 0
    orig = {k: list(v) for k, v in J.items()}
    if view != "side":  # torso leaning towards or away from the camera
        l = math.dist(flat(orig["hip"]), flat(orig["shoulder"]))
        if l < F.TORSO * 0.95:
            d = math.sqrt(F.TORSO ** 2 - l * l)
            for k in J:
                if k.startswith(("shoulder", "neck", "head", "elbow", "wrist", "hand")):
                    J[k][0] += d
    for s, sign in SIDES.items():
        for k in ("elbow", "wrist", "hand", "knee", "ankle", "toe"):
            parent, L = BONES[k]
            a, b = orig[parent + s], orig[k + s]
            l = math.dist(flat(a), flat(b))
            extra = math.sqrt(max(0.0, L * L - l * l)) if l < L * 0.95 else 0.0
            if view == "side":
                extra *= -sign  # across the body
            new = [J[parent + s][i] + b[i] - a[i] for i in range(3)]
            new[axis] += extra
            J[k + s] = new
    return J


def props(rec, view, cx, hands):
    """Equipment as 3D primitives: box (two corners), rod (two ends + radius), disc (centre, radius, axis),
    weights. `hands`: (x, y, joint 3D) of the drawn hands and wrists: anything drawn at a hand (handle, cable
    end, dumbbell, bar) follows the hand into 3D."""
    out = []

    def held(pt, reach=12):
        near = [h for h in hands if math.dist(pt, h[:2]) < reach]
        return list(min(near, key=lambda h: math.dist(pt, h[:2]))[2]) if near else None

    def P(pt, z=0.0):
        u, v = pt
        return [u - cx, FLOOR - v, z] if view == "side" else [0.0, FLOOR - v, (-1 if view == "front" else 1) * (u - cx)]

    def side_z(pt):
        """Depth of a free point in a side view: on the side of the nearest hand."""
        return min(hands, key=lambda h: math.dist(pt, h[:2]))[2][2] if hands else 0.0

    def depth(a, b, half):
        """Corners of a slab drawn a→b, `half` deep across the drawing."""
        if view == "side":
            return P(a, -half), P(b, half)
        pa, pb = P(a), P(b)
        pa[0], pb[0] = -half, half
        return pa, pb
    for kind, pts, size, *extra in rec:
        if kind == "pad":
            a, b = pts
            # the drawn pad's thickness sits on the left of a→b
            d = (b[0] - a[0], b[1] - a[1])
            L = math.hypot(*d) or 1
            n = (d[1] / L * size, -d[0] / L * size)
            out.append(dict(k="pad", a=P(a), b=P(b), n=[n[0], -n[1]], w=17 if view == "side" else 0))
        elif kind in ("block", "mat"):
            a, b = depth(pts[0], pts[1], size / 2)
            out.append(dict(k=kind, lo=[min(a[i], b[i]) for i in range(3)], hi=[max(a[i], b[i]) for i in range(3)]))
        elif kind == "cable":
            # cable / band: free points on the hand's side (side view), the ends at a hand follow it
            pp = [held(q, 8) or P(q, side_z(q) if view == "side" else 0.0) for q in pts]
            for a, b in zip(pp, pp[1:]):
                out.append(dict(k="rod", a=a, b=b, r=size / 2, s="cable" if size < 2 else "band"))
        elif kind == "pulley":
            c = pts[0]
            out.append(dict(k="disc", c=P(c, side_z(c) if view == "side" else 0.0), r=size, ax="x" if view != "side" else "z"))
        elif kind == "handle":
            h = held(pts[0]) or P(pts[0], side_z(pts[0]) if view == "side" else 0.0)
            out.append(dict(k="rod", a=[h[0], h[1] - 6, h[2]], b=[h[0], h[1] + 6, h[2]], r=3, s="handle"))
        elif kind == "tube":
            a, b = pts
            if math.dist(a, b) < 6:
                continue
            ha, hb = held(a, 10), held(b, 10)
            if ha or hb:  # a bar or handle in the hand
                za = ha or P(a, side_z(a) if view == "side" else 0.0)
                zb = hb or P(b, side_z(b) if view == "side" else 0.0)
                out.append(dict(k="rod", a=za, b=zb, r=size / 2))
            elif view == "side":  # machine frame: both sides of the machine
                for z in (-26, 26):
                    out.append(dict(k="rod", a=P(a, z), b=P(b, z), r=size / 2))
            else:
                out.append(dict(k="rod", a=P(a), b=P(b), r=size / 2))
        elif kind in ("plate", "bar"):
            c = pts[0]
            if view == "side":
                out.append(dict(k="rod", a=P(c, -62), b=P(c, 62), r=2.2))
                if kind == "plate":
                    for z in (-50, 50):
                        out.append(dict(k="disc", c=P(c, z), r=size))
            else:
                out.append(dict(k="disc", c=P(c), r=size, ax="x"))
        elif kind == "orb":  # circle the scene drew itself: ball, wheel, ring, roller, hub
            c = pts[0]
            h = held(c, size + 6)
            if h is None:
                near = hands and min(math.dist(c, q[:2]) for q in hands) < 30
                h = P(c, side_z(c) if view == "side" and near else 0.0)
            o = dict(k="ball", c=h, r=size)
            if extra and extra[0].get("col"):
                o["col"] = extra[0]["col"]
            out.append(o)
        elif kind in ("db", "kb", "ball"):
            c = held(pts[0], 22) or P(pts[0], side_z(pts[0]) if view == "side" else 0.0)
            out.append(dict(k=kind, c=c, r=size))
    # identical primitives (both layers of a scene) once
    seen, uniq = set(), []
    for o in out:
        o = json.loads(json.dumps(o), parse_float=lambda v: round(float(v), 1))
        key = json.dumps(o, sort_keys=True)
        if key not in seen:
            seen.add(key)
            uniq.append(o)
    return uniq


def angle(a, b, c):
    """Angle at b (degrees, 180 = straight)."""
    u = [a[i] - b[i] for i in range(3)]
    v = [c[i] - b[i] for i in range(3)]
    nu, nv = math.hypot(*u), math.hypot(*v)
    if not nu or not nv:
        return 180.0
    return math.degrees(math.acos(max(-1, min(1, sum(u[i] * v[i] for i in range(3)) / nu / nv))))


def bends_backwards(j, view, hip, knee, ankle):
    """Side view: a knee flexes towards the front of the shin (where the toes point with a neutral ankle). Bent
    the other way, the drawing shows a knee bent backwards."""
    if view != "side" or angle(j[hip], j[knee], j[ankle]) > 160:
        return False
    (hx, hy), (kx, ky), (ax, ay) = j[hip][:2], j[knee][:2], j[ankle][:2]
    fx, fy = -(ay - ky), ax - kx  # shin turned a quarter: its front
    dx, dy = ax - hx, ay - hy
    return (dx * (ky - hy) - dy * (kx - hx)) * (dx * fy - dy * fx) < 0


def round_pt(p):
    return [round(v, 1) for v in p]


def export(ex_id, cat, scenes, pattern):
    _frames.clear()
    generate._render(ex_id, cat, scenes, None, 17)
    keys = [_frames[i] for i in (0, len(_frames) // 2, len(_frames) - 1)] if _frames else []
    if len(keys) < 3:
        return None, []
    entry = scenes[ex_id]
    drawn = keys[0][0]
    view = "side" if "hipN" not in drawn else ("back" if _is_back(entry) else "front")
    xs = [v[0] for j, _, _ in keys for k, v in j.items() if not k.startswith("_") and isinstance(v, tuple)]
    cx = (min(xs) + max(xs)) / 2
    out, flags = [], []
    for n, (j, _, rec) in enumerate(keys):
        J = recover_depth(lift(j, view, cx, 17.0 if pattern in WIDE else 11.0, GRIP if on_bar(j, rec) else None), view)
        hands2d = [(j[k + s][0], j[k + s][1], J[k + s]) for s in SIDES for k in ("hand", "wrist")]
        out.append(dict(j={k: round_pt(v) for k, v in J.items()}, p=props(rec, view, cx, hands2d)))
        for s in SIDES:
            if bends_backwards(J, view, "hip", "knee" + s, "ankle" + s):
                flags.append(f"{ex_id}: key {n} knee{s} bends backwards")
    # figures drawn off the floor (hanging, floor=False scenes) stand on y = 0 at their lowest point
    low = min(min(p[1] for p in k["j"].values()) for k in out)
    if low < 0:
        for k in out:
            for p in k["j"].values():
                p[1] = round(p[1] - low, 1)
            for pr in k["p"]:
                for key in ("a", "b", "c", "lo", "hi"):
                    if key in pr:
                        pr[key][1] -= low
    return dict(v=view[0], k=out), flags


def _is_back(entry):
    if callable(entry):
        return False
    _, poses, _ = entry
    return any(p.get("front") == "back" for p in poses)


def main():
    cat = generate.catalog()
    scenes = generate.scenes()
    pat = patterns()
    data, flags = {}, []
    for ex_id in sorted(cat):
        e, f = export(ex_id, cat, scenes, pat.get(ex_id))
        flags += f
        if e:
            data[ex_id] = e
    flags = [f for f in flags if f.split(":")[0] not in ALLOWED]
    for f in flags:
        print(f)
    if "--check" in sys.argv:
        sys.exit(1 if flags else 0)
    raw = json.dumps(data, separators=(",", ":")).encode()
    c = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw deflate, as NSData.decompressed(using: .zlib)
    OUT.write_bytes(c.compress(raw) + c.flush())
    print(f"{len(data)} exercises, {len(raw) // 1024} KB json, {OUT.stat().st_size // 1024} KB packed")


if __name__ == "__main__":
    main()
