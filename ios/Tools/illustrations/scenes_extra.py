"""Extra scenes for the realistic exercise art (#170): machines and variations added to the catalog later
(assisted / weighted dips, EZ-bar work, preacher and arm machines, shoulder press, calf machine, T-bar row,
GHD, reverse hyper, stability-ball crunch, jump rope).

Same conventions as scenes.py: angles 0 = right, 90 = down; the figure faces right in side view. Poses pin
the hip (B()) and solve arms / legs with two-link IK so hands land on handles and feet on the floor or
platform; static equipment is drawn in absolute view-box coordinates and moving parts (levers, carriages,
weight-stack plates) follow the figure's joints. Views are fitted around every frame with fit().
"""
import math

import art
import kit
from art import GROUND
from poses import P
from scenes_lower import column, slab, step_block

F = art.F
TORSO, UPPER, FORE, HAND = F.TORSO, F.UPPER_ARM, F.FOREARM, F.HAND
THIGH, SHIN, FOOT = F.THIGH, F.SHIN, F.FOOT
FLOOR_Y = GROUND - 4  # ankle height of a foot flat on the floor


# ---- geometry / pose helpers (same model as scenes_upper.B) ----------------------------------------

def deg(v):
    return math.degrees(math.atan2(v[1], v[0]))


def lerp(a, b, k):
    if isinstance(a, tuple):
        return tuple(x + (y - x) * k for x, y in zip(a, b))
    return a + (b - a) * k


def unit(a):
    return (math.cos(math.radians(a)), math.sin(math.radians(a)))


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
    """Limb goal: grip centre (or wrist / ankle) at p, joint bent to side `bend`, optional end angle."""

    def __init__(self, p, bend=1, end=None, wrist=False):
        self.p, self.bend, self.end, self.wrist = p, bend, end, wrist


def B(hip, t, aN=None, aF=None, lN=None, lF=None, **kw):
    """Pose with the hip pinned at `hip`; limbs as angle tuples or G goals (solved by IK)."""
    sh = art.ang_pt(hip, t, TORSO)
    out = {}
    for key, spec in (("aN", aN), ("aF", aF), ("lN", lN), ("lF", lF)):
        if spec is None:
            continue
        if not isinstance(spec, G):
            out[key] = spec
            continue
        arm = key[0] == "a"
        root = sh if arm else hip
        l2 = (FORE if spec.wrist else FORE + HAND / 2) if arm else SHIN
        u, f = ik(root, spec.p, UPPER if arm else THIGH, l2, spec.bend)
        out[key] = (u, f, spec.end) if spec.end is not None else (u, f)
    return P(t=t, pin=("hip", hip), **out, **kw)


def place(pose):
    j = F.place(pose)
    if art.view_of(pose) != "side":
        art.frontal(j)
    return j


def chest_pt(hip, t, u=0.8, out=16):
    d = unit(t)
    return art.add(art.add(hip, d, u * TORSO), (-d[1], d[0]), out)


def seq(fn, ks=(0, 0.5, 1)):
    return [fn(k) for k in ks]


# ---- framing (as scenes_upper.fit) -------------------------------------------------------------------

def body_points(j):
    pts = []
    hd = art.norm(art.sub(j["head"], j["neck"]))
    pts.append((art.add(j["neck"], hd, 16), 16))
    pts.append((j["neck"], 8))
    for i in range(5):
        pts.append((lerp(j["hip"], j["shoulder"], i / 4), 16))
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
    pts = []
    for p in art.frames(poses):
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
        y0 = y1 - hh if grounded else y0 - (hh - h) / 2
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
    for g in [i * 0.03 for i in range(21)]:
        for side in ("c", "l", "r"):
            v = grown(g, side)
            for c in corners:
                sc = score(v, c)
                if best is None or sc < best[0] - 0.01:
                    best = (sc, v, c)
        if best[0] < 0.5:
            break
    _, view, corner = best
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


# ---- shared drawing --------------------------------------------------------------------------------

def floor(doc, cx=200, rx=110):
    kit.floor(doc, cx, rx, x0=-200, x1=600)


def hub(doc, c, r=6):
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.38:.1f}" fill="{art.CHROME}"/>')


def grip_handle(doc, c, ang=90, half=8):
    """Rubber handle grip seen across (handle axis in the picture plane at `ang`)."""
    d = unit(ang)
    a, b = art.add(c, d, -half), art.add(c, d, half)
    doc.add(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="#0A0B0D" stroke-width="7.6" '
            f'stroke-linecap="round"/><line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" '
            f'stroke="#23272C" stroke-width="5.6" stroke-linecap="round"/>')


def back_pad(doc, hip, t, u0=0.12, u1=1.0, back=15, th=12):
    """Backrest pad behind a torso pinned at `hip` with angle t; returns its top and bottom points."""
    d = unit(t)
    n = (-d[1], d[0])
    a = art.add(art.add(hip, d, u1 * TORSO), n, -(back + th))
    b = art.add(art.add(hip, d, u0 * TORSO), n, -(back + th))
    art.pad(doc, a, b, th)
    return a, b


_LEVELS = {}


