"""Scenes for the #174 catalog extension (push): chest and shoulder variations.

Built on the scenes_upper.py helpers (B() pinned poses with IK goals, fit() framing) and the Smith machine
of scenes_lower.py. Movements that leave the side / front plane (dumbbell flyes, chest-supported reverse
fly, archer push-up, cable rear-delt fly) place the joints from a small 3D body model in the scene's back
layer (art.render draws the figure from the same joint dict afterwards); those entries are custom
renderers with one scene per frame.
"""
import math

import art
import kit
from art import GROUND
from poses import P
from scenes_lower import smith_bar, smith_frame
from scenes_upper import (BENCH, BENCH_TOP, BP_HIP, BP_SH, FL_SH, FLOOR_Y, FORE, FR_HIP, FR_LEGS, G, HAND, INC,
                          INC_HIP, INC_SH, PD_LEGS, PRESS_KS, SHIN, ST_HIP, SW, THIGH, TORSO, UP, UP_HIP, UP_SH, UPPER, B,
                          along, back_pad, bar_end, bench_rack, both, chest_pt, fit, floor, fr_sh, grip_n, held_at, lerp,
                          lying_bench, mat_scene, rigid_plank, S, seated, seq, standing, supine, tower, tower_box)

ARM = UPPER + FORE + HAND / 2  # shoulder to grip, arm straight


def reach_above(x, sh, length=80):
    """Point on the vertical line x, `length` from the shoulder, above it (vertical bar path)."""
    dx = x - sh[0]
    return (x, sh[1] - math.sqrt(max(0.0, length * length - dx * dx)))


def deg(v):
    return math.degrees(math.atan2(v[1], v[0]))


# ==== decline barbell bench ========================================================================

DEC_T = 163  # shoulders below the hips
DEC_HIP = (238, 180)
DEC_SH = art.ang_pt(DEC_HIP, DEC_T, TORSO)
DEC_LEGS = dict(lN=(-24, 84, -6), lF=(-22, 86, -4))


def dec_ankle():
    j = art.F.place(P(t=DEC_T, pin=("hip", DEC_HIP), **DEC_LEGS))
    return j["ankleN"]


DEC_ANK = dec_ankle()


def decline_poses():
    bottom = chest_pt(DEC_HIP, DEC_T, 0.66, 22)
    top = reach_above(bottom[0] - 4, DEC_SH, 80)

    def f(k):
        g = lerp(top, bottom, k)
        return B(DEC_HIP, DEC_T, aN=G(g, 1), aF=G((g[0] - 3, g[1] - 1), 1), h=DEC_T + 6, **DEC_LEGS)
    return seq(f, PRESS_KS)


def decline_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 120)
        bench_rack(doc, DEC_SH[0] - 30, DEC_SH[1] - 78)
        a, b = back_pad(doc, DEC_HIP, DEC_T, -0.12, 1.32, back=14)
        col = DEC_ANK[0] + 14
        # Post under the low (head) end, main post under the hips, leg-holder column in front.
        art.tube(doc, art.add(a, (8, -3)), (a[0] + 8, GROUND - 2), 7, "butt")
        art.tube(doc, art.add(b, (-6, -3)), (b[0] - 6, GROUND - 2), 8, "butt")
        art.tube(doc, (b[0] - 6, GROUND - 40), (col, GROUND - 40), 6)
        art.tube(doc, (col, GROUND - 2), (col, DEC_ANK[1] - 30), 7, "butt")
        art.tube(doc, (col, DEC_ANK[1] - 30), (col - 10, DEC_ANK[1] - 30), 5)
        kit.feet(doc, a[0] - 18, a[0] + 34)
        kit.feet(doc, b[0] - 30, col + 22)
    else:
        bar_end(doc, kit.grip(j), 23)
        # Foot rollers hooked in front of the ankles.
        col = DEC_ANK[0] + 14
        art.tube(doc, (col, DEC_ANK[1] - 2), (j["ankleN"][0] + 9, j["ankleN"][1] - 2), 5)
        kit.roller_pad(doc, (j["ankleN"][0] + 9, j["ankleN"][1] - 2), 7.5)
        # Thigh pad over the knees.
        kit.roller_pad(doc, (col - 14, DEC_ANK[1] - 36), 9)


# ==== Smith machine presses ========================================================================

SB_X = BP_SH[0] + 20  # bar rail over the mid-chest


def smith_bench_poses():
    bottom = (SB_X, BP_SH[1] - 22)
    top = reach_above(SB_X, BP_SH, 80)

    def f(k):
        g = lerp(top, bottom, k)
        return lying_bench(BP_HIP, 180, g, (g[0] - 3, g[1] - 1), 1, curl=-2)
    return seq(f, PRESS_KS)


def smith_bench_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 120)
        smith_frame(doc, SB_X, top=20)
        kit.flat_bench(doc, 104, 254, BENCH_TOP)
    else:
        smith_bar(doc, kit.grip(j), 23)


SI_BOTTOM = chest_pt(INC_HIP, INC, 0.9, 22)
SI_X = SI_BOTTOM[0]


def smith_incline_poses():
    top = reach_above(SI_X, INC_SH, 80)

    def f(k):
        g = lerp(top, SI_BOTTOM, k)
        return seated(INC_HIP, INC, g, (g[0] - 4, g[1] - 2), 1, h=-160)
    return seq(f, PRESS_KS)


def smith_bench_frame(back_ang, back_len, x):
    def scene(doc, j, layer):
        if layer == "back":
            floor(doc, 190, 120)
            smith_frame(doc, x, top=20)
            kit.incline_bench(doc, 150, 206, 208, back_len, back_ang)
        else:
            smith_bar(doc, kit.grip(j), 22)
    return scene


SS_X = UP_SH[0] + 18  # bar in front of the face


def smith_shoulder_poses():
    bottom = (SS_X, UP_SH[1] - 22)
    top = reach_above(SS_X, UP_SH, 80)

    def f(k):
        g = lerp(bottom, top, k)
        return seated(UP_HIP, UP, g, (g[0] - 4, g[1] - 2), 1, h=-96)
    return seq(f, (0, 0.45, 1))


