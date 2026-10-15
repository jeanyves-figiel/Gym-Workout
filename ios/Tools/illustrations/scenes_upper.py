"""Upper-body scenes for the realistic exercise art (#170): presses, rows, pulls, raises.

Same conventions as scenes.py: angles 0 = right, 90 = down; the figure faces right in side view. Poses are
built in absolute view-box coordinates: B() pins the hip and solves arms / legs with a two-link IK so the
hands land exactly on the bar, handle or bench and the feet on the floor. Static equipment is drawn in
absolute coordinates; held equipment follows the hands (kit.grip).
"""
import math

import art
import kit
from art import GROUND
from poses import P

F = art.F
TORSO, UPPER, FORE, HAND = F.TORSO, F.UPPER_ARM, F.FOREARM, F.HAND
THIGH, SHIN = F.THIGH, F.SHIN
FLOOR_Y = GROUND - 4  # ankle height of a standing figure
SW = art.PROFILES["torso"][-1][1] * 1.45 * 0.9  # shoulder offset in front / back view
HW = 9.0  # hip offset in front / back view


# ---- geometry helpers --------------------------------------------------------------------------

def deg(v):
    return math.degrees(math.atan2(v[1], v[0]))


def lerp(a, b, k):
    return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)


def ik(a, target, l1, l2, bend=1):
    """Two-link chain from a to target: (first angle, second angle). bend +1 = joint clockwise of a→target."""
    dx, dy = target[0] - a[0], target[1] - a[1]
    d = max(abs(l1 - l2) + 0.01, min(math.hypot(dx, dy), l1 + l2 - 0.01))
    base = math.degrees(math.atan2(dy, dx))
    al = math.degrees(math.acos(max(-1, min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))))
    u = base + bend * al
    e = art.ang_pt(a, u, l1)
    return u, deg((target[0] - e[0], target[1] - e[1]))


class G:
    """Limb goal: the hand grip (or wrist / ankle) at p, joint bent to side `bend`, optional end angle."""

    def __init__(self, p, bend=1, end=None, wrist=False):
        self.p, self.bend, self.end, self.wrist = p, bend, end, wrist


def near(a, ref):
    """Angle a shifted by whole turns to be closest to ref (smooth interpolation)."""
    while a - ref > 180:
        a -= 360
    while a - ref < -180:
        a += 360
    return a


def B(hip, t, aN=None, aF=None, lN=None, lF=None, **kw):
    """Pose with the hip pinned at `hip`; limbs given as angle tuples or G goals (solved by IK)."""
    sh = art.ang_pt(hip, t, TORSO)
    view = kw.get("front")
    tv = art.norm(art.sub(sh, hip))
    n = (-tv[1], tv[0])
    out = {}
    for key, spec in (("aN", aN), ("aF", aF), ("lN", lN), ("lF", lF)):
        if spec is None:
            continue
        if not isinstance(spec, G):
            out[key] = spec
            continue
        s = 1 if key[1] == "N" else -1
        arm = key[0] == "a"
        root = sh if arm else hip
        if view:
            root = art.add(root, n, s * (SW if arm else HW))
        if arm:
            l2 = FORE if spec.wrist else FORE + HAND / 2
        else:
            l2 = SHIN
        u, f = ik(root, spec.p, UPPER if arm else THIGH, l2, spec.bend)
        if spec.end is not None:
            out[key] = (u, f, spec.end)
        else:
            out[key] = (u, f)
    kw = dict(kw)
    return P(t=t, pin=("hip", hip), **out, **kw)


def place(pose):
    j = F.place(pose)
    if art.view_of(pose) != "side":
        art.frontal(j)
    return j


PRESS_KS = (0, 0.68, 1)  # middle frame nearer the bottom: elbows read better


def seq(fn, ks=(0, 0.5, 1)):
    return [fn(k) for k in ks]


# ---- framing -------------------------------------------------------------------------------------

def body_points(j):
    """(point, radius) samples covering the drawn body."""
    pts = []
    hd = art.norm(art.sub(j["head"], j["neck"]))
    pts.append((art.add(j["neck"], hd, 16), 16))
    pts.append((j["neck"], 8))
    for a, b, r in (("hip", "shoulder", 16),):
        for i in range(5):
            pts.append((lerp(j[a], j[b], i / 4), r))
    for s in "NF":
        for a, b, r in (("shoulder", "elbow", 9), ("elbow", "wrist", 6), ("wrist", "hand", 5),
                        ("hip", "knee", 13), ("knee", "ankle", 8), ("ankle", "toe", 5)):
            pa = j.get(a + s) or j[a]
            for i in range(4):
                pts.append((lerp(pa, j[b + s], i / 3), r))
    return pts


def inset_rect(view, corner):
    x, y, w = view
    h = w * 0.75
    ph = h * 0.36
    s = ph / 430
    pw = 410 * s + 8
    px = x + 6 if corner[1] == "l" else x + w - pw - 6
    py = y + 6 if corner[0] == "t" else y + h - ph - 6
    return px, py, px + pw, py + ph


def fit(poses, boxes=(), held=None, m=8, corner=None, floor=True):
    """Tight 4:3 view around every frame + the equipment boxes; picks a free corner for the inset."""
    fr = art.frames(poses)
    pts = []
    for p in fr:
        j = place(p)
        pts += body_points(j)
        if held:
            pts += held(j)
    xs0 = [p[0] - r for p, r in pts] + [b[0] for b in boxes]
    xs1 = [p[0] + r for p, r in pts] + [b[2] for b in boxes]
    ys0 = [p[1] - r for p, r in pts] + [b[1] for b in boxes]
    ys1 = [p[1] + r for p, r in pts] + [b[3] for b in boxes]
    x0, x1, y0, y1 = min(xs0) - m, max(xs1) + m, min(ys0) - m, max(ys1) + m
    grounded = floor and y1 >= GROUND - 2
    if grounded:
        y1 = GROUND + 5
    w, h = x1 - x0, y1 - y0
    if w < h * 4 / 3:
        x0 -= (h * 4 / 3 - w) / 2
        w = h * 4 / 3
    else:
        hh = w * 0.75
        if grounded:
            y0 = y1 - hh
        else:
            y0 -= (hh - h) / 2
    base = (x0, y0, w)

    def score(view, c):
        rx0, ry0, rx1, ry1 = inset_rect(view, c)
        sc = 0
        for p, r in pts:
            if rx0 - r + 2 < p[0] < rx1 + r - 2 and ry0 - r + 2 < p[1] < ry1 + r - 2:
                sc += 1
        for b in boxes:
            ox = max(0, min(rx1, b[2]) - max(rx0, b[0]))
            oy = max(0, min(ry1, b[3]) - max(ry0, b[1]))
            sc += ox * oy / 40
        return sc

    def grown(g, side):
        x, y, ww = base
        nw = ww * (1 + g)
        dx = {"c": (nw - ww) / 2, "l": nw - ww, "r": 0}[side]
        dy = (nw - ww) * 0.75 * (1 if grounded else 0.5)
        return (round(x - dx, 1), round(y - dy, 1), round(nw, 1))

    corners = (corner,) if corner else ("tl", "tr", "bl", "br")
    best = None
    cap = max(base[2], 392)
    for g in [i * 0.03 for i in range(21)]:
        if base[2] * (1 + g) > cap:
            break
        for side in ("c", "l", "r"):
            v = grown(g, side)
            for c in corners:
                sc = score(v, c)
                if best is None or sc < best[0] - 0.01:
                    best = (sc, v, c)
        if best[0] < 0.5:
            break
    _, view, corner = best
    if view[2] <= 400:  # keep the crop on the canvas where the floor is drawn
        view = (round(min(max(view[0], 0), 400 - view[2]), 1), view[1], view[2])
    out = []
    for p in poses:
        p = dict(p)
        p["inset"] = corner
        out.append(p)
    return out, view


def S(fn, poses, boxes=(), held=None, **kw):
    ps, view = fit(poses, boxes, held, **kw)
    return (fn, ps, view)


def held_at(side="N", r=12):
    return lambda j: [(kit.grip(j, side), r)]


# ---- shared equipment ----------------------------------------------------------------------------

def floor(doc, cx=200, rx=110):
    kit.floor(doc, cx, rx, x0=-120, x1=520)


def bench_rack(doc, x, hook_y, top=None):
    """Bench-press uprights behind the head: post with a J-hook pointing right."""
    top = top or hook_y - 30
    art.tube(doc, (x, GROUND - 2), (x, top), 10, "butt")
    for y in range(int(top) + 10, GROUND - 16, 14):
        doc.add(f'<circle cx="{x}" cy="{y}" r="1.5" fill="#0C0E10"/>')
    art.tube(doc, (x, hook_y), (x + 15, hook_y), 6)
    art.tube(doc, (x + 15, hook_y), (x + 17, hook_y - 9), 4)
    kit.feet(doc, x - 30, x + 30)


def bar_end(doc, c, r=24):
    kit.barbell(doc, c, r)


