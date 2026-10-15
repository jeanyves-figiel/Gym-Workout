"""Scenes for the gym app comparison (#182): foam rolling, massage ball, mat stretches and mobility drills.

Same conventions as scenes.py (figure faces right, angles 0 = right, 90 = down, floor surface art.GROUND).
Built on the floor solvers of scenes_mobility (rest / reach / solve, 4:3 view fitting) and the foam-roller
helpers of scenes_var_core. The massage ball is drawn here.
"""
import math

import art
import kit
import scenes_mobility as MO
import scenes_var_core as VC
from art import GROUND
from poses import P

F = art.F
MAT = MO.MAT
FOOT_Y = GROUND - 4
WRIST_UP = MO.WRIST_UP
lerp, lerp2, tween = MO.lerp, MO.lerp2, MO.tween
rest, reach, joints, solve, dist = MO.rest, MO.reach, MO.joints, MO.solve, MO.dist
FR_R = VC.FR_R
E, floor_scene, settle_on = VC.E, VC.floor_scene, VC.settle_on

SCENES = {}


def add(ex_id, e):
    SCENES[ex_id] = e


def massage_ball(doc, c, r=6.5):
    """Small spiky massage ball."""
    g = doc.lin((c[0] - r, c[1] - r), (c[0] + r, c[1] + r), [(0, "#FF8A3D"), (1, "#B8461A")])
    dots = "".join(f'<circle cx="{c[0] + math.cos(math.radians(a)) * r * 0.55:.1f}" '
                   f'cy="{c[1] + math.sin(math.radians(a)) * r * 0.55:.1f}" r="{r * 0.16:.1f}" fill="#7A2C0E"/>'
                   for a in range(0, 360, 60))
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="{g}" stroke="#0A0B0D" stroke-width="0.9"/>' + dots
            + f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.16:.1f}" fill="#7A2C0E"/>')


def _roller_at(c):
    return lambda doc, j: kit.foam_roller(doc, c, FR_R)


def _box(c, r):
    return (c[0] - r, c[1] - r, c[0] + r, c[1] + r)


def sit_on(pose, x, y, parts=("torso", "thigh")):
    """Move the figure so the lowest point of its seat (torso/thigh outline) rests on (x, y)."""
    name, (px, py) = pose["pin"]
    low = max(MO.outline(pose, parts), key=lambda q: q[1])
    return dict(pose, pin=(name, (px + x - low[0], py + y - low[1])))


def _back_y(p, x, seg="torso", side=-1):
    """y of a segment edge (side -1 = back / underside of the torso) at x."""
    s = MO.segments(p)[seg]
    pts = [s.at(u / 80, side) for u in range(81)]
    return min(pts, key=lambda q: abs(q[0] - x))[1]


# ---- foam roll upper back: supine on the roller, hips up, hands behind the head --------------------------------

UB_C = (176, GROUND - FR_R)
UB_FEET = 300


def _roll_upper_back(u):
    """u = contact along the torso from the hip (0.45 mid back .. 0.8 upper back)."""
    rx, ry = UB_C
    top = ry - FR_R

    def mk(hy):
        hx = rx + u * F.TORSO
        return P(t=184, h=190, curl=-3, lN=(-60, 60, -10), lF=(-58, 62, -8), pin=("hip", (hx, hy)))
    hy = solve(lambda y: _back_y(mk(y), rx) - (top + 0.5), top - 40, top + 10)
    p = mk(hy)
    p = reach(p, "lN", (UB_FEET, FOOT_Y), end=0, pick=lambda m: -m[1])
    p = reach(p, "lF", (UB_FEET + 3, FOOT_Y), end=0, pick=lambda m: -m[1])
    hd = joints(p)["head"]
    p = reach(p, "aN", (hd[0] + 3, hd[1] + 9), end=150, pick=lambda m: -m[1])
    return reach(p, "aF", (hd[0], hd[1] + 10), end=150, pick=lambda m: -m[1])


add("foam-roll-upper-back", E(floor_scene(220, 110, back=_roller_at(UB_C)),
                              [_roll_upper_back(0.5), _roll_upper_back(0.66), _roll_upper_back(0.82)],
                              [_box(UB_C, FR_R)]))


# ---- foam roll glutes: sit on the roller, ankle over the other knee, hands behind ---------------------------

GL_C = (190, GROUND - FR_R)