def levels_of(ex_id):
    if not _LEVELS:
        import generate
        for k, ex in generate.catalog().items():
            _LEVELS[k] = art.muscle_levels(ex)
    return _LEVELS.get(ex_id, {})


def redraw_near_arm(doc, j, ex_id):
    """Draw the near arm again (over equipment drawn in front of the trunk, e.g. a preacher pad)."""
    near = art.body_segments(j)[2]
    lv = levels_of(ex_id)
    for name in ("upper", "fore", "hand"):
        sg = near[name]
        d = art.draw_segment(doc, sg, art.SKIN_NEAR)
        art.draw_muscles(doc, sg, name, lv, d, False, "side")


def seat(doc, hip, x0=-30, x1=30, post=0):
    """Seat pad under a sitting hip on a post to the floor."""
    art.tube(doc, (hip[0] + post, hip[1] + 26), (hip[0] + post, GROUND - 2), 9, "butt")
    art.pad(doc, (hip[0] + x0, hip[1] + 26), (hip[0] + x1, hip[1] + 26), 12)


# ==== curls / triceps on a preacher-style pad =======================================================

PR_HIP = (150, 200)
PR_T = -68
PR_SH = art.ang_pt(PR_HIP, PR_T, TORSO)


def arm_pad(upper, u0=0.12, u1=1.14, off=9):
    """Contact line of a pad under an upper arm at angle `upper` from the shoulder (underside of the arm)."""
    d = unit(upper)
    n = (-d[1], d[0])  # underside of an arm pointing down-forward
    a = art.add(art.add(PR_SH, d, u0 * UPPER), n, off)
    b = art.add(art.add(PR_SH, d, u1 * UPPER), n, off)
    return a, b


def arm_pose(upper, fore, far=(-3, -1), hand=None):
    """Seated, upper arms on the pad at `upper`, forearms at `fore`."""
    aN = (upper, fore) if hand is None else (upper, fore, hand)
    aF = (upper + 1, fore + 1) if hand is None else (upper + 1, fore + 1, hand)
    return B(PR_HIP, PR_T, aN=aN, aF=aF, lN=G((PR_HIP[0] + 58, FLOOR_Y), -1, end=0),
             lF=G((PR_HIP[0] + 52, FLOOR_Y), -1, end=0), h=-72 if fore > -40 else -80)


def preacher_bench(doc, upper, pad_t=15):
    a, b = arm_pad(upper)
    elbow = art.ang_pt(PR_SH, upper, UPPER)
    seat(doc, PR_HIP, -32, 26)
    # Pad on a stem down to the floor beam (between the knees), beam back to the seat post.
    d = art.norm(art.sub(b, a))
    n = (-d[1], d[0])
    under = art.add(lerp(a, b, 0.62), n, pad_t)
    foot = (under[0] + 30, GROUND - 2)
    art.tube(doc, under, foot, 9, "butt")
    kit.feet(doc, PR_HIP[0] - 34, foot[0] + 26)
    return under


def preacher_pad(doc, j, upper, ex_id, pad_t=15):
    """Arm pad in front of the trunk and thighs, the near arm redrawn lying on it."""
    a, b = arm_pad(upper)
    slab(doc, a, b, pad_t, art.ang_pt(PR_SH, upper, UPPER))
    redraw_near_arm(doc, j, ex_id)


def db_preacher_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 100)
        preacher_bench(doc, PR_UP)
        art.db_end(doc, kit.grip(j, "F"), 9.5)
    else:
        preacher_pad(doc, j, PR_UP, "db-preacher-curl")
        art.db_end(doc, kit.grip(j), 10)


PR_UP = 38  # upper-arm angle on the preacher pad


def preacher_poses():
    return [arm_pose(PR_UP, f) for f in (74, -6, -88)]


# -- selectorized arm machines (curl / triceps extension): elbows on the cam axis, stack behind the seat
AM_STACK_X = 62
AM_TOP = 96


def arm_machine(ex_id, upper, fore0, sign):
    """Scene for an arm machine with the upper arm on a pad at `upper`; the cam turns with the forearm
    (sign +1: curling = forearm turning anticlockwise on screen lifts the stack)."""
    def scene(doc, j, layer):
        elbow, g = j["elbowN"], kit.grip(j)
        fa = deg(art.sub(j["wristN"], elbow))
        turn = sign * (fore0 - fa)
        lift = max(0.0, turn * 0.16)
        if layer == "back":
            floor(doc, 170, 130)
            p = column(doc, AM_STACK_X, AM_TOP, lift, 11)
            under = preacher_bench(doc, upper)
            # Cable: stack → top pulley → down the column → floor pulleys → up the pad stem to the cam.
            px = AM_STACK_X + 34 + 12
            art.pulley(doc, (px, GROUND - 16), 5.5)
            art.cable(doc, [(p[0] + 5.5, p[1]), (px + 5.5, p[1]), (px + 5.5, GROUND - 16)])
            art.cable(doc, [(px, GROUND - 10.5), (under[0] + 24, GROUND - 10.5)])
            # Cam and lever arm (far side) from the elbow axis.
            art.tube(doc, elbow, kit.grip(j, "F"), 6)
        else:
            preacher_pad(doc, j, upper, ex_id)
            cam = art.add(elbow, (0, 0))
            doc.add(f'<circle cx="{cam[0]:.1f}" cy="{cam[1]:.1f}" r="11" fill="#2A2E34" fill-opacity="0.92" '
                    f'stroke="#0A0B0D" stroke-width="0.9"/>')
            hub(doc, cam, 4.5)
            art.tube(doc, elbow, art.add(g, art.norm(art.sub(g, elbow)), -2), 6)
            grip_handle(doc, g, fa + 90, 7)
    return scene


