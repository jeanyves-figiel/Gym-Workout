"""Scenes for the realistic exercise art (#168): arms, core, carries and forearm work.

Same conventions as scenes.py: each scene pins one joint so static equipment stays still across frames;
held weights follow the figure's joints. Angles as in poses.py (0 = right, 90 = down; figure faces right).
"""
import math

import art
import kit
from art import GROUND
from poses import P

MAT_Y = GROUND - 4  # top of an exercise mat


# ---- helpers -----------------------------------------------------------------------------------

def place(pose):
    return art.F.place(pose)


def bisect(f, lo, hi, n=40):
    """Root of a monotonic f on [lo, hi]."""
    flo = f(lo)
    for _ in range(n):
        mid = (lo + hi) / 2
        if (f(mid) > 0) == (flo > 0):
            lo, flo = mid, f(mid)
        else:
            hi = mid
    return (lo + hi) / 2


def ang(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def ik(shoulder, target, bend=1, l1=art.F.UPPER_ARM, l2=art.F.FOREARM):
    """Two-bone arm reaching `target` with the wrist: (upper, fore) angles. bend=+1 elbow below/behind."""
    d = min(l1 + l2 - 0.01, max(abs(l1 - l2) + 0.01, kit.dist(shoulder, target)))
    base = ang(shoulder, target)
    a = math.degrees(math.acos((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
    upper = base + bend * a
    elbow = art.ang_pt(shoulder, upper, l1)
    return upper, ang(elbow, target)


def leg_ik(hip, target, bend=-1):
    return ik(hip, target, bend, art.F.THIGH, art.F.SHIN)


def grounded(pose, x, toe_lift=2):
    """Pin the hip at x and drop the figure so its lowest foot stands on the floor (walking poses)."""
    j = place(dict(pose, pin=("hip", (x, 0))))
    low = max(max(j["ankleN"][1], j["toeN"][1] + toe_lift), max(j["ankleF"][1], j["toeF"][1] + toe_lift))
    return dict(pose, pin=("hip", (x, GROUND - 4 - low)))


def stand(x=200, **kw):
    return P(pin=("ankleN", (x, GROUND - 4)), **kw)


def shoulder_of(pose):
    """Shoulder position of a pose (pin applied) — the base for arm IK."""
    return place(pose)["shoulder"]


def arms_to(pose, target_n, target_f=None, bend=1, hand=None):
    """Return pose with both arms reaching their targets (side view: shared shoulder)."""
    s = shoulder_of(pose)
    out = dict(pose)
    for side, tgt in (("N", target_n), ("F", target_f or target_n)):
        u, f = ik(s, tgt, bend)
        out["a" + side] = (u, f) if hand is None else (u, f, hand)
    return out


def lie_floor(make, joint, y, lo, hi):
    """Solve the free parameter of make(p) so that `joint` sits at height y."""
    p = bisect(lambda v: place(make(v))[joint][1] - y, lo, hi)
    return make(p)


def floor_back(doc, cx=200, rx=120):
    art.floor(doc)
    art.shadow(doc, cx, rx)


def tower(doc, x, pulley_y, lift=0, face="left", w=34, top=24):
    """Cable column like kit.cable_tower, but the pulley can sit on either face ("left"/"right").
    Returns the pulley centre."""
    if face == "left":
        return kit.cable_tower(doc, x, pulley_y, lift, w, top)
    # Mirror: column on the right edge of the stack, figure works to the right of it.
    x1 = x  # column x
    art.tube(doc, (x1 + 4, GROUND - 2), (x1 + 4, top), 9)
    art.shroud(doc, x1 - w - 10, top + 30, GROUND - 4, w + 8)
    st = art.stack(doc, x1 - w - 6, top + 44, GROUND - 4, w, 12, lift)
    art.tube(doc, (x1 - w - 14, top), (x1 + 8, top), 8)
    art.pulley(doc, (st[0], top + 7), 5.5)
    art.cable(doc, [(st[0] - 5.5, top + 7), st])
    p = (x1 + 12, pulley_y)
    art.tube(doc, (x1 + 4, pulley_y), (p[0] - 2, pulley_y), 5)
    art.pulley(doc, p, 6)
    return p


def cable_lift(g, p, rest, k=0.35):
    """Plates rise with the cable paid out beyond its rest length."""
    return max(0.0, (kit.dist(g, p) - rest) * k)


def db_hold(doc, j, side="N", r=10, neutral=False):
    """Dumbbell in a hand: end-on (pronated / supinated) or seen lengthwise (neutral grip)."""
    g = kit.grip(j, side)
    if neutral:
        fa = ang(j["elbow" + side], j["wrist" + side])
        art.db_side(doc, g, fa + 90, r * 0.9)
    else:
        art.db_end(doc, g, r)


# ---- planks ------------------------------------------------------------------------------------

def mat_scene(x0, x1, cx=None, rx=None):
    def scene(doc, j, layer):
        if layer == "back":
            floor_back(doc, cx or (x0 + x1) / 2, rx or (x1 - x0) / 2)
            kit.mat(doc, x0, x1)
    return scene


def forearm_plank(elbow=(258, MAT_Y - 6), knees=False, **kw):
    """Forearm plank on the mat: elbow under the shoulder, body straight to the toes (or knees)."""
    def make(t):
        if knees:
            legs = dict(lN=(t + 180, 186, 180), lF=(t + 180, 186, 180))
        else:
            legs = dict(lN=(t + 180, t + 180, 84), lF=(t + 180, t + 180, 84))
        return P(t=t, h=t + 4, aN=(90, 0, 0), aF=(92, 2, 2), pin=("elbowN", elbow), **legs, **kw)
    if knees:
        return lie_floor(make, "kneeN", MAT_Y - 7, -40, 10)
    return lie_floor(make, "toeN", MAT_Y - 1, -40, 10)


# ---- dead bug / hollow / crunches on the back --------------------------------------------------

SUPINE_Y = MAT_Y - 15  # hip centre of a figure lying on its back on the mat


def dead_bug_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, 200, 140)
        kit.mat(doc, 50, 350)


# ---- ab wheel ----------------------------------------------------------------------------------

WHEEL_R = 12


def ab_wheel_pose(thigh, t, knee=(130, MAT_Y - 7), **kw):
    def make(a):
        return P(t=t, h=t + 8, lN=(thigh, 180, 180), lF=(thigh, 182, 182), aN=(a, a, a), aF=(a + 2, a + 2, a + 2),
                 pin=("kneeN", knee), **kw)
    # Arms straight; solve their angle so the hands sit on the wheel axle.
    return lie_floor(lambda a: make(a), "wristN", GROUND - WHEEL_R - 4, -20, 90)


def ab_wheel_scene(doc, j, layer):
    g = kit.grip(j)
    c = (g[0], GROUND - WHEEL_R)
    if layer == "back":
        floor_back(doc, 200, 140)
        kit.mat(doc, 60, 160)
        kit.ab_wheel(doc, c, WHEEL_R)


# ---- front / back views ------------------------------------------------------------------------

def fplace(pose):
    """Joints as drawn in a front/back view (limbs shifted sideways)."""
    return art.frontal(place(pose))


def front_pin(pose, joint, target):
    """Pin `joint` where it is DRAWN in a front/back view (frontal() shifts limbs after pinning)."""
    pj = "hip" if joint in ("hipN", "hipF", "shoulderN", "shoulderF") else joint
    p = dict(pose, pin=(pj, target))
    j = fplace(p)
    d = (target[0] - j[joint][0], target[1] - j[joint][1])
    return dict(pose, pin=(pj, (target[0] + d[0], target[1] + d[1])))


# ---- TRX body saw ------------------------------------------------------------------------------

TRX_ANCHOR = (52, -40)


def body_saw_pose(upper, elbow=(262, MAT_Y - 6), ankle_y=GROUND - 44):
    def make(t):
        return P(t=t, h=t + 4, lN=(t + 180, t + 180, 70), lF=(t + 180, t + 180, 70), aN=(upper, 0, 0),
                 aF=(upper + 2, 2, 2), pin=("elbowN", elbow), inset="tr")
    return lie_floor(make, "ankleN", ankle_y, -40, 20)


def body_saw_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, 200, 130)
        kit.mat(doc, 160, 330)
        kit.strap(doc, j["ankleF"], TRX_ANCHOR, handle=False)
    else:
        for side in "N":
            a, t = j["ankle" + side], j["toe" + side]
            kit.strap(doc, a, TRX_ANCHOR, handle=False)
            # Foot cradle round the heel/instep.
            doc.add(f'<path d="M{a[0] - 3:.1f},{a[1] - 5:.1f} Q{a[0] + 6:.1f},{a[1] + 9:.1f} {(a[0] + t[0]) / 2 + 3:.1f},'
                    f'{(a[1] + t[1]) / 2:.1f}" fill="none" stroke="#16181B" stroke-width="4.4" stroke-linecap="round"/>')


# ---- Pallof press ------------------------------------------------------------------------------

PALLOF_X = 196


def pallof_pose(reach):
    base = stand(PALLOF_X, t=-90, lN=(78, 102, 0), lF=(100, 84, 0), inset="br")
    s = shoulder_of(base)
    tgt = (s[0] + 18 + reach, s[1] + 26 - reach * 0.12)
    return arms_to(base, tgt, (tgt[0] - 2, tgt[1] + 1), bend=1, hand=0)


def pallof_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor_back(doc, 190, 120)
        p = (172, 108)
        lift = cable_lift(g, p, 46, 0.3)
        tower(doc, 160, 108, lift, face="right")
        art.cable(doc, [p, g])
    else:
        kit.handle(doc, g)


# ---- side plank (front view) -------------------------------------------------------------------

def side_plank_pose(hips_up, elbow=(282, MAT_Y - 7)):
    """Side plank seen from the front, on the near (lower) forearm; top arm to the ceiling."""
    def make(t):
        legs = (t + 180, t + 180, t + 170) if hips_up else (178, 180, 172)
        top = (-90, -90) if hips_up else (t + 172, t + 186)
        pose = P(front=True, t=t, h=t, lN=legs, lF=legs, aN=(90, 0, 0), aF=top, inset="tl")
        return front_pin(pose, "elbowN", elbow)
    if hips_up:
        t = bisect(lambda v: fplace(make(v))["ankleN"][1] - (MAT_Y - 6), -40, 0)
    else:
        t = bisect(lambda v: fplace(make(v))["hipN"][1] - (MAT_Y - 12), -60, 0)
    return make(t)


# ---- landmine rotation (front view) ------------------------------------------------------------

LM_X = 200
LM_ANCHOR = (LM_X, GROUND - 4)


def front_stand(x=LM_X, wide=0, **kw):
    """Standing front view, feet under the hips, centred on x."""
    kw.setdefault("front", True)
    base = P(lN=(86 - wide, 92 - wide / 2, 10), lF=(94 + wide, 88 + wide / 2, 170), **kw)
    j = fplace(dict(base, pin=("hip", (x, 0))))
    low = max(j["ankleN"][1], j["ankleF"][1])
    return dict(base, pin=("hip", (x, GROUND - 4 - low)))


def front_arms(pose, tn, tf, bend_n=-1, bend_f=1):
    """Front view: aim each arm's wrist at its target (shoulders sit either side of the torso)."""
    j = fplace(pose)
    out = dict(pose)
    out["aN"] = ik(j["shoulderN"], tn, bend_n)
    out["aF"] = ik(j["shoulderF"], tf, bend_f)
    return out


def landmine_pose(side, t=-90):
    base = front_stand(LM_X, 6, t=t, h=t + side * 6)
    if side == 0:
        tgt = (LM_X, 66)
        bends = (1, -1)
    else:
        tgt = (LM_X + side * 62, 156)
        bends = (side, side)
    return front_arms(base, (tgt[0] + 3, tgt[1]), (tgt[0] - 3, tgt[1]), *bends)


def landmine_rot_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, LM_X, 90)
    else:
        g = ((j["wristN"][0] + j["wristF"][0]) / 2, (j["wristN"][1] + j["wristF"][1]) / 2)
        kit.landmine(doc, g, LM_ANCHOR)
        for s in "NF":
            h = kit.grip(j, s)
            doc.add(f'<circle cx="{h[0]:.1f}" cy="{h[1]:.1f}" r="4.4" fill="#E2E6EB" stroke="{art.OUTLINE}" stroke-width="0.9"/>')


# ---- hanging core work -------------------------------------------------------------------------

BAR = (196, -14)


def hang(t=-90, h=None, legs=((94, 104, 70), (92, 108, 72)), arm=-86, **kw):
    """Hanging from the bar (end-on), wrists pinned under it, arms straight."""
    return P(t=t, h=t + 8 if h is None else h, lN=legs[0], lF=legs[1], aN=(arm, arm - 2, -90), aF=(arm - 2, arm - 4, -92),
             pin=("wristN", (BAR[0], BAR[1] + 5)), **kw)


def hang_scene(doc, j, layer):
    if layer == "back":
        art.floor(doc)
        art.shadow(doc, BAR[0], 60)
        kit.pullup_bar(doc, BAR, top=-60)
    else:
        doc.add(f'<circle cx="{BAR[0]:.1f}" cy="{BAR[1]:.1f}" r="4.6" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
                f'<circle cx="{BAR[0]:.1f}" cy="{BAR[1]:.1f}" r="1.8" fill="{art.CHROME}"/>')


# ---- cable crunch ------------------------------------------------------------------------------

CC_KNEE = (150, GROUND - 8)
CC_TOWER = 314


def kneel(t, h, curl=0, knee=CC_KNEE, **kw):
    return P(t=t, h=h, curl=curl, lN=(90, 180, 178), lF=(92, 181, 179), pin=("kneeN", knee), **kw)


def cable_crunch_pose(t, h, curl=0):
    base = kneel(t, h, curl)
    j = place(base)
    # Hands hold the rope beside the head, just under the ears.
    hd = art.norm(art.sub(j["head"], j["neck"]))
    nrm = (hd[1], -hd[0])  # towards the face
    tgt = art.add(art.add(j["neck"], hd, 2), nrm, 9)
    return arms_to(base, tgt, (tgt[0] - 1, tgt[1] + 1), bend=1, hand=ang(j["neck"], j["head"]))


def cable_crunch_scene(doc, j, layer):
    g = kit.grip(j)
    p = (CC_TOWER - 12, 40)
    if layer == "back":
        floor_back(doc, 210, 130)
        kit.mat(doc, 90, 200)
        kit.cable_tower(doc, CC_TOWER, 40, max(0.0, (g[1] - 128) * 0.3))
    else:
        art.cable(doc, [p, (g[0], g[1] - 6)])
        kit.handle(doc, g, "rope")


# ---- lying on the back -------------------------------------------------------------------------

def supine_scene(x0, x1):
    return mat_scene(x0, x1)


# ---- carries -----------------------------------------------------------------------------------

def stride(lead="N", **kw):
    """Walking side view: `lead` leg forward at heel strike, the other pushing off."""
    front, back = (70, 92, -8), (110, 122, 66)
    legs = {"l" + lead: front, "l" + ("F" if lead == "N" else "N"): back}
    return P(**dict(legs, **kw))


def passing(stance="N", **kw):
    legs = {"l" + stance: (90, 90, 0), "l" + ("F" if stance == "N" else "N"): (76, 118, 40)}
    return P(**dict(legs, **kw))


CARRY_X = 196


def farmer_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, CARRY_X, 70)
        art.db_end(doc, kit.grip(j, "F"), 12)
    else:
        art.db_end(doc, kit.grip(j), 12.5)


