"""Scenes for the climbing gym exercises (#366): wall warm-up drills, hangboard basics, lift blocks and the
wall cool-down (Exercises+Climbing.swift).

Built on the helpers of scenes_upper.py (B / G pose solver, S framing) and kit.py (hangboard, climbing wall,
lift block). Same conventions: angles 0 = right, 90 = down, the figure faces right in side view; static
equipment in absolute view-box coordinates, held equipment follows the hands.

Where a hand or foot must stay on a hold while the body moves, the scene re-solves that limb onto the hold
(`reach`) in every frame: interpolating joint angles alone would let it drift off.
"""
import math

import art
import kit
import scenes_arms_core as A
import scenes_power as SP
import scenes_upper as U
from art import GROUND
from poses import P

B, G, S = U.B, U.G, U.S
lerp, deg, ik = U.lerp, U.deg, U.ik
TORSO, UPPER, FORE, HAND = U.TORSO, U.UPPER, U.FORE, U.HAND
THIGH, SHIN = U.THIGH, U.SHIN
FLOOR_Y = U.FLOOR_Y
CH = A.CURL_CH  # a tiny `curl` carries a per-frame value to the scene (A.channel)


def floor(doc, cx=200, rx=110):
    U.floor(doc, cx, rx)


def reach(j, limb, target, bend=1, end=None):
    """Re-solve one limb ("aN", "aF", "lN", "lF") so its grip (arm) or ankle (leg) lands on `target`.
    `end` = hand / foot angle (default: the hand continues the forearm, the foot keeps its angle to the shin)."""
    side = limb[1]
    if limb[0] == "a":
        root = j.get("shoulder" + side, j["shoulder"])
        u, f = ik(root, target, UPPER, FORE + HAND / 2, bend)
        e = art.ang_pt(root, u, UPPER)
        w = art.ang_pt(e, f, FORE)
        j["elbow" + side], j["wrist" + side] = e, w
        j["hand" + side] = art.ang_pt(w, f if end is None else end, HAND)
    else:
        root = j.get("hip" + side, j["hip"])
        foot = deg(art.sub(j["toe" + side], j["ankle" + side])) - deg(art.sub(j["ankle" + side], j["knee" + side]))
        flen = math.dist(j["toe" + side], j["ankle" + side])
        u, f = ik(root, target, THIGH, SHIN, bend)
        k = art.ang_pt(root, u, THIGH)
        a = art.ang_pt(k, f, SHIN)
        j["knee" + side], j["ankle" + side] = k, a
        j["toe" + side] = art.ang_pt(a, f + foot if end is None else end, flen)


# ---- hand close-up drawing: open fan ↔ fist (finger ramp) -----------------------------------------------------

FINGER = [(0, 1.9, 1.9), (1, 1.6, 1.6)]


def draw_hand(doc, wrist, ang, s, tones=art.SKIN_NEAR):
    """Hand seen from the thumb side, palm facing the body's midline: s = 1 fingers straight and fanned
    (spread wide), s = 0 rolled into a fist. `ang` = the forearm's direction."""
    d = art.ang_pt((0, 0), ang, 1)
    up = (d[1], -d[0])  # towards the thumb (up for a forward-pointing arm)
    palm_end = art.add(wrist, d, 8.5)
    palm = art.Seg(art.add(wrist, d, -1), palm_end, [(0, 3.6, 3.6), (0.6, 4.7, 4.5), (1, 4.5, 4.3)])
    fingers = []
    # Index (thumb side) .. little finger, two phalanges each. Open: a fan in the plane of the palm; closed: the
    # first phalanx turns down, the second folds back under the palm.
    for i, (fan, ln) in enumerate(((-24, 10.5), (-8, 11.5), (8, 11), (22, 9))):
        base = art.add(art.add(palm_end, d, -1.2), up, (1.5 - i) * 2.1)
        a1 = ang + fan * s + 84 * (1 - s)
        p1 = art.ang_pt(base, a1, ln * (0.5 + 0.06 * (1 - s)))
        a2 = a1 + 96 * (1 - s)
        p2 = art.ang_pt(p1, a2, ln * (0.5 - 0.1 * (1 - s)))
        fingers.append((art.Seg(base, p1, FINGER), art.Seg(p1, p2, [(0, 1.6, 1.6), (1, 1.4, 1.4)])))
    tb = art.add(art.add(wrist, d, 2), up, 3)
    thumb = art.Seg(tb, art.ang_pt(tb, ang - 58 * s - 12 * (1 - s), 8.5 - 1.5 * (1 - s)),
                    [(0, 2.3, 2.3), (1, 1.7, 1.7)])
    for f1, f2 in reversed(fingers):
        art.draw_segment(doc, f2, tones, 0.75)
        art.draw_segment(doc, f1, tones, 0.75)
    art.draw_segment(doc, palm, tones, 0.75)
    art.draw_segment(doc, thumb, tones, 0.75)