def _roll_glutes(dx):
    rx, ry = GL_C
    t = -128
    p = P(t=t, h=t + 30, lF=(-28, 66, 0), lN=(-30, 60, 0), aN=(110, 110, 0), aF=(112, 112, 0),
          pin=("hip", (rx + dx, 200)))
    p = settle_on(p, "torso", rx, ry - FR_R, band=4)
    p = reach(p, "lF", (rx + 96, FOOT_Y), end=0, pick=lambda m: -m[1])
    j = joints(p)
    # Near ankle crossed over the far knee, knee open towards the camera.
    kf = j["kneeF"]
    p = reach(p, "lN", (kf[0] - 2, kf[1] - 6), end=-30, pick=lambda m: -m[1])
    s = j["shoulder"]
    p = reach(p, "aN", (s[0] - 22, FOOT_Y - WRIST_UP + 4), end=180, pick=lambda m: m[0])
    return reach(p, "aF", (s[0] - 25, FOOT_Y - WRIST_UP + 4), end=180, pick=lambda m: m[0])


add("foam-roll-glutes", E(floor_scene(200, 100, back=_roller_at(GL_C)),
                          [_roll_glutes(-6), _roll_glutes(2), _roll_glutes(10)], [_box(GL_C, FR_R)]))


# ---- foam roll hamstrings: roller under the thighs, hands behind, hips up ------------------------------------

HM_C = (216, GROUND - FR_R)


def _roll_hams(u):
    a = 6  # thighs nearly level, roller under the back of the thigh
    hx = HM_C[0] - u * F.THIGH * math.cos(math.radians(a))
    t = -130
    p = P(t=t, h=t + 34, lN=(a, a - 2, -80), lF=(a - 3, a - 5, -82), aN=(110, 110, 0), aF=(112, 112, 0),
          pin=("hip", (hx, 210)))
    p = settle_on(p, "thighN", HM_C[0], GROUND - 2 * FR_R)
    s = joints(p)["shoulder"]
    p = reach(p, "aN", (s[0] - 16, GROUND - WRIST_UP), end=180, pick=lambda m: m[0])
    return reach(p, "aF", (s[0] - 18, GROUND - WRIST_UP), end=180, pick=lambda m: m[0])


add("foam-roll-hamstrings", E(floor_scene(200, 110, back=_roller_at(HM_C)),
                              [_roll_hams(0.85), _roll_hams(0.55), _roll_hams(0.25)], [_box(HM_C, FR_R)]))


# ---- massage ball glute: sit on the ball, lean into it, then cross the leg -----------------------------------

MB_R = 6.5
MBG_C = (184, GROUND - MB_R)


def _ball_at(c, r=MB_R):
    return lambda doc, j: massage_ball(doc, c, r)


def _ball_glute(k):
    rx, ry = MBG_C
    t = lerp(-112, -124, k)
    p = P(t=t, h=t + 26, lF=(-36, 64, 0), lN=(-38, 62, 0), aN=(110, 110, 0), aF=(112, 112, 0),
          pin=("hip", (rx + 2, 200)))
    p = sit_on(p, rx, ry - MB_R + 1)
    p = reach(p, "lF", (rx + 92, FOOT_Y), end=0, pick=lambda m: -m[1])
    j = joints(p)
    if k < 1:
        p = reach(p, "lN", (rx + 88 - 6 * k, FOOT_Y - 30 * k * k), end=lerp(0, -20, k), pick=lambda m: -m[1])
    else:
        kf = j["kneeF"]
        p = reach(p, "lN", (kf[0] - 2, kf[1] - 6), end=-30, pick=lambda m: -m[1])
    s = j["shoulder"]
    p = reach(p, "aN", (s[0] - 18, FOOT_Y - WRIST_UP + 4), end=180, pick=lambda m: m[0])
    return reach(p, "aF", (s[0] - 21, FOOT_Y - WRIST_UP + 4), end=180, pick=lambda m: m[0])


add("massage-ball-glute", E(floor_scene(200, 100, back=_ball_at(MBG_C)),
                            [_ball_glute(0), _ball_glute(0.5), _ball_glute(1)], [_box(MBG_C, MB_R)]))


# ---- massage ball foot: standing, ball under the arch, roll heel to toes -------------------------------------

MBF_C = (232, GROUND - 7)


def _ball_foot(u):
    """u = where the ball sits along the sole (0 heel .. 1 toes)."""
    bx, by = MBF_C
    p = P(t=-90, h=-90, lF=(90, 90, 0), pin=("ankleF", (196, FOOT_Y)), lit_sides="N")
    sole = by - 7 + 1.5
    ankle = (bx - lerp(-3, 15, u), sole - 4)
    p = reach(p, "lN", ankle, end=lerp(4, -4, u), pick=lambda m: m[0])
    # Arms relaxed, slightly forward for balance.
    return dict(p, aN=(98, 76, 70), aF=(96, 80, 74))


