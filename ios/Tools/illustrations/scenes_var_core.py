"""Scenes for the #174 catalog extension (core): core variations, carries, power, cardio and mobility.

Same conventions as scenes.py (figure faces right, angles 0 = right, 90 = down, floor surface art.GROUND).
Built from the existing scene modules: the hanging, plank, carry and front-view helpers of scenes_arms_core,
the IK pose builder B() of scenes_power, the floor solvers rest() / reach() and the 4:3 view fitting of
scenes_mobility. New equipment (stability ball, trap bar carried, sled straps, ...) is drawn here.
"""
import math

import art
import kit
import scenes_arms_core as AC
import scenes_mobility as MO
import scenes_power as PW
import scenes_upper as UP
from art import GROUND
from poses import P

F = art.F
MAT = MO.MAT
FOOT_Y = GROUND - 4
lerp, lerp2, tween = MO.lerp, MO.lerp2, MO.tween
rest, reach, joints = MO.rest, MO.reach, MO.joints


def E(scene, poses, boxes=(), corner=None, view=None, margin=8):
    """Scene entry with a fitted 4:3 view and the muscle-map inset in a free corner."""
    return MO.entry(scene, poses, boxes, (), corner, margin, view)


def floor_scene(cx=200, rx=110, mat=None, back=None, front=None):
    def scene(doc, j, layer):
        if layer == "back":
            art.floor(doc, -160, art.W + 160)
            art.shadow(doc, cx, rx)
            if mat:
                kit.mat(doc, *mat)
            if back:
                back(doc, j)
        elif front:
            front(doc, j)
    return scene


SCENES = {}


def add(ex_id, e):
    SCENES[ex_id] = e


# ---- hanging leg raise: straight legs to hip height (knee raise has bent knees) -----------------------------

add("hanging-leg-raise", (AC.hang_scene, [
    AC.hang(),
    AC.hang(t=-94, h=-90, legs=((40, 40, -44), (43, 43, -41)), curl=2, arm=-82),
    AC.hang(t=-104, h=-92, legs=((-6, -6, -86), (-3, -3, -83)), curl=6, arm=-76),
], (0, -30, 400)))


# ---- bicycle crunch: shoulders curled up, hands behind the head, legs alternate ------------------------------

def _behind_head(p):
    j = joints(p)
    hd = j["head"]
    p = reach(p, "aN", (hd[0] + 3, hd[1] + 6), end=None, pick=lambda m: -m[1])
    return reach(p, "aF", (hd[0] + 1, hd[1] + 7), end=None, pick=lambda m: -m[1])


def _bicycle(side):
    tuck, long_ = (-62, 4, -70), (-14, -14, -98)
    legs = {"lN": tuck, "lF": long_} if side == "N" else {"lN": long_, "lF": tuck}
    p = P(t=202, h=214, curl=5, aN=(-150, 20), aF=(-150, 20), **legs)
    p = rest(p, "hip", 214, MAT, ("torso",))
    return _behind_head(p)


def _bicycle_mid():
    p = P(t=196, h=208, curl=4, lN=(-40, 0, -80), lF=(-36, -4, -84), aN=(-150, 20), aF=(-150, 20))
    p = rest(p, "hip", 214, MAT, ("torso",))
    return _behind_head(p)


add("bicycle-crunch", E(floor_scene(200, 130, mat=(40, 350)), [_bicycle("N"), _bicycle_mid(), _bicycle("F")],
                        [(40, MAT, 350, GROUND)]))


# ---- V-up: from flat, arms overhead, fold to a V balanced on the hips -----------------------------------------

def _vup(k):
    t = lerp(180, 242, k)
    leg = lerp(0, -64, k)
    p = P(t=t, h=t + lerp(0, 10, k), curl=lerp(0, 6, k), lN=(leg, leg, leg - 90 + 30 * k),
          lF=(leg + 1, leg + 1, leg - 89 + 30 * k), aN=(180, 180, 180), aF=(182, 182, 182))
    p = rest(p, "hip", 206, MAT)
    if k == 0:
        return p
    j = joints(p)
    s = j["shoulder"]
    if k < 1:  # arms swinging up over the face
        return dict(p, aN=(-100, -100, -100), aF=(-98, -98, -98))
    tgt = lerp2(j["kneeN"], j["ankleN"], 0.55)
    a = MO._ang((tgt[0] - s[0], tgt[1] - s[1]))
    return dict(p, aN=(a, a, a), aF=(a + 2, a + 2, a + 2))


add("v-up", E(floor_scene(200, 130, mat=(40, 360)), [_vup(0), dict(_vup(0.5)), _vup(1)], [(40, MAT, 360, GROUND)]))


# ---- dragon flag: shoulders on the bench, hands gripping it behind the head, straight body lowered -------------

DF = dict(x0=56, x1=250, top=226)
DF_SH = (122, DF["top"] - 11)


