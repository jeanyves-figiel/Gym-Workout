"""Scenes for the #174 catalog extension (lower): squat, lunge, hinge, glute and knee variations.

Built on the pose solver and equipment of scenes_lower.py (body(): hip pinned, ankles / hands solved with
two-link IK onto absolute targets) so the variations match their base exercises; views are fitted around
every frame with scenes_power.fit(). Lying-on-the-side moves are drawn in a front / back view; limbs that
point towards or away from the camera are foreshortened in the scene's back layer (as
scenes_arms_core.foreshorten_trunk does for the trunk). Angles as in poses.py (0 = right, 90 = down; the
figure faces right).
"""
import math

import art
import kit
from art import GROUND
from scenes_arms_core import foreshorten_trunk, tower
from scenes_lower import (ANK, FT, SH, SW, TH, TOR, angle, arms_for, back_bar, back_ext_pose, back_ext_scene, bar_end,
                          bar_split_scene, body, dbs, floor, grip, hang_from, hinge_pose, hip_thrust_scene, ins,
                          leg_curl_pose, leg_curl_scene, leg_ext_pose, leg_ext_scene, leg_press_pose, leg_press_scene,
                          norm2, pt, reverse_lunge_frames, shoulder, smith_bar, smith_frame, split_pose, step_block,
                          tframe, thrust_pose)
from scenes_power import fit

MAT_Y = GROUND - 4
SCENES = {}


def mid(a, b, k=0.5):
    return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)


def hand_dots(doc, j, sides="NF"):
    """Closed hands drawn over a bar / handle held in front of the body."""
    for s in sides:
        h = grip(j, s)
        doc.add(f'<circle cx="{h[0]:.1f}" cy="{h[1]:.1f}" r="4.4" fill="#E2E6EB" stroke="{art.OUTLINE}" stroke-width="0.9"/>')


# ==== squats ======================================================================================

# -- barbell box squat: sit back to a box behind the heels
BXS_ANK = (204, ANK)
BXS_BOX = (122, 56, 44)  # x, width, height (top under the glutes at the bottom)


def box_squat_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 186, 110)
        kit.rack(doc, 70, hook_y=84, safety_y=196)
        kit.box(doc, BXS_BOX[0], BXS_BOX[1], BXS_BOX[2])
    else:
        bar_end(doc, kit.on_back(j))


def box_squat_pose(hip, t, h=None):
    return body(hip, t, h=h, ankN=BXS_ANK, ankF=(BXS_ANK[0] - 4, ANK), **arms_for(hip, t, "bar"))


BXS = [box_squat_pose((200, 152), -90), box_squat_pose((176, 184), -70, h=-76),
       box_squat_pose((148, GROUND - BXS_BOX[2] - 14), -52, h=-62)]


# -- Zercher squat: bar in the elbow crease, hands clasped in front of the chest
ZS_ANK = (200, ANK)


def zercher_bar(j):
    e, w = j["elbowN"], j["wristN"]
    d = norm2(e, w)
    return art.add(art.add(e, d, 7), (d[1], -d[0]), -6)


def zercher_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 100)
        kit.rack(doc, 92, hook_y=150, safety_y=208)
    else:
        bar_end(doc, zercher_bar(j))


def zercher_pose(hip, t, h=None):
    up = t + 160
    fore = t - 8
    return body(hip, t, h=h, ankN=ZS_ANK, ankF=(ZS_ANK[0] - 4, ANK), aN=(up, fore, fore - 20),
                aF=(up + 4, fore + 2, fore - 18))


ZS = [zercher_pose((198, 152), -90), zercher_pose((184, 186), -80), zercher_pose((172, 216), -72, h=-78)]


# -- double kettlebell front squat
def kb_rack(doc, j, side):
    td, n = kit.torso_frame(j)
    g = grip(j, side)
    bell = art.add(art.add(g, n, 7), td, -9)
    r = 11 if side == "N" else 10.5
    gr = doc.lin((bell[0] - r, bell[1] - r), (bell[0] + r, bell[1] + r), [(0, "#4A5058"), (0.5, "#24282D"), (1, "#101214")])
    doc.add(f'<path d="M{g[0] - 6:.1f},{g[1] + 2:.1f} Q{g[0]:.1f},{g[1] - 8:.1f} {g[0] + 6:.1f},{g[1] + 2:.1f}" fill="none" '
            f'stroke="#1A1D21" stroke-width="3.6"/>'
            f'<circle cx="{bell[0]:.1f}" cy="{bell[1]:.1f}" r="{r}" fill="{gr}" stroke="#08090A" stroke-width="0.9"/>')


def kb_front_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 90)
        kb_rack(doc, j, "F")
    else:
        kb_rack(doc, j, "N")


def kb_front_pose(hip, t, h=None):
    td, n = tframe(t)
    s = shoulder(hip, t)
    g = art.add(art.add(s, n, 15), td, -12)
    return body(hip, t, h=h, ankN=(200, ANK), ankF=(196, ANK), gN=g, gF=art.add(g, n, 2), eN=1, eF=1,
                hN=t - 4, hF=t - 4)


KBF = [kb_front_pose((198, 152), -90), kb_front_pose((184, 186), -80), kb_front_pose((172, 220), -72, h=-80)]


# -- heels-elevated goblet squat: heels on a slant board, knees travel far forward, torso upright
HE_ANK = (200, ANK - 13)
HE_FOOT = 28


