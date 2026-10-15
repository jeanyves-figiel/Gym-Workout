"""Lower-body scenes for the realistic exercise art (#170): squats, hinges, lunges, leg machines, calves.

Poses are built with `body()`: pin the hip, give the torso angle and the targets for the ankles and the
hands; the limb angles are solved (two-link IK) so feet stay planted on the floor / platform and hands stay
on the bar or handles in every frame. Every exercise lists three explicit frames (start, middle, end).
Static equipment is drawn in absolute view-box coordinates, held items follow the hands.
Angles as in poses.py (0 = right, 90 = down; the figure faces right).
"""
import math

import art
import kit
from art import GROUND
from poses import P

TH, SH, FT = 56, 54, 14  # thigh, shin, foot
UA, FA, HA = 42, 38, 10  # upper arm, forearm, hand
TOR = 72
ANK = GROUND - 4  # ankle height of a foot flat on the floor
SW = art.PROFILES["torso"][-1][1] * 1.45 * 0.9  # frontal view: shoulder offset
HW = 9.0  # frontal view: hip offset


# ---- geometry / pose solving ---------------------------------------------------------------------

def pt(p, a, length):
    return art.ang_pt(p, a, length)


def angle(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def ik(a, b, l1, l2, s):
    """Two-link chain a→joint→b: absolute angles of both links. s = ±1 picks the side the joint bends to."""
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    d = max(abs(l1 - l2) + 1e-3, min(l1 + l2 - 1e-3, d))
    c = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    a1 = angle(a, b) + s * math.degrees(math.acos(max(-1.0, min(1.0, c))))
    j = pt(a, a1, l1)
    return a1, angle(j, b)


def lerp(a, b, k):
    if isinstance(a, tuple):
        return tuple(x + (y - x) * k for x, y in zip(a, b))
    return a + (b - a) * k


def body(hip, t=-90, h=None, ankN=None, ankF=None, kN=-1, kF=-1, fN=0, fF=0,
         gN=None, gF=None, eN=1, eF=1, hN=None, hF=None, **kw):
    """Pose pinned at the hip. ankX = ankle target (knee bends to side kX), fX = foot angle;
    gX = grip (centre of the closed hand) target, eX = elbow side, hX = hand angle (default: in line)."""
    front = kw.get("front")
    sh = pt(hip, t, TOR)
    td = (math.cos(math.radians(t)), math.sin(math.radians(t)))
    n = (-td[1], td[0])
    p = dict(t=t, h=t if h is None else h, pin=("hip", hip))
    for side, s in (("N", 1), ("F", -1)):
        ank, k, f = (ankN, kN, fN) if side == "N" else (ankF, kF, fF)
        if ank is not None:
            if front:
                ank = art.add(ank, n, -s * HW)
            p["l" + side] = (*ik(hip, ank, TH, SH, k), f)
        g, e, ha = (gN, eN, hN) if side == "N" else (gF, eF, hF)
        if g is not None:
            if front:
                g = art.add(g, n, -s * SW)
            if ha is None:
                a1, a2 = ik(sh, g, UA, FA + HA / 2, e)
                p["a" + side] = (a1, a2)
            else:
                w = pt(g, ha, -HA / 2)
                a1, a2 = ik(sh, w, UA, FA, e)
                p["a" + side] = (a1, a2, ha)
    p.update({k: v for k, v in kw.items()})
    return P(**p)


def replant(j, side, ank, k=-1):
    """Keep a foot that is planted in every key pose planted in the in-betweens too: the angle interpolation of
    the other joints lets it slide a few px, so re-solve that leg's knee from its hip onto the fixed ankle
    (the foot keeps its interpolated angle)."""
    hp = j.get("hip" + side, j["hip"])
    a = j["ankle" + side]
    t = j["toe" + side]
    a1, _ = ik(hp, ank, TH, SH, k)
    j["knee" + side] = pt(hp, a1, TH)
    j["ankle" + side] = ank
    j["toe" + side] = (t[0] + ank[0] - a[0], t[1] + ank[1] - a[1])


def ins(poses, corner):
    """Put the muscle-map inset in `corner` on every frame."""
    for p in poses:
        p["inset"] = corner
    return poses


def joints(pose):
    j = art.F.place(pose)
    if art.view_of(pose) != "side":
        art.frontal(j)
    return j


def shoulder(hip, t):
    return pt(hip, t, TOR)


def tframe(t):
    td = (math.cos(math.radians(t)), math.sin(math.radians(t)))
    return td, (-td[1], td[0])


def back_bar(hip, t, back=14, up=3):
    """High-bar position on the upper back for a torso pinned at `hip` with angle t."""
    td, n = tframe(t)
    s = shoulder(hip, t)
    return (s[0] - n[0] * back + td[0] * up, s[1] - n[1] * back + td[1] * up)


def front_bar(hip, t, fwd=13, up=-3):
    """Front-rack bar position: on the front delts."""
    td, n = tframe(t)
    s = shoulder(hip, t)
    return (s[0] + n[0] * fwd + td[0] * up, s[1] + n[1] * fwd + td[1] * up)


def grip(j, side="N"):
    return kit.grip(j, side)


# ---- shared equipment ------------------------------------------------------------------------------

def floor(doc, cx=200, rx=110):
    art.floor(doc, -60, 460)
    art.shadow(doc, cx, rx)


def bar_end(doc, c, r=25):
    kit.barbell(doc, c, r)


def dbs(doc, j, layer, r=10):
    """Dumbbells held end-on in both hands (far one behind the body)."""
    if layer == "back":
        art.db_end(doc, grip(j, "F"), r * 0.95)
    else:
        art.db_end(doc, grip(j), r)


def slab(doc, a, b, t, body_pt, stitch=True):
    """Upholstered pad whose contact face is the line a-b, extending away from `body_pt`."""
    d = (b[0] - a[0], b[1] - a[1])
    side = (d[1], -d[0])  # art.pad extends towards this side of a→b
    if side[0] * (body_pt[0] - a[0]) + side[1] * (body_pt[1] - a[1]) > 0:
        a, b = b, a
    art.pad(doc, a, b, t, stitch)


def step_block(doc, x, w, h):
    """Low aerobic step / calf block: dark plastic top over a grey base."""
    g = doc.box_grad([(0, "#4A5059"), (1, "#24282E")])
    doc.add(f'<rect x="{x:.1f}" y="{GROUND - h:.1f}" width="{w:.1f}" height="{h:.1f}" rx="2.5" fill="{g}" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>'
            f'<rect x="{x:.1f}" y="{GROUND - h:.1f}" width="{w:.1f}" height="4" rx="2" fill="#15171A"/>')


def smith_frame(doc, x, top=20):
    """Smith machine seen from the side: guide rail at x (bar runs in it), frame posts and top beam."""
    art.tube(doc, (x - 70, GROUND - 2), (x - 70, top), 10, "butt")
    art.tube(doc, (x + 70, GROUND - 2), (x + 70, top), 10, "butt")
    art.tube(doc, (x - 76, top), (x + 76, top), 9)
    kit.feet(doc, x - 92, x + 92)
    art.tube(doc, (x, top + 4), (x, GROUND - 2), 5, "butt")
    for y in range(top + 30, GROUND - 30, 22):
        doc.add(f'<rect x="{x - 76:.1f}" y="{y}" width="8" height="3" rx="1" fill="#0C0E10"/>')


def smith_bar(doc, c, r=24):
    """Smith bar end-on: carriage block on the rail, plate on the sleeve."""
    doc.add(f'<rect x="{c[0] - 7:.1f}" y="{c[1] - 12:.1f}" width="14" height="24" rx="2" fill="#2A2E34" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>')
    kit.barbell(doc, c, r)
    art.tube(doc, (c[0] + r - 2, c[1] - 2), (c[0] + r + 10, c[1] - 9), 3.5)  # rotating hook handle


# ==== squats ======================================================================================

# -- front squat
FS_ANK = (200, ANK)


def front_squat_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    bar = (j["shoulder"][0] + n[0] * 13 - td[0] * 3, j["shoulder"][1] + n[1] * 13 - td[1] * 3)
    if layer == "back":
        floor(doc, 196, 100)
        kit.rack(doc, 108, hook_y=84, safety_y=196)
    else:
        bar_end(doc, bar)


def rack_arm(hip, t, upper=-14, dx=0):
    """Front-rack arm: upper arm near horizontal (elbows high), forearm folded back to the bar."""
    s = shoulder(hip, t)
    b = front_bar(hip, t)
    el = pt(s, upper, UA)
    return (upper, angle(el, (b[0] - 6 + dx, b[1] + 2)), -100)


def front_squat_pose(hip, t):
    return body(hip, t, ankN=FS_ANK, ankF=(FS_ANK[0] - 4, ANK), aN=rack_arm(hip, t), aF=rack_arm(hip, t, -10, 3))


# -- goblet squat
GS_ANK = (200, ANK)


def goblet_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 90)
    else:
        g = grip(j)
        art.db_side(doc, (g[0] + 1, g[1] + 12), 90, 10, 15)


