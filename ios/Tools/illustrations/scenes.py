"""Scenes for the realistic exercise art (#168): poses (start, end, optional middle) plus the equipment.

Each scene pins one joint so the figure moves inside a still machine. Equipment that does not move is
drawn in absolute view-box coordinates; things held by the figure (bar, handle, dumbbell) follow its joints.
Angles as in poses.py (0 = right, 90 = down; the figure faces right).
"""
import math

import art
from art import GROUND
from poses import P


def grip(j, side="N"):
    """Centre of the closed hand."""
    w, h = j["wrist" + side], j["hand" + side]
    return ((w[0] + h[0]) / 2, (w[1] + h[1]) / 2)


def torso_frame(j):
    t = art.norm(art.sub(j["shoulder"], j["hip"]))
    return t, (-t[1], t[0])  # along the torso (up), towards the chest


def base(doc, x0, x1, y=GROUND - 2):
    art.tube(doc, (x0, y), (x1, y), 6)


# ---- lat pulldown ------------------------------------------------------------------------------

PD_TOP_PULLEY = (156, 30)
PD_STACK_X = 236


def pulldown(doc, j, layer):
    g = grip(j)
    if layer == "back":
        art.floor(doc)
        art.shadow(doc, 190, 120)
        # Column + boom.
        art.tube(doc, (281, GROUND - 2), (281, 22), 10)
        art.tube(doc, (146, 22), (286, 22), 9)
        art.shroud(doc, PD_STACK_X - 6, 60, GROUND - 4, 46)
        lift = max(0, (g[1] - 58) * 0.45)
        top = art.stack(doc, PD_STACK_X, 76, GROUND - 4, 34, 12, lift)
        art.pulley(doc, PD_TOP_PULLEY)
        art.pulley(doc, (top[0], 30))
        art.cable(doc, [(PD_TOP_PULLEY[0] + 0.5, PD_TOP_PULLEY[1] - 6.5), (top[0], 23.5)])
        art.cable(doc, [(top[0] + 6.5, 30), top])
        # Seat + knee roller on their posts.
        art.tube(doc, (150, 238), (150, GROUND - 2), 8, "butt")
        base(doc, 104, 286)
        art.pad(doc, (112, 238), (186, 238), 12)
        art.tube(doc, (150, 232), (214, 232), 6)
        art.tube(doc, (212, 232), (206, 192), 6)
    else:
        # Knee roller (end-on) over the thighs, bar (end-on) in the hands, cable to the pulley.
        art.cable(doc, [g, (PD_TOP_PULLEY[0] - 6, PD_TOP_PULLEY[1])])
        doc.add('<circle cx="204" cy="190" r="9.5" fill="#1C1F24" stroke="#0A0B0D" stroke-width="0.9"/>'
                '<circle cx="204" cy="190" r="3" fill="#6D7681"/>')
        doc.add(f'<circle cx="{g[0]:.1f}" cy="{g[1]:.1f}" r="5.2" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
                f'<circle cx="{g[0]:.1f}" cy="{g[1]:.1f}" r="2.2" fill="{art.CHROME}"/>')


# ---- seated cable row --------------------------------------------------------------------------

def cable_row(doc, j, layer):
    g = grip(j)
    A, B, C, D, E = (250, 206), (262, GROUND - 10), (300, GROUND - 10), (300, 44), (330, 44)
    if layer == "back":
        art.floor(doc)
        art.shadow(doc, 200, 150)
        art.tube(doc, (296, GROUND - 2), (296, 38), 10)
        art.tube(doc, (292, 38), (348, 38), 9)
        art.shroud(doc, 310, 60, GROUND - 4, 44)
        lift = max(0, (230 - g[0]) * 0.18)
        top = art.stack(doc, 313, 78, GROUND - 4, 34, 12, lift)
        # Frame from the stack to the foot plate, the long bench.
        art.tube(doc, (240, GROUND - 6), (300, GROUND - 6), 8)
        art.tube(doc, (60, GROUND - 6), (240, GROUND - 6), 7)
        art.tube(doc, (90, 216), (90, GROUND - 6), 7, "butt")
        art.tube(doc, (172, 216), (172, GROUND - 6), 7, "butt")
        art.pad(doc, (64, 228), (184, 228), 12)
        # Foot plate, angled.
        art.tube(doc, (246, GROUND - 6), (246, 200), 6, "butt")
        art.pad(doc, (236, 182), (252, 246), 9, stitch=False)
        for p in (A, B, C, D):
            art.pulley(doc, p, 6)
        art.pulley(doc, (top[0], 44), 6)
        art.cable(doc, [B, C, D, (top[0], 37.5)])
        art.cable(doc, [(top[0] + 6, 44), top])
        art.cable(doc, [A, B])
    else:
        art.cable(doc, [g, (A[0] - 5, A[1] - 2)])
        doc.add(f'<path d="M{g[0] - 2:.1f},{g[1] - 6:.1f} l7,4 l-2,9 l-8,-2 z" fill="{art.CHROME}" stroke="#5A616A" stroke-width="0.8"/>'
                f'<circle cx="{g[0]:.1f}" cy="{g[1]:.1f}" r="4.6" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>')
    del E


