"""Scenes for the gym app comparison (#182): small props — sandbag, sliders and the BOSU balance trainer.

Built on the pose solver of scenes_lower.py (body(): hip pinned, ankles / hands solved with two-link IK onto
absolute targets) so the moves match their base exercises (goblet squat, reverse / lateral lunge, glute
bridge, push-up); views are fitted around every frame with scenes_power.fit(). The props are not in kit.py
and are drawn here with art.py primitives. Angles as in poses.py (0 = right, 90 = down; the figure faces
right).
"""
import math

import art
import kit
from art import GROUND
from poses import P
from scenes_lower import ANK, TOR, body, floor, ins, pt, shoulder, split_pose, tframe
from scenes_power import fit

SCENES = {}

CANVAS = ("#8C8257", "#5F5838", "#3B3622")  # sandbag cordura: light, mid, shadow
STRAP = "#1E1F1A"


# ---- props -------------------------------------------------------------------------------------------

def sandbag(doc, c, w=40, h=26, ang=0.0, end=False):
    """Canvas sandbag centred at c. Side-on it is a padded capsule `w` long, `h` thick along `ang` (deg) with
    two webbing handles; `end` = seen end-on (a round, slightly squashed cushion with a cinched seam)."""
    if end:
        r = h / 2
        g = doc.lin((c[0] - r, c[1] - r), (c[0] + r * 0.6, c[1] + r), [(0, CANVAS[0]), (0.55, CANVAS[1]), (1, CANVAS[2])])
        doc.add(f'<g transform="translate({c[0]:.1f} {c[1]:.1f}) rotate({ang:.1f})">'
                f'<path d="M{-r * 1.05:.1f},0 C{-r * 1.08:.1f},{-r * 0.95:.1f} {-r * 0.5:.1f},{-r:.1f} 0,{-r * 0.96:.1f} '
                f'C{r * 0.55:.1f},{-r * 1.02:.1f} {r * 1.1:.1f},{-r * 0.85:.1f} {r * 1.06:.1f},0 '
                f'C{r * 1.04:.1f},{r * 0.9:.1f} {r * 0.5:.1f},{r * 1.0:.1f} 0,{r * 0.95:.1f} '
                f'C{-r * 0.55:.1f},{r * 1.0:.1f} {-r * 1.04:.1f},{r * 0.9:.1f} {-r * 1.05:.1f},0 Z" '
                f'fill="{g}" stroke="#14130C" stroke-width="0.9"/>'
                f'<rect x="{-r * 0.16:.1f}" y="{-r * 0.97:.1f}" width="{r * 0.32:.1f}" height="{r * 1.92:.1f}" fill="{STRAP}" '
                f'fill-opacity="0.85"/>'
                f'<path d="M{-r * 0.8:.1f},{-r * 0.35:.1f} Q{-r * 0.5:.1f},{-r * 0.15:.1f} {-r * 0.3:.1f},{-r * 0.45:.1f} '
                f'M{r * 0.35:.1f},{r * 0.5:.1f} Q{r * 0.6:.1f},{r * 0.3:.1f} {r * 0.85:.1f},{r * 0.45:.1f}" fill="none" '
                f'stroke="#2A2718" stroke-opacity="0.5" stroke-width="0.9"/>'
                f'<path d="M{-r * 0.85:.1f},{-r * 0.6:.1f} Q{-r * 0.4:.1f},{-r * 0.9:.1f} {-r * 0.2:.1f},{-r * 0.88:.1f}" '
                f'fill="none" stroke="#C9C08F" stroke-opacity="0.45" stroke-width="1.2"/>'
                + '</g>')
        return
    g = doc.lin((0, -h / 2), (0, h / 2), [(0, CANVAS[0]), (0.45, CANVAS[1]), (1, CANVAS[2])])
    hw = w / 2
    handles = "".join(
        f'<path d="M{x - 6:.1f},{-h / 2 + 1:.1f} Q{x:.1f},{-h / 2 - 7:.1f} {x + 6:.1f},{-h / 2 + 1:.1f}" fill="none" '
        f'stroke="{STRAP}" stroke-width="2.6" stroke-linecap="round"/>' for x in (-hw * 0.45, hw * 0.45))
    doc.add(f'<g transform="translate({c[0]:.1f} {c[1]:.1f}) rotate({ang:.1f})">{handles}'
            f'<rect x="{-hw:.1f}" y="{-h / 2:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{h * 0.46:.1f}" fill="{g}" '
            f'stroke="#14130C" stroke-width="0.9"/>'
            f'<line x1="{-hw + 5:.1f}" y1="{-h / 2 + 3:.1f}" x2="{hw - 5:.1f}" y2="{-h / 2 + 3:.1f}" stroke="#B5AB7C" '
            f'stroke-opacity="0.5" stroke-width="0.8" stroke-dasharray="2 1.6"/>'
            + "".join(f'<rect x="{x - 2:.1f}" y="{-h / 2 + 0.5:.1f}" width="4" height="{h - 1:.1f}" fill="{STRAP}" '
                      f'fill-opacity="0.85"/>' for x in (-hw * 0.45, hw * 0.45))
            + '</g>')


