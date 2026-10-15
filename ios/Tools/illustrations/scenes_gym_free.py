"""Scenes for the gym app comparison (#182): free-weight and bodyweight additions.

Thrusters, overhead squats, upright rows / high pulls, man maker, kettlebell windmill / halo, sit-ups, wall sit,
bear crawl, donkey kick, frog pump and deficit push-up. Built on the existing solvers: body() of scenes_lower
(hip pinned, ankles / hands solved onto absolute targets), B() of scenes_power, the floor helpers rest() /
reach() of scenes_mobility and the front-view helpers of scenes_upper. Views are fitted with scenes_power.fit().
Angles as in poses.py (0 = right, 90 = down; the figure faces right).
"""
import math

import art
import kit
import scenes_mobility as MO
import scenes_power as PW
from art import GROUND
from poses import P
from scenes_arms_core import CURL_CH, channel, foreshorten_trunk
import scenes_lower as L
from scenes_lower import ANK, bar_end, body, floor, grip, rack_arm, shoulder, tframe
from scenes_power import fit
from scenes_var_lower import bar_front, hand_dots, kb_rack, mid, sumo_k

F = art.F
MAT = MO.MAT
FOOT_Y = GROUND - 4
SCENES = {}


def bar_box(r=26, side="N"):
    """fit() box for a weight of radius r at the hand."""
    def f(j):
        c = grip(j, side)
        return [(c[0] - r, c[1] - r, c[0] + r, c[1] + r)]
    return f


def overhead(j, side="N", above=24):
    return grip(j, side)[1] < j["shoulder"][1] - above


# ==== thrusters: front squat to full depth, drive up and press in one move ===========================

TH_X = 200


def thr_bottom(arms):
    hip, t = (172, 216), -72
    return body(hip, t, h=-78, ankN=(TH_X, ANK), ankF=(TH_X - 4, ANK), **arms(hip, t, 0))


def thr_drive(arms):
    hip, t = (192, 172), -84
    return body(hip, t, h=-84, ankN=(TH_X, ANK), ankF=(TH_X - 4, ANK), **arms(hip, t, 1))


def thr_top(arms):
    hip, t = (198, 152), -90
    return body(hip, t, h=-88, ankN=(TH_X, ANK), ankF=(TH_X - 4, ANK), **arms(hip, t, 2))


def thr_frames(arms):
    return [thr_bottom(arms), thr_drive(arms), thr_top(arms)]


def bar_arms(hip, t, stage):
    s = shoulder(hip, t)
    if stage == 0:
        return dict(aN=rack_arm(hip, t), aF=rack_arm(hip, t, -10, 3))
    g = (s[0] + 10, s[1] - 42) if stage == 1 else (s[0] - 2, s[1] - 81)
    return dict(gN=g, gF=(g[0] - 4, g[1] - 2), eN=1, eF=1)


def front_rack_bar(j):
    td, n = kit.torso_frame(j)
    s = j["shoulder"]
    return (s[0] + n[0] * 13 - td[0] * 3, s[1] + n[1] * 13 - td[1] * 3)


def bar_thruster_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 100)
        kit.rack(doc, 104, hook_y=84, safety_y=196)
    else:
        bar_end(doc, grip(j) if overhead(j) else front_rack_bar(j), 22)


def db_arms(hip, t, stage):
    s = shoulder(hip, t)
    td, n = tframe(t)
    if stage == 0:
        g = art.add(art.add(s, n, 13), td, -8)
    elif stage == 1:
        g = (s[0] + 10, s[1] - 40)
    else:
        g = (s[0] - 1, s[1] - 81)
    return dict(gN=g, gF=(g[0] - 4, g[1] - 2), eN=1, eF=1, hN=-90 if stage else t - 10, hF=-90 if stage else t - 10)


def db_thruster_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 90)
        art.db_end(doc, grip(j, "F"), 9.5)
    else:
        art.db_end(doc, grip(j), 10)


def kb_arms(hip, t, stage):
    td, n = tframe(t)
    s = shoulder(hip, t)
    if stage == 0:
        g = art.add(art.add(s, n, 15), td, -12)
        return dict(gN=g, gF=art.add(g, n, 2), eN=1, eF=1, hN=t - 4, hF=t - 4)
    g = (s[0] + 10, s[1] - 40) if stage == 1 else (s[0] - 1, s[1] - 81)
    return dict(gN=g, gF=(g[0] - 4, g[1] - 2), eN=1, eF=1, hN=-90, hF=-90)


