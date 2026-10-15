"""Scenes for the gym app comparison (#182): selectorized / plate-loaded machines and the bench pullover.

Built on the pose solver of scenes_lower.py (body(): hip pinned, ankles / hands solved with two-link IK onto
absolute targets) and fitted with scenes_power.fit(). The machines (chest-pad row, seated back extension,
lever squat, pendulum squat, belt squat, glute kickback, multi-hip, pullover) are not in kit.py, so they are
composed here from the art.py primitives (tubes, pads, plates, stacks, pulleys, cables). Levers swing about a
fixed pivot placed on the perpendicular bisector of their start / end attachment points, so the lever keeps
its length between frames. Angles as in poses.py (0 = right, 90 = down; the figure faces right).
"""
import math

import art
import kit
from art import GROUND
from scenes_lower import ANK, TOR, body, floor, grip, ins, shoulder, slab, tframe
from scenes_power import fit

SCENES = {}


# ---- helpers -------------------------------------------------------------------------------------

def mid(a, b, k=0.5):
    return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)


def tpt(hip, t, u, out=0.0):
    """Point on the torso: u along hip→shoulder (0..1), `out` px towards the chest (negative = back)."""
    td, n = tframe(t)
    return art.add(art.add(hip, td, u * TOR), n, out)


def bisect_pivot(a, b, y=None, x=None):
    """Point on the perpendicular bisector of a-b at height y (or at x): a lever pivoting there reaches both."""
    m = mid(a, b)
    d = (b[0] - a[0], b[1] - a[1])
    p = (-d[1], d[0])
    if y is not None:
        k = (y - m[1]) / p[1]
    else:
        k = (x - m[0]) / p[0]
    return (m[0] + p[0] * k, m[1] + p[1] * k)


def hub(doc, c, r=7):
    """Lever pivot / cam hub."""
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="#262A30" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.4:.1f}" fill="{art.CHROME}"/>')


def column(doc, x, top=40, w=34, lift=0.0, plates=11):
    """Selectorized stack in its shroud (x = left edge of the shroud); returns the stack's top (cable end)."""
    art.tube(doc, (x - 4, GROUND - 2), (x - 4, top), 9)
    art.tube(doc, (x + w + 12, GROUND - 2), (x + w + 12, top), 9)
    art.tube(doc, (x - 8, top), (x + w + 16, top), 8)
    art.shroud(doc, x, top + 22, GROUND - 4, w + 8)
    st = art.stack(doc, x + 4, top + 34, GROUND - 4, w, plates, lift)
    art.pulley(doc, (st[0], top + 7), 5.5)
    return st


def hand_dot(doc, c):
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="4.4" fill="#E2E6EB" stroke="{art.OUTLINE}" stroke-width="0.9"/>')


def seat(doc, x0, x1, top, post_x=None, t=12):
    """Seat pad (top face at `top`) on a post to a floor rail."""
    post_x = (x0 + x1) / 2 if post_x is None else post_x
    art.tube(doc, (post_x, top + t), (post_x, GROUND - 2), 10, "butt")
    art.pad(doc, (x0, top + t), (x1, top + t), t)


# ==== seated chest-pad row =========================================================================

MR_HIP = (148, 190)
MR_T = -84
MR_SEAT = 205
MR_SH = shoulder(MR_HIP, MR_T)
MR_A = (MR_SH[0] + 80, MR_SH[1] + 30)    # arms long
MR_B = (MR_SH[0] + 24, MR_SH[1] + 46)    # elbows back, handle by the ribs
MR_PIV = bisect_pivot(MR_A, MR_B, y=236)  # plate-loaded lever pivoting low in front


def mr_grip(k):
    """Handle on its arc around the pivot, k = 0 (arms long) .. 1 (pulled)."""
    a0 = math.degrees(math.atan2(MR_A[1] - MR_PIV[1], MR_A[0] - MR_PIV[0]))
    a1 = math.degrees(math.atan2(MR_B[1] - MR_PIV[1], MR_B[0] - MR_PIV[0]))
    return art.ang_pt(MR_PIV, a0 + (a1 - a0) * k, math.dist(MR_A, MR_PIV))


MR_BEND_B = (225, 185)  # bend of the dog-leg lever (pulled position): it reaches over the knees, not through


