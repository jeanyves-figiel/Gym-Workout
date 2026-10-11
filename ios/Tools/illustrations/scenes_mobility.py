"""Mobility scenes for the realistic exercise art (#170): stretches, CARs and mobility drills.

Same conventions as scenes.py: angles as in poses.py (0 = right, 90 = down, figure faces right), every pose
pins a joint, static equipment in absolute view-box coordinates. Floor poses rest the body on the mat with
`rest()` (lowest point of the drawn body outline on the surface) and plant hands/feet with the 2-link
`reach()` solver, so frames stay anchored while the body moves. Views are fitted by `entry()`: the tightest
4:3 crop around every frame plus the equipment, with the muscle-map inset in a free corner.
"""
import math

import art
import kit
from art import GROUND
from poses import P

F = art.F
MAT = GROUND - 4          # mat top surface
WRIST_UP = 4.6            # wrist above the surface when the hand lies flat on it


# ---- geometry helpers ----------------------------------------------------------------------------

def joints(pose):
    j = F.place(pose)
    if art.view_of(pose) != "side":
        art.frontal(j)
    return j


def segments(pose):
    j = joints(pose)
    far, trunk, near = art.body_segments(j, art.view_of(pose) != "side")
    out = dict(trunk)
    out.update({k + "F": v for k, v in far.items()})
    out.update({k + "N": v for k, v in near.items()})
    return out


def _match(k, parts):
    return parts is None or k in parts or (k[-1] in "NF" and k[:-1] in parts)


def outline(pose, parts=None, dense=False):
    pts = []
    for k, s in segments(pose).items():
        if not _match(k, parts):
            continue
        pts += s.outline()
        if dense:
            pts += [s.at(u / 8, v / 2) for u in range(9) for v in range(-2, 3)]
    return pts


def rest(pose, joint, x, floor=MAT, parts=None):
    """Pin `joint` at x and move the figure vertically so its lowest outline point (of `parts`) sits on `floor`."""
    p = dict(pose, pin=(joint, (x, 0.0)))
    y = max(pt[1] for pt in outline(p, parts))
    return dict(pose, pin=(joint, (x, floor - y)))


def lowest(pose, parts=None):
    return max(pt[1] for pt in outline(pose, parts))


def _ang(v):
    return math.degrees(math.atan2(v[1], v[0]))


def ik(root, target, l1, l2):
    """Both 2-link solutions root→mid→target: [(a1, a2, mid), ...] (straight towards target if out of reach)."""
    dx, dy = target[0] - root[0], target[1] - root[1]
    d = min(max(math.hypot(dx, dy), abs(l1 - l2) + 0.01), l1 + l2 - 0.001)
    base = _ang((dx, dy))
    a = math.degrees(math.acos(max(-1, min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))))
    out = []
    for s in (1, -1):
        u = base + s * a
        mid = art.ang_pt(root, u, l1)
        out.append((u, _ang((target[0] - mid[0], target[1] - mid[1])), mid))
    return out


def reach(pose, limb, target, end=None, pick=None):
    """Set limb ("aN", "aF", "lN", "lF") so its wrist/ankle lands on `target`.
    Default bend: elbows flex forward (front of the arm), knees flex backward. `pick(mid)` chooses otherwise
    (largest score wins). `end` = hand/foot angle (default keeps the pose's own, else straight on)."""
    j = joints(pose)
    side = limb[1]
    arm = limb[0] == "a"
    front = art.view_of(pose) != "side"
    root = j[("shoulder" if arm else "hip") + (side if front else "")]
    l1, l2 = (F.UPPER_ARM, F.FOREARM) if arm else (F.THIGH, F.SHIN)
    sols = ik(root, target, l1, l2)
    if pick:
        u, f, _ = max(sols, key=lambda s: pick(s[2]))
    else:
        u, f, _ = sols[0] if arm else sols[1]
    old = pose.get(limb, (90, 90))
    if end is None and len(old) > 2:
        end = old[2]
    return dict(pose, **{limb: (u, f) + ((end,) if end is not None else ())})


def solve(fn, lo, hi, n=40):
    """Bisection: x in [lo, hi] with fn(x) == 0 (fn changes sign)."""
    flo = fn(lo)
    for _ in range(n):
        mid = (lo + hi) / 2
        fm = fn(mid)
        if (fm < 0) == (flo < 0):
            lo, flo = mid, fm
        else:
            hi = mid
    return (lo + hi) / 2


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def lerp(a, b, k):
    return a + (b - a) * k


def lerp2(a, b, k):
    return (lerp(a[0], b[0], k), lerp(a[1], b[1], k))


def tween(fn, ks=(0, 0.5, 1)):
    return [fn(k) for k in ks]


# ---- scenes & views ------------------------------------------------------------------------------

def make_scene(mat=None, back=None, front=None, shadow=None):
    def scene(doc, j, layer):
        if layer == "back":
            art.floor(doc, -120, art.W + 120)  # wide: some views reach past the 400-wide box
            if shadow:
                art.shadow(doc, *shadow)
            if mat:
                kit.mat(doc, *mat)
            if back:
                back(doc, j)
        elif front:
            front(doc, j)
    return scene


def _rect_pts(r, step=5):
    x0, y0, x1, y1 = r
    nx, ny = max(1, int((x1 - x0) / step)), max(1, int((y1 - y0) / step))
    return [(x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * k / ny) for i in range(nx + 1) for k in range(ny + 1)]