# ==== barbell floor press ==========================================================================

def bar_floor_poses():
    a = reach_above(FL_SH[0] + 8, FL_SH, 80)
    b = (FL_SH[0] + 26, FL_SH[1] - 30)

    def f(k):
        g = lerp(a, b, k)
        return supine(g, (g[0] - 3, g[1] - 1))
    return seq(f, PRESS_KS)


def bar_floor_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 210, 120)
        kit.mat(doc, 96, 320)
        kit.rack(doc, FL_SH[0] - 30, hook_y=FL_SH[1] - 74, safety_y=GROUND - 40, top=80)
    else:
        bar_end(doc, kit.grip(j), 22)


# ==== 3D helpers ===================================================================================

OBL = (0.22, 0.34)  # depth towards the viewer drawn as a slight down-right offset
OBL_FAR = (0.24, -0.04)  # depth away from the viewer: tucked behind the trunk


def proj(p2, v, k=1.0):
    """2D point p2 plus a 3D offset v = (x, y, z) projected (z towards the viewer)."""
    o = OBL if v[2] >= 0 else OBL_FAR
    return (p2[0] + (v[0] + o[0] * v[2]) * k, p2[1] + (v[1] + o[1] * v[2]) * k)


def unit3(v):
    n = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / n for c in v)


def custom(make_scene, poses, view, keys):
    """Renderer entry with a scene per frame: `make_scene(state)` closes over that frame's 3D arm state,
    eased between the start / middle / end `keys` like the poses (art.frames)."""
    def render(ex):
        frames = art.frames(poses)
        return [art.render(p, ex, make_scene(art.sample(keys, art.progress(i), art.lerp_num)), prefix=f"f{i}",
                           view=view, heat=art.glow(i)) for i, p in enumerate(frames)]
    return render


# ==== small 3D body model ==========================================================================
# World axes: X right, Y up (floor Y = 0), Z towards the camera. The camera is raised by `elev` degrees.

def v3add(*vs):
    return tuple(sum(c) for c in zip(*vs))


def v3mul(v, k):
    return tuple(c * k for c in v)


def v3sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def v3dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def v3len(v):
    return math.sqrt(v3dot(v, v))


def ik3(a, t, l1, l2, pole):
    """Elbow / knee of a two-link chain a→t, bent towards `pole`."""
    d = v3sub(t, a)
    dist = max(abs(l1 - l2) + 0.01, min(v3len(d), l1 + l2 - 0.01))
    u = unit3(d)
    x = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(0.0, l1 * l1 - x * x))
    pp = unit3(v3sub(pole, v3mul(u, v3dot(pole, u))))
    return v3add(a, v3mul(u, x), v3mul(pp, h))


class Cam:
    """Orthographic camera: turned `yaw` degrees about the vertical, raised `elev` degrees."""

    def __init__(self, elev, origin, yaw=0.0):
        self.c, self.s, self.o = math.cos(math.radians(elev)), math.sin(math.radians(elev)), origin
        self.yc, self.ys = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))

    def __call__(self, p):
        x, y, z = p
        x, z = x * self.yc - z * self.ys, x * self.ys + z * self.yc
        return (self.o[0] + x, self.o[1] - (y * self.c - z * self.s))

    def depth(self, p):
        x, y, z = p
        return x * self.ys + z * self.yc


def arm_chain(sh, upper, fore, hand=None):
    """Elbow, wrist, hand from unit directions."""
    e = v3add(sh, v3mul(upper, UPPER))
    w = v3add(e, v3mul(fore, FORE))
    return e, w, v3add(w, v3mul(hand or fore, HAND))


def apply3d(j, cam, J):
    for k, v in J.items():
        j[k] = cam(v)


def grip3(J, side="N"):
    return v3mul(v3add(J["wrist" + side], J["hand" + side]), 0.5)


def view_around(pts, m=14):
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs) - m, max(xs) + m, min(ys) - m, max(ys) + m
    w, h = x1 - x0, y1 - y0
    if w < h * 4 / 3:
        x0 -= (h * 4 / 3 - w) / 2
        w = h * 4 / 3
    else:
        y0 -= (w * 0.75 - h) / 2
    return (round(x0, 1), round(y0, 1), round(w, 1))


def dummy(front=True, corner_="tr"):
    return P(t=-90, front=front, pin=("hip", (200, 150)), inset=corner_)


def box3(doc, cam, x0, x1, y0, y1, z0, z1, stops=art.PAD):
    """Axis-aligned box: the faces turned towards the camera."""
    f = (cam.ys * cam.c, cam.s, cam.yc * cam.c)
    faces = [((0, 1, 0), [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (stops[0], stops[1])),
             ((0, 0, 1), [(x0, y1, z1), (x1, y1, z1), (x1, y0, z1), (x0, y0, z1)], (stops[1], stops[2])),
             ((0, 0, -1), [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)], (stops[1], stops[2])),
             ((1, 0, 0), [(x1, y1, z0), (x1, y1, z1), (x1, y0, z1), (x1, y0, z0)], (stops[1], stops[2])),
             ((-1, 0, 0), [(x0, y1, z0), (x0, y1, z1), (x0, y0, z1), (x0, y0, z0)], (stops[1], stops[2]))]
    for nrm, poly, st in faces:
        if v3dot(nrm, f) <= 0.02:
            continue
        g = doc.box_grad([(0, st[0]), (1, st[1])])
        doc.add(f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in (cam(p) for p in poly))}" fill="{g}" '
                f'stroke="#0A0B0D" stroke-width="0.8" stroke-linejoin="round"/>')


SH3 = SW  # shoulder half-width
HIP3 = 9.0


# ==== flat dumbbell fly: three-quarter view from the foot end, a little above ======================

FF_CAM = Cam(32, (200, GROUND - 30), 140)
FF_PAD = 54  # bench pad top