def carry_arms(**kw):
    return dict(aN=(92, 90, 90), aF=(88, 90, 90), **kw)


def suitcase_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, CARRY_X, 70)
    else:
        kit.kettlebell(doc, kit.grip(j), r=12)


def kb_overhead(doc, g, r=11):
    """Kettlebell pressed overhead: handle in the fist, bell resting on the back of the forearm."""
    bell = (g[0] - r - 2, g[1] + 7)
    grad = doc.lin((bell[0] - r, bell[1] - r), (bell[0] + r, bell[1] + r), [(0, "#4A5058"), (0.5, "#24282D"), (1, "#101214")])
    doc.add(f'<path d="M{g[0] - 3:.1f},{g[1] + 5:.1f} Q{g[0] - 4:.1f},{g[1] - 7:.1f} {g[0] - 10:.1f},{g[1] - 6:.1f} '
            f'Q{bell[0] - 4:.1f},{bell[1] - 12:.1f} {bell[0]:.1f},{bell[1] - r + 2:.1f}" fill="none" stroke="#1A1D21" stroke-width="3.6"/>')
    doc.add(f'<circle cx="{bell[0]:.1f}" cy="{bell[1]:.1f}" r="{r}" fill="{grad}" stroke="#08090A" stroke-width="0.9"/>')