def tower(doc, x, pulley_y, lift=0, side="L", w=34, top=24, plates=12):
    """Cable column; side "L" = pulley on its left face (figure to the left), "R" = mirrored."""
    if side == "L":
        if top == 24:
            return kit.cable_tower(doc, x, pulley_y, lift, w, top)
        art.tube(doc, (x - 4, GROUND - 2), (x - 4, top), 9)
        art.shroud(doc, x + 2, top + 30, GROUND - 4, w + 8)
        st = art.stack(doc, x + 6, top + 44, GROUND - 4, w, plates, lift)
        art.tube(doc, (x - 8, top), (x + w + 14, top), 8)
        art.pulley(doc, (st[0], top + 7), 5.5)
        art.cable(doc, [(st[0] + 5.5, top + 7), st])
        p = (x - 12, pulley_y)
        art.tube(doc, (x - 4, pulley_y), (p[0] + 2, pulley_y), 5)
        art.pulley(doc, p, 6)
        return p
    # Mirror: stack in the shroud, column on the right, pulley on the right face.
    art.tube(doc, (x + 4, GROUND - 2), (x + 4, top), 9)
    art.shroud(doc, x - w - 10, top + 30, GROUND - 4, w + 8)
    st = art.stack(doc, x - w - 6, top + 44, GROUND - 4, w, plates, lift)
    art.tube(doc, (x - w - 14, top), (x + 8, top), 8)
    art.pulley(doc, (st[0], top + 7), 5.5)
    art.cable(doc, [(st[0] - 5.5, top + 7), st])
    p = (x + 12, pulley_y)
    art.tube(doc, (x + 4, pulley_y), (p[0] - 2, pulley_y), 5)
    art.pulley(doc, p, 6)
    return p


# ---- bench press family --------------------------------------------------------------------------

BENCH_TOP = 212
BP_HIP = (236, BENCH_TOP - 17)
BP_SH = art.ang_pt(BP_HIP, 180, TORSO)


def lying_bench(hip, t, grip_n, grip_f, bend=1, foot_x=None, **kw):
    foot_x = foot_x or hip[0] + 68
    return B(hip, t, aN=G(grip_n, bend), aF=G(grip_f, bend), lN=G((foot_x, FLOOR_Y), -1, end=0),
             lF=G((foot_x - 8, FLOOR_Y), -1, end=0), h=180, **kw)


def bench_press_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 200, 120)
        bench_rack(doc, 128, BP_SH[1] - 76)
        kit.flat_bench(doc, 104, 254, BENCH_TOP)
    else:
        bar_end(doc, g, 23)


def bench_poses(top_dx=2, bot=(24, -20), elbow=1):
    top = (BP_SH[0] + top_dx, BP_SH[1] - 81)
    bottom = (BP_SH[0] + bot[0], BP_SH[1] + bot[1])

    def f(k):
        g = lerp(top, bottom, k)
        return lying_bench(BP_HIP, 180, g, (g[0] - 3, g[1] - 1), elbow, curl=-2)
    return seq(f, PRESS_KS)


def db_bench_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 120)
        kit.flat_bench(doc, 104, 254, BENCH_TOP)
        kit.dumbbell(doc, kit.grip(j, "F"), r=9)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


def db_bench_poses():
    top = (BP_SH[0] + 4, BP_SH[1] - 80)
    bottom = (BP_SH[0] + 14, BP_SH[1] - 22)

    def f(k):
        g = lerp(top, bottom, k)
        return lying_bench(BP_HIP, 180, g, (g[0] - 5, g[1] - 2), 1, curl=-2)
    return seq(f, PRESS_KS)


# ---- incline / upright bench ---------------------------------------------------------------------

def bench_hip(pivot, ang, seat_top, back=15, t=12):
    """Hip of a figure sitting on the seat with the back flat on a backrest through `pivot` at `ang`."""
    d = (math.cos(math.radians(ang)), math.sin(math.radians(ang)))
    n = (-d[1], d[0])
    base = art.add(pivot, n, t + back)
    s = (seat_top - 16 - base[1]) / d[1]
    return art.add(base, d, s)


SEAT_X0, SEAT_X1, SEAT_TOP = 150, 206, 208


def adj_bench(back_ang, back_len=100):
    pivot = (SEAT_X0 + 4, SEAT_TOP + 12)
    hip = bench_hip(pivot, back_ang, SEAT_TOP)
    return pivot, hip, art.ang_pt(hip, back_ang, TORSO)


def chest_pt(hip, t, u=0.8, out=16):
    d = (math.cos(math.radians(t)), math.sin(math.radians(t)))
    return art.add(art.add(hip, d, u * TORSO), (-d[1], d[0]), out)


def seated(hip, t, gn, gf, bend=1, foot_dx=66, **kw):
    return B(hip, t, aN=G(gn, bend), aF=G(gf, bend), lN=G((hip[0] + foot_dx, FLOOR_Y), -1, end=0),
             lF=G((hip[0] + foot_dx - 8, FLOOR_Y), -1, end=0), **kw)


def make_bench_scene(back_ang, weight="db", rack_x=None, hook=None, back_len=100):
    def scene(doc, j, layer):
        if layer == "back":
            floor(doc, 190, 120)
            if rack_x:
                bench_rack(doc, rack_x, hook)
            kit.incline_bench(doc, SEAT_X0, SEAT_X1, SEAT_TOP, back_len, back_ang)
            if weight == "db":
                kit.dumbbell(doc, kit.grip(j, "F"), r=9)
        elif weight == "db":
            kit.dumbbell(doc, kit.grip(j), r=10)
        else:
            bar_end(doc, kit.grip(j), 23)
    return scene


INC = -150  # 30 degree incline
INC_PIVOT, INC_HIP, INC_SH = adj_bench(INC)


def incline_poses(bottom_u=0.86, bottom_out=24, top_dx=2):
    top = (INC_SH[0] + top_dx, INC_SH[1] - 80)
    bottom = chest_pt(INC_HIP, INC, bottom_u, bottom_out)

    def f(k):
        g = lerp(top, bottom, k)
        return seated(INC_HIP, INC, g, (g[0] - 4, g[1] - 2), 1, h=-160)
    return seq(f, PRESS_KS)


UP = -100  # near-upright backrest
UP_PIVOT, UP_HIP, UP_SH = adj_bench(UP, 110)


def seated_press_poses():
    bottom = (UP_SH[0] + 16, UP_SH[1] - 26)
    top = (UP_SH[0] + 6, UP_SH[1] - 81)

    def f(k):
        g = lerp(bottom, top, k)
        return seated(UP_HIP, UP, g, (g[0] - 4, g[1] - 2), 1, h=-96)
    return seq(f, (0, 0.45, 1))


def arnold_poses():
    s = UP_SH
    gs = [(s[0] + 32, s[1] - 24), (s[0] + 16, s[1] - 26), (s[0] + 6, s[1] - 81)]
    return [seated(UP_HIP, UP, g, (g[0] - 4, g[1] - 2), 1, h=-96) for g in gs]


# ---- standing presses ----------------------------------------------------------------------------

ST_HIP = (200, FLOOR_Y - THIGH - SHIN + 1)


def standing(hip, t, gn, gf, bend=1, stance=(0, 0), **kw):
    return B(hip, t, aN=G(gn, bend), aF=G(gf, bend),
             lN=G((hip[0] + stance[0], FLOOR_Y), -1, end=0), lF=G((hip[0] + stance[1], FLOOR_Y), -1, end=0), **kw)


def press_poses(rack=(18, -4), top=(-2, -81), hip=ST_HIP, t=-90, far=(-4, -2), ks=(0, 0.45, 1)):
    sh = art.ang_pt(hip, t, TORSO)
    a, b = (sh[0] + rack[0], sh[1] + rack[1]), (sh[0] + top[0], sh[1] + top[1])

    def f(k):
        g = lerp(a, b, k)
        return standing(hip, t, g, (g[0] + far[0], g[1] + far[1]), 1, stance=(1, -3),
                        h=-96 if k < 0.9 else -88)
    return seq(f, ks)


def db_press_poses(hip=ST_HIP, t=-90, far=(-4, -2)):
    """Standing dumbbell press: the bells start in front of the shoulders (not on the face) and travel up in
    front of the face before finishing overhead."""
    sh = art.ang_pt(hip, t, TORSO)
    gs = [(sh[0] + 25, sh[1] - 2), (sh[0] + 16, sh[1] - 55), (sh[0] - 1, sh[1] - 81)]
    return [standing(hip, t, g, (g[0] + far[0], g[1] + far[1]), 1, stance=(1, -3), h=-96 if i < 2 else -88)
            for i, g in enumerate(gs)]


def ohp_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 70)
        kit.rack(doc, 132, hook_y=ST_HIP[1] - TORSO - 2, safety_y=None, top=40)
    else:
        bar_end(doc, kit.grip(j), 20)


def db_press_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 50)
        kit.dumbbell(doc, kit.grip(j, "F"), r=9)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