def hide_hand(j, side):
    """Shrink the figure's own hand under the drawn one."""
    w, h = j["wrist" + side], j["hand" + side]
    j["hand" + side] = lerp(w, h, 0.35)


# ---- finger & forearm ramp / forearm waves: standing, arms forward ---------------------------------------------

ST_ANK = (196, FLOOR_Y)
UPPER_VIEW = (110, 18, 216)  # chest-up crop: the hands read


def arms_forward(hand=0, s=None, arm=0):
    p = P(t=-90, h=-88, aN=(arm, arm, hand), aF=(arm - 3, arm - 3, hand - 3), lF=(92, 88, 0),
          pin=("ankleN", ST_ANK), inset="bl")
    if s is not None:
        p["curl"] = s / CH
    return p


def ramp_scene(doc, j, layer):
    if layer == "back":
        s = A.channel(j)
        j["_open"] = s
        for side in "NF":
            hide_hand(j, side)
        floor(doc, 200, 50)
        a = deg(art.sub(j["wristF"], j["elbowF"]))
        draw_hand(doc, j["wristF"], a, s, art.SKIN_FAR)
    else:
        a = deg(art.sub(j["wristN"], j["elbowN"]))
        draw_hand(doc, j["wristN"], a, j["_open"])


def waves_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 50)
    else:
        kit.arc(doc, j["wristN"], 16, -50, 50)


# ---- band external rotation: front view, band anchored to a post on the far side --------------------------------

ER_POST = 82


def band_er_scene(doc, j, layer):
    e = j["elbowN"]
    if layer == "back":
        # Foreshorten the forearm: it turns in the horizontal plane at elbow height (as cable-external-rotation).
        phi = deg(art.sub(j["handN"], j["wristN"]))
        j["wristN"] = U._er_point(e, phi, FORE)
        j["handN"] = U._er_point(e, phi, FORE + HAND)
        floor(doc, 160, 120)
        kit.post(doc, ER_POST, 120)
        doc.add(f'<rect x="{ER_POST - 6}" y="{e[1] - 5:.1f}" width="12" height="9" rx="2" fill="#1E2227"/>')
        return
    g = kit.grip(j)
    pts = [U._er_point(e, a, FORE + 8) for a in range(-84, 97, 6)]
    doc.add(f'<path d="{art.smooth(pts, closed=False)}" fill="none" stroke="#fff" stroke-opacity="0.7" '
            f'stroke-width="2.4" stroke-dasharray="2 6" stroke-linecap="round"/>')
    doc.add(f'<rect x="{e[0] - 12:.1f}" y="{e[1] - 13:.1f}" width="7" height="12" rx="2" fill="#EDEFF2" '
            f'stroke="#8A939E" stroke-width="0.7"/>')
    kit.band(doc, (ER_POST + 4, e[1]), g, color="#E8B32A")


# ---- hangboard -------------------------------------------------------------------------------------------------

HB_WALL = 236      # wall face the board is screwed to (the climber faces it)
HB_TOP = -26       # board top
BOARD = kit.hangboard_holds(HB_WALL, HB_TOP)
EDGE, JUG = BOARD["edge"], BOARD["jug"]
HB_LEGS = dict(lN=(80, 148, 124), lF=(86, 154, 130))  # knees bent, feet crossed behind, clear of the floor
REACH = UPPER + FORE + HAND / 2 - 0.5  # shoulder → grip, arm straight
EDGE_END, JUG_END = -64, -38  # hand angle: fingers hooked into the slot / draped over the jug


def palm(tip, end):
    """Grip centre for fingertips on `tip` with the hand at angle `end`."""
    return art.ang_pt(tip, end + 180, HAND / 2)


def hb_hang(sh, t, tip=EDGE, legs=HB_LEGS, h=None, end=EDGE_END, **kw):
    """Hang from the board: fingertips on `tip`, both hands angled up into the hold."""
    g = palm(tip, end)
    hip = art.ang_pt(sh, t + 180, TORSO)
    return B(hip, t, aN=G(g, 1, end=end), aF=G((g[0] - 2, g[1] + 1), 1, end=end), h=t if h is None else h,
             **legs, **kw)