def _inset_rect(view, corner):
    x, y, w = view
    h = w * 0.75
    ph = h * 0.36
    pw = (2 * 200 + 10) * ph / 430 + 8
    px = x + 6 if corner[1] == "l" else x + w - pw - 6
    py = y + 6 if corner[0] == "t" else y + h - ph - 6
    return (px - 3, py - 3, px + pw + 3, py + ph + 3)


def fit(poses, boxes=(), avoid=(), margin=8, corner=None, floor=True):
    """Tightest 4:3 view around all frames + `boxes` (equipment rects x0,y0,x1,y1) with the inset in a free
    corner (`avoid` = more rects the inset must not cover). Returns (view, corner)."""
    frs = art.frames(poses)
    body = [p for f in frs for p in outline(f, dense=True)]
    pts = [p for f in frs for p in outline(f)] + [p for b in boxes for p in ((b[0], b[1]), (b[2], b[3]))]
    if floor:
        pts.append((pts[0][0], GROUND + 2))
    x0 = min(p[0] for p in pts) - margin
    x1 = max(p[0] for p in pts) + margin
    y0 = min(p[1] for p in pts) - margin
    y1 = max(p[1] for p in pts) + margin
    obstacles = body + [p for b in list(boxes) + list(avoid) + [(x0, GROUND - 1, x1, GROUND + 3)] for p in _rect_pts(b)]
    best = None
    for c in ([corner] if corner else ["tl", "tr", "bl", "br"]):
        w0 = max(x1 - x0, (y1 - y0) / 0.75)
        for i in range(120):
            w = w0 * (1 + 0.01 * i)
            h = w * 0.75
            # Floor at the bottom (vertical slack goes to the top); horizontally centred, else pushed away
            # from the inset corner.
            vy = y1 - h
            sx = [(x0 + x1) / 2 - w / 2, x1 - w if c[1] == "l" else x0]
            ok = None
            for vx_ in sx:
                r = _inset_rect((vx_, vy, w), c)
                if not any(r[0] <= p[0] <= r[2] and r[1] <= p[1] <= r[3] for p in obstacles):
                    ok = (vx_, vy)
                    break
            if ok:
                if best is None or w < best[0][2] - 0.5:
                    best = ((round(ok[0], 1), round(ok[1], 1), round(w, 1)), c)
                break
    return best


def entry(scene, poses, boxes=(), avoid=(), corner=None, margin=8, view=None):
    v, c = fit(poses, boxes, avoid, margin, corner)
    if view:
        v = view
    return (scene, [dict(p, inset=c) for p in poses], v)


def shadow_of(poses, parts=("foot", "shin", "thigh", "torso", "head", "hand")):
    xs = [p[0] for f in art.frames(poses) for p in outline(f, parts)]
    return ((min(xs) + max(xs)) / 2, (max(xs) - min(xs)) / 2 + 6)


def floor_entry(poses, mat=None, back=None, front=None, boxes=(), avoid=(), corner=None, margin=8, view=None):
    """Floor exercise: floor + shadow (+ mat) + optional extra equipment callbacks."""
    sh = shadow_of(poses)
    bx = list(boxes)
    if mat:
        bx.append((mat[0], MAT, mat[1], GROUND + 1))
    return entry(make_scene(mat, back, front, sh), poses, bx, avoid, corner, margin, view)


# ---- exercises -------------------------------------------------------------------------------------

SCENES = {}


def add(ex_id, e):
    SCENES[ex_id] = e


# Frog rock-backs: quadruped, knees wide, rock the hips back towards the heels, hands stay planted.
def _frog(k, forearms=False):
    KX = 176
    thigh = lerp(90, 30 if not forearms else 50, k)
    base = P(t=-15, h=-10, lN=(thigh, 180, 180), lF=(thigh + 4, 180, 180), aN=(90, 90, 0), aF=(92, 92, 0))
    legs = ("thigh", "shin", "foot")
    reach_len = 76 if not forearms else 40
    if forearms:
        base.update(aN=(90, 0, 0), aF=(92, 2, 0))
    wrist = (KX + (66 if not forearms else 46), MAT - WRIST_UP)

    def pose_t(t):
        return rest(dict(base, t=t), "kneeN", KX, MAT, legs)

    def err(t):
        j = joints(pose_t(t))
        tgt = wrist if not forearms else (wrist[0] - 2, MAT - 7)
        return dist(j["shoulder"], tgt) - reach_len
    t = solve(err, -40, 40)
    p = pose_t(t)
    p["h"] = t + (5 if not forearms else -8)
    if forearms:
        j = joints(p)
        p = reach(p, "aN", (j["shoulder"][0] + 2, MAT - 7))
        a = p["aN"]
        p["aN"] = (a[0], 0, 0)
        p["aF"] = (a[0] + 3, 2, 0)
    else:
        p = reach(p, "aN", wrist, end=0)
        p = reach(p, "aF", (wrist[0] + 3, wrist[1]), end=0)
    return p


add("frog-rockback", floor_entry(tween(_frog), mat=(84, 300)))


# ---- standing front-view squats ------------------------------------------------------------------------

def _out(cx, s):
    """pick(): knee/elbow furthest out on side s (+1 = screen right)."""
    return lambda m: s * (m[0] - cx)