def _dragon(body):
    """`body` = angle of the straight body from the shoulders (deg above horizontal)."""
    t = 180 - body
    leg = -body
    p = P(t=t, h=182, lN=(leg, leg, leg + 6), lF=(leg + 1, leg + 1, leg + 7), aN=(-130, 140), aF=(-130, 140),
          pin=("shoulder", DF_SH))
    p = reach(p, "aN", (DF["x0"] + 6, DF["top"] + 2), end=100, pick=lambda m: -m[1])
    return reach(p, "aF", (DF["x0"] + 4, DF["top"] + 3), end=100, pick=lambda m: -m[1])


def _dragon_scene(doc, j, layer):
    if layer == "back":
        art.floor(doc, -160, art.W + 160)
        art.shadow(doc, 160, 110)
        kit.flat_bench(doc, DF["x0"], DF["x1"], DF["top"])


add("dragon-flag", E(_dragon_scene, [_dragon(76), _dragon(44), _dragon(14)], [(DF["x0"], DF["top"], DF["x1"], GROUND)]))


# ---- L-sit on the dip station ------------------------------------------------------------------------------

LS_Y = 150
LS_GRIP = (206, LS_Y - 5)


def _lsit(legs, t=-86):
    lN, lF = legs
    return P(t=t, h=t - 2, lN=lN, lF=lF, aN=(97, 97, 0), aF=(98, 98, 2), pin=("wristN", LS_GRIP))


def _lsit_scene(doc, j, layer):
    if layer == "back":
        art.floor(doc, -160, art.W + 160)
        art.shadow(doc, 210, 90)
        kit.dip_bars(doc, 150, 262, LS_Y)
    else:
        # Near bar in front of the near hand.
        g = kit.grip(j)
        doc.add(f'<circle cx="{g[0]:.1f}" cy="{g[1] + 1:.1f}" r="3.2" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.8"/>')


add("l-sit", E(_lsit_scene, [
    _lsit(((92, 98, 40), (90, 100, 42)), -90),
    _lsit(((-6, 92, 30), (-4, 94, 32)), -88),
    _lsit(((-2, -2, -40), (0, 0, -38)), -84),
], [(140, LS_Y - 6, 272, GROUND)]))


# ---- Russian twist: seated V, lean back, med ball from hip to hip ------------------------------------------

RT_HIP_X = 200


def _ball_at(c, r=12):
    return lambda doc, j: kit.ball(doc, c(j) if callable(c) else c, r)


def _twist(side):
    """side: +1 ball by the near hip (in front of the body), 0 in front of the chest, -1 by the far hip (behind)."""
    t = -124
    p = P(t=t, h=t + 18 - side * 8, curl=-2, lN=(-38, 42, 10), lF=(-34, 46, 14))
    p = rest(p, "hip", RT_HIP_X, MAT, ("torso",))
    j = joints(p)
    s = j["shoulder"]
    if side == 0:
        c = (s[0] + 40, s[1] + 34)
    else:
        c = (j["hip"][0] + 12 - side * 4, MAT - 22)
    hn, hf = (c[0] + 2, c[1] - 1), (c[0] - 2, c[1] + 1)
    p = reach(p, "aN", hn, end=None, pick=lambda m: m[1] if side else -m[1])
    p = reach(p, "aF", hf, end=None, pick=lambda m: m[1] if side else -m[1])
    ball = _ball_at(lambda j: art.add(PW.hands(j), (5, 0)), 12)
    if side < 0:
        return dict(p, props=[ball])
    return dict(p, front_props=[ball])


add("russian-twist", E(floor_scene(200, 80, mat=(110, 300)),
                       [_twist(1), _twist(0), _twist(-1)], [(110, MAT, 300, GROUND)]))


# ---- cable woodchops (front view: tower on the right, figure side-on to it) ---------------------------------

CH_X = 186
CH_TOWER = 330


def _chop_pose(hands, t, h, pivot=False):
    base = AC.front_stand(CH_X, 14, t=t, h=h)
    if pivot:  # back (tower-side) heel up, knee turned in
        base = dict(base, lN=(base["lN"][0] + 6, base["lN"][1] - 6, 40))
    side = 1 if hands[0] > CH_X + 20 else (-1 if hands[0] < CH_X - 20 else 0)
    bends = (side, side) if side else (1, -1)
    return AC.front_arms(base, (hands[0] + 3, hands[1]), (hands[0] - 3, hands[1] + 1), *bends)


def chop_scene(pulley_y, rest_len):
    def scene(doc, j, layer):
        g = PW.hands(j)
        p = (CH_TOWER - 12, pulley_y)
        if layer == "back":
            art.floor(doc, -160, art.W + 160)
            art.shadow(doc, 220, 120)
            kit.cable_tower(doc, CH_TOWER, pulley_y, AC.cable_lift(g, p, rest_len, 0.25))
        else:
            art.cable(doc, [p, g])
            kit.handle(doc, g)
            for s in "NF":
                h = kit.grip(j, s)
                doc.add(f'<circle cx="{h[0]:.1f}" cy="{h[1]:.1f}" r="4.2" fill="#E2E6EB" stroke="{art.OUTLINE}" '
                        f'stroke-width="0.9"/>')
    return scene


