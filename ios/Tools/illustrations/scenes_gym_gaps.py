"""Scenes for the machine gaps (#796): seated and standing leg curl, lateral raise, incline chest press, seated
dip and high row machines.

Side views use the pose solver of scenes_lower.py (body(): hip pinned, ankles / hands solved onto targets), the
lateral raise the back-view seated figure of scenes_var_push.py. Levers swing about a fixed pivot (bisect_pivot)
so they keep their length between frames, as in scenes_gym_machines.py.
"""
import math

import art
import kit
from art import GROUND
from scenes_gym_machines import bisect_pivot, column, hand_dot, hub, mid, seat, tpt
from scenes_lower import ANK, SH, TH, body, floor, grip, ins, lever, norm2, pt, shoulder, slab, tframe
from scenes_power import fit
from scenes_upper import B, PD_LEGS, held_at
from scenes_var_push import SL_HIP, SL_SEAT, seat_legs_back

SCENES = {}


def arc_pt(piv, a, b, k):
    """Point k (0..1) along the arc around `piv` from a to b."""
    a0 = math.degrees(math.atan2(a[1] - piv[1], a[0] - piv[0]))
    a1 = math.degrees(math.atan2(b[1] - piv[1], b[0] - piv[0]))
    return art.ang_pt(piv, a0 + (a1 - a0) * k, math.dist(a, piv))


# ==== seated leg curl ================================================================================
# Legs out in front over the roller, thigh pad pinning the knees; the pad is pushed down and under the seat.

SC_HIP = (166, 194)
SC_T = -106
SC_SEAT = SC_HIP[1] + 13


def seated_curl_scene(doc, j, layer):
    knee, ank = j["kneeN"], j["ankleN"]
    sd = norm2(knee, ank)
    back = (-sd[1], sd[0])  # back of the shin
    roller = art.add(art.add(ank, sd, -6), back, 10)
    if layer == "back":
        floor(doc, 180, 130)
        hip = SC_HIP
        td, n = tframe(SC_T)
        shin = math.degrees(math.atan2(sd[1], sd[0]))
        st = column(doc, 30, top=58, w=30, lift=max(0, (shin - 10) * 0.25))
        kit.feet(doc, 22, 300)
        art.cable(doc, [(st[0] + 5.5, 65), (110, 65), (110, 238), (knee[0], 238), (knee[0], knee[1] + 8)])
        art.pulley(doc, (110, 238), 5)
        # Seat post, rail, backrest, knee-pivot upright.
        art.tube(doc, (hip[0] - 4, SC_SEAT + 12), (hip[0] - 4, GROUND - 2), 9, "butt")
        art.tube(doc, (96, GROUND - 2), (knee[0] + 30, GROUND - 2), 7)
        art.tube(doc, (knee[0] + 8, knee[1] - 30), (knee[0] + 22, GROUND - 2), 8, "butt")
        slab(doc, (hip[0] - 26, SC_SEAT), (knee[0] - 16, SC_SEAT), 12, hip)
        slab(doc, art.add(art.add(hip, td, 4), n, -15), art.add(art.add(hip, td, 82), n, -15), 12, hip)
        art.tube(doc, art.add(art.add(hip, td, 30), n, -27), (hip[0] - 4, SC_SEAT + 14), 6)
        lever(doc, knee, roller)
    else:
        # Thigh pad on top of the knees, on its arm from the upright.
        kp = (knee[0] - 12, knee[1] - 13)
        art.tube(doc, (knee[0] + 10, knee[1] - 30), (kp[0] + 8, kp[1] - 4), 6)
        art.pad(doc, (kp[0] - 18, kp[1]), (kp[0] + 14, kp[1]), 9)
        kit.roller_pad(doc, roller, 9)
        kit.handle(doc, grip(j))


def seated_curl_pose(shin):
    knee = pt(SC_HIP, 0, TH)
    ank = pt(knee, shin, SH)
    g = (SC_HIP[0] + 18, SC_HIP[1] + 8)  # side handles by the seat
    return body(SC_HIP, SC_T, h=-92, ankN=ank, ankF=art.add(ank, (-3, 0)), fN=shin - 90, fF=shin - 90,
                gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1)


SCL = ins([seated_curl_pose(10), seated_curl_pose(62), seated_curl_pose(112)], "tr")
SCENES["seated-leg-curl"] = (seated_curl_scene, SCL, fit(SCL, (16, 50, 316, GROUND)))


# ==== standing leg curl ==============================================================================
# One leg on the platform, front of the working thigh on the knee pad, heel curled to the glute.