def _prayer(p, drop=30, dx=0):
    """Hands together in front of the sternum (front view), elbows out."""
    j = joints(p)
    sh = j["shoulder"]
    c = sh[0]
    p = reach(p, "aN", (sh[0] + dx + 3, sh[1] + drop), end=-90, pick=_out(c, 1))
    p = reach(p, "aF", (sh[0] + dx - 3, sh[1] + drop), end=-90, pick=_out(c, -1))
    return p


def _front_legs(p, an, af, fN=0, fF=180):
    hx = joints(p)["hip"][0]
    p = reach(p, "lN", an, end=fN, pick=_out(hx, 1))
    return reach(p, "lF", af, end=fF, pick=_out(hx, -1))


def _deep_squat(k):
    CX = 200
    shift = lerp(-16, 16, k)
    hip = (CX + shift, GROUND - 50)
    p = P(front=True, t=-90 - shift * 0.25, h=-90 - shift * 0.5, pin=("hip", hip))
    p = _front_legs(p, (CX + 50, GROUND - 4), (CX - 50, GROUND - 4), 10, 170)
    j = joints(p)
    # Elbows press the inner knees, palms together.
    sh = j["shoulder"]
    p = reach(p, "aN", (sh[0] + shift * 0.2 + 3, sh[1] + 30), end=-90, pick=_out(sh[0], 1))
    p = reach(p, "aF", (sh[0] + shift * 0.2 - 3, sh[1] + 30), end=-90, pick=_out(sh[0], -1))
    return p


add("deep-squat-pry", floor_entry(tween(_deep_squat)))


def _cossack(k):
    CX = 200
    AN, AF = (CX + 66, GROUND - 4), (CX - 66, GROUND - 4)
    hx = CX + lerp(0, 40, k)

    def at_y(y):
        return P(front=True, t=-90 + 6 * k, h=-90 + 4 * k, pin=("hip", (hx, y)))
    if k == 0:
        y = GROUND - 4 - 100
    else:
        y = solve(lambda y: dist(joints(at_y(y))["hipF"], AF) - (109.6 if k == 1 else 104), GROUND - 140, GROUND - 20)
    p = _front_legs(at_y(y), AN, AF, 0, lerp(180, 255, k))
    return _prayer(p, 32)


add("bw-cossack", floor_entry(tween(_cossack)))


# ---- seated on the mat -------------------------------------------------------------------------------

def _pancake(k):
    t = lerp(-96, -32, k)
    p = P(t=t, h=t + lerp(4, 16, k), lN=(0, 0, -90), lF=(2, 2, -88), aN=(-4, -4), aF=(-2, -2))
    p = rest(p, "hip", 130, MAT, ("thigh", "shin", "foot", "torso"))
    if k == 0:
        return p
    j = joints(p)
    sh = j["shoulder"]
    # Reach: from straight ahead at shoulder height to the hands on the mat far out.
    tgt = lerp2((sh[0] + 78, sh[1] - 6), (j["ankleN"][0] - 4, MAT - WRIST_UP), k)
    p = reach(p, "aN", tgt, end=lerp(-4, 0, k))
    return reach(p, "aF", (tgt[0] + 3, tgt[1]), end=lerp(-2, 0, k))


add("pancake-gm", floor_entry(tween(_pancake), mat=(86, 330)))


def _hf_lift(k):
    base = P(t=-104, h=-88, lN=(0, 0, -90), lF=(1, 1, -89), aN=(100, 100, 0), aF=(102, 102, 0), lit_sides="N")
    base = rest(base, "hip", 170, MAT, ("thigh", "shin", "foot", "torso"))
    j = joints(base)
    p = dict(base, lN=(lerp(0, -16, k), lerp(0, -16, k), lerp(-90, -106, k)))
    p = reach(p, "aN", (j["hip"][0] - 30, MAT - WRIST_UP), end=0)
    return reach(p, "aF", (j["hip"][0] - 27, MAT - WRIST_UP), end=0)


add("hip-flexor-lift", floor_entry(tween(_hf_lift), mat=(96, 330)))


# ---- standing -----------------------------------------------------------------------------------------

def _hands_on_hips(p):
    j = joints(p)
    hip = j["hip"]
    back = lambda m: -m[0]
    p = reach(p, "aN", (hip[0] - 4, hip[1] - 8), end=60, pick=back)
    return reach(p, "aF", (hip[0] - 7, hip[1] - 9), end=62, pick=back)


def _hip_car(t, lN):
    p = P(t=t, h=t, lN=lN, lF=(90, 90, 0), pin=("ankleF", (196, GROUND - 4)), lit_sides="N")
    return _hands_on_hips(p)


add("hip-car", floor_entry([
    _hip_car(-92, (-16, 74, -6)),
    _hip_car(-90, (28, 150, 70)),
    _hip_car(-84, (118, 192, 110)),
]))


def _wall_back(x0, x1, top=0):
    """Wall seen face-on behind a front-view figure: a light plane with a skirting board."""
    def draw(doc, j):
        doc.add(f'<rect x="{x0}" y="{top}" width="{x1 - x0}" height="{GROUND - top}" fill="#FFFFFF" fill-opacity="0.16"/>'
                f'<rect x="{x0}" y="{GROUND - 9}" width="{x1 - x0}" height="9" fill="#000" fill-opacity="0.16"/>')
    return draw


add("wall-slide", floor_entry([
    P(front=True, lN=(87, 93, 20), lF=(93, 87, 160), aN=(12, -84, -92), aF=(168, -96, -88),
      pin=("ankleN", (212, GROUND - 4))),
    P(front=True, lN=(87, 93, 20), lF=(93, 87, 160), aN=(-48, -68, -72), aF=(228, -112, -108),
      pin=("ankleN", (212, GROUND - 4))),
], back=_wall_back(0, 400)))