add("massage-ball-foot", E(floor_scene(210, 50, back=_ball_at(MBF_C, 7)),
                           [_ball_foot(0), _ball_foot(0.5), _ball_foot(1)], [_box(MBF_C, 7)]))


# ---- boat pose: tuck balance → shins level → legs long ---------------------------------------------------------

def _boat(k):
    t = lerp(-110, -128, k)
    if k < 0.5:
        legs = dict(lN=(-40, 50, -40), lF=(-37, 53, -37))
    elif k < 1:
        legs = dict(lN=(-50, 0, -80), lF=(-47, 3, -77))
    else:
        legs = dict(lN=(-44, -44, -110), lF=(-41, -41, -107))
    p = P(t=t, h=t + 18, curl=-2, aN=(4, 4, 4), aF=(6, 6, 6), **legs)
    p = rest(p, "hip", 196, MAT, ("torso", "thigh", "shin", "foot"))
    if k == 0:  # feet still on the mat, hands behind the knees
        p = dict(p, lN=(-40, 50, 0), lF=(-37, 53, 3))
        p = rest(p, "hip", 196, MAT, ("torso", "thigh", "shin", "foot"))
        kn = joints(p)["kneeN"]
        p = reach(p, "aN", (kn[0] - 6, kn[1] + 8), end=0, pick=lambda m: m[1])
        p = reach(p, "aF", (kn[0] - 8, kn[1] + 10), end=0, pick=lambda m: m[1])
    return p


add("boat-pose", E(floor_scene(200, 90, mat=(90, 320)), [_boat(0), _boat(0.5), _boat(1)], [(90, MAT, 320, GROUND)]))


# ---- downward dog: plank → hips up → heels down -----------------------------------------------------------------

DD_HAND = (276, MAT - WRIST_UP)
DD_FOOT = 128


def _dog_apex():
    """Hips at the top of the inverted V: legs straight to the heels, trunk and arms in line to the hands."""
    heel, leg = (DD_FOOT, MAT - 5), F.THIGH + F.SHIN - 2
    reach_ = F.TORSO + F.UPPER_ARM + F.FOREARM - 6

    def at(a):
        return (heel[0] + leg * math.cos(math.radians(a)), heel[1] + leg * math.sin(math.radians(a)))
    a = solve(lambda a: dist(at(a), DD_HAND) - reach_, -89, -20)
    return at(a)


DD_APEX = _dog_apex()


def _dog(k):
    arm = F.UPPER_ARM + F.FOREARM
    hip = lerp2((DD_FOOT + 100, MAT - 70), DD_APEX, k)
    # The feet stay on the mat: never lift the hip beyond the legs' reach.
    heel = (DD_FOOT, lerp(MAT - 12, MAT - 5, k))
    d = dist(hip, heel)
    if d > F.THIGH + F.SHIN - 2:
        hip = lerp2(heel, hip, (F.THIGH + F.SHIN - 2) / d)

    def mk(t):
        return P(t=t, h=t + 10, aN=(90, 90, 0), aF=(92, 92, 0), pin=("hip", hip))
    t = solve(lambda t: dist(joints(mk(t))["shoulder"], DD_HAND) - arm + 0.3, -60, 60)
    p = mk(t)
    s = joints(p)["shoulder"]
    a = MO._ang((DD_HAND[0] - s[0], DD_HAND[1] - s[1]))
    p = dict(p, aN=(a, a, 0), aF=(a + 1, a + 1, 0), h=a - 180 + lerp(70, 40, k) if k else t + 6)
    ankle = (DD_FOOT, lerp(MAT - 12, MAT - 5, k))
    # Any slack in the legs is a soft knee bent forward (towards the hands), never locked back past straight.
    p = reach(p, "lN", ankle, end=lerp(60, 0, k), pick=lambda m: m[0])
    return reach(p, "lF", (ankle[0] - 3, ankle[1]), end=lerp(60, 0, k), pick=lambda m: m[0])


add("downward-dog", E(floor_scene(200, 100, mat=(90, 320)), [_dog(0), _dog(0.5), _dog(1)], [(90, MAT, 320, GROUND)]))


# ---- helpers for front / back / top-down views --------------------------------------------------------------------