def kb_overhead(doc, j, side="N", r=11):
    """Kettlebell pressed overhead: handle in the fist, bell resting on the back of the forearm."""
    w, e = j["wrist" + side], j["elbow" + side]
    g = grip(j, side)
    d = art.norm(art.sub(e, w))  # down the forearm
    nrm = (-d[1], d[0]) if -d[1] < 0 else (d[1], -d[0])  # towards the back (left)
    bell = art.add(art.add(w, d, 6), nrm, r - 1)
    grad = doc.lin((bell[0] - r, bell[1] - r), (bell[0] + r, bell[1] + r), [(0, "#4A5058"), (0.5, "#24282D"), (1, "#101214")])
    doc.add(f'<path d="M{g[0] + 3:.1f},{g[1] + 1:.1f} Q{g[0] - 2:.1f},{g[1] - 9:.1f} {bell[0] + 1:.1f},{bell[1] - r + 1:.1f}" '
            f'fill="none" stroke="#1A1D21" stroke-width="3.6"/>')
    doc.add(f'<circle cx="{bell[0]:.1f}" cy="{bell[1]:.1f}" r="{r}" fill="{grad}" stroke="#08090A" stroke-width="0.9"/>')


def kb_thruster_scene(doc, j, layer):
    side = "F" if layer == "back" else "N"
    if layer == "back":
        floor(doc, 196, 90)
    if overhead(j, side, 14):
        kb_overhead(doc, j, side, 11 if side == "N" else 10.5)
    else:
        kb_rack(doc, j, side)


BTH = thr_frames(bar_arms)
DTH = thr_frames(db_arms)
KTH = thr_frames(kb_arms)

SCENES.update({
    "barbell-thruster": (bar_thruster_scene, BTH, fit(BTH, (68, 60, 140, GROUND), bar_box(24))),
    "db-thruster": (db_thruster_scene, DTH, fit(DTH, bar_box(12))),
    "kb-thruster": (kb_thruster_scene, KTH, fit(KTH, bar_box(22))),
})


# ==== overhead squats ================================================================================

def ohs_pose(hip, t, h, single=False):
    s = shoulder(hip, t)
    # Bar / bell stacked over the mid-foot, arms locked a little behind the ears.
    g = (TH_X - 8, s[1] - 80)
    if single:
        g = (g[0], s[1] - 87)  # bell arm locked out (at - 80 the elbow stayed bent ~40°)
        return body(hip, t, h=h, ankN=(TH_X, ANK), ankF=(TH_X - 4, ANK), gN=g, eN=1, hN=-90,
                    aF=(t + 128, t + 118))
    return body(hip, t, h=h, ankN=(TH_X, ANK), ankF=(TH_X - 4, ANK), gN=g, gF=(g[0] - 4, g[1] + 2), eN=1, eF=1,
                hN=-90, hF=-90)


def ohs_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 100)
        kit.rack(doc, 96, hook_y=84, safety_y=196)
    else:
        bar_end(doc, grip(j), 22)


def kb_ohs_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 90)
    else:
        kb_overhead(doc, j, "N", 11.5)


OHS = [ohs_pose((198, 152), -90, -86), ohs_pose((186, 186), -82, -78), ohs_pose((176, 220), -76, -74)]
KOHS = [ohs_pose((198, 152), -90, -80, True), ohs_pose((186, 186), -82, -72, True),
        ohs_pose((176, 220), -76, -68, True)]

SCENES.update({
    "overhead-squat": (ohs_scene, OHS, fit(OHS, (60, 60, 132, GROUND), bar_box(24))),
    "kb-overhead-squat": (kb_ohs_scene, KOHS, fit(KOHS, bar_box(24))),
})


# ==== upright rows (front view): elbows lead up and out, stop at shoulder height ======================

from scenes_upper import FR_HIP, G, B as UB, fr_sh  # noqa: E402

FR_LEGS = dict(lN=(84, 92, 12), lF=(96, 88, 168))


