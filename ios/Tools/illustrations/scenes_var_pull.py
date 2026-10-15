"""Scenes for the #174 catalog extension (pull): row, pull-up and pulldown variations, curls, triceps, grip, shrugs.

Built on the helpers of scenes_upper.py (B / G pose solver, S framing) and scenes_arms_core.py (curls, cable
towers, back-view stands). Same conventions: angles 0 = right, 90 = down, the figure faces right in side view;
static equipment in absolute view-box coordinates, held equipment follows the hands.
"""
import math

import art
import kit
import scenes as S0
import scenes_arms_core as A
import scenes_upper as U
from art import GROUND
from poses import P
from scenes_var_push import custom

B, G, S, fit = U.B, U.G, U.S, U.fit
lerp, deg, chest_pt, circle_x = U.lerp, U.deg, U.chest_pt, U.circle_x
TORSO, UPPER, FORE, HAND = U.TORSO, U.UPPER, U.FORE, U.HAND
THIGH, SHIN = U.THIGH, U.SHIN
FLOOR_Y = U.FLOOR_Y
held_at, along, both, grip_n, grip_f = U.held_at, U.along, U.both, U.grip_n, U.grip_f
floor = U.floor


def seq3(fn):
    return [fn(k) for k in (0, 0.5, 1)]


def tower_box(x, side="L"):
    return U.tower_box(x, side)


# ---- bent-over rows ------------------------------------------------------------------------------

PR_ANKLE = (226, FLOOR_Y)
PR_T = -12
PR_BAR0 = (232, GROUND - 22)  # plates resting on the floor
PR_SH = (236, PR_BAR0[1] - 80)
PR_HIP = art.ang_pt(PR_SH, PR_T + 180, TORSO)


def pendlay_poses():
    a = PR_BAR0
    b = chest_pt(PR_HIP, PR_T, 0.74, 22)

    def f(k):
        g = lerp(a, b, k)
        return B(PR_HIP, PR_T, aN=G(g, 1), aF=G((g[0] - 4, g[1] - 2), 1),
                 lN=G(PR_ANKLE, -1, end=0), lF=G((PR_ANKLE[0] - 4, FLOOR_Y), -1, end=0), h=PR_T + 14)
    return seq3(f)


def plate_bar_scene(r=22):
    def scene(doc, j, layer):
        if layer == "back":
            floor(doc, 200, 80)
        else:
            kit.barbell(doc, kit.grip(j), r)
    return scene


def yates_poses():
    return U.hinge_poses(t=-28, hip=(168, 160), end_u=0.3, end_out=20)


# Meadows row: landmine end beside the front foot, lifter side-on; the bar runs away from the viewer.
MR_HIP = (172, 166)
MR_T = -24
MR_SH = art.ang_pt(MR_HIP, MR_T, TORSO)
MR_ANCHOR = (70, GROUND - 4)
MR_LEGS = dict(lN=G((MR_HIP[0] - 46, FLOOR_Y), -1, end=0), lF=G((MR_HIP[0] + 52, FLOOR_Y), -1, end=0))


def meadows_poses():
    j0 = U.place(B(MR_HIP, MR_T, **MR_LEGS))
    knee = j0["kneeF"]
    a = (MR_SH[0] + 6, MR_SH[1] + 80)
    b = chest_pt(MR_HIP, MR_T, 0.6, 14)

    def f(k):
        g = lerp(a, b, k)
        return B(MR_HIP, MR_T, aN=G(g, 1), aF=G((knee[0] + 2, knee[1] - 7), 1, end=MR_T + 10, wrist=True),
                 h=MR_T + 14, lit_sides="N", **MR_LEGS)
    return seq3(f)


def meadows_scene(doc, j, layer):
    g = kit.grip(j)
    # The hand holds the thick end of the bar just inside the plate: the loaded end is beyond the hand, on the
    # viewer's side (drawn in front), so the weight stays in sight as it rises past the trunk.
    pc = art.add(g, art.norm(art.sub(g, MR_ANCHOR)), 6)
    if layer == "back":
        floor(doc, 170, 120)
        art.tube(doc, g, MR_ANCHOR, 5)
        doc.add(f'<rect x="{MR_ANCHOR[0] - 10:.1f}" y="{GROUND - 8:.1f}" width="20" height="8" rx="2" fill="#2A2E34"/>')
    else:
        art.tube(doc, g, pc, 6)
        art.plate(doc, pc, 17, hub=False)
        doc.add(f'<circle cx="{pc[0]:.1f}" cy="{pc[1]:.1f}" r="3" fill="{art.CHROME}" stroke="#5A616A" stroke-width="0.6"/>')


# Landmine T-bar row: straddling the bar, V-handle hooked under it just behind the plates.
TB_HIP = (168, 164)
TB_T = -38
TB_SH = art.ang_pt(TB_HIP, TB_T, TORSO)
TB_ANCHOR = (40, GROUND - 4)
TB_DROP = 9  # handle grip below the bar


def tb_bar(theta):
    """Point on the bar under the hands for bar angle theta (deg above the floor)."""
    return art.ang_pt(TB_ANCHOR, -theta, TB_L)


TB_L = kit.dist(TB_ANCHOR, (TB_SH[0] + 6, TB_SH[1] + 80 - TB_DROP))


def tb_theta(reach):
    """Smallest bar angle (rising from the floor) at which the handle is `reach` from the shoulder."""
    th = 0.0
    while th < 80:
        p = tb_bar(th)
        if kit.dist(TB_SH, (p[0], p[1] + TB_DROP)) <= reach:
            return th
        th += 0.05
    return th


def tbar_poses():
    th = [tb_theta(r) for r in (80, 58, 38)]

    def f(t):
        p = tb_bar(t)
        g = (p[0], p[1] + TB_DROP)
        return B(TB_HIP, TB_T, aN=G(g, 1), aF=G((g[0] - 3, g[1] - 1), 1),
                 lN=G((TB_HIP[0] + 34, FLOOR_Y), -1, end=0), lF=G((TB_HIP[0] + 30, FLOOR_Y), -1, end=0), h=TB_T + 14)
    return [f(t) for t in th]


def tbar_scene(doc, j, layer):
    g = kit.grip(j)
    p = (g[0], g[1] - TB_DROP)
    if layer == "back":
        floor(doc, 160, 140)
        kit.landmine(doc, p, TB_ANCHOR)
    else:
        d = art.norm(art.sub(p, TB_ANCHOR))
        hook = art.add(p, d, 7)
        art.tube(doc, (g[0] - 8, g[1]), (g[0] + 6, g[1]), 4)
        art.tube(doc, (g[0] + 6, g[1]), hook, 3.2)
        doc.add(f'<circle cx="{g[0]:.1f}" cy="{g[1]:.1f}" r="3" fill="{art.CHROME}"/>')