def mr_lever(doc, g, plate=True):
    """Dog-leg lever from the pivot up in front of the knees, then back to the vertical handle held at g;
    plate on a horn near the pivot. The bend turns with the lever about the pivot (rigid)."""
    rot = math.radians(math.degrees(math.atan2(g[1] - MR_PIV[1], g[0] - MR_PIV[0]))
                       - math.degrees(math.atan2(MR_B[1] - MR_PIV[1], MR_B[0] - MR_PIV[0])))
    v = art.sub(MR_BEND_B, MR_PIV)
    bend = (MR_PIV[0] + v[0] * math.cos(rot) - v[1] * math.sin(rot), MR_PIV[1] + v[0] * math.sin(rot) + v[1] * math.cos(rot))
    d = art.norm(art.sub(bend, MR_PIV))
    n = (d[1], -d[0])
    if n[0] < 0:
        n = (-n[0], -n[1])
    if plate:
        horn = art.add(MR_PIV, d, 30)
        art.tube(doc, horn, art.add(horn, n, 16), 5)
        art.plate(doc, art.add(horn, n, 14), 19)
    end = (g[0], g[1] + 12)
    art.tube(doc, MR_PIV, bend, 8)
    art.tube(doc, bend, end, 8)
    doc.add(f'<circle cx="{bend[0]:.1f}" cy="{bend[1]:.1f}" r="4" fill="#2A2E34"/>')
    art.tube(doc, (g[0], g[1] - 10), end, 5)


def machine_row_scene(doc, j, layer, single=False):
    gN, gF = grip(j, "N"), grip(j, "F")
    if layer == "back":
        floor(doc, 200, 130)
        # Frame: base rail, seat post, chest-pad post, upright to the lever pivot.
        kit.feet(doc, 96, MR_PIV[0] + 40)
        seat(doc, MR_HIP[0] - 34, MR_HIP[0] + 26, MR_SEAT)
        a, b = tpt(MR_HIP, MR_T, 0.3, 15), tpt(MR_HIP, MR_T, 0.86, 15)
        pc = mid(a, b)
        art.tube(doc, (pc[0] + 13, pc[1]), (pc[0] + 13, MR_SEAT + 26), 9)
        art.tube(doc, (MR_HIP[0], MR_SEAT + 26), (MR_PIV[0], MR_SEAT + 26), 8)
        art.tube(doc, (MR_PIV[0], MR_PIV[1]), (MR_PIV[0] + 14, GROUND - 2), 10, "butt")
        art.tube(doc, (MR_PIV[0], MR_PIV[1]), (MR_PIV[0] - 14, GROUND - 2), 8, "butt")
        # Chest pad, then the levers beside the body (far one stays out on the single-arm version).
        slab(doc, a, b, 14, j["shoulder"])
        art.tube(doc, (pc[0] + 6, pc[1]), (pc[0] + 14, pc[1]), 8)
        mr_lever(doc, gF, plate=False)
        # Foot bar.
        art.tube(doc, (j["ankleN"][0] + 9, GROUND - 16), (j["ankleN"][0] + 9, GROUND - 2), 6, "butt")
    else:
        mr_lever(doc, gN)
        hub(doc, MR_PIV, 8)
        hand_dot(doc, gN)


def machine_row_pose(k, single=False):
    g = mr_grip(k)
    gf = mr_grip(0.0 if single else k)
    return body(MR_HIP, MR_T, h=MR_T + 4, ankN=(MR_HIP[0] + 66, ANK), ankF=(MR_HIP[0] + 60, ANK),
                gN=g, gF=(gf[0] - 2, gf[1] - 1), eN=1, eF=1, hN=95, hF=95,
                **({"lit_sides": "N"} if single else {}))


MR = [machine_row_pose(k) for k in (0, 0.5, 1)]
MRS = [machine_row_pose(k, True) for k in (0, 0.5, 1)]
MR_BOX = (MR_HIP[0] - 40, 150, MR_PIV[0] + 44, GROUND)
SCENES["machine-row"] = (machine_row_scene, MR, fit(MR, MR_BOX))
SCENES["machine-row-single"] = (lambda d, j, l: machine_row_scene(d, j, l, True), MRS, fit(MRS, MR_BOX))


# ==== seated back extension machine =================================================================

BX_HIP = (196, 188)
BX_SEAT = 203
BX_STACK = 64
BX_ANK = (BX_HIP[0] + 72, GROUND - 22)