def slider(doc, c, w=22, color=("#E8463A", "#8E2018")):
    """Furniture-style gliding disc on the floor, seen edge-on, its top face centred at c."""
    g = doc.lin((c[0], c[1]), (c[0], c[1] + 5), [(0, color[0]), (1, color[1])])
    doc.add(f'<rect x="{c[0] - w / 2:.1f}" y="{c[1]:.1f}" width="{w:.1f}" height="4.5" rx="2.2" fill="{g}" '
            f'stroke="#0A0B0D" stroke-width="0.7"/>'
            f'<line x1="{c[0] - w / 2 + 3:.1f}" y1="{c[1] + 1.2:.1f}" x2="{c[0] + w / 2 - 3:.1f}" y2="{c[1] + 1.2:.1f}" '
            f'stroke="#fff" stroke-opacity="0.35" stroke-width="0.7"/>')


BOSU_H = 30  # platform top above the floor
BOSU_R = 42  # platform half-width


def bosu(doc, cx, r=BOSU_R, h=BOSU_H):
    """BOSU-style balance trainer flipped dome-down (flat platform up), seen from the side."""
    top = GROUND - h
    pt_h = 7  # platform thickness
    dome = doc.lin((cx - r, top), (cx + r, GROUND), [(0, "#4E8FD8"), (0.5, "#2B62A8"), (1, "#163A6A")])
    plat = doc.box_grad([(0, "#3A3F46"), (0.35, "#22262B"), (1, "#0E1012")])
    k = 0.55  # dome curvature handle
    y0 = top + pt_h
    doc.add(f'<path d="M{cx - r + 3:.1f},{y0:.1f} C{cx - r + 3:.1f},{y0 + (GROUND - y0) * k * 1.6:.1f} '
            f'{cx - r * 0.45:.1f},{GROUND:.1f} {cx:.1f},{GROUND:.1f} '
            f'C{cx + r * 0.45:.1f},{GROUND:.1f} {cx + r - 3:.1f},{y0 + (GROUND - y0) * k * 1.6:.1f} {cx + r - 3:.1f},{y0:.1f} Z" '
            f'fill="{dome}" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<path d="M{cx - r * 0.62:.1f},{y0 + 4:.1f} Q{cx:.1f},{y0 + 14:.1f} {cx + r * 0.62:.1f},{y0 + 4:.1f}" fill="none" '
            f'stroke="#fff" stroke-opacity="0.22" stroke-width="1.2"/>'
            f'<rect x="{cx - r:.1f}" y="{top:.1f}" width="{2 * r:.1f}" height="{pt_h}" rx="2.5" fill="{plat}" '
            f'stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<rect x="{cx - r + 6:.1f}" y="{top + 2.4:.1f}" width="9" height="2.4" rx="1.2" fill="#5A616A"/>'
            f'<rect x="{cx + r - 15:.1f}" y="{top + 2.4:.1f}" width="9" height="2.4" rx="1.2" fill="#5A616A"/>')
    art.shadow(doc, cx, r * 0.5, ry=3)


# ==== sandbag ===========================================================================================

def hug_point(hip, t, fwd=33, down=26):
    """Bag centre hugged high on the chest: in front of the sternum."""
    td, n = tframe(t)
    return art.add(art.add(shoulder(hip, t), n, fwd), td, -down)


# -- bear-hug squat: bag hugged high on the chest, elbows under it
SBS_ANK = (200, ANK)
SBS_R = 20


def sb_squat_pose(hip, t, h=None):
    td, n = tframe(t)
    c = hug_point(hip, t)
    g = art.add(art.add(c, n, 13), td, 2)  # hands reach round the front of the bag
    return body(hip, t, h=h, ankN=SBS_ANK, ankF=(SBS_ANK[0] - 4, ANK), gN=g, gF=art.add(g, td, 3), eN=1, eF=1,
                hN=t - 100, hF=t - 100)


def sb_squat_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 196, 90)
        td, n = kit.torso_frame(j)
        c = art.add(art.add(j["shoulder"], n, 33), td, -26)
        sandbag(doc, c, h=2 * SBS_R, ang=math.degrees(math.atan2(td[1], td[0])) + 90, end=True)