def upright_poses(dx0=20, dx1=12, top=16):
    shn, _ = fr_sh()
    out = []
    for k in (0, 0.5, 1):
        y = FR_HIP[1] + 10 + (shn[1] + top - FR_HIP[1] - 10) * k
        dx = dx0 + (dx1 - dx0) * k
        out.append(UB(FR_HIP, -90, front=True, aN=G((FR_HIP[0] + dx, y), -1), aF=G((FR_HIP[0] - dx, y), 1),
                      h=-90, **FR_LEGS))
    return out


def bar_upright_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 60)
    else:
        bar_front(doc, mid(grip(j, "N"), grip(j, "F")), half=96, r=22)
        hand_dots(doc, j)


def db_upright_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 60)
    else:
        for s in "NF":
            g = grip(j, s)
            art.db_side(doc, (g[0], g[1] + 1), 0, 8.5, 14)


BUR = upright_poses(18, 18)  # hands stay where they grip the bar (they slid 22 -> 14 px in)
DUR = upright_poses(18, 22, 14)


def bar_box_front(half=96, r=22):
    def f(j):
        c = mid(grip(j, "N"), grip(j, "F"))
        return [(c[0] - half - 20, c[1] - r, c[0] + half + 20, c[1] + r)]
    return f


SCENES.update({
    "barbell-upright-row": (bar_upright_scene, BUR, fit(BUR, bar_box_front())),
    "db-upright-row": (db_upright_scene, DUR, fit(DUR, lambda j: [(grip(j, s)[0] - 20, grip(j, s)[1] - 10,
                                                                  grip(j, s)[0] + 20, grip(j, s)[1] + 10)
                                                                 for s in "NF"])),
})


# ==== sumo deadlift high pull (front view): wide stance, narrow grip, hips first, bar to the chin =======

from scenes_var_lower import SDL_X, sumo_dl_pose  # noqa: E402


SHP_GRIP = 14  # hands either side of the bar's centre (narrow grip, kept for the whole lift)


def shp_arms(j):
    """Hands stay on the bar at the same narrow grip while the elbows lead up and out: the joint-angle
    in-betweens swung the forearms across each other in front of the chest."""
    y = mid(grip(j, "N"), grip(j, "F"))[1]
    for s, sx in (("N", 1), ("F", -1)):
        sh = j["shoulder" + s]
        best = None
        for bend in (1, -1):
            u, f = L.ik(sh, (SDL_X + sx * SHP_GRIP, y), L.UA, L.FA + L.HA / 2, bend)
            e = art.ang_pt(sh, u, L.UA)
            if best is None or sx * e[0] > sx * best[0][0]:
                best = (e, f)
        e, f = best
        w = art.ang_pt(e, f, L.FA)
        j["elbow" + s], j["wrist" + s], j["hand" + s] = e, w, art.ang_pt(w, f, L.HA)


def shp_scene(doc, j, layer):
    if layer == "back":
        floor(doc, SDL_X, 140)
        foreshorten_trunk(j, sumo_k(j["hip"][1]))
        shp_arms(j)
    else:
        bar_front(doc, mid(grip(j, "N"), grip(j, "F")))
        hand_dots(doc, j)


def shp_top():
    hip = (SDL_X, 156)
    s = shoulder(hip, -90)
    return body(hip, -90, ankN=(SDL_X + 48, ANK - 8), ankF=(SDL_X - 48, ANK - 8), kN=-1, kF=1, fN=60, fF=120,
                gN=(SDL_X + SHP_GRIP, s[1] + 8), gF=(SDL_X - SHP_GRIP, s[1] + 8), eN=-1, eF=1, h=-90, front=True)


SHP = [sumo_dl_pose(196, GROUND - 25), sumo_dl_pose(161, 172), shp_top()]
SCENES["sumo-high-pull"] = (shp_scene, SHP, fit(SHP, (SDL_X - 140, GROUND - 52, SDL_X + 140, GROUND),
                                                 bar_box_front(132, 25)))


# ==== kettlebell high pull (side view): swing from the hips, elbow pulls high and back =================

KBHP_WT = (17, 8)  # wrist at the top of the pull, relative to the shoulder: in front of the chest