def flat_fly_body(theta, bend):
    y = FF_PAD + 17
    S, H = (0, y, 0), (0, y, -TORSO)
    J = {"shoulder": S, "hip": H, "neck": (0, y - 1, 10), "head": (0, y - 3, 25)}
    for side, s in (("N", 1), ("F", -1)):
        sh, hp = (s * SH3, y, 0), (s * HIP3, y, -TORSO)
        knee = v3add(hp, (s * 9, -14, -52))
        ank = v3add(knee, (s * 8, -53, -4))
        r, rb = math.radians(theta), math.radians(theta - bend)
        up = unit3((s * math.sin(r), math.cos(r), -0.06))
        fo = unit3((s * math.sin(rb), math.cos(rb), -0.08))
        e, w, h = arm_chain(sh, up, fo)
        J.update({"shoulder" + side: sh, "hip" + side: hp, "knee" + side: knee, "ankle" + side: ank,
                  "toe" + side: v3add(ank, (s * 2, -3, -13)), "elbow" + side: e, "wrist" + side: w, "hand" + side: h})
    return J


def shadow3(doc, cam, c, rx, rz):
    pts = [cam((c[0] + rx * math.cos(a / 12 * math.pi), 0, c[2] + rz * math.sin(a / 12 * math.pi))) for a in range(24)]
    doc.add(f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in pts)}" fill="#000" fill-opacity="0.13"/>')


def flat_bench3(doc, cam):
    # Shadow, legs (near and far end), frame rail, pad.
    shadow3(doc, cam, (0, 0, -50), 56, 96)
    for z in (22, -100):
        art.tube(doc, cam((0, FF_PAD - 12, z)), cam((0, 2, z)), 7, "butt")
        art.tube(doc, cam((-22, 2, z)), cam((22, 2, z)), 6)
    box3(doc, cam, -16, 16, FF_PAD - 12, FF_PAD, -112, 36)


def flat_fly_scene(theta, bend):
    J = flat_fly_body(theta, bend)

    def scene(doc, j, layer):
        if layer == "back":
            apply3d(j, FF_CAM, J)
            flat_bench3(doc, FF_CAM)
        else:
            for s in "FN":
                art.db_end(doc, FF_CAM(grip3(J, s)), 9)
    return scene


FLY_FRAMES = ((4, 6), (50, 16), (94, 22))


def flat_fly_entry():
    poses = [dummy(True, "tr")] * 3
    pts = []
    for th, b in FLY_FRAMES:
        J = flat_fly_body(th, b)
        pts += [FF_CAM(v) for v in J.values()]
    pts += [FF_CAM((-70, 0, -50)), FF_CAM((70, 0, -50)), FF_CAM((0, 0, 60)), FF_CAM((0, 0, -160))]
    view = view_around(pts, 16)
    return custom(lambda k: flat_fly_scene(*k), poses, view, FLY_FRAMES)


# ==== incline dumbbell fly: same camera, backrest at 30 degrees ===================================

IF_CAM = Cam(28, (200, GROUND - 30), 140)
IF_SEAT = 58
IF_A = math.radians(30)  # backrest angle above horizontal


def incline_fly_body(theta, bend):
    d = (0, math.sin(IF_A), math.cos(IF_A))  # hip → shoulder
    n = (0, math.cos(IF_A), -math.sin(IF_A))  # out of the chest
    H = (0, IF_SEAT + 16, 0)
    S = v3add(H, v3mul(d, TORSO))
    J = {"shoulder": S, "hip": H, "neck": v3add(S, v3mul(d, 9), v3mul(n, 1)), "head": v3add(S, v3mul(d, 24), v3mul(n, 2))}
    for side, s in (("N", 1), ("F", -1)):
        sh, hp = v3add(S, (s * SH3, 0, 0)), (s * HIP3, H[1], 0)
        knee = v3add(hp, (s * 10, -4, -54))
        ank = v3add(knee, (s * 6, -51, 16))
        r, rb = math.radians(theta), math.radians(theta - bend)
        up = unit3(v3add(v3mul((s, 0, 0), math.sin(r)), v3mul(n, math.cos(r)), v3mul(d, -0.08)))
        fo = unit3(v3add(v3mul((s, 0, 0), math.sin(rb)), v3mul(n, math.cos(rb)), v3mul(d, -0.12)))
        e, w, h = arm_chain(sh, up, fo)
        J.update({"shoulder" + side: sh, "hip" + side: hp, "knee" + side: knee, "ankle" + side: ank,
                  "toe" + side: v3add(ank, (s * 3, -2, -13)), "elbow" + side: e, "wrist" + side: w, "hand" + side: h})
    return J


def incline_bench3(doc, cam):
    d = (0, math.sin(IF_A), math.cos(IF_A))
    n = (0, math.cos(IF_A), -math.sin(IF_A))
    shadow3(doc, cam, (0, 0, 20), 56, 96)
    base = (0, IF_SEAT, 8)
    top = v3add(base, v3mul(d, 112))
    # Backrest support, seat post, floor rails.
    art.tube(doc, cam(v3add(base, v3mul(d, 60), v3mul(n, -14))), cam((0, 2, 84)), 7)
    art.tube(doc, cam((0, IF_SEAT - 12, -8)), cam((0, 2, -8)), 8, "butt")
    art.tube(doc, cam((0, 2, 84)), cam((0, 2, -24)), 6)
    art.tube(doc, cam((-24, 2, 84)), cam((24, 2, 84)), 6)
    art.tube(doc, cam((-24, 2, -24)), cam((24, 2, -24)), 6)
    # Backrest pad (its face towards the lifter) and the seat.
    lo, hi = v3add(base, v3mul(n, -1)), v3add(top, v3mul(n, -1))
    face = [v3add(lo, (-18, 0, 0)), v3add(lo, (18, 0, 0)), v3add(hi, (18, 0, 0)), v3add(hi, (-18, 0, 0))]
    g = doc.box_grad([(0, art.PAD[0]), (0.5, art.PAD[1]), (1, art.PAD[2])], vertical=False)
    doc.add(f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in (cam(p) for p in face))}" fill="{g}" '
            f'stroke="#0A0B0D" stroke-width="0.9" stroke-linejoin="round"/>')
    box3(doc, cam, -18, 18, IF_SEAT - 12, IF_SEAT, -30, 10)