def overhead_carry_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, CARRY_X, 70)
    else:
        kb_overhead(doc, kit.grip(j))


# ---- curls -------------------------------------------------------------------------------------

def curl_scene(kind="end", r=10, plate=0):
    """Standing curl: kind 'end' (dumbbell end-on), 'neutral' (hammer grip, lengthwise) or 'bar'."""
    def scene(doc, j, layer):
        if layer == "back":
            floor_back(doc, 200, 40)
            if kind != "bar":
                db_hold(doc, j, "F", r, kind == "neutral")
        else:
            if kind == "bar":
                kit.barbell(doc, kit.grip(j), plate)
            else:
                db_hold(doc, j, "N", r + 0.5, kind == "neutral")
    return scene


def curl_poses(x=200, hand0=None, hand1=None, **kw):
    a0 = (92, 86) if hand0 is None else (92, 86, hand0)
    a1 = (88, -60) if hand1 is None else (88, -60, hand1)
    f0 = (96, 88) if hand0 is None else (96, 88, hand0 + 2)
    f1 = (92, -56) if hand1 is None else (92, -56, hand1 + 4)
    return [P(aN=a0, aF=f0, lF=(92, 88, 0), pin=("ankleN", (x, GROUND - 4)), **kw),
            P(aN=a1, aF=f1, lF=(92, 88, 0), pin=("ankleN", (x, GROUND - 4)), **kw)]


def cable_curl_scene(doc, j, layer):
    g = kit.grip(j)
    p = (288, GROUND - 22)
    if layer == "back":
        floor_back(doc, 220, 110)
        kit.cable_tower(doc, 300, p[1], cable_lift(g, p, 128, 0.35))
        art.tube(doc, (300 - 4, GROUND - 2), (240, GROUND - 2), 6)
    else:
        art.cable(doc, [p, g])
        kit.handle(doc, g)


def pushdown_scene(doc, j, layer):
    g = kit.grip(j)
    p = (288, 40)
    if layer == "back":
        floor_back(doc, 220, 110)
        kit.cable_tower(doc, 300, p[1], cable_lift(g, p, 85, 0.35))
    else:
        art.cable(doc, [p, g])
        kit.handle(doc, g)


OHT_PULLEY = (112, 66)


def oh_triceps_scene(doc, j, layer):
    g = kit.grip(j)
    if layer == "back":
        floor_back(doc, 180, 130)
        tower(doc, 100, OHT_PULLEY[1], cable_lift(g, OHT_PULLEY, 96, 0.3), face="right")
        art.cable(doc, [OHT_PULLEY, g])
    else:
        kit.handle(doc, g, "rope")


# ---- push-up family ----------------------------------------------------------------------------

def hands_plank(arm, curl=0, h_off=0, wrist=(276, GROUND - 5)):
    """Push-up body on the hands: solve the torso angle so the toes touch the floor."""
    def make(t):
        return P(t=t, h=t + h_off, curl=curl, lN=(t + 180, t + 180, 80), lF=(t + 180, t + 180, 80), aN=arm, aF=arm,
                 pin=("wristN", wrist))
    return lie_floor(make, "toeN", GROUND - 1, -60, 20)


def floor_scene(cx=190, rx=120):
    def scene(doc, j, layer):
        if layer == "back":
            floor_back(doc, cx, rx)
    return scene


# ---- seated forearm work -----------------------------------------------------------------------

SEAT = dict(x0=96, x1=196, top=226)
SEAT_HIP = (140, SEAT["top"] - 13)