def kbhp_arms(j, k):
    """Pull (k = 0 hips snapped, arms long .. 1 top): the hand rises straight up close to the body while the
    elbow travels up and out to the side, towards the camera, so the upper arm foreshortens. Interpolating the
    joint angles swung the elbow back and the bell behind the hips; the old top key had the elbow forward."""
    sh = j["shoulder"]
    for s, off in (("N", (0, 0)), ("F", (-4, 1))):
        w = art.add(art.add(sh, mid(KBHP_W0, KBHP_WT, k)), off)
        l1, l2 = L.UA * (1 - 0.55 * k), L.FA * (1 - 0.12 * k)
        u, f = L.ik(sh, w, l1, l2, 1)
        e = art.ang_pt(sh, u, l1)
        if e[0] > sh[0]:  # elbow behind the shoulder–wrist line, never in front
            u, f = L.ik(sh, w, l1, l2, -1)
            e = art.ang_pt(sh, u, l1)
        j["elbow" + s], j["wrist" + s] = e, art.ang_pt(e, f, l2)
        j["hand" + s] = (j["wrist" + s][0], j["wrist" + s][1] + L.HA)


def kbhp_scene(doc, j, layer):
    if layer == "back":
        PW.ground(doc, 200, 70)
        k = channel(j)
        if k > 0:
            kbhp_arms(j, min(1.0, k))
    else:
        w, h = j["wristN"], j["handN"]
        PW.kb(doc, grip(j), math.degrees(math.atan2(h[1] - w[1], h[0] - w[0])) if h[1] > w[1] + 3 else 90, 12)


KBHP = [
    PW.B((152, 178), -22, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), wrN=(166, 208), wrF=(162, 208), h=-28, curl=0),
    PW.B((196, 150), -94, ankN=(202, GROUND - 10), ankF=(198, GROUND - 10), footN=34, footF=34,
         wrN=(214, 196), wrF=(210, 197), h=-90, curl=0),
    # Top: elbow high and back (out to the side, foreshortened by kbhp_elbows), bell hanging at the chest. It
    # was (-14, 122): elbow pointing forward with the hand folded back under it.
    PW.B((198, 152), -90, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(-165, 20, 90), aF=(-163, 22, 90), h=-90,
         curl=1 / CURL_CH),  # pull progress for kbhp_arms (the scene redraws the arms)
]
_j = F.place(KBHP[1])
KBHP_W0 = art.sub(_j["wristN"], _j["shoulder"])  # wrist at the hip snap (arms long), relative to the shoulder
SCENES["kb-high-pull"] = (kbhp_scene, KBHP, fit(KBHP, PW.ball_box(26)))


# ==== man maker: push-up on the bells, row each side, stand up and press ===============================

from scenes_var_pull import RG_DB, RG_W, renegade_pose  # noqa: E402

MM_HIP = (236, 152)


def db_plank(arm):
    """Plank on the dumbbells (wrists pinned on the handles), torso angle solved so the toes touch the floor."""
    lo, hi = -40.0, 30.0
    pose = None
    for _ in range(44):
        t = (lo + hi) / 2
        pose = P(t=t, h=t + 6, lN=(t + 180, t + 180, 80), lF=(t + 181, t + 181, 80), aN=arm, aF=arm,
                 pin=("wristF", RG_W))
        if F.place(pose)["toeN"][1] < GROUND - 1:
            hi = t
        else:
            lo = t
    return pose


def mm_press():
    s = shoulder(MM_HIP, -90)
    g = (s[0] - 1, s[1] - 81)
    return body(MM_HIP, -90, h=-88, ankN=(MM_HIP[0], ANK), ankF=(MM_HIP[0] - 4, ANK), gN=g, gF=(g[0] - 4, g[1] - 2),
                eN=1, eF=1, hN=-90, hF=-90)


def man_maker_scene(doc, j, layer):
    standing = j["hip"][1] < GROUND - 60
    if layer == "back":
        PW.ground(doc, 220, 120)
        if standing:
            art.db_end(doc, grip(j, "F"), 9.5)
        else:
            art.db_side(doc, (RG_DB[0] - 2, RG_DB[1]), 0, 9, 15)
    elif standing:
        art.db_end(doc, grip(j), 10)
    else:
        art.db_side(doc, grip(j), 0, 9.5, 15)


MMK = [db_plank((198, 64, 90)), renegade_pose((150, 86, 86)), mm_press()]
MMK[0]["h"] = MMK[0]["t"] + 2
SCENES["man-maker"] = (man_maker_scene, MMK, fit(MMK, (RG_DB[0] - 20, GROUND - 20, RG_DB[0] + 20, GROUND), bar_box(12)))


