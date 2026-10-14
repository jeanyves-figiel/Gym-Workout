"""Scenes for the gym app comparison (#182): advanced calisthenics.

Muscle-ups, levers, human flag, iron cross, one-arm / archer pull-ups, push-up and handstand variations,
pistols, bar holds and hanging drills. Built on the IK pose builder of scenes_upper.py (B / G: hip pinned,
hands and feet solved onto absolute targets) and its 4:3 framing (S / fit). Same conventions: angles 0 = right,
90 = down, the figure faces right in side view; static equipment (bars, rings, stall bars, wall, mat) is drawn
in absolute view-box coordinates, held equipment follows the hands. Rings and stall bars are drawn here.
"""
import math

import art
import kit
import scenes_upper as U
from art import GROUND
from poses import P

B, G, S, fit = U.B, U.G, U.S, U.fit
lerp, chest_pt, circle_x = U.lerp, U.chest_pt, U.circle_x
TORSO, UPPER, FORE, HAND = U.TORSO, U.UPPER, U.FORE, U.HAND
THIGH, SHIN = U.THIGH, U.SHIN
FLOOR_Y = U.FLOOR_Y
REACH = UPPER + FORE + HAND / 2 - 1  # shoulder → grip, arm straight
floor = U.floor


def solve(make, joint, y, lo, hi, n=44):
    """Bisect the free parameter of make(v) so that `joint` lands at height y (y grows with v)."""
    for _ in range(n):
        m = (lo + hi) / 2
        if U.place(make(m))[joint][1] < y:
            hi = m
        else:
            lo = m
    return make((lo + hi) / 2)


def from_shoulder(sh, t):
    return art.ang_pt(sh, t + 180, TORSO)


def _mix(a, b, k):
    if isinstance(a, tuple):
        return tuple(_mix(x, y, k) for x, y in zip(a, b))
    return a + (b - a) * k


def along(ctrl, s):
    """Values at progress s on a path of control dicts ctrl = [(s0, {...}), (s1, {...}), ...] (numbers / tuples)."""
    for (s0, a), (s1, b) in zip(ctrl, ctrl[1:]):
        if s <= s1 or s1 == ctrl[-1][0]:
            k = min(1, max(0, (s - s0) / ((s1 - s0) or 1)))
            return {key: _mix(a[key], b[key], k) for key in a}
    return dict(ctrl[-1][1])


def path_tweens(make):
    """tweens.EXTRA entry: every in-between solved again by make(progress) (hands kept on the bar by IK), where a
    straight interpolation of the key poses lets the grip drift off the bar."""
    def extra(keys):
        mid = art.FRAMES // 2
        return {i: make(art.progress(i)) for i in range(1, art.FRAMES - 1) if i != mid}
    return extra


def bar_dot(doc, c):
    """Bar end-on, drawn over the near hand."""
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="4.6" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="1.8" fill="{art.CHROME}"/>')


def hang_bar(c, top=-160, half=40):
    def scene(doc, j, layer):
        if layer == "back":
            kit.pullup_bar(doc, c, top=top, half=half)
        else:
            bar_dot(doc, c)
    return scene


def bar_box(c):
    return (c[0] - 46, c[1] - 30, c[0] + 10, c[1] + 8)


# ---- rings ---------------------------------------------------------------------------------------

RING_TOP = -260  # strap anchor height (off screen)


def ring_at(doc, c, anchor_x=None, side=False):
    """Gymnastic ring held at c, strap from a ceiling anchor. side=True: ring seen edge-on (side view)."""
    ax = c[0] if anchor_x is None else anchor_x
    top = (c[0], c[1] - 9)
    doc.add(f'<line x1="{ax:.1f}" y1="{RING_TOP}" x2="{top[0]:.1f}" y2="{top[1]:.1f}" stroke="#16181B" stroke-width="3.4"/>'
            f'<line x1="{ax:.1f}" y1="{RING_TOP}" x2="{top[0]:.1f}" y2="{top[1]:.1f}" stroke="#E8B32A" stroke-width="1" '
            f'stroke-dasharray="6 10"/>')
    rx = 3.6 if side else 8.5
    doc.add(f'<ellipse cx="{c[0]:.1f}" cy="{c[1]:.1f}" rx="{rx}" ry="8.5" fill="none" stroke="#3A2A18" stroke-width="5"/>'
            f'<ellipse cx="{c[0]:.1f}" cy="{c[1]:.1f}" rx="{rx}" ry="8.5" fill="none" stroke="#C8A06A" stroke-width="3.2"/>')