def back_ext_machine_scene(doc, j, layer):
    hip, sh = j["hip"], j["shoulder"]
    td, n = kit.torso_frame(j)
    t = math.degrees(math.atan2(td[1], td[0]))
    if layer == "back":
        floor(doc, 190, 130)
        kit.feet(doc, BX_STACK - 10, 290)
        lift = max(0.0, (-48 - t)) * 0.35
        st = column(doc, BX_STACK, top=70, lift=lift)
        # Seat and frame forward to the foot plate.
        seat(doc, hip[0] - 36, hip[0] + 30, BX_SEAT, hip[0] - 4)
        art.tube(doc, (hip[0] - 4, BX_SEAT + 30), (276, BX_SEAT + 30), 8)
        # Foot plate under the soles, thigh roller over the knees.
        sole = art.add(j["ankleN"], (1, 8))
        art.tube(doc, (sole[0] - 2, sole[1] + 4), (sole[0] - 2, BX_SEAT + 30), 6)
        slab(doc, (sole[0] - 16, sole[1] - 2), (sole[0] + 16, sole[1] + 2), 6, j["ankleN"], stitch=False)
        # Cam at the hip, cable down and back to the stack.
        cam = (hip[0] - 4, hip[1] + 6)
        art.tube(doc, cam, (hip[0] - 4, BX_SEAT + 12), 9, "butt")
        px = BX_STACK + 54
        art.pulley(doc, (px, cam[1] + 3), 5)
        art.pulley(doc, (px, 77), 5)
        art.cable(doc, [(cam[0], cam[1] + 9), (px, cam[1] + 8)])
        art.cable(doc, [(px + 5, cam[1] + 3), (px + 5, 77)])
        art.cable(doc, [(px, 72), (st[0], 71.5)])
        art.cable(doc, [(st[0] - 5.5, 77), st])
        # Lever from the cam up behind the back to the pad across the shoulder blades.
        p0 = art.add(cam, n, -24)
        p1 = art.add(art.add(hip, td, 0.8 * TOR), n, -26)
        art.tube(doc, cam, p0, 8)
        art.tube(doc, p0, p1, 8)
        hub(doc, cam, 9)
        slab(doc, tpt(hip, t, 0.58, -14), tpt(hip, t, 0.98, -14), 12, sh)
        art.tube(doc, tpt(hip, t, 0.8, -26), tpt(hip, t, 0.8, -18), 6)
    else:
        k = j["kneeN"]
        kit.roller_pad(doc, (k[0] - 4, k[1] - 14), 8)


def back_ext_machine_pose(t, h):
    gn = tpt(BX_HIP, t, 0.74, 12)
    return body(BX_HIP, t, h=h, ankN=BX_ANK, ankF=(BX_ANK[0] - 4, BX_ANK[1] + 1),
                fN=-10, fF=-10, gN=gn, gF=art.add(gn, (2, -6)), eN=1, eF=1, hN=t + 180, hF=t + 180)


BXM = [back_ext_machine_pose(-44, -20), back_ext_machine_pose(-68, -56), back_ext_machine_pose(-94, -88)]
SCENES["back-extension-machine"] = (back_ext_machine_scene, BXM, fit(BXM, (BX_STACK - 10, 60, 290, GROUND)))


# ==== lever squat machine (shoulder pads) ============================================================

MS_ANK = (222, ANK - 8)  # on the foot platform
MS_PLAT = (150, 290)


def ms_pad(hip, t):
    """Centre of the shoulder pad resting on top of the shoulder."""
    td, n = tframe(t)
    return art.add(art.add(shoulder(hip, t), td, 9), n, -6)


MS_POSE = [((206, 148), -88), ((190, 180), -74), ((176, 212), -60)]
MS_PIV = bisect_pivot(ms_pad(*MS_POSE[0]), ms_pad(*MS_POSE[-1]), x=58)


def platform(doc, x0, x1, h=8):
    g = doc.box_grad([(0, "#4A5059"), (1, "#24282E")])
    doc.add(f'<rect x="{x0:.1f}" y="{GROUND - h:.1f}" width="{x1 - x0:.1f}" height="{h}" rx="2" fill="{g}" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>')
    for x in range(int(x0) + 8, int(x1) - 4, 9):
        doc.add(f'<line x1="{x}" y1="{GROUND - h + 2}" x2="{x}" y2="{GROUND - 2}" stroke="#000" stroke-opacity="0.25" '
                f'stroke-width="1"/>')