def machine_curl_poses():
    return [arm_pose(PR_UP, f) for f in (68, -8, -86)]


TX_UP = 30  # triceps machine: upper arms flatter on the pad


def triceps_poses():
    return [arm_pose(TX_UP, f, hand=None) for f in (-118, -46, 26)]


# ==== EZ bar ========================================================================================

def ez_bar(doc, c, r=19):
    """EZ bar end-on: smaller plate on the sleeve."""
    kit.barbell(doc, c, r)


def ez_curl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 46)
    else:
        ez_bar(doc, kit.grip(j))


ST_ANK = (200, FLOOR_Y)


def ez_curl_poses():
    def f(fore, hand):
        return P(aN=(92 if fore > 0 else 88, fore, hand), aF=(95, fore + 3, hand + 2), lF=(92, 88, 0), h=-86,
                 pin=("ankleN", ST_ANK))
    return [f(86, 80), f(12, 4), f(-60, -70)]


SK_BENCH = dict(x0=96, x1=226, top=222)
SK_HIP = (210, SK_BENCH["top"] - 15)


def skull_pose(fore, upper=-104):
    return P(t=177, h=180, lN=(-4, 92, 0), lF=(0, 88, 4), aN=(upper, fore), aF=(upper - 2, fore - 2),
             pin=("hip", SK_HIP))


def skull_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 170, 120)
        kit.flat_bench(doc, SK_BENCH["x0"], SK_BENCH["x1"], SK_BENCH["top"])
    else:
        ez_bar(doc, kit.grip(j))


# ==== machine shoulder press ========================================================================

MS_HIP = (186, 190)
MS_T = -95
MS_SH = art.ang_pt(MS_HIP, MS_T, TORSO)
MS_S = (MS_SH[0] + 17, MS_SH[1] - 9)   # handles at shoulder height
MS_E = (MS_SH[0] + 6, MS_SH[1] - 80)   # arms extended


def _pivot(s, e, k, behind=True):
    """Point on the perpendicular bisector of s-e, k px from its midpoint (on the left side if behind)."""
    m = lerp(s, e, 0.5)
    d = art.norm(art.sub(e, s))
    n = (-d[1], d[0])
    if (n[0] > 0) == behind:
        n = (-n[0], -n[1])
    return art.add(m, n, k)


MS_P = _pivot(MS_S, MS_E, 64)
MS_R = kit.dist(MS_P, MS_S)
MS_A0, MS_A1 = deg(art.sub(MS_S, MS_P)), deg(art.sub(MS_E, MS_P))
MS_KNEE = (MS_SH[0] + 2, MS_SH[1] - 60)  # bend of the J-shaped lever (over the head) in the start frame
MS_KR, MS_KA = kit.dist(MS_P, MS_KNEE), deg(art.sub(MS_KNEE, MS_P))
MS_STACK_X = 44


def ms_poses():
    def f(k):
        g = art.ang_pt(MS_P, lerp(MS_A0, MS_A1, k), MS_R)
        return B(MS_HIP, MS_T, aN=G(g, 1), aF=G((g[0] - 3, g[1] - 1), 1),
                 lN=G((MS_HIP[0] + 60, FLOOR_Y), -1, end=0), lF=G((MS_HIP[0] + 52, FLOOR_Y), -1, end=0), h=-92)
    return seq(f, (0, 0.45, 1))


def ms_scene(doc, j, layer):
    g = kit.grip(j)
    rot = deg(art.sub(g, MS_P)) - MS_A0
    knee = art.ang_pt(MS_P, MS_KA + rot, MS_KR)
    if layer == "back":
        floor(doc, 170, 120)
        lift = max(0.0, -rot * 0.9)
        p = column(doc, MS_STACK_X, 40, lift, 11)
        # Frame: column top beam to the pivot post behind the backrest.
        post_x = MS_P[0]
        art.tube(doc, (MS_STACK_X + 46, 36), (post_x + 6, 36), 8)
        art.tube(doc, (post_x, 36), (post_x, GROUND - 2), 9, "butt")
        art.cable(doc, [(p[0] + 5.5, p[1]), (post_x - 6, p[1])])
        a, b = back_pad(doc, MS_HIP, MS_T, 0.1, 1.08)
        art.tube(doc, art.add(b, (2, -4)), (post_x, b[1] - 4), 7)
        art.tube(doc, art.add(a, (2, 4)), (post_x, a[1] + 4), 6)
        seat(doc, MS_HIP, -30, 34, 2)
        kit.feet(doc, MS_STACK_X - 6, MS_HIP[0] + 50)
        # J-shaped levers from the pivot over the shoulders to the handles (far one first).
        gf = kit.grip(j, "F")
        art.tube(doc, MS_P, art.add(knee, (-2, 1)), 6)
        art.tube(doc, art.add(knee, (-2, 1)), gf, 6)
        art.tube(doc, MS_P, knee, 7)
        art.tube(doc, knee, art.add(g, art.norm(art.sub(g, knee)), 4), 7)
        hub(doc, MS_P, 7)
    else:
        grip_handle(doc, g, deg(art.sub(g, knee)) + 90, 7)