def slant_board(doc, x0, x1, h0, h1):
    g = doc.box_grad([(0, "#6B5A44"), (1, "#3E3022")])
    doc.add(f'<path d="M{x0:.1f},{GROUND:.1f} L{x0:.1f},{GROUND - h0:.1f} L{x1:.1f},{GROUND - h1:.1f} L{x1:.1f},{GROUND:.1f} Z" '
            f'fill="{g}" stroke="#0A0B0D" stroke-width="0.8" stroke-linejoin="round"/>')


def heel_goblet_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 90)
        slant_board(doc, 186, 230, 16, 4)
    else:
        g = grip(j)
        art.db_side(doc, (g[0] + 1, g[1] + 12), 90, 10, 15)


def heel_goblet_pose(hip, t, h=None):
    td, n = tframe(t)
    s = shoulder(hip, t)
    g = (s[0] + n[0] * 22 - td[0] * 16, s[1] + n[1] * 22 - td[1] * 16)
    return body(hip, t, h=h, ankN=HE_ANK, ankF=(HE_ANK[0] - 4, HE_ANK[1]), fN=HE_FOOT, fF=HE_FOOT,
                gN=g, gF=(g[0] + 1, g[1] - 1), eN=1, eF=1, hN=-90, hF=-90)


HEG = [heel_goblet_pose((200, 139), -90), heel_goblet_pose((192, 180), -86), heel_goblet_pose((184, 214), -80, h=-84)]


# -- dumbbell sumo squat (front view): wide stance, toes out, one dumbbell hanging between the legs
SUMO_X = 200


def sumo_db_scene(doc, j, layer):
    if layer == "back":
        floor(doc, SUMO_X, 100)
    else:
        g = mid(grip(j, "N"), grip(j, "F"))
        art.db_side(doc, (g[0], g[1] + 15), 90, 10, 15)
        hand_dots(doc, j)


def sumo_db_pose(y):
    hip = (SUMO_X, y)
    s = shoulder(hip, -90)
    gy = s[1] + 80
    return body(hip, -90, ankN=(SUMO_X + 54, ANK), ankF=(SUMO_X - 54, ANK), kN=-1, kF=1, fN=20, fF=160,
                gN=(SUMO_X + 7, gy + 2), gF=(SUMO_X - 7, gy + 2), eN=1, eF=-1, front=True)


SUMO = [sumo_db_pose(160), sumo_db_pose(184), sumo_db_pose(208)]


# -- landmine squat: bar end at the chest, anchor on the floor in front
LMS_ANCHOR = (356, GROUND - 4)


def landmine_bar(doc, g, anchor=LMS_ANCHOR, plate_r=20):
    d = norm2(anchor, g)
    end = art.add(g, d, 9)
    art.tube(doc, anchor, end, 5)
    art.plate(doc, art.add(g, d, -26), plate_r, hub=False)
    doc.add(f'<rect x="{anchor[0] - 10:.1f}" y="{GROUND - 8:.1f}" width="20" height="8" rx="2" fill="#2A2E34"/>')


def landmine_squat_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 230, 140)
    else:
        landmine_bar(doc, mid(grip(j, "N"), grip(j, "F")))
        hand_dots(doc, j, "N")


def landmine_squat_pose(hip, t, h=None):
    td, n = tframe(t)
    s = shoulder(hip, t)
    g = art.add(art.add(s, n, 20), td, -16)
    return body(hip, t, h=h, ankN=(204, ANK), ankF=(200, ANK), gN=g, gF=art.add(g, td, 2), eN=1, eF=1,
                hN=t + 60, hF=t + 60)


LMS = [landmine_squat_pose((200, 152), -84), landmine_squat_pose((188, 186), -78),
       landmine_squat_pose((176, 216), -70, h=-76)]


# -- single-leg leg press: near foot on the plate, far foot down on the frame
def sl_press_pose(k):
    p = leg_press_pose(k)
    p["lF"] = (10, 122, 30)
    p["lit_sides"] = "N"
    return p


SCENES.update({
    "box-squat": (box_squat_scene, BXS, fit(BXS, (40, 20, 100, GROUND), (122, GROUND - 44, 178, GROUND),
                                            lambda j: [(kit.on_back(j)[0] - 26, kit.on_back(j)[1] - 26,
                                                        kit.on_back(j)[0] + 26, kit.on_back(j)[1] + 26)])),
    "zercher-squat": (zercher_scene, ZS, fit(ZS, (60, 140, 140, GROUND), lambda j: [
        (zercher_bar(j)[0] - 26, zercher_bar(j)[1] - 26, zercher_bar(j)[0] + 26, zercher_bar(j)[1] + 26)])),
    "kb-front-squat": (kb_front_scene, KBF, fit(KBF)),
    "heel-elevated-goblet-squat": (heel_goblet_scene, HEG, fit(HEG)),
    "sumo-db-squat": (sumo_db_scene, SUMO, fit(SUMO, (140, 240, 260, GROUND))),
    "landmine-squat": (landmine_squat_scene, LMS, fit(LMS, (300, 200, 366, GROUND))),
    "single-leg-press": (leg_press_scene, ins([sl_press_pose(0), sl_press_pose(0.5), sl_press_pose(1)], "tr"),
                         (50, 44, 314)),
})