def band_ohp_poses():
    legs = dict(lN=(80, 92, 12), lF=(100, 88, 168))
    return [P(t=-90, front=True, aN=(36, -88), aF=(144, -92), pin=("hip", FR_HIP), **legs),
            P(t=-90, front=True, aN=(-22, -86), aF=(202, -94), pin=("hip", FR_HIP), **legs),
            P(t=-90, front=True, aN=(-78, -84), aF=(258, -96), pin=("hip", FR_HIP), **legs)]


def band_press_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 50)
    else:
        for s in "NF":
            g = kit.grip(j, s)
            kit.band(doc, (j["ankle" + s][0], GROUND - 2), g)
            kit.handle(doc, g)


# ---- landmine press ------------------------------------------------------------------------------

def circle_x(c0, r0, c1, r1, pick=1):
    """Intersection of two circles; pick +1 / -1 chooses the side."""
    dx, dy = c1[0] - c0[0], c1[1] - c0[1]
    d = math.hypot(dx, dy)
    a = (r0 * r0 - r1 * r1 + d * d) / (2 * d)
    h = math.sqrt(max(0, r0 * r0 - a * a))
    m = (c0[0] + a * dx / d, c0[1] + a * dy / d)
    return (m[0] - pick * h * dy / d, m[1] + pick * h * dx / d)


LM_HIP = (176, GROUND - 8 - THIGH)
LM_ANCHOR = (352, GROUND - 4)


def landmine_poses():
    out = []
    for k, t in ((0, -90), (0.5, -86), (1, -82)):
        sh = art.ang_pt(LM_HIP, t, TORSO)
        start = (sh[0] + 16, sh[1] + 2)
        if k == 0:
            g = start
        else:
            g = circle_x(LM_ANCHOR, LANDMINE_L, sh, 40 + 40 * k, 1)
        out.append(B(LM_HIP, t, aN=G(g, 1), aF=(96, 84),
                     lN=(90, 180, 180), lF=G((LM_HIP[0] + 60, FLOOR_Y), -1, end=0), lit_sides="N", h=-92))
    return out


LANDMINE_L = kit.dist(LM_ANCHOR, (art.ang_pt(LM_HIP, -90, TORSO)[0] + 16, art.ang_pt(LM_HIP, -90, TORSO)[1] + 2))


def landmine_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 230, 140)
        kit.mat(doc, 120, 240)
    else:
        kit.landmine(doc, kit.grip(j), LM_ANCHOR)


# ---- chest press machine -------------------------------------------------------------------------

CP_SEAT = 204
CP_HIP = (176, CP_SEAT - 16)
CP_T = -96
CP_SH = art.ang_pt(CP_HIP, CP_T, TORSO)
CP_START = (CP_SH[0] + 26, CP_SH[1] + 18)
# Lever pivot above the middle of the press path (#QA): the long lever swings the handles almost level at
# chest height, a horizontal press rather than an incline.
CP_PIVOT = (CP_SH[0] + 50, 46)
CP_R = kit.dist(CP_PIVOT, CP_START)


def chest_press_poses():
    end = circle_x(CP_PIVOT, CP_R, CP_SH, 79, -1)
    gs = [CP_START, circle_x(CP_PIVOT, CP_R, CP_SH, 56, -1), end]
    return [seated(CP_HIP, CP_T, g, (g[0] - 3, g[1] - 1), 1, foot_dx=62, h=-92) for g in gs]


def back_pad(doc, hip, t, u0=0.12, u1=1.0, back=15, th=12):
    d = (math.cos(math.radians(t)), math.sin(math.radians(t)))
    n = (-d[1], d[0])
    a = art.add(art.add(hip, d, u1 * TORSO), n, -(back + th))
    b = art.add(art.add(hip, d, u0 * TORSO), n, -(back + th))
    art.pad(doc, a, b, th)
    return a, b


def chest_press_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 170, 120)
        # Weight stack behind the backrest.
        lift = max(0, (g[0] - CP_START[0]) * 0.32)
        art.tube(doc, (46, GROUND - 2), (46, 36), 10)
        art.shroud(doc, 52, 66, GROUND - 4, 44)
        top = art.stack(doc, 57, 80, GROUND - 4, 34, 12, lift)
        art.tube(doc, (40, 36), (CP_PIVOT[0] + 8, 36), 9)
        art.pulley(doc, (top[0], 44), 5.5)
        art.cable(doc, [(top[0] + 5.5, 44), top])
        # Cable along the boom onto the lever's cam at the pivot.
        art.cable(doc, [(top[0], 38.5), (CP_PIVOT[0], 38.5)])
        # Backrest frame + seat.
        a, b = back_pad(doc, CP_HIP, CP_T, 0.14, 1.0)
        art.tube(doc, art.add(b, (-4, 4)), (126, GROUND - 2), 7)
        art.tube(doc, art.add(a, (-6, 0)), (122, 36), 6)
        art.tube(doc, (CP_HIP[0] + 2, CP_SEAT + 12), (CP_HIP[0] + 2, GROUND - 2), 8, "butt")
        kit.feet(doc, 34, 236)
        art.pad(doc, (CP_HIP[0] - 34, CP_SEAT + 12), (CP_HIP[0] + 36, CP_SEAT + 12), 12)
        # Lever arms (pivot overhead, in front of the face) run beside the body to the handles.
        art.tube(doc, CP_PIVOT, kit.grip(j, "F"), 6)
        art.tube(doc, CP_PIVOT, g, 7)
        art.tube(doc, (CP_PIVOT[0], 34), CP_PIVOT, 8)
        art.pulley(doc, CP_PIVOT, 7.5)
    else:
        art.tube(doc, (g[0], g[1] - 9), (g[0], g[1] + 9), 6)
        doc.add(f'<rect x="{g[0] - 3.6:.1f}" y="{g[1] - 7:.1f}" width="7.2" height="14" rx="3.2" fill="#1B1D20"/>')


# ---- bent-over rows ------------------------------------------------------------------------------

ROW_ANKLE = (206, FLOOR_Y)


def hinge_poses(t=-40, hip=(166, 164), end_u=0.5, end_out=20, far=(-4, -2)):
    sh = art.ang_pt(hip, t, TORSO)
    a = (sh[0] + 4, sh[1] + 81)
    b = chest_pt(hip, t, end_u, end_out)

    def f(k):
        g = lerp(a, b, k)
        return B(hip, t, aN=G(g, 1), aF=G((g[0] + far[0], g[1] + far[1]), 1),
                 lN=G(ROW_ANKLE, -1, end=0), lF=G((ROW_ANKLE[0] - 4, FLOOR_Y), -1, end=0), h=t + 12)
    return seq(f, (0, 0.5, 1))


def barbell_row_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 70)
    else:
        bar_end(doc, kit.grip(j), 22)


def db_row_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 70)
        kit.dumbbell(doc, kit.grip(j, "F"), r=9)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


# ---- chest-supported row -------------------------------------------------------------------------

CS_T = -38
CS_HIP = (150, 163)
CS_SH = art.ang_pt(CS_HIP, CS_T, TORSO)


def cs_pad_line(u0, u1, out=15, th=12):
    d = (math.cos(math.radians(CS_T)), math.sin(math.radians(CS_T)))
    n = (-d[1], d[0])
    a = art.add(art.add(CS_HIP, d, u0 * TORSO), n, out + th)
    b = art.add(art.add(CS_HIP, d, u1 * TORSO), n, out + th)
    return a, b


def chest_supported_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 110)
        a, b = cs_pad_line(0.04, 0.9)
        mid = lerp(a, b, 0.45)
        art.tube(doc, mid, (mid[0] + 6, GROUND - 2), 8, "butt")
        art.tube(doc, lerp(a, b, 0.1), (a[0] - 18, GROUND - 2), 6)
        kit.feet(doc, a[0] - 34, mid[0] + 40)
        art.pad(doc, a, b, 12)
        kit.dumbbell(doc, kit.grip(j, "F"), r=9)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


def chest_supported_poses():
    a = (CS_SH[0] + 14, CS_SH[1] + 79)
    # Row finish beside the ribs (not out in front of the chest, where the pad is).
    b = chest_pt(CS_HIP, CS_T, 0.55, 5)

    def f(k):
        g = lerp(a, b, k)
        return B(CS_HIP, CS_T, aN=G(g, 1), aF=G((g[0] - 4, g[1] - 2), 1),
                 lN=G((CS_HIP[0] - 40, FLOOR_Y), -1, end=0), lF=G((CS_HIP[0] - 46, FLOOR_Y), -1, end=0), h=-20)
    return seq(f)


# ---- one-arm dumbbell row ------------------------------------------------------------------------

OA_HIP = (160, 156)
OA_T = -8
OA_SH = art.ang_pt(OA_HIP, OA_T, TORSO)
OA_KNEE = (OA_HIP[0] - 22, BENCH_TOP - 7)


def one_arm_poses():
    a = (OA_SH[0] + 2, OA_SH[1] + 81)
    b = chest_pt(OA_HIP, OA_T, 0.3, 14)

    def f(k):
        g = lerp(a, b, k)
        return B(OA_HIP, OA_T, aN=G(g, 1), aF=G((OA_SH[0] + 6, BENCH_TOP - 5), 1, end=0, wrist=True),
                 lN=G((OA_HIP[0] + 8, FLOOR_Y), -1, end=0), lF=(deg(art.sub(OA_KNEE, OA_HIP)), 180, 180),
                 h=OA_T + 10, lit_sides="N")
    return seq(f)