# ==== dips ==========================================================================================

def dip_poses(grip, legs, ks=(0, 0.5, 1), drop=44):
    """Dip on parallel handles at `grip`: shoulders from straight-arm support down `drop` px, slight lean."""
    out = []
    for k, lg in zip(ks, legs):
        s = (grip[0] - 2 + 12 * k, grip[1] - 80 + drop * k)
        t = -86 + 18 * k
        hip = art.ang_pt(s, t + 180, TORSO)
        out.append(B(hip, t, aN=G(grip, 1), aF=G((grip[0] - 2, grip[1] + 1), 1), h=t + 6, lN=lg[0], lF=lg[1]))
    return out


# -- weighted dip: dip belt, chain, plate hanging between the legs
WD_Y = 140
WD_GRIP = (206, WD_Y - 5)


def wd_plate(j):
    belt = chest_pt(j["hip"], j["_t"], 0.06, 15)
    return belt, (belt[0] + 2, j["hip"][1] + 74)


def weighted_dip_scene(doc, j, layer):
    belt, c = wd_plate(j)
    if layer == "back":
        floor(doc, 200, 90)
        kit.dip_bars(doc, 150, 262, WD_Y)
        art.plate(doc, c, 17)
        art.cable(doc, [belt, (c[0], c[1] - 4)])
    else:
        # Belt round the hips, chain to the plate.
        hip, t = j["hip"], j["_t"]
        back = chest_pt(hip, t, 0.06, -16)
        doc.add(f'<line x1="{back[0]:.1f}" y1="{back[1]:.1f}" x2="{belt[0]:.1f}" y2="{belt[1]:.1f}" stroke="#1B1D20" '
                f'stroke-width="5" stroke-linecap="round"/>')
        doc.add(f'<polyline points="{belt[0]:.1f},{belt[1]:.1f} {c[0]:.1f},{c[1] - 15:.1f}" fill="none" stroke="#9AA3AD" '
                f'stroke-width="2.2" stroke-dasharray="2.5 1.5"/>')
        hub(doc, belt, 2.6)


WD_LEGS = [((98, 150, 140), (92, 154, 144)), ((100, 152, 140), (94, 156, 144)), ((104, 156, 142), (98, 160, 146))]


# -- machine-assisted dip: knees on a pad lever that the counterweight pushes up
AD_GRIP = (224, 136)
AD_COL = 96          # main column (stack to its left)
AD_PIV = (112, 212)  # knee-pad lever pivot on the column


def circle_hit(c0, r0, c1, r1, pick_right=True):
    d = kit.dist(c0, c1)
    a = (r0 * r0 - r1 * r1 + d * d) / (2 * d)
    h = math.sqrt(max(0.0, r0 * r0 - a * a))
    m = art.add(c0, art.norm(art.sub(c1, c0)), a)
    n = art.norm((-(c1[1] - c0[1]), c1[0] - c0[0]))
    p1, p2 = art.add(m, n, h), art.add(m, n, -h)
    return max(p1, p2) if pick_right else min(p1, p2)


def ad_knee0():
    s = (AD_GRIP[0] - 2, AD_GRIP[1] - 80)
    hip = art.ang_pt(s, -86 + 180, TORSO)
    return art.ang_pt(hip, 97, THIGH)


AD_R = kit.dist(AD_PIV, ad_knee0())
AD_HORN_X = art.add(AD_PIV, art.norm(art.sub(ad_knee0(), AD_PIV)), 30)[0]


def ad_poses():
    out = []
    for k in (0, 0.5, 1):
        s = (AD_GRIP[0] - 2 + 12 * k, AD_GRIP[1] - 80 + 44 * k)
        t = -86 + 18 * k
        hip = art.ang_pt(s, t + 180, TORSO)
        knee = circle_hit(hip, THIGH, AD_PIV, AD_R)
        th = deg(art.sub(knee, hip))
        sh = deg(art.sub(AD_PIV, knee)) - 1
        out.append(B(hip, t, aN=G(AD_GRIP, 1), aF=G((AD_GRIP[0] - 2, AD_GRIP[1] + 1), 1), h=t + 6,
                     lN=(th, sh, sh + 6), lF=(th - 2, sh + 1, sh + 7)))
    return out