STC_HIP = (196, ANK - TH - SH - 10)  # standing on a 10 px platform
STC_T = -78
STC_COL = 270


def standing_curl_scene(doc, j, layer):
    knee, ank = j["kneeN"], j["ankleN"]
    sd = norm2(knee, ank)
    back = (-sd[1], sd[0])
    roller = art.add(art.add(ank, sd, -6), back, 10)
    piv = (knee[0] + 4, knee[1])
    if layer == "back":
        floor(doc, 210, 120)
        shin = math.degrees(math.atan2(sd[1], sd[0]))
        st = column(doc, STC_COL, top=40, w=30, lift=max(0, (shin - 92) * 0.25))
        art.cable(doc, [(st[0] - 5.5, 47), (st[0] - 5.5, piv[1]), piv])
        # Platform, frame to the column, chest pad + handles.
        art.pad(doc, (STC_HIP[0] - 40, GROUND - 2), (STC_HIP[0] + 40, GROUND - 2), 10, False)
        kit.feet(doc, STC_HIP[0] - 50, STC_COL + 60)
        art.tube(doc, (STC_HIP[0] + 30, GROUND - 6), (STC_COL - 4, GROUND - 6), 7)
        art.tube(doc, (piv[0] + 14, piv[1] + 6), (STC_COL - 4, piv[1] + 6), 7)
        sh = j["shoulder"]
        cp = (sh[0] + 22, sh[1] + 16)
        art.tube(doc, (cp[0] + 10, cp[1]), (STC_COL - 4, cp[1]), 7)
        art.pad(doc, (cp[0], cp[1] - 26), (cp[0], cp[1] + 22), 11)
        lever(doc, piv, roller)
    else:
        kp = (knee[0] + 12, knee[1] - 12)
        art.pad(doc, (kp[0], kp[1] - 14), (kp[0], kp[1] + 12), 9)
        kit.roller_pad(doc, roller, 9)
        kit.handle(doc, grip(j))


def standing_curl_pose(shin):
    sh = shoulder(STC_HIP, STC_T)
    g = (sh[0] + 34, sh[1] + 36)
    return body(STC_HIP, STC_T, h=-70, lN=(96, shin, shin - 90), ankF=(STC_HIP[0] - 2, ANK - 10),
                gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1, lit_sides="N")


STL = ins([standing_curl_pose(92), standing_curl_pose(150), standing_curl_pose(204)], "tl")
SCENES["standing-leg-curl"] = (standing_curl_scene, STL, fit(STL, (STC_HIP[0] - 50, 30, STC_COL + 60, GROUND)))


# ==== machine lateral raise (back view) ==============================================================
# Seated, pads on the outside of the arms just above the elbows; levers pivot at the shoulders.

def lateral_machine_poses():
    arms = (((84, 88), (96, 92)), ((40, 46), (140, 134)), ((-2, 8), (182, 172)))
    return [B(SL_HIP, -90, front="back", aN=a, aF=b, **PD_LEGS) for a, b in arms]


def lateral_machine_scene(doc, j, layer):
    if layer == "back":
        seat_legs_back(j)
        floor(doc, 200, 90)
        # Frame in front of the seat (hidden by the body), cross beam at the pivots, stack on the right.
        y = j["shoulderN"][1] - 4
        art.tube(doc, (SL_HIP[0], GROUND - 2), (SL_HIP[0], y - 20), 10, "butt")
        st = column(doc, 300, top=40, w=28, lift=max(0, (j["shoulderN"][1] - j["elbowN"][1]) * 0.4 + 8))
        art.tube(doc, (SL_HIP[0], y - 20), (300, y - 20), 7)
        art.cable(doc, [(st[0] - 5.5, 47), (st[0] - 5.5, y - 20)])
        art.tube(doc, (SL_HIP[0], SL_SEAT + 12), (SL_HIP[0], GROUND - 2), 10, "butt")
        kit.feet(doc, SL_HIP[0] - 40, 340)
        g = doc.box_grad([(0, art.PAD[0]), (0.3, art.PAD[1]), (1, art.PAD[2])])
        doc.add(f'<rect x="{SL_HIP[0] - 26}" y="{SL_SEAT}" width="52" height="13" rx="5" fill="{g}" '
                f'stroke="#0A0B0D" stroke-width="0.9"/>')
    else:
        for s in "NF":
            shp, el = j["shoulder" + s], j["elbow" + s]
            d = norm2(shp, el)
            out = 1 if el[0] >= j["shoulder"][0] else -1
            pc = art.add(art.add(shp, d, 34), (d[1] * out, -d[0] * out), 0)
            art.tube(doc, shp, art.add(shp, d, 40), 5)
            hub(doc, shp, 5)
            # Pad on the outside of the upper arm, just above the elbow.
            n = (-d[1], d[0])
            if n[1] > 0:
                n = (-n[0], -n[1])
            c = art.add(pc, n, 0)
            art.pad(doc, art.add(c, d, -10), art.add(c, d, 10), 8)
            hand_dot(doc, grip(j, s))