# ==== kettlebell windmill (front view): bell locked overhead, hips out, free hand slides down the leg ====

WM_X = 200


def windmill(t, hip_dx, reach_k):
    """t = trunk tilt towards the far (free-hand) side; reach_k 0..1 along the far thigh, 1..2 down the shin."""
    hip = (WM_X + hip_dx, 152 + abs(t + 90) * 0.1)
    p = body(hip, t, ankN=(WM_X + 26, ANK), ankF=(WM_X - 40, ANK), kN=-1, kF=1, fN=10, fF=170, front=True, h=t)
    p["aN"] = (-90, -90, -90)  # bell arm vertical, stacked over the shoulder
    j = F.place(p)
    art.frontal(j)
    tgt = mid(j["hipF"], j["kneeF"], 0.4 + 0.6 * reach_k) if reach_k <= 1 else mid(j["kneeF"], j["ankleF"], reach_k - 1)
    tgt = art.add(tgt, (-5, 0))
    p["aF"] = L.ik(j["shoulderF"], tgt, L.UA, L.FA + L.HA / 2, 1)
    p["lit_sides"] = "NF"
    return p


def windmill_scene(doc, j, layer):
    if layer == "back":
        floor(doc, WM_X, 70)
    else:
        kb_overhead_front(doc, j)


def kb_overhead_front(doc, j, side="N", r=11.5):
    """Bell locked out overhead, seen from the front: resting on the back of the wrist (towards the viewer)."""
    g = grip(j, side)
    kit.kettlebell(doc, (g[0], g[1] + 2), up=True, r=r)


WMD = [windmill(-90, 0, 0), windmill(-122, 8, 0.9), windmill(-148, 14, 1.6)]
SCENES["kb-windmill"] = (windmill_scene, WMD, fit(WMD, bar_box(26)))


# ==== kettlebell halo (front view): bell upside down by the horns, circled close around the head ======

HALO_HIP = (200, 153)


def halo(c, h=-90, eN=-1, eF=1):
    p = body(HALO_HIP, -90, ankN=(HALO_HIP[0] + 8, ANK), ankF=(HALO_HIP[0] - 8, ANK), kN=-1, kF=1, fN=12, fF=168,
             gN=(c[0] + 5, c[1]), gF=(c[0] - 5, c[1]), eN=eN, eF=eF, front=True, h=h)
    return p


def halo_at(s):
    """One full circle round the head (s = 0 … 1): chest, near side of the head, behind the head (hidden, elbows
    up either side of the face), far side, back to the chest. Every frame solved on the circle (tweens.EXTRA)."""
    a = 2 * math.pi * s
    c = (_HS[0] + 30 * math.sin(a), _HS[1] - 6 + 28 * math.cos(a))
    up = (1 - math.cos(a)) / 2  # 0 at the chest, 1 behind the head
    # Elbows out and down below the shoulders, out and up above them (they crossed over the face before); the
    # switch is hidden by halo_scene, which draws the elbows pointing at the camera around shoulder height.
    e = 1 if c[1] < _HS[1] else -1
    return halo(c, h=-90 - 4 * math.sin(a) * up, eN=e, eF=-e)


HALO_BAND = 26  # px above / below the shoulders over which the elbows turn towards the camera


def halo_scene(doc, j, layer):
    if layer == "back":
        # Elbows pointing at the camera (foreshortened onto the shoulder–wrist line) while the hands pass shoulder
        # height, so the elbows go from down-and-out to up-and-out without flipping.
        for s in "NF":
            sh, w = j["shoulder" + s], j["wrist" + s]
            k = max(0.0, 1 - abs(grip(j, s)[1] - _HS[1]) / HALO_BAND)
            j["elbow" + s] = art.add(j["elbow" + s], art.sub(mid(sh, w), j["elbow" + s]), k)
    c = mid(grip(j, "N"), grip(j, "F"))
    behind = c[1] < j["neck"][1] - 10 and abs(c[0] - j["neck"][0]) < 24
    if layer == "back":
        floor(doc, 200, 50)
        if behind:
            kit.kettlebell(doc, c, up=True, r=12)
    elif not behind:
        kit.kettlebell(doc, c, up=True, r=12)
        hand_dots(doc, j)


_HS = shoulder(HALO_HIP, -90)
HALO = [halo_at(0), halo_at(0.5), halo_at(1)]
SCENES["kb-halo"] = (halo_scene, HALO, fit(HALO, bar_box(26)))