def assisted_dip_scene(doc, j, layer):
    knee = j["kneeN"]
    ld = art.norm(art.sub(AD_PIV, knee))      # along the shins, towards the pivot
    dn = (-ld[1], ld[0]) if ld[0] < 0 else (ld[1], -ld[0])
    if dn[1] < 0:
        dn = (-dn[0], -dn[1])                  # below the shins
    top_a = art.add(art.add(knee, ld, -6), dn, 8)
    top_b = art.add(top_a, ld, 52)
    if layer == "back":
        floor(doc, 170, 130)
        k0 = ad_knee0()
        lift = max(0.0, (knee[1] - k0[1]) * 0.9)
        # Stack in its shroud left of the main column, top beam with chin-up handles.
        x = AD_COL - 50
        art.shroud(doc, x - 5, 70, GROUND - 4, 44)
        st = art.stack(doc, x, 84, GROUND - 4, 34, 11, lift)
        art.tube(doc, (AD_COL, GROUND - 2), (AD_COL, 30), 11, "butt")
        art.tube(doc, (x - 10, 30), (AD_GRIP[0] + 10, 30), 9)
        art.tube(doc, (AD_GRIP[0] + 4, 30), (AD_GRIP[0] + 14, 46), 5)
        kit.feet(doc, x - 14, AD_GRIP[0] + 10)
        # Cable: stack → pulley on the beam → down to the lever horn behind the pivot.
        horn = art.add(AD_PIV, ld, -30)
        px = AD_HORN_X
        art.pulley(doc, (st[0], 38), 5.5)
        art.pulley(doc, (px - 5.5, 38), 5.5)
        art.cable(doc, [st, (st[0], 32.5), (px - 5.5, 32.5)])
        art.cable(doc, [(px, 38), (px, horn[1])])
        hub(doc, horn, 3.5)
        # Dip handles on an arm from the main column.
        art.tube(doc, (AD_COL, AD_GRIP[1] + 2), (AD_GRIP[0] + 12, AD_GRIP[1] + 2), 7)
        art.tube(doc, (AD_COL, AD_GRIP[1] + 40), (AD_COL + 40, AD_GRIP[1] + 2), 5)
        # Knee-pad lever.
        pad_mid = lerp(top_a, top_b, 0.5)
        art.tube(doc, AD_PIV, art.add(pad_mid, dn, 10), 8)
        hub(doc, AD_PIV, 7)
    else:
        grip_handle(doc, AD_GRIP, 0, 9)
        slab(doc, top_a, top_b, 13, knee)


# ==== chest-supported T-bar row =====================================================================

TB_T = -38
TB_HIP = (150, 163)
TB_SH = art.ang_pt(TB_HIP, TB_T, TORSO)
TB_G0 = (TB_SH[0] + 9, TB_SH[1] + 79)            # arms long
TB_G1 = chest_pt(TB_HIP, TB_T, 0.36, 34)         # handles pulled to the bottom of the pad
TB_FOOT = (TB_HIP[0] - 46, GROUND - 16)          # ankles on the foot platform


TB_P = (TB_FOOT[0] - 12, GROUND - 10)  # lever pivot on the floor behind the foot platform
TB_R = kit.dist(TB_P, TB_G0)
TB_A0 = deg(art.sub(TB_G0, TB_P))
TB_A1 = math.degrees(math.asin((TB_G1[1] - TB_P[1]) / TB_R))  # rotated until the handles reach the pad


def tb_pad_face(u0=0.46, u1=1.06, out=15):
    d = unit(TB_T)
    n = (-d[1], d[0])
    return art.add(art.add(TB_HIP, d, u0 * TORSO), n, out), art.add(art.add(TB_HIP, d, u1 * TORSO), n, out)


def tbar_poses():
    def f(k):
        g = art.ang_pt(TB_P, lerp(TB_A0, TB_A1, k), TB_R)
        return B(TB_HIP, TB_T, aN=G(g, 1), aF=G((g[0] - 3, g[1] - 1), 1),
                 lN=G(TB_FOOT, -1, end=-8), lF=G((TB_FOOT[0] - 5, TB_FOOT[1]), -1, end=-8), h=-14)
    return seq(f)


def tbar_scene(doc, j, layer):
    g = kit.grip(j)
    d = art.norm(art.sub(g, TB_P))
    tip = art.add(g, d, 34)
    if layer == "back":
        floor(doc, 170, 120)
        a, b = tb_pad_face()
        under = art.add(lerp(a, b, 0.4), (unit(TB_T)[1], -unit(TB_T)[0]), -16)
        # Frame: base rail, pad post, foot platform.
        kit.feet(doc, TB_P[0] - 30, under[0] + 60)
        art.tube(doc, under, (under[0] + 14, GROUND - 2), 9, "butt")
        art.tube(doc, (TB_FOOT[0] - 22, GROUND - 9), (TB_P[0] + 4, GROUND - 9), 7)
        step_block(doc, TB_FOOT[0] - 24, 46, 12)
        # Lever from the floor pivot through the handles to the loading horn.
        art.tube(doc, TB_P, tip, 7)
        art.tube(doc, art.add(tip, d, -12), art.add(tip, d, 6), 9)
        art.plate(doc, art.add(tip, d, -4), 22)
        hub(doc, TB_P, 6)
        doc.add(f'<rect x="{TB_P[0] - 12:.1f}" y="{GROUND - 8:.1f}" width="24" height="8" rx="2" fill="#2A2E34"/>')
    else:
        a, b = tb_pad_face()
        slab(doc, a, b, 15, TB_HIP)
        redraw_near_arm(doc, j, "t-bar-row")
        grip_handle(doc, g, deg(d) + 90, 8)


# ==== standing calf raise machine ===================================================================

CM_TOE = (214, GROUND - 16)
CM_RAIL = 150          # vertical guide the shoulder carriage slides on
CM_STACK_X = 72