def incline_fly_scene(theta, bend):
    J = incline_fly_body(theta, bend)

    def scene(doc, j, layer):
        if layer == "back":
            apply3d(j, IF_CAM, J)
            incline_bench3(doc, IF_CAM)
        else:
            for s in "FN":
                art.db_end(doc, IF_CAM(grip3(J, s)), 9)
    return scene


def incline_fly_entry():
    poses = [dummy(True, "tr")] * 3
    pts = []
    for th, b in FLY_FRAMES:
        J = incline_fly_body(th, b)
        pts += [IF_CAM(v) for v in J.values()]
    pts += [IF_CAM((-60, 0, -70)), IF_CAM((60, 0, 110)), IF_CAM((0, IF_SEAT + 60, 110))]
    view = view_around(pts, 16)
    return custom(lambda k: incline_fly_scene(*k), poses, view, FLY_FRAMES)


# ==== cable flyes from low / high pulleys ==========================================================

CFV_L, CFV_R = 76, 324


def cable_fly_var_poses(py, end_dy, ks=(0, 0.55, 1)):
    shn, shf = fr_sh()
    pn, pf = (CFV_R - 12, py), (CFV_L + 12, py)
    a_n = art.add(shn, art.norm(art.sub(pn, shn)), 78)
    a_f = art.add(shf, art.norm(art.sub(pf, shf)), 78)
    mid = (FR_HIP[0], shn[1] + end_dy)
    out = []
    for k in ks:
        gn = lerp(a_n, (mid[0] + 5, mid[1]), k)
        gf = lerp(a_f, (mid[0] - 5, mid[1]), k)
        if 0 < k < 1:
            gn = art.add(shn, art.norm(art.sub(gn, shn)), 74)
            gf = art.add(shf, art.norm(art.sub(gf, shf)), 74)
        out.append(B(FR_HIP, -90, front=True, aN=G(gn, 1), aF=G(gf, -1), lN=(80, 92, 12), lF=(100, 88, 168)))
    return out


def cable_fly_var_scene(py):
    def scene(doc, j, layer):
        gn, gf = kit.grip(j), kit.grip(j, "F")
        pn, pf = (CFV_R - 12, py), (CFV_L + 12, py)
        if layer == "back":
            floor(doc, 200, 150)
            tower(doc, CFV_R, py, max(0, (kit.dist(gn, pn) - 78) * 0.3), "L")
            tower(doc, CFV_L, py, max(0, (kit.dist(gf, pf) - 78) * 0.3), "R")
        else:
            art.cable(doc, [gn, art.add(pn, (-5, 0))])
            art.cable(doc, [gf, art.add(pf, (5, 0))])
            kit.handle(doc, gn)
            kit.handle(doc, gf)
    return scene


LOW_PY, HIGH_PY = GROUND - 26, 44
CFV_BOXES = [(CFV_L - 48, 10, CFV_L + 18, GROUND), (CFV_R - 18, 10, CFV_R + 48, GROUND)]


# ==== push-up family ===============================================================================

def solve(make, joint, y, lo, hi, n=44):
    """Bisect the free parameter of make(v) so that `joint` lands at height y (y grows with v)."""
    for _ in range(n):
        m = (lo + hi) / 2
        if art.F.place(make(m))[joint][1] < y:
            hi = m
        else:
            lo = m
    return make((lo + hi) / 2)


IP_TOP = BENCH_TOP + 8  # bench pad top
IP_W = (176, IP_TOP - 5)


def incline_push_poses():
    return [rigid_plank((92, 92), IP_W, lo=-70, hi=0), rigid_plank((140, 62), IP_W, lo=-70, hi=0),
            rigid_plank((176, 46), IP_W, lo=-70, hi=0)]


def incline_push_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 140)
        kit.flat_bench(doc, IP_W[0] - 8, IP_W[0] + 140, IP_TOP)


KP_W = (262, GROUND - 5)
KP_KNEE_Y = GROUND - 8


def knee_plank(arm):
    def make(t):
        return P(t=t, h=t, lN=(t + 180, 200, 200), lF=(t + 181, 202, 202), aN=arm, aF=arm, pin=("wristN", KP_W))
    return solve(make, "kneeN", KP_KNEE_Y, -70, 10)


def knee_push_poses():
    return [knee_plank((90, 90)), knee_plank((138, 66)), knee_plank((178, 50))]


DP_TOP = GROUND - 56  # box / bench top under the feet
DP_W = (290, GROUND - 5)


def decline_push_poses():
    return [rigid_plank(a, DP_W, toe_y=DP_TOP - 1, foot=60, lo=-40, hi=40) for a in ((86, 86), (132, 66), (166, 52))]


DP_TOE_X = art.F.place(decline_push_poses()[0])["toeN"][0]


def decline_push_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 150)
        kit.flat_bench(doc, DP_TOE_X - 126, DP_TOE_X + 16, DP_TOP)


# ==== bench dip ====================================================================================

BD_X1 = 168  # bench front edge
BD_TOP = BENCH_TOP + 4
BD_GRIP = (BD_X1 - 5, BD_TOP - 4)


def bench_dip_poses():
    out = []
    for drop, t in ((0, -93), (22, -92), (40, -90)):
        sh = (BD_GRIP[0] + 20, BD_GRIP[1] - 77 + drop)
        hip = art.ang_pt(sh, t + 180, TORSO)
        out.append(B(hip, t, aN=G(BD_GRIP, 1), aF=G((BD_GRIP[0] - 3, BD_GRIP[1] - 1), 1), h=t + 4,
                     lN=G((BD_X1 + 92, FLOOR_Y), -1, end=0), lF=G((BD_X1 + 86, FLOOR_Y), -1, end=0)))
    return out


def bench_dip_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 170, 130)
        kit.flat_bench(doc, BD_X1 - 150, BD_X1, BD_TOP)