def machine_squat_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    t = math.degrees(math.atan2(td[1], td[0]))
    p = ms_pad(j["hip"], t)
    if layer == "back":
        floor(doc, 190, 130)
        platform(doc, *MS_PLAT)
        # Pivot tower behind the lifter, lever forward to the pad yoke, plate horn on the lever.
        art.tube(doc, (MS_PIV[0], GROUND - 2), MS_PIV, 12, "butt")
        art.tube(doc, (MS_PIV[0], MS_PIV[1] + 40), (MS_PLAT[0], GROUND - 4), 7)
        kit.feet(doc, MS_PIV[0] - 30, MS_PIV[0] + 30)
        back = art.add(p, n, -18)
        art.tube(doc, MS_PIV, back, 10)
        horn = mid(MS_PIV, back, 0.45)
        art.tube(doc, horn, (horn[0], horn[1] - 4), 5)
        art.plate(doc, horn, 26)
        hub(doc, MS_PIV, 8)
        art.tube(doc, back, art.add(p, n, -6), 8)
    else:
        # Shoulder pad over the top of the shoulder, handle forward of it.
        slab(doc, art.add(p, n, -12), art.add(p, n, 9), 10, j["shoulder"])
        art.tube(doc, art.add(art.add(p, n, 4), td, 4), grip(j), 5)
        hand_dot(doc, grip(j))


def machine_squat_pose(hip, t):
    td, n = tframe(t)
    g = art.add(art.add(shoulder(hip, t), n, 20), td, 4)
    return body(hip, t, h=max(t, -84), ankN=MS_ANK, ankF=(MS_ANK[0] - 4, MS_ANK[1]), gN=g, gF=art.add(g, td, 2),
                eN=1, eF=1)


MSQ = [machine_squat_pose(*a) for a in MS_POSE]
SCENES["machine-squat"] = (machine_squat_scene, MSQ, fit(MSQ, (MS_PIV[0] - 32, 70, MS_PLAT[1], GROUND)))


# ==== pendulum squat =================================================================================

PS_ANK = (240, GROUND - 26)
PS_FOOT = -16  # platform tilt (toes up)
PS_POSE = [((216, 135), -103), ((194, 176), -92), ((172, 204), -80)]


def ps_back(hip, t):
    """Contact point of the back pad (mid back)."""
    return tpt(hip, t, 0.55, -15)


PS_PIV = bisect_pivot(ps_back(*PS_POSE[0]), ps_back(*PS_POSE[-1]), x=60)


def pendulum_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    t = math.degrees(math.atan2(td[1], td[0]))
    hip, sh = j["hip"], j["shoulder"]
    if layer == "back":
        floor(doc, 190, 130)
        # A-frame up to the pivot behind and above the lifter.
        art.tube(doc, (PS_PIV[0] - 40, GROUND - 2), PS_PIV, 11)
        art.tube(doc, (PS_PIV[0] + 30, GROUND - 2), PS_PIV, 9)
        kit.feet(doc, PS_PIV[0] - 60, 290)
        # Tilted foot platform.
        fd = (math.cos(math.radians(PS_FOOT)), math.sin(math.radians(PS_FOOT)))
        sole = art.add(PS_ANK, (-fd[1], fd[0]), 7)
        art.tube(doc, art.add(sole, fd, 6), (PS_ANK[0] + 10, GROUND - 2), 8, "butt")
        slab(doc, art.add(sole, fd, -22), art.add(sole, fd, 30), 8, j["kneeN"], stitch=False)
        # Swing arm from the pivot to the carriage behind the back pad, plates on its horn.
        bp = ps_back(hip, t)
        car = art.add(bp, n, -14)
        art.tube(doc, PS_PIV, car, 11)
        horn = mid(PS_PIV, car, 0.38)
        art.tube(doc, art.add(horn, (-14, 0)), art.add(horn, (14, 0)), 5)
        art.plate(doc, horn, 24)
        hub(doc, PS_PIV, 9)
        # Carriage frame and back pad from the hips to the shoulders.
        art.tube(doc, art.add(tpt(hip, t, 0.05, -24), td, 0), tpt(hip, t, 1.05, -24), 8)
        slab(doc, tpt(hip, t, 0.0, -13), tpt(hip, t, 1.02, -13), 12, sh)
        art.tube(doc, tpt(hip, t, 0.02, -20), art.add(grip(j), (0, 0)), 5)
    else:
        sp = art.add(art.add(sh, td, 9), n, -5)
        slab(doc, art.add(sp, n, -11), art.add(sp, n, 8), 9, sh)
        hand_dot(doc, grip(j))


def pendulum_pose(hip, t):
    g = tpt(hip, t, 0.08, 14)
    g = (g[0] - 2, g[1] + 6)
    return body(hip, t, h=t + 8, ankN=PS_ANK, ankF=(PS_ANK[0] - 3, PS_ANK[1] + 1), fN=PS_FOOT, fF=PS_FOOT,
                gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1)