# ==== floor work: shared helpers ======================================================================

def flat_plate(doc, cx, bottom, r=22, h=6):
    """Weight plate lying flat on the floor, seen edge-on from the side."""
    g = doc.box_grad([(0, "#3A3F46"), (0.5, "#1B1E22"), (1, "#0E1012")])
    doc.add(f'<rect x="{cx - r:.1f}" y="{bottom - h:.1f}" width="{2 * r:.1f}" height="{h}" rx="1.8" fill="{g}" '
            f'stroke="#08090A" stroke-width="0.8"/>'
            f'<rect x="{cx - r * 0.3:.1f}" y="{bottom - h - 1.2:.1f}" width="{r * 0.6:.1f}" height="1.6" rx="0.8" fill="#4A5058"/>')


def mat_scene(x0, x1, back=None, front=None):
    def scene(doc, j, layer):
        if layer == "back":
            PW.ground(doc, (x0 + x1) / 2, (x1 - x0) / 2)
            kit.mat(doc, x0, x1)
            if back:
                back(doc, j)
        elif front:
            front(doc, j)
    return scene


def crossed_arms(p):
    """Arms folded across the chest (relative to the torso angle)."""
    t = p["t"]
    return dict(p, aN=(t + 166, t + 10, t + 10), aF=(t + 168, t + 12, t + 12))


# ==== sit-up: feet anchored under a dumbbell, curl up spine first, lower slowly ======================

SU_HIP_X = 196
SU_ANK = (SU_HIP_X + 74, MAT - 4)  # heels on the mat top (at FOOT_Y the feet sank into the mat)


def situp(t, curl, h):
    p = P(t=t, h=h, curl=curl, lN=(-50, 50, 0), lF=(-50, 50, 0))
    p = crossed_arms(p)
    p = MO.rest(p, "hip", SU_HIP_X, MAT, ("torso",))
    p = MO.reach(p, "lN", SU_ANK, end=0, pick=lambda m: -m[1])
    p = MO.reach(p, "lF", (SU_ANK[0] - 3, SU_ANK[1]), end=0, pick=lambda m: -m[1])
    return p


def situp_anchor(doc, j):
    art.db_end(doc, (SU_ANK[0] + 9, SU_ANK[1] - 9), 12)


SITUP = [situp(180, 0, 178), situp(222, 8, 238), situp(-76, 6, -66)]
SCENES["sit-up"] = MO.entry(mat_scene(90, 320, front=situp_anchor), SITUP, [(90, MAT, 320, GROUND),
                                                                             (SU_ANK[0] - 6, GROUND - 26,
                                                                              SU_ANK[0] + 24, GROUND)], corner="tl")


# ==== decline sit-up: hips on the decline pad, feet hooked under the rollers =============================

DB_LO = (96, 232)    # low (head) end of the pad's top surface
DB_HI = (262, 180)   # high end
DB_ANG = math.degrees(math.atan2(DB_HI[1] - DB_LO[1], DB_HI[0] - DB_LO[0]))  # about -17
DB_ROLL = (286, 172)  # ankle roller


def on_pad(x, lift=15):
    """Point `lift` px above the pad surface at x."""
    k = (x - DB_LO[0]) / (DB_HI[0] - DB_LO[0])
    s = mid(DB_LO, DB_HI, k)
    a = math.radians(DB_ANG - 90)
    return (s[0] + math.cos(a) * lift, s[1] + math.sin(a) * lift)


DS_HIP = on_pad(222)


def decline_bench(doc, j):
    lo, hi = DB_LO, DB_HI
    # Frame: low foot under the head end, tall post under the high end, ankle post with rollers.
    art.tube(doc, (lo[0] + 16, lo[1] + 12), (lo[0] + 16, GROUND - 2), 7, "butt")
    art.tube(doc, (hi[0] - 20, hi[1] + 12), (hi[0] - 20, GROUND - 2), 8, "butt")
    kit.feet(doc, lo[0] - 4, lo[0] + 36)
    kit.feet(doc, hi[0] - 44, DB_ROLL[0] + 26)
    art.tube(doc, (lo[0] + 16, lo[1] + 15), (hi[0] - 20, hi[1] + 15), 6)
    art.tube(doc, (hi[0] - 20, hi[1] + 12), (DB_ROLL[0], DB_ROLL[1] + 12), 6)
    art.tube(doc, (DB_ROLL[0], DB_ROLL[1]), (DB_ROLL[0], GROUND - 2), 6, "butt")
    L.slab(doc, lo, hi, 12, (lo[0], lo[1] - 40))