def seated_forearm_pose(hand, fore=-4, **kw):
    """Seated on a flat bench, forearm resting along the near thigh, wrist just past the knee."""
    legs = dict(lN=(-5, 95, 0), lF=(-3, 93, 0))
    j0 = place(P(pin=("hip", SEAT_HIP), **legs))
    knee = j0["kneeN"]
    wrist = (knee[0] + 18, knee[1] - 13)
    elbow = art.ang_pt(wrist, fore + 180, art.F.FOREARM)

    def make(t):
        return P(t=t, h=-36, pin=("hip", SEAT_HIP), **legs, **kw)
    t = bisect(lambda v: kit.dist(shoulder_of(make(v)), elbow) - art.F.UPPER_ARM, -95, -30)
    base = make(t)
    u = ang(shoulder_of(base), elbow)
    return dict(base, aN=(u, fore, fore + hand), aF=(u + 3, fore + 2, fore + hand))


def seated_scene(extra=None):
    def scene(doc, j, layer):
        if layer == "back":
            floor_back(doc, 170, 90)
            kit.flat_bench(doc, SEAT["x0"], SEAT["x1"], SEAT["top"])
        if extra:
            extra(doc, j, layer)
    return scene


def _rev_wrist_db(doc, j, layer):
    if layer == "front":
        art.db_end(doc, kit.grip(j), 9.5)


CURL_CH = 1000.0  # pose channel: a tiny `curl` (invisible) carries a per-frame value to the scene


def channel(j):
    """Read (and clear) the value a pose passed through its tiny curl."""
    v = j["_curl"] * CURL_CH
    j["_curl"] = 0
    return v


def _prosup_db(doc, j, layer):
    th = channel(j) if layer == "back" else j.get("_prosup", 0)
    j["_prosup"] = th
    g = kit.grip(j)
    L, r = 30, 10
    c = math.cos(math.radians(th))
    s = abs(math.sin(math.radians(th)))
    top = (g[0], g[1] - L * c)
    toward = th < 0
    if layer == "back":
        kit.arc(doc, (g[0], g[1] - 6), 30, -140, -40)
    if (layer == "front") == toward or layer == "front" and abs(th) < 1:
        art.tube(doc, (g[0], g[1] + 5), top, 3.6)
        grad = doc.lin((top[0] - r, top[1]), (top[0] + r, top[1]), [(0, "#4A5058"), (0.5, "#24282D"), (1, "#121417")])
        doc.add(f'<ellipse cx="{top[0]:.1f}" cy="{top[1]:.1f}" rx="{r}" ry="{max(4.5, r * s + 3):.1f}" fill="{grad}" '
                f'stroke="#08090A" stroke-width="0.9"/>')
        if s > 0.5:
            doc.add(f'<circle cx="{top[0]:.1f}" cy="{top[1]:.1f}" r="{r * 0.36:.1f}" fill="{art.CHROME}" '
                    f'stroke="#7D8794" stroke-width="0.8"/>')
    if layer == "front":
        # Short end below the fist.
        doc.add(f'<rect x="{g[0] - 8:.1f}" y="{g[1] + 4:.1f}" width="16" height="6" rx="2" fill="#1D2125" '
                f'stroke="#08090A" stroke-width="0.8"/>')


def oh_db_scene(doc, j, layer):
    """One dumbbell held vertically, both palms under the top plate."""
    if layer == "back":
        floor_back(doc, 200, 50)
        g = kit.grip(j)
        art.db_side(doc, (g[0], g[1] + 15), 90, 11, 17)


# ---- side-lying work (front / back views) ------------------------------------------------------

def bench_end(doc, cx, top, w=34, t=12):
    """Flat bench seen end-on: pad cross-section on its post and foot."""
    art.tube(doc, (cx, top + t), (cx, GROUND - 2), 8, "butt")
    kit.feet(doc, cx - 22, cx + 22)
    g = doc.box_grad([(0, art.PAD[0]), (0.25, art.PAD[1]), (1, art.PAD[2])])
    doc.add(f'<rect x="{cx - w / 2:.1f}" y="{top:.1f}" width="{w}" height="{t}" rx="{t * 0.42:.1f}" fill="{g}" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>')


CPH_BENCH = (92, 206)  # end-on bench centre x, pad top
CPH_ANKLE = (CPH_BENCH[0] + 4, CPH_BENCH[1] - 6)


def copenhagen_pose(up, elbow=(296, MAT_Y - 7)):
    def make(t):
        pose = P(front=True, t=t, h=t, aN=(90, 0, 0), aF=(t + 174, t + 186), lN=(t + 180, t + 180, t + 175),
                 lF=(t + 180, t + 180, t + 175), inset="tl")
        return front_pin(pose, "elbowN", elbow)
    if up:
        t = bisect(lambda v: fplace(make(v))["ankleF"][1] - CPH_ANKLE[1], -30, 20)
        return make(t)  # bottom leg lifted alongside the top one
    p = make(-16)
    j = fplace(p)
    tf = leg_ik(j["hipF"], CPH_ANKLE, -1)
    hn = j["hipN"]
    a = 180 - math.degrees(math.asin(max(-1, min(1, (MAT_Y - 7 - hn[1]) / 110))))
    return dict(p, lF=tf + (tf[1] - 5,), lN=(a, a, a - 5))


def copenhagen_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, 200, 140)
        kit.mat(doc, 140, 340)
        bench_end(doc, *CPH_BENCH)


SLR_BENCH = dict(x0=90, x1=290, top=196)


def slr_pose(theta):
    """Side-lying external rotation from behind: top forearm angle theta (90 down .. -90 up), drawn foreshortened."""
    pose = P(front="back", t=0, h=-2, lN=(178, 178, 172), lF=(178, 178, 172), aN=(-12, 196, 190), aF=(180, theta, theta),
             inset="tr", lit_sides="F")
    return front_pin(pose, "hipN", (172, SLR_BENCH["top"] - 6))


def slr_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, 200, 130)
        kit.flat_bench(doc, SLR_BENCH["x0"], SLR_BENCH["x1"], SLR_BENCH["top"])
        # The forearm turns about the upper arm, towards the camera: draw its projection.
        e = j["elbowF"]
        th = math.radians(ang(e, j["wristF"]))
        k = math.sin(th)
        j["wristF"] = (e[0] + 2, e[1] + max(5, abs(k) * art.F.FOREARM) * (1 if k >= 0 else -1))
        j["handF"] = (j["wristF"][0], j["wristF"][1] + max(4, abs(k) * art.F.HAND) * (1 if k >= 0 else -1))
    else:
        e = j["elbowF"]
        # Rolled towel between elbow and ribs.
        doc.add(f'<ellipse cx="{e[0] + 6:.1f}" cy="{e[1] + 8:.1f}" rx="9" ry="5" fill="#E9E4D8" stroke="#8C877B" stroke-width="0.8"/>')
        art.db_side(doc, kit.grip(j, "F"), 0, 8, 14)


# ---- incline curl / lying triceps ------------------------------------------------------------

INC = dict(seat_x0=150, seat_x1=214, seat_top=208, back_len=100, back_ang=-122)