def goblet_pose(hip, t):
    td, n = tframe(t)
    s = shoulder(hip, t)
    g = (s[0] + n[0] * 22 - td[0] * 16, s[1] + n[1] * 22 - td[1] * 16)
    return body(hip, t, ankN=GS_ANK, ankF=(GS_ANK[0] - 4, ANK), gN=g, gF=(g[0] + 1, g[1] - 1), eN=1, eF=1,
                hN=-90, hF=-90)


# -- bodyweight squat (arms reach forward for balance)

def bw_squat_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 90)


def bw_squat_pose(hip, t, reach):
    s = shoulder(hip, t)
    g = (s[0] + reach[0], s[1] + reach[1])
    return body(hip, t, ankN=GS_ANK, ankF=(GS_ANK[0] - 4, ANK), gN=g, gF=(g[0] - 3, g[1] + 2), eN=1, eF=1)


# ==== hack squat ===================================================================================

HK_T = -118  # torso angle = backrest / rail angle
HK_ANK = (252, 244)
HK_FOOT = -16


def hack_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    hip, sh = j["hip"], j["shoulder"]
    if layer == "back":
        floor(doc, 200, 110)
        # Rails (fixed, parallel to the backrest) from the floor frame up behind the lifter.
        r0 = art.add((204, 150), n, -38)
        top = art.add(r0, td, 120)
        k = (GROUND - 4 - r0[1]) / td[1]
        bot = art.add(r0, td, k)
        art.tube(doc, bot, top, 9)
        art.tube(doc, (bot[0] - 26, GROUND - 2), (300, GROUND - 2), 7)
        art.tube(doc, art.add(bot, td, 30), (bot[0] - 24, GROUND - 2), 6)
        # Foot platform on its support.
        fd = (math.cos(math.radians(HK_FOOT)), math.sin(math.radians(HK_FOOT)))
        sole = art.add(HK_ANK, (-fd[1], fd[0]), 6)
        a, b = art.add(sole, fd, -18), art.add(sole, fd, 30)
        art.tube(doc, art.add(sole, fd, 6), (264, GROUND - 2), 8, "butt")
        art.tube(doc, art.add(sole, fd, 6), (226, GROUND - 2), 6, "butt")
        slab(doc, a, b, 8, j["kneeN"], stitch=False)
        # Carriage: plate horn, back pad, shoulder pads (ride the rails with the lifter).
        car = art.add(art.add(hip, td, 34), n, -38)
        doc.add(f'<rect x="{car[0] - 9:.1f}" y="{car[1] - 30:.1f}" width="18" height="60" rx="3" fill="#2A2E34" '
                f'stroke="#0A0B0D" stroke-width="0.8" transform="rotate({HK_T + 90} {car[0]:.1f} {car[1]:.1f})"/>')
        art.plate(doc, art.add(car, n, -14), 22)
        slab(doc, art.add(art.add(hip, td, -8), n, -15), art.add(art.add(sh, td, 4), n, -15), 11, hip)
    else:
        sp = art.add(sh, td, 13)
        slab(doc, art.add(sp, n, -12), art.add(sp, n, 12), 10, sh)
        art.tube(doc, art.add(sp, n, 12), art.add(art.add(sp, n, 20), td, -8), 5)
        kit.handle(doc, grip(j))


def hack_pose(k):
    hip = lerp((204, 150), (233, 200), k)
    td, n = tframe(HK_T)
    s = shoulder(hip, HK_T)
    g = art.add(art.add(s, n, 20), td, 5)
    return body(hip, HK_T, h=HK_T + 22, ankN=HK_ANK, ankF=(HK_ANK[0] - 3, HK_ANK[1] + 1), fN=HK_FOOT, fF=HK_FOOT,
                gN=g, gF=art.add(g, n, -2), eN=1, eF=1)


# ==== 45-degree leg press ==========================================================================

LP_HIP = (150, 206)
LP_T = -140
LP_R = -40  # sled travel direction (up the rails)
LP_RD = (math.cos(math.radians(LP_R)), math.sin(math.radians(LP_R)))
LP_PD = (math.cos(math.radians(LP_R - 90)), math.sin(math.radians(LP_R - 90)))  # along the plate, upwards
LP_ANK = art.ang_pt(LP_HIP, -41, 107.5)  # legs extended (soft knees)


def leg_press_machine(doc, j, layer, s, po=2):
    """45° leg press: seat + backrest, inclined rails, sled with foot plate and plate horns.
    s = sled travel from its fully extended position (px along the rails, negative = lowered);
    po = where the foot plate sits along its own face relative to the ankles."""
    if layer == "back":
        floor(doc, 210, 140)
        # Base and inclined rail frame (below the sled path).
        kit.feet(doc, 96, 352)
        r0 = (176, 244)
        r1 = art.add(r0, LP_RD, 150)
        art.tube(doc, (r0[0] - 10, GROUND - 2), r0, 9)
        art.tube(doc, r0, r1, 10)
        art.tube(doc, r1, (r1[0], GROUND - 2), 9, "butt")
        m = art.add(r0, LP_RD, 84)
        art.tube(doc, m, (m[0], GROUND - 2), 8, "butt")
        # Seat on its post, reclined backrest.
        hip = LP_HIP
        td, n = tframe(LP_T)
        art.tube(doc, (hip[0] - 4, hip[1] + 18), (hip[0] - 4, GROUND - 2), 9, "butt")
        art.tube(doc, (hip[0] - 50, hip[1] - 20), (hip[0] - 56, GROUND - 2), 7, "butt")
        slab(doc, art.add(art.add(hip, td, -14), n, -15), art.add(art.add(hip, td, 84), n, -15), 12, hip)
        slab(doc, (hip[0] - 18, hip[1] + 14), (hip[0] + 30, hip[1] + 14), 12, hip)
        art.tube(doc, (hip[0] + 6, hip[1] + 20), (hip[0] + 22, hip[1] + 6), 5)
        # Sled riding on the rail: carriage, foot plate, plate horn low on the sled.
        pc = art.add(art.add(LP_ANK, LP_RD, 6 + s), LP_PD, po)
        car = art.add(art.add(pc, LP_RD, 14), LP_PD, -30)
        art.tube(doc, art.add(car, LP_RD, -14), art.add(car, LP_RD, 22), 13)
        art.tube(doc, art.add(pc, LP_RD, 8), car, 7)
        art.tube(doc, art.add(art.add(pc, LP_PD, 22), LP_RD, 8), art.add(car, LP_RD, 10), 6)
        art.plate(doc, art.add(art.add(car, LP_RD, -4), LP_PD, -12), 21)
        slab(doc, art.add(pc, LP_PD, -26), art.add(pc, LP_PD, 30), 9, LP_HIP, stitch=False)
    else:
        kit.handle(doc, grip(j))


def leg_press_scene(doc, j, layer):
    s = (j["ankleN"][0] - LP_ANK[0]) * LP_RD[0] + (j["ankleN"][1] - LP_ANK[1]) * LP_RD[1]
    leg_press_machine(doc, j, layer, s)


def leg_press_pose(k):
    ank = art.add(LP_ANK, LP_RD, -36 * k)  # bottom: knees about 90-100°, thighs short of the chest
    g = (LP_HIP[0] + 8, LP_HIP[1] + 4)
    # Knees fold up towards the chest (above the hip-ankle line), never down below it.
    return body(LP_HIP, LP_T, h=LP_T + 40, ankN=ank, ankF=art.add(ank, LP_PD, 4), kN=-1, kF=-1,
                fN=LP_R - 90, fF=LP_R - 90, gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1)


def calf_press_scene(doc, j, layer):
    toe = j["toeN"]
    s = (toe[0] - LP_ANK[0]) * LP_RD[0] + (toe[1] - LP_ANK[1]) * LP_RD[1] - 4
    leg_press_machine(doc, j, layer, s, po=34)