def around(f, r):
    """fit() box of radius r around a point that moves with the figure."""
    def box(j):
        c = f(j)
        return [(c[0] - r, c[1] - r, c[0] + r, c[1] + r)]
    return box


def fore_knee(j, side="N", out=3, k=None):
    """Front / back view of a knee bending towards the camera: the knee projects onto the hip-ankle line
    (thigh and shin foreshortened) instead of swinging sideways."""
    h, a = j["hip" + side], j["ankle" + side]
    k = TH / (TH + SH) if k is None else k
    s = 1 if side == "N" else -1
    j["knee" + side] = (h[0] + (a[0] - h[0]) * k + s * out, h[1] + (a[1] - h[1]) * k)


# ==== single-leg ==================================================================================

# -- Smith machine split squat: bar in the fixed vertical rail
SMS_X = 200


def smith_split_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 110)
        smith_frame(doc, SMS_X, top=24)
    else:
        smith_bar(doc, kit.on_back(j))


def smith_split_pose(y, t):
    hip = (SMS_X - back_bar((0, 0), t)[0], y)
    return split_pose(hip, t, (hip[0] + 44, ANK), (hip[0] - 64, GROUND - 13), 44 + (y - 166) / 12, "bar")


SMSP = ins([smith_split_pose(166, -88), smith_split_pose(190, -86), smith_split_pose(212, -84)], "tr")


# -- dumbbell forward lunge: step forward from standing, land heel first, sink
def lunge_db_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 100)
    dbs(doc, j, layer)


FWL = ins([
    split_pose((154, 152), -90, (158, ANK), (150, ANK), 0, "db"),
    split_pose((180, 168), -90, (230, GROUND - 14), (150, GROUND - 6), 26, "db", front_foot=-18),
    split_pose((196, 212), -88, (244, ANK), (146, GROUND - 13), 48, "db"),
], "tr")


# -- curtsy lunge (front view): the rear leg steps back and across behind the working leg
CL_X = 200


def front_dbs(doc, j, layer):
    if layer == "front":
        for s in "NF":
            art.db_end(doc, grip(j, s), 10)


def curtsy_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 80)
        fore_knee(j, "F", 4)
        h, a = j["hipN"], j["ankleN"]
        if a[0] < h[0] - 6:  # the rear knee drops towards the floor as it travels back and across
            fore_knee(j, "N", 0, 0.62)
            j["kneeN"] = (j["kneeN"][0] + 6, j["kneeN"][1] + 6)
    front_dbs(doc, j, layer)


def curtsy_pose(hip, ankN, fN, kN=1):
    """Back view: the far leg works, the near (rear) leg crosses behind it towards the camera."""
    s = shoulder(hip, -90)
    return body(hip, -90, ankF=(hip[0] - 12, ANK), ankN=ankN, kF=1, kN=kN, fF=168, fN=fN,
                gN=(hip[0] + SW + 12, s[1] + 80), gF=(hip[0] - SW - 12, s[1] + 80), eN=1, eF=-1,
                front="back", lit_sides="F")


CUR = [curtsy_pose((200, 152), (212, ANK), 12), curtsy_pose((198, 178), (172, GROUND - 20), 84),
       curtsy_pose((196, 202), (152, GROUND - 10), 86)]


# -- dumbbell lateral lunge (front view): big step to the side, sit into the hip, other leg straight
def lateral_lunge_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 206, 110)
    front_dbs(doc, j, layer)


def lateral_lunge_pose(hip, ankN, ankF, t=-90):
    s = shoulder(hip, t)
    return body(hip, t, ankN=ankN, ankF=ankF, kN=-1, kF=1, fN=14, fF=168,
                gN=(s[0] + SW + 12, s[1] + 80), gF=(s[0] - SW - 12, s[1] + 80), eN=1, eF=-1, front=True)


LAT = [lateral_lunge_pose((200, 152), (212, ANK), (188, ANK)),
       lateral_lunge_pose((214, 168), (272, ANK), (140, ANK)),
       lateral_lunge_pose((236, 204), (272, ANK), (140, ANK))]


# -- front-foot-elevated split squat: front foot on a low step
FFE_STEP = (212, 60, 18)  # x, width, height
FFE_F = (240, GROUND - FFE_STEP[2] - 4)


def ffe_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 110)
        step_block(doc, *FFE_STEP)
    dbs(doc, j, layer)


FFE = ins([
    split_pose((194, 152), -88, FFE_F, (128, GROUND - 13), 44),
    split_pose((190, 188), -86, FFE_F, (128, GROUND - 13), 46),
    split_pose((186, 214), -84, FFE_F, (128, GROUND - 13), 50),
], "tr")


# -- lateral step-down (front view): stand side-on on a low box, lower the free heel to the floor
LSD_BOX = (212, 100, 44)
LSD_ANK = (232, GROUND - LSD_BOX[2] - 4)


def step_down_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 220, 90)
        kit.box(doc, *LSD_BOX)
        fore_knee(j, "N", 5)


def step_down_pose(hip, ankF, arms=0):
    s = shoulder(hip, -90)
    g = (s[0] + 40 + arms, s[1] + 40 - arms)
    return body(hip, -90, ankN=LSD_ANK, ankF=ankF, kN=-1, kF=1, fN=10, fF=180, gN=(s[0] + SW + 4, s[1] + 70),
                gF=(s[0] - SW - 4, s[1] + 70), eN=-1, eF=1, front=True, lit_sides="N") if arms == 0 else \
        body(hip, -90, ankN=LSD_ANK, ankF=ankF, kN=-1, kF=1, fN=10, fF=180, gN=g, gF=(g[0] - 80, g[1]),
             eN=-1, eF=1, front=True, lit_sides="N")