def cm_pose(f):
    ank = art.ang_pt(CM_TOE, f, -FOOT)
    hip = (ank[0] - 2, ank[1] - THIGH - SHIN + 0.5)
    sh = art.ang_pt(hip, -90, TORSO)
    g = (sh[0] + 12, sh[1] - 10)
    return B(hip, -90, aN=G(g, 1), aF=G((g[0] - 3, g[1]), 1), lN=G(ank, -1, end=f), lF=G((ank[0] - 3, ank[1]), -1, end=f),
             h=-90)


CM_Y0 = place(cm_pose(-24))["shoulder"][1]


def cm_scene(doc, j, layer):
    sh = j["shoulder"]
    pad_y = sh[1] - 10
    if layer == "back":
        floor(doc, 190, 110)
        lift = max(0.0, (CM_Y0 - sh[1]) * 1.6)
        p = column(doc, CM_STACK_X, 40, lift, 10)
        # Guide rail + carriage, cable from the carriage under the floor pulleys up to the stack.
        art.tube(doc, (CM_RAIL, GROUND - 2), (CM_RAIL, 36), 9, "butt")
        art.tube(doc, (CM_STACK_X - 8, 36), (CM_RAIL + 6, 36), 8)
        kit.feet(doc, CM_STACK_X - 14, CM_TOE[0] + 50)
        px = CM_STACK_X + 46
        art.pulley(doc, (px, GROUND - 16), 5.5)
        art.pulley(doc, (CM_RAIL - 8, GROUND - 16), 5.5)
        art.cable(doc, [(p[0] + 5.5, p[1]), (px + 5.5, p[1]), (px + 5.5, GROUND - 16)])
        art.cable(doc, [(px, GROUND - 10.5), (CM_RAIL - 8, GROUND - 10.5)])
        art.cable(doc, [(CM_RAIL - 13.5, GROUND - 16), (CM_RAIL - 13.5, pad_y + 18)])
        doc.add(f'<rect x="{CM_RAIL - 10:.1f}" y="{pad_y - 12:.1f}" width="20" height="34" rx="3" fill="#2A2E34" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')
        art.tube(doc, (CM_RAIL, pad_y + 2), (sh[0] - 6, pad_y + 2), 8)
        step_block(doc, CM_TOE[0] - 12, 50, GROUND - CM_TOE[1] - 1)
    else:
        # Shoulder pad on top of the shoulder, handle in front of it.
        art.pad(doc, (sh[0] - 16, pad_y + 2), (sh[0] + 14, pad_y + 2), 11)
        art.tube(doc, (sh[0] + 10, pad_y - 2), (sh[0] + 16, pad_y - 2), 5)
        grip_handle(doc, kit.grip(j), 90, 7)


# ==== glute-ham raise (GHD) =========================================================================

GH_KNEE = (160, 146)
GH_SHIN = 172
GH_PAD = (GH_KNEE[0] + 15, GH_KNEE[1] + 15)
GH_ANK = art.ang_pt(GH_KNEE, GH_SHIN, SHIN)


def gh_pose(th, t, h):
    hip = art.ang_pt(GH_KNEE, th + 180, THIGH)
    leg = (th, GH_SHIN, GH_SHIN - 90)
    return B(hip, t, lN=leg, lF=(th, GH_SHIN + 1, GH_SHIN - 89), aN=G(chest_pt(hip, t, 0.8, 14), 1),
             aF=G(chest_pt(hip, t, 0.8, 10), 1), h=h)


def gh_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 120)
        sole = art.ang_pt(GH_ANK, GH_SHIN, 7)
        # Frame: long base, post under the thigh pad, post under the foot plate.
        kit.feet(doc, sole[0] - 30, GH_PAD[0] + 70)
        art.tube(doc, (GH_PAD[0] + 4, GH_PAD[1]), (GH_PAD[0] + 30, GROUND - 2), 10, "butt")
        art.tube(doc, (sole[0] + 2, GH_ANK[1] + 6), (sole[0] + 10, GROUND - 2), 9, "butt")
        art.tube(doc, (sole[0] + 10, GH_ANK[1] + 28), (GH_PAD[0] + 8, GH_PAD[1] + 16), 8)
        # Foot plate behind the soles and the round thigh pad.
        doc.add(f'<rect x="{sole[0] - 8:.1f}" y="{GH_ANK[1] - 8:.1f}" width="7" height="38" rx="2" fill="#2A2E34" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')
        g = doc.lin((GH_PAD[0] - 13, GH_PAD[1] - 13), (GH_PAD[0] + 13, GH_PAD[1] + 13), [(0, art.PAD[0]), (1, art.PAD[2])])
        doc.add(f'<circle cx="{GH_PAD[0]:.1f}" cy="{GH_PAD[1]:.1f}" r="15" fill="{g}" stroke="#0A0B0D" stroke-width="0.9"/>')
        kit.roller_pad(doc, art.add(GH_ANK, (5, 12)), 6.5)
    else:
        kit.roller_pad(doc, art.add(GH_ANK, (3, -12)), 6.5)


# ==== reverse hyper =================================================================================