TOWER_BOX = (CH_TOWER - 20, 20, CH_TOWER + 50, GROUND)

add("cable-woodchop", E(chop_scene(44, 70), [
    _chop_pose((276, 82), -84, -78),
    _chop_pose((200, 150), -90, -94),
    _chop_pose((134, 214), -98, -104, pivot=True),
], [TOWER_BOX]))

add("cable-low-high-chop", E(chop_scene(GROUND - 26, 70), [
    _chop_pose((268, 222), -82, -76),
    _chop_pose((200, 150), -90, -92),
    _chop_pose((132, 70), -97, -102, pivot=True),
], [TOWER_BOX]))


# ---- bird dog: quadruped, opposite arm and leg long ---------------------------------------------------------

def _bird(k):
    arm = lerp(90, -6, k)
    thigh, shin = lerp(90, 182, k), lerp(180, 182, k)
    p = P(t=lerp(2, 0, k), h=lerp(10, -6, k), lN=(90, 180, 180), lF=(thigh, shin, lerp(180, 100, k)),
          aN=(arm, arm, arm if k else 0))
    p = rest(p, "kneeN", 168, MAT, ("thighN", "shinN", "footN"))
    j = joints(p)
    s = j["shoulder"]
    p = reach(p, "aF", (s[0] + 2, MAT - MO.WRIST_UP), end=0)
    if k == 0:
        p = reach(p, "aN", (s[0] + 4, MAT - MO.WRIST_UP), end=0)
    return p


add("bird-dog", E(floor_scene(200, 100, mat=(70, 330)), [_bird(0), _bird(0.5), _bird(1)], [(70, MAT, 330, GROUND)]))


# ---- mountain climber: high plank, knees driven in turn -----------------------------------------------------

MC_WRIST = (284, GROUND - 5)


def _climber(drive, ahead=34, up=18):
    support = "F" if drive == "N" else "N"

    def make(t):
        legs = {"l" + support: (t + 180, t + 180, 84), "l" + drive: (60, 130, 60)}
        return P(t=t, h=t + 4, aN=(92, 92, 0), aF=(93, 93, 0), pin=("wristN", MC_WRIST), **legs)
    p = AC.lie_floor(make, "toe" + support, GROUND - 1, -50, 10)
    j = joints(p)
    # Driving knee under the chest, its foot just off the floor.
    p = reach(p, "l" + drive, (j["hip"][0] + ahead, GROUND - up), end=60, pick=lambda m: m[0])
    return p


def _climber_mid():
    def make(t):
        return P(t=t, h=t + 4, lN=(t + 160, t + 186, 84), lF=(t + 176, t + 168, 84), aN=(92, 92, 0), aF=(93, 93, 0),
                 pin=("wristN", MC_WRIST))
    return AC.lie_floor(make, "toeF", GROUND - 1, -50, 10)


add("mountain-climber", E(floor_scene(200, 120), [
    _climber("N"),
    _climber_mid(),
    _climber("F"),
]))


# ---- RKC plank: elbows walked forward under the eyes, fists together, glutes squeezed (posterior tilt) ------

def _rkc(upper, curl=0, elbow=(262, MAT - 6)):
    def make(t):
        legs = dict(lN=(t + 180, t + 180, 84), lF=(t + 180, t + 180, 84))
        return P(t=t, h=t + 2, curl=curl, aN=(upper, -6, -14), aF=(upper + 2, -4, -12), pin=("elbowN", elbow), **legs)
    return AC.lie_floor(make, "toeN", MAT - 1, -40, 10)


add("rkc-plank", E(AC.mat_scene(50, 330), [_rkc(90), _rkc(68), _rkc(62, curl=4)], [(50, MAT, 330, GROUND)]))


# ---- stir the pot: forearms on a stability ball, plank, small circles ---------------------------------------

SB_R = 38
SB_X = 236


def stability_ball(doc, c, r=SB_R):
    g = doc.lin((c[0] - r, c[1] - r), (c[0] + r * 0.6, c[1] + r), [(0, "#9FB6CC"), (0.45, "#5F7E9C"), (1, "#2C4258")])
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="{g}" stroke="#0A0B0D" stroke-width="1"/>'
            f'<ellipse cx="{c[0] - r * 0.36:.1f}" cy="{c[1] - r * 0.42:.1f}" rx="{r * 0.3:.1f}" ry="{r * 0.18:.1f}" '
            f'fill="#fff" fill-opacity="0.22" transform="rotate(-30 {c[0] - r * 0.36:.1f} {c[1] - r * 0.42:.1f})"/>'
            f'<path d="M{c[0] - r * 0.9:.1f},{c[1] + r * 0.3:.1f} Q{c[0]:.1f},{c[1] + r * 0.62:.1f} {c[0] + r * 0.9:.1f},'
            f'{c[1] + r * 0.3:.1f}" fill="none" stroke="#000" stroke-opacity="0.2" stroke-width="1"/>')