# ==== single-arm presses ===========================================================================

def sa_press_poses():
    """Front view: one dumbbell from the shoulder to lockout, free hand on the hip."""
    shn, shf = fr_sh()
    hip_f = (FR_HIP[0] - 15, FR_HIP[1] + 2)
    gs = [(shn[0] + 12, shn[1] - 20), (shn[0] + 8, shn[1] - 52), (shn[0] + 1, shn[1] - 80)]
    return [B(FR_HIP, -90, front=True, aN=G(g, 1), aF=G(hip_f, 1, wrist=True), lit_sides="N", **FR_LEGS) for g in gs]


def sa_press_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 50)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


def kb_press_poses():
    """Side view: bell from the rack to lockout by the ear, the other arm relaxed."""
    sh = art.ang_pt(ST_HIP, -90, TORSO)
    a, b = (sh[0] + 14, sh[1] - 4), (sh[0] - 2, sh[1] - 81)
    out = []
    for k in (0, 0.45, 1):
        g = lerp(a, b, k)
        out.append(standing(ST_HIP, -90, g, (sh[0] + 2, sh[1] + 78), 1, stance=(1, -3), h=-96 if k < 0.9 else -88,
                            lit_sides="N"))
    return out


def kb_press_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 50)
    else:
        w, h = j["wristN"], j["handN"]
        fore = art.norm(art.sub(w, j["elbowN"]))
        c = kit.grip(j)
        # Bell rests on the back of the forearm: hangs behind the wrist, away from the palm.
        back = (fore[1], -fore[0])
        bell = art.add(art.add(c, fore, -12), back, 9)
        ang = math.degrees(math.atan2(bell[1] - c[1], bell[0] - c[0]))
        doc.add(f'<g transform="rotate({ang - 90:.1f} {c[0]:.1f} {c[1]:.1f})">')
        kit.kettlebell(doc, c, r=11)
        doc.add("</g>")
        del h


# ==== Z press: seated on the floor, legs straight ==================================================

ZP_HIP = (176, GROUND - 14)
ZP_SH = art.ang_pt(ZP_HIP, -90, TORSO)
ZP_LEGS = dict(lN=(-1, 1, -80), lF=(1, 1, -78))


def z_press_poses():
    a, b = (ZP_SH[0] + 18, ZP_SH[1] - 4), (ZP_SH[0] - 2, ZP_SH[1] - 81)

    def f(k):
        g = lerp(a, b, k)
        return B(ZP_HIP, -90, aN=G(g, 1), aF=G((g[0] - 4, g[1] - 2), 1), h=-96 if k < 0.9 else -88, **ZP_LEGS)
    return seq(f, (0, 0.45, 1))


def z_press_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 220, 120)
        kit.mat(doc, 120, 320)
        kit.rack(doc, ZP_SH[0] - 44, hook_y=ZP_SH[1] - 2, safety_y=None, top=int(ZP_SH[1] - 60))
    else:
        bar_end(doc, kit.grip(j), 20)


# ==== wall handstand push-up =======================================================================

HS_WALL = 262  # wall face
HS_W = (HS_WALL - 34, GROUND - 5)  # wrists on the mat


def hspu_poses():
    out = []
    for k in (0, 0.5, 1):
        # Shoulders sink and drift forward (away from the wall) as the head goes to the mat.
        sh = (HS_W[0] + 2 - 12 * k, HS_W[1] - 80 + 52 * k)
        # One line from the shoulders to the heels on the wall (hip → shoulder points down).
        t = 90 + math.degrees(math.atan2(HS_WALL - 7 - sh[0], TORSO + THIGH + SHIN)) - 3
        hip = art.ang_pt(sh, t + 180, TORSO)
        # Legs lean back so the heels rest on the wall.
        legs = -90 + math.degrees(math.asin(max(-1, min(1, (HS_WALL - 7 - hip[0]) / (THIGH + SHIN)))))
        out.append(B(hip, t, aN=G(HS_W, -1, end=180, wrist=True), aF=G((HS_W[0] + 3, HS_W[1]), -1, end=180, wrist=True),
                     lN=(legs, legs - 2, legs - 70), lF=(legs + 2, legs, legs - 68), h=t - 14 * k))
    return out


def hspu_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 220, 70)
        kit.wall(doc, HS_WALL, 16, top=-120)
        kit.mat(doc, HS_W[0] - 70, HS_WALL - 2)


# ==== front raises =================================================================================

def front_raise_poses(far=True):
    out = []
    for a in (88, 40, -12):
        aN = (a, a - 4)
        aF = (a + 2, a - 2) if far else (92, 88)
        out.append(P(t=-90, h=-92, aN=aN, aF=aF, lF=(92, 88, 0), pin=("ankleN", (200, GROUND - 4)),
                     lit_sides="NF" if far else "N"))
    return out


def db_front_raise_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 40)
        kit.dumbbell(doc, kit.grip(j, "F"), r=9)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


CFR_TOWER = 96
CFR_PULLEY = (CFR_TOWER + 12, GROUND - 16)


def cable_front_raise_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor(doc, 170, 110)
        lift = max(0, (kit.dist(g, CFR_PULLEY) - 100) * 0.3)
        tower(doc, CFR_TOWER, CFR_PULLEY[1], lift, side="R")
        art.cable(doc, [art.add(CFR_PULLEY, (5, 0)), (j["ankleF"][0] + 6, GROUND - 14), g])
    else:
        kit.handle(doc, g)


# ==== lateral-raise variations (back view) =========================================================

SL_HIP = (200, FLOOR_Y - round(THIGH * math.sin(math.radians(24)) + SHIN * math.sin(math.radians(92)), 1))
SL_SEAT = SL_HIP[1] + 14


def seated_lateral_poses():
    legs = PD_LEGS
    arms = (((84, 88), (96, 92)), ((40, 46), (140, 134)), ((-2, 8), (182, 172)))
    return [B(SL_HIP, -90, front="back", aN=a, aF=b, **legs) for a, b in arms]