def calf_press_pose(f):
    ank = art.add(LP_ANK, LP_RD, -6)
    g = (LP_HIP[0] + 8, LP_HIP[1] + 4)
    p = body(LP_HIP, LP_T, h=LP_T + 40, ankN=ank, ankF=art.add(ank, LP_PD, 4), kN=-1, kF=-1, fN=f, fF=f,
             gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1)
    return p


# ==== hinges ==========================================================================================

ARM = 84  # shoulder → grip with a straight arm


def hang_from(bar, t, dx=0):
    """Hip position for a torso at angle t whose straight arms hang to `bar`; shoulder dx ahead of the bar."""
    s = (bar[0] + dx, bar[1] - math.sqrt(ARM * ARM - dx * dx))
    return pt(s, t, -TOR)


def hinge_pose(bar, t, ank, dx=0, far=(-4, 1), h=None, **kw):
    """Both hands on a bar / dumbbells at `bar`, arms straight, feet at `ank`."""
    hip = hang_from(bar, t, dx)
    return body(hip, t, h=h, ankN=ank, ankF=(ank[0] + far[0], ank[1]), gN=bar, gF=(bar[0] + far[1], bar[1]),
                eN=1, eF=1, **kw)


# -- conventional deadlift
DL_ANK = (196, ANK)
DL_X = 204  # bar over mid-foot


def deadlift_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 100)
    else:
        bar_end(doc, grip(j))


# -- trap bar deadlift (high handles 14 px above the sleeve)
TB_X = 196


def trap_bar_scene(doc, j, layer):
    g = grip(j)
    if layer == "back":
        floor(doc, 196, 100)
        art.tube(doc, (g[0] - 40, g[1] + 14), (g[0] + 40, g[1] + 14), 4)
    else:
        sleeve = (g[0], g[1] + 14)
        art.tube(doc, (g[0] - 8, g[1]), (g[0] - 8, sleeve[1]), 4)
        art.tube(doc, (g[0] + 8, g[1]), (g[0] + 8, sleeve[1]), 4)
        art.plate(doc, sleeve, 24)
        doc.add(f'<circle cx="{sleeve[0]:.1f}" cy="{sleeve[1]:.1f}" r="6" fill="none" stroke="#A9B2BC" stroke-width="2"/>')
        art.tube(doc, (g[0] - 9, g[1]), (g[0] + 9, g[1]), 5)
        kit.handle(doc, g)


# -- Romanian deadlift (barbell) and dumbbell RDL
def db_rdl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 90)
    dbs(doc, j, layer)


# -- good morning (bar on the back, rack behind)
GM_ANK = (204, ANK)


def good_morning_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    if layer == "back":
        floor(doc, 196, 100)
        kit.rack(doc, 96, hook_y=84, safety_y=200)
    else:
        bar_end(doc, kit.on_back(j))


def gm_pose(hip, t, h=None, **kw):
    b = back_bar(hip, t)
    td, n = tframe(t)
    g = art.add(b, n, 4)
    return body(hip, t, h=h, ankN=GM_ANK, ankF=(GM_ANK[0] - 4, ANK), gN=g, gF=art.add(g, td, 2), eN=1, eF=1,
                hN=t - 20, hF=t - 20, **kw)


# -- band good morning: band under the feet and over the back of the neck, hands hold it at the shoulders
def band_gm_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    top = art.add(art.add(j["shoulder"], n, -9), td, 6)
    foot = (j["ankleN"][0] + 6, GROUND - 1)
    if layer == "back":
        floor(doc, 196, 90)
        kit.band(doc, (foot[0] - 3, foot[1]), art.add(top, n, -2))
    else:
        kit.band(doc, foot, grip(j))
        kit.band(doc, grip(j), top)


def band_gm_pose(hip, t, h=None):
    td, n = tframe(t)
    s = shoulder(hip, t)
    g = art.add(art.add(s, n, 12), td, 6)
    return body(hip, t, h=h, ankN=GM_ANK, ankF=(GM_ANK[0] - 4, ANK), gN=g, gF=art.add(g, td, -2), eN=1, eF=1,
                hN=t, hF=t)


# -- single-leg RDL: stand on the near leg, far leg reaches back in line with the torso
SL_ANK = (220, ANK)


def sl_rdl_pose(hip, t, legF, k=-1, **kw):
    """legF = (thigh, shin, foot) of the free leg; arms hang straight down."""
    s = shoulder(hip, t)
    g = (s[0] + 2, s[1] + ARM)
    p = body(hip, t, ankN=SL_ANK, kN=k, gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1, lit_sides="N", **kw)
    p["lF"] = legF
    return p


def sl_rdl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 214, 70)
    dbs(doc, j, layer)


def bw_scene(doc, j, layer, cx=200, rx=80):
    if layer == "back":
        floor(doc, cx, rx)


def bw_sl_rdl_scene(doc, j, layer):
    bw_scene(doc, j, layer, 214, 70)


# -- cable pull-through: low pulley behind the lifter, rope between the legs
PT_PULLEY = (104, GROUND - 16)


def low_tower(doc, x, pulley, lift):
    """Cable column with its stack on the LEFT and the pulley on its RIGHT face (the lifter works to the right)."""
    top = 46
    art.tube(doc, (x + 4, GROUND - 2), (x + 4, top), 9)
    art.shroud(doc, x - 52, top + 28, GROUND - 4, 44)
    st = art.stack(doc, x - 47, top + 42, GROUND - 4, 34, 11, lift)
    art.tube(doc, (x - 58, top), (x + 10, top), 8)
    art.pulley(doc, (st[0], top + 7), 5.5)
    art.cable(doc, [(st[0] + 5.5, top + 7), st])
    art.cable(doc, [(st[0] - 5.5, top + 7), (st[0] - 5.5, top + 2), (x + 4, top + 2)])
    art.tube(doc, (x + 4, pulley[1]), (pulley[0] - 2, pulley[1]), 5)
    kit.feet(doc, x - 60, x + 24)
    art.pulley(doc, pulley, 6)


def pull_through_scene(doc, j, layer):
    g = grip(j)
    if layer == "back":
        floor(doc, 170, 130)
        L = math.hypot(g[0] - PT_PULLEY[0], g[1] - PT_PULLEY[1])
        low_tower(doc, PT_PULLEY[0] - 12, PT_PULLEY, max(0, (L - 90) * 0.35))
        art.cable(doc, [(PT_PULLEY[0] + 1, PT_PULLEY[1] + 6), g])
    else:
        kit.handle(doc, g, "rope")


PT_ANK = (206, ANK)


def pt_pose(hip, t, g, h=None):
    return body(hip, t, h=h, ankN=PT_ANK, ankF=(PT_ANK[0] - 6, ANK), gN=g, gF=(g[0] - 2, g[1]), eN=-1, eF=-1)


# -- 45° back extension
BE_HIP = (206, 132)
BE_LEG = 135  # legs run down-left at 45°


def back_ext_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 170, 110)
        hip = BE_HIP
        ld = (math.cos(math.radians(BE_LEG)), math.sin(math.radians(BE_LEG)))
        fr = (ld[1], -ld[0])  # thigh front (down-right)
        ank = pt(hip, BE_LEG, TH + SH)
        # Main beam under the legs, pad support, foot plate support.
        b0 = art.add(art.add(hip, fr, 34), ld, -4)
        b1 = art.add(art.add(ank, fr, 30), ld, 10)
        art.tube(doc, b0, b1, 10)
        art.tube(doc, art.add(art.add(hip, fr, 14), ld, 12), b0, 7)
        art.tube(doc, b0, (b0[0] + 28, GROUND - 2), 9, "butt")
        art.tube(doc, b1, (b1[0], GROUND - 2), 9, "butt")
        kit.feet(doc, b1[0] - 22, b0[0] + 50)
        # Hip pad on the front of the thighs.
        slab(doc, art.add(art.add(hip, fr, 13), ld, -6), art.add(art.add(hip, fr, 13), ld, 34), 11, hip)
        # Foot plate under the soles and the ankle roller behind the heels.
        sole = art.add(ank, ld, 6)
        art.tube(doc, art.add(sole, fr, 8), b1, 6)
        slab(doc, art.add(sole, fr, -8), art.add(sole, fr, 22), 6, ank, stitch=False)
    else:
        ank = pt(BE_HIP, BE_LEG, TH + SH)
        ld = (math.cos(math.radians(BE_LEG)), math.sin(math.radians(BE_LEG)))
        kit.roller_pad(doc, art.add(art.add(ank, (ld[1], -ld[0]), -11), ld, -6), 7)