RH_HIP = (148, 128)
RH_PIV = (RH_HIP[0] + 10, RH_HIP[1] + 30)
RH_LEG = THIGH + SHIN


def rh_heel(a):
    """Back of the ankles (where the strap / roller sits) with the straight legs at angle a."""
    ank = art.ang_pt(RH_HIP, a, RH_LEG)
    return art.add(ank, unit(a - 90), 8)


RH_L = kit.dist(RH_PIV, rh_heel(90)) - 4


def rh_pose(a):
    sh = art.ang_pt(RH_HIP, 0, TORSO)
    g = (sh[0] + 24, RH_HIP[1] + 34)
    return B(RH_HIP, 0, lN=(a, a, a - 92), lF=(a - 3, a - 3, a - 95), aN=G(g, -1), aF=G((g[0] - 3, g[1]), -1), h=6)


def rh_scene(doc, j, layer):
    a = deg(art.sub(j["ankleN"], j["hip"]))
    heel = rh_heel(a)
    d = art.norm(art.sub(heel, RH_PIV))
    end = art.add(RH_PIV, d, RH_L)
    horn = art.add(RH_PIV, d, RH_L * 0.55)
    if layer == "back":
        floor(doc, 170, 110)
        # Pad on a column, frame to the front handles.
        top = RH_HIP[1] + 15
        x0, x1 = RH_HIP[0] - 8, RH_HIP[0] + 86
        art.tube(doc, (x0 + 46, top + 12), (x0 + 46, GROUND - 2), 10, "butt")
        art.tube(doc, (x0 + 46, top + 26), RH_PIV, 8)
        kit.feet(doc, RH_HIP[0] - 70, x1 + 46)
        hx = x1 + 22
        art.tube(doc, (hx, GROUND - 2), (hx, top + 6), 8, "butt")
        art.tube(doc, (x0 + 46, top + 18), (hx, top + 18), 7)
        art.pad(doc, (x0, top + 13), (x1, top + 13), 13)
        # Pendulum: plates on its horn, roller behind the ankles.
        art.tube(doc, RH_PIV, end, 7)
        art.tube(doc, art.add(horn, d, -8), art.add(horn, d, 8), 4)
        art.plate(doc, horn, 18)
        hub(doc, RH_PIV, 6.5)
    else:
        kit.roller_pad(doc, end, 7)
        g = kit.grip(j)
        grip_handle(doc, g, 0, 8)


# ==== stability-ball crunch =========================================================================

BC_R = 40
BC_C = (172, GROUND - BC_R)
BC_HIP_X = 202
BC_ANK = (266, FLOOR_Y)


def bc_pose(t, curl, h):
    """Hip lowered until the lower back rests on the ball."""
    def make(y):
        hip = (BC_HIP_X, y)
        # Fingertips by the ears (hands do not pull the head), elbows open.
        sh = art.ang_pt(hip, t, TORSO)
        neck = art.ang_pt(sh, h, F.NECK)
        ear = art.add(art.ang_pt(neck, h, 11), unit(h - 90), -3)
        return B(hip, t, curl=curl, lN=G(BC_ANK, -1, end=0), lF=G((BC_ANK[0] - 6, BC_ANK[1]), -1, end=0), h=h,
                 aN=G(ear, 1, wrist=True), aF=G(art.add(ear, unit(h - 90), -2), 1, wrist=True))

    def clearance(y):
        hip = (BC_HIP_X, y)
        d = unit(t)
        back = (d[1], -d[0])  # back of the torso (front is (-d.y, d.x))
        best = 1e9
        for i in range(0, 8):
            u = i / 10
            w = 15.5 - 6 * u
            pnt = art.add(art.add(hip, d, u * TORSO), back, w)
            best = min(best, kit.dist(pnt, BC_C) - BC_R)
        return best

    lo, hi = BC_C[1] - 120.0, BC_C[1]
    for _ in range(40):
        mid = (lo + hi) / 2
        if clearance(mid) > 0:
            lo = mid
        else:
            hi = mid
    return make(lo + 1)


def ball_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 210, 110)
        kit.mat(doc, 110, 300)
        c = (BC_C[0], BC_C[1] - 4)
        g = doc.lin((c[0] - BC_R, c[1] - BC_R), (c[0] + BC_R, c[1] + BC_R), [(0, "#5DA9E9"), (0.6, "#2F6FB0"), (1, "#1D4472")])
        doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{BC_R}" fill="{g}" stroke="#0A0B0D" stroke-width="0.9"/>'
                f'<path d="M{c[0] - BC_R + 6:.1f},{c[1] - 10:.1f} Q{c[0]:.1f},{c[1] + 8:.1f} {c[0] + BC_R - 6:.1f},{c[1] - 10:.1f}" '
                f'fill="none" stroke="#fff" stroke-opacity="0.18" stroke-width="1.2"/>'
                f'<ellipse cx="{c[0] - 14:.1f}" cy="{c[1] - 20:.1f}" rx="10" ry="6" fill="#fff" fill-opacity="0.22" '
                f'transform="rotate(-30 {c[0] - 14:.1f} {c[1] - 20:.1f})"/>')


# ==== jump rope =====================================================================================

JR_TOE = (214, GROUND - 2)