SBS = ins([sb_squat_pose((198, 152), -90), sb_squat_pose((184, 186), -80), sb_squat_pose((172, 218), -70, h=-78)], "tr")


# -- shouldering: bag on the floor between the feet → lapped on the thighs → onto one shoulder
SH_ANK = (196, ANK)


def sh_pose(hip, t, g, h=None, gF=None, hN=None, eN=-1):
    return body(hip, t, h=h, ankN=SH_ANK, ankF=(SH_ANK[0] - 4, ANK), gN=g, gF=gF or art.add(g, (-3, 1)), eN=eN,
                eF=eN, hN=hN, hF=hN)


SH_BAG = [(218, GROUND - 14), None, None]


def sh_bag(j, frame):
    if frame == 0:
        return SH_BAG[0], 0.0
    if frame == 1:  # lapped: resting on top of the thighs, near the hips
        k, hp = j["kneeN"], j["hip"]
        m = art.add(hp, art.sub(k, hp), 0.62)
        return (m[0], m[1] - 15), math.degrees(math.atan2(k[1] - hp[1], k[0] - hp[0]))
    s = j["shoulder"]
    return (s[0] - 14, s[1] + 4), -8.0


def sh_scene_for(frame):
    def scene(doc, j, layer):
        if layer == "back":
            floor(doc, 196, 90)
        else:
            c, a = sh_bag(j, frame)
            sandbag(doc, c, w=44, h=26, ang=a)
    return scene


def sh_scene(doc, j, layer):
    """The frame is read off the torso angle: hinged (start), half-up with the bag lapped (middle), tall."""
    t = j["_t"]
    sh_scene_for(0 if t > -50 else 1 if t > -84 else 2)(doc, j, layer)


SHO = ins([
    sh_pose((164, 202), -32, (220, GROUND - 26), h=-40, hN=60, eN=-1),
    sh_pose((176, 216), -72, (228, 196), h=-82, hN=-150, eN=1),
    sh_pose((196, 152), -90, (206, 86), hN=-160, eN=1),
], "tr")


# -- front-loaded (Zercher-style) reverse lunge: bag in the elbow creases
def zbag(j):
    e, w = j["elbowN"], j["wristN"]
    d = art.norm(art.sub(w, e))
    return art.add(art.add(e, d, 9), (d[1], -d[0]), -9)


def zercher_arms(t):
    up = t + 160
    fore = t - 8
    return dict(aN=(up, fore, fore - 20), aF=(up + 4, fore + 2, fore - 18))


def sb_lunge_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 186, 100)
    else:
        sandbag(doc, zbag(j), h=36, ang=0, end=True)


def sb_lunge_pose(hip, t, front, rear, rear_foot):
    return body(hip, t, ankN=front, ankF=rear, kN=-1, kF=-1, fN=0, fF=rear_foot, lit_sides="N", **zercher_arms(t))


SPLIT_F = (238, ANK)
SBL = ins([
    sb_lunge_pose((232, 152), -90, SPLIT_F, (SPLIT_F[0] - 5, ANK), 0),
    sb_lunge_pose((214, 178), -87, SPLIT_F, (170, GROUND - 22), 62),
    sb_lunge_pose((190, 212), -84, SPLIT_F, (130, GROUND - 13), 48),
], "tr")


# ==== sliders ===========================================================================================

# -- slider leg curl: supine, heels on sliders, hips held up; heels pulled to the glutes and slid back out
SLC_SH = (118, GROUND - 13)
MAT = (60, 300)


def slc_pose(lift, ank_x, foot):
    hip = pt(SLC_SH, -lift, TOR)
    t = 180 - lift
    g = (SLC_SH[0] + 79, GROUND - 6)
    return body(hip, t, h=180, ankN=(ank_x, GROUND - 10), ankF=(ank_x - 3, GROUND - 10), kN=-1, kF=-1, fN=foot,
                fF=foot, gN=g, gF=(g[0] - 3, g[1]), eN=1, eF=1, hN=0, hF=0)


def slc_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 190, 120)
        kit.mat(doc, *MAT)
        a = j["ankleF"]
        slider(doc, (a[0] - 1, GROUND - 5.5), 20, ("#2F8BD8", "#174A80"))
    else:
        a = j["ankleN"]
        slider(doc, (a[0] - 1, GROUND - 5.5))


SLC = ins([slc_pose(12, 290, -84), slc_pose(26, 260, -70), slc_pose(38, 226, -52)], "tl")