def _arc_shoulder(r, a0, a1):
    def draw(doc, j):
        kit.arc(doc, j["shoulder"], r, a0, a1)
    return draw


def _shoulder_car(a):
    return P(t=-90, aN=(a, a, a), aF=(94, 92), lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4)), lit_sides="N")


add("shoulder-car", floor_entry([_shoulder_car(4), _shoulder_car(-92), _shoulder_car(142)],
                                back=_arc_shoulder(98, 132, 362)))


# ---- side-lying (front view: the camera faces the chest, head to the right, near side on the mat) -----------

def _side_lying(arm_f, arm_n=(22, 4, 4), x=196, h=-6, **kw):
    p = P(front=True, t=0, h=h, lN=(176, 192, 196), lF=(174, 190, 194), aN=arm_n, aF=arm_f, **kw)
    base = dict(p, aF=(30, 4, 4))
    pin = rest(base, "hip", x, MAT)["pin"]
    return dict(p, pin=pin)


add("open-book", floor_entry([
    _side_lying((28, 6, 6)),
    _side_lying((-92, -92, -92), h=-24),
    _side_lying((-150, -150, -150), h=-40),
], mat=(66, 346)))



# ---- quadruped ------------------------------------------------------------------------------------------

def _quad(t, h=None, KX=170, thigh=90, **kw):
    """Quadruped with the near knee on the mat at KX."""
    p = P(t=t, h=t + 4 if h is None else h, lN=(thigh, 180, 180), lF=(thigh + 3, 180, 180), **kw)
    return rest(p, "kneeN", KX, MAT, ("thigh", "shin", "foot"))


def _thread(k):
    t = lerp(-20, 20, k)
    p = _quad(t, h=lerp(-40, 34, k), aN=(lerp(-92, 178, k), lerp(-92, 182, k), lerp(-92, 182, k)), aF=(90, 90, 0))
    j = joints(p)
    return reach(p, "aF", (j["hip"][0] + 76, MAT - WRIST_UP), end=0)


def _thread_mid():
    p = _quad(0, h=8, aN=(96, 98, 100), aF=(90, 90, 0))
    j = joints(p)
    p = reach(p, "aN", (j["shoulder"][0] - 22, MAT - WRIST_UP), end=180, pick=lambda m: -m[0])
    return reach(p, "aF", (j["hip"][0] + 76, MAT - WRIST_UP), end=0)


add("thread-needle", floor_entry([_thread(0), _thread_mid(), _thread(1)], mat=(70, 320)))


# ---- foam roller T-spine extension ------------------------------------------------------------------------

ROLLER = (178, GROUND - 12, 12)


def _back_height(p, x):
    """y of the torso's back edge at x."""
    tor = segments(p)["torso"]
    pts = [tor.at(u / 60, -1) for u in range(61)]
    best = min(pts, key=lambda q: abs(q[0] - x))
    return best[1]


def _t_roller(k):
    rx, ry, r = ROLLER
    curl = lerp(0, -9, k)

    def mk(t):
        p = P(t=t, h=lerp(t + 6, 150, k), curl=curl, lN=(-60, 60, -30), lF=(-58, 62, -28))
        return rest(p, "hip", 232, GROUND, ("torso",))
    t = solve(lambda t: _back_height(mk(t), rx) - (ry - r + 1), 182, 230)
    p = mk(t)
    j = joints(p)
    p = reach(p, "lN", (300, GROUND - 4), end=-4, pick=lambda m: -m[1])
    p = reach(p, "lF", (303, GROUND - 4), end=-2, pick=lambda m: -m[1])
    # Hands cradle the back of the head, elbows up.
    hd = j["head"]
    p = reach(p, "aN", (hd[0] + 2, hd[1] + 10), end=lerp(150, 120, k), pick=lambda m: -m[1])
    p = reach(p, "aF", (hd[0] - 1, hd[1] + 11), end=lerp(150, 120, k), pick=lambda m: -m[1])
    return p


def _roller_draw(doc, j):
    kit.foam_roller(doc, ROLLER[:2], ROLLER[2])


add("t-spine-roller", floor_entry(tween(_t_roller), back=_roller_draw))


# ---- wrist CARs -------------------------------------------------------------------------------------------

def _wrist_car(hand):
    p = P(t=-90, aN=(-2, -2, hand), lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4)), lit_sides="N")
    j = joints(p)
    e, w = j["elbowN"], j["wristN"]
    return reach(p, "aF", lerp2(e, w, 0.45), end=-10)


add("wrist-car", floor_entry([_wrist_car(-62), _wrist_car(0), _wrist_car(64)]))



# ---- knee to wall -------------------------------------------------------------------------------------------

WALL_X = 292


def _wall_right(doc, j):
    kit.wall(doc, WALL_X, 16, 30)


def _hands_on_wall(p, y_off=(18, 22), x=WALL_X):
    j = joints(p)
    sh = j["shoulder"]
    p = reach(p, "aN", (x - 5, sh[1] + y_off[0]), end=-80)
    return reach(p, "aF", (x - 5, sh[1] + y_off[1]), end=-80)