def _stir(off):
    bx = SB_X + off
    top = (bx, GROUND - 2 * SB_R)
    elbow = (bx - 14, top[1] - 4)

    def make(t):
        return P(t=t, h=t + 4, lN=(t + 180, t + 180, 84), lF=(t + 180, t + 180, 84), aN=(90 - off * 1.4, 4, 4),
                 aF=(92 - off * 1.4, 6, 6), pin=("elbowN", elbow))
    p = AC.lie_floor(make, "toeN", GROUND - 1, -50, 10)
    return dict(p, props=[lambda doc, j, c=(bx, GROUND - SB_R): stability_ball(doc, c)])


def _stir_scene(doc, j, layer):
    if layer == "back":
        art.floor(doc, -160, art.W + 160)
        art.shadow(doc, 190, 130)


add("stir-the-pot", E(_stir_scene, [_stir(-14), _stir(0), _stir(14)],
                      [(SB_X - SB_R - 10, GROUND - 2 * SB_R, SB_X + SB_R + 10, GROUND)]))


# ---- dumbbell side bend (front view): dumbbell in the near hand, far hand on the head ----------------------

SBX = 200
BEND = -1


def _side_bend(t):
    base = AC.front_stand(SBX, 8, t=t, h=t + (t + 90) * 0.3, aN=(90, 90, 90))
    j = AC.fplace(base)
    hd = j["head"]
    sf = j["shoulderF"]
    tgt = (hd[0] - 9, hd[1] - 4)
    u, f = AC.ik(sf, tgt, BEND)
    out = dict(base, aF=(u, f, f + 40))
    # Near arm hangs straight down from the shoulder.
    return out


def _side_bend_scene(doc, j, layer):
    if layer == "back":
        art.floor(doc, -160, art.W + 160)
        art.shadow(doc, SBX, 50)
    else:
        art.db_end(doc, kit.grip(j), 11)


add("db-side-bend", E(_side_bend_scene, [_side_bend(-90), _side_bend(-70), _side_bend(-104)],
                      [(SBX - 60, 40, SBX + 80, GROUND)]))


# ---- Turkish get-up: bell locked out overhead from lying to tall sit to standing ---------------------------

TGU_HIP = (196, MAT)


def _tgu(stage):
    up = (-90, -90, -90)
    if stage == 0:
        p = P(t=180, h=180, lN=(-52, 54, 0), lF=(0, 0, -86), aN=up, aF=(170, 170, 170))
        p = rest(p, "hip", TGU_HIP[0], MAT, ("torso", "thighF", "shinF", "head"))
        p = reach(p, "lN", (TGU_HIP[0] + 66, FOOT_Y), end=0, pick=lambda m: -m[1])
        return p
    if stage == 1:
        t = -132
        p = P(t=t, h=t + 30, lN=(-52, 54, 0), lF=(0, 0, -86), aN=up, aF=(120, 120, 0))
        p = rest(p, "hip", TGU_HIP[0], MAT, ("torso", "thighF", "shinF"))
        j = joints(p)
        p = reach(p, "lN", (j["hip"][0] + 66, FOOT_Y), end=0, pick=lambda m: -m[1])
        p = reach(p, "aF", (j["shoulder"][0] - 22, MAT - MO.WRIST_UP), end=180, pick=lambda m: m[0])
        return p
    return P(t=-90, h=-90, lF=(92, 88, 0), aN=up, aF=(88, 90), pin=("ankleN", (TGU_HIP[0] + 12, FOOT_Y)))


def _tgu_scene(doc, j, layer):
    if layer == "back":
        art.floor(doc, -160, art.W + 160)
        art.shadow(doc, 200, 110)
        kit.mat(doc, 60, 320)
    else:
        AC.kb_overhead(doc, kit.grip(j), 11)


add("turkish-get-up", E(_tgu_scene, [_tgu(0), _tgu(1), _tgu(2)], [(60, MAT, 320, GROUND)]))


# ---- trap bar carry: hex bar at the sides, plates level with the knees ------------------------------------

import scenes_lower as LO  # noqa: E402

add("trap-bar-carry", (LO.trap_bar_scene, [
    AC.grounded(AC.stride("N", **AC.carry_arms()), AC.CARRY_X),
    AC.grounded(AC.passing("F", **AC.carry_arms()), AC.CARRY_X),
    AC.grounded(AC.stride("F", **AC.carry_arms()), AC.CARRY_X),
], (40, 22, 330)))


# ---- kettlebell front-rack carry: two bells racked at the chest, walking ----------------------------------

RACK_ARM_N, RACK_ARM_F = (74, -78, -66), (70, -80, -68)