def seated_lateral_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 70)
        # Flat bench seen end-on under the hips.
        art.tube(doc, (SL_HIP[0], SL_SEAT + 12), (SL_HIP[0], GROUND - 2), 10, "butt")
        kit.feet(doc, SL_HIP[0] - 34, SL_HIP[0] + 34)
        g = doc.box_grad([(0, art.PAD[0]), (0.3, art.PAD[1]), (1, art.PAD[2])])
        doc.add(f'<rect x="{SL_HIP[0] - 24}" y="{SL_SEAT}" width="48" height="13" rx="5" fill="{g}" '
                f'stroke="#0A0B0D" stroke-width="0.9"/>')
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)
        kit.dumbbell(doc, kit.grip(j, "F"), r=10)


LA_POST = 112
LA_ANK = 152
LA_T = -77  # lean away from the post
LA_HIP = art.ang_pt((LA_ANK, FLOOR_Y), LA_T, THIGH + SHIN - 2)
LA_GRIP = (LA_POST + 8, art.ang_pt(LA_HIP, LA_T, TORSO)[1] + 36)


def lean_away_poses():
    a = deg(art.sub((LA_ANK, FLOOR_Y), LA_HIP))
    legs = dict(lN=(a, a, 8), lF=(a, a, 172))
    out = []
    for a in ((90, 92), (44, 48), (-6, 2)):
        out.append(B(LA_HIP, LA_T, front="back", aN=a, aF=G(LA_GRIP, 1), h=LA_T - 8, lit_sides="N", **legs))
    return out


def lean_away_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 170, 80)
        kit.post(doc, LA_POST, 30)
    else:
        kit.dumbbell(doc, kit.grip(j), r=10)


def band_lateral_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 60)
    else:
        for s in "NF":
            g = kit.grip(j, s)
            foot = (j["ankle" + s][0] + (3 if s == "N" else -3), GROUND - 2)
            kit.band(doc, foot, g)
            kit.handle(doc, g)


def band_lateral_poses():
    return [P(t=-90, front="back", aN=(84, 86), aF=(96, 94), pin=("hip", FR_HIP), **FR_LEGS),
            P(t=-90, front="back", aN=(40, 48), aF=(140, 132), pin=("hip", FR_HIP), **FR_LEGS),
            P(t=-90, front="back", aN=(-2, 8), aF=(182, 172), pin=("hip", FR_HIP), **FR_LEGS)]


# ==== cable Y-raise / rear-delt fly: two towers, cables crossed ====================================

XT_L, XT_R = 70, 330


def cross_scene(py, handle="d"):
    def scene(doc, j, layer):
        gn, gf = kit.grip(j), kit.grip(j, "F")
        pl, pr = (XT_L + 12, py), (XT_R - 12, py)
        if layer == "back":
            floor(doc, 200, 150)
            tower(doc, XT_R, py, max(0, (kit.dist(gf, pr) - 120) * 0.25), "L")
            tower(doc, XT_L, py, max(0, (kit.dist(gn, pl) - 120) * 0.25), "R")
            # Crossed: the right hand holds the left cable and vice versa (the cables run in front of the body).
            art.cable(doc, [art.add(pl, (5, 0)), gn])
            art.cable(doc, [art.add(pr, (-5, 0)), gf])
        else:
            kit.handle(doc, gn, handle)
            kit.handle(doc, gf, handle)
    return scene


def y_raise_poses():
    arms = (((112, 108), (68, 72)), ((20, 14), (160, 166)), ((-48, -52), (-132, -128)))
    return [P(t=-90, front="back", aN=a, aF=b, pin=("hip", FR_HIP), **FR_LEGS) for a, b in arms]


RD_FRAMES = ((-16, 8), (40, 14), (88, 10))  # (arm angle from straight ahead towards the side, elbow bend)


def rear_delt_arms(j, phi, bend):
    """Back view: arms in the horizontal plane at shoulder height; straight ahead (away from the viewer)
    reads slightly higher, the camera being a little above the shoulders."""
    for side, s in (("N", 1), ("F", -1)):
        def d(a):
            r = math.radians(a)
            return (s * math.sin(r), -0.28 * math.cos(r) + 0.06, 0)
        sh = j["shoulder" + side]
        e = proj(sh, d(phi), UPPER)
        w = proj(e, d(phi - bend), FORE)
        j["elbow" + side], j["wrist" + side], j["hand" + side] = e, w, proj(w, d(phi - bend), HAND)


def rear_delt_entry():
    py = fr_sh()[0][1] + 4
    base = cross_scene(py)
    poses, view = fit([P(t=-90, front="back", aN=(0, 0), aF=(180, 180), pin=("hip", FR_HIP), **FR_LEGS)] * 3,
                      [(XT_L - 48, 10, XT_L + 18, GROUND), (XT_R - 18, 10, XT_R + 48, GROUND)])

    def make(k):
        def scene(doc, j, layer):
            if layer == "back":
                rear_delt_arms(j, *k)
            base(doc, j, layer)
        return scene
    return custom(make, poses, view, RD_FRAMES)


# ==== cable upright row (front view, low pulley in front of the feet) ==============================

def upright_row_poses():
    shn, shf = fr_sh()
    out = []
    for k in (0, 0.5, 1):
        y = lerp((0, FR_HIP[1] + 8), (0, shn[1] + 16), k)[1]
        dx = 22 - 8 * k
        gn, gf = (FR_HIP[0] + dx, y), (FR_HIP[0] - dx, y)
        out.append(B(FR_HIP, -90, front=True, aN=G(gn, -1), aF=G(gf, 1), lN=(80, 92, 12), lF=(100, 88, 168)))
    return out


UR_PULLEY = (FR_HIP[0], GROUND - 8)


def upright_row_scene(doc, j, layer):
    gn, gf = kit.grip(j), kit.grip(j, "F")
    if layer == "back":
        floor(doc, 200, 60)
    else:
        mid = lerp(gn, gf, 0.5)
        art.cable(doc, [mid, UR_PULLEY])
        art.tube(doc, (gf[0] - 8, gf[1]), (gn[0] + 8, gn[1]), 5)
        doc.add(f'<rect x="{UR_PULLEY[0] - 13}" y="{GROUND - 5}" width="26" height="6" rx="2" fill="#2A2E34" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')
        art.pulley(doc, UR_PULLEY, 6)


