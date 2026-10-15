"""Scenes for the realistic exercise art: power, cardio and warm-up exercises.

Same conventions as scenes.py (figure faces right, 0 = right, 90 = down; floor surface art.GROUND).
Most poses are built with `B()`: the hip (or another joint) is placed in absolute view-box coordinates and
the limbs are solved with two-link IK onto absolute targets (pedals, handles, floor contacts), so the
figure sits exactly on the machine drawn in absolute coordinates. Views are fitted with `fit()` around
every frame of the figure plus the equipment boxes.
"""
import math

import art
import figure as F
import kit
from art import GROUND
from poses import P

TH, SH, UA, FA = F.THIGH, F.SHIN, F.UPPER_ARM, F.FOREARM
FOOT_Y = GROUND - 4  # ankle height of a foot flat on the floor


# ---- pose helpers ------------------------------------------------------------------------------

def ik(a, b, l1, l2, bend=1):
    """Two-link chain a→b: (angle of the first link, angle of the second) in degrees.
    bend=+1 puts the middle joint counter-clockwise of a→b on screen (knee forward for a leg below the hip),
    bend=-1 the other way (elbow down/back for an arm reaching forward)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    d = max(abs(l1 - l2) + 0.01, min(l1 + l2 - 0.01, math.hypot(dx, dy)))
    base = math.atan2(dy, dx)
    alpha = math.acos(max(-1, min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
    a1 = base - bend * alpha
    m = (a[0] + math.cos(a1) * l1, a[1] + math.sin(a1) * l1)
    a2 = math.atan2(b[1] - m[1], b[0] - m[0])
    return math.degrees(a1), math.degrees(a2)


def B(hip, t=-90, ankN=None, ankF=None, wrN=None, wrF=None, footN=0, footF=0, handN=None, handF=None,
      kneeN=1, kneeF=1, elbN=-1, elbF=-1, lN=None, lF=None, aN=None, aF=None, **kw):
    """Pose with the hip pinned at `hip`; limbs given as angles (lN, aN, ...) or solved onto absolute ankle /
    wrist targets (ankN, wrN, ...)."""
    sh = art.ang_pt(hip, t, F.TORSO)
    if ankN:
        lN = ik(hip, ankN, TH, SH, kneeN) + (footN,)
    if ankF:
        lF = ik(hip, ankF, TH, SH, kneeF) + (footF,)
    if wrN:
        a = ik(sh, wrN, UA, FA, elbN)
        aN = a + ((handN if handN is not None else a[1]),)
    if wrF:
        a = ik(sh, wrF, UA, FA, elbF)
        aF = a + ((handF if handF is not None else a[1]),)
    kw.setdefault("pin", ("hip", hip))
    return P(t=t, lN=lN or (90, 90), lF=lF or (90, 90), aN=aN or (90, 90), aF=aF or (90, 90), **kw)


def joints(pose):
    j = F.place(pose)
    if art.view_of(pose) != "side":
        art.frontal(j)
    return j


SEG_R = [("hip", "knee", 15), ("knee", "ankle", 10), ("ankle", "toe", 6), ("shoulder", "elbow", 11),
         ("elbow", "wrist", 8), ("wrist", "hand", 6)]


def body_rects(pose):
    """Small squares covering the figure of one frame (for fitting the view and placing the inset)."""
    j = joints(pose)
    front = art.view_of(pose) != "side"
    out = []


    def seg(a, b, r):
        for i in range(7):
            p = mid(a, b, i / 6)
            out.append((p[0] - r, p[1] - r, p[0] + r, p[1] + r))
    for s in "NF":
        for a, b, r in SEG_R:
            seg(j.get(a + s, j.get(a)), j[b + s], r)
    seg(j["hip"], j["shoulder"], 17 if not front else 22)
    hd = art.norm(art.sub(j["head"], j["neck"]))
    seg(j["shoulder"], art.add(j["neck"], hd, 2 * F.HEAD_R - 2), 13)
    return out, j


def fit(poses, *boxes, m=8, floor=True, corners=("tl", "tr", "bl", "br")):
    """4:3 view around every frame of the figure and the equipment, `m` px margin, as tight as possible
    with the muscle-map inset in a free corner. `boxes` are (x0, y0, x1, y1) or callables j -> [boxes]
    (things that move with the figure). Sets the chosen inset corner on the poses; returns the view."""
    rects = []
    for p in art.frames(poses):
        r, j = body_rects(p)
        rects += r
        for b in boxes:
            rects += b(j) if callable(b) else [b]
    x0 = min(r[0] for r in rects) - m
    y0 = min(r[1] for r in rects) - m
    x1 = max(r[2] for r in rects) + m
    y1 = max(r[3] for r in rects) + m
    if floor:
        y1 = max(y1, GROUND + 3 + m)
    best = None
    for ci, corner in enumerate(corners):
        w = w0 = max(x1 - x0, (y1 - y0) * 4 / 3)
        found = None
        while w < w0 * 1.6:
            h = w * 0.75
            found = None
            for fy in ([1 - i / 8 for i in range(9)] if floor else [.5, .375, .625, .25, .75, .125, .875, 0, 1]):
                for fx in [0.5 + d for d in (0, .0625, -.0625, .125, -.125, .1875, -.1875, .25, -.25, .3125, -.3125,
                                             .375, -.375, .4375, -.4375, .5, -.5)]:
                    vx = x0 - (w - (x1 - x0)) * fx
                    # Spare height goes above the floor by preference (fy = 1: content at the bottom).
                    vy = y0 - (h - (y1 - y0)) * fy
                    pw, ph = 0.2574 * w + 8, 0.27 * w
                    ix = vx + 6 if corner[1] == "l" else vx + w - pw - 6
                    iy = vy + 6 if corner[0] == "t" else vy + h - ph - 6
                    if not any(r[0] < ix + pw + 2 and r[2] > ix - 2 and r[1] < iy + ph + 2 and r[3] > iy - 2
                               for r in rects):
                        found = (vx, vy, w)
                        break
                if found:
                    break
            if found:
                break
            w += 3
        cost = w * (1.0 if corner[0] == "t" else 1.06) * (1 + ci * 0.002)
        if found and (best is None or cost < best[0]):
            best = (cost, corner, found)
    if best is None:  # no free corner: centred view, inset top-left
        w = max(x1 - x0, (y1 - y0) * 4 / 3)
        best = (0, "tl", ((x0 + x1) / 2 - w / 2, (y0 + y1) / 2 - w * 0.375, w))
    _, corner, (vx, vy, w) = best
    for p in poses:
        p["inset"] = corner
    return (round(vx, 1), round(vy, 1), round(w, 1))


def arrow(c, ang, length=24):
    """front_props entry: motion arrow (jumps, throws)."""
    return lambda doc, j: kit.motion(doc, c(j) if callable(c) else c, ang, length)


def ball_box(r, dx=0, dy=0, side=None):
    """fit() box for something of radius r held in the hands (or in one hand)."""
    def f(j):
        c = art.add(grip(j, side) if side else hands(j), (dx, dy))
        return [(c[0] - r, c[1] - r, c[0] + r, c[1] + r)]
    return f


def grip(j, side="N"):
    return kit.grip(j, side)


def mid(a, b, k=0.5):
    return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)


def hands(j):
    """Centre between both hands (a ball or bar held in both)."""
    return mid(grip(j, "N"), grip(j, "F"))


def ground(doc, cx=200, rx=110, x0=16, x1=art.W - 16):
    kit.floor(doc, cx, rx, x0, x1)


def rotated(doc, c, deg, draw):
    doc.add(f'<g transform="rotate({deg:.1f} {c[0]:.1f} {c[1]:.1f})">')
    draw()
    doc.add("</g>")


def kb(doc, c, ang=90, r=11):
    """Kettlebell with its handle at c, the bell hanging in direction `ang` (90 = straight down)."""
    rotated(doc, c, ang - 90, lambda: kit.kettlebell(doc, c, r=r))


def rope_path(doc, pts, w=5.5, color="#2B2F36"):
    d = art.smooth(pts, closed=False)
    doc.add(f'<path d="{d}" fill="none" stroke="#0A0B0D" stroke-width="{w + 1.6}" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="#fff" stroke-opacity="0.12" stroke-width="1.2" stroke-dasharray="3 3"/>')


def housing(doc, d, stops=("#3A414A", "#1E2328"), vertical=True):
    g = doc.box_grad([(0, stops[0]), (1, stops[1])], vertical)
    doc.add(f'<path d="{d}" fill="{g}" stroke="#0A0B0D" stroke-width="0.9" stroke-linejoin="round"/>')


def rect(doc, x, y, w, h, rx=3, stops=("#3A414A", "#1E2328"), vertical=True, op=1):
    g = doc.box_grad([(0, stops[0]), (1, stops[1])], vertical)
    doc.add(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx}" fill="{g}" fill-opacity="{op}" '
            f'stroke="#0A0B0D" stroke-width="0.9"/>')


def screen(doc, x, y, w, h):
    doc.add(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="2" fill="#0E1A22" stroke="#0A0B0D" '
            f'stroke-width="0.8"/><rect x="{x + 2:.1f}" y="{y + 2:.1f}" width="{w - 4:.1f}" height="{h * 0.35:.1f}" rx="1" '
            f'fill="#3FD0FF" fill-opacity="0.35"/>')


def basic(cx=200, rx=110):
    def scene(doc, j, layer):
        if layer == "back":
            ground(doc, cx, rx)
    return scene


# ---- jumps ---------------------------------------------------------------------------------------

BOX = (236, 62, 72)  # x, height, width
BOX_TOP = GROUND - 62 - 4  # ankle height on top of the box


def box_jump(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 120)
        kit.box(doc, BOX[0], BOX[2], BOX[1])


BJ = [
    B((128, 194), -42, ankN=(150, FOOT_Y), ankF=(146, FOOT_Y), aN=(150, 140), aF=(145, 135), h=-50),
    B((196, 132), -66, lN=(-12, 98, 10), lF=(-4, 104, 14), aN=(-50, -40), aF=(-56, -46), h=-70,
      front_props=[arrow((150, 150), -35)]),
    B((240, 122), -58, ankN=(262, BOX_TOP), ankF=(258, BOX_TOP), aN=(10, 0), aF=(14, 4), h=-75),
]


def depth_jump(doc, j, layer):
    if layer == "back":
        ground(doc, 220, 120)
        kit.box(doc, 70, 72, 62)


DJ = [
    B((126, 85), -90, ankN=(128, BOX_TOP), lF=(36, 84, 10), aN=(100, 95), aF=(80, 70), h=-92),
    B((214, 182), -52, ankN=(236, FOOT_Y), ankF=(232, FOOT_Y), aN=(150, 135), aF=(146, 132), h=-62),
    B((236, 124), -86, ankN=(240, 232), ankF=(236, 234), footN=70, footF=70, aN=(-62, -70), aF=(-68, -74),
      h=-88, front_props=[arrow((282, 150), -90)]),
]

BROAD = [
    B((70, 194), -38, ankN=(92, FOOT_Y), ankF=(88, FOOT_Y), aN=(160, 150), aF=(155, 145), h=-45),
    B((190, 150), -55, lN=(112, 118, 40), lF=(120, 132, 50), aN=(-40, -36), aF=(-46, -40), h=-58,
      front_props=[arrow((150, 118), -10)]),
    B((280, 200), -45, ankN=(306, FOOT_Y), ankF=(302, FOOT_Y), aN=(10, 4), aF=(14, 8), h=-58),
]

SQJ = [
    B((182, 174), -60, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(140, 130), aF=(136, 128), h=-70),
    B((198, 142), -86, ankN=(202, GROUND - 14), ankF=(198, GROUND - 14), footN=58, footF=58,
      aN=(-70, -76), aF=(-76, -80), h=-88),
    B((198, 104), -88, ankN=(202, GROUND - 52), ankF=(198, GROUND - 52), footN=70, footF=70,
      aN=(-84, -86), aF=(-88, -90), h=-90, front_props=[arrow((248, 150), -90)]),
]



# Lateral bound, seen from behind: push off the left (screen) leg, land on the right one.
LAT = [
    P(front="back", t=-84, h=-86, lF=(112, 96, 180), lN=(64, 122, 0), aN=(100, 96), aF=(150, 130),
      pin=("ankleF", (132, FOOT_Y))),
    P(front="back", t=-72, h=-76, lF=(128, 136, 200), lN=(52, 68, 0), aN=(-24, 20), aF=(82, 88),
      pin=("hip", (206, 136)), front_props=[arrow((150, 120), 0, 30)]),
    P(front="back", t=-98, h=-94, lN=(76, 94, 0), lF=(118, 52, 160), aN=(40, 70), aF=(150, 120),
      pin=("ankleN", (270, FOOT_Y))),
]


# Trap bar jump: hex bar end-on, plates riding with the hands.
def trap_bar_jump(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 60)
    else:
        kit.trap_bar(doc, grip(j), 26)


TBJ = [
    B((180, 176), -58, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(94, 92), aF=(92, 90), h=-66),
    B((198, 142), -84, ankN=(202, GROUND - 14), ankF=(198, GROUND - 14), footN=58, footF=58,
      aN=(92, 90), aF=(90, 88), h=-86),
    B((198, 112), -86, ankN=(202, GROUND - 46), ankF=(198, GROUND - 46), footN=66, footF=66,
      aN=(92, 90), aF=(90, 88), h=-88, front_props=[arrow((246, 140), -90)]),
]


# ---- throws ------------------------------------------------------------------------------------

def held_ball(r=13, color=("#C0392B", "#7A1E16"), dx=0, dy=0):
    return lambda doc, j: kit.ball(doc, art.add(hands(j), (dx, dy)), r, color)


def flying_ball(c, ang, r=13, color=("#C0392B", "#7A1E16")):
    return [lambda doc, j: kit.ball(doc, c, r, color), arrow(art.ang_pt(c, ang, r + 4), ang, 22)]


WALL_X = 336


def chest_pass(doc, j, layer):
    if layer == "back":
        ground(doc, 190, 80)
        kit.wall(doc, WALL_X, 16)


MBP = [
    B((150, 154), -84, ankN=(156, FOOT_Y), ankF=(148, FOOT_Y), wrN=(176, 102), wrF=(172, 104), handN=-60,
      handF=-60, h=-86, front_props=[held_ball(dx=8)]),
    B((176, 158), -80, ankN=(212, FOOT_Y), ankF=(148, FOOT_Y), wrN=(226, 100), wrF=(222, 102), handN=-40,
      handF=-40, h=-84, front_props=[held_ball(dx=8)]),
    B((186, 160), -78, ankN=(214, FOOT_Y), ankF=(150, FOOT_Y), footF=30, wrN=(276, 96), wrF=(272, 98), h=-82,
      front_props=flying_ball((300, 96), 0)),
]


# Rotational throw, seen from the front: load the back (screen-left) hip, release to the right.
def rot_throw(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 80)
        kit.wall(doc, 330, 16)


ROT = [
    P(front=True, t=-98, h=-96, lN=(70, 96, 0), lF=(116, 80, 180), aN=(150, 130, 120), aF=(122, 110, 110),
      pin=("hip", (196, 156)), front_props=[held_ball(dx=-4)]),
    P(front=True, t=-90, h=-90, lN=(72, 92, 0), lF=(112, 86, 180), aN=(72, 40, 20), aF=(96, 60, 40),
      pin=("hip", (204, 154)), front_props=[held_ball(dx=4)]),
    P(front=True, t=-82, h=-84, lN=(78, 86, 0), lF=(118, 106, 160), aN=(-8, -10), aF=(14, -4),
      pin=("hip", (210, 154)), front_props=flying_ball((300, 82), -6)),
]


def slam(doc, j, layer):
    if layer == "back":
        ground(doc, 210, 70)


SLAM_C = ("#2B2F36", "#0E1013")
SLAM = [
    B((200, 140), -88, ankN=(204, GROUND - 12), ankF=(200, GROUND - 12), footN=50, footF=50,
      aN=(-84, -88, -95), aF=(-88, -92, -95), h=-90, front_props=[held_ball(14, SLAM_C, 0, -10)]),
    B((192, 158), -66, ankN=(204, FOOT_Y), ankF=(200, FOOT_Y), wrN=(266, 112), wrF=(262, 114), h=-66,
      front_props=[held_ball(14, SLAM_C, 6, 0)]),
    B((168, 196), -30, ankN=(204, FOOT_Y), ankF=(200, FOOT_Y), wrN=(238, 246), wrF=(234, 246), handN=80,
      handF=80, h=-16, front_props=[lambda doc, j: kit.ball(doc, (244, GROUND - 14), 14, SLAM_C)]),
]


def back_throw(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 60)


OBT = [
    B((178, 192), -50, ankN=(204, FOOT_Y), ankF=(200, FOOT_Y), wrN=(210, 214), wrF=(206, 214), h=-60,
      front_props=[held_ball(14, dy=6)]),
    B((198, 146), -86, ankN=(204, GROUND - 12), ankF=(200, GROUND - 12), footN=50, footF=50,
      wrN=(262, 74), wrF=(258, 76), h=-88, front_props=[held_ball(14, dx=4)]),
    B((200, 132), -100, ankN=(206, GROUND - 26), ankF=(202, GROUND - 26), footN=64, footF=64,
      aN=(-112, -118), aF=(-116, -122), h=-112, front_props=flying_ball((136, 24), -150, 14)),
]


# ---- kettlebell & barbell ballistics -----------------------------------------------------------

def kb_scene(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 70)
    else:
        w, h = j["wristN"], j["handN"]
        kb(doc, grip(j), math.degrees(math.atan2(h[1] - w[1], h[0] - w[0])), 12)


KBS = [
    B((152, 178), -22, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), wrN=(166, 208), wrF=(162, 208), h=-28),
    B((186, 156), -72, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), wrN=(228, 172), wrF=(224, 172), h=-76),
    B((198, 152), -92, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(-4, -6), aF=(-2, -4), h=-90),
]


def snatch(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 70)
    else:
        w, h = j["wristN"], j["handN"]
        up = h[1] < w[1] - 6
        if up:
            kb(doc, grip(j), -98, 12)
        else:
            kb(doc, grip(j), math.degrees(math.atan2(h[1] - w[1], h[0] - w[0])), 12)


SNATCH = [
    B((152, 178), -22, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), wrN=(166, 208), aF=(150, 100), h=-28,
      lit_sides="N"),
    B((198, 150), -92, ankN=(202, GROUND - 6), ankF=(198, GROUND - 6), footN=24, footF=24,
      aN=(-24, -100, -100), aF=(150, 110), h=-90, lit_sides="N"),
    B((198, 152), -90, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(-88, -88, -88), aF=(100, 92), h=-90,
      lit_sides="N"),
]


def clean(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 70)
    else:
        kit.barbell(doc, art.add(grip(j), (2, 0)), 26)


HPC = [
    B((178, 160), -64, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(92, 92), aF=(90, 90), h=-70),
    B((196, 140), -96, ankN=(202, GROUND - 12), ankF=(198, GROUND - 12), footN=50, footF=50,
      aN=(98, 96), aF=(96, 94), h=-94),
    B((186, 172), -78, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(12, -158, -110), aF=(14, -156, -110), h=-84),
]


# ---- sled push -----------------------------------------------------------------------------------

SLED_X = 300


def sled(doc, j, layer):
    x = SLED_X
    if layer == "back":
        ground(doc, 230, 140)
        # Far upright, base with runners, centre post loaded with plates (seen edge-on).
        art.tube(doc, (x + 4, GROUND - 12), (x - 4, 132), 7)
        doc.add(f'<path d="M{x - 10},{GROUND - 3} L{x + 92},{GROUND - 3} Q{x + 104},{GROUND - 3} {x + 106},{GROUND - 14} '
                f'L{x - 8},{GROUND - 14} Z" fill="#30363D" stroke="#0A0B0D" stroke-width="0.9"/>')
        art.tube(doc, (x - 8, GROUND - 2), (x + 98, GROUND - 2), 4)
        art.tube(doc, (x + 52, GROUND - 14), (x + 52, GROUND - 92), 6, "butt")
        for i in range(4):
            y = GROUND - 22 - i * 13
            rect(doc, x + 22, y, 60, 11, 3, ("#3A3F46", "#121417"))
        art.tube(doc, (x + 52, GROUND - 12), (x + 92, GROUND - 12), 4)
    else:
        art.tube(doc, (x + 8, GROUND - 12), (x, 128), 8)
        art.tube(doc, (x, GROUND - 22), (x + 52, GROUND - 22), 5)


def sled_pose(stance, swing, hip=(176, 190), t=-28):
    """`stance` = (N|F, ankle) pushing back on the ball of the foot; the other leg drives the knee."""
    side, ank = stance
    other = "F" if side == "N" else "N"
    kw = {"ank" + side: ank, "foot" + side: 52, "l" + other: swing}
    return B(hip, t, wrN=(SLED_X - 6, 150), wrF=(SLED_X - 8, 152), handN=-70, handF=-70, h=-14, **kw)


SLED = [
    sled_pose(("N", (98, GROUND - 13)), (14, 104, 30)),
    sled_pose(("N", (138, GROUND - 10)), (64, 146, 60), hip=(180, 186)),
    sled_pose(("F", (98, GROUND - 13)), (14, 104, 30)),
]


# ---- upper-body plyometrics --------------------------------------------------------------------

def plank(t, arm, toe=(110, GROUND - 1), curl=0, h=None, **kw):
    return P(t=t, h=t if h is None else h, curl=curl, lN=(t + 180, t + 180, 80), lF=(t + 180, t + 180, 80),
             aN=arm, aF=arm, pin=("toeN", toe), **kw)


def settle(make, lo, hi, joint, y, n=40):
    """Bisection on the one free parameter of `make` so that `joint` ends up at height y."""
    f = lambda v: F.place(make(v))[joint][1] - y
    flo = f(lo)
    for _ in range(n):
        m = (lo + hi) / 2
        if (f(m) > 0) == (flo > 0):
            lo, flo = m, f(m)
        else:
            hi = m
    return make((lo + hi) / 2)


def on_hands(arm, toe=(110, GROUND - 1), **kw):
    return settle(lambda t: plank(t, arm, toe, **kw), -60, 10, "wristN", GROUND - 5)


PLYO = [
    on_hands((200, 60, 0)),
    on_hands((96, 92, 0)),
    plank(-34, (100, 96, 60), front_props=[arrow((318, 234), -90, 22)]),
]


def pullup(doc, j, layer):
    if layer == "back":
        bar_front(doc, BAR, top=-20)


def bar_front(doc, c, top=4, half=34):
    """Pull-up bar end-on at c, its frame held from the ceiling in front of the athlete (right), so the head
    rising behind the bar never crosses the frame (local mirror of kit.pullup_bar)."""
    art.tube(doc, (c[0] + half, top), (c[0] + half, c[1]), 7, "butt")
    art.tube(doc, (c[0] - 6, c[1]), (c[0] + half, c[1]), 6)
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="4.6" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="1.8" fill="{art.CHROME}"/>')


BAR = (232, 24)


def hang(sh_off, t, legs=((80, 168, 120), (84, 172, 124)), h=None, bend=-1, **kw):
    """Pose hanging from the bar: the shoulder at `sh_off` from the wrist, arm solved, wrist pinned."""
    wr = (BAR[0], BAR[1] + 5)
    sh = art.add(wr, sh_off)
    a = ik(sh, wr, UA, FA, bend)
    return P(t=t, h=t if h is None else h, lN=legs[0], lF=legs[1], aN=a + (-90,), aF=(a[0] + 3, a[1] + 2, -90),
             pin=("wristN", wr), **kw)


EPU = [
    hang((-2, 80), -90),
    hang((-10, 44), -98, h=-92),
    hang((-24, 8), -104, h=-90, front_props=[arrow((150, 150), -90, 26)]),
]


# ---- battle ropes --------------------------------------------------------------------------------

ANCHOR = (372, GROUND - 10)


def ropes(doc, j, layer):
    if layer == "back":
        ground(doc, 260, 130)
        art.tube(doc, (ANCHOR[0], GROUND - 2), (ANCHOR[0], GROUND - 40), 12, "butt")
        kit.feet(doc, ANCHOR[0] - 20, ANCHOR[0] + 20)
        rope(doc, grip(j, "F"), -4)
    else:
        rope(doc, grip(j), 0)
        doc.add(f'<circle cx="{ANCHOR[0]:.1f}" cy="{ANCHOR[1]:.1f}" r="6" fill="none" stroke="#2B2F36" stroke-width="4"/>')


def rope(doc, g, dy):
    """Rope from the hand down to the floor, then a wave running to the anchor (higher near the athlete)."""
    x0 = g[0] + 24
    fy = GROUND - 4 + dy * 0.3
    amp = max(6, min(20, (fy - g[1]) * 0.16))
    pts = [g, (g[0] + 14, mid(g, (x0, fy), 0.55)[1]), (x0 + 4, fy - 3)]
    n = max(2, int((ANCHOR[0] - x0 - 20) // 22))
    for i in range(1, n + 1):
        x = x0 + 4 + (ANCHOR[0] - 10 - x0 - 4) * i / n
        k = 1 - i / (n + 1)
        pts.append((x, fy - 3 - (amp * k * 2 if i % 2 else 0)))
    pts.append(ANCHOR)
    rope_path(doc, pts, 5)


ROPES = [
    B((168, 186), -58, ankN=(194, FOOT_Y), ankF=(188, FOOT_Y), aN=(-56, -60), aF=(-60, -64), h=-66),
    B((166, 190), -54, ankN=(194, FOOT_Y), ankF=(188, FOOT_Y), aN=(0, -6), aF=(-4, -10), h=-62),
    B((162, 196), -46, ankN=(194, FOOT_Y), ankF=(188, FOOT_Y), wrN=(250, 222), wrF=(246, 222), h=-54),
]



# ---- cardio machines ---------------------------------------------------------------------------

def fan(doc, c, r, blades=10):
    """Air-resistance fan / flywheel cage seen from the side."""
    g = doc.lin((c[0] - r, c[1] - r), (c[0] + r, c[1] + r), [(0, "#4A525C"), (0.5, "#262B31"), (1, "#121417")])
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="{g}" stroke="#0A0B0D" stroke-width="1"/>')
    for i in range(blades):
        a = math.radians(i * 360 / blades)
        p = (c[0] + math.cos(a) * r * 0.86, c[1] + math.sin(a) * r * 0.86)
        doc.add(f'<line x1="{c[0]:.1f}" y1="{c[1]:.1f}" x2="{p[0]:.1f}" y2="{p[1]:.1f}" stroke="#596270" '
                f'stroke-opacity="0.6" stroke-width="1"/>')
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.86:.1f}" fill="none" stroke="#6D7681" stroke-opacity="0.5" '
            f'stroke-width="1.2" stroke-dasharray="1.5 2.5"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{max(4, r * 0.18):.1f}" fill="#2C3137" stroke="#5A616A" stroke-width="1"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="2.4" fill="{art.CHROME}"/>')


def crank(doc, c, pedal, r=4):
    art.tube(doc, c, pedal, 4)
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="5" fill="#2C3137" stroke="#0A0B0D" stroke-width="0.8"/>')
    doc.add(f'<rect x="{pedal[0] - 7:.1f}" y="{pedal[1] - 2:.1f}" width="14" height="4" rx="1.5" fill="#1B1E22" '
            f'stroke="#0A0B0D" stroke-width="0.7"/>')


def on_pedal(p):
    """Ankle position for the ball of the foot on pedal p."""
    return (p[0] - 9, p[1] - 6)


# Rower: monorail, seat on the rail, foot stretcher, flywheel cage with the chain to the handle.
ROW_SEAT = 220  # seat top
ROW_ANK = (258, 226)
ROW_OUT = (300, 196)  # chain outlet


def rower(doc, j, layer):
    hip = j["hip"]
    g = grip(j)
    if layer == "back":
        ground(doc, 200, 150, 20, 380)
        # Rear leg, monorail, front leg.
        art.tube(doc, (78, GROUND - 2), (86, 230), 6)
        kit.feet(doc, 64, 96)
        rect(doc, 74, 228, 236, 9, 3, ("#B7C0CA", "#6B747E"))
        art.tube(doc, (340, GROUND - 2), (322, 214), 7)
        kit.feet(doc, 322, 360)
        # Monitor arm + monitor.
        art.tube(doc, (318, 186), (306, 128), 5)
        rect(doc, 290, 104, 30, 26, 3, ("#2A2F35", "#15181B"))
        screen(doc, 293, 107, 24, 18)
        # Flywheel cage.
        fan(doc, (330, 210), 30, 12)
        rect(doc, 296, 190, 14, 22, 3, ("#3A414A", "#1E2328"))
        # Foot stretcher (angled plate with heel cup) on its frame.
        art.tube(doc, (240, 236), (262, 228), 5)
        art.pad(doc, (246, 238), (272, 200), 8, stitch=False)
        # Seat on its rollers.
        art.tube(doc, (hip[0] - 12, ROW_SEAT + 6), (hip[0] + 12, ROW_SEAT + 6), 5)
        art.pad(doc, (hip[0] - 18, ROW_SEAT + 9), (hip[0] + 18, ROW_SEAT + 9), 9)
        art.cable(doc, [(g[0] - 2, g[1]), ROW_OUT])
    else:
        # Foot strap over the near foot, handle (end-on bar) in the hands.
        a = j["ankleN"]
        doc.add(f'<path d="M{a[0] + 4:.1f},{a[1] - 9:.1f} l12,-3" stroke="#1B1E22" stroke-width="4" stroke-linecap="round"/>')
        kit.handle(doc, g)


def row_pose(hip_x, t, wr, h=None):
    hip = (hip_x, ROW_SEAT - 12)
    return B(hip, t, ankN=ROW_ANK, ankF=(ROW_ANK[0] - 4, ROW_ANK[1]), footN=-58, footF=-58, wrN=wr,
             wrF=(wr[0] - 3, wr[1] + 1), handN=10, handF=10, h=t if h is None else h)


ROW = [
    row_pose(198, -60, (284, 182), h=-64),
    row_pose(156, -84, (236, 168), h=-86),
    row_pose(150, -110, (174, 172), h=-100),
]


# SkiErg: tall tower, flywheel housing on top, two handles on cords from the top pulleys.
SKI_X = 324


def ski_erg(doc, j, layer):
    top = SKI_PULLEY
    if layer == "back":
        ground(doc, 260, 110)
        kit.feet(doc, SKI_X - 30, SKI_X + 54)
        rect(doc, SKI_X - 16, GROUND - 14, 64, 12, 3, ("#3A414A", "#1E2328"))
        rect(doc, SKI_X + 8, 70, 18, GROUND - 82, 3, ("#3A414A", "#1E2328"), vertical=False)
        housing(doc, f"M{SKI_X - 14},{12} h50 q8,0 8,8 v58 q0,8 -8,8 h-50 q-8,0 -8,-8 v-58 q0,-8 8,-8 Z")
        fan(doc, (SKI_X + 16, 50), 20, 10)
        screen(doc, SKI_X - 4, 96, 22, 16)
        # Pulley arm sticking out of the housing's top front corner: the handles hang in front of the machine.
        art.tube(doc, (SKI_X - 10, top[1]), (top[0] - 3, top[1]), 6)
        for side, dx in (("F", -3), ("N", 0)):
            if side == "F":
                art.pulley(doc, (top[0] + dx, top[1]), 5)
                art.cable(doc, [(top[0] + dx - 5, top[1]), grip(j, "F")])
                ski_handle(doc, grip(j, "F"))
    else:
        art.pulley(doc, top, 5)
        art.cable(doc, [(top[0] - 5, top[1]), grip(j)])
        ski_handle(doc, grip(j))


def ski_handle(doc, c):
    doc.add(f'<rect x="{c[0] - 3.5:.1f}" y="{c[1] - 10:.1f}" width="7" height="20" rx="3.5" fill="#1D2125" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>')


SKI_PULLEY = (SKI_X - 30, 14)

SKI = [
    B((232, 150), -88, ankN=(236, FOOT_Y), ankF=(232, FOOT_Y), wrN=(262, 30), wrF=(258, 32), handN=-60, handF=-60,
      elbN=-1, elbF=-1, h=-86),
    B((226, 160), -66, ankN=(236, FOOT_Y), ankF=(232, FOOT_Y), wrN=(272, 124), wrF=(268, 126), handN=60, handF=60,
      h=-70),
    B((206, 178), -34, ankN=(236, FOOT_Y), ankF=(232, FOOT_Y), wrN=(220, 210), wrF=(216, 210), handN=100,
      handF=100, h=-40),
]


# Air bike: big fan in front, seat post, cranks, moving handles linked to the cranks.
AB_HIP = (172, 160)
AB_CRANK = (222, 226)
AB_PIVOT = (284, 214)


def ab_lever(phase):
    return art.ang_pt(AB_PIVOT, -116 + 13 * math.cos(math.radians(phase)), 104)


def air_bike_moving(ph, near):
    def draw(doc, j):
        p = ph if near else ph + 180
        art.tube(doc, AB_PIVOT, ab_lever(p), 6)
        if near:
            doc.add(f'<circle cx="{AB_PIVOT[0]}" cy="{AB_PIVOT[1]}" r="4.5" fill="#2C3137" stroke="#0A0B0D" stroke-width="0.8"/>')
        crank(doc, AB_CRANK, art.ang_pt(AB_CRANK, p, 21))
    return draw


def air_bike(doc, j, layer):
    if layer == "back":
        ground(doc, 230, 130)
        kit.feet(doc, 140, 196)
        kit.feet(doc, 286, 360)
        art.tube(doc, (170, GROUND - 2), (AB_CRANK[0], AB_CRANK[1]), 8)
        art.tube(doc, (AB_CRANK[0], AB_CRANK[1]), (318, 214), 8)
        art.tube(doc, (318, 214), (322, GROUND - 2), 8)
        art.tube(doc, (176, 190), (AB_CRANK[0], AB_CRANK[1]), 8)
        fan(doc, (318, 212), 42, 14)
        # Seat post + saddle.
        art.tube(doc, (176, 192), (170, 172), 7)
        art.pad(doc, (150, 176), (190, 172), 9)


def bike_pose(hip, t, crank_c, crank_r, phase, wrN, wrF, h=None, handle=None, moving=None, **kw):
    pn = art.ang_pt(crank_c, phase, crank_r)
    pf = art.ang_pt(crank_c, phase + 180, crank_r)
    p = B(hip, t, ankN=on_pedal(pn), ankF=on_pedal(pf), footN=12, footF=12, wrN=wrN, wrF=wrF,
          handN=handle, handF=handle, h=t if h is None else h,
          props=[moving(phase, False)], front_props=[moving(phase, True)], **kw)
    return p


AB = [bike_pose(AB_HIP, -76, AB_CRANK, 21, ph, ab_lever(ph), ab_lever(ph + 180), h=-80, moving=air_bike_moving)
      for ph in (-30, 90, 210)]


# Upright exercise bike: saddle, handlebars, flywheel under a cover in front.
BK_CRANK = (226, 224)


def bike_moving(ph, near):
    def draw(doc, j):
        crank(doc, BK_CRANK, art.ang_pt(BK_CRANK, ph if near else ph + 180, 20))
        if near:
            art.tube(doc, (276, 126), (262, 124), 7)
    return draw


def bike(doc, j, layer):
    if layer == "back":
        ground(doc, 230, 120)
        kit.feet(doc, 140, 200)
        kit.feet(doc, 280, 344)
        # Frame: rear post to crank, front column to the handlebars.
        art.tube(doc, (170, GROUND - 2), BK_CRANK, 9)
        art.tube(doc, BK_CRANK, (310, GROUND - 2), 9)
        art.tube(doc, (300, 238), (278, 124), 9)
        housing(doc, "M262,190 Q300,176 330,204 Q340,236 318,252 L258,252 Q244,230 262,190 Z")
        art.tube(doc, (278, 128), (292, 122), 6)
        rect(doc, 268, 104, 26, 18, 3, ("#2A2F35", "#15181B"))
        screen(doc, 271, 107, 20, 12)
        art.tube(doc, (184, 206), (176, 168), 8)
        art.pad(doc, (152, 170), (196, 164), 9)


BIKE = [bike_pose((176, 154), -64, BK_CRANK, 20, ph, (264, 128), (260, 129), h=-70, handle=10, moving=bike_moving)
        for ph in (-30, 90, 210)]


# Treadmill: deck with belt, motor hood, console uprights and handrails. `tilt` in degrees (incline walk).
def treadmill(tilt=0.0):
    k = math.tan(math.radians(tilt))
    rear, front = 56, 300

    def deck_y(x):
        return GROUND - 22 - (x - rear) * k

    def scene(doc, j, layer):
        if layer != "back":
            return
        ground(doc, 190, 140)
        r0, f0 = (rear, deck_y(rear)), (front, deck_y(front))
        # Front elevation leg (incline), rear foot.
        art.tube(doc, (front - 6, deck_y(front) + 8), (front - 6, GROUND - 2), 8, "butt")
        kit.feet(doc, rear - 4, rear + 30)
        kit.feet(doc, front - 30, front + 44)
        ang = math.degrees(math.atan2(f0[1] - r0[1], f0[0] - r0[0]))
        L = math.hypot(f0[0] - r0[0], f0[1] - r0[1])
        g = doc.box_grad([(0, "#4A525C"), (1, "#1E2328")])
        doc.add(f'<g transform="translate({r0[0]:.1f} {r0[1]:.1f}) rotate({ang:.2f})">'
                f'<rect x="0" y="0" width="{L:.1f}" height="16" rx="6" fill="{g}" stroke="#0A0B0D" stroke-width="0.9"/>'
                f'<rect x="4" y="-1" width="{L - 8:.1f}" height="4" rx="2" fill="#15181B"/>'
                f'<line x1="10" y1="9" x2="{L - 10:.1f}" y2="9" stroke="#C9D1DA" stroke-opacity="0.5" stroke-width="1.4"/>'
                f'<circle cx="8" cy="8" r="5" fill="#2C3137" stroke="#6D7681" stroke-width="0.8"/>'
                f'<circle cx="{L - 8:.1f}" cy="8" r="5" fill="#2C3137" stroke="#6D7681" stroke-width="0.8"/></g>')
        # Motor hood.
        hy = deck_y(front)
        housing(doc, f"M{front - 6},{hy - 4:.1f} Q{front + 30},{hy - 14:.1f} {front + 46},{hy + 2:.1f} "
                     f"L{front + 46},{GROUND - 2} L{front - 6},{GROUND - 2} Z")
        # Uprights, console, handrails.
        art.tube(doc, (front + 34, hy), (front + 14, 104), 9)
        art.tube(doc, (front + 14, 104), (front - 4, 100), 8)
        art.tube(doc, (front + 8, 140), (front - 74, 140 - 0 * k), 7)
        housing(doc, f"M{front - 30},88 L{front + 22},84 Q{front + 30},84 {front + 28},94 L{front + 18},116 "
                     f"L{front - 26},118 Q{front - 34},118 {front - 32},110 Z")
        screen(doc, front - 22, 92, 38, 18)
    scene.deck_y = deck_y
    return scene


TM = treadmill()
TD = TM.deck_y(180) - 4


def run_pose(stance, hip, t, swing, arms, h=-84, lift=0):
    """Running stride: `stance` = (side, ankle x) or None for the flight phase; `swing` = legs not on the deck."""
    kw = {}
    if stance:
        side, x = stance
        kw["ank" + side] = (x, TD)
        kw["foot" + side] = 2
    for side, ang in swing.items():
        kw["l" + side] = ang
    return B((hip[0], hip[1] - lift), t, aN=arms[0], aF=arms[1], h=h, **kw)


RUN = [
    run_pose(("N", 186), (178, 136), -80, {"F": (56, 156, 96)}, ((124, 40), (50, -50))),
    run_pose(None, (180, 128), -80, {"N": (118, 166, 104), "F": (34, 100, 6)}, ((84, 0), (104, 30))),
    run_pose(("F", 186), (178, 136), -80, {"N": (56, 156, 96)}, ((50, -50), (124, 40))),
]

INC = treadmill(6.8)


def walk_pose(front, back, hip, t=-82, arms=((70, 80), (110, 100)), h=-86, back_foot=36):
    """Walking on the inclined deck: `front`/`back` = (side, x) heel strike / toe-off."""
    fs, fx = front
    bs, bx = back
    fy, by = INC.deck_y(fx) - 4, INC.deck_y(bx) - 4
    kw = {"ank" + fs: (fx, fy), "foot" + fs: -24, "ank" + bs: (bx, by - 7), "foot" + bs: back_foot}
    return B(hip, t, aN=arms[0], aF=arms[1], h=h, **kw)


WALK = [
    walk_pose(("N", 214), ("F", 150), (184, 134), arms=((116, 84), (66, 50))),
    B((186, 128), -80, ankN=(192, INC.deck_y(192) - 4), footN=-7, lF=(56, 124, 30), aN=(92, 86), aF=(92, 86), h=-86),
    walk_pose(("F", 214), ("N", 150), (184, 134), arms=((66, 50), (116, 84))),
]


# Stair climber (stepmill): revolving staircase rising into the machine, side handrails, console.
SX, SY, STEP_W, STEP_H = 150, GROUND - 34, 28, 24


def step_top(k):
    return SY - k * STEP_H


def stairs(doc, j, layer):
    if layer != "back":
        return
    ground(doc, 230, 130)
    # Machine body.
    housing(doc, f"M{SX + 4 * STEP_W - 6},{GROUND - 2} L{SX + 4 * STEP_W - 6},{step_top(4) - 20} "
                 f"Q{SX + 4 * STEP_W + 10},{100} {SX + 4 * STEP_W + 50},{96} L{SX + 4 * STEP_W + 64},{96} "
                 f"L{SX + 4 * STEP_W + 64},{GROUND - 2} Z", vertical=False)
    housing(doc, f"M{SX - 10},{GROUND - 2} L{SX - 10},{SY + 6} L{SX + 4 * STEP_W},{step_top(4) - 8} "
                 f"L{SX + 4 * STEP_W},{GROUND - 2} Z", ("#30363D", "#1A1E22"))
    for k in range(4):
        x = SX + k * STEP_W
        y = step_top(k)
        doc.add(f'<rect x="{x - 2:.1f}" y="{y:.1f}" width="{STEP_W + 4}" height="6" rx="1.5" fill="#596270" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>'
                f'<rect x="{x:.1f}" y="{y + 6:.1f}" width="{STEP_W}" height="{STEP_H - 6}" fill="#15181B"/>')
    kit.feet(doc, SX - 16, SX + 4 * STEP_W + 70)
    # Handrail from the console back to the rear post, console.
    art.tube(doc, (SX + 4 * STEP_W + 20, RAIL_Y[0]), (SX - 8, RAIL_Y[1]), 7)
    art.tube(doc, (SX - 8, RAIL_Y[1]), (SX - 8, SY + 4), 7)
    housing(doc, f"M{SX + 4 * STEP_W - 10},96 L{SX + 4 * STEP_W + 40},84 L{SX + 4 * STEP_W + 46},112 "
                 f"L{SX + 4 * STEP_W - 4},118 Z")
    screen(doc, SX + 4 * STEP_W - 2, 94, 36, 16)


RAIL_Y = (98, 112)  # handrail height at the console end / at the rear post (waist high)


def on_rail(x, dy=-3):
    """Wrist on the handrail at x."""
    x0, x1 = SX + 4 * STEP_W + 20, SX - 8
    return (x, RAIL_Y[0] + (RAIL_Y[1] - RAIL_Y[0]) * (x0 - x) / (x0 - x1) + dy)


def on_step(k, back=8):
    return (SX + k * STEP_W + back, step_top(k) - 4)


STAIR = [
    B((188, 106), -84, ankN=on_step(2, 10), ankF=on_step(1, 6), footF=24, wrN=on_rail(232), wrF=on_rail(228),
      handN=10, handF=10, h=-88),
    B((190, 102), -84, ankN=on_step(2, 10), lF=(40, 110, 20), wrN=on_rail(232), wrF=on_rail(228), handN=10,
      handF=10, h=-88),
    B((188, 106), -84, ankF=on_step(2, 10), ankN=on_step(1, 6), footN=24, wrN=on_rail(232), wrF=on_rail(228),
      handN=10, handF=10, h=-88),
]


# Elliptical cross-trainer: front drive, pedal links on rear rollers, moving handles pivoting on the mast.
EL_CRANK = (318, 232)
EL_PIVOT = (290, 172)


def el_links(phase):
    c = art.ang_pt(EL_CRANK, phase, 18)
    rear = (104 + 12 * math.cos(math.radians(phase)), GROUND - 12)
    pedal = mid(rear, c, 0.46)
    return c, rear, pedal


def el_handle(phase):
    return art.ang_pt(EL_PIVOT, -128 - 11 * math.cos(math.radians(phase)), 66)


def el_side(p, near):
    def side(doc, j):
        c, rear, pedal = el_links(p)
        art.tube(doc, rear, c, 7)
        doc.add(f'<circle cx="{rear[0]:.1f}" cy="{rear[1]:.1f}" r="5" fill="#2C3137" stroke="#0A0B0D" stroke-width="0.8"/>')
        doc.add(f'<rect x="{pedal[0] - 22:.1f}" y="{pedal[1] - 8:.1f}" width="40" height="7" rx="3" fill="#1B1E22" '
                f'stroke="#0A0B0D" stroke-width="0.8"/>')
        lo = art.ang_pt(EL_PIVOT, 52 - 11 * math.cos(math.radians(p)), 40)
        art.tube(doc, el_handle(p), lo, 6)
        art.tube(doc, lo, mid(rear, c, 0.8), 5)
        if near:
            doc.add(f'<circle cx="{EL_PIVOT[0]}" cy="{EL_PIVOT[1]}" r="5" fill="#2C3137" stroke="#0A0B0D" stroke-width="0.8"/>')
    return side


def elliptical(doc, j, layer):
    if layer == "back":
        ground(doc, 220, 150)
        kit.feet(doc, 80, 140)
        kit.feet(doc, 290, 360)
        art.tube(doc, (92, GROUND - 4), (330, GROUND - 4), 7)
        art.tube(doc, (300, 236), (300, 96), 9)
        housing(doc, "M276,214 Q320,196 352,222 Q360,252 340,GROUND L284,GROUND Q268,240 276,214 Z".replace(
            "GROUND", str(GROUND - 4)))
        housing(doc, "M282,84 L320,78 Q326,78 324,86 L318,102 L284,106 Q278,106 278,100 Z")
        screen(doc, 286, 84, 30, 16)


def el_pose(phase):
    _, _, pn = el_links(phase)
    _, _, pf = el_links(phase + 180)
    p = B((196, 128 + 3 * math.sin(math.radians(phase))), -84, ankN=(pn[0], pn[1] - 13), ankF=(pf[0], pf[1] - 13),
          footN=0, footF=0, wrN=el_handle(phase), wrF=el_handle(phase + 180), handN=-80, handF=-80, h=-86,
          props=[el_side(phase + 180, False)], front_props=[el_side(phase, True)])
    return p


ELL = [el_pose(ph) for ph in (0, 120, 240)]


# ---- warm-up -----------------------------------------------------------------------------------

def mat_scene(x0, x1, cx=None, rx=None):
    def scene(doc, j, layer):
        if layer == "back":
            ground(doc, cx or (x0 + x1) / 2, rx or (x1 - x0) / 2)
            kit.mat(doc, x0, x1)
    return scene


WGS_HIP = (190, 206)
WGS = [
    B(WGS_HIP, -22, ankN=(264, FOOT_Y), ankF=(94, GROUND - 13), footF=48, wrN=(250, GROUND - 6),
      wrF=(244, GROUND - 6), handN=0, handF=0, h=-10),
    B((WGS_HIP[0], WGS_HIP[1] + 4), -6, ankN=(264, FOOT_Y), ankF=(94, GROUND - 13), footF=48, aN=(100, 24, 24),
      wrF=(240, GROUND - 6), handF=0, h=6),
    B(WGS_HIP, -30, ankN=(264, FOOT_Y), ankF=(94, GROUND - 13), footF=48, aN=(-88, -90),
      wrF=(244, GROUND - 6), handF=0, h=-64),
]


# Leg swings: the far hand on a pole standing beside the athlete (behind the body in this side view) for
# balance, the near leg swings back and forth in front of it.
LSW_POLE = 222


def leg_swing(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 70)
        kit.post(doc, LSW_POLE, 60)


LSW = [
    B((196, 152), -92, ankF=(196, FOOT_Y), lN=(126, 132, 40), wrF=(LSW_POLE - 2, 128), handF=-80, aN=(60, 40), h=-90,
      lit_sides="N"),
    B((196, 152), -90, ankF=(196, FOOT_Y), lN=(84, 92, 10), wrF=(LSW_POLE - 2, 128), handF=-80, aN=(84, 70), h=-90,
      lit_sides="N"),
    B((196, 152), -96, ankF=(196, FOOT_Y), lN=(-30, -28, -60), wrF=(LSW_POLE - 2, 128), handF=-80, aN=(116, 100), h=-94,
      lit_sides="N"),
]


# 90/90 switches, seen from the front: knees drop to one side, come up, drop to the other.
def knee_down(thigh, dy, back):
    """(thigh, shin) for a shin that runs from the knee back down to the floor `dy` below the hip."""
    k = art.ang_pt((0, 0), thigh, TH)
    s = max(-1, min(1, (dy - k[1]) / SH))
    a = math.degrees(math.asin(s))
    return (thigh, 180 - a if back else a)


H90_HIP = (200, GROUND - 16)
_CAT = {}


def levels_of(ex_id):
    """Worked-muscle levels of a catalog exercise (for parts a scene redraws itself)."""
    if not _CAT:
        import sample
        _CAT.update(sample.catalog())
    return art.muscle_levels(_CAT[ex_id])


def h90_feet(j):
    """In-betweens: a shin swinging between its key directions dips the foot under the mat; swing it back up
    round the knee (same side) so the foot slides along the mat as the knees windshield-wipe. A foot turning
    between pointing out left and right shows foreshortened (towards the camera), not pointing into the floor."""
    for s in "NF":
        kn, an, to = j["knee" + s], j["ankle" + s], j["toe" + s]
        a2 = an
        if an[1] > FOOT_Y:
            dy = FOOT_Y - kn[1]
            dx = math.sqrt(max(0.0, SH * SH - dy * dy)) * (1 if an[0] >= kn[0] else -1)
            a2 = (kn[0] + dx, FOOT_Y)
        j["ankle" + s] = a2
        j["toe" + s] = (a2[0] + to[0] - an[0], a2[1] + min(0.0, to[1] - an[1]))


def hip_90_90(doc, j, layer):
    if layer == "back":
        h90_feet(j)
        ground(doc, 200, 90)
        kit.mat(doc, 110, 290)
        return
    # Seated, seen from the front: the legs come towards the viewer, so they go over the trunk (art.py draws
    # front-view legs behind it), then the arms over the legs.
    far, _, near = art.body_segments(j, True)
    lv = levels_of("hip-90-90")
    for names in (("foot", "shin", "thigh"), ("upper", "fore", "hand")):
        for limbs in (far, near):
            for name in names:
                d = art.draw_segment(doc, limbs[name], art.SKIN_NEAR)
                art.draw_muscles(doc, limbs[name], name, lv, d, False, "front")
H90 = [
    P(front=True, t=-92, h=-90, lN=knee_down(6, 12, True) + (180,), lF=knee_down(-34, 12, False) + (0,),
      aN=(60, 70), aF=(120, 110), pin=("hip", H90_HIP)),
    P(front=True, t=-90, h=-90, lN=knee_down(-62, 12, False) + (0,), lF=knee_down(-118, 12, True) + (180,),
      aN=(60, 70), aF=(120, 110), pin=("hip", H90_HIP)),
    P(front=True, t=-88, h=-90, lN=knee_down(-146, 12, True) + (180,), lF=knee_down(174, 12, False) + (0,),
      aN=(60, 70), aF=(120, 110), pin=("hip", H90_HIP)),
]


INCH = [
    B((100, 152), 52, ankN=(112, FOOT_Y), ankF=(108, FOOT_Y), wrN=(176, GROUND - 6), wrF=(172, GROUND - 6),
      handN=0, handF=0, h=76),
    B((138, 154), 30, ankN=(112, FOOT_Y), ankF=(108, FOOT_Y), kneeN=-1, kneeF=-1, wrN=(238, GROUND - 6),
      wrF=(234, GROUND - 6), handN=0, handF=0, h=44),
    None,
]
INCH[2] = on_hands((90, 90, 0), toe=F.place(INCH[0])["toeN"])


def band_props(doc, j):
    kit.band(doc, grip(j, "N"), grip(j, "F"), "#E0473A")


DISLOC = [
    P(front="back", lN=(84, 90, 0), lF=(96, 90, 180), aN=(62, 70), aF=(118, 110), pin=("ankleN", (204, FOOT_Y)),
      props=[band_props]),
    P(front="back", lN=(84, 90, 0), lF=(96, 90, 180), aN=(-50, -52), aF=(-130, -128), pin=("ankleN", (204, FOOT_Y)),
      front_props=[band_props]),
    P(front="back", lN=(84, 90, 0), lF=(96, 90, 180), aN=(64, 72), aF=(116, 108), pin=("ankleN", (204, FOOT_Y)),
      front_props=[band_props]),
]


def quad(wrist, knee, arm=90, hand=0, curl=0, h=None, **kw):
    """Quadruped: straight arms at `arm` degrees onto `wrist`, knees on the floor at `knee`; the hip is solved."""
    sh = art.ang_pt(wrist, arm + 180, UA + FA)
    a1, a2 = ik(sh, knee, F.TORSO, TH, -1)
    t = a1 + 180
    hip = art.ang_pt(sh, a1, F.TORSO)
    return P(t=t, h=t if h is None else h, curl=curl, lN=(a2, 180, 180), lF=(a2 + 2, 180, 180),
             aN=(arm, arm, hand), aF=(arm, arm, hand), pin=("hip", hip), **kw)


QW, QK = (262, GROUND - 6), (172, GROUND - 9)
CATCOW = [
    quad(QW, QK, arm=74, curl=11, h=72),
    quad(QW, QK, arm=74, curl=-10, h=-36),
]


GB_SH = (130, GROUND - 13)


def bridge(lift):
    hip = art.ang_pt(GB_SH, -lift, F.TORSO)
    t = 180 - lift
    return B(hip, t, ankN=(254, FOOT_Y), ankF=(250, FOOT_Y), wrN=(GB_SH[0] + 79, GROUND - 6),
             wrF=(GB_SH[0] + 77, GROUND - 6), elbN=1, elbF=1, handN=0, handF=0, h=180)


GBR = [bridge(2), bridge(26)]


SCAP = [
    on_hands((90, 90, 0), curl=-10, h=-4),
    on_hands((90, 90, 0), curl=14, h=-24),
]


SQS = [
    B((162, 166), 30, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), wrN=(212, 254), wrF=(208, 254), handN=60, handF=60,
      h=56),
    B((170, 216), -40, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), wrN=(214, 250), wrF=(210, 250), handN=60,
      handF=60, h=-56),
    B((198, 152), -90, ankN=(200, FOOT_Y), ankF=(196, FOOT_Y), aN=(-76, -78), aF=(-80, -82), h=-92),
]


# Arm circles, seen from the front, with the path of the hands.
def arm_circles(doc, j, layer):
    if layer == "back":
        ground(doc, 200, 50)
        kit.arc(doc, j["shoulderN"], UA + FA + 6, -80, 80)
        kit.arc(doc, j["shoulderF"], UA + FA + 6, 100, 260)


CIRC = [
    P(front=True, lN=(84, 90, 0), lF=(96, 90, 180), aN=(50, 50), aF=(130, 130), pin=("ankleN", (204, FOOT_Y))),
    P(front=True, lN=(84, 90, 0), lF=(96, 90, 180), aN=(0, 0), aF=(180, 180), pin=("ankleN", (204, FOOT_Y))),
    P(front=True, lN=(84, 90, 0), lF=(96, 90, 180), aN=(-50, -50), aF=(-130, -130), pin=("ankleN", (204, FOOT_Y))),
]


# Walking lunge with twist: the far leg steps forward into the lunge, then the torso turns over the front leg,
# the arms staying long: the far arm sweeps back behind the body, the near arm stays forward (tweens.py adds the
# step's in-between, foot off the floor).
LTW = [
    B((150, 152), -90, ankN=(148, FOOT_Y), ankF=(152, FOOT_Y), aN=(2, 0), aF=(0, -2), h=-90),
    B((196, 196), -88, ankF=(254, FOOT_Y), ankN=(140, GROUND - 13), footN=48, aN=(2, 0), aF=(0, -2), h=-90),
    B((196, 196), -88, ankF=(254, FOOT_Y), ankN=(140, GROUND - 13), footN=48, aN=(8, 4), aF=(178, 180), h=-100),
]


def lunge_step():
    """In-between of the lunge step (tweens.py): front foot swinging forward just off the floor, back heel up."""
    return B((172, 172), -89, lF=(28, 100, 10), ankN=(144, GROUND - 8), footN=30, aN=(2, 0), aF=(0, -2), h=-90)


WRIST = [
    quad((240, GROUND - 6), QK, arm=72, hand=180),
    quad((240, GROUND - 6), QK, arm=112, hand=180),
]

SCENES = {
    "box-jump": (box_jump, BJ, fit(BJ, (BOX[0], GROUND - BOX[1], BOX[0] + BOX[2], GROUND))),
    "broad-jump": (basic(190, 140), BROAD, fit(BROAD)),
    "squat-jump": (basic(200, 50), SQJ, fit(SQJ)),
    "lateral-bound": (basic(200, 100), LAT, fit(LAT)),
    "depth-jump": (depth_jump, DJ, fit(DJ, (70, GROUND - 62, 142, GROUND), (110, -56, 140, -50))),  # headroom on the box
    "trap-bar-jump": (trap_bar_jump, TBJ, fit(TBJ, ball_box(34))),
    "med-ball-chest-pass": (chest_pass, MBP, fit(MBP, (WALL_X, 60, WALL_X + 16, GROUND), (286, 82, 324, 110))),
    "rotational-throw": (rot_throw, ROT, fit(ROT, (330, 60, 346, GROUND), (286, 68, 324, 96))),
    "ball-slam": (slam, SLAM, fit(SLAM, ball_box(14, 0, -10))),
    "overhead-back-throw": (back_throw, OBT, fit(OBT, (96, 0, 160, 42), ball_box(14))),
    "kb-swing": (kb_scene, KBS, fit(KBS, ball_box(16, 10, 0))),
    "kb-snatch": (snatch, SNATCH, fit(SNATCH, ball_box(16, 0, -14, "N"))),
    "hang-power-clean": (clean, HPC, fit(HPC, ball_box(26))),
    "sled-sprint": (sled, SLED, fit(SLED, (SLED_X - 12, 124, SLED_X + 106, GROUND))),
    "plyo-push-up": (basic(220, 120), PLYO, fit(PLYO)),
    "explosive-pull-up": (pullup, EPU, fit(EPU, (BAR[0] - 8, 0, BAR[0] + 40, 30), floor=False)),
    "battle-rope-slams": (ropes, ROPES, fit(ROPES, (ANCHOR[0] - 22, GROUND - 42, ANCHOR[0] + 22, GROUND))),
    "rower": (rower, ROW, fit(ROW, (64, 100, 362, GROUND))),
    "ski-erg": (ski_erg, SKI, fit(SKI, (SKI_X - 38, 4, SKI_X + 54, GROUND))),
    "air-bike": (air_bike, AB, fit(AB, (140, 168, 362, GROUND))),
    "bike": (bike, BIKE, fit(BIKE, (140, 102, 344, GROUND))),
    "treadmill-run": (TM, RUN, fit(RUN, (50, 84, 346, GROUND))),
    "incline-walk": (INC, WALK, fit(WALK, (50, 84, 346, GROUND))),
    "stair-climber": (stairs, STAIR, fit(STAIR, (SX - 16, 84, SX + 4 * STEP_W + 70, GROUND))),
    "elliptical": (elliptical, ELL, fit(ELL, (80, 78, 362, GROUND))),
    "worlds-greatest": (basic(180, 110), WGS, fit(WGS)),
    "leg-swings": (leg_swing, LSW, fit(LSW, (LSW_POLE - 24, 50, LSW_POLE + 24, GROUND))),
    "hip-90-90": (hip_90_90, H90, fit(H90, (110, GROUND - 4, 290, GROUND))),
    "inchworm": (basic(190, 120), INCH, fit(INCH)),
    "band-dislocates": (basic(204, 50), DISLOC, fit(DISLOC)),
    "cat-cow": (mat_scene(92, 300), CATCOW, fit(CATCOW, (92, GROUND - 4, 300, GROUND))),
    "glute-bridge": (mat_scene(70, 290), GBR, fit(GBR, (70, GROUND - 4, 290, GROUND))),
    "scap-push-up": (basic(220, 120), SCAP, fit(SCAP)),
    "squat-to-stand": (basic(200, 50), SQS, fit(SQS)),
    "arm-circles": (arm_circles, CIRC, fit(CIRC, (100, 30, 310, 230))),
    "lunge-twist": (basic(200, 80), LTW, fit(LTW)),
    "wrist-prep": (basic(210, 100), WRIST, fit(WRIST)),
}