def back_ext_pose(t, h=None):
    td, n = tframe(t)
    s = shoulder(BE_HIP, t)
    g = art.add(art.add(s, n, 13), td, -12)
    leg = (BE_LEG, BE_LEG, BE_LEG - 90)
    return body(BE_HIP, t, h=h, lN=leg, lF=(BE_LEG - 2, BE_LEG - 2, BE_LEG - 92), gN=g, gF=art.add(g, td, 3),
                eN=1, eF=1)


# ==== hip thrusts =====================================================================================

HT_EDGE = (148, 218)  # bench edge under the shoulder blades
HT_ANK = (264, ANK)


HT_REST = dict(back=10, along=18)  # bench versions: shoulder blades (not the top of the shoulder) on the pad edge


def thrust_hip(t, edge=HT_EDGE, back=15, along=8):
    """Upper back rests on the bench edge: shoulder and hip for a torso angle t (≈180 = flat, head left).
    The shoulder joint sits `back` px off the edge (towards the chest) and `along` px past it (towards the head)."""
    td, n = tframe(t)
    s = art.add(art.add(edge, n, back), td, along)
    return pt(s, t, -TOR)


def thrust_pose(t, ank=HT_ANK, bar=True, legF=None, edge=HT_EDGE, back=15, along=8, **kw):
    hip = thrust_hip(t, edge, back, along)
    td, n = tframe(t)
    if bar:
        b = art.add(hip, n, 20)
        g = dict(gN=art.add(b, td, -2), gF=art.add(b, td, -6), eN=1, eF=1)
    else:
        s = shoulder(hip, t)
        g = dict(gN=(s[0] + 36, GROUND - 6), gF=(s[0] + 30, GROUND - 6), eN=1, eF=1, hN=0, hF=0)
    p = body(hip, t, h=t + 18, ankN=ank, ankF=(ank[0] - 4, ank[1]), kN=-1, kF=-1, **g, **kw)
    if legF:
        p["lF"] = legF
    return p


def hip_thrust_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    if layer == "back":
        floor(doc, 200, 120)
        kit.flat_bench(doc, 56, HT_EDGE[0] + 4, HT_EDGE[1])
    else:
        bar_end(doc, art.add(j["hip"], n, 20))


# -- hip thrust machine: back pad, padded lever over the hips pivoting low behind the back pad, cable to a stack
HTM_PIVOT = (118, 234)


def hip_thrust_machine_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    pad_c = art.add(j["hip"], n, 19)
    if layer == "back":
        floor(doc, 170, 140)
        # Weight stack column behind the back pad.
        art.shroud(doc, 26, 104, GROUND - 4, 44)
        st = art.stack(doc, 31, 118, GROUND - 4, 34, 10, max(0, (222 - pad_c[1]) * 0.5))
        art.tube(doc, (80, GROUND - 2), (80, 92), 8)
        art.tube(doc, (22, 92), (86, 92), 8)
        art.pulley(doc, (st[0], 99), 5.5)
        art.pulley(doc, (80, 99), 5.5)
        art.pulley(doc, (86, 236), 5.5)
        art.cable(doc, [st, (st[0], 93.5), (80, 93.5)])
        art.cable(doc, [(85.5, 99), (91.5, 236), (HTM_PIVOT[0], HTM_PIVOT[1] + 6)])
        kit.feet(doc, 18, 300)
        doc.add(f'<rect x="150" y="{GROUND - 6}" width="140" height="5" rx="2" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.6"/>')
        art.tube(doc, (136, HT_EDGE[1] + 8), (150, GROUND - 2), 8, "butt")
        # Lever arm (far side) from the pivot cam to the hip pad.
        art.tube(doc, HTM_PIVOT, pad_c, 8)
        art.tube(doc, HTM_PIVOT, (HTM_PIVOT[0], GROUND - 2), 9, "butt")
        art.pulley(doc, HTM_PIVOT, 7)
        slab(doc, (96, HT_EDGE[1] - 14), (HT_EDGE[0] + 6, HT_EDGE[1]), 12, (140, 160))
        art.tube(doc, (104, HT_EDGE[1] - 6), (100, GROUND - 2), 6, "butt")
    else:
        d = norm2(HTM_PIVOT, pad_c)
        art.tube(doc, art.add(pad_c, d, -34), pad_c, 7)
        kit.roller_pad(doc, pad_c, 11)


def norm2(a, b):
    """Unit vector a→b."""
    return art.norm(art.sub(b, a))


# -- single-leg hip thrust: shoulders on the sofa edge
SOFA_EDGE = (148, 222)


def sofa(doc, x0, x1, top):
    """Sofa seen from the side: frame, seat cushion (top at `top`), backrest and arm at the left."""
    fab = doc.box_grad([(0, "#5B6B85"), (1, "#3B475A")])
    doc.add(f'<rect x="{x0:.1f}" y="{top + 12:.1f}" width="{x1 - x0:.1f}" height="{GROUND - 8 - top - 12:.1f}" rx="4" '
            f'fill="{fab}" stroke="#0A0B0D" stroke-width="0.8"/>')
    doc.add(f'<rect x="{x0 - 6:.1f}" y="{top - 40:.1f}" width="22" height="{GROUND - 8 - top + 40:.1f}" rx="7" '
            f'fill="{fab}" stroke="#0A0B0D" stroke-width="0.8"/>')
    cush = doc.box_grad([(0, "#6D7E9A"), (1, "#4A576D")])
    doc.add(f'<rect x="{x0 + 12:.1f}" y="{top:.1f}" width="{x1 - x0 - 12:.1f}" height="14" rx="6" fill="{cush}" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>')
    for x in (x0 + 8, x1 - 10):
        doc.add(f'<rect x="{x:.1f}" y="{GROUND - 8:.1f}" width="5" height="7" fill="#20242A"/>')


def sl_thrust_pose(t, legF):
    """Single-leg hip thrust: shoulder blades on the sofa edge the whole time, arms reaching back near straight
    over the cushion to hold the sofa arm (not propped on the floor, elbows never bent backwards), free leg held up."""
    hip = thrust_hip(t, SOFA_EDGE, **HT_REST)
    s = shoulder(hip, t)
    g = (s[0] - 80, s[1] + 10)
    p = body(hip, t, h=t + 18, ankN=HT_ANK, ankF=(HT_ANK[0] - 4, ANK), gN=g, gF=(g[0] + 5, g[1] - 1), eN=1, eF=1,
             hN=180, hF=180, lit_sides="N")
    p["lF"] = legF
    return p


def sl_thrust_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 120)
        sofa(doc, 52, SOFA_EDGE[0] + 6, SOFA_EDGE[1])


# ==== single-leg: split squats, lunges, step-ups ====================================================

def arms_for(hip, t, arms):
    """Arm targets: 'db' (dumbbells hanging), 'bar' (bar on the back), 'hips' (hands on the hips)."""
    td, n = tframe(t)
    s = shoulder(hip, t)
    if arms == "db":
        g = (s[0] + 3, s[1] + ARM)
        return dict(gN=g, gF=(g[0] - 4, g[1] - 1), eN=1, eF=1)
    if arms == "bar":
        g = art.add(back_bar(hip, t), n, 4)
        return dict(gN=g, gF=art.add(g, td, 2), eN=1, eF=1, hN=t - 20, hF=t - 20)
    g = art.add(art.add(hip, td, 18), n, 6)
    return dict(gN=g, gF=art.add(g, n, -10), eN=1, eF=1, hN=t + 170, hF=t + 170)


def split_pose(hip, t, front, rear, rear_foot, arms="db", front_foot=0, h=None, **kw):
    """Near leg in front (the working leg), far leg behind."""
    return body(hip, t, h=h, ankN=front, ankF=rear, kN=-1, kF=-1, fN=front_foot, fF=rear_foot, lit_sides="N",
                **arms_for(hip, t, arms), **kw)


SPLIT_F = (238, ANK)
SPLIT_R = (130, GROUND - 13)


def lunge_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 186, 100)
    dbs(doc, j, layer)


def split_frames(arms, view_inset="tr"):
    return ins([
        split_pose((194, 166), -88, SPLIT_F, SPLIT_R, 44, arms),
        split_pose((190, 190), -86, SPLIT_F, SPLIT_R, 46, arms),
        split_pose((186, 212), -84, SPLIT_F, SPLIT_R, 48, arms),
    ], view_inset)