def _out(cx, s):
    """pick(): knee/elbow furthest out on side s (+1 = screen right)."""
    return lambda m: s * (m[0] - cx)


def under_y(pose, seg, x, band=4):
    """Lowest outline point of segment `seg` around x."""
    pts = [q for q in MO.segments(pose)[seg].outline(40) if abs(q[0] - x) < band]
    return max(q[1] for q in pts)


def top_scene(mat, back=None, front=None):
    """Seen from above: the mat is a rectangle under the body, no floor line."""
    x0, y0, x1, y1 = mat

    def scene(doc, j, layer):
        if layer == "back":
            g = doc.box_grad([(0, "#3A7FA2"), (1, "#28627F")])
            doc.add(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{x1 - x0:.1f}" height="{y1 - y0:.1f}" rx="6" fill="{g}" '
                    f'stroke="#0A0B0D" stroke-opacity="0.5" stroke-width="0.8"/>')
            if back:
                back(doc, j)
        elif front:
            front(doc, j)
    return scene


def top_entry(scene, poses, boxes, corner=None, margin=6):
    v, c = MO.fit(poses, boxes, (), margin, corner, floor=False)
    return (scene, [dict(p, inset=c) for p in poses], v)


def roller_top(doc, x0, x1, cy, r=FR_R):
    """Foam roller seen from above (long side), shaded as a cylinder with grip rings."""
    g = doc.box_grad([(0, "#1B4A7A"), (0.35, "#4A93DE"), (1, "#173F69")])
    doc.add(f'<rect x="{x0:.1f}" y="{cy - r:.1f}" width="{x1 - x0:.1f}" height="{2 * r:.1f}" rx="4" fill="{g}" '
            f'stroke="#0A0B0D" stroke-width="0.9"/>')
    for i in range(1, 9):
        x = x0 + (x1 - x0) * i / 9
        doc.add(f'<line x1="{x:.1f}" y1="{cy - r + 1:.1f}" x2="{x:.1f}" y2="{cy + r - 1:.1f}" stroke="#0E2A47" '
                f'stroke-opacity="0.45" stroke-width="1.2"/>')


# ---- foam roll lats: side-lying (seen from behind), roller under the armpit, bottom arm overhead ---------------------

LT_C = (150, GROUND - FR_R)


def _roll_lats(u):
    """u = roller contact along the torso from the shoulder (0.12 armpit .. 0.45 mid ribs)."""
    rx, ry = LT_C
    top = ry - FR_R

    def mk(t):
        hx = rx + (1 - u) * F.TORSO
        p = P(front="back", t=t, h=t + 4, lN=(1, 1, 90), lF=(-1, -1, 90), aF=(t - 6, t - 6, t - 6),
              aN=(t - 174, t - 186, t - 186), pin=("hip", (hx, 0)))
        return rest(p, "hip", hx, GROUND, ("thigh", "shin"))
    t = solve(lambda t: under_y(mk(t), "torso", rx) - top, 170, 235)
    p = mk(t)
    j = joints(p)
    # Bottom hand on the floor past the head.
    s = j["shoulderF"]
    p = reach(p, "aF", (s[0] - 74, GROUND - 5), end=180, pick=lambda m: -m[1])
    # Top hand resting on the top hip.
    h = j["hipN"]
    return reach(p, "aN", (h[0] - 10, h[1] - 6), end=10, pick=lambda m: m[1])


add("foam-roll-lats", E(floor_scene(200, 120, back=_roller_at(LT_C)),
                        [_roll_lats(0.1), _roll_lats(0.3), _roll_lats(0.5)], [_box(LT_C, FR_R)]))


# ---- foam roll adductors: prone on the forearms seen from above, roller along the inner thigh -------------------

AD_ROLL = (110, 236, 214)  # x0, x1, centre y


def _roll_adductors(u):
    """u = roller contact along the near thigh from the hip (0.8 by the knee .. 0.3 by the groin)."""
    th = 112
    hy = AD_ROLL[2] - u * F.THIGH * math.sin(math.radians(th)) - 6
    p = P(front="back", t=0, h=0, lF=(182, 182, 182), lN=(th, 196, 180), aN=(28, -18, -18), aF=(-28, 18, 18),
          pin=("hip", (170, hy)))
    return p


def _ad_roller(doc, j):
    roller_top(doc, AD_ROLL[0], AD_ROLL[1], AD_ROLL[2])


add("foam-roll-adductors", top_entry(top_scene((40, 140, 330, 250), back=_ad_roller),
                                     [_roll_adductors(0.75), _roll_adductors(0.5), _roll_adductors(0.25)],
                                     [(40, 140, 330, 250)]))