def decline_rollers(doc, j):
    kit.roller_pad(doc, (DB_ROLL[0], DB_ROLL[1] - 3), 8)
    kit.roller_pad(doc, (DB_ROLL[0] - 4, DB_ROLL[1] + 16), 8)


def decline_situp(t, curl, h):
    p = P(t=t, h=h, curl=curl, pin=("hip", DS_HIP))
    p = crossed_arms(p)
    # Knees bent over the top of the pad, ankles between the rollers.
    p = MO.reach(p, "lN", (DB_ROLL[0] - 4, DB_ROLL[1] + 6), end=10, pick=lambda m: -m[1])
    p = MO.reach(p, "lF", (DB_ROLL[0] - 7, DB_ROLL[1] + 7), end=10, pick=lambda m: -m[1])
    return p


def decline_scene(doc, j, layer):
    if layer == "back":
        PW.ground(doc, 190, 110)
        decline_bench(doc, j)
    else:
        decline_rollers(doc, j)


DSU = [decline_situp(DB_ANG + 180, 0, DB_ANG + 180), decline_situp(214, 8, 232), decline_situp(-80, 6, -70)]
SCENES["decline-sit-up"] = MO.entry(decline_scene, DSU, [(DB_LO[0] - 6, DB_HI[1] - 4, DB_ROLL[0] + 26, GROUND)])


# ==== wall sit: back flat on the wall, thighs parallel, knees over the ankles ===========================

WALL_X = 130  # wall face
WS_ANK_X = WALL_X + 16 + 56  # knees over the ankles


def wall_sit(hip_y, arms=None, h=-90):
    hip = (WALL_X + 16, hip_y)
    # Arms reaching forward: elbows softly flexed (eN=-1 bent them backwards, hyperextended).
    kw = dict(gN=arms, gF=(arms[0] - 3, arms[1] + 1), eN=1, eF=1) if arms else {}
    p = body(hip, -90, h=h, ankN=(WS_ANK_X, ANK), ankF=(WS_ANK_X - 4, ANK), **kw)
    if not arms:
        p["aN"], p["aF"] = (92, 70, 70), (94, 72, 72)
    return p


def wall_scene(doc, j, layer):
    if layer == "back":
        PW.ground(doc, 190, 70)
        g = doc.box_grad([(0, "#6F7782"), (1, "#4C535C")], vertical=False)
        doc.add(f'<rect x="{WALL_X - 40}" y="-40" width="40" height="{GROUND + 40}" fill="{g}" stroke="#2A2F35" '
                f'stroke-width="0.8"/>')


_WS_S = shoulder((WALL_X + 16, ANK - 54), -90)
WSIT = [wall_sit(176), wall_sit(ANK - 54), wall_sit(ANK - 54, (_WS_S[0] + 78, _WS_S[1] + 4))]
SCENES["wall-sit"] = (wall_scene, WSIT, fit(WSIT, (WALL_X - 20, 80, WALL_X, GROUND)))


# ==== bear crawl: knees hovering just off the floor, opposite hand and foot step together ===============

BC_HIP = (176, GROUND - 80)
BC_TOE_UP = 13  # ankle height on the balls of the feet


def bear(step=None):
    """step None = hold; "N" = near hand + far foot forward; "F" = far hand + near foot forward."""
    p = P(t=-2, h=8, lN=(92, 180, 70), lF=(92, 180, 70), aN=(90, 90, 0), aF=(90, 90, 0), pin=("hip", BC_HIP))
    j = MO.joints(p)
    s = j["shoulder"]
    hand = {"N": 0, "F": 0}
    foot = {"N": 0, "F": 0}
    if step == "N":
        hand["N"], foot["F"] = 24, 24
    elif step == "F":
        hand["F"], foot["N"] = 24, 24
    for side in "NF":
        lift = 8 if (hand[side] and step) else 0
        p = MO.reach(p, "a" + side, (s[0] + 2 + hand[side] - (2 if side == "F" else 0), GROUND - MO.WRIST_UP - lift),
                     end=0 if not lift else 20)
        fl = 6 if foot[side] else 0
        p = MO.reach(p, "l" + side, (BC_HIP[0] - 46 + foot[side] - (3 if side == "F" else 0), GROUND - BC_TOE_UP - fl),
                     end=40, pick=lambda m: m[0])
    return p