LSD = [step_down_pose((222, 110), (186, GROUND - 30)), step_down_pose((220, 134), (186, GROUND - 16)),
       step_down_pose((218, 156), (186, GROUND - 5))]


# -- box pistol: sit to a box on one leg, free leg straight forward
BP_ANK = (214, ANK)
BP_BOX = (124, 58, 54)


def box_pistol_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 100)
        kit.box(doc, *BP_BOX)


def box_pistol_pose(hip, t, legF, reach, h=None):
    s = shoulder(hip, t)
    g = (s[0] + reach[0], s[1] + reach[1])
    p = body(hip, t, h=h, ankN=BP_ANK, gN=g, gF=(g[0] - 3, g[1] + 2), eN=-1, eF=-1, lit_sides="N")
    p["lF"] = legF
    return p


BPIS = [box_pistol_pose((212, 152), -90, (70, 80, -10), (30, 60)),
        box_pistol_pose((192, 184), -72, (16, 20, -70), (68, 18), h=-76),
        box_pistol_pose((168, GROUND - BP_BOX[2] - 14), -56, (-6, -6, -96), (78, 2), h=-66)]


# -- skater squat: back knee to the floor behind, arms forward, front heel down
SK_ANK = (216, ANK)


def skater_pose(hip, t, legF, reach, h=None):
    s = shoulder(hip, t)
    g = (s[0] + reach[0], s[1] + reach[1])
    p = body(hip, t, h=h, ankN=SK_ANK, gN=g, gF=(g[0] - 3, g[1] + 2), eN=-1, eF=-1, lit_sides="N")
    p["lF"] = legF
    return p


def skater_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 100)
        kit.mat(doc, 120, 176, "#3A4048")


SKS = [skater_pose((214, 152), -90, (100, 166, 104), (20, 70)),
       skater_pose((196, 182), -62, (110, 172, 112), (62, 26), h=-70),
       skater_pose((178, 210), -40, (117, 174, 118), (78, 8), h=-50)]


SCENES.update({
    "smith-split-squat": (smith_split_scene, SMSP, (30, 10, 350)),
    "forward-lunge": (lunge_db_scene, FWL, (48, 28, 332)),
    "curtsy-lunge": (curtsy_scene, CUR, fit(CUR)),
    "barbell-reverse-lunge": (bar_split_scene, reverse_lunge_frames("bar"), (40, 28, 332)),
    "lateral-lunge": (lateral_lunge_scene, LAT, fit(LAT)),
    "ffe-split-squat": (ffe_scene, FFE, (48, 28, 332)),
    "lateral-step-down": (step_down_scene, LSD, fit(LSD, (212, GROUND - 44, 312, GROUND))),
    "box-pistol": (box_pistol_scene, BPIS, fit(BPIS, (124, GROUND - 54, 182, GROUND))),
    "skater-squat": (skater_scene, SKS, fit(SKS)),
})


# ==== hinges ======================================================================================

# -- sumo deadlift (front view): wide stance, toes out, hands inside the knees; the trunk is foreshortened
#    as it hinges towards the camera
SDL_X = 200
SDL_PLATE = 25


def sumo_k(hip_y):
    """Trunk foreshortening for the hinge: 0.56 with the hips low at the floor, 1 at lockout."""
    return max(0.56, min(1.0, 0.56 + (196 - hip_y) / (196 - 161) * 0.44))


def bar_front(doc, c, half=118, r=SDL_PLATE):
    """Barbell seen from the front: shaft across the view, plates edge-on on both sleeves."""
    art.tube(doc, (c[0] - half - 14, c[1]), (c[0] + half + 14, c[1]), 4)
    for s in (-1, 1):
        x = c[0] + s * half
        art.tube(doc, (x - s * 14, c[1]), (x - s * 14, c[1]), 7)
        for i, (w, rr) in enumerate(((7, r), (7, r), (4, r * 0.62))):
            xx = x + s * i * 7.5
            g = doc.box_grad([(0, "#3A3F46"), (0.5, "#1B1E22"), (1, "#0E1012")], vertical=False)
            doc.add(f'<rect x="{xx - w / 2:.1f}" y="{c[1] - rr:.1f}" width="{w}" height="{2 * rr:.1f}" rx="1.6" '
                    f'fill="{g}" stroke="#08090A" stroke-width="0.8"/>')
        art.tube(doc, (x - s * 6, c[1] - 6), (x - s * 6, c[1] + 6), 4)


def sumo_dl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, SDL_X, 140)
        foreshorten_trunk(j, sumo_k(j["hip"][1]))
    else:
        bar_front(doc, mid(grip(j, "N"), grip(j, "F")))
        hand_dots(doc, j)


def sumo_dl_pose(hip_y, bar_y):
    hip = (SDL_X, hip_y)
    dy = TOR * (1 - sumo_k(hip_y))  # foreshorten_trunk() drops the arms by this much
    return body(hip, -90, ankN=(SDL_X + 48, ANK), ankF=(SDL_X - 48, ANK), kN=-1, kF=1, fN=24, fF=156,
                gN=(SDL_X + 14, bar_y - dy), gF=(SDL_X - 14, bar_y - dy), eN=-1, eF=1, front=True)