def one_arm_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 120)
        kit.flat_bench(doc, 62, 250, BENCH_TOP)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


# ---- band row ------------------------------------------------------------------------------------

BR_HIP = (170, ST_HIP[1])
BR_SH = art.ang_pt(BR_HIP, -90, TORSO)
BR_ANCHOR = (BR_SH[0] + 156, BR_SH[1] + 22)


def band_row_poses():
    a = (BR_SH[0] + 79, BR_SH[1] + 18)
    b = chest_pt(BR_HIP, -90, 0.5, 14)

    def f(k):
        g = lerp(a, b, k)
        return B(BR_HIP, -90 - 4 * (1 - k), aN=G(g, 1), aF=G((g[0] - 4, g[1] - 1), 1),
                 lN=G((BR_HIP[0] + 18, FLOOR_Y), -1, end=0), lF=G((BR_HIP[0] - 18, FLOOR_Y), -1, end=0), h=-92)
    return seq(f)


def band_row_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 230, 120)
        kit.post(doc, BR_ANCHOR[0] + 6, BR_ANCHOR[1] - 16)
        kit.band(doc, (BR_ANCHOR[0], BR_ANCHOR[1] + 2), kit.grip(j, "F"))
    else:
        kit.band(doc, BR_ANCHOR, kit.grip(j))
        kit.handle(doc, kit.grip(j))


# ---- inverted row / table row ---------------------------------------------------------------------

def body_line(ankle, t, grip, d_goal, foot=None, **kw):
    hip = art.ang_pt(ankle, t, THIGH + SHIN)
    leg = t + 180
    return B(hip, t, aN=G(grip, 1), aF=G((grip[0] - 3, grip[1] - 1), 1),
             lN=(leg, leg, leg - 90 if foot is None else foot), lF=(leg + 1, leg + 1, leg - 90 if foot is None else foot),
             h=t, **kw)


def solve_t(ankle, grip, dist, lo=-179, hi=-120):
    for _ in range(50):
        m = (lo + hi) / 2
        sh = art.ang_pt(art.ang_pt(ankle, m, THIGH + SHIN), m, TORSO)
        if kit.dist(sh, grip) > dist:
            lo = m
        else:
            hi = m
    return (lo + hi) / 2


def hang_row_poses(ankle, grip):
    t1 = solve_t(ankle, grip, 81)
    t3 = solve_t(ankle, grip, 36)
    return [body_line(ankle, t, grip, 0) for t in (t1, (t1 + t3) / 2 + 2, t3)]


IR_ANKLE = (322, FLOOR_Y)
IR_GRIP = (196, 132)


def inverted_row_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 230, 120)
        kit.strap(doc, (IR_GRIP[0] - 3, IR_GRIP[1] - 1), (IR_GRIP[0] - 14, -60))
    else:
        kit.strap(doc, IR_GRIP, (IR_GRIP[0] - 10, -60))


TR_ANKLE = (330, FLOOR_Y)
TR_TOP = 168
TR_GRIP = (188, TR_TOP + 4)


def table_row_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 230, 140)
        x1 = TR_GRIP[0] + 8
        x0 = x1 - 190
        wood = doc.box_grad([(0, "#8A6744"), (1, "#5E4329")])
        # Far legs (darker, a little higher up the picture) behind the lifter, who lies between the legs.
        for x in (x0 + 12, x1 - 12):
            doc.add(f'<rect x="{x:.1f}" y="{TR_TOP + 8}" width="7" height="{GROUND - TR_TOP - 11}" fill="#4A3522" '
                    f'stroke="#0A0B0D" stroke-width="0.7"/>')
        _table_leg(doc, x0 + 8, wood)
        doc.add(f'<rect x="{x0 + 4:.1f}" y="{TR_TOP + 8}" width="{x1 - x0 - 8:.1f}" height="9" fill="#4A3522" '
                f'stroke="#0A0B0D" stroke-width="0.6"/>')
        doc.add(f'<rect x="{x0:.1f}" y="{TR_TOP}" width="{x1 - x0:.1f}" height="9" rx="2" fill="{wood}" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')
    else:
        # Near leg at the gripped end stands in front of the body (the lifter lies between the table legs),
        # instead of looking like it runs through the torso.
        x1 = TR_GRIP[0] + 8
        _table_leg(doc, x1 - 16, doc.box_grad([(0, "#8A6744"), (1, "#5E4329")]), top=TR_TOP + 9)


def _table_leg(doc, x, fill, top=TR_TOP + 8):
    doc.add(f'<rect x="{x:.1f}" y="{top}" width="8" height="{GROUND - top}" fill="{fill}" stroke="#0A0B0D" '
            f'stroke-width="0.7"/>')


# ---- hanging: pull-ups ---------------------------------------------------------------------------

BAR = (204, 46)
HANG_LEGS = dict(lN=(74, 158, 136), lF=(80, 164, 142))


def hang(sh, t, legs=HANG_LEGS, grip=BAR, bend=1, h=None, **kw):
    hip = art.ang_pt(sh, t + 180, TORSO)
    return B(hip, t, aN=G(grip, bend), aF=G((grip[0] - 2, grip[1] + 1), bend), h=t if h is None else h,
             **legs, **kw)


def pull_poses(end=(-20, 18), mid=(-10, 50), t=(-92, -96, -101), legs=HANG_LEGS):
    shs = [(BAR[0] - 3, BAR[1] + 80.5), (BAR[0] + mid[0], BAR[1] + mid[1]), (BAR[0] + end[0], BAR[1] + end[1])]
    hs = [t[0] + 8, t[1] + 4, t[2] + 18]
    return [hang(s, tt, legs, h=hh) for s, tt, hh in zip(shs, t, hs)]


def pullup_scene(doc, j, layer):
    if layer == "back":
        kit.pullup_bar(doc, BAR, top=-80, half=40)


def weighted_scene(doc, j, layer):
    if layer == "back":
        kit.pullup_bar(doc, BAR, top=-80, half=40)
    else:
        belt = chest_pt(j["hip"], j["_t"], 0.08, 14)
        kb = (j["hip"][0] + 10, j["hip"][1] + 40)
        doc.add(f'<polyline points="{belt[0]:.1f},{belt[1]:.1f} {kb[0]:.1f},{kb[1] - 7:.1f}" fill="none" stroke="#9AA3AD" '
                f'stroke-width="2" stroke-dasharray="2.5 1.5"/>')
        kit.kettlebell(doc, kb, r=12)


def band_assist_scene(doc, j, layer):
    if layer == "back":
        kit.pullup_bar(doc, BAR, top=-80, half=40)
        kit.band(doc, (BAR[0] - 3, BAR[1] + 3), art.add(j["kneeF"], (0, 6)), color="#C0392B")
    else:
        k = art.add(j["kneeN"], (0, 7))
        kit.band(doc, (BAR[0] + 2, BAR[1] + 3), k, color="#C0392B")


def scap_scene(doc, j, layer):
    if layer == "back":
        kit.pullup_bar(doc, BAR, top=-80, half=40)
    elif j["_t"] < -95:
        kit.motion(doc, art.add(j["shoulder"], (-26, 14)), -90, 18)


SCAP_LEGS = dict(lN=(80, 96, 62), lF=(86, 100, 66))  # legs hang long (bent-back knees read as kneeling)


def scap_poses():
    """Straight-arm hang: passive at the start, then the shoulder blades depress and draw back, so the body
    rises only a few px with the arms (nearly) straight."""
    s0 = (BAR[0] - 2, BAR[1] + 83)
    s2 = circle_x(BAR, 78, (BAR[0] - 10, BAR[1] + 76), 6, 1)
    s1 = lerp(s0, s2, 0.5)
    return [hang(s0, -90, SCAP_LEGS, h=-72), hang(s1, -94, SCAP_LEGS, h=-82, curl=-3),
            hang(s2, -98, SCAP_LEGS, h=-92, curl=-6)]


# ---- dips ----------------------------------------------------------------------------------------

DIP_Y = 138
DIP_GRIP = (206, DIP_Y - 5)


def dip_poses():
    shs = [((DIP_GRIP[0] - 2, DIP_GRIP[1] - 80), -86), ((DIP_GRIP[0] + 4, DIP_GRIP[1] - 60), -78),
           ((DIP_GRIP[0] + 10, DIP_GRIP[1] - 36), -68)]
    out = []
    for (s, t), legs in zip(shs, ((96, 150, 140), (100, 152, 140), (104, 156, 142))):
        hip = art.ang_pt(s, t + 180, TORSO)
        out.append(B(hip, t, aN=G(DIP_GRIP, 1), aF=G((DIP_GRIP[0] - 2, DIP_GRIP[1] + 1), 1), h=t + 6,
                     lN=legs, lF=(legs[0] - 6, legs[1] + 4, legs[2])))
    return out


def dips_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 90)
        # Long bars: the rear post stands behind the feet instead of crossing the shins.
        kit.dip_bars(doc, 92, 262, DIP_Y)