# -- slider lateral lunge (front view): the far leg slides out straight, sit into the near hip
def slat_pose(hip, ankN, ankF, fF=168):
    s = shoulder(hip, -90)
    c = (s[0], s[1] + 34)
    return body(hip, -90, ankN=ankN, ankF=ankF, kN=-1, kF=1, fN=14, fF=fF, gN=(c[0] + 5, c[1]),
                gF=(c[0] - 5, c[1]), eN=-1, eF=1, hN=-90, hF=-90, front=True)


def slat_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 206, 110)
    else:
        a = j["ankleF"]
        slider(doc, (a[0] - 3, GROUND - 3), 26)


SLAT = [slat_pose((200, 152), (212, ANK), (188, GROUND - 7)),
        slat_pose((210, 166), (248, ANK), (156, GROUND - 7)),
        slat_pose((232, 202), (266, ANK), (126, GROUND - 7))]


# -- slider reverse lunge: rear foot on the slider (ball of the foot), slides straight back
def srl_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 186, 100)
        t = j["toeF"]
        slider(doc, (t[0] - 4, GROUND - 3), 22)


SRL = ins([
    split_pose((232, 152), -90, SPLIT_F, (SPLIT_F[0] - 5, ANK - 1), 0, "hips"),
    split_pose((212, 182), -87, SPLIT_F, (172, GROUND - 14), 40, "hips"),
    split_pose((190, 212), -84, SPLIT_F, (130, GROUND - 13), 46, "hips"),
], "tr")


# ==== BOSU ==============================================================================================

BOSU_X = 196
BS_ANK = (200, GROUND - BOSU_H - 4)


def bosu_squat_scene(doc, j, layer):
    if layer == "back":
        floor(doc, BOSU_X, 60)
        bosu(doc, BOSU_X)


def bosu_squat_pose(hip, t, reach, h=None):
    s = shoulder(hip, t)
    g = (s[0] + reach[0], s[1] + reach[1])
    return body(hip, t, h=h, ankN=BS_ANK, ankF=(BS_ANK[0] - 4, BS_ANK[1]), gN=g, gF=(g[0] - 3, g[1] + 2), eN=-1,
                eF=-1)


BSQ = ins([
    bosu_squat_pose((198, 152 - BOSU_H), -90, (5, 80)),
    bosu_squat_pose((182, 188 - BOSU_H), -78, (60, 20)),
    bosu_squat_pose((168, 216 - BOSU_H), -64, (78, 4), h=-72),
], "tr")


# -- BOSU push-up: hands on the platform edges, body straight from heels to head
BP_X = 272


def bosu_push_scene(doc, j, layer):
    if layer == "back":
        art.floor(doc, -60, 460)
        art.shadow(doc, 170, 110)
        bosu(doc, BP_X + 2)


def plank_on(arm, wrist, toe_y=GROUND - 1):
    """Rigid push-up body with the hands pinned at `wrist`: solve the torso angle so the toes touch the floor."""
    lo, hi = -60.0, 40.0
    for _ in range(40):
        t = (lo + hi) / 2
        pose = P(t=t, h=t, lN=(t + 180, t + 180, 80), lF=(t + 180, t + 180, 80), aN=arm, aF=arm,
                 pin=("wristN", wrist))
        y = art.F.place(pose)["toeN"][1]
        if y < toe_y:
            hi = t
        else:
            lo = t
    return pose


BP_W = (BP_X, GROUND - BOSU_H - 4)
BPU = ins([plank_on((90, 90, 0), BP_W), plank_on((138, 72, 0), BP_W), plank_on((186, 58, 0), BP_W)], "tl")


# ---- registry -----------------------------------------------------------------------------------------

SCENES.update({
    "sandbag-squat": (sb_squat_scene, SBS, fit(SBS)),
    "sandbag-shouldering": (sh_scene, SHO, fit(SHO, (190, GROUND - 30, 240, GROUND),
                                              lambda j: [(j["shoulder"][0] - 26, j["shoulder"][1] - 30,
                                                          j["shoulder"][0] + 22, j["shoulder"][1])])),
    "sandbag-lunge": (sb_lunge_scene, SBL, fit(SBL)),
    "slider-leg-curl": (slc_scene, SLC, fit(SLC, (MAT[0], GROUND - 4, MAT[1], GROUND))),
    "slider-lateral-lunge": (slat_scene, SLAT, fit(SLAT)),
    "slider-reverse-lunge": (srl_scene, SRL, fit(SRL)),
    "bosu-squat": (bosu_squat_scene, BSQ, fit(BSQ, (BOSU_X - BOSU_R, GROUND - BOSU_H, BOSU_X + BOSU_R, GROUND))),
    "bosu-push-up": (bosu_push_scene, BPU, fit(BPU, (BP_X + 2 - BOSU_R, GROUND - BOSU_H, BP_X + 2 + BOSU_R, GROUND))),
})