# ---- standing single-arm cable row ---------------------------------------------------------------

SC_HIP = (176, U.ST_HIP[1] + 4)
SC_T = -84
SC_SH = art.ang_pt(SC_HIP, SC_T, TORSO)
SC_TOWER = 330
SC_PULLEY = (SC_TOWER - 12, SC_SH[1] + 18)


def single_cable_row_poses():
    d = art.norm(art.sub(SC_PULLEY, SC_SH))
    out = []
    for k, t in ((0, -80), (0.5, -84), (1, -88)):
        sh = art.ang_pt(SC_HIP, t, TORSO)
        a = art.add(sh, d, 80)
        b = chest_pt(SC_HIP, t, 0.04, 12)
        g = lerp(a, b, k)
        if k == 0.5:
            g = art.add(sh, art.norm(art.sub(g, sh)), 60)
        out.append(B(SC_HIP, t, aN=G(g, 1), aF=(100, 40, 30), lit_sides="N", h=-88,
                     lN=G((SC_HIP[0] - 22, FLOOR_Y), -1, end=0), lF=G((SC_HIP[0] + 26, FLOOR_Y), -1, end=0)))
    return out


def single_cable_row_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 240, 130)
        kit.cable_tower(doc, SC_TOWER, SC_PULLEY[1], A.cable_lift(g, SC_PULLEY, 70, 0.3))
    else:
        art.cable(doc, [g, art.add(SC_PULLEY, (-5, 1))])
        kit.handle(doc, g)


# ---- wide-grip seated row ------------------------------------------------------------------------

def wide_row_scene(k):
    def scene(doc, j, layer):
        if layer == "back":
            wide_row_arms(j, k)
            S0.cable_row(doc, j, "back")
        else:
            g = kit.grip(j)
            art.cable(doc, [g, (245, 204)])
            doc.add(f'<circle cx="{g[0]:.1f}" cy="{g[1]:.1f}" r="5.2" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
                    f'<circle cx="{g[0]:.1f}" cy="{g[1]:.1f}" r="2.2" fill="{art.CHROME}"/>')
    return scene


WR_HIP = (138, 202)  # far enough forward on the bench for the soles to reach the angled foot plate
WR_PLATE = ((236, 182), (252, 246))  # cable_row's foot plate (scenes.py): its left face takes the soles
WR_SOLE = -104  # foot along the plate, toes up


def wr_leg(y, gap=5):
    """Leg angles with the ankle `gap` px off the plate face at height y, the sole flat on the plate."""
    (ax, ay), (bx, by) = WR_PLATE
    ankle = (ax + (bx - ax) * (y - ay) / (by - ay) - gap, y)
    u, f = U.ik(WR_HIP, ankle, THIGH, SHIN, -1)
    return (u, f, WR_SOLE)


WR_LEGS = dict(lN=wr_leg(222), lF=wr_leg(229))


def wide_row_poses():
    return [P(t=-72, h=-62, aN=(28, 18), aF=(30, 20), pin=("hip", WR_HIP), **WR_LEGS),
            P(t=-86, h=-80, aN=(84, -8), aF=(86, -6), pin=("hip", WR_HIP), **WR_LEGS),
            P(t=-92, h=-86, aN=(158, 0), aF=(160, 2), pin=("hip", WR_HIP), **WR_LEGS)]


WR_START = art.F.place(wide_row_poses()[0])
WR_G0 = kit.grip(WR_START)  # arms long towards the cable
WR_G1 = chest_pt(WR_HIP, -92, 0.7, 22)  # bar at the lower chest
WR_OUT = 10  # wide grip: each hand this far out from its shoulder (towards / away from the camera)


def wide_row_arms(j, k):
    """Arms as 3D chains projected to the side view: the bar travels from arm's length to the lower chest and
    the elbows flare out and back (wide grip), the upper arms foreshortened, instead of folding flat in the
    picture plane with the elbow far behind the back."""
    sh = j["shoulder"]
    for s, sz, off in (("N", 1, (0, 0)), ("F", -1, (-2, -1))):
        a = (sh[0], sh[1], 0.0)
        p = lerp(art.add(WR_G0, off), art.add(WR_G1, off), k)
        g = (p[0], p[1], sz * WR_OUT)
        e = A._ik3(a, g, UPPER, FORE + HAND / 2, (-0.8, -0.1, sz * 1.0))
        d = art.norm((g[0] - e[0], g[1] - e[1])) if math.dist(g[:2], e[:2]) > 0.5 else (1.0, 0.0)
        fl = math.dist(g, e)
        scale = math.dist(g[:2], e[:2]) / fl if fl else 1
        j["elbow" + s] = (e[0], e[1])
        j["wrist" + s] = art.add(g[:2], d, -HAND / 2 * scale)
        j["hand" + s] = art.add(g[:2], d, HAND / 2 * scale)


# ---- renegade row --------------------------------------------------------------------------------

RG_DB = (270, GROUND - 9)
RG_W = (RG_DB[0], RG_DB[1] - 5)


def renegade_pose(arm_n):
    lo, hi = -40.0, 30.0
    pose = None
    for _ in range(44):
        t = (lo + hi) / 2
        lf = (t + 180, t + 180, 80)
        pose = P(t=t, h=t + 6, lN=lf, lF=(t + 181, t + 181, 80), aN=arm_n, aF=(90, 90, 90), pin=("wristF", RG_W),
                 lit_sides="N")
        y = F_place(pose)["toeN"][1]
        if y < GROUND - 1:
            hi = t
        else:
            lo = t
    return pose


def F_place(p):
    return art.F.place(p)


def renegade_poses():
    base = renegade_pose((90, 90, 90))
    j = F_place(base)
    sh = j["shoulder"]
    out = [base]
    for arm in ((150, 86, 86), (204, 92, 92)):
        out.append(renegade_pose(arm))
    return out


def renegade_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 120)
        art.db_side(doc, (RG_DB[0] - 2, RG_DB[1]), 0, 9, 15)
    else:
        art.db_side(doc, kit.grip(j), 0, 9.5, 15)


# ---- Smith machine inverted row ------------------------------------------------------------------

SM_GRIP = (190, 128)
SM_ANKLE = (300, FLOOR_Y)  # close enough that the chest (not the face) reaches the bar at the top