def under(tip, end, dx, dy):
    """Shoulder point relative to the grip centre."""
    g = palm(tip, end)
    return (g[0] + dx, g[1] + dy)


def straight(tip, end, dx):
    """Shoulder `dx` behind the grip with the arm straight."""
    g = palm(tip, end)
    return (g[0] + dx, g[1] + math.sqrt(REACH * REACH - dx * dx))


def engaged(tip, end):
    """Shoulder of the engaged straight-arm hang: blades down and back, the body a few px higher."""
    s0 = straight(tip, end, -4)
    return U.circle_x(palm(tip, end), REACH - 1, (s0[0] - 8, s0[1] - 8), 6, 1)


def board_scene(extra=None):
    def scene(doc, j, layer):
        if layer == "back":
            floor(doc, 196, 50)
            kit.hangboard(doc, HB_WALL, HB_TOP)
        if extra:
            extra(doc, j, layer)
    return scene


def hang_settle(tip=EDGE, end=EDGE_END, legs=HB_LEGS):
    """Passive hang → shoulders engaged, arms straight."""
    s0, s2 = straight(tip, end, -4), engaged(tip, end)
    return [hb_hang(s0, -90, tip, legs, h=-74, end=end),
            hb_hang(lerp(s0, s2, 0.5), -93, tip, legs, h=-84, curl=-3, end=end),
            hb_hang(s2, -96, tip, legs, h=-90, curl=-5, end=end)]


FLOOR_BOX = (150, GROUND - 4, 240, GROUND + 4)
BOARD_BOX = (HB_WALL - kit.HB_D - 4, HB_TOP - 8, HB_WALL + 16, HB_TOP + kit.HB_H + 4)


def belt_plate(doc, j, layer):
    """Max hangs: a plate on a dipping belt, hanging between the thighs (#719: behind the legs, not over them)."""
    if layer == "back":
        belt = U.chest_pt(j["hip"], j["_t"], 0.08, 14)
        c = (j["hip"][0] + 8, j["hip"][1] + 68)
        doc.add(f'<polyline points="{belt[0]:.1f},{belt[1]:.1f} {c[0]:.1f},{c[1] - 12:.1f}" fill="none" '
                f'stroke="#9AA3AD" stroke-width="2" stroke-dasharray="2.5 1.5"/>')
        art.plate(doc, c, 12)


def recruit_poses():
    """From a straight-arm hang, a short hard pull: elbows bend, shoulders down."""
    return [hb_hang(straight(EDGE, EDGE_END, -4), -90, h=-76),
            hb_hang(under(EDGE, EDGE_END, -9, 70), -94, h=-86, curl=-3),
            hb_hang(under(EDGE, EDGE_END, -15, 55), -99, h=-94, curl=-5)]


# Hang ramp: toes on a box behind take part of the weight (legs long, body slightly inclined); then the feet
# come off and the hang is free.
RAMP_BOX = (66, 56, 40)  # x, width, height
RAMP_TOP = GROUND - RAMP_BOX[2] - 4  # ankle height on the box


def ramp_poses():
    s0, s2 = straight(EDGE, EDGE_END, -4), engaged(EDGE, EDGE_END)
    p0 = hb_hang(s0, -90, h=-76)
    hip = art.ang_pt(s0, 90, TORSO)
    legs = B(hip, -90, lN=G((RAMP_BOX[0] + 34, RAMP_TOP), -1), lF=G((RAMP_BOX[0] + 26, RAMP_TOP + 1), -1))
    p0["lN"], p0["lF"] = legs["lN"] + (legs["lN"][1] - 30,), legs["lF"] + (legs["lF"][1] - 30,)
    p2 = hb_hang(s2, -96, h=-90, curl=-5)
    return [p0, art.lerp_pose(p0, p2, 0.5), p2]


def ramp_box(doc, j, layer):
    if layer == "back":
        kit.box(doc, RAMP_BOX[0], RAMP_BOX[1], RAMP_BOX[2])