def incline_curl_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, 190, 100)
        kit.incline_bench(doc, **INC)
        db_hold(doc, j, "F", 10)
    else:
        db_hold(doc, j, "N", 10.5)


def incline_pose(fore):
    return P(t=INC["back_ang"] + 4, h=INC["back_ang"] + 44, lN=(-2, 74, 0), lF=(2, 78, 4), aN=(92, fore),
             aF=(94, fore + 3), pin=("hip", (INC["seat_x0"] + 10, INC["seat_top"] - 13)), inset="tr")


FB = dict(x0=96, x1=226, top=222)
FB_HIP = (210, FB["top"] - 15)


def lying_pose(fore, upper=-100, **kw):
    return P(t=177, h=180, lN=(-4, 92, 0), lF=(0, 88, 4), aN=(upper, fore), aF=(upper - 2, fore - 2),
             pin=("hip", FB_HIP), inset="tr", **kw)


def lying_tri_scene(kind):
    def scene(doc, j, layer):
        if layer == "back":
            floor_back(doc, 170, 120)
            kit.flat_bench(doc, FB["x0"], FB["x1"], FB["top"])
            if kind == "db":
                db_hold(doc, j, "F", 9.5, True)
        else:
            if kind == "db":
                db_hold(doc, j, "N", 10, True)
            else:
                kit.barbell(doc, kit.grip(j), 20)
    return scene


# ---- back-view hinge (reverse fly) -------------------------------------------------------------

UPPER_BODY = ("shoulder", "shoulderN", "shoulderF", "neck", "head", "elbowN", "elbowF", "wristN", "wristF", "handN", "handF")


def foreshorten_trunk(j, k=0.72, head_drop=6):
    """Back/front view of a trunk hinged towards/away from the camera: shorten it (everything above the hips
    drops) so the hinge reads even though the view is frontal."""
    dy = (j["hip"][1] - j["shoulder"][1]) * (1 - k)
    for name in UPPER_BODY:
        x, y = j[name]
        j[name] = (x, y + dy + (head_drop if name in ("neck", "head") else 0))


def reverse_fly_scene(doc, j, layer):
    if layer == "back":
        foreshorten_trunk(j)
        floor_back(doc, 200, 60)
    else:
        for s in "NF":
            art.db_end(doc, kit.grip(j, s), 10)


def reverse_fly_pose(lift):
    a = 90 - lift
    b = 8 * lift / 86  # slight elbow bend as the arms open
    base = front_stand(200, 4, front="back", t=-90, h=-90, aN=(a, a + b, a + b), aF=(180 - a, 180 - a - b, 180 - a - b))
    return base


# ---- plate-loaded crunch -----------------------------------------------------------------------

CR_HIP = (150, 202)
CR_PIVOT = (132, 150)


def crunch_machine_pose(t, h, curl=0):
    base = P(t=t, h=h, curl=curl, lN=(-12, 88, 0), lF=(-10, 90, 2), pin=("hip", CR_HIP), inset="tr")
    j = place(base)
    hd = art.norm(art.sub(j["head"], j["neck"]))
    nrm = (hd[1], -hd[0])
    tgt = art.add(art.add(j["neck"], hd, 6), nrm, 10)
    return arms_to(base, tgt, (tgt[0] - 1, tgt[1] + 1), bend=1, hand=ang(j["neck"], j["head"]))


def crunch_machine_scene(doc, j, layer):
    g = kit.grip(j)
    lever = art.norm(art.sub(g, CR_PIVOT))
    la = math.degrees(math.atan2(lever[1], lever[0]))
    horn = art.ang_pt(CR_PIVOT, la + 160, 46)
    if layer == "back":
        floor_back(doc, 170, 110)
        kit.feet(doc, 70, 270)
        # Seat post, seat, backrest column + pad, foot-roller post.
        art.tube(doc, (150, 220), (150, GROUND - 2), 9, "butt")
        art.pad(doc, (118, 216), (194, 216), 12)
        art.tube(doc, (108, GROUND - 2), (112, 112), 10)
        art.pad(doc, (124, 214), (116, 140), 12)
        art.tube(doc, (150, 236), (238, 236), 7)
        art.tube(doc, (236, 236), (236, GROUND - 2), 7, "butt")
        art.tube(doc, (112, CR_PIVOT[1]), CR_PIVOT, 8)
        # Lever: plate horn behind the pivot, arm up to the handles.
        art.tube(doc, CR_PIVOT, horn, 7)
        art.plate(doc, horn, 20)
        art.tube(doc, CR_PIVOT, art.add(g, lever, -4), 6)
        doc.add(f'<circle cx="{CR_PIVOT[0]}" cy="{CR_PIVOT[1]}" r="6" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
                f'<circle cx="{CR_PIVOT[0]}" cy="{CR_PIVOT[1]}" r="2.2" fill="{art.CHROME}"/>')
    else:
        kit.handle(doc, g)
        kit.roller_pad(doc, (j["ankleN"][0] + 6, j["ankleN"][1] - 12), 8)


# ---- shrugs (back view) -----------------------------------------------------------------------

SHRUG_X = 200


def shrug(j, v):
    """Elevate the shoulder girdle by v (0..1): arms and shoulder caps rise, the head sinks a little."""
    up = 12 * v
    for name in ("shoulderN", "shoulderF", "elbowN", "elbowF", "wristN", "wristF", "handN", "handF"):
        j[name] = (j[name][0], j[name][1] - up)
    # Trunk top rises under a fixed head: the neck shortens, the traps bunch.
    j["shoulder"] = (j["shoulder"][0], j["shoulder"][1] - up * 0.7)


def shrug_pose(v, **kw):
    pose = front_stand(SHRUG_X, 6, front="back", curl=v / CURL_CH, **kw)
    return pose


def barbell_shrug_scene(doc, j, layer):
    if layer == "back":
        shrug(j, channel(j))
        floor_back(doc, SHRUG_X, 110)
        g = kit.grip(j)
        y = g[1]
        x0, x1 = SHRUG_X - 118, SHRUG_X + 118
        art.tube(doc, (x0, y), (x1, y), 4.5)
        for x, sgn in ((x0 + 10, -1), (x1 - 10, 1)):
            art.tube(doc, (x - sgn * 14, y), (x - sgn * 14, y), 9)
            grad = doc.box_grad([(0, "#3A3F46"), (0.5, "#1B1E22"), (1, "#0E1012")], vertical=False)
            doc.add(f'<rect x="{x - 6:.1f}" y="{y - 27:.1f}" width="12" height="54" rx="3" fill="{grad}" stroke="#08090A" '
                    f'stroke-width="0.9"/>')
            doc.add(f'<rect x="{x - sgn * 9 - 2.5:.1f}" y="{y - 6:.1f}" width="5" height="12" rx="1.5" fill="{art.CHROME}"/>')


def db_shrug_scene(doc, j, layer):
    if layer == "back":
        shrug(j, channel(j))
        floor_back(doc, SHRUG_X, 60)
    else:
        for s in "NF":
            art.db_end(doc, kit.grip(j, s), 11)