# ---- massage ball chest: facing a wall, ball under the collarbone, hand slides up the wall ---------------------------

MBC_R = 6.5


def _mbc_base():
    p = P(t=-80, h=-80, lN=(96, 96, 0), lF=(98, 98, 0), pin=("ankleN", (176, FOOT_Y)))
    tor = MO.segments(p)["torso"]
    front = tor.at(0.84, 1)
    return p, (front[0] + MBC_R - 1, front[1])


MBC_P, MBC_C = _mbc_base()
MBC_WALL = MBC_C[0] + MBC_R - 1


def _ball_chest(k):
    """k 0 = hand on the wall by the ribs, 0.5 = at shoulder height, 1 = overhead: the hand slides up the wall
    (it no longer swings up from a hanging arm through the wall)."""
    p = dict(MBC_P)
    s = joints(p)["shoulder"]
    tgt = (MBC_WALL - 8, s[1] + 34 if k == 0 else lerp(s[1] + 4, s[1] - 75, (k - 0.5) * 2))
    p = reach(p, "aN", tgt, end=-90, pick=lambda m: m[1] if k < 1 else -m[0])
    return dict(p, aF=(98, 86, 86))


def _mbc_wall(doc, j):
    kit.wall(doc, MBC_WALL, 16, 30)


def _mbc_ball(doc, j):
    massage_ball(doc, MBC_C, MBC_R)


add("massage-ball-chest", E(floor_scene(200, 40, back=_mbc_wall, front=_mbc_ball),
                            [_ball_chest(0), _ball_chest(0.5), _ball_chest(1)],
                            [(MBC_WALL, 120, MBC_WALL + 16, GROUND)]))


# ---- hip windshield wipers (front view): seated, feet wide, both knees drop to one side, then the other -------------

WW_X = 200


def _wipers(side):
    """side 0 = knees up, +1 = knees dropped to screen right, -1 = to screen left (front view, legs foreshortened)."""
    up_N, up_F = (-48, 104, 20), (228, 76, 160)
    # Dropped near foot lies on its outer edge, toes to the side: turning it to 170 swept the toes down through the mat.
    flat_N, flat_F = (8, 168, -10), (-40, 128, 160)
    if side == 0:
        lN, lF = up_N, up_F
    elif side > 0:
        lN, lF = flat_N, flat_F
    else:
        lN, lF = (180 - flat_F[0], 180 - flat_F[1], 180 - flat_F[2]), (180 - flat_N[0], 180 - flat_N[1], 180 - flat_N[2])
    p = P(front=True, t=-96, h=-90, lN=lN, lF=lF)
    p = rest(p, "hip", WW_X, MAT, ("torso",))
    p = dict(p, t=-90 - 4 * side, h=-90 - 6 * side)
    j = joints(p)
    # Hands planted behind the hips, arms straight.
    p = reach(p, "aN", (j["shoulderN"][0] + 16, MAT - WRIST_UP), end=80, pick=_out(WW_X, 1))
    return reach(p, "aF", (j["shoulderF"][0] - 16, MAT - WRIST_UP), end=100, pick=_out(WW_X, -1))


add("windshield-wipers", E(floor_scene(200, 80, mat=(110, 290)), [_wipers(0), _wipers(1), _wipers(-1)],
                           [(110, MAT, 290, GROUND)]))


# ---- seated straddle (front view): legs wide, hinge, walk the hands out ------------------------------------------

ST_X = 200


def _straddle(k):
    p = P(front=True, t=-90, h=-90, curl=lerp(0, 4, k), lN=(4, 4, -90), lF=(176, 176, -90))
    p = rest(p, "hip", ST_X, MAT, ("torso", "thigh", "shin"))
    j = joints(p)
    if k == 0:
        tgt = 28
    else:
        tgt = lerp(30, 76, k)
    p = reach(p, "aN", (ST_X + tgt, MAT - WRIST_UP), end=lerp(80, 10, k), pick=_out(ST_X, 1))
    return reach(p, "aF", (ST_X - tgt, MAT - WRIST_UP), end=lerp(100, 170, k), pick=_out(ST_X, -1))


add("straddle-stretch", E(floor_scene(200, 120, mat=(60, 340)), [_straddle(0), _straddle(0.5), _straddle(1)],
                          [(60, MAT, 340, GROUND)]))


# ---- warrior 2 (front view): wide stance, front knee bends over the ankle, arms long ----------------------------