LRM = ins(lateral_machine_poses(), "tl")
SCENES["machine-lateral-raise"] = (lateral_machine_scene, LRM,
                                   fit(LRM, (SL_HIP[0] - 60, 30, 340, GROUND)))


# ==== incline chest press machine ====================================================================

IC_HIP = (150, 192)
IC_T = -122  # backrest reclined ~30°
IC_SEAT = IC_HIP[1] + 14
IC_SH = shoulder(IC_HIP, IC_T)
IC_A = tpt(IC_HIP, IC_T, 0.82, 26)                     # handles by the upper chest
IC_B = art.ang_pt(IC_A, -36, 62)                         # pressed up and forward
IC_PIV = bisect_pivot(IC_A, IC_B, y=28)


def incline_press_scene(doc, j, layer):
    g, gF = grip(j), grip(j, "F")
    if layer == "back":
        floor(doc, 170, 130)
        lift = max(0, math.dist(g, IC_A) * 0.3)
        st = column(doc, 26, top=20, w=30, lift=lift)
        art.cable(doc, [(st[0] + 5.5, 27), (IC_PIV[0], 20)])
        art.tube(doc, (12, 20), (IC_PIV[0] + 10, 20), 8)
        art.tube(doc, (IC_PIV[0], 20), IC_PIV, 8)
        kit.feet(doc, 16, IC_HIP[0] + 110)
        seat(doc, IC_HIP[0] - 30, IC_HIP[0] + 30, IC_SEAT)
        td, n = tframe(IC_T)
        a, b = art.add(art.add(IC_HIP, td, 6), n, -15), art.add(art.add(IC_HIP, td, 92), n, -15)
        slab(doc, a, b, 12, IC_HIP)
        art.tube(doc, art.add(b, n, -8), (60, GROUND - 2), 7)
        # Levers run beside the body from the pivot overhead to the handles.
        art.tube(doc, IC_PIV, gF, 6)
        art.tube(doc, IC_PIV, g, 7)
        art.pulley(doc, IC_PIV, 7)
    else:
        art.tube(doc, (g[0], g[1] - 9), (g[0], g[1] + 9), 6)
        hand_dot(doc, g)


def incline_press_pose(k):
    gp = arc_pt(IC_PIV, IC_A, IC_B, k)
    return body(IC_HIP, IC_T, h=-98, ankN=(IC_HIP[0] + 70, ANK), ankF=(IC_HIP[0] + 62, ANK),
                gN=gp, gF=(gp[0] - 3, gp[1] - 1), eN=1, eF=1)


ICP = ins([incline_press_pose(k) for k in (0, 0.5, 1)], "tr")
SCENES["incline-chest-press-machine"] = (incline_press_scene, ICP, fit(ICP, (12, 18, IC_HIP[0] + 110, GROUND)))


# ==== seated dip machine =============================================================================
# Upright seat, handles beside the ribs on levers pivoting behind the back; pushed down to straight arms.

DM_HIP = (200, 196)
DM_T = -90
DM_SEAT = DM_HIP[1] + 14
DM_SH = shoulder(DM_HIP, DM_T)
DM_A = (DM_SH[0] + 6, DM_SH[1] + 44)    # hands by the ribs, elbows back
DM_B = (DM_SH[0] + 4, DM_SH[1] + 80)    # arms straight by the hips
DM_PIV = bisect_pivot(DM_A, DM_B, x=DM_HIP[0] - 70)