def ring_hand(doc, c):
    """Fingers wrapped over the ring (drawn in front of the hand)."""
    doc.add(f'<path d="M{c[0] - 5:.1f},{c[1] - 1:.1f} Q{c[0]:.1f},{c[1] + 3:.1f} {c[0] + 5:.1f},{c[1] - 1:.1f}" fill="none" '
            f'stroke="#C8A06A" stroke-width="3.2" stroke-linecap="round"/>')


def side_rings(anchor_x=None):
    """Rings in side view: far ring behind the body, near ring in front."""
    def scene(doc, j, layer):
        if layer == "back":
            ring_at(doc, kit.grip(j, "F"), anchor_x, side=True)
        else:
            ring_at(doc, kit.grip(j, "N"), anchor_x, side=True)
    return scene


# ==== muscle-up ===================================================================================

MU = (200, 120)
MU_LEGS = dict(lN=(80, 146, 124), lF=(84, 152, 130))


# Shoulder path relative to the grip (progress s: 0 hang, 0.5 transition, 1 support), solved by IK at every frame
# (path_tweens) so the hands stay on the bar: pull to the chest, turn over the bar, press out to support.
MU_PATH = [
    (0, dict(sh=(-3, REACH - 1), t=-93, h=-80, curl=0, lN=(80, 146, 124), lF=(84, 152, 130))),
    (0.25, dict(sh=(-14, 24), t=-100, h=-84, curl=0, lN=(76, 136, 112), lF=(80, 142, 118))),
    # Turnover: the shoulders rise behind the bar to above it (hand passes shoulder height in front of them, the
    # elbows drop under and behind), then come forward over it; they stay ~20 px clear of the grip throughout
    # (closer, the elbow IK flipped).
    (0.31, dict(sh=(-22, 6), t=-98, h=-82, curl=0, lN=(79, 131, 107), lF=(83, 137, 112))),
    (0.38, dict(sh=(-14, -14), t=-80, h=-64, curl=2, lN=(82, 126, 102), lF=(86, 132, 106))),
    (0.5, dict(sh=(14, -30), t=-62, h=-44, curl=3, lN=(86, 120, 96), lF=(90, 126, 100))),
    (0.75, dict(sh=(4, -58), t=-76, h=-70, curl=1, lN=(92, 106, 80), lF=(96, 110, 84))),
    (1, dict(sh=(-6, -REACH + 4), t=-86, h=-86, curl=0, lN=(96, 94, 66), lF=(100, 98, 70))),
]


def mu_at(s):
    v = along(MU_PATH, s)
    sh = (MU[0] + v["sh"][0], MU[1] + v["sh"][1])
    p = B(from_shoulder(sh, v["t"]), v["t"], aN=G(MU, 1), aF=G((MU[0] - 2, MU[1] + 1), 1), h=v["h"], curl=v["curl"],
          lN=v["lN"], lF=v["lF"])
    return recentre([p])[0]


def mu_poses():
    return [mu_at(0), mu_at(0.5), mu_at(1)]


def recentre(poses, y=150):
    """Camera follows the body: shift each frame vertically so the body is centred (bar drawn at the grip)."""
    out = []
    for p in poses:
        pts = U.body_points(U.place(p))
        cy = (min(q[1] - r for q, r in pts) + max(q[1] + r for q, r in pts)) / 2
        name, (px, py) = p["pin"]
        p = dict(p)
        p["pin"] = (name, (px, py + y - cy))
        out.append(p)
    return out


def grip_bar(doc, j, layer):
    """Pull-up bar under the near hand (frames re-centred on the body)."""
    g = kit.grip(j)
    c = (MU[0], g[1])
    if layer == "back":
        kit.pullup_bar(doc, c, top=-200, half=40)
    else:
        bar_dot(doc, c)


def weighted_mu_scene(doc, j, layer):
    grip_bar(doc, j, layer)
    if layer == "front":
        belt = chest_pt(j["hip"], j["_t"], 0.06, 12)
        pl = (j["hip"][0] + 6, j["hip"][1] + 46)
        doc.add(f'<polyline points="{belt[0]:.1f},{belt[1]:.1f} {pl[0]:.1f},{pl[1] - 14:.1f}" fill="none" stroke="#9AA3AD" '
                f'stroke-width="2" stroke-dasharray="2.5 1.5"/>')
        art.plate(doc, pl, 14)