# ---- plank family on the floor -------------------------------------------------------------------

def rigid_plank(arm, wrist, toe_y=GROUND - 1, foot=None, lo=-60.0, hi=30.0, **kw):
    """Straight body from the pinned wrist; solve the torso angle so the toes touch the floor."""
    pose = None
    for _ in range(44):
        t = (lo + hi) / 2
        lf = (t + 180, t + 180, 80 if foot is None else foot)
        pose = P(t=t, h=t, lN=lf, lF=lf, aN=arm, aF=arm, pin=("wristN", wrist), **kw)
        y = F.place(pose)["toeN"][1]
        if y < toe_y:
            hi = t
        else:
            lo = t
    return pose


RING = (272, 220)


def ring_push_poses():
    w = (RING[0], RING[1] - 5)
    return [rigid_plank((90, 90), w), rigid_plank((140, 64), w), rigid_plank((178, 50), w)]


def ring_push_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 120)
        kit.ring(doc, (RING[0] - 3, RING[1] + 1), (RING[0] - 1, -120))
        # Near strap behind the figure too: it hangs beside the body, so the torso hides it instead of the strap
        # cutting through the chest; only its ring is drawn in front, in the hand.
        doc.add(f'<line x1="{RING[0] + 2}" y1="-120" x2="{RING[0]}" y2="{RING[1] - 8}" stroke="#16181B" stroke-width="3"/>')
    else:
        doc.add(f'<circle cx="{RING[0]}" cy="{RING[1]}" r="8" fill="none" stroke="#C8A06A" stroke-width="3.6"/>')


PK_W = (264, GROUND - 5)
PK_ANKLE = (PK_W[0] - 92, GROUND - 10)


def pike_poses():
    """Hips stay high over the feet; the shoulders come forward over the hands as the elbows bend, so the
    head lowers towards the floor between the hands (forearms stay steep, not a forearm-plank fold)."""
    out = []
    for hip, reach in (((176, 148), 79), ((194, 150), 66), ((210, 153), 54)):
        s = circle_x(hip, TORSO, PK_W, reach, -1)
        t = deg(art.sub(s, hip))
        out.append(B(hip, t, aN=G(PK_W, 1, end=0, wrist=True), aF=G((PK_W[0] - 3, PK_W[1]), 1, end=0, wrist=True),
                     lN=G(PK_ANKLE, -1, end=30), lF=G((PK_ANKLE[0] - 3, PK_ANKLE[1]), -1, end=30), h=t + 24))
    return out


def floor_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 130)


def mat_scene(x0, x1):
    def scene(doc, j, layer):
        if layer == "back":
            floor(doc, (x0 + x1) / 2, (x1 - x0) / 2)
            kit.mat(doc, x0, x1)
    return scene


PRONE_HIP = (176, GROUND - 4 - 15)


def prone_pulldown_poses():
    legs = dict(lN=(180, 180, 110), lF=(180.5, 180.5, 110))
    return [P(t=-5, h=-10, aN=(-10, -10), aF=(-12, -12), pin=("hip", PRONE_HIP), **legs),
            P(t=-7, h=-12, aN=(196, -16), aF=(198, -16), pin=("hip", PRONE_HIP), **legs),
            P(t=-8, h=-14, aN=(170, 6), aF=(172, 6), pin=("hip", PRONE_HIP), **legs)]


# ---- kneeling pulldowns --------------------------------------------------------------------------

KN_HIP = (176, GROUND - 8 - THIGH)
KN_LEGS = dict(lN=(90, 180, 180), lF=(92, 180, 180))


def kneel_pull_poses(anchor, t=(-94, -92, -90), end=(14, 18), far=None, both=True):
    out = []
    for k, tt in zip((0, 0.5, 1), t):
        sh = art.ang_pt(KN_HIP, tt, TORSO)
        d = art.norm(art.sub(anchor, sh))
        a = art.add(sh, d, 80)
        b = (sh[0] + end[0], sh[1] + end[1])
        g = lerp(a, b, k) if k < 1 else b
        if k == 0.5:
            g = art.add(sh, art.norm(art.sub(lerp(a, b, 0.5), sh)), 56)
        aF = G((g[0] - 3, g[1] - 1), 1) if both else (far or (96, 84))
        out.append(B(KN_HIP, tt, aN=G(g, 1), aF=aF, h=tt + 6 - 10 * (1 - k), lit_sides="NF" if both else "N",
                     **KN_LEGS))
    return out


SA_TOWER_X = 300
SA_PULLEY = (SA_TOWER_X - 12, 40)


def single_pulldown_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 230, 130)
        kit.mat(doc, 100, 200)
        lift = max(0, (kit.dist(g, SA_PULLEY) - 66) * 0.28)
        kit.cable_tower(doc, SA_TOWER_X, SA_PULLEY[1], lift)
    else:
        art.cable(doc, [g, art.add(SA_PULLEY, (-5, 3))])
        kit.handle(doc, g)


DOOR_X = 292
DOOR_ANCHOR = (DOOR_X - 2, 34)


def band_pulldown_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 220, 120)
        kit.mat(doc, 110, 210)
        wood = doc.box_grad([(0, "#9A7650"), (1, "#6E5136")], vertical=False)
        doc.add(f'<rect x="{DOOR_X}" y="20" width="16" height="{GROUND - 20}" fill="{wood}" stroke="#2A2F35" stroke-width="0.8"/>'
                f'<rect x="{DOOR_X + 16}" y="12" width="22" height="{GROUND - 12}" fill="#5B636D" stroke="#2A2F35" '
                f'stroke-width="0.8"/>'
                f'<circle cx="{DOOR_X - 2}" cy="150" r="3" fill="#C9CFD6" stroke="#2A2F35" stroke-width="0.6"/>')
        doc.add(f'<rect x="{DOOR_X - 4}" y="22" width="24" height="7" rx="2" fill="#1A1D21"/>')
        kit.band(doc, DOOR_ANCHOR, kit.grip(j, "F"))
    else:
        kit.band(doc, DOOR_ANCHOR, kit.grip(j))
        kit.handle(doc, kit.grip(j))


# ---- floor presses / pullover --------------------------------------------------------------------

FL_HIP = (236, GROUND - 4 - 17)
FL_SH = art.ang_pt(FL_HIP, 180, TORSO)
FL_FOOT = (FL_HIP[0] + 62, GROUND - 4 - 4)


def supine(gn, gf, bend=1, **kw):
    return B(FL_HIP, 180, aN=G(gn, bend), aF=G(gf, bend), lN=G(FL_FOOT, -1, end=0),
             lF=G((FL_FOOT[0] - 6, FL_FOOT[1]), -1, end=0), h=182, **kw)


def floor_press_poses():
    a = (FL_SH[0] + 4, FL_SH[1] - 80)
    b = (FL_SH[0] + 30, FL_SH[1] - 34)

    def f(k):
        g = lerp(a, b, k)
        return supine(g, (g[0] - 4, g[1] - 2))
    return seq(f, PRESS_KS)


def floor_db_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 210, 120)
        kit.mat(doc, 96, 320)
        kit.dumbbell(doc, kit.grip(j, "F"), r=9)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


def pullover_poses():
    out = []
    for a in (-86, -128, -170):
        g = art.ang_pt(FL_SH, a, 78)
        out.append(supine(g, (g[0] + 1, g[1] - 1), -1))
    return out


def pullover_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 210, 120)
        kit.mat(doc, 70, 320)
    else:
        w, h = j["wristN"], j["handN"]
        d = art.norm(art.sub(h, w))
        kit.dumbbell(doc, art.add(w, d, 16), deg(d), r=9)


# ---- band chest press ----------------------------------------------------------------------------

BC_HIP = (214, ST_HIP[1])
BC_SH = art.ang_pt(BC_HIP, -90, TORSO)
BC_ANCHOR = (BC_SH[0] - 100, BC_SH[1] + 20)


def band_chest_poses():
    a = chest_pt(BC_HIP, -90, 0.86, 30)
    b = (BC_SH[0] + 79, BC_SH[1] + 8)

    def f(k):
        g = lerp(a, b, k)
        return B(BC_HIP, -88, aN=G(g, 1), aF=G((g[0] - 4, g[1] - 1), 1),
                 lN=G((BC_HIP[0] + 18, FLOOR_Y), -1, end=0), lF=G((BC_HIP[0] - 20, FLOOR_Y), -1, end=0), h=-90)
    return seq(f, PRESS_KS)


def band_chest_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 170, 120)
        kit.post(doc, BC_ANCHOR[0] - 6, BC_ANCHOR[1] - 16)
        kit.band(doc, BC_ANCHOR, kit.grip(j, "F"))
        # Near band too: it runs beside the body (under the arm), so the torso hides it instead of the
        # band cutting across the chest.
        kit.band(doc, (BC_ANCHOR[0], BC_ANCHOR[1] + 2), kit.grip(j))
    else:
        kit.handle(doc, kit.grip(j))


# ---- face pull -----------------------------------------------------------------------------------