BEAR = [bear(), bear("N"), bear("F")]
SCENES["bear-crawl"] = MO.entry(mat_scene(90, 320), BEAR, [(90, MAT, 320, GROUND)])


# ==== donkey kick: on all fours, knee bent 90 degrees, heel pressed to the ceiling ======================

def donkey(k):
    thigh = MO.lerp(90, 196, k)
    shin = MO.lerp(180, 286, k)
    p = P(t=1, h=12, lN=(thigh, shin, shin - 90 if k else 180), lF=(90, 180, 180), aN=(90, 90, 0), aF=(90, 90, 0),
          lit_sides="N")
    p = MO.rest(p, "kneeF", 168, MAT, ("thighF", "shinF", "footF"))
    j = MO.joints(p)
    s = j["shoulder"]
    p = MO.reach(p, "aN", (s[0] + 3, MAT - MO.WRIST_UP), end=0)
    p = MO.reach(p, "aF", (s[0] + 1, MAT - MO.WRIST_UP), end=0)
    if k == 0:
        p = dict(p, lN=(90, 180, 180))
    return p


DONKEY = [donkey(0), donkey(0.5), donkey(1)]
SCENES["donkey-kick"] = MO.entry(mat_scene(70, 330), DONKEY, [(70, MAT, 330, GROUND)])


# ==== frog pump: soles together, knees out, drive the hips up ===========================================

FP_SH = (130, MAT - 14)  # shoulders on the mat; at GROUND - 13 the pelvis sank through it at the bottom
FP_ANK = (232, MAT - 5)  # feet on their outer edges on the mat (at FOOT_Y - 1 they sank through it)


def frog(lift):
    hip = art.ang_pt(FP_SH, -lift, F.TORSO)
    return PW.B(hip, 180 - lift, ankN=FP_ANK, ankF=(FP_ANK[0] - 2, FP_ANK[1]), footN=8, footF=10,
                wrN=(FP_SH[0] + 79, MAT - 5), wrF=(FP_SH[0] + 77, MAT - 5), elbN=-1, elbF=-1, handN=0, handF=0,
                h=180)


def frog_knees(doc, j):
    """Soles together, knees fallen out to the sides: each leg solved in 3D (hip either side of the pelvis,
    ankles together on the mat, knee pushed out towards / away from the camera) and projected, so the thighs
    read short and the knees low. The flat two-link solve stood the knees straight up and drove the shins and
    toes down through the mat."""
    from scenes_arms_core import _ik3
    hip = j["hip"]
    for s, sz in (("N", 1), ("F", -1)):
        a = j["ankle" + s]
        k = _ik3((hip[0], hip[1], sz * 9.0), (a[0], a[1], sz * 2.0), F.THIGH, F.SHIN, (0.0, -0.3, sz * 1.0))
        j["knee" + s] = (k[0], k[1])


FROG = [frog(2), frog(14), frog(26)]
SCENES["frog-pump"] = MO.entry(mat_scene(70, 290, back=frog_knees), FROG, [(70, MAT, 290, GROUND)])


# ==== deficit push-up: hands on stacked plates, chest sinks below the hands ===============================

DP_PLATE_X = 272
DP_DEF = 12  # two plates


def deficit_scene(doc, j, layer):
    if layer == "back":
        PW.ground(doc, 190, 120)
        for i in range(2):
            flat_plate(doc, DP_PLATE_X - 4, GROUND - i * 6, 22, 6)


from scenes import plank_on_floor  # noqa: E402

DPU = [plank_on_floor((90, 90, 0), (DP_PLATE_X, GROUND - DP_DEF - 5)),
       plank_on_floor((150, 72, 0), (DP_PLATE_X, GROUND - DP_DEF - 5)),
       plank_on_floor((212, 56, 0), (DP_PLATE_X, GROUND - DP_DEF - 5))]
SCENES["deficit-push-up"] = (deficit_scene, DPU, fit(DPU, (DP_PLATE_X - 30, GROUND - 14, DP_PLATE_X + 22, GROUND)))