def smith_scene(doc, j, layer):
    gx, gy = SM_GRIP
    if layer == "back":
        floor(doc, 240, 130)
        # Frame posts, top beam, guide rod with the bar carriage locked on its hook.
        for x in (gx - 46, gx + 40):
            art.tube(doc, (x, GROUND - 2), (x, 16), 10, "butt")
        art.tube(doc, (gx - 52, 18), (gx + 46, 18), 9)
        kit.feet(doc, gx - 76, gx + 70)
        art.tube(doc, (gx - 4, 22), (gx - 4, GROUND - 4), 4, "butt")
        doc.add(f'<rect x="{gx - 11:.1f}" y="{gy - 9:.1f}" width="14" height="18" rx="2" fill="#2A2E34" stroke="#0A0B0D" '
                f'stroke-width="0.8"/>')
        art.plate(doc, (gx, gy), 13, hub=False)
        doc.add(f'<circle cx="{gx:.1f}" cy="{gy:.1f}" r="4.6" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
                f'<circle cx="{gx:.1f}" cy="{gy:.1f}" r="1.8" fill="{art.CHROME}"/>')


def smith_poses():
    """Hang with straight arms, row until the lower chest touches the bar (the body pivots on the heels)."""
    def chest_gap(t):
        hip = art.ang_pt(SM_ANKLE, t, THIGH + SHIN)
        return kit.dist(chest_pt(hip, t, 0.7, 13), SM_GRIP)
    t1 = U.solve_t(SM_ANKLE, SM_GRIP, 81)
    t3 = min((t1 + 0.25 * i for i in range(240)), key=chest_gap)
    return [U.body_line(SM_ANKLE, t, SM_GRIP, 0) for t in (t1, (t1 + t3) / 2 + 2, t3)]


ROW_SCENES = {
    "pendlay-row": S(plate_bar_scene(22), pendlay_poses(), [], held_at("N", 22)),
    "yates-row": S(plate_bar_scene(22), yates_poses(), [], held_at("N", 22)),
    "meadows-row": S(meadows_scene, meadows_poses(), [(MR_ANCHOR[0] - 12, GROUND - 10, MR_ANCHOR[0] + 12, GROUND)],
                     held_at("N", 18)),
    "landmine-t-bar-row": S(tbar_scene, tbar_poses(), [(TB_ANCHOR[0] - 12, GROUND - 10, TB_ANCHOR[0] + 12, GROUND)],
                            lambda j: [(art.add(kit.grip(j), (24, -12)), 18)]),
    "single-arm-cable-row": S(single_cable_row_scene, single_cable_row_poses(), [tower_box(SC_TOWER)],
                              along(grip_n, SC_PULLEY)),
    "wide-grip-cable-row": custom(wide_row_scene, wide_row_poses(), (20, 31, 340), (0, 0.5, 1)),
    "renegade-row": S(renegade_scene, renegade_poses(), [(RG_DB[0] - 20, GROUND - 20, RG_DB[0] + 20, GROUND)],
                      held_at("N", 12)),
    "smith-inverted-row": S(smith_scene, smith_poses(), [(SM_GRIP[0] - 60, 10, SM_GRIP[0] + 52, GROUND)]),
}

# ---- pull-up variations ---------------------------------------------------------------------------

BAR = U.BAR
AB = (204, -6)  # assisted machine handles: high enough for a kneeling hang above the pad travel
AS_COL = 96  # machine column (counterweight stack) behind the lifter
KNEEL_LEGS = dict(lN=(86, 178, 178), lF=(90, 180, 180))


def bar_pull_poses(bar, end=(-20, 18), mid=(-10, 50), t=(-92, -96, -101), legs=U.HANG_LEGS):
    """U.pull_poses for a bar at `bar`."""
    shs = [(bar[0] - 3, bar[1] + 80.5), (bar[0] + mid[0], bar[1] + mid[1]), (bar[0] + end[0], bar[1] + end[1])]
    hs = [t[0] + 8, t[1] + 4, t[2] + 18]
    return [U.hang(s, tt, legs, grip=bar, h=hh) for s, tt, hh in zip(shs, t, hs)]


def assisted_poses():
    return bar_pull_poses(AB, legs=KNEEL_LEGS)


def assisted_scene(doc, j, layer):
    k = j["kneeN"]
    pad_y = k[1] + 9
    if layer == "back":
        floor(doc, 160, 110)
        # Column with the counterweight stack; the stack drops as the knee pad rises.
        lift = max(0.0, (190 - pad_y) * 0.18)
        art.tube(doc, (AS_COL + 40, GROUND - 2), (AS_COL + 40, -40), 11)
        art.shroud(doc, AS_COL - 6, 70, GROUND - 4, 44)
        top = art.stack(doc, AS_COL - 1, 120, GROUND - 4, 34, 10, max(0.0, 16 - lift))
        art.pulley(doc, (top[0], 84), 5.5)
        art.cable(doc, [(top[0] + 5.5, 84), top])
        kit.feet(doc, AS_COL - 20, AS_COL + 150)
        # Top frame out to the handles (end-on) above the lifter.
        art.tube(doc, (AS_COL + 40, AB[1] - 12), (AB[0] + 6, AB[1] - 12), 9)
        art.tube(doc, (AB[0] - 2, AB[1] - 12), (AB[0] - 2, AB[1]), 6)
        doc.add(f'<circle cx="{AB[0]:.1f}" cy="{AB[1]:.1f}" r="4.8" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
                f'<circle cx="{AB[0]:.1f}" cy="{AB[1]:.1f}" r="1.8" fill="{art.CHROME}"/>')
        # Lever from the column pivot to the knee pad, and the step platform.
        piv = (AS_COL + 40, 196)
        art.tube(doc, piv, (k[0] - 6, pad_y + 6), 7)
        art.pulley(doc, piv, 6)
        art.tube(doc, (AS_COL + 40, 236), (AS_COL + 96, 236), 7)
        art.pad(doc, (AS_COL + 56, 236), (AS_COL + 104, 236), 6, stitch=False)
    else:
        art.pad(doc, (k[0] - 46, pad_y + 6), (k[0] + 8, pad_y + 6), 12)


NB = (204, -14)  # negative pull-up bar: high enough to hang with straight legs above the floor
NB_BOX = (118, 70)  # box x, width


def negative_poses():
    t1, t2, t3 = -100, -96, -92
    sh1 = (NB[0] - 20, NB[1] + 20)
    hip1 = art.ang_pt(sh1, t1 + 180, TORSO)
    ank1 = (hip1[0] - 26, hip1[1] + math.sqrt(105 ** 2 - 26 ** 2))
    p1 = B(hip1, t1, aN=G(NB, 1), aF=G((NB[0] - 2, NB[1] + 1), 1), h=t1 + 18,
           lN=G(ank1, -1, end=0), lF=G((ank1[0] - 4, ank1[1]), -1, end=0))
    p2 = U.hang((NB[0] - 10, NB[1] + 50), t2, legs=dict(lN=(88, 104, 40), lF=(92, 108, 44)), grip=NB, h=t2 + 4)
    p3 = U.hang((NB[0] - 3, NB[1] + 80.5), t3, legs=dict(lN=(86, 96, 30), lF=(90, 100, 34)), grip=NB, h=t3 + 8)
    return [p1, p2, p3], ank1[1] + 4