FP_HIP = (176, ST_HIP[1])
FP_SH = art.ang_pt(FP_HIP, -90, TORSO)
FP_TOWER = 330
FP_PULLEY = (FP_TOWER - 12, FP_SH[1] - 22)


def face_pull_poses():
    d = art.norm(art.sub(FP_PULLEY, FP_SH))
    a = art.add(FP_SH, d, 79)
    # Rope pulled level to the face (hands by the forehead, not behind the head); the elbows stay high (bend -1)
    # in every key so the in-betweens do not swing the arm over the head.
    b = (FP_SH[0] + 14, FP_SH[1] - 27)
    out = []
    for k in (0, 0.5, 1):
        g = lerp(a, b, k)
        out.append(B(FP_HIP, -90 - 3 * k, aN=G(g, -1), aF=G((g[0] - 4, g[1] - 1), -1),
                     lN=G((FP_HIP[0] + 14, FLOOR_Y), -1, end=0), lF=G((FP_HIP[0] - 14, FLOOR_Y), -1, end=0), h=-90))
    return out


def face_pull_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 240, 130)
        lift = max(0, (kit.dist(g, FP_PULLEY) - 58) * 0.3)
        kit.cable_tower(doc, FP_TOWER, FP_PULLEY[1], lift)
    else:
        art.cable(doc, [g, art.add(FP_PULLEY, (-5, 1))])
        kit.handle(doc, g, "rope")


# ---- frontal-plane: raises, flyes ----------------------------------------------------------------

FR_HIP = (200, ST_HIP[1])
FR_LEGS = dict(lN=(86, 91, 12), lF=(94, 89, 168))


def fr_sh(hip=FR_HIP, t=-90):
    sh = art.ang_pt(hip, t, TORSO)
    return (sh[0] + SW, sh[1]), (sh[0] - SW, sh[1])


def lateral_raise_poses():
    return [P(t=-90, front="back", aN=(84, 88), aF=(96, 92), pin=("hip", FR_HIP), **FR_LEGS),
            P(t=-90, front="back", aN=(40, 46), aF=(140, 134), pin=("hip", FR_HIP), **FR_LEGS),
            P(t=-90, front="back", aN=(-2, 8), aF=(182, 172), pin=("hip", FR_HIP), **FR_LEGS)]


def lateral_raise_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 60)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)
        kit.dumbbell(doc, kit.grip(j, "F"), r=10)


CL_TOWER = 96
CL_PULLEY = (CL_TOWER + 12, GROUND - 22)


def cable_lateral_poses():
    shf = fr_sh()[1]
    col = (CL_TOWER + 6, shf[1] + 34)
    out = []
    for aN in ((100, 102), (48, 52), (0, 6)):
        out.append(B(FR_HIP, -90, front="back", aN=aN, aF=G(col, 1), lit_sides="N", **FR_LEGS))
    return out


def cable_lateral_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 170, 110)
        lift = max(0, (kit.dist(g, CL_PULLEY) - 110) * 0.25)
        tower(doc, CL_TOWER, CL_PULLEY[1], lift, side="R")
    else:
        art.cable(doc, [art.add(CL_PULLEY, (5, 0)), g])
        kit.handle(doc, g)


CF_L, CF_R = 70, 330
CF_PY = 104
CF_TOP = 94


def cable_fly_poses():
    shn, shf = fr_sh()
    pn, pf = (CF_R - 12, CF_PY), (CF_L + 12, CF_PY)
    a_n = art.add(shn, art.norm(art.sub(pn, shn)), 78)
    a_f = art.add(shf, art.norm(art.sub(pf, shf)), 78)
    mid = (FR_HIP[0], shn[1] + 48)
    out = []
    for k in (0, 0.55, 1):
        gn = lerp(a_n, (mid[0] + 5, mid[1]), k)
        gf = lerp(a_f, (mid[0] - 5, mid[1]), k)
        if k == 0.55:
            gn = art.add(shn, art.norm(art.sub(gn, shn)), 72)
            gf = art.add(shf, art.norm(art.sub(gf, shf)), 72)
        out.append(B(FR_HIP, -90, front=True, aN=G(gn, 1), aF=G(gf, -1), lN=(80, 92, 12), lF=(100, 88, 168)))
    return out


def cable_fly_scene(doc, j, layer):
    gn, gf = kit.grip(j), kit.grip(j, "F")
    if layer == "back":
        floor(doc, 200, 150)
        tower(doc, CF_R, CF_PY, max(0, (kit.dist(gn, (CF_R - 12, CF_PY)) - 78) * 0.3), "L", top=CF_TOP, plates=9)
        tower(doc, CF_L, CF_PY, max(0, (kit.dist(gf, (CF_L + 12, CF_PY)) - 78) * 0.3), "R", top=CF_TOP, plates=9)
    else:
        art.cable(doc, [gn, (CF_R - 12, CF_PY + 6)])
        art.cable(doc, [gf, (CF_L + 12, CF_PY + 6)])
        kit.handle(doc, gn)
        kit.handle(doc, gf)


CE_TOWER = 80
CE_HIP = (206, ST_HIP[1])
CE_PHI = (-74, 34, 84)   # forearm's rotation in the horizontal plane: -90 across the belly, 0 forward, 90 out
CE_TILT = 0.42           # front view seen slightly from above: forward-pointing forearm drops this much


def ext_rot_poses():
    """Front view: the elbow stays at the side, the forearm swings from across the belly out to the side."""
    # The rotation angle rides in the (otherwise unused) hand angle; the scene foreshortens the forearm from it.
    return [B(CE_HIP, -90, front=True, aN=(86, 90, phi), aF=(94, 88), **FR_LEGS) for phi in CE_PHI]


def _er_point(e, phi, r):
    a = math.radians(phi)
    return (e[0] + r * math.sin(a), e[1] + r * math.cos(a) * CE_TILT)


def ext_rot_scene(doc, j, layer):
    """The cable runs across the front of the body from the column on the far side; towel under the elbow."""
    e = j["elbowN"]
    if layer == "back":
        # Foreshorten the forearm: it moves in the horizontal plane at elbow height.
        phi = deg(art.sub(j["handN"], j["wristN"]))
        j["wristN"] = _er_point(e, phi, FORE)
        j["handN"] = _er_point(e, phi, FORE + HAND)
    g = kit.grip(j)
    p = (CE_TOWER + 12, e[1])
    if layer == "back":
        floor(doc, 160, 120)
        tower(doc, CE_TOWER, p[1], max(0, (kit.dist(g, p) - 96) * 0.3), "R")
    else:
        # Rotation path: the hand's circle around the elbow (in front of the belly), seen from slightly above.
        pts = [_er_point(e, a, FORE + 8) for a in range(-84, 97, 6)]
        doc.add(f'<path d="{art.smooth(pts, closed=False)}" fill="none" stroke="#fff" stroke-opacity="0.7" '
                f'stroke-width="2.4" stroke-dasharray="2 6" stroke-linecap="round"/>')
        doc.add(f'<rect x="{e[0] - 12:.1f}" y="{e[1] - 13:.1f}" width="7" height="12" rx="2" fill="#EDEFF2" '
                f'stroke="#8A939E" stroke-width="0.7"/>')
        art.cable(doc, [art.add(p, (5, 0)), g])
        kit.handle(doc, g)


def pull_apart_poses():
    return [B(FR_HIP, -90, front="back", aN=(64, 70), aF=(116, 110), **FR_LEGS),
            B(FR_HIP, -90, front="back", aN=(30, 32), aF=(150, 148), **FR_LEGS),
            B(FR_HIP, -90, front="back", aN=(-2, -2), aF=(182, 182), **FR_LEGS)]


def pull_apart_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 70)
        kit.band(doc, kit.grip(j, "F"), kit.grip(j))


# ---- prone Y-T-W ---------------------------------------------------------------------------------
# Seen from above and a little from the side: the back faces the viewer so the Y, T and W read as letters,
# the body lies chest-down along an incline bench whose head end stands higher (longer legs), its frame and
# the lifter's feet on the floor below. Height above the floor shifts things up the picture (YT_K px per px).

YT_HIP = (165, 150)
YT_T = -4             # body axis (hip → shoulder), head end raised
YT_FLOOR = 190        # floor level under the bench's centre line
YT_K = 0.4            # picture shift per unit of height
YT_LEGS = dict(lN=(150, 160, 160), lF=(164, 166, 166))


def ytw_poses():
    a = YT_T
    arms = [((a + 40, a + 40, a + 40), (a - 40, a - 40, a - 40)),            # Y: overhead in a V
            ((a + 90, a + 90, a + 90), (a - 90, a - 90, a - 90)),            # T: straight out to the sides
            ((a + 122, a + 34, a + 34), (a - 122, a - 34, a - 34))]          # W: elbows bent, squeezed back
    return [B(YT_HIP, a, front="back", h=a, aN=n, aF=f, **YT_LEGS) for n, f in arms]


def _yt_line(x):
    """Pad centre line (picture y) at x: just under the body, rising with the body axis."""
    return YT_HIP[1] + 12 + (x - YT_HIP[0]) * math.tan(math.radians(YT_T))