def bw_split_scene(doc, j, layer):
    if layer == "back":
        replant(j, "F", SPLIT_R)
    bw_scene(doc, j, layer)


def bar_split_planted_scene(doc, j, layer):
    if layer == "back":
        replant(j, "F", SPLIT_R)
    bar_split_scene(doc, j, layer)


def bar_split_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 186, 100)
        kit.rack(doc, 84, hook_y=84, safety_y=204)
    else:
        bar_end(doc, kit.on_back(j))


def reverse_lunge_frames(arms):
    return ins([
        split_pose((232, 152), -90, SPLIT_F, (SPLIT_F[0] - 5, ANK), 0, arms),
        split_pose((214, 178), -87, SPLIT_F, (170, GROUND - 22), 62, arms),
        split_pose((190, 212), -84, SPLIT_F, SPLIT_R, 48, arms),
    ], "tr")


# -- walking lunge: the far (rear) foot stays, the near leg steps forward
WL_R = (150, ANK)


def walking_lunge_frames():
    return ins([
        split_pose((154, 152), -90, (158, ANK), WL_R, 0, "db"),
        split_pose((188, 166), -88, (236, GROUND - 16), (148, GROUND - 6), 24, "db", front_foot=-14),
        split_pose((202, 212), -84, (252, ANK), (148, GROUND - 13), 48, "db"),
    ], "tr")


# -- Bulgarian split squat: rear foot laces-down on a bench
BSS_BENCH = 212
BSS_R = (140, BSS_BENCH - 6)
BSS_F = (252, ANK)


def bss_scene(doc, j, layer):
    if layer == "back":
        replant(j, "F", BSS_R)
        floor(doc, 190, 110)
        kit.flat_bench(doc, 50, 150, BSS_BENCH)
    dbs(doc, j, layer)


# -- step-up onto a box (knee-high)
BOX_X, BOX_W, BOX_H = 214, 80, 58
BOX_TOP = GROUND - BOX_H


def step_up_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 220, 110)
        kit.box(doc, BOX_X, BOX_W, BOX_H)
    dbs(doc, j, layer)


# ==== knee machines ===================================================================================

def lever(doc, pivot, end, w=7):
    art.tube(doc, pivot, end, w)
    art.pulley(doc, pivot, 6.5)


def column(doc, x, top, lift, plates=10, w=34):
    """Weight-stack column (shroud + stack + top pulley); returns the top pulley centre."""
    art.tube(doc, (x + w + 12, GROUND - 2), (x + w + 12, top - 4), 8)
    art.shroud(doc, x - 5, top + 10, GROUND - 4, w + 10)
    st = art.stack(doc, x, top + 24, GROUND - 4, w, plates, lift)
    art.tube(doc, (x - 8, top - 4), (x + w + 16, top - 4), 8)
    p = (st[0], top + 3)
    art.pulley(doc, p, 5.5)
    art.cable(doc, [st, (st[0], top - 2.5)])
    return p


# -- leg extension
LE_HIP = (176, 196)
LE_T = -100


def leg_ext_scene(doc, j, layer):
    knee, ank = j["kneeN"], j["ankleN"]
    sd = norm2(knee, ank)
    roller = art.add(art.add(ank, sd, -7), (sd[1], -sd[0]), 10)
    if layer == "back":
        floor(doc, 170, 130)
        shin = math.degrees(math.atan2(sd[1], sd[0]))
        p = column(doc, 44, 60, max(0, (96 - shin) * 0.3))
        hip = LE_HIP
        td, n = tframe(LE_T)
        kit.feet(doc, 34, 262)
        # Cable from the stack over the column top, down behind the seat to the cam at the knee.
        art.pulley(doc, (96, 236), 5.5)
        art.cable(doc, [(p[0] + 5.5, p[1]), (96 + 5.5, 56), (101.5, 236), (knee[0] - 6, 236), (knee[0] - 6, knee[1] + 8)])
        # Seat, backrest, frame.
        art.tube(doc, (hip[0], hip[1] + 18), (hip[0], GROUND - 2), 9, "butt")
        art.tube(doc, (100, GROUND - 2), (knee[0] + 14, GROUND - 2), 7)
        art.tube(doc, (knee[0] - 6, knee[1] + 14), (knee[0] + 8, GROUND - 2), 8, "butt")
        art.tube(doc, (hip[0] - 34, hip[1] + 16), (hip[0] - 44, GROUND - 2), 7, "butt")
        slab(doc, (hip[0] - 20, hip[1] + 13), (knee[0] - 6, hip[1] + 13), 12, hip)
        slab(doc, art.add(art.add(hip, td, 2), n, -15), art.add(art.add(hip, td, 80), n, -15), 12, hip)
        lever(doc, knee, roller)
    else:
        kit.roller_pad(doc, roller, 9)
        kit.handle(doc, grip(j))


def leg_ext_pose(shin):
    knee = pt(LE_HIP, 2, TH)
    ank = pt(knee, shin, SH)
    g = (LE_HIP[0] + 14, LE_HIP[1] + 10)
    return body(LE_HIP, LE_T, h=-86, ankN=ank, ankF=art.add(ank, (-3, 0)), fN=shin - 90, fF=shin - 90,
                gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1)


# -- lying leg curl (plate-loaded lever)
LC_HIP = (196, 196)
LC_T = -6


def leg_curl_scene(doc, j, layer):
    knee, ank = j["kneeN"], j["ankleN"]
    sd = norm2(knee, ank)
    back = (-sd[1], sd[0])  # back of the shin
    roller = art.add(art.add(ank, sd, -6), back, 10)
    if layer == "back":
        floor(doc, 190, 140)
        hip = LC_HIP
        # Bench: hip hump + chest pad on the frame, legs to the floor.
        art.tube(doc, (124, 228), (300, 228), 7)
        for x in (138, 284):
            art.tube(doc, (x, 228), (x, GROUND - 2), 8, "butt")
        kit.feet(doc, 118, 160)
        kit.feet(doc, 262, 306)
        slab(doc, (hip[0] - 50, hip[1] + 21), (hip[0] + 6, hip[1] + 14), 12, hip)
        slab(doc, (hip[0] + 6, hip[1] + 14), (hip[0] + 108, hip[1] + 8), 12, hip)
        art.tube(doc, (300, 228), (306, 214), 6)
        # Lever from the knee-axis cam to the ankle roller, plate horn on it.
        horn = art.add(art.add(knee, sd, 20), back, 16)
        art.tube(doc, art.add(knee, sd, 16), horn, 5)
        art.plate(doc, horn, 18)
        lever(doc, knee, roller)
        art.tube(doc, (knee[0], knee[1] + 6), (knee[0] + 8, 228), 7)
    else:
        kit.roller_pad(doc, roller, 8.5)
        kit.handle(doc, grip(j))


def leg_curl_pose(shin):
    knee = pt(LC_HIP, 178, TH)
    ank = pt(knee, shin, SH)
    s = shoulder(LC_HIP, LC_T)
    g = (s[0] + 40, s[1] + 40)  # handles under the front of the pad: upper arms down past it, forearms forward
    return body(LC_HIP, LC_T, h=6, lN=(178, shin, shin + 90), lF=(177, shin - 2, shin + 88),
                gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1)


# -- seated calf raise (plate-loaded): toes on the block edge, knee pad on a lever pivoting at the front
SC_HIP = (154, 198)
SC_TOE = (240, GROUND - 22)
SC_PIVOT = (304, 236)


def seated_calf_scene(doc, j, layer):
    knee, hip = j["kneeN"], j["hip"]
    td = norm2(hip, knee)
    pad = art.add(art.add(knee, td, -9), (td[1], -td[0]), 16)
    if layer == "back":
        floor(doc, 200, 130)
        # Seat on a post, frame on the floor, toe block.
        art.tube(doc, (SC_HIP[0], SC_HIP[1] + 18), (SC_HIP[0], GROUND - 2), 9, "butt")
        kit.feet(doc, 110, SC_PIVOT[0] + 20)
        slab(doc, (SC_HIP[0] - 30, SC_HIP[1] + 14), (SC_HIP[0] + 24, SC_HIP[1] + 14), 12, SC_HIP)
        step_block(doc, SC_TOE[0] - 10, 36, GROUND - SC_TOE[1] - 1)
        art.tube(doc, SC_PIVOT, (SC_PIVOT[0], GROUND - 2), 10, "butt")
        # Lever from the front pivot back over the knees, plate horn on it.
        d = norm2(SC_PIVOT, pad)
        lever(doc, SC_PIVOT, art.add(pad, d, 4), 8)
        horn = art.add(SC_PIVOT, d, 30)
        art.tube(doc, horn, art.add(horn, (d[1], -d[0]), -12), 5)
        art.plate(doc, art.add(horn, (d[1], -d[0]), -6), 19)
    else:
        doc.add(f'<g transform="rotate({math.degrees(math.atan2(td[1], td[0])):.1f} {pad[0]:.1f} {pad[1]:.1f})">'
                f'<rect x="{pad[0] - 14:.1f}" y="{pad[1] - 6:.1f}" width="28" height="12" rx="5" fill="#1E2227" '
                f'stroke="#0A0B0D" stroke-width="0.8"/></g>')
        kit.handle(doc, grip(j))