NEG_POSES, NEG_BOX_TOP = negative_poses()


def negative_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 180, 100)
        kit.pullup_bar(doc, NB, top=-90, half=40)
        kit.box(doc, NB_BOX[0], NB_BOX[1], GROUND - NEG_BOX_TOP)
        if j["shoulder"][1] > NB[1] + 40:
            kit.motion(doc, art.add(j["shoulder"], (30, -6)), 90, 20)


NG_BAR = BAR


def neutral_scene(doc, j, layer):
    if layer == "back":
        x, y = NG_BAR
        # Parallel handles, seen lengthwise, hanging from a frame.
        art.tube(doc, (x - 46, -80), (x - 46, y - 16), 8, "butt")
        art.tube(doc, (x - 50, y - 16), (x + 22, y - 16), 8)
        for dx in (-20, 16):
            art.tube(doc, (x + dx, y - 16), (x + dx, y), 5)
        art.tube(doc, (x - 22, y), (x + 18, y), 7)
        doc.add(f'<rect x="{x - 12:.1f}" y="{y - 4:.1f}" width="22" height="8" rx="4" fill="#1B1D20"/>')


# ---- pulldown variations ----------------------------------------------------------------------------

PD_HIP = (150, 212)
PD_LEGS = dict(lN=(-2, 92, 0), lF=(2, 90, 0))
PD_PULLEY = S0.PD_TOP_PULLEY


def pd_pose(t, g, bend=1, **kw):
    return B(PD_HIP, t, aN=G(g, bend), aF=G((g[0] - 2, g[1] - 1), bend), h=t + 4, **PD_LEGS, **kw)


def pulldown_poses(t_end, end_u, end_out, bend=1):
    sh0 = art.ang_pt(PD_HIP, -96, TORSO)
    g0 = (sh0[0] + 10, sh0[1] - 80)
    g2 = chest_pt(PD_HIP, t_end, end_u, end_out)
    t1 = (-96 + t_end) / 2
    sh1 = art.ang_pt(PD_HIP, t1, TORSO)
    g1 = art.add(sh1, art.norm(art.sub(lerp(g0, g2, 0.5), sh1)), 54)
    return [pd_pose(-96, g0, bend), pd_pose(t1, g1, bend), pd_pose(t_end, g2, bend)]


def pulldown_var_scene(kind):
    def scene(doc, j, layer):
        g = kit.grip(j)
        if layer == "back":
            S0.pulldown(doc, j, "back")
        else:
            art.cable(doc, [g, (PD_PULLEY[0] - 6, PD_PULLEY[1])])
            kit.roller_pad(doc, (204, 190), 9.5)
            kit.handle(doc, g, kind)
    return scene


# ---- straight-arm pulldown --------------------------------------------------------------------------

SA_HIP = (186, U.ST_HIP[1] + 3)
SA_T = -70
SA_SH = art.ang_pt(SA_HIP, SA_T, TORSO)
SA_TOWER = 320
SA_PULLEY = (SA_TOWER - 12, 36)


def straight_arm_poses():
    out = []
    for a in (-34, 22, 74):
        g = art.ang_pt(SA_SH, a, UPPER + FORE + HAND / 2 - 2)
        out.append(B(SA_HIP, SA_T, aN=G(g, 1), aF=G((g[0] - 3, g[1] - 1), 1), h=-76,
                     lN=G((SA_HIP[0] + 8, FLOOR_Y), -1, end=0), lF=G((SA_HIP[0] + 2, FLOOR_Y), -1, end=0)))
    return out


def straight_arm_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 240, 130)
        kit.cable_tower(doc, SA_TOWER, SA_PULLEY[1], A.cable_lift(g, SA_PULLEY, 100, 0.3))
    else:
        art.cable(doc, [g, art.add(SA_PULLEY, (-5, 2))])
        kit.handle(doc, g)


PULL_BAR = U.PULL_BAR
PULL_SCENES = {
    "assisted-pull-up": S(assisted_scene, assisted_poses(), [(AS_COL - 10, AB[1] - 20, AB[0] + 10, GROUND)]),
    "negative-pull-up": S(negative_scene, NEG_POSES, [(NB_BOX[0], NB[1] - 14, NB[0] + 10, GROUND)]),
    "neutral-grip-pull-up": S(neutral_scene, U.pull_poses(end=(-14, 24), mid=(-6, 54), t=(-90, -94, -97)),
                              [(NG_BAR[0] - 50, NG_BAR[1] - 20, NG_BAR[0] + 24, NG_BAR[1] + 8)], floor=False),
    "close-grip-pulldown": (pulldown_var_scene("v"), pulldown_poses(-110, 0.86, 22), (25, 14, 340)),
    "reverse-grip-pulldown": (pulldown_var_scene("d"), pulldown_poses(-106, 0.9, 16), (25, 14, 340)),
    "straight-arm-pulldown": S(straight_arm_scene, straight_arm_poses(), [tower_box(SA_TOWER)], along(grip_n, SA_PULLEY)),
}

# ---- curls ----------------------------------------------------------------------------------------

# Concentration curl: seated on a flat bench, leaning in, elbow braced on the inner thigh by the knee.
CC_SEAT = dict(x0=86, x1=186, top=226)
CC_HIP = (132, CC_SEAT["top"] - 13)
CC_T = -52
CC_LEGS = dict(lN=G((CC_HIP[0] + 70, FLOOR_Y), -1, end=0), lF=G((CC_HIP[0] + 62, FLOOR_Y), -1, end=0))


def concentration_poses():
    sh = art.ang_pt(CC_HIP, CC_T, TORSO)
    j0 = U.place(B(CC_HIP, CC_T, **CC_LEGS))
    kf = j0["kneeF"]
    out = []
    for fore in (94, 26, -40):
        out.append(B(CC_HIP, CC_T, aN=(84, fore), aF=G((kf[0] + 4, kf[1] - 6), 1, end=CC_T + 40, wrist=True),
                     h=CC_T + 30, **CC_LEGS))
    del sh
    return out


def concentration_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 160, 100)
        kit.flat_bench(doc, CC_SEAT["x0"], CC_SEAT["x1"], CC_SEAT["top"])
    else:
        art.db_end(doc, kit.grip(j), 10)