def _knee_wall(k):
    AN = (250, GROUND - 4)
    shin = lerp(90, 124, k)
    thigh = lerp(4, 18, k)
    t = lerp(-86, -78, k)
    p = P(t=t, h=t, lN=(thigh, shin, 0), lF=(120, 180, 180), pin=("ankleN", AN), lit_sides="N")
    j = joints(p)
    dy = (GROUND - 9) - j["hip"][1]
    p["lF"] = (180 - math.degrees(math.asin(min(1, dy / F.THIGH))), 180, 180)
    return _hands_on_wall(p)


add("knee-to-wall", floor_entry(tween(_knee_wall), back=_wall_right, boxes=[(WALL_X, 120, WALL_X + 16, GROUND)]))


# ---- Jefferson curl on a box ------------------------------------------------------------------------------

BOX_H = 56


def _jefferson(t, curl, h, thigh, arm=90):
    p = P(t=t, h=h, curl=curl, lN=(thigh, 92 - (90 - thigh) * 0.3, 0), lF=(thigh + 1, 93 - (90 - thigh) * 0.3, 0),
          aN=(arm, arm + 4), aF=(arm + 1, arm + 4), pin=("ankleN", (180, GROUND - BOX_H - 4)))
    return p


def _box_draw(doc, j):
    kit.box(doc, 100, 88, BOX_H)


def _db_front(doc, j):
    kit.dumbbell(doc, kit.grip(j), None, 9.5)


add("jefferson-curl", floor_entry([
    _jefferson(-90, 0, -90, 90, 92),
    _jefferson(-8, 12, 30, 84, 88),
    _jefferson(55, 26, 110, 64, 74),
], back=_box_draw, front=_db_front, boxes=[(100, GROUND - BOX_H, 188, GROUND)]))


# ---- doorway pec stretch ------------------------------------------------------------------------------------

def _pec(k):
    start = P(t=-90, aN=(180, -90, -90), aF=(94, 92), pin=("ankleN", (200, GROUND - 4)), lit_sides="N")
    if k == 0:
        return start
    js = joints(start)
    E = js["elbowN"]
    AF = js["ankleF"]
    AN = (js["ankleN"][0] + 58 * k, GROUND - 4)
    t = lerp(-90, -80, k)

    def mk(a):
        return P(t=t, h=t - 4 * k, aN=(a, -90, -90), aF=(94, 92), pin=("elbowN", E), lit_sides="N")
    a = solve(lambda a: dist(joints(mk(a))["hip"], AF) - (108.5 - 3 * (1 - k)), 180, 215)
    p = mk(a)
    p = reach(p, "lN", AN, end=0)
    return reach(p, "lF", AF, end=0)


def _jamb(doc, j):
    x = joints(_pec(0))["elbowN"][0]
    kit.wall(doc, x - 9, 14, 20)


_PEC_X = joints(_pec(0))["elbowN"][0]
add("pec-stretch", floor_entry(tween(_pec), back=_jamb, avoid=[(_PEC_X - 9, 20, _PEC_X + 5, GROUND)]))



# ---- kneeling lat stretch on a bench ------------------------------------------------------------------------

BENCH_TOP = 220
LAT_E = (262, BENCH_TOP - 5)


def _bench_lat(doc, j):
    kit.flat_bench(doc, 246, 336, BENCH_TOP - 12)


def _lat(k):
    t = lerp(-6, 20, k)
    KX = 150

    def mk(th):
        p = P(t=t, h=t + lerp(0, 30, k), lN=(th, 180, 180), lF=(th + 3, 180, 180))
        return rest(p, "kneeN", KX, GROUND, ("thigh", "shin", "foot"))
    th = solve(lambda th: dist(joints(mk(th))["shoulder"], LAT_E) - 42, 30, 120)
    p = mk(th)
    j = joints(p)
    up = _ang((LAT_E[0] - j["shoulder"][0], LAT_E[1] - j["shoulder"][1]))
    fore = up - 150
    return dict(p, aN=(up, fore, fore - 10), aF=(up + 2, fore + 2, fore - 8))


add("lat-stretch", floor_entry(tween(_lat), back=_bench_lat, boxes=[(246, BENCH_TOP - 12, 336, GROUND)]))


# ---- child's pose reach ------------------------------------------------------------------------------------

def _childs(k):
    KX = 150
    wrist = (KX + 92, MAT - WRIST_UP)
    th = lerp(78, 24, k)

    def mk(t):
        p = P(t=t, h=t + lerp(10, 40, k), lN=(th, 180, 180), lF=(th + 3, 180, 180))
        return rest(p, "kneeN", KX, MAT, ("thigh", "shin", "foot"))
    t = solve(lambda t: dist(joints(mk(t))["shoulder"], wrist) - 79, -40, 40)
    p = mk(t)
    p = reach(p, "aN", wrist, end=0)
    return reach(p, "aF", (wrist[0] + 3, wrist[1]), end=0)


add("childs-pose-reach", floor_entry(tween(_childs), mat=(70, 286)))


# ---- standing, back view ------------------------------------------------------------------------------------

def _cross(k):
    a = lerp(160, 182, k)
    p = P(front="back", t=-90, h=lerp(-90, -84, k), aN=(a, a + 4, a + 4), aF=(96, 90), lN=(88, 90, 20), lF=(92, 90, 160),
          pin=("ankleN", (210, GROUND - 4)), lit_sides="N")
    j = joints(p)
    return reach(p, "aF", lerp2(j["elbowN"], j["wristN"], 0.15), end=-20, pick=lambda m: m[1])


add("cross-body", floor_entry(tween(_cross)))



# ---- sleeper stretch (side-lying, front view) -----------------------------------------------------------------