def held_bar(j):
    g = kit.grip(j)
    return [((MU[0] - 40, g[1]), 8), ((MU[0] + 6, g[1]), 8)]


def mu_held(j):
    return [((j["hip"][0] + 6, j["hip"][1] + 46), 16)]


# ==== levers on the bar ===========================================================================

FL = (196, 110)


def lever_pose(t, arm, legs, h=None, grip=FL, curl=0):
    """Straight arms from the bar at angle `arm` (shoulder → grip), torso angle t."""
    sh = art.ang_pt(grip, arm + 180, REACH)
    return P(t=t, h=t if h is None else h, aN=(arm, arm, arm), aF=(arm - 1, arm - 1, arm - 1),
             pin=("shoulder", sh), curl=curl, **legs)


TUCK_FL = dict(lN=(-156, 16, 50), lF=(-152, 20, 54))  # knees to the chest, heels by the hips


def front_lever_poses():
    tuck = lever_pose(180, -82, TUCK_FL, h=196)
    # Advanced tuck (hips open, knees still bent): both legs extend together, no one-leg flicker between keys.
    one = lever_pose(180, -78, dict(lN=(-26, 64, 74), lF=(-22, 68, 78)), h=192)
    full = lever_pose(180, -74, dict(lN=(1, 1, 12), lF=(-1, -1, 10)), h=190)
    return [tuck, one, full]


def tuck_front_lever_poses():
    hang = lever_pose(-92, -90, dict(lN=(84, 92, 64), lF=(88, 96, 68)), h=-80)
    rise = lever_pose(-136, -86, dict(lN=(-111, 61, 95), lF=(-107, 65, 99)), h=-150)
    tuck = lever_pose(180, -82, TUCK_FL, h=196)
    return [hang, rise, tuck]


def lever_box():
    return [bar_box(FL)]


# ==== levers on the rings =========================================================================

RG = (176, 70)  # near ring centre (grip)


def ring_pose(t, arm, legs, h=None, curl=0):
    sh = art.ang_pt(RG, arm + 180, REACH)
    return P(t=t, h=t if h is None else h, aN=(arm, arm, arm), aF=(arm - 1, arm - 1, arm - 1),
             pin=("shoulder", sh), curl=curl, lit_sides="N", **legs)


def tuck_legs(t):
    """Knees pulled to the chest, heels by the hips, for a face-down torso at angle t."""
    th = t + 28
    return dict(lN=(th, th + 170, th + 205), lF=(th + 4, th + 174, th + 209))


INV_LEGS = dict(lN=(-90, -90, -100), lF=(-92, -92, -102))
TUCK_BL = tuck_legs(2)


def back_lever_poses():
    inv = ring_pose(92, -86, INV_LEGS, h=96)
    # Lowered from the inverted hang with the body kept straight (a tuck in between folded the legs away and back).
    half = ring_pose(46, -119, dict(lN=(-135, -135, -145), lF=(-133, -133, -143)), h=50)
    full = ring_pose(0, -152, dict(lN=(181, 181, 170), lF=(182, 182, 172)), h=6)
    return [inv, half, full]


def tuck_back_lever_poses():
    inv = ring_pose(90, -88, tuck_legs(90), h=94)
    mid = ring_pose(44, -122, tuck_legs(44), h=50)
    tuck = ring_pose(2, -150, TUCK_BL, h=8)
    return [inv, mid, tuck]


def rings_box():
    return [(RG[0] - 30, RG[1] - 40, RG[0] + 12, RG[1] + 10)]


# ==== iron cross (front view, rings) ==============================================================

IC_Y = 120  # ring height at the cross
IC_X = 200
IC_ANCHOR = U.SW + 8  # straps hang straight down beside the hips in support

FRONT_HANG_LEGS = dict(lN=(90, 90, 90), lF=(90, 90, 90))