# Spider curl: chest on an incline bench, upper arms hanging straight in front of the pad.
SP_T, SP_HIP = U.CS_T, U.CS_HIP


def spider_poses():
    out = []
    for fore in (88, 16, -30):
        out.append(B(SP_HIP, SP_T, aN=(84, fore), aF=(86, fore + 2), h=-20,
                     lN=G((SP_HIP[0] - 44, FLOOR_Y), -1, end=-10), lF=G((SP_HIP[0] - 50, FLOOR_Y), -1, end=-10)))
    return out


def spider_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 110)
        a, b = U.cs_pad_line(-0.1, 0.62)
        mid = lerp(a, b, 0.45)
        art.tube(doc, mid, (mid[0] + 6, GROUND - 2), 8, "butt")
        art.tube(doc, lerp(a, b, 0.1), (a[0] - 18, GROUND - 2), 6)
        kit.feet(doc, a[0] - 34, mid[0] + 40)
        art.pad(doc, a, b, 12)
        art.db_end(doc, kit.grip(j, "F"), 9)
    else:
        art.db_end(doc, kit.grip(j), 10)


# EZ-bar preacher curl: seated, upper arms down the sloped pad.
PC_HIP = (168, 196)
PC_T = -78
PC_SH = art.ang_pt(PC_HIP, PC_T, TORSO)
PC_UA = 46  # upper-arm angle on the pad


def preacher_poses():
    out = []
    for fore in (36, -30, -88):  # top: forearm upright, the bar in front of the chin (not into the face)
        out.append(B(PC_HIP, PC_T, aN=(PC_UA, fore), aF=(PC_UA + 2, fore + 2), h=-70,
                     lN=G((PC_HIP[0] + 60, FLOOR_Y), -1, end=0), lF=G((PC_HIP[0] + 54, FLOOR_Y), -1, end=0)))
    return out


def redraw_near_arm(doc, j, levels):
    """Draw the near arm again on top of equipment placed between it and the trunk (e.g. a preacher pad)."""
    near = art.body_segments(j)[2]
    for name in ("upper", "fore", "hand"):
        sg = near[name]
        d = art.draw_segment(doc, sg, art.SKIN_NEAR)
        art.draw_muscles(doc, sg, name, levels, d, False, "side")


CURL_LEVELS = {"biceps": art.PRIMARY, "brachialis": art.SECONDARY}


def preacher_scene(doc, j, layer):
    d = (math.cos(math.radians(PC_UA)), math.sin(math.radians(PC_UA)))
    under = (-d[1], d[0])  # the arm's underside
    p1 = art.add(art.add(PC_SH, d, 10), under, 8.5)
    p2 = art.add(art.add(PC_SH, d, 60), under, 8.5)
    p3 = art.add(p2, (-3, 16))
    p4 = (p1[0] + 3, min(p3[1] + 6, PC_HIP[1] - 12))
    if layer == "back":
        floor(doc, 190, 110)
        # Pad column from the base up under the wedge, seat on its own post.
        art.tube(doc, (p3[0] - 6, GROUND - 2), lerp(p3, p4, 0.3), 8)
        kit.feet(doc, PC_HIP[0] - 40, p3[0] + 30)
        art.tube(doc, (PC_HIP[0], PC_HIP[1] + 16), (PC_HIP[0], GROUND - 2), 8, "butt")
        art.pad(doc, (PC_HIP[0] - 30, PC_HIP[1] + 28), (PC_HIP[0] + 26, PC_HIP[1] + 28), 12)
    else:
        g = doc.box_grad([(0, art.PAD[0]), (0.25, art.PAD[1]), (1, art.PAD[2])])
        pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in (p1, p2, p3, p4))
        doc.add(f'<polygon points="{pts}" fill="{g}" stroke="#0A0B0D" stroke-width="0.8" stroke-linejoin="round"/>')
        a, b = art.add(p1, under, 2.6), art.add(p2, under, 2.6)
        doc.add(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="#6B737D" stroke-opacity="0.55" '
                f'stroke-width="0.6" stroke-dasharray="2 1.6"/>')
        redraw_near_arm(doc, j, CURL_LEVELS)
        kit.barbell(doc, kit.grip(j), 16)


# Bayesian curl: facing away from a low pulley, the working arm stays behind the body.
BY_HIP = (206, U.ST_HIP[1] + 2)
BY_TOWER = 96
BY_PULLEY = (BY_TOWER + 12, GROUND - 24)


def bayesian_poses():
    out = []
    # Top: elbow flexed ~145 degrees, the hand by the front of the shoulder (further would fold the forearm
    # through the upper arm).
    for fore in (124, 24, -22):
        out.append(B(BY_HIP, -88, aN=(122, fore), aF=(92, 88), h=-90, lit_sides="N",
                     lN=G((BY_HIP[0] + 22, FLOOR_Y), -1, end=0), lF=G((BY_HIP[0] - 24, FLOOR_Y), -1, end=-6)))
    return out


def bayesian_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 170, 120)
        A.tower(doc, BY_TOWER, BY_PULLEY[1], A.cable_lift(g, BY_PULLEY, 120, 0.3), face="right")
    else:
        art.cable(doc, [art.add(BY_PULLEY, (5, 0)), g])
        kit.handle(doc, g)


# Drag curl: the bar slides up the front of the body, elbows travel back.
DC_HIP = U.ST_HIP


def drag_poses():
    a = (art.ang_pt(DC_HIP, -90, TORSO)[0] + 6, art.ang_pt(DC_HIP, -90, TORSO)[1] + 80)
    gs = [a, chest_pt(DC_HIP, -90, 0.42, 20), chest_pt(DC_HIP, -90, 0.8, 19)]
    return [B(DC_HIP, -90, aN=G(g, 1), aF=G((g[0] - 3, g[1] - 1), 1), h=-92,
              lN=G((DC_HIP[0] + 2, FLOOR_Y), -1, end=0), lF=G((DC_HIP[0] - 2, FLOOR_Y), -1, end=0)) for g in gs]


def zottman_poses():
    p = A.curl_poses()
    mid = P(aN=(90, -10), aF=(94, -6), lF=(92, 88, 0), pin=("ankleN", (200, GROUND - 4)))
    return [p[0], p[1], dict(mid, curl=1 / A.CURL_CH)]


def zottman_scene(doc, j, layer):
    if layer == "back":
        j["_low"] = j["_curl"] > 0
        j["_curl"] = 0
        floor(doc, 200, 40)
        art.db_end(doc, kit.grip(j, "F"), 10)
    else:
        g = kit.grip(j)
        art.db_end(doc, g, 10.5)
        if g[1] < j["elbowN"][1] - 20:
            kit.arc(doc, g, 17, -150, 60)  # palms turn down at the top
        elif j.get("_low"):
            kit.motion(doc, (g[0] + 18, g[1] - 10), 110, 18)