def _sleeper(k):
    p = _side_lying((40, 10, 10), arm_n=(20, -90, -90), lit_sides="N")
    j = joints(p)
    sh = j["shoulderN"]
    up = math.degrees(math.asin(max(-1, min(1, (MAT - 7 - sh[1]) / F.UPPER_ARM))))
    fore = lerp(-92, -150, k)
    p["aN"] = (up, fore, fore)
    j = joints(p)
    return reach(p, "aF", lerp2(j["wristN"], j["handN"], 0.2), end=lerp(-60, -100, k), pick=lambda m: -m[1])


add("sleeper-stretch", floor_entry(tween(_sleeper), mat=(66, 346)))


# ---- overhead triceps stretch -----------------------------------------------------------------------------------

def _triceps(aN):
    p = P(t=-90, h=-88, aN=aN, lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4)), lit_sides="N")
    j = joints(p)
    return reach(p, "aF", (j["elbowN"][0] + 4, j["elbowN"][1] + 2), end=-80, pick=lambda m: m[0])


add("triceps-stretch", floor_entry([_triceps((-94, -94, -94)), _triceps((-104, -4, -4)), _triceps((-114, 98, 98))]))


# ---- biceps wall stretch -----------------------------------------------------------------------------------------

def _biceps(k):
    start = P(t=-90, aN=(178, 180, 92), aF=(94, 92), pin=("ankleN", (210, GROUND - 4)), lit_sides="N")
    if k == 0:
        return start
    js = joints(start)
    Wp = js["wristN"]
    AF = js["ankleF"]
    AN = (js["ankleN"][0] + 54 * k, GROUND - 4)
    t = lerp(-90, -80, k)

    def mk(a):
        p = P(t=t, h=t - 6 * k, aN=(a, a + 2), aF=(94, 92), lit_sides="N")
        p["pin"] = ("hip", (0, 0))
        j = joints(p)
        off = (j["hip"][0] - j["wristN"][0], j["hip"][1] - j["wristN"][1])
        p["pin"] = ("hip", (Wp[0] + off[0], Wp[1] + off[1]))
        p["aN"] = (a, a + 2, 92)
        return p
    a = solve(lambda a: dist(joints(mk(a))["hip"], AF) - (108.5 - 3 * (1 - k)), 160, 200)
    p = mk(a)
    p = reach(p, "lN", AN, end=0)
    return reach(p, "lF", AF, end=0)


def _wall_left(doc, j):
    x = joints(_biceps(0))["wristN"][0]
    kit.wall(doc, x - 22, 16, 40)


_BIC_X = joints(_biceps(0))["wristN"][0]
add("biceps-wall", floor_entry(tween(_biceps), back=_wall_left, avoid=[(_BIC_X - 22, 40, _BIC_X - 6, GROUND)]))



# ---- forearm stretches ---------------------------------------------------------------------------------------

def _forearm(hand, bend):
    p = P(t=-90, aN=(-2, -2, hand), lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4)), lit_sides="N")
    j = joints(p)
    w = j["wristN"]
    a = math.radians(hand)
    # Far palm flat on the front of the near hand, pressing it back.
    tgt = (w[0] + 7 * math.sin(a) * (-1 if hand < 0 else 1) + 2, w[1] + 1)
    return reach(p, "aF", tgt, end=hand + bend)


add("forearm-flexor", floor_entry([_forearm(-20, 10), _forearm(-50, 0), _forearm(-78, -10)]))
add("forearm-extensor", floor_entry([_forearm(20, -10), _forearm(52, 0), _forearm(82, 10)]))


# ---- half-kneeling hip flexor stretch ---------------------------------------------------------------------------

def _half_kneel(k):
    KX = 150
    p = P(t=lerp(-88, -94, k), h=lerp(-88, -92, k), lN=(lerp(96, 124, k), 180, 180),
          aN=(lerp(92, -100, k),) * 2 + ((lerp(92, -100, k)),), aF=(80, 60), lit_sides="N")
    p = rest(p, "kneeN", KX, MAT, ("shinN", "footN", "thighN"))
    p = reach(p, "lF", (KX + 62, MAT - 4), end=0)
    j = joints(p)
    return reach(p, "aF", (j["kneeF"][0] - 2, j["kneeF"][1] - 12), end=10)


add("half-kneeling-hf", floor_entry([_half_kneel(0), _half_kneel(0.5), _half_kneel(1)], mat=(70, 260)))



# ---- supine hamstring stretch with a band --------------------------------------------------------------------

def _ham(k):
    raise_ = lerp(56, 96, k)
    p = P(t=180, h=182, lN=(-raise_, -raise_, -raise_ - 90), lF=(-2, -2, -92), aN=(-60, -20), aF=(-58, -18),
          lit_sides="N")
    p = rest(p, "hip", 210, MAT, ("torso", "thighF", "shinF", "head"))
    j = joints(p)
    # Band from the sole (just past the ball of the foot) to both hands.
    a, t_ = j["ankleN"], j["toeN"]
    sole = lerp2(a, t_, 0.6)
    sh = j["shoulder"]
    d = (sole[0] - sh[0], sole[1] - sh[1])
    L = math.hypot(*d)
    hand = (sh[0] + d[0] / L * 64, sh[1] + d[1] / L * 64)
    p = reach(p, "aN", hand, end=_ang(d), pick=lambda m: -m[1])
    return reach(p, "aF", (hand[0] - 1, hand[1] + 1), end=_ang(d), pick=lambda m: -m[1])