def cross_pose(k):
    """k = 0 support (arms straight down), 1 = full cross (arms horizontal)."""
    a = 90 * (1 - k)  # arm angle below horizontal
    ring_y = IC_Y + 6 * (1 - k)
    sw = U.SW
    dy = REACH * math.sin(math.radians(a))
    dx = REACH * math.cos(math.radians(a))
    sh = (IC_X, ring_y - dy)
    gN = (IC_X + sw + dx, ring_y)
    gF = (IC_X - sw - dx, ring_y)
    return B(from_shoulder(sh, -90), -90, aN=G(gN, 1), aF=G(gF, -1), h=-90, front=True, **FRONT_HANG_LEGS)


def cross_poses():
    return [cross_pose(0), cross_pose(0.55), cross_pose(1)]


def cross_scene(band=False):
    def scene(doc, j, layer):
        if layer == "back":
            for s, sgn in (("N", 1), ("F", -1)):
                g = kit.grip(j, s)
                ring_at(doc, g, IC_X + sgn * IC_ANCHOR)
        else:
            for s in "NF":
                ring_hand(doc, kit.grip(j, s))
            if band:
                for s in "NF":
                    g = kit.grip(j, s)
                    ft = j["toe" + s]
                    kit.band(doc, (g[0], g[1] - 6), (ft[0], ft[1] + 3), color="#C0392B")
    return scene


def cross_box():
    w = U.SW + REACH + 12
    return [(IC_X - w, IC_Y - 30, IC_X + w, IC_Y + 14)]


def band_held(j):
    out = []
    for s in "NF":
        g, ft = kit.grip(j, s), j["toe" + s]
        out += [(lerp(g, ft, i / 6), 4) for i in range(7)]
    return out


# ==== human flag (front view, stall bars) =========================================================

HF_X = 120  # gripped upright
HF_TOP, HF_BOT = 40, 190  # hand heights on the upright


def stall_bars(doc, x, w=74, top=-80):
    """Wall bars: two uprights and round rungs; the figure grips the right upright at x."""
    wood = ("#A9774A", "#6E4A2A")
    g = doc.box_grad([(0, wood[0]), (1, wood[1])], vertical=False)
    for y in range(int(top) + 14, GROUND - 6, 17):
        doc.add(f'<rect x="{x - w:.1f}" y="{y - 2.6:.1f}" width="{w:.1f}" height="5.2" rx="2.6" fill="{g}" '
                f'stroke="#2A1B0E" stroke-width="0.6"/>')
    for xx in (x - w, x):
        doc.add(f'<rect x="{xx - 6:.1f}" y="{top}" width="12" height="{GROUND - top:.1f}" rx="2" fill="{g}" '
                f'stroke="#2A1B0E" stroke-width="0.8"/>')


def flag_pose(t, legs, h=None):
    """Front view; t = torso angle (180 = horizontal, head at the bars); top arm = near arm."""
    sh_x = HF_X + 30
    sh = (sh_x, (HF_TOP + HF_BOT) / 2 + (t + 180) * 0.0)
    return B(from_shoulder(sh, t), t, aN=G((HF_X, HF_TOP), -1), aF=G((HF_X, HF_BOT), 1),
             h=t if h is None else h, front=True, **legs)


def flag_poses():
    return [flag_pose(-140, dict(lN=(42, 42, 48), lF=(46, 46, 52))),
            flag_pose(-176, dict(lN=(-40, 36, 30), lF=(-34, 42, 36))),
            flag_pose(-180, dict(lN=(-1, -1, 4), lF=(1, 1, 6)))]


def flag_scene(doc, j, layer):
    if layer == "back":
        floor(doc, HF_X + 80, 110)
        stall_bars(doc, HF_X)
    else:
        for s in "NF":
            g = kit.grip(j, s)
            doc.add(f'<rect x="{HF_X - 6:.1f}" y="{g[1] - 3:.1f}" width="12" height="6" rx="2" fill="#8A5E37" '
                    f'fill-opacity="0.9"/>')


# ==== one-arm / archer pull-ups (back view) =======================================================

PB = (200, 70)  # bar height, centre


def wide_bar(doc, j, layer):
    if layer == "back":
        y = PB[1]
        for x in (PB[0] - 120, PB[0] + 120):
            art.tube(doc, (x, -200), (x, y), 8, "butt")
        art.tube(doc, (PB[0] - 124, y), (PB[0] + 124, y), 6)