# ==== chest-supported reverse fly: 3/4 rear view of the incline bench ==============================

def hull(pts):
    pts = sorted(set((round(x, 2), round(y, 2)) for x, y in pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def slab(doc, cam, c, axes, half):
    """Oriented pad (box centre c, unit axes, half sizes) drawn as its projected silhouette."""
    corners = []
    for i in (-1, 1):
        for k in (-1, 1):
            for m in (-1, 1):
                corners.append(cam(v3add(c, v3mul(axes[0], i * half[0]), v3mul(axes[1], k * half[1]),
                                         v3mul(axes[2], m * half[2]))))
    h = hull(corners)
    g = doc.box_grad([(0, art.PAD[0]), (0.35, art.PAD[1]), (1, art.PAD[2])])
    doc.add(f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in h)}" fill="{g}" stroke="#0A0B0D" '
            f'stroke-width="0.9" stroke-linejoin="round"/>')


RF_CAM = Cam(24, (200, GROUND - 6), 128)
RF_A = math.radians(42)  # pad incline
RF_D = (0, math.sin(RF_A), math.cos(RF_A))      # hip → shoulder (figure faces +Z)
RF_N = (0, -math.cos(RF_A), math.sin(RF_A))     # out of the chest, into the pad
RF_HIP = (0, 100, 0)


def rear_fly_body(theta, bend):
    S = v3add(RF_HIP, v3mul(RF_D, TORSO))
    hd = unit3(v3add(RF_D, v3mul(RF_N, 0.5)))
    J = {"shoulder": S, "hip": RF_HIP, "neck": v3add(S, v3mul(hd, 10)), "head": v3add(S, v3mul(hd, 25))}
    for side, s in (("N", 1), ("F", -1)):
        sh, hp = v3add(S, (s * SH3, 0, 0)), v3add(RF_HIP, (s * HIP3, 0, 0))
        ank = (s * 11, 6, -34)
        knee = ik3(hp, ank, THIGH, SHIN, (0, 0, 1))
        r, rb = math.radians(theta), math.radians(theta + bend)
        up = unit3((s * math.sin(r), -math.cos(r), 0.06))
        fo = unit3((s * math.sin(rb) * 0.94, -math.cos(rb), 0.18))
        e, w, h = arm_chain(sh, up, fo)
        J.update({"shoulder" + side: sh, "hip" + side: hp, "knee" + side: knee, "ankle" + side: ank,
                  "toe" + side: v3add(ank, (0, -5, 13)), "elbow" + side: e, "wrist" + side: w, "hand" + side: h})
    return J


def rear_fly_bench(doc, cam):
    shadow3(doc, cam, (0, 0, 20), 60, 80)
    # Pad: under the chest, its long axis along the torso.
    c = v3add(RF_HIP, v3mul(RF_D, 46), v3mul(RF_N, 22))
    seat_post = v3add(RF_HIP, v3mul(RF_D, 30), v3mul(RF_N, 30))
    art.tube(doc, cam(seat_post), cam((0, 2, seat_post[2])), 8, "butt")
    art.tube(doc, cam(v3add(RF_HIP, v3mul(RF_D, 70), v3mul(RF_N, 30))), cam((0, 2, 96)), 6)
    art.tube(doc, cam((0, 2, 96)), cam((0, 2, seat_post[2] - 26)), 6)
    art.tube(doc, cam((-24, 2, 96)), cam((24, 2, 96)), 6)
    art.tube(doc, cam((-24, 2, seat_post[2] - 26)), cam((24, 2, seat_post[2] - 26)), 6)
    slab(doc, cam, c, ((1, 0, 0), RF_D, RF_N), (17, 56, 6))


RF_FRAMES = ((4, 8), (46, 14), (88, 18))


def rear_fly_scene(theta, bend):
    J = rear_fly_body(theta, bend)

    def scene(doc, j, layer):
        if layer == "back":
            rear_fly_bench(doc, RF_CAM)
            apply3d(j, RF_CAM, J)
            kit.dumbbell(doc, RF_CAM(grip3(J, "F")), r=8)
        else:
            kit.dumbbell(doc, RF_CAM(grip3(J, "N")), r=9)
    return scene


def rear_fly_entry():
    pts = []
    for th, b in RF_FRAMES:
        pts += [RF_CAM(v) for v in rear_fly_body(th, b).values()]
    pts += [RF_CAM((0, 2, 96)), RF_CAM((0, 0, -40)), RF_CAM(v3add(RF_HIP, v3mul(RF_D, 104), v3mul(RF_N, 22)))]
    return custom(lambda k: rear_fly_scene(*k), [dummy("back", "tr")] * 3, view_around(pts, 18), RF_FRAMES)


# ==== archer push-up: seen from in front of the head, a little above ==============================

AR_CAM = Cam(35, (200, GROUND - 6), 55)
AR_HAND_X = 64
AR_FEET_Z = -196


def archer_body(cx):
    """Shoulders shifted cx towards the near (bending) hand; the far arm stays straight."""
    # Far arm straight from its shoulder to the far hand fixes the shoulder height.
    dx = AR_HAND_X + cx - SH3
    sy = math.sqrt(max(0.0, ARM * ARM - dx * dx - 16)) + 3
    S = (cx, sy, 0)
    feet = (0, 8, AR_FEET_Z)
    d = unit3(v3sub(feet, S))  # shoulder → feet
    H = v3add(S, v3mul(d, TORSO))
    hd = unit3((0, -0.25, 1))
    J = {"shoulder": S, "hip": H, "neck": v3add(S, v3mul(hd, 10)), "head": v3add(S, v3mul(hd, 25))}
    for side, s in (("N", 1), ("F", -1)):
        sh, hp = v3add(S, (s * SH3, 0, 0)), v3add(H, (s * HIP3, 0, 0))
        ank = (s * 9, 8, AR_FEET_Z)
        knee = v3add(hp, v3mul(unit3(v3sub(ank, hp)), THIGH))
        hand_c = (s * AR_HAND_X, 5, 6)
        w = v3add(hand_c, (0, 0, -4))
        el = ik3(sh, w, UPPER, FORE, (s * 0.7, 0.2, -0.7))
        J.update({"shoulder" + side: sh, "hip" + side: hp, "knee" + side: knee, "ankle" + side: ank,
                  "toe" + side: v3add(ank, (0, -6, 10)), "elbow" + side: el, "wrist" + side: w,
                  "hand" + side: v3add(w, (s * 1, -3, 9))})
    return J