def _slab(doc, x0, x1, y0, y1, half=19, side=6):
    """Upholstered pad seen from above: top face (x0, y0)→(x1, y1) ± half, near side face below it."""
    top = [(x0, y0 - half), (x1, y1 - half), (x1, y1 + half), (x0, y0 + half)]
    face = [(x0, y0 + half), (x1, y1 + half), (x1, y1 + half + side), (x0, y0 + half + side)]
    g = doc.lin((x0, min(y0, y1) - half), (x0, max(y0, y1) + half), [(0, "#4A515A"), (0.35, art.PAD[1]), (1, art.PAD[2])])
    pts = lambda ps: " ".join(f"{x:.1f},{y:.1f}" for x, y in ps)
    doc.add(f'<polygon points="{pts(face)}" fill="#0F1113" stroke="#0A0B0D" stroke-width="0.8" stroke-linejoin="round"/>')
    doc.add(f'<polygon points="{pts(top)}" fill="{g}" stroke="#0A0B0D" stroke-width="0.9" stroke-linejoin="round"/>')
    doc.add(f'<line x1="{x0 + 4:.1f}" y1="{y0 - half + 3:.1f}" x2="{x1 - 4:.1f}" y2="{y1 - half + 3:.1f}" stroke="#6B737D" '
            f'stroke-opacity="0.5" stroke-width="0.6" stroke-dasharray="2 1.6"/>')


def ytw_scene(doc, j, layer):
    if layer == "back":
        f = YT_FLOOR
        doc.add(f'<ellipse cx="150" cy="{f + 4}" rx="125" ry="16" fill="#000" fill-opacity="0.2"/>')
        # Base rail and cross feet on the floor, posts up to the pads (the head end stands higher).
        seat_x0, seat_x1, back_x1 = 98, 150, 242
        art.tube(doc, (seat_x0 - 8, f), (back_x1 + 2, f), 7)
        for x in (seat_x0 - 4, back_x1 - 2):
            art.tube(doc, (x, f - 20), (x, f + 20), 7)
        art.tube(doc, (seat_x0 + 6, f), (seat_x0 + 6, _yt_line(seat_x0) + 10), 6, "butt")
        art.tube(doc, (back_x1 - 6, f), (back_x1 - 6, _yt_line(back_x1) + 10), 6, "butt")
        art.tube(doc, (196, f), (214, _yt_line(214) + 10), 5, "butt")
        _slab(doc, seat_x0, seat_x1, _yt_line(seat_x0) + 6, _yt_line(seat_x0) + 6, half=17)
        _slab(doc, seat_x1 + 2, back_x1, _yt_line(seat_x1), _yt_line(back_x1))
    else:
        kit.dumbbell(doc, kit.grip(j), r=8)
        kit.dumbbell(doc, kit.grip(j, "F"), r=8)


# ---- pec deck (front) / reverse pec deck (back) --------------------------------------------------

PD_HIP = (200, 186)
PD_LEGS = dict(lN=(24, 92, 12), lF=(156, 88, 168))
PD_PIV_Y = 40


def pec_deck_poses():
    shn, shf = fr_sh(PD_HIP)
    a_n, a_f = (shn[0] + 76, shn[1] + 6), (shf[0] - 76, shf[1] + 6)
    mid = (PD_HIP[0], shn[1] + 22)
    out = []
    for k in (0, 0.5, 1):
        gn = lerp(a_n, (mid[0] + 5, mid[1]), k)
        gf = lerp(a_f, (mid[0] - 5, mid[1]), k)
        out.append(B(PD_HIP, -90, front=True, aN=G(gn, 1), aF=G(gf, -1), h=-90, **PD_LEGS))
    return out


def reverse_deck_poses():
    shn, shf = fr_sh(PD_HIP)
    mid = (PD_HIP[0], shn[1] + 16)
    a_n, a_f = (shn[0] + 79, shn[1] + 2), (shf[0] - 79, shf[1] + 2)
    out = []
    for k in (0, 0.5, 1):
        gn = lerp((mid[0] + 6, mid[1]), a_n, k)
        gf = lerp((mid[0] - 6, mid[1]), a_f, k)
        out.append(B(PD_HIP, -90, front="back", aN=G(gn, -1), aF=G(gf, 1), h=-90, **PD_LEGS))
    return out


PD_REACH = 78  # shoulder → grip, elbows softly bent (the arm is 85 long straight)
PD_DROP = 6  # grips just below shoulder height


def pec_sweep(j, facing):
    """0 = arms out to the sides, 1 = hands together in front of the chest, read from the pose's near grip."""
    shn = fr_sh(PD_HIP)[0]
    g = kit.grip(j)
    wide, closed = shn[0] + 76, PD_HIP[0] + 5
    return max(0.0, min(1.0, (wide - g[0]) / (wide - closed)))


def pec_arms(j, facing):
    """Arms as a 3D chain projected to the front / back view: each grip swings on a horizontal arc round its
    shoulder (towards the camera in front view) with the elbow softly bent and pointing out and down, so the
    arms foreshorten as they close instead of folding and crossing in the picture plane."""
    from scenes_arms_core import _ik3
    k = pec_sweep(j, facing)
    shn, shf = fr_sh(PD_HIP)
    r = math.sqrt(PD_REACH ** 2 - PD_DROP ** 2)
    end = math.acos(max(-1.0, min(1.0, (SW - 5) / r)))
    phi = math.radians(4) + (end - math.radians(4)) * k
    toward = 1 if facing == "front" else -1  # +z = towards the camera
    for s, sh in (("N", shn), ("F", shf)):
        sx = 1 if s == "N" else -1
        a = (sh[0], sh[1], 0.0)
        g = (sh[0] + sx * r * math.cos(phi), sh[1] + PD_DROP, toward * r * math.sin(phi))
        e = _ik3(a, g, UPPER, FORE + HAND / 2, (sx * 0.6, 1.0, -toward * 0.5))
        d = art.norm((g[0] - e[0], g[1] - e[1])) if math.dist(g[:2], e[:2]) > 0.5 else (sx * 1.0, 0.0)
        fl = math.dist(g, e)  # 3D forearm + half hand
        flat = math.dist(g[:2], e[:2])
        scale = flat / fl if fl else 1
        j["elbow" + s] = (e[0], e[1])
        j["wrist" + s] = art.add(g[:2], d, -HAND / 2 * scale)
        j["hand" + s] = art.add(g[:2], d, HAND / 2 * scale)


def pec_seat_legs(j):
    """Seated, thighs pointing at the camera: short (foreshortened) thighs off the seat front, shins down."""
    for s, sx in (("N", 1), ("F", -1)):
        hp = j["hip" + s]
        kn = (hp[0] + sx * 30, hp[1] + 12)
        an = (kn[0] + sx * 2, GROUND - 4)
        j["knee" + s] = kn
        j["ankle" + s] = an
        j["toe" + s] = (an[0] + sx * 5, an[1] + 3)


def pec_machine(doc, j, layer, facing):
    shn, shf = fr_sh(PD_HIP)
    pivots = ((shn[0] + 6, PD_PIV_Y), (shf[0] - 6, PD_PIV_Y))
    if layer == "back":
        pec_arms(j, facing)
        pec_seat_legs(j)
        gn, gf = kit.grip(j), kit.grip(j, "F")
        floor(doc, 200, 140)
        open_ = abs(gn[0] - gf[0])
        lift = max(0, (150 - open_) * 0.12) if facing == "front" else max(0, (open_ - 20) * 0.1)
        # Central tower: head unit on top carrying the two swing arms.
        art.tube(doc, (PD_HIP[0] - 30, GROUND - 2), (PD_HIP[0] - 30, 30), 10)
        art.tube(doc, (PD_HIP[0] + 30, GROUND - 2), (PD_HIP[0] + 30, 30), 10)
        art.tube(doc, (pivots[1][0] - 10, 30), (pivots[0][0] + 10, 30), 10)
        kit.feet(doc, PD_HIP[0] - 70, PD_HIP[0] + 70)
        # Stack column behind the seat, back pad (front view) / chest pad (back view).
        art.shroud(doc, 178, 44, PD_HIP[1] - 30, 44)
        art.stack(doc, 183, 54, PD_HIP[1] - 30, 34, 8, lift)
        art.tube(doc, (PD_HIP[0], PD_HIP[1] - 30), (PD_HIP[0], GROUND - 2), 10, "butt")
        doc.add(f'<rect x="{PD_HIP[0] - 22}" y="{shn[1] - 30:.1f}" width="44" height="{PD_HIP[1] - shn[1] + 22:.1f}" rx="8" '
                f'fill="#23272C" stroke="#0A0B0D" stroke-width="0.9"/>')
        # Seat under the hips: its front edge shows below the pelvis, the thighs come over it towards the camera.
        art.tube(doc, (PD_HIP[0] - 22, PD_HIP[1] + 14), (PD_HIP[0] + 22, PD_HIP[1] + 14), 14)
        doc.add(f'<rect x="{PD_HIP[0] - 48}" y="{PD_HIP[1] + 4}" width="96" height="14" rx="6" fill="#1E2227" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')
        for p in pivots:
            art.tube(doc, (p[0], 30), p, 7)
            art.pulley(doc, p, 6)
    else:
        gn, gf = kit.grip(j), kit.grip(j, "F")
        for p, g in zip(pivots, (gn, gf)):
            art.tube(doc, p, (g[0], g[1] - 12), 6)
            art.tube(doc, (g[0], g[1] - 12), (g[0], g[1] + 8), 6)
            doc.add(f'<rect x="{g[0] - 3.6:.1f}" y="{g[1] - 8:.1f}" width="7.2" height="16" rx="3.2" fill="#1B1D20"/>')