def _ham_band(doc, j):
    sole = lerp2(j["ankleN"], j["toeN"], 0.6)
    n = (math.cos(math.radians(_ang((j["toeN"][0] - j["ankleN"][0], j["toeN"][1] - j["ankleN"][1])) - 90)),
         math.sin(math.radians(_ang((j["toeN"][0] - j["ankleN"][0], j["toeN"][1] - j["ankleN"][1])) - 90)))
    tip = (sole[0] + n[0] * 4, sole[1] + n[1] * 4)
    kit.band(doc, kit.grip(j), tip)


add("hamstring-stretch", floor_entry(tween(_ham), mat=(50, 300), front=_ham_band))


# ---- pigeon -------------------------------------------------------------------------------------------------------

def _pigeon(k):
    t = lerp(-80, -12, k)
    p = P(t=t, h=lerp(-84, -6, k), lN=(24, 176, 182), lF=(172, 176, 180), aN=(90, 90, 0), aF=(90, 90, 0))
    p = rest(p, "hip", 180, MAT, ("thigh", "shin", "foot"))
    j = joints(p)
    sh = j["shoulder"]
    if k < 0.75:
        tgt = (lerp(sh[0] + 6, sh[0] + 40, k / 0.75), MAT - WRIST_UP)
        p = reach(p, "aN", tgt, end=0)
        return reach(p, "aF", (tgt[0] + 3, tgt[1]), end=0)
    # Folded: forearms on the mat.
    e = (sh[0] + 4, MAT - 6)
    p = reach(p, "aN", (e[0] + 38, MAT - 5), end=0)
    return reach(p, "aF", (e[0] + 41, MAT - 5), end=0)


add("pigeon", floor_entry(tween(_pigeon), mat=(60, 320)))


# ---- supine figure-4 --------------------------------------------------------------------------------------------

def _fig4(k):
    th = lerp(-52, -88, k)
    p = P(t=180, h=182, lF=(th, th + 100, th + 10), lit_sides="N")
    p = rest(p, "hip", 200, MAT, ("torso", "head"))
    j = joints(p)
    kf = j["kneeF"]
    # Near ankle crossed over the far knee, knee open towards the camera.
    p = reach(p, "lN", (kf[0] - 6, kf[1] - 8), end=-80, pick=lambda m: m[0] - m[1] * 0.2)
    # Hands behind the far thigh, pulling it in.
    tgt = lerp2(j["hip"], kf, 0.75)
    p = reach(p, "aN", (tgt[0] + 2, tgt[1] + 4), end=_ang((kf[0] - j["hip"][0], kf[1] - j["hip"][1])) + 90, pick=lambda m: -m[1])
    return reach(p, "aF", (tgt[0] - 2, tgt[1] + 6), end=_ang((kf[0] - j["hip"][0], kf[1] - j["hip"][1])) + 90, pick=lambda m: -m[1])


add("figure-4", floor_entry(tween(_fig4), mat=(70, 300)))



# ---- butterfly (front view, seated) ------------------------------------------------------------------------------

def _butterfly(k):
    CX = 200
    p = P(front=True, t=-90, h=-90, lN=(-20, 150, 180), lF=(200, 30, 0))
    p = rest(p, "hip", CX, MAT, ("torso", "thigh"))
    fx = lerp(34, 18, k)
    p = reach(p, "lN", (CX + fx, MAT - 5), end=180, pick=lambda m: m[0] - m[1] * 0.3)
    p = reach(p, "lF", (CX - fx, MAT - 5), end=0, pick=lambda m: -m[0] - m[1] * 0.3)
    j = joints(p)
    # Hands around the feet.
    p = reach(p, "aN", (j["ankleN"][0] - 2, j["ankleN"][1] - 6), end=100, pick=_out(CX, 1))
    return reach(p, "aF", (j["ankleF"][0] + 2, j["ankleF"][1] - 6), end=80, pick=_out(CX, -1))


add("butterfly", floor_entry(tween(_butterfly), mat=(100, 300)))


# ---- frog stretch (forearms) ----------------------------------------------------------------------------------------

FROG_E = (232, MAT - 7)


def _frog_stretch(k):
    KX = 160
    th = lerp(90, 70, k)

    def mk(t):
        p = P(t=t, h=t - 10, lN=(th, 180, 180), lF=(th + 4, 180, 180))
        return rest(p, "kneeN", KX, MAT, ("thigh", "shin", "foot"))
    t = solve(lambda t: dist(joints(mk(t))["shoulder"], FROG_E) - 41, -30, 40)
    p = mk(t)
    j = joints(p)
    up = _ang((FROG_E[0] - j["shoulder"][0], FROG_E[1] - j["shoulder"][1]))
    return dict(p, aN=(up, 0, 0), aF=(up + 2, 2, 0))


add("frog-stretch", floor_entry(tween(_frog_stretch), mat=(80, 300)))


# ---- calf stretch at the wall --------------------------------------------------------------------------------------

def _calf_base(k):
    t = lerp(-68, -76, k)
    p = P(t=t, h=t + 4, lN=(lerp(112, 96, k), lerp(112, 128, k), 0), pin=("ankleN", (160, GROUND - 4)), lit_sides="N")
    return reach(p, "lF", (226, GROUND - 4), end=0)


CALF_WALL = joints(_calf_base(0))["shoulder"][0] + 66