SDL = [sumo_dl_pose(196, GROUND - SDL_PLATE), sumo_dl_pose(180, 212), sumo_dl_pose(161, 172)]


# -- rack pull: bar on the safety pins just below the knee
RP_PIN = 214


def rack_pull_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 110)
        for x in (128, 282):
            kit.rack(doc, x)
        art.tube(doc, (124, RP_PIN + 6), (286, RP_PIN + 6), 6)
        art.tube(doc, (128, 84), (144, 84), 6)
        art.tube(doc, (282, 84), (266, 84), 6)
    else:
        bar_end(doc, grip(j))


RPL = ins([
    hinge_pose((204, RP_PIN), -40, (196, ANK), dx=7, h=-48),
    hinge_pose((204, 190), -62, (196, ANK), dx=2),
    hinge_pose((203, 164), -89, (196, ANK), dx=-12),
], "tr")


# -- deficit deadlift: standing on a plate, bar on the floor, hips start lower
DD_H = 10
DD_ANK = (196, ANK - DD_H)


def deficit_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 100)
        g = doc.box_grad([(0, "#3E444C"), (1, "#1A1D21")])
        doc.add(f'<rect x="158" y="{GROUND - DD_H:.1f}" width="84" height="{DD_H}" rx="2" fill="{g}" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')
    else:
        bar_end(doc, grip(j))


DDL = ins([
    hinge_pose((204, GROUND - 25), -12, DD_ANK, dx=12, h=-26),
    hinge_pose((204, 200), -44, DD_ANK, dx=4, h=-50),
    hinge_pose((203, 156), -89, DD_ANK, dx=-12),
], "tr")


# -- kettlebell deadlift: bell between the feet
KBD_X = 202


def kb_dl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 90)
    else:
        g = mid(grip(j, "N"), grip(j, "F"))
        kit.kettlebell(doc, (g[0], g[1] - 2), r=12)
        hand_dots(doc, j, "N")


KBDL = ins([
    hinge_pose((KBD_X, GROUND - 29), -26, (198, ANK), dx=4, h=-34),
    hinge_pose((KBD_X, 214), -50, (198, ANK), dx=0, h=-54),
    hinge_pose((KBD_X - 1, 168), -89, (198, ANK), dx=-10),
], "tr")


# -- B-stance dumbbell RDL: front foot flat, back toes down beside the front heel as a kickstand
BS_F = (206, ANK)
BS_R = (176, GROUND - 9)


def bstance_pose(bar, t, dx, h=None):
    hip = hang_from(bar, t, dx)
    return body(hip, t, h=h, ankN=BS_F, ankF=BS_R, kF=-1, fF=58, gN=bar, gF=(bar[0] - 3, bar[1]), eN=-1, eF=-1,
                lit_sides="N")


BSR = ins([bstance_pose((206, 166), -89, -10), bstance_pose((208, 192), -58, -2),
           bstance_pose((208, 216), -28, 4, h=-22)], "tr")


def bstance_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 90)
    dbs(doc, j, layer)


# -- dumbbell hip thrust: one dumbbell across the hips, shoulders on the bench
def db_thrust_scene(doc, j, layer):
    td, n = kit.torso_frame(j)
    if layer == "back":
        hip_thrust_scene(doc, j, layer)
    else:
        art.db_end(doc, art.add(j["hip"], n, 17), 12)


DHT = ins([thrust_pose(206), thrust_pose(193), thrust_pose(180)], "tl")


# -- barbell glute bridge: shoulders on the floor, bar padded over the hips
GB_SH = (130, GROUND - 13)


def bridge_bar(j):
    td, n = kit.torso_frame(j)
    return art.add(j["hip"], n, 19)


def glute_bridge_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 120)
        kit.mat(doc, 60, 300)
    else:
        c = bridge_bar(j)
        doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="7" fill="#3A4E66" stroke="#0A0B0D" stroke-width="0.8"/>')
        bar_end(doc, c, 23)


def glute_bridge_pose(lift):
    t = 180 - lift
    hip = pt(GB_SH, -lift, TOR)
    td, n = tframe(t)
    b = art.add(hip, n, 19)
    return body(hip, t, h=182, ankN=(250, ANK), ankF=(246, ANK), gN=art.add(b, td, -3), gF=art.add(b, td, -7),
                eN=1, eF=1)


GBB = [glute_bridge_pose(4), glute_bridge_pose(15), glute_bridge_pose(27)]


# -- single-leg 45° back extension: one foot under the roller, the free leg bent off the platform
def sl_back_ext_pose(t, h=None):
    p = back_ext_pose(t, h)
    p["lF"] = (112, 64, 150)
    p["lit_sides"] = "N"
    return p


SLBE = ins([sl_back_ext_pose(52, h=48), sl_back_ext_pose(4, h=2), sl_back_ext_pose(-44, h=-42)], "tl")


# -- cable glute kickback: low pulley, ankle cuff on the near (working) leg, hands on the column
CK_TOWER = 304
CK_PULLEY_Y = GROUND - 18


def cuff(doc, a):
    doc.add(f'<rect x="{a[0] - 6:.1f}" y="{a[1] - 7:.1f}" width="12" height="9" rx="3" fill="#1E2227" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>')