PSQ = [pendulum_pose(*a) for a in PS_POSE]
SCENES["pendulum-squat"] = (pendulum_scene, PSQ, fit(PSQ, (PS_PIV[0] - 44, PS_PIV[1] - 12, 290, GROUND)))


# ==== belt squat =====================================================================================

BS_H = 30  # platform height
BS_ANK = (214, GROUND - BS_H - 4)
BS_RAIL = (262, 128)  # front handle the hands rest on
BS_PIV = (70, GROUND - 40)
BS_POSE = [((202, 120), -88), ((196, 150), -84), ((190, 182), -80)]


def belt_squat_scene(doc, j, layer):
    hip = j["hip"]
    td, n = kit.torso_frame(j)
    if layer == "back":
        floor(doc, 190, 140)
        # Raised deck in two halves (slot in the middle for the chain).
        for x0, x1 in ((150, 200), (214, 268)):
            g = doc.box_grad([(0, "#4A5059"), (1, "#24282E")])
            doc.add(f'<rect x="{x0}" y="{GROUND - BS_H}" width="{x1 - x0}" height="6" rx="2" fill="{g}" '
                    f'stroke="#0A0B0D" stroke-width="0.8"/>')
        art.tube(doc, (154, GROUND - BS_H + 6), (154, GROUND - 2), 7, "butt")
        art.tube(doc, (264, GROUND - BS_H + 6), (264, GROUND - 2), 7, "butt")
        kit.feet(doc, BS_PIV[0] - 20, 300)
        # Lever from the rear pivot under the deck; chain from the belt down to it, plates on the front horn.
        hook = (hip[0] + 2, GROUND - BS_H - 6 + (hip[1] - BS_POSE[0][0][1]) * 0.3)
        d = art.norm(art.sub(hook, BS_PIV))
        tip = art.add(BS_PIV, d, 168)
        art.tube(doc, BS_PIV, tip, 9)
        art.tube(doc, art.add(tip, (0, -10)), art.add(tip, (0, 10)), 5)
        art.plate(doc, tip, 17)
        hub(doc, BS_PIV, 8)
        art.tube(doc, (BS_PIV[0], BS_PIV[1]), (BS_PIV[0], GROUND - 2), 10, "butt")
        doc.add(f'<line x1="{hip[0] + 2:.1f}" y1="{hip[1] + 6:.1f}" x2="{hook[0]:.1f}" y2="{hook[1]:.1f}" '
                f'stroke="#9AA3AD" stroke-width="3" stroke-dasharray="4 2"/>')
        # Front post and handle.
        art.tube(doc, (BS_RAIL[0] + 26, GROUND - 2), (BS_RAIL[0] + 26, BS_RAIL[1]), 9, "butt")
        art.tube(doc, (BS_RAIL[0] + 26, BS_RAIL[1]), BS_RAIL, 7)
    else:
        # Hip belt.
        a, b = art.add(art.add(hip, n, -15), td, 4), art.add(art.add(hip, n, 15), td, 4)
        doc.add(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="#1E2227" '
                f'stroke-width="9" stroke-linecap="round"/>'
                f'<circle cx="{hip[0] + 2:.1f}" cy="{hip[1] + 6:.1f}" r="3" fill="none" stroke="{art.CHROME}" '
                f'stroke-width="1.6"/>')
        hand_dot(doc, grip(j))


def belt_squat_pose(hip, t):
    return body(hip, t, h=max(t, -86), ankN=BS_ANK, ankF=(BS_ANK[0] - 4, BS_ANK[1]), gN=BS_RAIL,
                gF=(BS_RAIL[0] - 3, BS_RAIL[1] + 1), eN=1, eF=1)


BSQ = [belt_squat_pose(*a) for a in BS_POSE]
SCENES["belt-squat"] = (belt_squat_scene, BSQ, fit(BSQ, (BS_PIV[0] - 22, 100, 300, GROUND)))


# ==== glute kickback machine =========================================================================

GK_HIP = (176, 150)
GK_T = -22
GK_ANK = (GK_HIP[0] + 14, ANK - 8)  # standing (far) foot on the platform
GK_STACK = 296
GK_LEGS = [(80, 150), (118, 186), (152, 214)]  # working thigh / shin angles: under the hip -> driven back


def gk_plate(legN):
    """Sole contact of the working foot (centre of the foot plate)."""
    knee = art.ang_pt(GK_HIP, legN[0], 56)
    ank = art.ang_pt(knee, legN[1], 54)
    return art.ang_pt(ank, legN[1] + 5, 7)