def rack_bell(doc, j, side="N", r=11):
    """Kettlebell in the front rack: handle in the fist, bell resting on the outside of the forearm."""
    w, e = j["wrist" + side], j["elbow" + side]
    g = kit.grip(j, side)
    d = art.norm(art.sub(e, w))
    nrm = (d[1], -d[0]) if d[1] > 0 else (-d[1], d[0])
    if nrm[0] > 0:
        nrm = (-nrm[0], -nrm[1])
    bell = art.add(art.add(w, d, 10), nrm, r - 2)
    grad = doc.lin((bell[0] - r, bell[1] - r), (bell[0] + r, bell[1] + r), [(0, "#4A5058"), (0.5, "#24282D"), (1, "#101214")])
    doc.add(f'<path d="M{g[0] + 2:.1f},{g[1] - 2:.1f} Q{g[0] - 6:.1f},{g[1] - 10:.1f} {bell[0]:.1f},{bell[1] - r + 1:.1f}" '
            f'fill="none" stroke="#1A1D21" stroke-width="3.6"/>')
    doc.add(f'<circle cx="{bell[0]:.1f}" cy="{bell[1]:.1f}" r="{r}" fill="{grad}" stroke="#08090A" stroke-width="0.9"/>')


def _rack_carry_scene(doc, j, layer):
    if layer == "back":
        AC.floor_back(doc, AC.CARRY_X, 70)
        rack_bell(doc, j, "F")
    else:
        rack_bell(doc, j, "N")


add("front-rack-carry", (_rack_carry_scene, [
    AC.grounded(AC.stride("N", aN=RACK_ARM_N, aF=RACK_ARM_F, h=-88), AC.CARRY_X),
    AC.grounded(AC.passing("F", aN=RACK_ARM_N, aF=RACK_ARM_F, h=-88), AC.CARRY_X),
    AC.grounded(AC.stride("F", aN=RACK_ARM_N, aF=RACK_ARM_F, h=-88), AC.CARRY_X),
], (40, 22, 330)))


# ---- backward sled drag: facing the sled, arms long on the straps, walking backwards ------------------------

SD_HOOK = (PW.SLED_X - 6, GROUND - 18)


def _sled_drag_scene(doc, j, layer):
    PW.sled(doc, j, layer)
    for s in ("F",) if layer == "back" else ("N",):
        g = kit.grip(j, s)
        doc.add(f'<line x1="{g[0]:.1f}" y1="{g[1]:.1f}" x2="{SD_HOOK[0]:.1f}" y2="{SD_HOOK[1]:.1f}" stroke="#16181B" '
                f'stroke-width="3.4"/><line x1="{g[0]:.1f}" y1="{g[1]:.1f}" x2="{SD_HOOK[0]:.1f}" y2="{SD_HOOK[1]:.1f}" '
                f'stroke="#E8B32A" stroke-width="1" stroke-dasharray="6 10"/>')
        kit.handle(doc, g)


def _drag(back, plant, hip):
    """`back` = (side, ankle) stepping back onto the ball of the foot, `plant` = the other foot flat."""
    (bs, ba), px = back, plant
    other = "F" if bs == "N" else "N"
    kw = {"ank" + bs: ba, "foot" + bs: 36, "ank" + other: (px, FOOT_Y)}
    return PW.B(hip, -100, wrN=(232, 196), wrF=(230, 197), handN=20, handF=20, h=-96, **kw)


SDRAG = [
    _drag(("N", (122, GROUND - 10)), 184, (160, 176)),
    _drag(("N", (146, FOOT_Y - 2)), 180, (164, 172)),
    _drag(("F", (122, GROUND - 10)), 184, (160, 176)),
]
add("sled-drag", (_sled_drag_scene, SDRAG, PW.fit(SDRAG, (PW.SLED_X - 12, 124, PW.SLED_X + 106, GROUND))))


# ---- power clean: from the floor, jump and shrug, catch in the front rack -----------------------------------

def _clean_floor():
    wr = (203, GROUND - 31)
    t = -32
    sh = (wr[0] + 4, wr[1] - 80)
    hip = art.ang_pt(sh, t + 180, F.TORSO)
    return PW.B(hip, t, ankN=(196, FOOT_Y), ankF=(192, FOOT_Y), wrN=wr, wrF=(wr[0] - 2, wr[1] + 1), h=-46)


PCL = [_clean_floor(), dict(PW.HPC[1]), dict(PW.HPC[2])]
add("power-clean", (PW.clean, PCL, PW.fit(PCL, PW.ball_box(26))))


# ---- push press: dip, drive with the legs, lock out overhead -----------------------------------------------

def _push_press(stage):
    hip0 = UP.ST_HIP
    t = -90
    if stage == 0:  # dip: knees forward, torso upright, bar in the rack
        hip = (hip0[0] + 2, hip0[1] + 16)
        sh = art.ang_pt(hip, t, F.TORSO)
        g = (sh[0] + 18, sh[1] - 4)
        return UP.B(hip, t, aN=UP.G(g, 1), aF=UP.G((g[0] - 4, g[1] - 2), 1),
                    lN=UP.G((hip0[0] + 1, UP.FLOOR_Y), 1, end=0), lF=UP.G((hip0[0] - 3, UP.FLOOR_Y), 1, end=0), h=-96)
    if stage == 1:  # drive: legs extended onto the toes, bar leaving the shoulders past the face
        hip = (hip0[0], hip0[1] - 8)
        sh = art.ang_pt(hip, t, F.TORSO)
        g = (sh[0] + 10, sh[1] - 40)
        return UP.B(hip, t, aN=UP.G(g, 1), aF=UP.G((g[0] - 4, g[1] - 2), 1),
                    lN=UP.G((hip0[0] + 1, UP.FLOOR_Y - 9), -1, end=50), lF=UP.G((hip0[0] - 3, UP.FLOOR_Y - 9), -1, end=50),
                    h=-86, front_props=[PW.arrow((hip0[0] + 44, hip0[1] - 10), -90, 22)])
    sh = art.ang_pt(hip0, t, F.TORSO)
    g = (sh[0] - 2, sh[1] - 81)
    return UP.standing(hip0, t, g, (g[0] - 4, g[1] - 2), 1, stance=(1, -3), h=-88)