def wide_bar_front(doc, j, layer):
    wide_bar(doc, j, layer)
    if layer == "front":
        for s in "NF":
            g = kit.grip(j, s)
            if abs(g[1] - PB[1]) < 6:
                doc.add(f'<path d="M{g[0] - 4.5:.1f},{PB[1] - 1:.1f} Q{g[0]:.1f},{PB[1] + 4:.1f} {g[0] + 4.5:.1f},{PB[1] - 1:.1f}" '
                        f'fill="none" stroke="#E2E6EB" stroke-width="3"/>')


BACK_LEGS = dict(lN=(88, 90, 90), lF=(92, 90, 90))


def back_hang(sh, gN, gF=None, t=-90, h=-90, aF=None, legs=BACK_LEGS):
    kw = dict(aN=G(gN, 1))
    kw["aF"] = G(gF, -1) if gF else aF
    return B(from_shoulder(sh, t), t, h=h, front="back", **kw, **legs)


ARCH = 70  # half grip width


# Archer: the body travels up and over to the pulling (near) hand, whose elbow bends down by the ribs; the far
# arm straightens out along the bar. Shoulder centre path, solved by IK at every frame (path_tweens).
ARCHER = [(0, dict(sh=(PB[0], PB[1] + 62), t=-90, h=-90)),
          (0.5, dict(sh=(PB[0] + 14, PB[1] + 42), t=-88, h=-88)),
          (1, dict(sh=(PB[0] + 27, PB[1] + 13), t=-86, h=-82))]


def archer_at(s):
    v = along(ARCHER, s)
    return back_hang(v["sh"], (PB[0] + ARCH, PB[1]), (PB[0] - ARCH, PB[1]), t=v["t"], h=v["h"])


def archer_poses():
    return [archer_at(0), archer_at(0.5), archer_at(1)]


def one_arm_poses():
    g = (PB[0] + 16, PB[1])
    free = [(96, 92), (94, 90), (92, 88)]
    sh = [(PB[0] + 1, PB[1] + 79), (PB[0] - 2, PB[1] + 46), (PB[0] - 6, PB[1] + 18)]
    ts = [-90, -88, -86]
    return [back_hang(s, g, aF=a, t=t, h=t) for s, a, t in zip(sh, free, ts)]


def pb_box():
    return [(PB[0] - 80, PB[1] - 34, PB[0] + 80, PB[1] + 6)]


# ==== push-up variations ==========================================================================

PU_W = (272, GROUND - 5)


def plank(arm_n, arm_f, pin="wristN", target=PU_W, toe="toeN", lN=None, lF=None, foot=80, lo=-60, hi=30, **kw):
    """Straight push-up body, hand `pin` fixed; torso angle solved so `toe` touches the floor."""
    def make(t):
        leg = (t + 180, t + 180, foot)
        return P(t=t, h=t, lN=lN(t) if lN else leg, lF=lF(t) if lF else leg, aN=arm_n, aF=arm_f,
                 pin=(pin, target), **kw)
    return solve(make, toe, GROUND - 1, lo, hi)


def one_arm_push_poses():
    def behind(t):
        return (t + 200, t + 172, t + 172)
    out = []
    for a in ((90, 90), (128, 66), (164, 52)):
        def make(t, a=a):
            leg = (t + 180, t + 180, 80)
            return P(t=t, h=t, lN=leg, lF=(t + 183, t + 183, 80), aN=a, aF=behind(t), pin=("wristN", PU_W),
                     lit_sides="N")
        out.append(solve(make, "toeN", GROUND - 1, -60, 30))
    return out


def tap_poses():
    top = plank((90, 90), (90, 90))
    bottom = plank((150, 64), (150, 64))
    # Near hand off the floor, tapping the far shoulder; weight on the far hand.
    tap = plank((90, 90), (90, 90), pin="wristF", target=(PU_W[0] - 3, PU_W[1]))
    t = tap["t"]
    tap = dict(tap)
    tap["aN"] = (t + 120, t - 132, t - 132)
    return [top, bottom, tap]


def spider_poses():
    def legs_bent(k):
        return lambda t: (t + 180 - 172 * k, t + 180 - 8 * k, t + 180 - 8 * k + 60)
    top = plank((90, 90), (90, 90))
    mid = plank((122, 68), (122, 68), toe="toeF", lN=lambda t: (t + 40, t + 172, t + 232))
    low = plank((152, 62), (152, 62), toe="toeF", lN=legs_bent(1))
    return [top, mid, low]