def jr_pose(f, lift, knee, apex):
    ank = art.add(art.ang_pt(JR_TOE, f, -FOOT), (0, -lift))
    hip = (ank[0] - 6 + knee * 0.3, ank[1] - THIGH - SHIN + 2 + knee)
    sh = art.ang_pt(hip, -86, TORSO)
    g = (sh[0] + 22, sh[1] + 74)
    p = B(hip, -86, aN=G(g, -1), aF=G((g[0] - 4, g[1] - 1), -1), lN=G(ank, -1, end=f),
          lF=G((ank[0] - 4, ank[1] + (2 if lift == 0 else 0)), -1, end=f + 4), h=-88)
    p["curl"] = apex * 1e-6  # carries the rope apex angle to the scene (invisible bow)
    return p


def jr_rope(j):
    """Near-hand handle tip, rope apex and a control point (the strand lags behind the turn)."""
    g = kit.grip(j)
    phi = j["_curl"] * 1e6
    tip = art.add(g, (6, 6))
    if phi > 80:  # under the feet
        apex = (tip[0] - 10, GROUND - 2)
    else:
        apex = art.ang_pt(tip, phi, 130)
    m = lerp(tip, apex, 0.5)
    d = art.norm(art.sub(apex, tip))
    ctrl = art.add(m, (d[1], -d[0]), 0.36 * kit.dist(tip, apex))
    return tip, ctrl, apex


def rope_line(doc, j, op=1.0):
    tip, ctrl, apex = jr_rope(j)
    doc.add(f'<path d="M{tip[0]:.1f},{tip[1]:.1f} Q{ctrl[0]:.1f},{ctrl[1]:.1f} {apex[0]:.1f},{apex[1]:.1f}" fill="none" '
            f'stroke="#16181B" stroke-opacity="{op}" stroke-width="2.4" stroke-linecap="round"/>')


def jr_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 214, 50)
        rope_line(doc, j, 0.7)
    else:
        rope_line(doc, j)
        g = kit.grip(j)
        grip_handle(doc, art.add(g, (2, 3)), 45, 7)


SCENES = {
    "ez-bar-curl": S(ez_curl_scene, ez_curl_poses(), [], held_at("N", 21)),
    "ez-skullcrusher": S(skull_scene, [skull_pose(-100), skull_pose(-146), skull_pose(-192)],
                         [(SK_BENCH["x0"], SK_BENCH["top"], SK_BENCH["x1"], GROUND)], held_at("N", 21)),
    "db-preacher-curl": S(db_preacher_scene, preacher_poses(), [(PR_HIP[0] - 34, 150, 260, GROUND)], held_at("N", 11)),
    "machine-curl": S(arm_machine("machine-curl", PR_UP, 68, 1), machine_curl_poses(),
                      [(AM_STACK_X - 10, AM_TOP - 10, 260, GROUND)], held_at("N", 10)),
    "machine-triceps-extension": S(arm_machine("machine-triceps-extension", TX_UP, -118, -1), triceps_poses(),
                                   [(AM_STACK_X - 10, AM_TOP - 10, 260, GROUND)], held_at("N", 10)),
    "machine-shoulder-press": S(ms_scene, ms_poses(), [(MS_STACK_X - 10, 30, MS_HIP[0] + 50, GROUND)], held_at("N", 10)),
    "weighted-dip": S(weighted_dip_scene, dip_poses(WD_GRIP, WD_LEGS), [(140, WD_Y - 6, 272, GROUND)],
                      lambda j: [(wd_plate(j)[1], 18)]),
    "assisted-dip": S(assisted_dip_scene, ad_poses(), [(AD_COL - 64, 22, AD_GRIP[0] + 18, GROUND)]),
    "t-bar-row": S(tbar_scene, tbar_poses(), [(TB_FOOT[0] - 26, 100, 270, GROUND)], held_at("N", 26)),
    "machine-calf-raise": S(cm_scene, [cm_pose(-24), cm_pose(6), cm_pose(36)],
                            [(CM_STACK_X - 10, 30, CM_TOE[0] + 40, GROUND)]),
    "glute-ham-raise": S(gh_scene, [gh_pose(180, 0, 4), gh_pose(135, -45, -40), gh_pose(92, -88, -86)],
                         [(GH_ANK[0] - 30, GH_KNEE[1] - 10, GH_PAD[0] + 74, GROUND)]),
    "reverse-hyper": S(rh_scene, [rh_pose(90), rh_pose(136), rh_pose(180)],
                       [(RH_HIP[0] - 70, RH_HIP[1], RH_HIP[0] + 150, GROUND)],
                       lambda j: [(rh_heel(deg(art.sub(j["ankleN"], j["hip"]))), 10)]),
    "ball-crunch": S(ball_scene, [bc_pose(188, -3, 190), bc_pose(208, 3, 222), bc_pose(226, 8, 244)],
                     [(BC_C[0] - BC_R, BC_C[1] - BC_R, BC_ANK[0] + 20, GROUND)]),
    "jump-rope": S(jr_scene, [jr_pose(40, 0, 2, -100), jr_pose(32, 4, 1, 36), jr_pose(36, 12, 0, 90)], [],
                   lambda j: [(jr_rope(j)[2], 4), (jr_rope(j)[1], 4)]),
}