add("push-press", UP.S(UP.ohp_scene, [_push_press(0), _push_press(1), _push_press(2)], [(96, 40, 150, GROUND)],
                       UP.held_at("N", 20)))


# ---- dumbbell snatch: from between the feet to lockout in one pull ----------------------------------------

def _db_snatch_scene(doc, j, layer):
    if layer == "back":
        PW.ground(doc, 200, 70)
    else:
        art.db_end(doc, kit.grip(j), 10.5)


DBS = [
    PW.B((150, 196), -18, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), wrN=(196, GROUND - 22), aF=(120, 110), h=-26,
         lit_sides="N"),
    PW.B((198, 146), -92, ankN=(202, GROUND - 10), ankF=(198, GROUND - 10), footN=34, footF=34,
         aN=(-22, -96, -96), aF=(150, 110), h=-90, lit_sides="N"),
    PW.B((198, 152), -90, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(-88, -88, -88), aF=(100, 92), h=-90,
         lit_sides="N"),
]
add("db-snatch", (_db_snatch_scene, DBS, PW.fit(DBS, PW.ball_box(14, 0, 0, "N"))))


# ---- kettlebell clean: hike pass, zip it up close, soft landing in the rack --------------------------------

def _kb_clean_scene(doc, j, layer):
    if layer == "back":
        PW.ground(doc, 200, 70)
        return
    w, h, e = j["wristN"], j["handN"], j["elbowN"]
    if w[1] < e[1] - 10:
        rack_bell(doc, j, "N", 12)
    else:
        PW.kb(doc, kit.grip(j), math.degrees(math.atan2(h[1] - w[1], h[0] - w[0])), 12)


KBC = [
    PW.B((150, 180), -20, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), wrN=(156, 212), aF=(140, 120), h=-26, lit_sides="N"),
    PW.B((198, 150), -92, ankN=(202, FOOT_Y - 4), ankF=(198, FOOT_Y - 4), footN=16, footF=16,
         aN=(132, 4, 70), aF=(110, 100), h=-90, lit_sides="N"),
    PW.B((196, 154), -90, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=RACK_ARM_N, aF=(100, 92), h=-90, lit_sides="N"),
]
add("kb-clean", (_kb_clean_scene, KBC, PW.fit(KBC, PW.ball_box(18, 0, 6, "N"))))


# ---- tuck jump: counter-movement, knees to the chest in the air, soft landing -----------------------------

TUCK = [
    PW.B((182, 174), -60, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(140, 130), aF=(136, 128), h=-70),
    PW.B((200, 112), -80, lN=(-42, 100, 40), lF=(-38, 104, 44), aN=(30, 50), aF=(34, 54), h=-84,
         front_props=[PW.arrow((272, 140), -90)]),
    PW.B((186, 178), -66, ankN=(204, FOOT_Y), ankF=(200, FOOT_Y), aN=(20, 4), aF=(24, 8), h=-74),
]
add("tuck-jump", (PW.basic(200, 50), TUCK, PW.fit(TUCK)))


# ---- med ball scoop toss (front view): scoop from below the back knee, throw up and across ---------------

def _scoop(x, lN, lF, t, h, ball):
    base = AC.front_legs(x, lN, lF, t=t, h=h)
    side = 1 if ball[0] > x + 20 else (-1 if ball[0] < x - 20 else 0)
    bends = (side, side) if side else (1, -1)
    return AC.front_arms(base, (ball[0] + 7, ball[1]), (ball[0] - 7, ball[1]), *bends)


SCOOP = [
    dict(_scoop(196, (58, 104, 0), (124, 86, 180), -106, -112, (146, 222)), front_props=[PW.held_ball(14)]),
    dict(_scoop(200, (70, 96, 0), (114, 88, 180), -92, -92, (204, 196)), front_props=[PW.held_ball(14)]),
    dict(_scoop(206, (80, 90, 0), (118, 104, 150), -80, -74, (262, 86)),
         front_props=PW.flying_ball((292, 58), -40, 14)),
]
add("med-ball-scoop-toss", (PW.rot_throw, SCOOP, PW.fit(SCOOP, (330, 60, 346, GROUND), (276, 40, 312, 76))))


# ---- battle rope alternating waves: half squat, one arm up while the other drives down --------------------