def band_curl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 40)
        g = kit.grip(j, "F")
        kit.band(doc, (j["toeF"][0] - 6, GROUND - 2), g)
    else:
        g = kit.grip(j)
        kit.band(doc, (j["toeN"][0] - 6, GROUND - 2), g)
        kit.handle(doc, g)


def rope_curl_scene(doc, j, layer):
    g = kit.grip(j)
    p = (288, GROUND - 22)
    if layer == "back":
        floor(doc, 220, 110)
        kit.cable_tower(doc, 300, p[1], A.cable_lift(g, p, 128, 0.35))
        art.tube(doc, (300 - 4, GROUND - 2), (240, GROUND - 2), 6)
    else:
        art.cable(doc, [p, (g[0], g[1] + 8)])
        kit.handle(doc, g, "rope")


# Cross-body hammer curl (front view): the near arm curls toward the opposite shoulder.
XB_X = 200


def cross_body_poses():
    base = A.front_stand(XB_X, 4, t=-90, h=-90)
    j = A.fplace(base)
    shn, shf = j["shoulderN"], j["shoulderF"]
    hang_n, hang_f = (shn[0] + 4, shn[1] + 80), (shf[0] - 15, shf[1] + 78)
    start = A.front_arms(base, hang_n, hang_f, 1, -1)
    # The upper arm stays down at the side; the forearm is replaced per frame (cross_body_fore).
    return [start] + [dict(start, aN=(95, 90)) for _ in range(2)]


XB_FLEX = (4, 80, 136)  # elbow flexion at the start / middle / top
XB_PLANE = (12, 40)  # the curl plane, turned from straight ahead towards the opposite shoulder (start, top)


def cross_body_fore(j, flex):
    """Near forearm as a 3D chain projected to the front view: it curls forwards (towards the camera) and
    across, so the hand travels diagonally in front of the body to the opposite chest, foreshortened, instead
    of sweeping flat across the waist over the far arm."""
    e = j["elbowN"]
    sx = 1 if e[0] >= j["shoulder"][0] else -1
    # The plane turns in as the hand rises: across the belly low down, to the opposite chest at the top.
    f = math.radians(flex)
    a = math.radians(XB_PLANE[0] + (XB_PLANE[1] - XB_PLANE[0]) * (flex / XB_FLEX[2]) ** 2)
    d3 = (-sx * math.sin(f) * math.sin(a), math.cos(f), math.sin(f) * math.cos(a))
    flat = math.hypot(d3[0], d3[1])
    d = (d3[0] / flat, d3[1] / flat) if flat > 0.02 else (-sx * 1.0, 0.0)
    g = art.add(e, d, (FORE + HAND / 2) * flat)
    j["wristN"] = art.add(g, d, -HAND / 2 * flat)
    j["handN"] = art.add(g, d, HAND / 2 * flat)


def cross_body_scene(flex):
    def scene(doc, j, layer):
        if layer == "back":
            cross_body_fore(j, flex)
            floor(doc, XB_X, 50)
        else:
            for s in "FN":
                g = kit.grip(j, s)
                art.db_end(doc, g, 9.5)
    return scene


ARM_FRONT = (40, 22, 330)
CURL_SCENES = {
    "concentration-curl": S(concentration_scene, concentration_poses(), [(CC_SEAT["x0"], CC_SEAT["top"], CC_SEAT["x1"], GROUND)],
                            held_at("N", 11)),
    "spider-curl": S(spider_scene, spider_poses(), [(95, 130, 215, GROUND)], held_at("N", 11)),
    "ez-preacher-curl": S(preacher_scene, preacher_poses(), [(PC_HIP[0] - 40, 120, PC_SH[0] + 70, GROUND)], held_at("N", 17)),
    "bayesian-curl": S(bayesian_scene, bayesian_poses(), [tower_box(BY_TOWER, "R")], along(grip_n, BY_PULLEY)),
    "drag-curl": S(plate_bar_scene(22), drag_poses(), [], held_at("N", 22)),
    "zottman-curl": (zottman_scene, zottman_poses(), ARM_FRONT),
    "band-curl": (band_curl_scene, A.curl_poses(), ARM_FRONT),
    "rope-hammer-curl": (rope_curl_scene, A.curl_poses(186), ARM_FRONT),
    "cross-body-hammer-curl": custom(cross_body_scene, cross_body_poses(), ARM_FRONT, XB_FLEX),
    "reverse-ez-curl": (A.curl_scene("bar", plate=16), A.curl_poses(hand0=86, hand1=-64), ARM_FRONT),
}

# ---- triceps -----------------------------------------------------------------------------------------

PUSH_PULLEY = (288, 40)


def pushdown_poses(end_fore=84, far=None, **kw):
    fa0, fa1 = far or ((98, -10), (96, 86))
    return [P(t=-80, h=-84, aN=(96, -12), aF=fa0, lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4)), **kw),
            P(t=-80, h=-84, aN=(94, end_fore), aF=fa1, lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4)), **kw)]


def cable_pushdown_scene(kind):
    def scene(doc, j, layer):
        g = kit.grip(j)
        if layer == "back":
            floor(doc, 220, 110)
            kit.cable_tower(doc, 300, PUSH_PULLEY[1], A.cable_lift(g, PUSH_PULLEY, 85, 0.35))
        else:
            if kind == "rope":
                art.cable(doc, [PUSH_PULLEY, (g[0], g[1] - 8)])
                kit.handle(doc, g, "rope")
            else:
                art.cable(doc, [PUSH_PULLEY, g])
                kit.handle(doc, g)
    return scene


BAND_ANCHOR = (300, 40)


def band_pushdown_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 230, 110)
        kit.post(doc, BAND_ANCHOR[0] + 8, BAND_ANCHOR[1] - 10)
        art.tube(doc, (BAND_ANCHOR[0] - 2, BAND_ANCHOR[1] - 6), (BAND_ANCHOR[0] + 30, BAND_ANCHOR[1] - 6), 7)
        kit.band(doc, BAND_ANCHOR, kit.grip(j, "F"))
    else:
        g = kit.grip(j)
        kit.band(doc, (BAND_ANCHOR[0] - 2, BAND_ANCHOR[1] + 1), g)
        kit.handle(doc, g)