# ---- seated torso rotation (front view) -------------------------------------------------------

ROT_X, ROT_HIP_Y = 200, 192


def rot_pose(phi):
    pose = P(front=True, t=-90, h=-90, curl=phi / CURL_CH, lN=(80, 96, 60), lF=(100, 84, 120),
             aN=(110, 180), aF=(70, 0))
    return front_pin(pose, "hip", (ROT_X, ROT_HIP_Y))


def rot_scene(doc, j, layer):
    if layer == "back":
        phi = math.radians(channel(j))
        j["_phi"] = phi
        # Thighs point at the camera: draw them short; shins straight down to the floor.
        for s, sx in (("N", 1), ("F", -1)):
            hp = j["hip" + s]
            j["knee" + s] = (hp[0] + sx * 3, hp[1] + 15)
            j["ankle" + s] = (hp[0] + sx * 5, GROUND - 4)
            j["toe" + s] = (hp[0] + sx * 9, GROUND - 2)
        # Upper body turns about the spine: shoulders narrow, hands on the handles swing sideways.
        c = j["shoulder"]
        sw = kit.dist(j["shoulderN"], c)
        for s, sx in (("N", 1), ("F", -1)):
            j["shoulder" + s] = (c[0] + sx * sw * math.cos(phi), j["shoulder" + s][1])
        hy = c[1] + 34
        R, dfw = 26, 34
        for s, sx, bend in (("N", 1, -1), ("F", -1, 1)):
            h = (c[0] + sx * R * math.cos(phi) + dfw * math.sin(phi), hy)
            sh = j["shoulder" + s]
            u, f = ik(sh, h, bend)
            j["elbow" + s] = art.ang_pt(sh, u, art.F.UPPER_ARM)
            j["wrist" + s] = h
            j["hand" + s] = art.ang_pt(h, f - sx * 20, art.F.HAND)
        floor_back(doc, ROT_X, 90)
        # Machine: centre column behind the seat, stack on the right, seat + knee pads.
        kit.feet(doc, ROT_X - 70, ROT_X + 150)
        art.tube(doc, (ROT_X, GROUND - 2), (ROT_X, 40), 12, "butt")
        art.tube(doc, (ROT_X, 44), (ROT_X + 120, 44), 9)
        art.shroud(doc, ROT_X + 92, 70, GROUND - 4, 46)
        top = art.stack(doc, ROT_X + 98, 86, GROUND - 4, 34, 12, abs(math.sin(phi)) * 14)
        art.pulley(doc, (top[0], 52), 6)
        art.cable(doc, [(top[0] + 6, 52), top])
        art.cable(doc, [(ROT_X + 4, 46), (top[0], 46)])
        art.tube(doc, (ROT_X, ROT_HIP_Y + 24), (ROT_X, GROUND - 2), 10, "butt")
    else:
        phi = j["_phi"]
        c = j["shoulder"]
        hy = c[1] + 34
        # Handle bar across the front of the chest, chest pad at its centre.
        a, b = j["wristF"], j["wristN"]
        art.tube(doc, a, b, 6)
        mid = ((a[0] + b[0]) / 2, hy - 6)
        g = doc.box_grad([(0, art.PAD[0]), (0.3, art.PAD[1]), (1, art.PAD[2])])
        w = 30 * (0.55 + 0.45 * math.cos(phi))
        doc.add(f'<rect x="{mid[0] - w / 2:.1f}" y="{mid[1] - 12:.1f}" width="{w:.1f}" height="26" rx="7" fill="{g}" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')
        for s in "NF":
            kit.handle(doc, kit.grip(j, s))
        # Seat front edge + knee pads (fixed, hips still).
        doc.add(f'<rect x="{ROT_X - 34}" y="{ROT_HIP_Y + 14}" width="68" height="11" rx="4" fill="{g}" stroke="#0A0B0D" stroke-width="0.8"/>')
        for sx in (-1, 1):
            x = ROT_X + sx * 27 - 5
            doc.add(f'<rect x="{x:.1f}" y="{ROT_HIP_Y + 18}" width="10" height="34" rx="4" fill="{g}" stroke="#0A0B0D" '
                    f'stroke-width="0.8"/>')
        # Dotted turn path round the trunk.
        y = c[1] + 34
        doc.add(f'<path d="M{c[0] - 58:.1f},{y - 4:.1f} A58,13 0 0 0 {c[0] + 58:.1f},{y - 4:.1f}" fill="none" stroke="#fff" '
                f'stroke-opacity="0.7" stroke-width="2.4" stroke-dasharray="2 6" stroke-linecap="round"/>')


# ---- lying leg raise --------------------------------------------------------------------------

LLR_SH = (FB["x0"] + 42, FB["top"] - 13)


def leg_raise_pose(leg, t, curl=0):
    return P(t=t, h=180, curl=curl, lN=(leg, leg, leg - 70), lF=(leg + 2, leg + 2, leg - 68), aN=(194, 104, 90),
             aF=(196, 106, 92), pin=("shoulder", LLR_SH))


def leg_raise_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, 170, 120)
        kit.flat_bench(doc, FB["x0"], FB["x1"], FB["top"])


# ---- band monster walk (front view) ------------------------------------------------------------

def front_legs(x, lN, lF, **kw):
    kw.setdefault("front", True)
    base = P(lN=lN, lF=lF, **kw)
    j = fplace(dict(base, pin=("hip", (x, 0))))
    low = max(j["ankleN"][1], j["ankleF"][1])
    return dict(base, pin=("hip", (x, GROUND - 4 - low)))


def monster_scene(doc, j, layer):
    if layer == "back":
        floor_back(doc, 200, 90)
    else:
        a = art.add(j["kneeN"], art.norm(art.sub(j["hipN"], j["kneeN"])), 12)
        b = art.add(j["kneeF"], art.norm(art.sub(j["hipF"], j["kneeF"])), 12)
        kit.band(doc, (a[0] + 6, a[1]), (b[0] - 6, b[1]))
        for p, sx in ((a, 1), (b, -1)):
            doc.add(f'<ellipse cx="{p[0]:.1f}" cy="{p[1]:.1f}" rx="{8:.1f}" ry="3.2" fill="none" stroke="#0A0B0D" stroke-width="4.6"/>'
                    f'<ellipse cx="{p[0]:.1f}" cy="{p[1]:.1f}" rx="{8:.1f}" ry="3.2" fill="none" stroke="#2EAD5B" stroke-width="3"/>')


def monster_pose(x, lN, lF):
    return front_legs(x, lN, lF, front="back", t=-90, h=-90, aN=(48, 150, 150), aF=(132, 30, 30))


# ---- finger extensions (hand close-up) ---------------------------------------------------------

OFFSTAGE = ("hip", (3000, 3000))  # the full figure is parked outside the view for the close-up
WRIST_C = (206, 192)