def pec_deck_scene(doc, j, layer):
    pec_machine(doc, j, layer, "front")


def reverse_deck_scene(doc, j, layer):
    pec_machine(doc, j, layer, "back")



# ---- scenes ----------------------------------------------------------------------------------------

def along(a, b, r=4, n=10):
    """Framing samples along a line (cables, bands, levers); a / b are points or functions of the joints."""
    def f(j):
        pa = a(j) if callable(a) else a
        pb = b(j) if callable(b) else b
        return [(lerp(pa, pb, i / n), r) for i in range(n + 1)]
    return f


def both(*fs):
    return lambda j: [p for f in fs for p in f(j)]


def grip_n(j):
    return kit.grip(j)


def grip_f(j):
    return kit.grip(j, "F")


def tower_box(x, side="L"):
    return (x - 12, 20, x + 48, GROUND) if side == "L" else (x - 48, 20, x + 18, GROUND)


BENCH = (104, BENCH_TOP, 254, GROUND)
BP_RACK = (98, BP_SH[1] - 106, 146, GROUND)
INC_BENCH = (60, 160, 210, GROUND)
UP_BENCH = (100, 100, 210, GROUND)
PEC_FRAME = [(150, 22, 250, GROUND), (130, GROUND - 6, 270, GROUND)]
PULL_BAR = (BAR[0] - 46, BAR[1] - 14, BAR[0] + 8, BAR[1] + 8)

SCENES = {
    "bench-press": S(bench_press_scene, bench_poses(), [BENCH, BP_RACK], held_at("N", 24)),
    "close-grip-bench": S(bench_press_scene, bench_poses(top_dx=4, bot=(28, -18)), [BENCH, BP_RACK], held_at("N", 24)),
    "db-bench": S(db_bench_scene, db_bench_poses(), [BENCH], held_at("N", 11)),
    "incline-db-press": S(make_bench_scene(INC), incline_poses(), [INC_BENCH], held_at("N", 11)),
    "incline-bench-press": S(make_bench_scene(INC, "bar", rack_x=INC_SH[0] - 26, hook=INC_SH[1] - 76),
                             incline_poses(0.9, 22, 4),
                             [INC_BENCH, (INC_SH[0] - 56, INC_SH[1] - 106, INC_SH[0] - 8, GROUND)], held_at("N", 23)),
    "seated-db-press": S(make_bench_scene(UP, back_len=110), seated_press_poses(), [UP_BENCH], held_at("N", 11)),
    "arnold-press": S(make_bench_scene(UP, back_len=110), arnold_poses(), [UP_BENCH], held_at("N", 11)),
    "ohp": S(ohp_scene, press_poses(), [(96, 40, 150, GROUND)], held_at("N", 20)),
    "db-standing-press": S(db_press_scene, db_press_poses(), [], held_at("N", 11)),
    "band-overhead-press": S(band_press_scene, band_ohp_poses()),
    "landmine-press": S(landmine_scene, landmine_poses(), [(LM_ANCHOR[0] - 12, GROUND - 10, LM_ANCHOR[0] + 12, GROUND)],
                        both(held_at("N", 18), along(grip_n, LM_ANCHOR, 4))),
    "chest-press-machine": S(chest_press_scene, chest_press_poses(), [(34, 26, 100, GROUND), (34, 26, CP_PIVOT[0] + 10, 46)],
                             along(CP_PIVOT, grip_n, 6)),
    "barbell-row": S(barbell_row_scene, hinge_poses(), [], held_at("N", 22)),
    "db-bent-row": S(db_row_scene, hinge_poses(end_u=0.4, end_out=18), [], held_at("N", 11)),
    "chest-supported-row": S(chest_supported_scene, chest_supported_poses(), [(95, 130, 215, GROUND)], held_at("N", 11)),
    "one-arm-db-row": S(one_arm_scene, one_arm_poses(), [(60, BENCH_TOP, 252, GROUND)], held_at("N", 11)),
    "band-row": S(band_row_scene, band_row_poses(), [(BR_ANCHOR[0] - 20, BR_ANCHOR[1] - 28, BR_ANCHOR[0] + 32, GROUND)],
                  along(grip_n, BR_ANCHOR)),
    "inverted-row": S(inverted_row_scene, hang_row_poses(IR_ANKLE, IR_GRIP),
                      [(IR_GRIP[0] - 20, IR_GRIP[1] - 40, IR_GRIP[0] + 4, IR_GRIP[1])]),
    "table-row": S(table_row_scene, hang_row_poses(TR_ANKLE, TR_GRIP), [(TR_GRIP[0] - 190, TR_TOP, TR_GRIP[0] + 10, GROUND)]),
    "pull-up": S(pullup_scene, pull_poses(), [PULL_BAR], floor=False),
    "chin-up": S(pullup_scene, pull_poses(end=(-24, 12), mid=(-18, 50), t=(-90, -95, -100)), [PULL_BAR], floor=False),
    "weighted-pull-up": S(weighted_scene, pull_poses(), [PULL_BAR],
                          lambda j: [((j["hip"][0] + 10, j["hip"][1] + 56), 14)], floor=False),
    "band-assisted-pull-up": S(band_assist_scene, pull_poses(legs=dict(lN=(38, 128, 110), lF=(70, 150, 124))),
                               [PULL_BAR], floor=False),
    "scap-pull-up": S(scap_scene, scap_poses(), [PULL_BAR], floor=False),
    "dips": S(dips_scene, dip_poses(), [(82, DIP_Y - 6, 272, GROUND)]),
    "ring-push-up": S(ring_push_scene, ring_push_poses(), [(RING[0] - 12, RING[1] - 40, RING[0] + 12, RING[1] + 10)]),
    "pike-push-up": S(floor_scene, pike_poses()),
    "prone-pulldown": S(mat_scene(84, 290), prone_pulldown_poses(), [(84, GROUND - 6, 290, GROUND)]),
    "single-arm-pulldown": S(single_pulldown_scene, kneel_pull_poses(SA_PULLEY, both=False), [tower_box(SA_TOWER_X)],
                             along(grip_n, SA_PULLEY)),
    "band-pulldown": S(band_pulldown_scene, kneel_pull_poses(DOOR_ANCHOR), [(DOOR_X - 6, 12, DOOR_X + 40, GROUND)],
                       along(grip_n, DOOR_ANCHOR)),
    "db-floor-press": S(floor_db_scene, floor_press_poses(), [(96, GROUND - 6, 320, GROUND)], held_at("N", 11)),
    "db-floor-pullover": S(pullover_scene, pullover_poses(), [(70, GROUND - 6, 320, GROUND)], held_at("N", 24)),
    "band-chest-press": S(band_chest_scene, band_chest_poses(),
                          [(BC_ANCHOR[0] - 32, BC_ANCHOR[1] - 28, BC_ANCHOR[0] + 18, GROUND)],
                          along(grip_n, BC_ANCHOR)),
    "face-pull": S(face_pull_scene, face_pull_poses(), [tower_box(FP_TOWER)], along(grip_n, FP_PULLEY)),
    "db-lateral-raise": S(lateral_raise_scene, lateral_raise_poses(), [], both(held_at("N", 11), held_at("F", 11))),
    "cable-lateral-raise": S(cable_lateral_scene, cable_lateral_poses(), [tower_box(CL_TOWER, "R")], along(grip_n, CL_PULLEY)),
    "cable-fly": S(cable_fly_scene, cable_fly_poses(),
                   [(CF_L - 48, CF_TOP - 14, CF_L + 18, GROUND), (CF_R - 12, CF_TOP - 14, CF_R + 48, GROUND)],
                   both(along(grip_n, (CF_R - 12, CF_PY)), along(grip_f, (CF_L + 12, CF_PY)))),
    "cable-external-rotation": S(ext_rot_scene, ext_rot_poses(), [tower_box(CE_TOWER, "R")],
                                 along(grip_n, (CE_TOWER + 12, 150))),
    "band-pull-apart": S(pull_apart_scene, pull_apart_poses()),
    "prone-ytw": S(ytw_scene, ytw_poses(), [(84, YT_FLOOR - 30, 250, YT_FLOOR + 22)],
                   held=both(held_at("N", 10), held_at("F", 10)), floor=False),
    "pec-deck-fly": S(pec_deck_scene, pec_deck_poses(), PEC_FRAME, m=12),
    "reverse-pec-deck": S(reverse_deck_scene, reverse_deck_poses(), PEC_FRAME, m=12),
}