def repeater_poses():
    """7 s on (hanging, shoulders engaged, feet off the floor) ↔ 3 s off (let go, stand, arms down)."""
    s0 = engaged(EDGE, EDGE_END)
    on = hb_hang(s0, -96, h=-90, curl=-5)
    hip = (s0[0] - 2, FLOOR_Y - THIGH - SHIN + 1)
    off = P(t=-90, h=-82, aN=(76, 64, 64), aF=(82, 70, 70), lN=(88, 90, 0), lF=(92, 92, 4), pin=("hip", hip))
    return [on, art.lerp_pose(on, off, 0.5), off]


# ---- easy traverse: back view on a climbing wall ----------------------------------------------------------------

TW_X0, TW_X1, TW_TOP = -40, 440, -120
HOLDS = {  # name: (centre, radius, colour)
    "hL": ((156, 0), 7, "#FF5A3D"), "hM": ((214, -14), 7, "#2EC5FF"), "hR": ((270, 0), 7, "#FFD23D"),
    "fL": ((168, 234), 6, "#8A4DFF"), "fM": ((214, 226), 6, "#1ED98A"), "fR": ((256, 228), 6, "#FF4DD8"),
}
DECOR = [((70, -10), 6, "#1ED98A"), ((330, -16), 8, "#FF5A3D"), ((84, 96), 7, "#FFD23D"), ((318, 84), 6, "#2EC5FF"),
         ((100, 196), 5, "#FF4DD8"), ((316, 200), 6, "#8A4DFF"), ((120, 40), 5, "#FF8A00"), ((300, 140), 6, "#1ED98A"),
         ((60, 150), 6, "#2EC5FF"), ((350, 40), 5, "#FFD23D")]
TW_HIP0, TW_HIP1 = (178, 134), (218, 132)


def hold(name, dy=0):
    (x, y), r, _ = HOLDS[name]
    return (x, y + dy)


def traverse_pose(hip, t, gn, gf, an, af):
    p = B(hip, t, front="back", aN=G(gn, 1), aF=G(gf, -1), lN=G(an, -1), lF=G(af, 1), inset="tr")
    p["lN"], p["lF"] = p["lN"] + (100,), p["lF"] + (80,)
    return p


def traverse_poses():
    # Start: weight over the left foot, hands on the left and middle holds. End: hips over to the right, the
    # right hand on the right-hand hold, the right foot stepped across to the right foothold.
    return [traverse_pose(TW_HIP0, -88, hold("hM"), hold("hL"), hold("fM", -4), hold("fL", -4)),
            traverse_pose(lerp(TW_HIP0, TW_HIP1, 0.5), -90, (244, -20), hold("hL"), hold("fM", -4), hold("fL", -4)),
            traverse_pose(TW_HIP1, -92, hold("hR"), hold("hL"), hold("fR", -4), hold("fL", -4))]


def traverse_scene(doc, j, layer):
    if layer == "back":
        # Progress from the hips' travel; the left hand and foot stay on their holds every frame, the right hand
        # moves to the next hold in an arc, then the right foot follows.
        k = max(0.0, min(1.0, (j["hip"][0] - TW_HIP0[0]) / (TW_HIP1[0] - TW_HIP0[0])))
        reach(j, "aF", hold("hL"), -1)
        reach(j, "lF", hold("fL", -4), 1)
        q = max(0.0, min(1.0, (k - 0.15) / 0.75))
        gn = lerp(hold("hM"), hold("hR"), q)
        reach(j, "aN", (gn[0], gn[1] - 18 * math.sin(math.pi * q)), 1)
        q = max(0.0, min(1.0, (k - 0.5) / 0.5))
        fn = lerp(hold("fM", -4), hold("fR", -4), q)
        reach(j, "lN", (fn[0], fn[1] - 10 * math.sin(math.pi * q)), -1)
        art.floor(doc)
        kit.climbing_wall(doc, TW_X0, TW_X1, TW_TOP, [(c, r, col) for c, r, col in HOLDS.values()] + DECOR)
        kit.crash_pad(doc, TW_X0 + 10, TW_X1 - 10)


# ---- lift blocks -----------------------------------------------------------------------------------------------

BL_X = 200


def block_pose(v, dip):
    """Back view, standing: the right (near) arm holds the block, the left hand rests on the hip. v = lift (the
    shoulder girdle sets down and back → up), dip = knee bend at the start (the weight rests on a step)."""
    hip = (BL_X, GROUND - 4 - (THIGH + SHIN - 2) + dip)
    an, af = (BL_X + 10, FLOOR_Y), (BL_X - 10, FLOOR_Y)
    p = B(hip, -90, front="back", aN=(70, 77, 86), aF=(96, 94), lN=G(an, -1), lF=G(af, 1), lit_sides="N",
          inset="tl", curl=v / CH)
    p["lN"] = p["lN"] + (40,)
    p["lF"] = p["lF"] + (140,)
    return p