def _calf(k):
    return _hands_on_wall(_calf_base(k), (16, 20), CALF_WALL)


def _calf_wall_draw(doc, j):
    kit.wall(doc, CALF_WALL, 16, 30)


add("calf-wall", floor_entry(tween(_calf), back=_calf_wall_draw, boxes=[(CALF_WALL, 120, CALF_WALL + 16, GROUND)]))



# ---- supine twist ---------------------------------------------------------------------------------------------------

def _twist(k):
    """Supine spinal twist: far leg long, near knee drawn up and pulled across by the far hand, shoulders flat."""
    p = P(t=180, h=lerp(182, 172, k), lF=(-1, -1, -91), lN=(-1, -1, -91), aN=(4, 2, 2), aF=(6, 4, 4), lit_sides="N")
    p = rest(p, "hip", 196, MAT, ("torso", "head", "thighF", "shinF"))
    if k == 0:
        return p
    j = joints(p)
    hip = j["hip"]
    foot = (hip[0] + lerp(110, 60, k), MAT - 5)
    p = reach(p, "lN", foot, end=lerp(-90, 10, k), pick=lambda m: -m[1])
    j = joints(p)
    kn = j["kneeN"]
    return reach(p, "aF", (kn[0] - 6, kn[1] - 2), end=lerp(-20, -60, k), pick=lambda m: -m[1])


add("supine-twist", floor_entry(tween(_twist), mat=(60, 330)))


# ---- sphinx -----------------------------------------------------------------------------------------------------------

def _sphinx(k):
    base = P(t=-2, h=0, lN=(180, 180, 180), lF=(181, 181, 181))
    pin = rest(base, "hip", 186, MAT, ("thigh", "shin", "torso"))["pin"]
    t = lerp(-3, -24, k)
    p = P(t=t, h=lerp(4, -30, k), lN=(180, 180, 180), lF=(181, 181, 181), pin=pin)
    sh = joints(p)["shoulder"]
    dy = (MAT - 6) - sh[1]
    a = math.degrees(math.asin(max(-1, min(1, dy / F.UPPER_ARM))))
    return dict(p, aN=(a, 0, 0), aF=(a + 2, 1, 0))


add("sphinx", floor_entry(tween(_sphinx), mat=(64, 340)))


# ---- side bend (back view) ---------------------------------------------------------------------------------------------

def _side_bend(k):
    t = lerp(-90, -112, k)
    up = lerp(-92, -146, k)
    return P(front="back", t=t, h=t - lerp(0, 8, k), lN=(88, 90, 20), lF=(92, 90, 160),
             aN=(up, up - lerp(0, 18, k), up - lerp(0, 22, k)), aF=(lerp(100, 116, k), lerp(96, 110, k)),
             pin=("ankleN", (214, GROUND - 4)))


add("side-bend", floor_entry(tween(_side_bend)))



# ---- behind-the-back clasp -------------------------------------------------------------------------------------------

def _clasp(k):
    t = lerp(-90, -96, k)
    a = lerp(104, 150, k)
    f = lerp(98, 150, k)
    return P(t=t, h=t + lerp(0, -8, k), aN=(a, f, f), aF=(a + 2, f + 2, f + 2), lF=(92, 88, 0),
             pin=("ankleN", (200, GROUND - 4)))


add("behind-back-clasp", floor_entry(tween(_clasp)))


# ---- upper-trap stretch (back view) -------------------------------------------------------------------------------------

def _trap(k):
    h = lerp(-90, -130, k)
    return P(front="back", t=-90, h=h, lN=(88, 90, 20), lF=(92, 90, 160), aN=(lerp(92, 78, k), lerp(90, 76, k)),
             aF=(98, 94), pin=("ankleN", (214, GROUND - 4)))


add("upper-trap", floor_entry(tween(_trap)))


# ---- side-delt stretch behind the back (back view) --------------------------------------------------------------------------

def _side_delt(k):
    up = lerp(102, 122, k)
    fore = lerp(150, 176, k)
    p = P(front="back", t=-90, h=lerp(-90, -116, k), lN=(88, 90, 20), lF=(92, 90, 160), aN=(up, fore, fore),
          aF=(70, 20), pin=("ankleN", (214, GROUND - 4)), lit_sides="N")
    j = joints(p)
    return reach(p, "aF", lerp2(j["wristN"], j["handN"], 0.1), end=20, pick=lambda m: m[1])


add("side-delt-stretch", floor_entry(tween(_side_delt)))


# ---- 90/90 breathing (supine, calves on a bench) ----------------------------------------------------------------------------

BREATH_BENCH = 218


def _breath(k):
    p = P(t=180, h=lerp(180, 182, k), curl=lerp(-3, 2, k), lN=(-90, 0, -80), lF=(-88, 2, -78))
    p = rest(p, "hip", 200, MAT, ("torso", "head"))
    j = joints(p)
    # Near hand on the belly, far hand on the chest.
    tor = segments(p)["torso"]
    belly = tor.at(0.35, 1.25)
    chest = tor.at(0.78, 1.25)
    p = reach(p, "aN", belly, end=0, pick=lambda m: -m[1])
    return reach(p, "aF", chest, end=0, pick=lambda m: -m[1])


def _breath_bench(doc, j):
    y = joints(_breath(0))["ankleN"][1] + 7
    kit.flat_bench(doc, 236, 330, y)


add("breathing", floor_entry(tween(_breath), mat=(60, 236), back=_breath_bench, boxes=[(236, 200, 330, GROUND)]))