def kickback_scene(doc, j, layer):
    a = j["ankleN"]
    if layer == "back":
        floor(doc, 230, 120)
        p = kit.cable_tower(doc, CK_TOWER, CK_PULLEY_Y, max(0.0, (226 - a[0]) * 0.25))
        art.cable(doc, [(p[0], p[1] + 6), (a[0] + 2, a[1] - 2)])
    else:
        cuff(doc, a)


def kickback_pose(legN, t=-70):
    hip = (206, 154)
    s = shoulder(hip, t)
    g = (CK_TOWER - 13, s[1] + 26)
    return body(hip, t, h=t + 4, ankF=(212, ANK), lN=legN, gN=g, gF=(g[0] - 2, g[1] + 6), eN=1, eF=1, hN=-80,
                hF=-80, lit_sides="N")


CKB = ins([kickback_pose((98, 100, 8)), kickback_pose((118, 126, 34)), kickback_pose((140, 150, 60))], "tl")


SCENES.update({
    "sumo-deadlift": (sumo_dl_scene, SDL, fit(SDL, (SDL_X - 140, GROUND - 52, SDL_X + 140, GROUND))),
    "rack-pull": (rack_pull_scene, RPL, (44, 10, 352)),
    "deficit-deadlift": (deficit_scene, DDL, (44, 28, 332)),
    "kb-deadlift": (kb_dl_scene, KBDL, (44, 28, 332)),
    "b-stance-rdl": (bstance_scene, BSR, (44, 28, 332)),
    "db-hip-thrust": (db_thrust_scene, DHT, (44, 82, 260)),
    "barbell-glute-bridge": (glute_bridge_scene, GBB, fit(GBB, (60, GROUND - 6, 300, GROUND),
                                                          around(bridge_bar, 24))),
    "single-leg-back-extension": (back_ext_scene, SLBE, (40, 30, 330)),
    "cable-glute-kickback": (kickback_scene, CKB, fit(CKB, (CK_TOWER - 20, 20, CK_TOWER + 50, GROUND))),
})


# ==== hip abduction / adduction ===================================================================

# -- cable hip abduction (front view): column on the left, cuff on the outside (near) leg
CA_TOWER = 96
CA_HIP_X = 192


def abd_cable_scene(doc, j, layer):
    a = j["ankleN"]
    if layer == "back":
        floor(doc, 170, 120)
        tower(doc, CA_TOWER, GROUND - 18, max(0.0, (a[0] - 214) * 0.25), face="right")
    else:
        p = (CA_TOWER + 12, GROUND - 18)
        art.cable(doc, [(p[0], p[1] + 6), (a[0] - 4, a[1] - 2)])
        cuff(doc, a)


def abd_cable_pose(a):
    hip = (CA_HIP_X, 154)
    s = shoulder(hip, -90)
    return body(hip, -90, ankF=(CA_HIP_X - 8, ANK), fF=168, lN=(90 - a, 90 - a, -a + 6),
                gF=(CA_TOWER + 8, s[1] + 34), gN=(hip[0] + SW + 12, hip[1] - 4), eF=1, eN=-1, hF=180, hN=100,
                front=True, lit_sides="N")


CAB = [abd_cable_pose(4), abd_cable_pose(20), abd_cable_pose(36)]


# -- cable hip adduction (front view): column on the right, cuff on the inside (near) leg, sweep across
CD_TOWER = 282
CD_HIP_X = 196


def add_cable_scene(doc, j, layer):
    a = j["ankleN"]
    p = (CD_TOWER - 12, GROUND - 18)
    if layer == "back":
        floor(doc, 230, 120)
        kit.cable_tower(doc, CD_TOWER, p[1], max(0.0, (p[0] - a[0] - 30) * 0.2))
    else:
        art.cable(doc, [(p[0], p[1] + 6), (a[0] + 4, a[1] - 2)])
        cuff(doc, a)


def add_cable_pose(a):
    hip = (CD_HIP_X, 154)
    s = shoulder(hip, -90)
    return body(hip, -90, ankF=(CD_HIP_X - 12, ANK), fF=168, lN=(90 - a, 90 - a, -a + 6),
                gN=(CD_TOWER - 8, s[1] + 34), gF=(hip[0] - SW - 12, hip[1] - 4), eN=-1, eF=1, hN=0, hF=80,
                front=True, lit_sides="N")


CAD = [add_cable_pose(30), add_cable_pose(8), add_cable_pose(-14)]


# -- side-lying work (front view, head on the left: near = top side). The camera is a little above the
#    mat, so a knee bent towards the camera drops on screen and the bend reads.
SL_HIP = (196, MAT_Y - 19)


def side_lying_pose(legN, legF, **kw):
    hip = SL_HIP
    s = shoulder(hip, 180)
    return body(hip, 180, h=184, lN=legN, lF=legF, aF=(178, 178, 178),
                gN=(s[0] + 34, MAT_Y - 4), eN=-1, hN=0, front=True, **kw)


def mat_back(doc, x0=60, x1=330):
    floor(doc, 196, 140)
    kit.mat(doc, x0, x1)


def side_abd_scene(doc, j, layer):
    if layer == "back":
        mat_back(doc)


SLA = [side_lying_pose((0, 0, 70), (0, 0, 70), lit_sides="N"),
       side_lying_pose((-16, -16, 54), (0, 0, 70), lit_sides="N"),
       side_lying_pose((-32, -32, 38), (0, 0, 70), lit_sides="N")]