def seated_calf_pose(f):
    ank = pt(SC_TOE, f, -FT)
    td = norm2(SC_HIP, ank)
    p = body(SC_HIP, -92, ankN=ank, ankF=art.add(ank, (-3, 0)), fN=f, fF=f, kN=-1, kF=-1)
    j = art.F.place(p)
    k = j["kneeN"]
    g = (k[0] - 8, k[1] - 20)
    return body(SC_HIP, -92, ankN=ank, ankF=art.add(ank, (-3, 0)), fN=f, fF=f, kN=-1, kF=-1,
                gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1, hN=0, hF=0)


# ==== calves / shins =================================================================================

# -- standing calf raise in the Smith machine, toes on a block
SCR_TOE = (214, GROUND - 16)
SCR_BX = 188


def calf_hip(f, toe):
    ank = pt(toe, f, -FT)
    return (ank[0] - 2, ank[1] - TH - SH + 0.5), ank


def smith_calf_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 110)
        smith_frame(doc, SCR_BX, top=-4)
        step_block(doc, SCR_TOE[0] - 9, 50, GROUND - SCR_TOE[1] - 1)
    else:
        smith_bar(doc, kit.on_back(j))


def smith_calf_pose(f):
    hip, ank = calf_hip(f, SCR_TOE)
    return body(hip, -90, ankN=ank, ankF=art.add(ank, (-3, 0)), fN=f, fF=f, **arms_for(hip, -90, "bar"))


# -- single-leg calf raise on a step (dumbbell in the working-side hand, other hand on the wall)
SLC_TOE = (206, GROUND - 16)
SLC_WALL = 262


def sl_calf_pose(f, db=True):
    hip, ank = calf_hip(f, SLC_TOE)
    s = shoulder(hip, -90)
    gF = (SLC_WALL - 4, s[1] + 30)
    gN = (s[0] + 3, s[1] + ARM) if db else (SLC_WALL - 4, s[1] + 36)
    return body(hip, -90, ankN=ank, fN=f, gN=gN, gF=gF, eN=1, eF=1, hF=-80,
                hN=None if db else -80, lF=(100, 160, 70), lit_sides="N")


def sl_calf_scene(doc, j, layer, db=True):
    if layer == "back":
        floor(doc, 210, 80)
        kit.wall(doc, SLC_WALL, 14, -60)
        step_block(doc, SLC_TOE[0] - 9, 52, GROUND - SLC_TOE[1] - 1)
    if db:
        if layer == "front":
            art.db_end(doc, grip(j), 10)


def bw_calf_scene(doc, j, layer):
    sl_calf_scene(doc, j, layer, db=False)


# -- wall tibialis raise: back and hips on the wall, heels a foot out, toes up
TIB_WALL = 106
TIB_ANK = (190, ANK)


def tib_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 170, 80)
        kit.wall(doc, TIB_WALL, 14, -60)


def tib_pose(f):
    hip = (TIB_WALL + 14 + 15, 0)
    dx = TIB_ANK[0] - hip[0]
    hip = (hip[0], TIB_ANK[1] - math.sqrt(108.5 ** 2 - dx * dx))
    s_t = -93
    s = shoulder(hip, s_t)
    g = (s[0] + 10, s[1] + 82)
    return body(hip, s_t, h=-90, ankN=TIB_ANK, ankF=(TIB_ANK[0] - 3, ANK), fN=f, fF=f, kN=-1, kF=-1,
                gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1)


# ==== Smith machine squat ============================================================================

SM_BX = 182
SM_ANK = (SM_BX + 22, ANK)


def smith_squat_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 110)
        smith_frame(doc, SM_BX, top=24)
    else:
        smith_bar(doc, kit.on_back(j))


def smith_squat_pose(y, t):
    hip = (SM_BX - back_bar((0, 0), t)[0], y)
    return body(hip, t, ankN=SM_ANK, ankF=(SM_ANK[0] - 4, ANK), **arms_for(hip, t, "bar"))


# ==== kneeling / floor hamstring & quad work =========================================================

KNEE_Y = GROUND - 8  # kneeling: knee joint above the pad


def kneel_pose(a, knee, arms, h=None, **kw):
    """Kneeling with hips locked straight: thigh and torso both at angle a; shins on the floor behind."""
    hip = pt(knee, a, TH)
    return body(hip, a, h=h, lN=(a + 180, 180, 180), lF=(a + 180, 181, 181), **arms(hip, a), **kw)


# -- assisted Nordic curl: ankles under a roller, band from a high anchor behind to the chest
NC_KNEE = (176, KNEE_Y)
NC_POST = 84
NC_ANCHOR = (NC_POST + 4, 50)


def nordic_arms(hip, a):
    td, n = tframe(a)
    s = shoulder(hip, a)
    g = art.add(art.add(s, n, 30), td, -26)
    return dict(gN=g, gF=art.add(g, td, 4), eN=1, eF=1, hN=a + 90, hF=a + 90)


def nordic_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    chest = art.add(art.add(j["shoulder"], td, -14), n, -10)
    ank = pt(NC_KNEE, 180, SH)
    if layer == "back":
        floor(doc, 160, 110)
        kit.mat(doc, 96, 210)
        kit.post(doc, NC_POST, NC_ANCHOR[1])
        art.tube(doc, (NC_POST, ank[1] - 12), (ank[0] - 2, ank[1] - 12), 6)
        art.tube(doc, (NC_POST - 8, NC_ANCHOR[1]), (NC_POST + 12, NC_ANCHOR[1]), 6)
        kit.band(doc, NC_ANCHOR, chest, "#2E7DD1")
    else:
        kit.roller_pad(doc, (ank[0] + 2, ank[1] - 12), 7)


# -- reverse Nordic: kneel tall, lean back with the hips locked
RN_KNEE = (216, KNEE_Y)


def rev_nordic_arms(hip, a):
    s = shoulder(hip, a)
    g = pt(s, a + 92, ARM - 2)
    return dict(gN=g, gF=art.add(g, (-3, 2)), eN=1, eF=1)


def rev_nordic_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 90)
        kit.mat(doc, 130, 250)


# -- TRX hamstring curl: shoulders on the floor, heels in the cradles, hips high
TRX_S = (122, GROUND - 13)
TRX_A = (288, 84)
TRX_R = 137


def trx_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 120)
        kit.mat(doc, 70, 330)
        art.tube(doc, (TRX_A[0] - 34, TRX_A[1] - 8), (TRX_A[0] + 34, TRX_A[1] - 8), 9)
        doc.add(f'<circle cx="{TRX_A[0]:.1f}" cy="{TRX_A[1] - 2:.1f}" r="4" fill="none" stroke="#C8A06A" stroke-width="2.4"/>')
        kit.strap(doc, art.add(j["ankleF"], (2, -4)), TRX_A, handle=False)
    else:
        kit.strap(doc, art.add(j["ankleN"], (2, -4)), TRX_A, handle=False)
        a = j["ankleN"]
        doc.add(f'<rect x="{a[0] - 5:.1f}" y="{a[1] - 9:.1f}" width="12" height="9" rx="3" fill="#1E2227" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')


def trx_pose(t, ank_x):
    td, n = tframe(t)
    hip = pt(TRX_S, t, -TOR)
    ank = (ank_x, TRX_A[1] + math.sqrt(TRX_R ** 2 - (ank_x - TRX_A[0]) ** 2))
    g = (TRX_S[0] + 78, GROUND - 6)
    return body(hip, t, h=182, ankN=ank, ankF=art.add(ank, (-2, -2)), kN=-1, kF=-1, fN=-96, fF=-98,
                gN=g, gF=(g[0] - 4, g[1]), eN=1, eF=1, hN=0, hF=0)