WAVES = [
    PW.B((166, 190), -56, ankN=(194, FOOT_Y), ankF=(188, FOOT_Y), aN=(-10, -26), aF=(44, 30), h=-62),
    PW.B((166, 190), -56, ankN=(194, FOOT_Y), ankF=(188, FOOT_Y), aN=(18, 4), aF=(18, 4), h=-62),
    PW.B((166, 190), -56, ankN=(194, FOOT_Y), ankF=(188, FOOT_Y), aN=(44, 30), aF=(-10, -26), h=-62),
]
add("battle-rope-waves", (PW.ropes, WAVES, PW.fit(WAVES, (PW.ANCHOR[0] - 22, GROUND - 42, PW.ANCHOR[0] + 22, GROUND))))


# ---- burpee: chest to the floor, feet jumped in, jump with the arms overhead -----------------------------

BURPEE = [
    AC.hands_plank((200, 58, 0)),
    PW.B((196, 204), -14, ankN=(214, FOOT_Y), ankF=(210, FOOT_Y), wrN=(270, GROUND - 6), wrF=(268, GROUND - 6),
         handN=0, handF=0, h=-4),
    PW.B((222, 128), -90, ankN=(224, GROUND - 32), ankF=(220, GROUND - 32), footN=66, footF=66,
         aN=(-84, -86), aF=(-88, -90), h=-90, front_props=[PW.arrow((272, 150), -90)]),
]
add("burpee", (PW.basic(210, 110), BURPEE, PW.fit(BURPEE)))


# ---- jumping jacks (front view) -----------------------------------------------------------------------------

JJ_X = 200


def _jack(k):
    spread = lerp(2, 24, k)
    arm = lerp(84, -64, k)
    p = AC.front_legs(JJ_X, (90 - spread, 90 - spread * 0.55, 10), (90 + spread, 90 + spread * 0.55, 170),
                      t=-90, h=-90, aN=(arm, arm - lerp(4, 14, k)), aF=(180 - arm, 180 - arm + lerp(4, 14, k)))
    if 0 < k < 1:  # in the air between the two landings
        n, (x, y) = p["pin"]
        p = dict(p, pin=(n, (x, y - 10)), lN=(p["lN"][0], p["lN"][1], 50), lF=(p["lF"][0], p["lF"][1], 130))
    return p


JJ = [_jack(0), _jack(0.5), _jack(1)]
add("jumping-jacks", (PW.basic(JJ_X, 60), JJ, PW.fit(JJ)))


# ---- high knees: running in place, knee to hip height, on the balls of the feet ----------------------------

HK_HIP = (196, 150)


def _high_knee(drive):
    up = (-6, 92, 40)
    other = "F" if drive == "N" else "N"
    arm_fwd, arm_back = (60, -50, -50), (124, 50, 50)
    kw = {"l" + drive: up, "ank" + other: (HK_HIP[0] + 4, GROUND - 9), "foot" + other: 48,
          "a" + drive: arm_back, "a" + other: arm_fwd}
    return PW.B(HK_HIP, -88, h=-88, **kw)


HKN = [
    _high_knee("N"),
    PW.B((HK_HIP[0], HK_HIP[1] + 2), -88, ankN=(HK_HIP[0] + 8, GROUND - 9), ankF=(HK_HIP[0], GROUND - 9), footN=48,
         footF=48, aN=(92, 10, 10), aF=(96, 14, 14), h=-88),
    _high_knee("F"),
]
add("high-knees", (PW.basic(200, 50), HKN, PW.fit(HKN)))


# ---- foam rolling ------------------------------------------------------------------------------------------

FR_R = 12


def settle_on(pose, seg, x, y_top, band=5):
    """Move the figure vertically so the lowest outline point of segment `seg` near x sits on y_top."""
    name, (px, py) = pose["pin"]
    pts = [q for q in MO.segments(pose)[seg].outline(30) if abs(q[0] - x) < band]
    low = max(q[1] for q in pts)
    return dict(pose, pin=(name, (px, py + y_top - low)))


FRQ_X = 196


def _roll_quads(u):
    a = 176  # thighs run back from the hip, slightly down to the toes
    hx = FRQ_X + u * F.THIGH
    p = P(t=-8, h=-14, lN=(a, a - 2, 100), lF=(a - 2, a - 4, 98), aN=(90, -2, 0), aF=(92, 0, 2), pin=("hip", (hx, 200)))
    p = settle_on(p, "thighN", FRQ_X, GROUND - 2 * FR_R)
    hip = p["pin"][1]
    # Torso angle so the elbows (under the shoulders) rest on the floor.
    dy = (GROUND - 6 - F.UPPER_ARM) - hip[1]
    t = math.degrees(math.asin(max(-1, min(1, dy / F.TORSO))))
    return dict(p, t=t, h=t - 6)


def _roller_at(c):
    return lambda doc, j: kit.foam_roller(doc, c, FR_R)