def bent_leg(j, side, open_deg=0.0, drop=0.25):
    """Hip 45°, knee 90°, foot back in line with the hips, seen from the front and slightly above (a knee
    towards the camera drops a little on screen); open_deg turns the knee up about the hip-foot line."""
    h = j["hip" + side]
    th = math.radians(open_deg)
    z = 39.6 * math.cos(th)  # towards the camera
    y = 39.6 * math.sin(th)  # up (lateral)
    j["knee" + side] = (h[0] + 39.6, h[1] - y * 0.95 + z * drop)
    j["ankle" + side] = (h[0] + 76, h[1] + 1)
    j["toe" + side] = (h[0] + 84, h[1] + 6)


def band_loop(doc, a, b, color="#2EAD5B"):
    kit.band(doc, a, b, color)
    for p in (a, b):
        doc.add(f'<ellipse cx="{p[0]:.1f}" cy="{p[1]:.1f}" rx="3.2" ry="7" fill="none" stroke="#0A0B0D" stroke-width="4.6"/>'
                f'<ellipse cx="{p[0]:.1f}" cy="{p[1]:.1f}" rx="3.2" ry="7" fill="none" stroke="{color}" stroke-width="3"/>')


def clam_scene(doc, j, layer):
    if layer == "back":
        mat_back(doc)
        # clam_pose() carries the opening in the near thigh's angle; the legs are then redrawn bent.
        bent_leg(j, "N", -angle(j["hipN"], j["kneeN"]))
        bent_leg(j, "F", 0)
    else:
        a = mid(j["hipN"], j["kneeN"], 0.78)
        b = mid(j["hipF"], j["kneeF"], 0.78)
        band_loop(doc, (a[0], a[1] - 3), (b[0], b[1] + 3))


def clam_pose(open_deg):
    return side_lying_pose((-open_deg, 0, 0), (0, 0, 0), lit_sides="N")


CLAM = [clam_pose(0), clam_pose(22), clam_pose(44)]


def side_add_scene(doc, j, layer):
    if layer == "back":
        mat_back(doc)
        # Top leg: hip and knee bent, foot planted on the mat in front of the bottom knee.
        h = j["hipN"]
        j["kneeN"] = (h[0] + 32, h[1] - 18)
        j["ankleN"] = (h[0] + 50, MAT_Y - 2)
        j["toeN"] = (h[0] + 63, MAT_Y + 1)


SLD = [side_lying_pose((40, 40, 40), (0, 0, 70), lit_sides="F"),
       side_lying_pose((40, 40, 40), (-6, -6, 64), lit_sides="F"),
       side_lying_pose((40, 40, 40), (-13, -13, 57), lit_sides="F")]


SCENES.update({
    "cable-hip-abduction": (abd_cable_scene, CAB, fit(CAB, (CA_TOWER - 60, 20, CA_TOWER + 16, GROUND))),
    "cable-hip-adduction": (add_cable_scene, CAD, fit(CAD, (CD_TOWER - 16, 20, CD_TOWER + 50, GROUND))),
    "side-lying-hip-abduction": (side_abd_scene, SLA, fit(SLA, (60, MAT_Y, 330, GROUND))),
    "band-clamshell": (clam_scene, CLAM, fit(CLAM, (60, MAT_Y, 330, GROUND))),
    "side-lying-adduction": (side_add_scene, SLD, fit(SLD, (60, MAT_Y, 330, GROUND))),
})


# ==== knee flexion / extension, calves ============================================================

# -- single-leg lying leg curl: the far leg stays straight on the pad
def sl_curl_pose(shin):
    p = leg_curl_pose(shin)
    p["lF"] = (177, 179, 263)
    p["lit_sides"] = "N"
    return p


SLC = ins([sl_curl_pose(182), sl_curl_pose(228), sl_curl_pose(266)], "tr")


# -- single-leg leg extension: the far leg stays down behind the roller
def sl_ext_pose(shin):
    p = leg_ext_pose(shin)
    p["lF"] = (p["lF"][0], 100, 10)
    p["lit_sides"] = "N"
    return p


SLE = ins([sl_ext_pose(100), sl_ext_pose(52), sl_ext_pose(6)], "tr")


# -- stability ball hamstring curl: shoulders on the mat, heels on the ball, hips high; the ball rolls in
BALL_R = 34
BH_S = (112, GROUND - 13)


def stability_ball(doc, c, r=BALL_R):
    g = doc.lin((c[0] - r, c[1] - r), (c[0] + r, c[1] + r), [(0, "#6FA8DC"), (0.55, "#2F6EA8"), (1, "#18436B")])
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="{g}" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<path d="M{c[0] - r * 0.7:.1f},{c[1] - r * 0.5:.1f} Q{c[0]:.1f},{c[1] - r * 0.95:.1f} {c[0] + r * 0.7:.1f},'
            f'{c[1] - r * 0.5:.1f}" fill="none" stroke="#fff" stroke-opacity="0.25" stroke-width="2"/>')


def ball_centre(j):
    a = j["ankleN"]
    return (a[0] + 8, GROUND - BALL_R)


def ball_curl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 130)
        kit.mat(doc, 60, 320)
        stability_ball(doc, ball_centre(j))