# ==== frontal-plane: Cossack squat, hip adduction / abduction =======================================

CS_HIP_X = 200


def cossack_pose(hip, t, ankN, ankF, fF, front=True):
    td, n = tframe(t)
    s = shoulder(hip, t)
    c = art.add(s, td, -22)
    return body(hip, t, ankN=ankN, ankF=ankF, kN=-1, kF=1, fN=0, fF=fF, gN=art.add(c, n, 5), gF=art.add(c, n, -5),
                eN=1, eF=-1, hN=-90, hF=-90, front=front)


def goblet_front_arms(j, fwd=24, down=22, gap=5):
    """Front view of a goblet / horn hold: the hands meet in front of the chest (towards the camera) and the
    elbows hang down under them. Solved as a 3D chain and projected, so the forearms point at the camera and
    foreshorten instead of folding across the chest in the picture plane (each elbow stays on its own side)."""
    from scenes_arms_core import _ik3
    td, n = kit.torso_frame(j)
    c = art.add(j["shoulder"], td, -down)
    for s, sx in (("N", 1), ("F", -1)):
        sh = j["shoulder" + s]
        g2 = art.add(c, n, sx * gap)
        g = (g2[0], g2[1], float(fwd))
        out = art.sub(sh, j["shoulder"])
        out = art.norm(out) if math.hypot(*out) > 0.5 else (sx * 1.0, 0.0)
        pole = (-td[0] + 0.35 * out[0], -td[1] + 0.35 * out[1], 0.3)
        e = _ik3((sh[0], sh[1], 0.0), g, UA, FA + HA / 2, pole)
        d = art.norm((g[0] - e[0], g[1] - e[1])) if math.dist(g[:2], e[:2]) > 0.5 else (-sx * 1.0, 0.0)
        fl = math.dist(g, e)  # 3D forearm + half hand
        scale = math.dist(g[:2], e[:2]) / fl if fl else 1
        j["elbow" + s] = (e[0], e[1])
        j["wrist" + s] = art.add(g2, d, -HA / 2 * scale)
        j["hand" + s] = art.add(g2, d, HA / 2 * scale)


def cossack_scene(doc, j, layer):
    if layer == "back":
        goblet_front_arms(j)
        floor(doc, 200, 110)
    else:
        g = ((j["handN"][0] + j["handF"][0]) / 2, (j["handN"][1] + j["handF"][1]) / 2 + 2)
        kit.kettlebell(doc, g, r=11)


# -- seated hip adduction / abduction machine, front (adduction) or back (abduction) view
HA_HIP = (200, 142)


def hip_machine_scene(doc, j, layer, outer, backrest=True):
    if layer == "back":
        seated_front_legs(j)
    kn, kf = j["kneeN"], j["kneeF"]
    spread = abs(kn[0] - kf[0])
    if layer == "back":
        floor(doc, 214, 130)
        # Weight stack column on the right, cable down to the pivot under the seat.
        art.shroud(doc, 300, 70, GROUND - 4, 44)
        st = art.stack(doc, 305, 84, GROUND - 4, 34, 11, max(0, (spread - 60) * 0.2 if outer else (150 - spread) * 0.2))
        art.tube(doc, (296, 52), (352, 52), 8)
        art.tube(doc, (352, 52), (352, GROUND - 2), 8)
        art.pulley(doc, (st[0], 59), 5.5)
        art.pulley(doc, (296, 59), 5.5)
        art.pulley(doc, (296, 244), 5.5)
        art.cable(doc, [st, (st[0], 53.5), (296, 53.5)])
        art.cable(doc, [(290.5, 59), (290.5, 244), (200, 249.5)])
        kit.feet(doc, 140, 356)
        art.tube(doc, (200, 160), (200, GROUND - 2), 12, "butt")
        if backrest:
            g = doc.box_grad([(0, "#3A4048"), (0.3, "#1E2227"), (1, "#121417")], vertical=False)
            doc.add(f'<rect x="166" y="66" width="68" height="84" rx="9" fill="{g}" stroke="#0A0B0D" stroke-width="0.8"/>')
            art.tube(doc, (200, 150), (200, 160), 10)
        g = doc.box_grad([(0, "#3A4048"), (0.3, "#1E2227"), (1, "#121417")])
        doc.add(f'<rect x="168" y="147" width="64" height="18" rx="7" fill="{g}" stroke="#0A0B0D" stroke-width="0.8"/>')
        # Lever arms and foot pegs run behind the shins.
        for side in "NF":
            k, a = j["knee" + side], j["ankle" + side]
            s = 1 if k[0] > HA_HIP[0] else -1
            pad_c = hip_pad_centre(k, s, outer)
            art.tube(doc, (HA_HIP[0] + s * 10, 168), (pad_c[0], pad_c[1] + 16), 7)
            art.tube(doc, (pad_c[0], pad_c[1] + 16), (a[0] + s * 4, a[1] + 8), 5)
            art.tube(doc, (a[0] - 10, a[1] + 8), (a[0] + 10, a[1] + 8), 5)
        art.pulley(doc, (200, 170), 6)
    else:
        # Knee pads: on the outside of the knees (abduction) or between them (adduction), never over the legs.
        for side in "NF":
            k = j["knee" + side]
            s = 1 if k[0] > HA_HIP[0] else -1
            pad_c = hip_pad_centre(k, s, outer)
            g = doc.box_grad([(0, "#3A4048"), (0.3, "#1E2227"), (1, "#121417")], vertical=False)
            doc.add(f'<rect x="{pad_c[0] - 5:.1f}" y="{pad_c[1] - 15:.1f}" width="10" height="30" rx="4.5" fill="{g}" '
                    f'stroke="#0A0B0D" stroke-width="0.8"/>')


def hip_pad_centre(knee, s, outer):
    """Centre of the knee pad on side s (+1 = right of the seat): just clear of the knee, outside or inside."""
    return (knee[0] + s * (15 if outer else -15), knee[1] + 2)


def seated_front_legs(j):
    """Seated, seen from the front / back: the thighs point at / away from the camera, so they read short (knees
    just below hip height); the shins hang to the foot pegs, the feet point at the camera."""
    for side in "NF":
        hp, k = j["hip" + side], j["knee" + side]
        s = 1 if k[0] > HA_HIP[0] else -1
        knee = (k[0], hp[1] + 12)
        ank = (knee[0] + s * 2, knee[1] + SH - 2)
        j["knee" + side] = knee
        j["ankle" + side] = ank
        j["toe" + side] = (ank[0] + s * 4, ank[1] + 6)


def adduction_scene(doc, j, layer):
    hip_machine_scene(doc, j, layer, outer=False)


def abduction_scene(doc, j, layer):
    hip_machine_scene(doc, j, layer, outer=True)


def hip_machine_pose(thigh, view):
    return body(HA_HIP, -90, lN=(thigh, 90, 0), lF=(180 - thigh, 90, 180),
                gN=(HA_HIP[0] + 30, HA_HIP[1] + 14), gF=(HA_HIP[0] - 30, HA_HIP[1] + 14), eN=-1, eF=1, front=view)