def spider_tweens(keys):
    """tweens.EXTRA: on the way down the hips lift a little and the near knee swings forward under the body, foot up,
    instead of dragging the knee along the floor (kneel) between the plank and the knee-to-elbow pose."""
    def pose(hip, t, legN):
        return B(hip, t, aN=G(PU_W, -1, end=80, wrist=True), aF=G((PU_W[0] - 3, PU_W[1]), -1, end=80, wrist=True),
                 lN=legN, lF=G((108, GROUND - 13), 1, end=80), h=t)
    return {art.at(0.14): pose((203, 189), -4, (126, 206, 236)),
            art.at(0.28): pose((205, 191), -7, (58, 190, 220))}


# Wall push-up: straight body leaning on the wall, hands at chest height.
WP_WALL = 262
WP_ANK = (110, FLOOR_Y)
WP_HAND = (WP_WALL - 5, 112)


def wall_push_poses():
    out = []
    for lean in (20, 28, 35):
        a = -90 + lean
        hip = art.ang_pt(WP_ANK, a, THIGH + SHIN)
        legs = a + 180
        out.append(B(hip, a, aN=G(WP_HAND, 1, end=-80), aF=G((WP_HAND[0], WP_HAND[1] + 3), 1, end=-80),
                     lN=(legs, legs, 10 + lean), lF=(legs + 1, legs + 1, 11 + lean), h=a + 4))
    return out


def wall_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 80)
        kit.wall(doc, WP_WALL, 16, top=-60)


# ==== handstand push-ups ==========================================================================

HS_W = (206, GROUND - 5)
HS_WALL = 262


def free_hspu_poses():
    out = []
    for k in (0, 0.5, 1):
        sh = (HS_W[0] + 4 - 14 * k, HS_W[1] - 80 + 54 * k)
        t = 92 - 12 * k  # hips drift over the hands as the head goes forward
        hip = from_shoulder(sh, t)
        legs = -90 - 6 * k
        out.append(B(hip, t, aN=G(HS_W, -1, end=180, wrist=True), aF=G((HS_W[0] + 3, HS_W[1]), -1, end=180, wrist=True),
                     lN=(legs, legs, legs - 12), lF=(legs + 2, legs + 2, legs - 10), h=t - 16 * k))
    return out


KH_W = (HS_WALL - 34, GROUND - 5)


def kipping_poses():
    def pose(k, legs, t_off=0):
        sh = (KH_W[0] + 2 - 12 * k, KH_W[1] - 80 + 52 * k)
        t = 90 + math.degrees(math.atan2(HS_WALL - 7 - sh[0], TORSO + THIGH + SHIN)) - 3 + t_off
        hip = from_shoulder(sh, t)
        return B(hip, t, aN=G(KH_W, -1, end=180, wrist=True), aF=G((KH_W[0] + 3, KH_W[1]), -1, end=180, wrist=True),
                 h=t - 14 * k, **legs)
    tuck = pose(1, dict(lN=(166, -84, -40), lF=(170, -80, -36)), -8)
    kick = pose(0.55, dict(lN=(-70, -62, -120), lF=(-66, -58, -116)), -2)
    top = U.place(pose(0, {}))
    hip = top["hip"]
    legs = -90 + math.degrees(math.asin(max(-1, min(1, (HS_WALL - 7 - hip[0]) / (THIGH + SHIN)))))
    lock = pose(0, dict(lN=(legs, legs - 2, legs - 70), lF=(legs + 2, legs, legs - 68)))
    return [tuck, kick, lock]


def mat_scene(x0, x1, wall=None):
    def scene(doc, j, layer):
        if layer == "back":
            floor(doc, (x0 + x1) / 2, 80)
            if wall:
                kit.wall(doc, wall, 16, top=-140)
            kit.mat(doc, x0, x1)
    return scene


# ==== pistol squat ================================================================================

PS_ANK = (206, FLOOR_Y)


def pistol_pose(hip, t, legF, reach, h=None, held=False):
    sh = art.ang_pt(hip, t, TORSO)
    g = (sh[0] + reach[0], sh[1] + reach[1])
    return B(hip, t, aN=G(g, -1 if not held else 1), aF=G((g[0] - 3, g[1] + 2), -1 if not held else 1),
             lN=G(PS_ANK, -1, end=0), lF=legF, h=t if h is None else h, lit_sides="N")