def ball_curl_pose(t, ank_x):
    hip = pt(BH_S, t, -TOR)
    c = (ank_x + 8, GROUND - BALL_R)
    ang = math.radians(-118)
    ank = (c[0] + math.cos(ang) * (BALL_R + 5), c[1] + math.sin(ang) * (BALL_R + 5))
    g = (BH_S[0] + 76, GROUND - 6)
    return body(hip, t, h=182, ankN=ank, ankF=art.add(ank, (-2, -1)), kN=-1, kF=-1, fN=-80, fF=-82,
                gN=g, gF=(g[0] - 4, g[1]), eN=1, eF=1, hN=0, hF=0)


BHC = [ball_curl_pose(170, 290), ball_curl_pose(160, 262), ball_curl_pose(150, 238)]


# -- sissy squat: heels rise, knees travel forward, straight line knees to shoulders; one hand on a post
SS_TOE = (224, GROUND - 2)
SS_POST = 268


def sissy_pose(f, shin_up, a, h=None):
    """f = foot angle (heel rises), shin_up = angle ankle -> knee, a = angle knee -> hip (= torso)."""
    ank = pt(SS_TOE, f, -FT)
    knee = pt(ank, shin_up, SH)
    hip = pt(knee, a, TH)
    s = shoulder(hip, a)
    g = (SS_POST - 6, s[1] + 16)
    return body(hip, a, h=a if h is None else h, lN=(a + 180, angle(knee, ank), f), lF=(a + 181, angle(knee, ank) + 1, f),
                gN=g, gF=(g[0] - 30, g[1] + 34), eN=-1, eF=-1, hN=-80)


def sissy_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 214, 90)
        kit.post(doc, SS_POST + 4, 60)


SSQ = [sissy_pose(0, -90, -90), sissy_pose(32, -58, -108, h=-96), sissy_pose(56, -30, -128, h=-108)]


# -- band Spanish squat: heavy band behind the knees anchored low in front, shins stay vertical
SP_ANK = (200, ANK)
SP_POST = 318


def spanish_knee_pts(j):
    k, a = j["kneeN"], j["ankleN"]
    d = norm2(k, a)
    nrm = (d[1], -d[0])  # towards the back of the shin
    return art.add(art.add(k, d, 8), nrm, -8), art.add(art.add(k, d, 8), nrm, 8)


def spanish_scene(doc, j, layer):
    back, front = spanish_knee_pts(j)
    anchor = (SP_POST - 6, GROUND - 52)
    if layer == "back":
        floor(doc, 230, 120)
        kit.post(doc, SP_POST, 120)
        art.tube(doc, (SP_POST - 10, anchor[1]), (SP_POST + 8, anchor[1]), 6)
        kit.band(doc, anchor, back, "#2E7DD1")
    else:
        kit.band(doc, anchor, front, "#2E7DD1")


def spanish_pose(hip, t, h=None):
    s = shoulder(hip, t)
    td, n = tframe(t)
    g = art.add(art.add(s, n, 22), td, -20)
    return body(hip, t, h=h, ankN=SP_ANK, ankF=(SP_ANK[0] - 4, ANK), gN=g, gF=art.add(g, n, -2), eN=1, eF=1,
                hN=-90, hF=-90)


SPQ = [spanish_pose((198, 152), -90), spanish_pose((170, 184), -80), spanish_pose((146, 206), -70, h=-78)]


# -- seated dumbbell calf raise: on a bench, balls of the feet on a block, dumbbells on the knees
SDC_HIP = (154, 198)
SDC_TOE = (232, GROUND - 22)


def seated_db_calf_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 110)
        kit.flat_bench(doc, 60, 172, SDC_HIP[1] + 14)
        step_block(doc, SDC_TOE[0] - 12, 40, GROUND - SDC_TOE[1] - 1)
        art.db_end(doc, art.add(j["kneeF"], (-10, -12)), 10)
    else:
        art.db_end(doc, art.add(j["kneeN"], (-10, -13)), 10.5)


def seated_db_calf_pose(f):
    ank = pt(SDC_TOE, f, -FT)
    p = body(SDC_HIP, -92, ankN=ank, ankF=art.add(ank, (-3, 0)), fN=f, fF=f)
    j = art.F.place(p)
    k = j["kneeN"]
    g = (k[0] - 10, k[1] - 13)
    return body(SDC_HIP, -92, ankN=ank, ankF=art.add(ank, (-3, 0)), fN=f, fF=f,
                gN=g, gF=(g[0] - 1, g[1] + 1), eN=-1, eF=-1, hN=0, hF=0)


SDCR = ins([seated_db_calf_pose(-26), seated_db_calf_pose(2), seated_db_calf_pose(30)], "tr")


SCENES.update({
    "single-leg-curl": (leg_curl_scene, SLC, (40, 52, 300)),
    "ball-hamstring-curl": (ball_curl_scene, BHC, fit(BHC, (60, MAT_Y, 320, GROUND), around(ball_centre, BALL_R))),
    "single-leg-extension": (leg_ext_scene, SLE, (30, 42, 310)),
    "sissy-squat": (sissy_scene, SSQ, fit(SSQ, (SS_POST - 20, 50, SS_POST + 28, GROUND))),
    "spanish-squat": (spanish_scene, SPQ, fit(SPQ, (SP_POST - 20, 110, SP_POST + 28, GROUND))),
    "seated-db-calf-raise": (seated_db_calf_scene, SDCR, (60, 60, 290)),
})