# ---- barbell back squat ------------------------------------------------------------------------

def back_squat(doc, j, layer):
    t, n = torso_frame(j)
    bar = (j["shoulder"][0] - n[0] * 14 + t[0] * 3, j["shoulder"][1] - n[1] * 14 + t[1] * 3)
    if layer == "back":
        art.floor(doc)
        art.shadow(doc, 196, 110)
        # Squat rack upright with J-hook + safety arm, behind the lifter.
        art.tube(doc, (112, GROUND - 2), (112, 24), 11, "butt")
        for y in range(40, GROUND - 20, 14):
            doc.add(f'<circle cx="112" cy="{y}" r="1.6" fill="#0C0E10"/>')
        art.tube(doc, (112, 84), (128, 84), 6)
        art.tube(doc, (128, 84), (130, 74), 4)
        art.tube(doc, (112, 200), (150, 200), 7)
        base(doc, 80, 150)
    else:
        art.plate(doc, bar, 25)
        doc.add(f'<circle cx="{bar[0]:.1f}" cy="{bar[1]:.1f}" r="6.5" fill="none" stroke="#A9B2BC" stroke-width="2.2"/>')


# ---- dumbbell curl -----------------------------------------------------------------------------

def db_curl(doc, j, layer):
    if layer == "back":
        art.floor(doc)
        art.shadow(doc, 200, 40)
        art.db_end(doc, grip(j, "F"), 10)
    else:
        art.db_end(doc, grip(j), 10.5)


# ---- push-up -----------------------------------------------------------------------------------

def push_up_scene(doc, j, layer):
    if layer == "back":
        art.floor(doc)
        art.shadow(doc, 190, 120)


def plank_on_floor(arm, wrist=(272, GROUND - 5), toe_y=GROUND - 1):
    """Rigid push-up body: solve the torso angle so the toes touch the floor with the hands pinned."""
    lo, hi = -60.0, 20.0
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


# ---- couch stretch -----------------------------------------------------------------------------

def couch(doc, j, layer):
    if layer == "back":
        art.floor(doc)
        art.shadow(doc, 190, 120)
        art.tube(doc, (72, 210), (72, GROUND - 2), 7, "butt")
        art.tube(doc, (144, 210), (144, GROUND - 2), 7, "butt")
        base(doc, 60, 156)
        art.pad(doc, (58, 210), (156, 210), 14)
        art.pad(doc, (150, GROUND), (222, GROUND), 5, stitch=False)


# ---- scenes ------------------------------------------------------------------------------------

SCENES = {
    "lat-pulldown": (pulldown, [
        P(t=-96, lN=(-2, 92, 0), lF=(2, 90, 0), aN=(-80, -84), aF=(-78, -82), pin=("hip", (150, 212))),
        P(t=-104, lN=(-2, 92, 0), lF=(2, 90, 0), aN=(97, -62), aF=(99, -60), pin=("hip", (150, 212))),
    ], (25, 14, 340)),
    "seated-cable-row": (cable_row, [
        P(t=-70, h=-60, lN=(-14, 36, -74), lF=(-10, 40, -70), aN=(30, 22), aF=(32, 24), pin=("hip", (128, 202))),
        P(t=-96, h=-90, lN=(-14, 36, -74), lF=(-10, 40, -70), aN=(122, -6), aF=(124, -4), pin=("hip", (128, 202))),
    ], (-14, 14, 376)),  # wide enough that the muscle-map inset (top left) clears the upright head
    "back-squat": (back_squat, [
        P(aN=(135, -60), aF=(130, -62), pin=("ankleN", (196, GROUND - 4))),
        P(t=-70, h=-80, lN=(50, 100, 0), lF=(52, 98, 0), aN=(155, -40), aF=(150, -42), pin=("ankleN", (196, GROUND - 4))),
        P(t=-50, h=-62, lN=(10, 110, 0), lF=(12, 108, 0), aN=(175, -20), aF=(170, -22), pin=("ankleN", (196, GROUND - 4))),
    ], (10, 28, 320)),
    "db-curl": (db_curl, [
        P(aN=(92, 86), aF=(96, 88), lF=(92, 88, 0), pin=("ankleN", (200, GROUND - 4))),
        P(aN=(88, -60), aF=(92, -56), lF=(92, 88, 0), pin=("ankleN", (200, GROUND - 4))),
    ], (40, 22, 330)),
    "push-up": (push_up_scene, [
        plank_on_floor((90, 90, 0)),
        plank_on_floor((145, 75, 0)),
        plank_on_floor((200, 60, 0)),
    ], (85, 76, 260)),
    "couch-stretch": (couch, [
        P(t=-62, h=-55, lF=(-2, 92, 0), lN=(110, -110, -110), aN=(85, 45), aF=(80, 40),
          pin=("ankleF", (252, GROUND - 4)), lit_sides="N"),
        P(t=-90, h=-90, lF=(-2, 92, 0), lN=(110, -110, -110), aN=(100, 60), aF=(96, 58),
          pin=("ankleF", (252, GROUND - 4)), lit_sides="N"),
    ], (45, 84, 250)),
}