AR_FRAMES = (0, 18, 34)


def archer_scene(cx):
    J = archer_body(cx)

    def scene(doc, j, layer):
        if layer == "back":
            cam = AR_CAM
            g = doc.box_grad([(0, "#2E6E8E"), (1, "#24566F")])
            mat = [(-92, 0, 46), (92, 0, 46), (60, 0, -230), (-60, 0, -230)]
            doc.add(f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in (cam(p) for p in mat))}" fill="{g}" '
                    f'stroke="#0A0B0D" stroke-opacity="0.5" stroke-width="0.7"/>')
            shadow3(doc, cam, (cx * 0.5, 0, -90), 56, 120)
            apply3d(j, cam, J)
    return scene


def archer_entry():
    pts = []
    for cx in AR_FRAMES:
        pts += [AR_CAM(v) for v in archer_body(cx).values()]
    pts += [AR_CAM((-92, 0, 46)), AR_CAM((92, 0, 46))]
    return custom(archer_scene, [dummy("back", "br")] * 3, view_around(pts, 10), AR_FRAMES)


SCENES = {
    "decline-bench-press": S(decline_scene, decline_poses(), [(DEC_SH[0] - 62, DEC_SH[1] - 108, DEC_ANK[0] + 40, GROUND)],
                             held_at("N", 24)),
    "smith-bench-press": S(smith_bench_scene, smith_bench_poses(), [BENCH, (SB_X - 96, 10, SB_X + 96, GROUND)],
                           held_at("N", 24)),
    "smith-incline-press": S(smith_bench_frame(INC, 100, SI_X), smith_incline_poses(),
                             [(60, 160, 210, GROUND), (SI_X - 96, 10, SI_X + 96, GROUND)], held_at("N", 23)),
    "smith-shoulder-press": S(smith_bench_frame(UP, 110, SS_X), smith_shoulder_poses(),
                              [(100, 100, 210, GROUND), (SS_X - 96, 10, SS_X + 96, GROUND)], held_at("N", 23)),
    "db-fly": flat_fly_entry(),
    "incline-db-fly": incline_fly_entry(),
    "low-high-cable-fly": S(cable_fly_var_scene(LOW_PY), cable_fly_var_poses(LOW_PY, 14), CFV_BOXES),
    "high-low-cable-fly": S(cable_fly_var_scene(HIGH_PY), cable_fly_var_poses(HIGH_PY, 74), CFV_BOXES),
    "incline-push-up": S(incline_push_scene, incline_push_poses(), [(IP_W[0] - 10, IP_TOP, IP_W[0] + 140, GROUND)]),
    "knee-push-up": S(mat_scene(70, 300), knee_push_poses(), [(70, GROUND - 6, 300, GROUND)]),
    "decline-push-up": S(decline_push_scene, decline_push_poses(), [(DP_TOE_X - 110, DP_TOP, DP_TOE_X + 18, GROUND)]),
    "archer-push-up": archer_entry(),
    "bench-dip": S(bench_dip_scene, bench_dip_poses(), [(BD_X1 - 70, BD_TOP, BD_X1 + 4, GROUND)]),
    "single-arm-db-press": S(sa_press_scene, sa_press_poses(), [], held_at("N", 11)),
    "kb-press": S(kb_press_scene, kb_press_poses(), [], held_at("N", 22)),
    "z-press": S(z_press_scene, z_press_poses(), [(ZP_SH[0] - 80, ZP_SH[1] - 60, 320, GROUND)], held_at("N", 20)),
    "wall-hspu": S(hspu_scene, hspu_poses(), [(HS_W[0] - 70, GROUND - 6, HS_WALL + 16, GROUND)]),
    "db-front-raise": S(db_front_raise_scene, front_raise_poses(), [], both(held_at("N", 11), held_at("F", 11))),
    "cable-front-raise": S(cable_front_raise_scene, front_raise_poses(False), [tower_box(CFR_TOWER, "R")],
                           along(grip_n, CFR_PULLEY)),
    "seated-lateral-raise": S(seated_lateral_scene, seated_lateral_poses(), [(SL_HIP[0] - 36, SL_SEAT, SL_HIP[0] + 36, GROUND)],
                              both(held_at("N", 11), held_at("F", 11))),
    "lean-away-lateral-raise": S(lean_away_scene, lean_away_poses(), [(LA_POST - 26, 20, LA_POST + 26, GROUND)],
                                 held_at("N", 11)),
    "band-lateral-raise": S(band_lateral_scene, band_lateral_poses(), [], both(held_at("N", 8), held_at("F", 8))),
    "cable-y-raise": S(cross_scene(GROUND - 26), y_raise_poses(),
                       [(XT_L - 48, 10, XT_L + 18, GROUND), (XT_R - 18, 10, XT_R + 48, GROUND)]),
    "cable-rear-delt-fly": rear_delt_entry(),
    "cable-upright-row": S(upright_row_scene, upright_row_poses(), [(170, GROUND - 8, 230, GROUND)]),
    "incline-reverse-fly": rear_fly_entry(),
    "barbell-floor-press": S(bar_floor_scene, bar_floor_poses(), [(96, GROUND - 6, 320, GROUND),
                                                                  (FL_SH[0] - 66, 80, FL_SH[0] + 6, GROUND)],
                             held_at("N", 23)),
}