GK_PIV = bisect_pivot(gk_plate(GK_LEGS[0]), gk_plate(GK_LEGS[-1]), x=GK_HIP[0] - 6)


def kickback_machine_scene(doc, j, layer):
    hip, sh = j["hip"], j["shoulder"]
    td, n = kit.torso_frame(j)
    ank, knee = j["ankleN"], j["kneeN"]
    if layer == "back":
        floor(doc, 200, 130)
        platform(doc, 150, GK_STACK - 8)
        kit.feet(doc, 100, GK_STACK + 56)
        lift = max(0.0, ank[1] - gk_plate(GK_LEGS[0])[1]) * -0.12 + max(0.0, GK_HIP[0] - ank[0]) * 0.1
        st = column(doc, GK_STACK, top=70, lift=max(0.0, lift))
        art.cable(doc, [(st[0] - 5.5, 77), (st[0] - 5.5, 77)])
        art.cable(doc, [(st[0] + 5.5, 77), st])
        # Chest pad on a post from the frame, handles under it.
        a, b = tpt(GK_HIP, GK_T, 0.45, 15), tpt(GK_HIP, GK_T, 1.0, 15)
        pc = mid(a, b)
        art.tube(doc, (pc[0] + 4, pc[1] + 14), (GK_STACK - 4, pc[1] + 40), 8)
        slab(doc, a, b, 12, sh)
        art.tube(doc, (pc[0] + 4, pc[1] + 6), (pc[0] + 4, pc[1] + 14), 8)
        art.tube(doc, (GK_PIV[0], GK_PIV[1]), (GK_STACK - 4, GK_PIV[1] + 8), 8)
        art.cable(doc, [GK_PIV, (st[0] - 5.5, GK_PIV[1] + 8), (st[0] - 5.5, 77)])
        # Lever from the pivot (level with the hip, beside the body) to the foot plate.
        art.tube(doc, GK_PIV, art.add(gk_sole(j), gk_sd(j), 4), 7)
        hub(doc, GK_PIV, 8)
    else:
        c, sd = gk_sole(j), gk_sd(j)
        slab(doc, art.add(c, sd, -8), art.add(c, sd, 20), 6, ank, stitch=False)
        hand_dot(doc, grip(j))


def gk_sole(j):
    ank, knee = j["ankleN"], j["kneeN"]
    return art.ang_pt(ank, math.degrees(math.atan2(ank[1] - knee[1], ank[0] - knee[0])) + 5, 7)


def gk_sd(j):
    return art.norm(art.sub(j["toeN"], j["ankleN"]))


def kickback_machine_pose(legN):
    g = tpt(GK_HIP, GK_T, 0.85, 26)
    return body(GK_HIP, GK_T, h=GK_T + 12, ankF=GK_ANK, lN=(legN[0], legN[1], legN[1] - 90), gN=g,
                gF=(g[0] - 3, g[1] + 1), eN=1, eF=1, hN=10, hF=10, lit_sides="N")


GKB = [kickback_machine_pose(l) for l in GK_LEGS]
SCENES["glute-kickback-machine"] = (kickback_machine_scene, GKB, fit(GKB, (90, 60, GK_STACK + 56, GROUND)))


# ==== multi-hip machine: extension (side view) and abduction (back view) ==============================

MH_HIP = (186, 140)
MH_COL = 274
MH_PLAT = 12


def mh_frame(doc, hub_c, hand_y, col=MH_COL):
    """Multi-hip column with its stack, a hand bar and the arm out to the lever hub."""
    st = column(doc, col, top=36, lift=0)
    art.tube(doc, (col - 4, hand_y), (col - 40, hand_y), 7)
    art.tube(doc, (col - 4, hub_c[1]), hub_c, 9)
    art.cable(doc, [(st[0] + 5.5, 43), st])
    return st


def multi_hip_ext_scene(doc, j, layer):
    hip, knee = j["hip"], j["kneeN"]
    if layer == "back":
        floor(doc, 210, 130)
        platform(doc, 120, MH_COL - 6, MH_PLAT)
        kit.feet(doc, 110, MH_COL + 52)
        mh_frame(doc, hip, grip(j)[1])
    else:
        # Lever from the hub (at the hip joint) down the thigh to the pad behind the lower thigh.
        d = art.norm(art.sub(knee, hip))
        bk = (d[1], -d[0])  # back of the thigh for a leg below the hip, figure facing right
        if bk[0] > 0:
            bk = (-bk[0], -bk[1])
        pc = art.add(art.add(hip, d, 44), bk, 9)
        art.tube(doc, art.add(hip, bk, 2), art.add(pc, bk, 3), 7)
        kit.roller_pad(doc, art.add(pc, bk, 2), 9)
        hub(doc, hip, 5.5)
        hand_dot(doc, grip(j))