def pistol_poses(held=False):
    r = [(56, 40), (66, 22), (74, 6)] if not held else [(26, 34), (30, 30), (32, 28)]
    return [pistol_pose((206, 152), -90, (74, 80, -10), r[0], held=held),
            pistol_pose((186, 196), -66, (8, 10, -76), r[1], h=-72, held=held),
            pistol_pose((180, GROUND - 32), -50, (-8, -8, -92), r[2], h=-60, held=held)]


def pistol_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 80)


def kb_pistol_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 80)
    else:
        g = lerp(kit.grip(j, "N"), kit.grip(j, "F"), 0.5)
        kit.kettlebell(doc, (g[0] + 2, g[1] - 4), r=11)


def kb_held(j):
    g = kit.grip(j)
    return [((g[0], g[1] + 12), 14)]


# ==== bar static hold =============================================================================

SH_BAR = (204, 60)


def static_hold_poses():
    bar = SH_BAR
    legs = U.HANG_LEGS
    pull = U.hang((bar[0] - 10, bar[1] + 48), -96, legs, grip=bar, h=-92)
    top = U.hang((bar[0] - 20, bar[1] + 18), -101, legs, grip=bar, h=-83)
    low = U.hang((bar[0] - 12, bar[1] + 38), -98, legs, grip=bar, h=-88)
    return [pull, top, low]


# ==== dip-bar leg raise ===========================================================================

DB_Y = 124  # high enough for the hanging feet to clear the floor
DB_GRIP = (206, DB_Y + 3)  # hand wrapped round the bar; the near bar crosses the hips (between the bars)


def dip_leg_pose(leg, t=-88):
    return P(t=t, h=t - 2, lN=(leg, leg, leg - 70), lF=(leg + 2, leg + 2, leg - 68), aN=(97, 97, 0), aF=(98, 98, 2),
             pin=("wristN", DB_GRIP))


def dip_bar_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 210, 90)
        kit.dip_bars(doc, 150, 262, DB_Y)
    else:
        # Near bar in front of the body: hips and raised legs are between the bars, not lying on them.
        art.tube(doc, (150, DB_Y), (262, DB_Y), 7)


# ==== monkey bars =================================================================================

MB_Y = -14  # high enough that the hanging feet stay well clear of the floor
MB_RUNGS = [76 + 52 * i for i in range(6)]  # x of each rung (end-on); one rung of travel per cycle


def monkey_scene(doc, j, layer):
    if layer == "back":
        for x in (MB_RUNGS[0] - 30, MB_RUNGS[-1] + 30):
            art.tube(doc, (x, MB_Y - 2), (x, GROUND - 2), 9, "butt")
            kit.feet(doc, x - 26, x + 26)
        floor(doc, 200, 110)
        art.tube(doc, (MB_RUNGS[0] - 34, MB_Y - 7), (MB_RUNGS[-1] + 34, MB_Y - 7), 7)
        for x in MB_RUNGS:
            bar_dot(doc, (x, MB_Y))
    else:
        for s in "NF":
            g = kit.grip(j, s)
            for x in MB_RUNGS:
                if abs(g[0] - x) < 4 and abs(g[1] - MB_Y) < 5:
                    bar_dot(doc, (x, MB_Y))


def monkey_poses():
    r = MB_RUNGS
    p1 = B(from_shoulder((r[2] - 26, MB_Y + 74), -88), -88, aN=G((r[2], MB_Y), 1), aF=G((r[1], MB_Y), 1),
           lN=(80, 128, 108), lF=(76, 122, 102), h=-80, curl=-2)
    # Far hand lets go and reaches for the next rung, hips swing forward under the near hand.
    p2 = B(from_shoulder((r[2], MB_Y + 82), -94), -94, aN=G((r[2], MB_Y), 1), aF=G((r[2] + 24, MB_Y + 16), 1),
           lN=(66, 112, 92), lF=(98, 140, 120), h=-82)
    p3 = B(from_shoulder((r[3] - 26, MB_Y + 74), -90), -90, aN=G((r[2], MB_Y), 1), aF=G((r[3], MB_Y), 1),
           lN=(90, 136, 116), lF=(84, 130, 110), h=-80)
    return [p1, p2, p3]


# ==== hanging shoulder circles ====================================================================