SCENES = {
    "front-squat": (front_squat_scene, ins([
        front_squat_pose((198, 152), -90),
        front_squat_pose((184, 186), -80),
        front_squat_pose((172, 216), -72),
    ], "tr"), (52, 28, 332)),
    "goblet-squat": (goblet_scene, [
        goblet_pose((198, 152), -90),
        goblet_pose((184, 186), -80),
        goblet_pose((172, 218), -70),
    ], (44, 28, 332)),
    "bw-squat": (bw_squat_scene, [
        bw_squat_pose((198, 152), -90, (6, 82)),  # arms hang, then rise forward (near straight) for balance
        bw_squat_pose((182, 188), -78, (70, 36)),
        bw_squat_pose((168, 218), -64, (82, 8)),
    ], (50, 28, 332)),
    "hack-squat": (hack_scene, ins([hack_pose(0), hack_pose(0.5), hack_pose(1)], "tr"), (56, 32, 324)),
    "leg-press": (leg_press_scene, ins([leg_press_pose(0), leg_press_pose(0.5), leg_press_pose(1)], "tr"), (50, 44, 314)),
    "leg-press-calf-raise": (calf_press_scene, ins([calf_press_pose(LP_R - 120), calf_press_pose(LP_R - 90),
                                                    calf_press_pose(LP_R - 58)], "tr"), (50, 44, 314)),
    "deadlift": (deadlift_scene, ins([
        hinge_pose((DL_X, GROUND - 25), -18, DL_ANK, dx=11, h=-30),
        hinge_pose((DL_X, 206), -44, DL_ANK, dx=4, h=-50),
        hinge_pose((DL_X - 1, 164), -89, DL_ANK, dx=-12),
    ], "tr"), (44, 28, 332)),
    "trap-bar-deadlift": (trap_bar_scene, ins([
        hinge_pose((TB_X, GROUND - 38), -38, (TB_X + 4, ANK), dx=3, h=-46),
        hinge_pose((TB_X, 204), -60, (TB_X + 4, ANK), dx=2),
        hinge_pose((TB_X, 166), -90, (TB_X + 4, ANK), dx=0),
    ], "tr"), (40, 28, 332)),
    "rdl": (deadlift_scene, ins([
        hinge_pose((DL_X - 1, 164), -89, DL_ANK, dx=-12),
        hinge_pose((DL_X, 190), -58, DL_ANK, dx=-2),
        hinge_pose((DL_X, 214), -27, DL_ANK, dx=4, h=-20),
    ], "tr"), (44, 28, 332)),
    "db-rdl": (db_rdl_scene, ins([
        hinge_pose((DL_X - 2, 164), -89, DL_ANK, dx=-10),
        hinge_pose((DL_X, 190), -58, DL_ANK, dx=-2),
        hinge_pose((DL_X, 214), -27, DL_ANK, dx=4, h=-20),
    ], "tr"), (44, 28, 332)),
    "good-morning": (good_morning_scene, ins([  # soft knees only, torso down to about parallel
        gm_pose((198, 152), -90),
        gm_pose((183, 155), -48, h=-42),
        gm_pose((166, 159), 0, h=8),
    ], "tr"), (52, 28, 332)),
    "band-good-morning": (band_gm_scene, ins([
        band_gm_pose((198, 152), -90),
        band_gm_pose((182, 158), -52, h=-46),
        band_gm_pose((166, 164), -14, h=-4),
    ], "tr"), (44, 28, 332)),
    "single-leg-rdl": (sl_rdl_scene, ins([
        sl_rdl_pose((216, 152), -90, (100, 96, 8)),
        sl_rdl_pose((200, 156), -46, (134, 134, 44)),
        sl_rdl_pose((188, 160), -6, (176, 176, 86), h=0),
    ], "tl"), (40, 28, 332)),
    "bw-sl-rdl": (bw_sl_rdl_scene, ins([
        sl_rdl_pose((216, 152), -90, (100, 96, 8)),
        sl_rdl_pose((200, 156), -46, (134, 134, 44)),
        sl_rdl_pose((188, 160), -6, (176, 176, 86), h=0),
    ], "tl"), (40, 28, 332)),
    "cable-pull-through": (pull_through_scene, ins([
        pt_pose((166, 168), -18, (174, 222), h=-5),
        pt_pose((180, 160), -50, (206, 216), h=-44),
        pt_pose((198, 152), -88, (216, 166)),
    ], "tr"), (26, 28, 332)),
    "back-extension": (back_ext_scene, ins([
        back_ext_pose(52, h=48),
        back_ext_pose(4, h=2),
        back_ext_pose(-44, h=-42),
    ], "tl"), (40, 30, 330)),
    "hip-thrust": (hip_thrust_scene, ins([thrust_pose(206, **HT_REST), thrust_pose(193, **HT_REST),
                                          thrust_pose(180, **HT_REST)], "tl"),
                   (44, 82, 260)),
    "hip-thrust-machine": (hip_thrust_machine_scene, ins([thrust_pose(206, bar=False), thrust_pose(193, bar=False),
                                                         thrust_pose(180, bar=False)], "tr"), (16, 70, 284)),
    "sl-hip-thrust": (sl_thrust_scene, ins([
        sl_thrust_pose(206, (-70, 8, -82)),
        sl_thrust_pose(193, (-80, 0, -90)),
        sl_thrust_pose(180, (-90, -8, -98)),
    ], "tl"), (40, 70, 276)),
    "bw-split-squat": (bw_split_scene, split_frames("hips"), (48, 28, 332)),
    "barbell-split-squat": (bar_split_planted_scene, split_frames("bar"), (40, 28, 332)),
    "reverse-lunge": (lunge_scene, reverse_lunge_frames("db"), (48, 28, 332)),
    "bw-reverse-lunge": (bw_scene, reverse_lunge_frames("hips"), (48, 28, 332)),
    "walking-lunge": (lunge_scene, walking_lunge_frames(), (48, 28, 332)),
    "bulgarian-split-squat": (bss_scene, ins([
        split_pose((210, 166), -84, BSS_F, BSS_R, 186),
        split_pose((205, 192), -80, BSS_F, BSS_R, 186),
        split_pose((198, 216), -76, BSS_F, BSS_R, 186),
    ], "tr"), (40, 28, 332)),
    "step-up": (step_up_scene, ins([
        split_pose((198, 166), -72, (238, BOX_TOP - 4), (182, ANK), 0, h=-80),
        # Trailing foot lifted above the box height before it travels over the edge (never through the box).
        split_pose((230, 116), -86, (240, BOX_TOP - 4), (204, BOX_TOP - 26), 50),
        split_pose((238, 100), -90, (240, BOX_TOP - 4), (234, BOX_TOP - 4), 0),
    ], "tl"), (34, -26, 400)),
    "leg-extension": (leg_ext_scene, ins([leg_ext_pose(100), leg_ext_pose(52), leg_ext_pose(6)], "tr"), (30, 42, 310)),
    "leg-curl": (leg_curl_scene, ins([leg_curl_pose(182), leg_curl_pose(228), leg_curl_pose(266)], "tr"), (40, 52, 300)),
    "seated-calf-raise": (seated_calf_scene, ins([seated_calf_pose(-26), seated_calf_pose(2), seated_calf_pose(30)], "tr"),
                          (60, 60, 290)),
    "standing-calf-raise": (smith_calf_scene, ins([smith_calf_pose(-24), smith_calf_pose(6), smith_calf_pose(36)], "tr"),
                            (14, -14, 388)),
    "db-calf-raise": (sl_calf_scene, ins([sl_calf_pose(-24), sl_calf_pose(6), sl_calf_pose(36)], "tl"), (40, 4, 362)),
    "bw-calf-raise": (bw_calf_scene, ins([sl_calf_pose(-24, False), sl_calf_pose(6, False), sl_calf_pose(36, False)], "tl"),
                      (40, 4, 362)),
    "tib-raise": (tib_scene, ins([tib_pose(0), tib_pose(-24), tib_pose(-48)], "tr"), (40, 28, 332)),
    "smith-squat": (smith_squat_scene, ins([smith_squat_pose(152, -90), smith_squat_pose(188, -80),
                                            smith_squat_pose(216, -68)], "tr"), (30, 10, 350)),
    "nordic-curl": (nordic_scene, ins([kneel_pose(-90, NC_KNEE, nordic_arms), kneel_pose(-56, NC_KNEE, nordic_arms),
                                       kneel_pose(-22, NC_KNEE, nordic_arms, h=-30)], "tr"), (40, 26, 330)),
    "reverse-nordic": (rev_nordic_scene, ins([kneel_pose(-90, RN_KNEE, rev_nordic_arms),
                                              kneel_pose(-108, RN_KNEE, rev_nordic_arms, h=-100),
                                              kneel_pose(-126, RN_KNEE, rev_nordic_arms, h=-112)], "tr"), (60, 26, 330)),
    "trx-hamstring-curl": (trx_scene, ins([trx_pose(171, 300), trx_pose(160, 272), trx_pose(150, 246)], "tl"),
                           (40, 64, 290)),
    "cossack-squat": (cossack_scene, ins([
        cossack_pose((200, 172), -90, (266, ANK), (134, ANK), 180),
        cossack_pose((220, 202), -88, (266, ANK), (134, ANK), 180),
        cossack_pose((238, 224), -84, (266, ANK), (130, GROUND - 8), -95),
    ], "tl"), (36, 28, 332)),
    "hip-adduction": (adduction_scene, ins([hip_machine_pose(42, True), hip_machine_pose(59, True),
                                            hip_machine_pose(76, True)], "tl"), (40, 22, 330)),
    "hip-abduction": (abduction_scene, ins([hip_machine_pose(76, True), hip_machine_pose(59, True),
                                            hip_machine_pose(42, True)], "tl"), (40, 22, 330)),
}