BL_STEP = (222, 40, 38)  # x, width, height of the step the weight rests on


def block_scene(pinch):
    def scene(doc, j, layer):
        if layer == "back":
            A.shrug(j, A.channel(j))
            floor(doc, BL_X, 60)
            kit.box(doc, BL_STEP[0], BL_STEP[1], BL_STEP[2])
        else:
            kit.lift_block(doc, j, pinch=pinch, weight="kb")
    return scene


def block_poses():
    return [block_pose(0, 6), block_pose(0.5, 2), block_pose(1, 0)]


# Pinch block: side view, a suitcase-style lift from the floor to standing.
PB_ANK = (196, FLOOR_Y)


def pinch_poses():
    def f(k):
        hip = (lerp((178, 186), (192, GROUND - 4 - THIGH - SHIN + 1), k))
        t = -62 + (-90 + 62) * k
        g = (lerp((222, GROUND - 46), (206, 186), k))
        return B(hip, t, h=t + 10 * (1 - k), aN=G(g, 1, end=90), aF=(98 + 8 * (1 - k), 96),
                 lN=G(PB_ANK, -1), lF=G((PB_ANK[0] - 6, FLOOR_Y), -1), inset="tr")
    ps = [f(k) for k in (0, 0.5, 1)]
    for p in ps:
        p["lN"] = p["lN"] + (0,)
        p["lF"] = p["lF"] + (0,)
    return ps


def pinch_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 200, 70)
    else:
        kit.lift_block(doc, j, pinch=True, weight="plate")


# ---- wrist flexor floor stretch: quadruped, fingers pointing back, rock the hips back -----------------------------

WF_W, WF_K = (262, GROUND - 6), (172, GROUND - 9)
WRIST_FLOOR = [
    SP.quad(WF_W, WF_K, arm=94, hand=180, inset="tl"),
    SP.quad(WF_W, WF_K, arm=78, hand=180, curl=2, inset="tl"),
    SP.quad(WF_W, WF_K, arm=62, hand=180, curl=4, inset="tl"),
]


def wf_scene(doc, j, layer):
    if layer == "back":
        floor(doc, 210, 110)
        kit.mat(doc, 120, 300)


SCENES = {
    "finger-ramp": (ramp_scene, [arms_forward(0, 1), arms_forward(0, 0.5), arms_forward(0, 0)], UPPER_VIEW),
    "forearm-waves": (waves_scene, [arms_forward(-50), arms_forward(0), arms_forward(50)], UPPER_VIEW),
    "band-external-rotation": S(band_er_scene, U.ext_rot_poses(), [(ER_POST - 24, 110, ER_POST + 24, GROUND)],
                                corner="tr"),
    "hang-ramp": S(board_scene(ramp_box), ramp_poses(),
                   [BOARD_BOX, (RAMP_BOX[0], GROUND - RAMP_BOX[2], RAMP_BOX[0] + RAMP_BOX[1], GROUND)]),
    "recruitment-pulls": S(board_scene(), recruit_poses(), [BOARD_BOX, FLOOR_BOX]),
    "easy-traverse": (traverse_scene, traverse_poses(), (24, -30, 384)),
    "max-hangs": S(board_scene(belt_plate), hang_settle(), [BOARD_BOX, FLOOR_BOX]),
    "repeaters": S(board_scene(), repeater_poses(), [BOARD_BOX, FLOOR_BOX]),
    "open-hand-hang": S(board_scene(), hang_settle(JUG, JUG_END), [BOARD_BOX, FLOOR_BOX]),
    "block-lift": S(block_scene(False), block_poses(), [(BL_STEP[0], GROUND - BL_STEP[2], BL_STEP[0] + BL_STEP[1], GROUND)],
                    lambda j: [((kit.grip(j)[0], kit.grip(j)[1] + 40), 12)]),
    "pinch-block-lift": S(pinch_scene, pinch_poses(), [(150, GROUND - 40, 250, GROUND)]),
    "wrist-flexor-floor": (wf_scene, WRIST_FLOOR, U.fit(WRIST_FLOOR, [(120, GROUND - 4, 300, GROUND)])[1]),
}