def db_kickback_poses():
    out = []
    for fore in (90, 136, 180):
        out.append(B(U.OA_HIP, U.OA_T, aN=(182, fore), aF=G((U.OA_SH[0] + 6, U.BENCH_TOP - 5), 1, end=0, wrist=True),
                     lN=G((U.OA_HIP[0] + 8, FLOOR_Y), -1, end=0), lF=(deg(art.sub(U.OA_KNEE, U.OA_HIP)), 180, 180),
                     h=U.OA_T + 10, lit_sides="N"))
    return out


def db_kickback_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 120)
        kit.flat_bench(doc, 62, 250, U.BENCH_TOP)
    else:
        A.db_hold(doc, j, "N", 10, True)
        # The fist closes over the handle (drawn on top, so the dumbbell reads as held, not stuck to the hip).
        hand = art.body_segments(j)[2]["hand"]
        art.draw_segment(doc, hand, art.SKIN_NEAR)


CK_HIP = (176, 162)
CK_T = -30
CK_TOWER = 330
CK_PULLEY = (CK_TOWER - 12, GROUND - 22)


def cable_kickback_poses():
    j0 = U.place(B(CK_HIP, CK_T, lN=G((CK_HIP[0] + 30, FLOOR_Y), -1, end=0), lF=G((CK_HIP[0] + 22, FLOOR_Y), -1, end=0)))
    kf = j0["kneeF"]
    out = []
    for fore in (84, 132, 176):
        out.append(B(CK_HIP, CK_T, aN=(174, fore), aF=G((kf[0] + 2, kf[1] - 8), 1, end=60, wrist=True), h=CK_T + 14,
                     lN=G((CK_HIP[0] + 30, FLOOR_Y), -1, end=0), lF=G((CK_HIP[0] + 22, FLOOR_Y), -1, end=0),
                     lit_sides="N"))
    return out


def cable_kickback_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 240, 130)
        kit.cable_tower(doc, CK_TOWER, CK_PULLEY[1], A.cable_lift(g, CK_PULLEY, 150, 0.3))
    else:
        art.cable(doc, [art.add(CK_PULLEY, (-5, 0)), g])
        kit.handle(doc, g)


def jm_poses():
    top = (U.BP_SH[0] + 2, U.BP_SH[1] - 81)
    bottom = (U.BP_SH[0] - 6, U.BP_SH[1] - 30)
    out = []
    for k in U.PRESS_KS:
        g = lerp(top, bottom, k)
        out.append(U.lying_bench(U.BP_HIP, 180, g, (g[0] - 3, g[1] - 1), 1, curl=-2))
    return out


TP_TOP = (U.BP_SH[0] + 4, U.BP_SH[1] - 80)
TP_BOTTOM = (U.BP_SH[0] + 24, U.BP_SH[1] - 22)
TP_IN = U.SW - 4  # at the bottom the bells meet over the sternum: each hand this far in from its shoulder


def tate_poses():
    out = []
    for k in (0, 0.6, 1):
        g = lerp(TP_TOP, TP_BOTTOM, k)
        out.append(U.lying_bench(U.BP_HIP, 180, g, (g[0] - 4, g[1] - 2), 1, curl=-2))
    return out


def tate_arms(j):
    """Elbows flared out to the sides: each arm is solved as a 3D chain (elbow pointing out, towards / away from
    the camera) and projected, so the forearms fold in towards the chest foreshortened instead of folding
    towards the feet in the picture plane (which reads as the elbow bending backwards)."""
    g2 = kit.grip(j)
    k = max(0.0, min(1.0, (g2[1] - TP_TOP[1]) / (TP_BOTTOM[1] - TP_TOP[1])))
    sh = j["shoulder"]
    for s, sz, off in (("N", 1, (0, 0)), ("F", -1, (-4, -2))):
        top, bottom = art.add(TP_TOP, off), art.add(TP_BOTTOM, off)
        a = (sh[0], sh[1], 0.0)
        g = (top[0] + (bottom[0] - top[0]) * k, top[1] + (bottom[1] - top[1]) * k, -sz * TP_IN * k)
        e = A._ik3(a, g, UPPER, FORE + HAND / 2, (0.25, -0.2, sz * 1.0))
        d = art.norm((g[0] - e[0], g[1] - e[1])) if math.dist(g[:2], e[:2]) > 0.5 else (1.0, 0.0)
        fl = math.dist(g, e)
        scale = math.dist(g[:2], e[:2]) / fl if fl else 1
        j["elbow" + s] = (e[0], e[1])
        j["wrist" + s] = art.add(g[:2], d, -HAND / 2 * scale)
        j["hand" + s] = art.add(g[:2], d, HAND / 2 * scale)


def tate_scene(doc, j, layer):
    if layer == "back":
        tate_arms(j)
        floor(doc, 200, 120)
        kit.flat_bench(doc, 104, 254, U.BENCH_TOP)
        art.db_end(doc, kit.grip(j, "F"), 9)
    else:
        art.db_end(doc, kit.grip(j), 10)


EZ_BACK = 92
EZ_PIVOT, EZ_HIP, EZ_SH = U.adj_bench(U.UP, EZ_BACK)


def ez_overhead_poses():
    out = []
    for up, fore in ((-94, -92), (-98, -165), (-102, -226)):
        out.append(B(EZ_HIP, U.UP, aN=(up, fore), aF=(up - 2, fore + 2), h=-92,
                     lN=G((EZ_HIP[0] + 66, FLOOR_Y), -1, end=0), lF=G((EZ_HIP[0] + 58, FLOOR_Y), -1, end=0)))
    return out


def ez_overhead_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 120)
        kit.incline_bench(doc, U.SEAT_X0, U.SEAT_X1, U.SEAT_TOP, EZ_BACK, U.UP)
    else:
        kit.barbell(doc, kit.grip(j), 16)


TRI_SCENES = {
    "rope-pushdown": (cable_pushdown_scene("rope"), pushdown_poses(88), ARM_FRONT),
    "single-arm-pushdown": (cable_pushdown_scene("d"), pushdown_poses(far=((92, 90), (92, 90)), lit_sides="N"),
                            ARM_FRONT),
    "band-pushdown": (band_pushdown_scene, pushdown_poses(), ARM_FRONT),
    "db-kickback": S(db_kickback_scene, db_kickback_poses(), [(60, U.BENCH_TOP, 252, GROUND)], held_at("N", 12)),
    "cable-kickback": S(cable_kickback_scene, cable_kickback_poses(), [tower_box(CK_TOWER)], along(grip_n, CK_PULLEY)),
    "jm-press": S(U.bench_press_scene, jm_poses(), [U.BENCH, U.BP_RACK], held_at("N", 24)),
    "tate-press": S(tate_scene, tate_poses(), [U.BENCH], held_at("N", 11)),
    "ez-overhead-triceps": S(ez_overhead_scene, ez_overhead_poses(), [U.UP_BENCH], held_at("N", 17)),
}