def hand_closeup(spread):
    """Encodes the spread (0..1) in the parked figure's torso angle; the scene draws the hand."""
    return P(t=-90 + spread * 40, pin=OFFSTAGE, inset=None)


def _finger(doc, base, a, length, w):
    seg = art.Seg(base, art.ang_pt(base, a, length), [(0, w, w), (0.55, w * 0.92, w * 0.92), (1, w * 0.78, w * 0.78)])
    d = art.draw_segment(doc, seg, art.SKIN_NEAR)
    clip = doc.clip(d)
    for u in (0.42, 0.74):  # knuckle creases
        a0, a1 = seg.at(u, -0.7), seg.at(u, 0.7)
        doc.add(f'<path d="M{a0[0]:.1f},{a0[1]:.1f} Q{seg.pos(u)[0]:.1f},{seg.pos(u)[1] - 2:.1f} {a1[0]:.1f},{a1[1]:.1f}" '
                f'fill="none" stroke="#000" stroke-opacity="0.16" stroke-width="1" clip-path="{clip}"/>')
    nail = [seg.at(u, v) for u, v in ((0.84, -0.5), (0.84, 0.5), (0.99, 0.45), (0.99, -0.45))]
    doc.add(f'<path d="{art.smooth(nail)}" fill="#FFFFFF" fill-opacity="0.5" stroke="#000" stroke-opacity="0.12" '
            f'stroke-width="0.7" clip-path="{clip}"/>')
    return seg


def finger_scene(doc, j, layer):
    if layer != "back":
        return
    s = max(0.0, min(1.0, (j["_t"] + 90) / 40))
    wx, wy = WRIST_C
    # Forearm from below the frame, extensors (back of the forearm) highlighted.
    fore = art.Seg((wx + 8, 262), (wx, wy + 6), [(0, 36, 36), (0.6, 32, 32), (1, 27, 27)], "up")
    d = art.draw_segment(doc, fore, art.SKIN_NEAR)
    art.draw_muscles(doc, fore, "fore", {"forearmExtensors": art.PRIMARY}, d, False, "back")
    # Thumb (left: right hand seen from the back), then the back of the hand.
    tb = (wx - 22, wy - 22)
    ta = -128 - 22 * s
    thumb = art.Seg(tb, art.ang_pt(tb, ta, 66), [(0, 15, 15), (0.5, 11, 11), (1, 9, 9)])
    art.draw_segment(doc, thumb, art.SKIN_NEAR)
    palm = art.Seg((wx, wy + 4), (wx + 2, wy - 72), [(0, 27, 27), (0.45, 34, 34), (1, 36, 36)], "up")
    art.draw_segment(doc, palm, art.SKIN_NEAR)
    # Tendons on the back of the hand.
    for k in (-0.55, -0.18, 0.18, 0.55):
        a, b = palm.at(0.18, k * 0.5), palm.at(0.95, k)
        doc.add(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="#000" stroke-opacity="0.08" '
                f'stroke-width="2"/>')
    # Fingers: index .. little, together (s=0) or fanned (s=1).
    lens, ws = (84, 92, 86, 70), (9.6, 10, 9.4, 8.4)
    xs = (-26, -9, 9, 25)
    band_pts = [thumb.pos(0.78)]
    for i in range(4):
        base = (wx + 2 + xs[i], wy - 70 + abs(xs[i]) * 0.12)
        a = -90 + (i - 1.5) * (2.5 + 15 * s) + 2
        seg = _finger(doc, base, a, lens[i], ws[i])
        band_pts.append(seg.pos(0.78 - (0.06 if i == 3 else 0)))
    # Band looped round fingers + thumb: stretched (thinner, lighter) as the hand opens.
    bw = 7 - 2.6 * s
    col = "#2EAD5B"
    left, right = band_pts[0], band_pts[-1]
    mid_y = sum(p[1] for p in band_pts[1:]) / 4
    d = (f"M{left[0] - 5:.1f},{left[1]:.1f} Q{(left[0] + right[0]) / 2:.1f},{mid_y + 22:.1f} {right[0] + 6:.1f},{right[1]:.1f}")
    doc.add(f'<path d="{d}" fill="none" stroke="#0A0B0D" stroke-width="{bw + 2:.1f}" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{bw:.1f}" stroke-linecap="round"/>')
    if s > 0.9:
        kit.motion(doc, (left[0] - 14, left[1] - 4), 200, 20)
        kit.motion(doc, (right[0] + 16, right[1] - 4), -20, 20)


# ---- scenes ------------------------------------------------------------------------------------