W2_X = 200
W2_N, W2_F = (W2_X + 96, FOOT_Y), (W2_X - 74, FOOT_Y)


def _warrior(k):
    leg = F.THIGH + F.SHIN
    hx = W2_X + lerp(0, 34, k)

    def at_y(y):
        return P(front=True, t=-90, h=-90, pin=("hip", (hx, y)))
    # Back leg stays straight: the hip slides along its arc as the front knee bends.
    y = solve(lambda y: dist(joints(at_y(y))["hipF"], W2_F) - (leg - 0.4), FOOT_Y - leg - 5, FOOT_Y - 20)
    p = at_y(y)
    p = reach(p, "lN", W2_N, end=0, pick=_out(hx, 1))
    p = reach(p, "lF", W2_F, end=200, pick=_out(hx, -1))
    a = lerp(76, 0, min(1, k * 2))
    return dict(p, aN=(a, a, a), aF=(180 - a, 180 - a, 180 - a), h=-90)


add("warrior-2", E(floor_scene(200, 90, mat=(100, 300)), [_warrior(0), _warrior(0.5), _warrior(1)],
                   [(100, MAT, 300, GROUND)]))


# ---- brettzel (seen from above): side-lying, top knee forward, top hand holds the bottom foot, chest opens ------------

BZ_HIP = (190, 170)


def _brettzel(k):
    """Set up from the first frame (the stretch is the rotation, not getting into it): top knee forward, held
    down by the bottom hand; bottom heel pulled behind the hip by the top hand. k = how far the chest opens:
    head and shoulders turn back over the top side, the heel drawn in a touch further."""
    shin = lerp(-18, -30, k)
    p = P(t=0, h=lerp(0, -42, k), curl=lerp(0, -4, k), lN=(70, 160, 160), lF=(195, shin, shin - 90),
          aN=(-150, -170, -170), aF=(80, 20, 20), pin=("hip", BZ_HIP))
    j = joints(p)
    a = j["ankleF"]
    p = reach(p, "aN", (a[0] + 3, a[1] - 1), end=None, pick=lambda m: -m[1])
    kn = j["kneeN"]
    return reach(p, "aF", (kn[0] + 4, kn[1] - 3), end=None, pick=lambda m: m[1])


BZ_MAT = (70, 100, 320, 252)


def bz_scene(doc, j, layer):
    """Seen from above on a light, close-fitting mat (a dark full-frame slab hid the pose)."""
    if layer == "back":
        x0, y0, x1, y1 = BZ_MAT
        g = doc.box_grad([(0, "#6FB4D2"), (1, "#5598B8")])
        doc.add(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{x1 - x0:.1f}" height="{y1 - y0:.1f}" rx="8" fill="{g}" '
                f'stroke="#0A0B0D" stroke-opacity="0.35" stroke-width="0.8"/>')


add("brettzel", top_entry(bz_scene, [_brettzel(0), _brettzel(0.5), _brettzel(1)], [BZ_MAT]))


# ---- adductor rock-back: quadruped, near leg straight out to the side (towards the camera), hips rock back -----------

AR_KNEE = 150
AR_HAND = (AR_KNEE + 88, MAT - WRIST_UP)
AR_FOOT = (AR_KNEE + 70, MAT - 5)


def _rock(k):
    thigh = lerp(84, 46, k)
    base = P(t=-10, h=-6, lF=(thigh, 180, 180), lN=(70, 70, 0), aN=(90, 90, 0), aF=(92, 92, 0))

    def mk(t):
        return rest(dict(base, t=t), "kneeF", AR_KNEE, MAT, ("thighF", "shinF", "footF"))
    t = solve(lambda t: dist(joints(mk(t))["shoulder"], AR_HAND) - (F.UPPER_ARM + F.FOREARM - 0.3), -50, 40)
    p = mk(t)
    s = joints(p)["shoulder"]
    a = MO._ang((AR_HAND[0] - s[0], AR_HAND[1] - s[1]))
    p = dict(p, aN=(a, a, 0), aF=(a + 2, a + 2, 0), h=t + 8)
    # Near leg long, foot flat: the knee stays soft only as far as the solver needs to reach the planted foot.
    return reach(p, "lN", AR_FOOT, end=0, pick=lambda m: -m[1])


add("adductor-rock-back", E(floor_scene(200, 110, mat=(70, 330)), [_rock(0), _rock(0.5), _rock(1)],
                            [(70, MAT, 330, GROUND)]))