# ---- grip and shrugs ----------------------------------------------------------------------------------

# Wrist curl: kneeling at a flat bench, forearms along the pad, palms up, hands past its end.
WC_HIP = (120, GROUND - 8 - THIGH)
WC_T = -20
WC_SH = art.ang_pt(WC_HIP, WC_T, TORSO)
WC_BENCH_X1 = WC_SH[0] + FORE - 1


def wrist_curl_poses():
    return [P(t=WC_T, h=-6, lN=(90, 180, 180), lF=(92, 180, 180), aN=(90, 0, hand), aF=(92, 1, hand),
              pin=("hip", WC_HIP), inset="tr") for hand in (64, 4, -52)]


def wrist_curl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 170, 110)
        kit.mat(doc, 70, 150)
        kit.flat_bench(doc, WC_BENCH_X1 - 84, WC_BENCH_X1, 226)
        art.db_end(doc, lerp(j["wristF"], j["handF"], 0.8), 8)
        art.db_end(doc, lerp(j["wristN"], j["handN"], 0.8), 8.5)
    else:
        kit.arc(doc, j["wristN"], 20, -60, 70)


def dead_hang_poses():
    # Knees softly bent, feet crossed behind: they hang well clear of the floor.
    legs = dict(lN=(82, 138, 116), lF=(88, 144, 122))
    s0 = (NB[0] - 2, NB[1] + 80.5)
    s1 = circle_x(NB, 80.5, (NB[0] - 10, NB[1] + 72), 5, 1)
    return [U.hang(s0, -90, legs=legs, grip=NB, h=-74),
            U.hang(s1, -93, legs=legs, grip=NB, h=-86, curl=-3),
            U.hang(s1, -93, legs=dict(lN=(80, 136, 114), lF=(90, 146, 124)), grip=NB, h=-88, curl=-3)]


def dead_hang_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 50)
        kit.pullup_bar(doc, NB, top=-90, half=40)


SHRUG_X = A.SHRUG_X


def trap_shrug_scene(doc, j, layer):
    gn, gf = kit.grip(j), kit.grip(j, "F")
    if layer == "back":
        A.shrug(j, A.channel(j))
        A.floor_back(doc, SHRUG_X, 110)
        gn, gf = kit.grip(j), kit.grip(j, "F")
        y = (gn[1] + gf[1]) / 2 + 2
        xl, xr = gf[0] - 16, gn[0] + 16
        # Far half of the hex frame, handles (end-on) under the fists, sleeves + plates either side.
        art.tube(doc, (xl, y), (gf[0] - 4, y - 10), 4.5)
        art.tube(doc, (gf[0] - 4, y - 10), (gn[0] + 4, y - 10), 4.5)
        art.tube(doc, (gn[0] + 4, y - 10), (xr, y), 4.5)
        for g in (gn, gf):
            doc.add(f'<circle cx="{g[0]:.1f}" cy="{g[1]:.1f}" r="5" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>')
        for x0, sgn in ((xl, -1), (xr, 1)):
            x1 = x0 + sgn * 44
            art.tube(doc, (x0, y), (x1, y), 5)
            px = x0 + sgn * 22
            grad = doc.box_grad([(0, "#3A3F46"), (0.5, "#1B1E22"), (1, "#0E1012")], vertical=False)
            doc.add(f'<rect x="{px - 6:.1f}" y="{y - 26:.1f}" width="12" height="52" rx="3" fill="{grad}" stroke="#08090A" '
                    f'stroke-width="0.9"/>')
            doc.add(f'<rect x="{px + sgn * 9 - 2.5:.1f}" y="{y - 6:.1f}" width="5" height="12" rx="1.5" fill="{art.CHROME}"/>')
        j["_hex"] = (xl, xr, y)
    else:
        xl, xr, y = j["_hex"]
        art.tube(doc, (xl, y), (gf[0] - 4, y + 10), 4.5)
        art.tube(doc, (gf[0] - 4, y + 10), (gn[0] + 4, y + 10), 4.5)
        art.tube(doc, (gn[0] + 4, y + 10), (xr, y), 4.5)


# Cable shrug (side view): straight bar on a low pulley in front.
CS_X = 190
CS_TOWER = 300
CS_PULLEY = (CS_TOWER - 12, GROUND - 22)


def side_shrug(j, v):
    """Side view: shoulder girdle up (and a touch back) by v; the head stays, the neck shortens."""
    up, back = 11 * v, 2.5 * v
    for side in "NF":
        for k in ("elbow", "wrist", "hand"):
            x, y = j[k + side]
            j[k + side] = (x - back, y - up)
    x, y = j["shoulder"]
    j["shoulder"] = (x - back, y - up * 0.7)


def cable_shrug_poses():
    return [P(aN=(86, 88), aF=(88, 90), lF=(92, 88, 0), h=-90, pin=("ankleN", (CS_X, GROUND - 4)), curl=v / A.CURL_CH)
            for v in (0, 0.5, 1)]


def cable_shrug_scene(doc, j, layer):
    if layer == "back":
        side_shrug(j, A.channel(j))
        g = kit.grip(j)
        floor(doc, 240, 110)
        kit.cable_tower(doc, CS_TOWER, CS_PULLEY[1], max(0.0, (200 - g[1]) * 0.6))
        art.tube(doc, (CS_TOWER - 4, GROUND - 2), (CS_X + 40, GROUND - 2), 6)
    else:
        g = kit.grip(j)
        art.cable(doc, [art.add(CS_PULLEY, (-5, 0)), g])
        kit.handle(doc, g)


GRIP_SCENES = {
    "wrist-curl": S(wrist_curl_scene, wrist_curl_poses(), [(WC_BENCH_X1 - 84, 226, WC_BENCH_X1, GROUND)], held_at("N", 11)),
    "dead-hang": S(dead_hang_scene, dead_hang_poses(), [(NB[0] - 46, NB[1] - 14, NB[0] + 10, NB[1] + 8),
                                                         (NB[0] - 30, GROUND - 4, NB[0] + 30, GROUND + 4)]),
    "trap-bar-shrug": (trap_shrug_scene, [A.shrug_pose(v, aN=(82, 88), aF=(98, 92)) for v in (0, 0.5, 1)], ARM_FRONT),
    "cable-shrug": (cable_shrug_scene, cable_shrug_poses(), ARM_FRONT),
}

SCENES = {}
SCENES.update(GRIP_SCENES)
SCENES.update(TRI_SCENES)
SCENES.update(ROW_SCENES)
SCENES.update(PULL_SCENES)
SCENES.update(CURL_SCENES)