SCENES = {
    "plank": (mat_scene(60, 330), [
        forearm_plank(knees=True),
        forearm_plank(),
    ], (64, 76, 262)),
    "dead-bug": (dead_bug_scene, [
        P(t=178, h=180, lN=(-90, 0, -80), lF=(-92, -2, -82), aN=(-88, -90), aF=(-92, -94),
          pin=("hip", (222, SUPINE_Y))),
        P(t=178, h=180, lN=(-12, -10, -60), lF=(-92, -2, -82), aN=(-88, -90), aF=(-172, -174),
          pin=("hip", (222, SUPINE_Y))),
    ], (36, 46, 330)),
    "ab-wheel": (ab_wheel_scene, [
        ab_wheel_pose(96, -36),
        ab_wheel_pose(150, -6),
        ab_wheel_pose(164, 3),
    ], (52, 84, 320)),
    "trx-body-saw": (body_saw_scene, [
        body_saw_pose(90),
        body_saw_pose(56),
    ], (30, 50, 300)),
    "pallof-press": (pallof_scene, [
        pallof_pose(0),
        pallof_pose(56),
    ], (50, 18, 340)),
    "side-plank": (mat_scene(50, 340), [
        side_plank_pose(False),
        side_plank_pose(True),
    ], (58, 40, 320)),
    "landmine-rotation": (landmine_rot_scene, [
        landmine_pose(-1, -86),
        landmine_pose(0),
        landmine_pose(1, -94),
    ], (50, 14, 340)),
    "hanging-knee-raise": (hang_scene, [
        hang(),
        hang(t=-100, h=-88, legs=((-12, 88, 10), (-8, 92, 14)), curl=4, arm=-78),
    ], (0, -30, 400)),
    "toes-to-bar": (hang_scene, [
        hang(),
        hang(t=-110, h=-96, legs=((-40, 40, -20), (-36, 44, -16)), curl=5, arm=-70),
        hang(t=-136, h=-112, legs=((-96, -96, -110), (-93, -93, -106)), curl=6, arm=-60),
    ], (0, -30, 400)),
    "cable-crunch": (cable_crunch_scene, [
        cable_crunch_pose(-72, -66),
        cable_crunch_pose(-40, -20, 5),
        cable_crunch_pose(-8, 40, 10),
    ], (50, 14, 340)),
    "hollow-hold": (supine_scene(40, 360), [
        P(t=179, h=180, lN=(2, 2, -50), lF=(2, 2, -52), aN=(181, 181, 181), aF=(182, 182, 182),
          pin=("hip", (214, SUPINE_Y))),
        P(t=196, h=206, curl=7, lN=(-16, -16, -40), lF=(-15, -15, -39), aN=(196, 196, 196), aF=(197, 197, 197),
          pin=("hip", (214, SUPINE_Y))),
    ], (34, 58, 326)),
    "farmer-carry": (farmer_scene, [
        grounded(stride("N", **carry_arms()), CARRY_X),
        grounded(passing("F", **carry_arms()), CARRY_X),
        grounded(stride("F", **carry_arms()), CARRY_X),
    ], (40, 22, 330)),
    "suitcase-carry": (suitcase_scene, [
        grounded(stride("N", aN=(90, 90, 90), aF=(82, 76)), CARRY_X),
        grounded(passing("F", aN=(90, 90, 90), aF=(90, 86)), CARRY_X),
        grounded(stride("F", aN=(90, 90, 90), aF=(98, 94)), CARRY_X),
    ], (40, 22, 330)),
    "cable-curl": (cable_curl_scene, curl_poses(186), (40, 22, 330)),
    "triceps-pushdown": (pushdown_scene, [
        P(t=-80, h=-84, aN=(96, -12), aF=(98, -10), lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4))),
        P(t=-80, h=-84, aN=(94, 84), aF=(96, 86), lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4))),
    ], (40, 22, 330)),
    "overhead-triceps": (oh_triceps_scene, [
        P(t=-66, h=-60, lN=(66, 96, 0), lF=(116, 116, 60), aN=(-58, 150), aF=(-56, 152),
          pin=("ankleN", (210, GROUND - 4)), inset="br"),
        P(t=-66, h=-60, lN=(66, 96, 0), lF=(116, 116, 60), aN=(-40, -34), aF=(-38, -32),
          pin=("ankleN", (210, GROUND - 4)), inset="br"),
    ], (34, 18, 340)),
    "overhead-carry": (overhead_carry_scene, [
        grounded(stride("N", aN=(-88, -90, -90), aF=(84, 96)), CARRY_X),
        grounded(passing("F", aN=(-88, -90, -90), aF=(90, 92)), CARRY_X),
        grounded(stride("F", aN=(-88, -90, -90), aF=(96, 88)), CARRY_X),
    ], (4, -26, 396)),
    "hammer-curl": (curl_scene("neutral"), curl_poses(), (40, 22, 330)),
    "push-up-plus": (floor_scene(), [
        hands_plank((150, 40, 0), curl=-2),
        hands_plank((92, 92, 0), curl=-3),
        hands_plank((92, 92, 0), curl=9, h_off=6),
    ], (86, 78, 258)),
    "reverse-wrist-curl": (seated_scene(_rev_wrist_db), [
        seated_forearm_pose(70),
        seated_forearm_pose(-62),
    ], (70, 112, 212)),
    "finger-extensions": (finger_scene, [
        hand_closeup(0),
        hand_closeup(1),
    ], (40, 0, 320)),
    "pronation-supination": (seated_scene(_prosup_db), [
        seated_forearm_pose(0, curl=-70 / CURL_CH),
        seated_forearm_pose(0, curl=0),
        seated_forearm_pose(0, curl=70 / CURL_CH),
    ], (66, 104, 222)),
    "db-overhead-triceps": (oh_db_scene, [
        P(t=-88, h=-84, aN=(-78, 128, 100), aF=(-80, 126, 98), lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4))),
        P(t=-88, h=-84, aN=(-84, 272, 260), aF=(-86, 270, 258), lF=(92, 88, 0), pin=("ankleN", (196, GROUND - 4))),
    ], (8, -24, 392)),
    "reverse-crunch": (mat_scene(40, 330), [
        P(t=180, h=180, lN=(-90, 0, -60), lF=(-88, 2, -58), aN=(4, 2, 2), aF=(6, 4, 4),
          pin=("shoulder", (120, MAT_Y - 13))),
        P(t=160, h=176, curl=8, lN=(-150, -60, -100), lF=(-148, -58, -98), aN=(4, 2, 2), aF=(6, 4, 4),
          pin=("shoulder", (120, MAT_Y - 13))),
    ], (48, 100, 232)),
    "copenhagen-plank": (copenhagen_scene, [
        copenhagen_pose(False),
        copenhagen_pose(True),
    ], (50, 60, 320)),
    "side-lying-external-rotation": (slr_scene, [
        slr_pose(40),
        slr_pose(-30),
        slr_pose(-86),
    ], (34, 74, 300)),
    "barbell-curl": (curl_scene("bar", plate=22), curl_poses(), (40, 22, 330)),
    "incline-db-curl": (incline_curl_scene, [
        incline_pose(88),
        incline_pose(-74),
    ], (56, 52, 296)),
    "barbell-french-press": (lying_tri_scene("bar"), [
        lying_pose(-100),
        lying_pose(-234),
    ], (56, 66, 290)),
    "db-french-press": (lying_tri_scene("db"), [
        lying_pose(-100),
        lying_pose(-234),
    ], (56, 66, 290)),
    "db-reverse-fly": (reverse_fly_scene, [
        dict(reverse_fly_pose(0), inset="bl"),
        dict(reverse_fly_pose(86), inset="bl"),
    ], (46, 36, 310)),
    "diamond-push-up": (floor_scene(), [
        hands_plank((102, 102, 0)),
        hands_plank((136, 76, 0)),
        hands_plank((168, 56, 0)),
    ], (86, 78, 258)),
    "crunch-machine": (crunch_machine_scene, [
        crunch_machine_pose(-98, -86),
        crunch_machine_pose(-74, -50, 5),
        crunch_machine_pose(-50, -10, 9),
    ], (40, 24, 330)),
    "torso-rotation": (rot_scene, [
        rot_pose(-40),
        rot_pose(40),
    ], (60, 20, 330)),
    "barbell-shrug": (barbell_shrug_scene, [
        shrug_pose(0, aN=(88, 90), aF=(92, 90)),
        shrug_pose(1, aN=(88, 90), aF=(92, 90)),
    ], (40, 22, 330)),
    "db-shrug": (db_shrug_scene, [
        shrug_pose(0, aN=(84, 88), aF=(96, 92)),
        shrug_pose(1, aN=(84, 88), aF=(96, 92)),
    ], (40, 22, 330)),
    "reverse-curl": (curl_scene("end"), curl_poses(hand0=86, hand1=-64), (40, 22, 330)),
    "lying-leg-raise": (leg_raise_scene, [
        leg_raise_pose(-2, 180),
        leg_raise_pose(-94, 166, 6),
    ], (50, 60, 300)),
    "monster-walk": (monster_scene, [
        monster_pose(190, (58, 100, 20), (122, 80, 160)),
        monster_pose(198, (40, 92, 10), (122, 80, 160)),
        monster_pose(212, (58, 100, 20), (138, 86, 170)),
    ], (40, 30, 320)),
}