def multi_hip_ext_pose(thigh, t=-86):
    g = (MH_COL - 34, MH_HIP[1] - 24)
    return body(MH_HIP, t, h=t, ankF=(MH_HIP[0] + 2, ANK - MH_PLAT), lN=(thigh, thigh + 6, thigh - 84), gN=g,
                gF=(g[0] - 2, g[1] + 1), eN=1, eF=1, lit_sides="N")


MHE = [multi_hip_ext_pose(56), multi_hip_ext_pose(88), multi_hip_ext_pose(122, -82)]
SCENES["multi-hip-extension"] = (multi_hip_ext_scene, MHE, fit(MHE, (110, 30, MH_COL + 52, GROUND)))


MA_HIP = (196, 142)


def multi_hip_abd_scene(doc, j, layer):
    hn, kn = j["hipN"], j["kneeN"]
    if layer == "back":
        floor(doc, 200, 120)
        platform(doc, 130, 270, MH_PLAT)
        # Column behind the lifter (seen past the body), hub arm out to the working hip.
        art.tube(doc, (196, GROUND - 2), (196, 30), 12, "butt")
        art.tube(doc, (150, 30), (242, 30), 8)
        art.tube(doc, (150, 30), (150, GROUND - 2), 8, "butt")
        art.tube(doc, (242, 30), (242, GROUND - 2), 8, "butt")
        art.tube(doc, (154, grip(j, "F")[1]), (238, grip(j, "N")[1]), 7)
        art.tube(doc, (196, hn[1] - 6), (hn[0] + 18, hn[1] - 6), 9)
    else:
        d = art.norm(art.sub(kn, hn))
        out = (-d[1], d[0])
        if out[0] < 0:
            out = (-out[0], -out[1])
        h = art.add(hn, out, 18)
        pc = art.add(art.add(hn, d, 40), out, 12)
        art.tube(doc, h, art.add(pc, d, 4), 7)
        g = doc.box_grad([(0, "#3A4048"), (0.3, "#1E2227"), (1, "#121417")], vertical=False)
        ang = math.degrees(math.atan2(d[1], d[0])) - 90
        doc.add(f'<rect x="{pc[0] - 5:.1f}" y="{pc[1] - 15:.1f}" width="10" height="30" rx="4.5" fill="{g}" '
                f'stroke="#0A0B0D" stroke-width="0.8" transform="rotate({ang:.1f} {pc[0]:.1f} {pc[1]:.1f})"/>')
        hub(doc, h, 8)


def multi_hip_abd_pose(thigh):
    return body(MA_HIP, -90, lN=(thigh, thigh, 0), lF=(92, 92, 180), gN=(MA_HIP[0] + 34, MA_HIP[1] - 24),
                gF=(MA_HIP[0] - 34, MA_HIP[1] - 24), eN=-1, eF=1, front="back", lift=0,
                ankF=None, lit_sides="N")


MHA = [multi_hip_abd_pose(90), multi_hip_abd_pose(72), multi_hip_abd_pose(54)]
SCENES["multi-hip-abduction"] = (multi_hip_abd_scene, MHA, fit(MHA, (130, 24, 270, GROUND)))


# ==== pullover machine ===============================================================================

PO_HIP = (190, 186)
PO_T = -98
PO_SEAT = 201
PO_STACK = 58
PO_ARMS = [-106, -24, 78]  # upper-arm angle: overhead behind the head -> down by the hips