add("foam-roll-quads", E(floor_scene(200, 120, back=_roller_at((FRQ_X, GROUND - FR_R))),
                         [_roll_quads(0.25), _roll_quads(0.5), _roll_quads(0.78)],
                         [(FRQ_X - FR_R, GROUND - 2 * FR_R, FRQ_X + FR_R, GROUND)]))


FRC_X = 254


def _roll_calves(u):
    a, b = 8, 2  # thigh, shin: legs long, near calf on the roller
    hx = FRC_X - F.THIGH * math.cos(math.radians(a)) - u * F.SHIN
    t = -132
    p = P(t=t, h=t + 34, lN=(a, b, -70), lF=(a - 5, b - 14, -84), aN=(110, 110, 0), aF=(112, 112, 0),
          pin=("hip", (hx, 220)))
    p = settle_on(p, "shinN", FRC_X, GROUND - 2 * FR_R)
    j = joints(p)
    s = j["shoulder"]
    p = reach(p, "aN", (s[0] - 18, GROUND - MO.WRIST_UP), end=180, pick=lambda m: m[0])
    return reach(p, "aF", (s[0] - 20, GROUND - MO.WRIST_UP), end=180, pick=lambda m: m[0])


add("foam-roll-calves", E(floor_scene(190, 110, back=_roller_at((FRC_X, GROUND - FR_R))),
                          [_roll_calves(0.72), _roll_calves(0.5), _roll_calves(0.24)],
                          [(FRC_X - FR_R, GROUND - 2 * FR_R, FRC_X + FR_R, GROUND)]))


# ---- standing quad stretch: heel to the glute, knees together ----------------------------------------------

def _quad_stretch(k):
    thigh = lerp(90, 108, k)
    shin = lerp(90, 248, k)
    p = P(t=-90, h=-90, curl=lerp(0, -2, k), lF=(90, 90, 0), lN=(thigh, shin, shin - lerp(90, 60, k)),
          aN=(90, 90), aF=(lerp(90, 8, k), lerp(90, 0, k)), pin=("ankleF", (200, FOOT_Y)), lit_sides="N")
    if k == 0:
        return p
    j = joints(p)
    a = j["ankleN"]
    return reach(p, "aN", (a[0] - 2, a[1] - 1), end=None, pick=lambda m: -m[0])


add("standing-quad-stretch", E(floor_scene(200, 50), [_quad_stretch(0), _quad_stretch(0.5), _quad_stretch(1)]))


# ---- seated forward fold: legs long, hinge from the hips, hands to the feet --------------------------------

def _fold(k):
    t = lerp(-90, -24, k)
    p = P(t=t, h=t + lerp(0, 14, k), curl=lerp(0, 4, k), lN=(0, 0, -84), lF=(1, 1, -83),
          aN=(-80, -82), aF=(-78, -80))
    p = rest(p, "hip", 150, MAT, ("torso", "thigh", "shin", "foot"))
    j = joints(p)
    if k == 0:
        return p
    toe = j["toeN"]
    tgt = lerp2((j["shoulder"][0] + 70, j["shoulder"][1] - 6), (toe[0] - 6, toe[1] + 10), k)
    pick = (lambda m: m[1]) if k == 1 else (lambda m: -m[1])
    p = reach(p, "aN", tgt, end=-70 if k == 1 else None, pick=pick)
    return reach(p, "aF", (tgt[0] - 2, tgt[1] + 1), end=-70 if k == 1 else None, pick=pick)


add("seated-forward-fold", E(floor_scene(190, 100, mat=(90, 300)), [_fold(0), _fold(0.5), _fold(1)],
                             [(90, MAT, 300, GROUND)]))


# ---- lizard stretch: deep lunge, hands inside the front foot, back knee down -------------------------------

LZ_FOOT = 252


def _lizard(hip, t, forearms=False):
    hx, hy = hip
    dy = (MAT - 7) - hy
    a = 180 - math.degrees(math.asin(max(-1, min(1, dy / F.THIGH))))
    p = P(t=t, h=t + 6, lF=(a, 182, 120), lN=(-10, 90, 0), aN=(90, 90, 0), aF=(90, 90, 0), pin=("hip", hip))
    p = reach(p, "lN", (LZ_FOOT, MAT - 4), end=0, pick=lambda m: -m[1])
    j = joints(p)
    s = j["shoulder"]
    if forearms:
        d = (MAT - 6) - s[1]
        ex = s[0] + math.sqrt(max(0, F.UPPER_ARM ** 2 - d * d))
        u = math.degrees(math.atan2(d, ex - s[0]))
        return dict(p, aN=(u, 0, 0), aF=(u + 2, 2, 2))
    p = reach(p, "aN", (LZ_FOOT - 4, MAT - MO.WRIST_UP), end=0)
    return reach(p, "aF", (LZ_FOOT - 7, MAT - MO.WRIST_UP), end=0)


add("lizard-stretch", E(floor_scene(200, 110, mat=(70, 330)), [
    _lizard((196, 212), -32),
    _lizard((186, 226), -24),
    _lizard((180, 232), -10, forearms=True),
], [(70, MAT, 330, GROUND)]))