def seated_dip_scene(doc, j, layer):
    g, gF = grip(j), grip(j, "F")
    if layer == "back":
        floor(doc, 190, 130)
        st = column(doc, 60, top=40, w=30, lift=max(0, (g[1] - DM_A[1]) * 0.35))
        # #949: cable runs onto the top of the pivot hub (r 8); at -12 it stopped short in mid-air.
        art.cable(doc, [(st[0] + 5.5, 47), (st[0] + 5.5, DM_PIV[1] - 8), (DM_PIV[0], DM_PIV[1] - 8)])
        kit.feet(doc, 50, DM_HIP[0] + 90)
        seat(doc, DM_HIP[0] - 30, DM_HIP[0] + 30, DM_SEAT)
        td, n = tframe(DM_T)
        a, b = art.add(art.add(DM_HIP, td, 8), n, -15), art.add(art.add(DM_HIP, td, 90), n, -15)
        slab(doc, a, b, 12, DM_HIP)
        art.tube(doc, (DM_PIV[0], DM_PIV[1]), (DM_PIV[0], GROUND - 2), 9, "butt")
        art.tube(doc, (DM_PIV[0], DM_SEAT + 20), (DM_HIP[0], DM_SEAT + 20), 7)
        # Levers run beside the body from the pivot behind the backrest to the handles.
        art.tube(doc, DM_PIV, gF, 6)
        art.tube(doc, DM_PIV, g, 7)
        hub(doc, DM_PIV, 8)
    else:
        art.tube(doc, (g[0] - 10, g[1]), (g[0] + 8, g[1]), 6)
        hand_dot(doc, g)


def seated_dip_pose(k):
    gp = arc_pt(DM_PIV, DM_A, DM_B, k)
    return body(DM_HIP, DM_T, h=-92, ankN=(DM_HIP[0] + 66, ANK), ankF=(DM_HIP[0] + 58, ANK),
                gN=gp, gF=(gp[0] - 3, gp[1] - 1), eN=1, eF=1)


SDM = ins([seated_dip_pose(k) for k in (0, 0.5, 1)], "tr")
SCENES["seated-dip-machine"] = (seated_dip_scene, SDM, fit(SDM, (50, 36, DM_HIP[0] + 90, GROUND)))


# ==== high row machine ===============================================================================
# Seated under a thigh pad, handles high and in front; pulled down and back to the shoulders.

HR_HIP = (170, 194)
HR_T = -86
HR_SEAT = HR_HIP[1] + 14
HR_SH = shoulder(HR_HIP, HR_T)
HR_A = (HR_SH[0] + 44, HR_SH[1] - 66)   # arms long, up and forward
HR_B = (HR_SH[0] + 22, HR_SH[1] + 8)    # handles by the front of the shoulders
HR_PIV = bisect_pivot(HR_A, HR_B, x=HR_SH[0] + 120)


def high_row_scene(doc, j, layer):
    g, gF = grip(j), grip(j, "F")
    if layer == "back":
        floor(doc, 200, 130)
        kit.feet(doc, HR_HIP[0] - 40, HR_PIV[0] + 30)
        seat(doc, HR_HIP[0] - 30, HR_HIP[0] + 28, HR_SEAT)
        art.tube(doc, (HR_PIV[0], HR_PIV[1]), (HR_PIV[0] + 10, GROUND - 2), 10, "butt")
        art.tube(doc, (HR_HIP[0], HR_SEAT + 24), (HR_PIV[0] + 6, HR_SEAT + 24), 8)
        # Thigh pad post in front of the knees.
        kn = j["kneeN"]
        art.tube(doc, (kn[0] + 14, kn[1] - 10), (kn[0] + 14, HR_SEAT + 24), 7)
        art.tube(doc, HR_PIV, gF, 6)
    else:
        kn = j["kneeN"]
        art.tube(doc, (kn[0] + 14, kn[1] - 10), (kn[0] - 2, kn[1] - 14), 6)
        art.pad(doc, (kn[0] - 22, kn[1] - 13), (kn[0] + 6, kn[1] - 13), 9)
        d = norm2(HR_PIV, g)
        horn = art.add(HR_PIV, d, -26)
        art.tube(doc, HR_PIV, horn, 7)
        art.plate(doc, horn, 18)
        art.tube(doc, HR_PIV, g, 7)
        hub(doc, HR_PIV, 8)
        hand_dot(doc, g)


def high_row_pose(k):
    gp = arc_pt(HR_PIV, HR_A, HR_B, k)
    return body(HR_HIP, HR_T, h=HR_T + (8 if k < 1 else 2), ankN=(HR_HIP[0] + 66, ANK), ankF=(HR_HIP[0] + 58, ANK),
                gN=gp, gF=(gp[0] - 3, gp[1] - 1), eN=1, eF=1)


HRM = ins([high_row_pose(k) for k in (0, 0.5, 1)], "tl")
SCENES["machine-high-row"] = (high_row_scene, HRM, fit(HRM, (HR_HIP[0] - 40, 20, HR_PIV[0] + 30, GROUND)))