def pullover_machine_scene(doc, j, layer):
    hip, sh = j["hip"], j["shoulder"]
    td, n = kit.torso_frame(j)
    en = j["elbowN"]
    ua = art.norm(art.sub(en, sh))
    lead = (-ua[1], ua[0])  # side of the upper arm the sweep moves towards (pads press there)
    if layer == "back":
        floor(doc, 180, 130)
        kit.feet(doc, PO_STACK - 10, 280)
        lift = (math.degrees(math.atan2(ua[1], ua[0])) - PO_ARMS[0]) * 0.1
        st = column(doc, PO_STACK, top=40, lift=max(0.0, lift))
        art.cable(doc, [(st[0] + 5.5, 47), st])
        art.cable(doc, [(st[0] - 5.5, 47), (st[0] - 5.5, 42), (sh[0] - 22, 42), (sh[0] - 12, sh[1] - 4)])
        seat(doc, hip[0] - 34, hip[0] + 30, PO_SEAT, hip[0] - 6)
        art.tube(doc, (hip[0] - 6, PO_SEAT + 30), (PO_STACK + 50, PO_SEAT + 30), 8)
        # Back pad up the spine, frame up to the cam at shoulder height.
        slab(doc, tpt(hip, PO_T, 0.0, -14), tpt(hip, PO_T, 0.95, -14), 12, sh)
        art.tube(doc, tpt(hip, PO_T, 0.5, -26), (PO_STACK + 50, 120), 8)
        art.tube(doc, tpt(hip, PO_T, 0.95, -26), sh, 8)
        # Far arm of the yoke.
        art.tube(doc, sh, art.add(art.add(sh, ua, 40), lead, 9), 6)
    else:
        # Near yoke arm from the cam at the shoulder to the elbow pad, crossbar at the hands.
        pad_c = art.add(art.add(sh, ua, 34), lead, 9)
        art.tube(doc, sh, pad_c, 7)
        slab(doc, art.add(pad_c, ua, -14), art.add(pad_c, ua, 10), 8, en, stitch=False)
        # Cam at the shoulder axis (the cable from the stack wraps it), arm on to the hand bar (end-on).
        doc.add(f'<circle cx="{sh[0]:.1f}" cy="{sh[1]:.1f}" r="12.5" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>')
        hub(doc, sh, 7)
        g = grip(j)
        art.tube(doc, art.add(pad_c, ua, 8), g, 6)
        kit.handle(doc, g)
        doc.add(f'<circle cx="{g[0]:.1f}" cy="{g[1]:.1f}" r="7" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>')
        hand_dot(doc, g)


def pullover_machine_pose(u):
    rel = -96
    return body(PO_HIP, PO_T, h=PO_T + 6, ankN=(PO_HIP[0] + 64, ANK), ankF=(PO_HIP[0] + 58, ANK),
                aN=(u, u + rel, u + rel), aF=(u - 2, u - 2 + rel, u - 2 + rel))


POM = [pullover_machine_pose(u) for u in PO_ARMS]
SCENES["machine-pullover"] = (pullover_machine_scene, POM, fit(POM, (PO_STACK - 10, 34, 280, GROUND)))


# ==== dumbbell bench pullover (lying across the bench) ================================================

DP_BENCH = (150, GROUND - 52)  # centre-top of the bench pad, bench seen end-on
DP_SH = (DP_BENCH[0] - 4, DP_BENCH[1] - 13)
DP_HIP = art.ang_pt(DP_SH, 10, TOR)
DP_T = math.degrees(math.atan2(DP_SH[1] - DP_HIP[1], DP_SH[0] - DP_HIP[0]))
DP_FOOT = (DP_HIP[0] + 56, ANK)


def db_pullover_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 120)
        x, y = DP_BENCH
        art.tube(doc, (x, y + 12), (x, GROUND - 2), 10, "butt")
        kit.feet(doc, x - 26, x + 26)
        g = doc.box_grad([(0, art.PAD[0]), (0.25, art.PAD[1]), (1, art.PAD[2])])
        doc.add(f'<rect x="{x - 24}" y="{y}" width="48" height="13" rx="5" fill="{g}" stroke="#0A0B0D" '
                f'stroke-width="0.8"/>')
    else:
        w, h = j["wristN"], j["handN"]
        d = art.norm(art.sub(h, w))
        kit.dumbbell(doc, art.add(w, d, 16), math.degrees(math.atan2(d[1], d[0])), r=9)


def db_pullover_pose(a):
    g = art.ang_pt(DP_SH, a, 80)
    # Elbows softly bent with the forearms folding towards the face over the chest and down towards the floor
    # behind the head (eN=-1 bent them backwards: hyperextended).
    return body(DP_HIP, DP_T, h=DP_T - 6, ankN=DP_FOOT, ankF=(DP_FOOT[0] - 6, ANK), gN=g,
                gF=(g[0] + 1, g[1] - 1), eN=1, eF=1)


DBP = [db_pullover_pose(a) for a in (-84, -132, -178)]
SCENES["db-bench-pullover"] = (db_pullover_scene, DBP, fit(DBP, (DP_BENCH[0] - 30, DP_BENCH[1], DP_BENCH[0] + 30, GROUND),
                                                            lambda j: [(j["handN"][0] - 24, j["handN"][1] - 24,
                                                                        j["handN"][0] + 24, j["handN"][1] + 24)]))