HC_BAR = (204, -26)  # high enough that the hanging feet stay well clear of the floor
HC_LEGS = dict(lN=(84, 104, 84), lF=(88, 108, 88))  # long hang, knees soft (bent knees read as kneeling)
HC_R = 8  # radius of the shoulder circle


def circles_at(s):
    """Shoulders trace a full circle (up, forward, down, back, up) with the arms long: s = 0 … 1 = one turn."""
    a = math.radians(-90 + 360 * s)
    c = (HC_BAR[0] - 3, HC_BAR[1] + REACH - HC_R - 1)
    sh = (c[0] + HC_R * math.cos(a), c[1] + HC_R * math.sin(a))
    t = -90 + 4 * math.cos(a)  # chest leans in as the shoulders roll forward
    return U.hang(sh, t, HC_LEGS, grip=HC_BAR, h=t + 12 - 10 * (1 + math.sin(a)) / 2)


def circles_poses():
    return [circles_at(0), circles_at(0.5), circles_at(1)]


def circles_scene(doc, j, layer):
    if layer == "back":
        floor(doc, HC_BAR[0], 60)
        kit.pullup_bar(doc, HC_BAR, top=-160, half=40)
    else:
        bar_dot(doc, HC_BAR)
        s = j["shoulder"]
        kit.arc(doc, s, 15, -200, 120)


# ==== scenes ======================================================================================

SCENES = {
    "muscle-up": S(grip_bar, mu_poses(), (), held_bar, floor=False),
    "weighted-muscle-up": S(weighted_mu_scene, mu_poses(), (), lambda j: held_bar(j) + mu_held(j), floor=False),
    "front-lever": S(hang_bar(FL), front_lever_poses(), lever_box(), floor=False),
    "tuck-front-lever": S(hang_bar(FL), tuck_front_lever_poses(), lever_box(), floor=False),
    "back-lever": S(side_rings(), back_lever_poses(), rings_box(), floor=False),
    "tuck-back-lever": S(side_rings(), tuck_back_lever_poses(), rings_box(), floor=False),
    "human-flag": S(flag_scene, flag_poses(), [(HF_X - 80, HF_TOP - 20, HF_X + 8, GROUND)]),
    "iron-cross": S(cross_scene(), cross_poses(), cross_box(), floor=False),
    "band-iron-cross": S(cross_scene(True), cross_poses(), cross_box(), band_held, floor=False),
    "one-arm-pull-up": S(wide_bar_front, one_arm_poses(), pb_box(), floor=False),
    "archer-pull-up": S(wide_bar_front, archer_poses(), pb_box(), floor=False),
    "one-arm-push-up": S(U.floor_scene, one_arm_push_poses()),
    "shoulder-tap-push-up": S(U.floor_scene, tap_poses()),
    "spiderman-push-up": S(U.floor_scene, spider_poses()),
    "wall-push-up": S(wall_scene, wall_push_poses(), [(WP_WALL, 100, WP_WALL + 16, GROUND)]),
    "freestanding-hspu": S(mat_scene(HS_W[0] - 60, HS_W[0] + 60), free_hspu_poses(),
                           [(HS_W[0] - 60, GROUND - 6, HS_W[0] + 60, GROUND)]),
    "kipping-hspu": S(mat_scene(KH_W[0] - 60, HS_WALL - 2, HS_WALL), kipping_poses(),
                      [(KH_W[0] - 60, GROUND - 6, HS_WALL + 16, GROUND)]),
    "pistol-squat": S(pistol_scene, pistol_poses()),
    "weighted-pistol": S(kb_pistol_scene, pistol_poses(True), (), kb_held),
    "bar-static-hold": S(hang_bar(SH_BAR), static_hold_poses(), [bar_box(SH_BAR)], floor=False),
    "dip-bar-leg-raise": S(dip_bar_scene, [dip_leg_pose(92, -90), dip_leg_pose(40, -88), dip_leg_pose(-10, -83)],
                           [(140, DB_Y - 6, 272, GROUND)]),
    "monkey-bar-traverse": S(monkey_scene, monkey_poses(), [(MB_RUNGS[0] - 34, MB_Y - 30, MB_RUNGS[-1] + 34, MB_Y + 8)],
                             floor=False),
    "hanging-shoulder-circles": S(circles_scene, circles_poses(), [bar_box(HC_BAR), (HC_BAR[0] - 40, GROUND - 4,
                                                                                    HC_BAR[0] + 40, GROUND)]),
}
