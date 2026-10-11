"""Equipment kit for the realistic exercise art (#170): common gym equipment in the art.py style.

Everything takes absolute view-box coordinates (400 x 300, figure faces right, floor surface at
art.GROUND = 266). Draw static equipment in a scene's "back" layer, things held in front of the body
in its "front" layer. Machines used by a single exercise are composed in the scene from these parts
and the art.py primitives (tube, pad, plate, stack, pulley, cable, shroud).
"""
import math

import art
from art import CHROME, GROUND, add, norm, sub


def floor(doc, cx=200, rx=120, x0=-200, x1=art.W + 200):
    art.floor(doc, x0, x1)
    art.shadow(doc, cx, rx)


def feet(doc, x0, x1, y=GROUND - 2):
    """Base rail on the floor."""
    art.tube(doc, (x0, y), (x1, y), 6)


def mat(doc, x0, x1, color="#2E6E8E"):
    doc.add(f'<rect x="{x0:.1f}" y="{GROUND - 4}" width="{x1 - x0:.1f}" height="5" rx="2.5" fill="{color}" '
            f'stroke="#0A0B0D" stroke-opacity="0.5" stroke-width="0.7"/>')


def flat_bench(doc, x0, x1, top=226, t=12):
    """Flat bench, pad top at `top`."""
    art.tube(doc, (x0 + 16, top + t), (x0 + 16, GROUND - 2), 7, "butt")
    art.tube(doc, (x1 - 16, top + t), (x1 - 16, GROUND - 2), 7, "butt")
    feet(doc, x0 + 4, x0 + 28)
    feet(doc, x1 - 28, x1 - 4)
    art.tube(doc, (x0 + 16, top + t + 3), (x1 - 16, top + t + 3), 6)
    art.pad(doc, (x0, top + t), (x1, top + t), t)


def incline_bench(doc, seat_x0, seat_x1, seat_top, back_len=96, back_ang=-135, t=12):
    """Adjustable bench: seat pad, backrest rising from the seat's left end at `back_ang` (deg; -90 upright,
    -135 = 45 deg incline, 180 = flat; facing right). Returns the backrest top point."""
    pivot = (seat_x0 + 4, seat_top + t)
    top = art.ang_pt(pivot, back_ang, back_len)
    art.tube(doc, ((seat_x0 + seat_x1) / 2, seat_top + t), ((seat_x0 + seat_x1) / 2, GROUND - 2), 8, "butt")
    art.tube(doc, (seat_x0 + 10, seat_top + t), art.ang_pt(pivot, back_ang, back_len * 0.55), 5)
    art.tube(doc, art.ang_pt(pivot, back_ang, back_len * 0.55), (seat_x0 - 30, GROUND - 2), 6)
    feet(doc, seat_x0 - 44, seat_x1 + 6)
    art.pad(doc, (seat_x0, seat_top + t), (seat_x1, seat_top + t), t)
    art.pad(doc, top, pivot, t)
    return top


def box(doc, x, w, h, color=("#5A4632", "#3E2F21")):
    """Plyo box / step / bench end, front face only."""
    g = doc.box_grad([(0, color[0]), (1, color[1])])
    doc.add(f'<rect x="{x:.1f}" y="{GROUND - h:.1f}" width="{w:.1f}" height="{h:.1f}" rx="3" fill="{g}" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>'
            f'<rect x="{x + 6:.1f}" y="{GROUND - h + 6:.1f}" width="{w - 12:.1f}" height="{max(2, h * 0.32):.1f}" rx="3" '
            f'fill="#000" fill-opacity="0.18"/>')


def wall(doc, x, w=14, top=8):
    g = doc.box_grad([(0, "#6F7782"), (1, "#4C535C")], vertical=False)
    doc.add(f'<rect x="{x:.1f}" y="{top}" width="{w}" height="{GROUND - top}" fill="{g}" stroke="#2A2F35" stroke-width="0.8"/>')


def rack(doc, x, hook_y=None, safety_y=None, top=20):
    """Squat-rack upright seen from the side, with J-hook and safety arm pointing right."""
    art.tube(doc, (x, GROUND - 2), (x, top), 11, "butt")
    for y in range(top + 16, GROUND - 16, 14):
        doc.add(f'<circle cx="{x}" cy="{y}" r="1.6" fill="#0C0E10"/>')
    if hook_y:
        art.tube(doc, (x, hook_y), (x + 16, hook_y), 6)
        art.tube(doc, (x + 16, hook_y), (x + 18, hook_y - 10), 4)
    if safety_y:
        art.tube(doc, (x, safety_y), (x + 46, safety_y), 7)
    feet(doc, x - 36, x + 36)


def barbell(doc, c, r=25):
    """Barbell end-on (bar points at the viewer): plate + sleeve collar."""
    art.plate(doc, c, r)
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{max(4, r * 0.24):.1f}" fill="none" stroke="#A9B2BC" stroke-width="2.2"/>')


def trap_bar(doc, c, r=24):
    """Hex bar end-on: plate on the sleeve, frame running to the handle at c."""
    art.plate(doc, (c[0], c[1] - 2), r)
    art.tube(doc, (c[0] - r - 8, c[1] - 2), (c[0] + r + 8, c[1] - 2), 4)


def dumbbell(doc, c, ang=None, r=10):
    """Dumbbell held at c: end-on hex (ang None) or seen from the side with its handle at `ang`."""
    if ang is None:
        art.db_end(doc, c, r)
    else:
        art.db_side(doc, c, ang, r)


def kettlebell(doc, c, up=False, r=11):
    """Kettlebell with its handle at c; `up` = racked/pressed, bell resting behind the wrist."""
    s = -1 if up else 1
    bell = (c[0], c[1] + s * (r + 5))
    g = doc.lin((bell[0] - r, bell[1] - r), (bell[0] + r, bell[1] + r), [(0, "#4A5058"), (0.5, "#24282D"), (1, "#101214")])
    doc.add(f'<path d="M{c[0] - 7:.1f},{c[1] + s * 5:.1f} Q{c[0] - 8:.1f},{c[1] - s * 7:.1f} {c[0]:.1f},{c[1] - s * 7:.1f} '
            f'Q{c[0] + 8:.1f},{c[1] - s * 7:.1f} {c[0] + 7:.1f},{c[1] + s * 5:.1f}" fill="none" stroke="#1A1D21" stroke-width="3.6"/>')
    doc.add(f'<circle cx="{bell[0]:.1f}" cy="{bell[1]:.1f}" r="{r}" fill="{g}" stroke="#08090A" stroke-width="0.9"/>')


def ball(doc, c, r=13, color=("#C0392B", "#7A1E16")):
    """Medicine / slam ball."""
    g = doc.lin((c[0] - r, c[1] - r), (c[0] + r, c[1] + r), [(0, color[0]), (1, color[1])])
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="{g}" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<path d="M{c[0] - r:.1f},{c[1]:.1f} Q{c[0]:.1f},{c[1] + r * 0.5:.1f} {c[0] + r:.1f},{c[1]:.1f}" fill="none" '
            f'stroke="#000" stroke-opacity="0.35" stroke-width="1"/>')


def pullup_bar(doc, c, top=4, half=34):
    """Pull-up bar end-on at c, held by a frame from the ceiling."""
    art.tube(doc, (c[0] - half, top), (c[0] - half, c[1]), 7, "butt")
    art.tube(doc, (c[0] - half, c[1]), (c[0] + 6, c[1]), 6)
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="4.6" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="1.8" fill="{CHROME}"/>')


def dip_bars(doc, x0, x1, y):
    """Parallel dip bar seen from the side (runs left-right), on two posts."""
    for x in (x0 + 8, x1 - 8):
        art.tube(doc, (x, y), (x, GROUND - 2), 8, "butt")
    feet(doc, x0 - 6, x1 + 6)
    art.tube(doc, (x0, y), (x1, y), 7)


def strap(doc, c, anchor, handle=True, color="#E8B32A"):
    """Suspension strap (TRX / rings) from `anchor` to c."""
    doc.add(f'<line x1="{anchor[0]:.1f}" y1="{anchor[1]:.1f}" x2="{c[0]:.1f}" y2="{c[1]:.1f}" stroke="#16181B" stroke-width="3.2"/>'
            f'<line x1="{anchor[0]:.1f}" y1="{anchor[1]:.1f}" x2="{c[0]:.1f}" y2="{c[1]:.1f}" stroke="{color}" stroke-width="1" '
            f'stroke-dasharray="6 10"/>')
    if handle:
        doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="4.4" fill="#1E2227" stroke="#0A0B0D" stroke-width="0.8"/>')


def ring(doc, c, anchor):
    doc.add(f'<line x1="{anchor[0]:.1f}" y1="{anchor[1]:.1f}" x2="{c[0]:.1f}" y2="{c[1] - 8:.1f}" stroke="#16181B" stroke-width="3"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="8" fill="none" stroke="#C8A06A" stroke-width="3.6"/>')


def band(doc, a, b, color="#2EAD5B"):
    """Resistance band stretched a→b."""
    doc.add(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="#0A0B0D" stroke-width="4.6" stroke-linecap="round"/>'
            f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="{color}" stroke-width="3" stroke-linecap="round"/>')


def post(doc, x, top):
    """Anchor post (rack upright / pole) from `top` to the floor."""
    art.tube(doc, (x, top - 10), (x, GROUND - 2), 9, "butt")
    feet(doc, x - 24, x + 24)


def cable_tower(doc, x, pulley_y, lift=0, w=34, top=24):
    """Cable column: stack in a shroud, pulley on the column's LEFT face at `pulley_y` (adjustable).
    The figure works to the left of it. Returns the pulley centre for art.cable()."""
    art.tube(doc, (x - 4, GROUND - 2), (x - 4, top), 9)
    art.shroud(doc, x + 2, top + 30, GROUND - 4, w + 8)
    st = art.stack(doc, x + 6, top + 44, GROUND - 4, w, 12, lift)
    art.tube(doc, (x - 8, top), (x + w + 14, top), 8)
    art.pulley(doc, (st[0], top + 7), 5.5)
    art.cable(doc, [(st[0] + 5.5, top + 7), st])
    p = (x - 12, pulley_y)
    art.tube(doc, (x - 4, pulley_y), (p[0] + 2, pulley_y), 5)
    art.pulley(doc, p, 6)
    return p


def handle(doc, c, kind="d"):
    """Cable attachment held at c: 'd' (D-handle / bar end-on), 'rope' or 'v'."""
    if kind == "rope":
        doc.add(f'<path d="M{c[0]:.1f},{c[1] - 8:.1f} q-3,8 0,16" fill="none" stroke="#1B1D20" stroke-width="5" stroke-linecap="round"/>'
                f'<circle cx="{c[0]:.1f}" cy="{c[1] + 8:.1f}" r="3.4" fill="#1B1D20"/>')
    elif kind == "v":
        doc.add(f'<path d="M{c[0] - 2:.1f},{c[1] - 6:.1f} l7,4 l-2,9 l-8,-2 z" fill="{CHROME}" stroke="#5A616A" stroke-width="0.8"/>'
                f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="4.6" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>')
    else:
        doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="5" fill="#2A2E34" stroke="#0A0B0D" stroke-width="0.9"/>'
                f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="2" fill="{CHROME}"/>')


def landmine(doc, end, anchor):
    """Landmine bar from the floor pivot `anchor` through the hands at `end`, plate on the sleeve beyond."""
    d = norm(sub(end, anchor))
    tip = add(end, d, 26)
    art.tube(doc, anchor, tip, 5)
    art.plate(doc, add(end, d, 18), 15, hub=False)
    doc.add(f'<rect x="{anchor[0] - 10:.1f}" y="{GROUND - 8:.1f}" width="20" height="8" rx="2" fill="#2A2E34"/>')


def foam_roller(doc, c, r=11):
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="#2B6FB8" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.4:.1f}" fill="#1B3F66"/>')


def ab_wheel(doc, c, r=12):
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="#1D2125" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.55:.1f}" fill="#C0392B"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="2.6" fill="{CHROME}"/>')


def arc(doc, c, r, a0, a1):
    """Dotted arc showing a range of motion."""
    s, e = art.ang_pt(c, a0, r), art.ang_pt(c, a1, r)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    doc.add(f'<path d="M{s[0]:.1f},{s[1]:.1f} A{r},{r} 0 {large} 1 {e[0]:.1f},{e[1]:.1f}" fill="none" stroke="#fff" '
            f'stroke-opacity="0.7" stroke-width="2.4" stroke-dasharray="2 6" stroke-linecap="round"/>')


def motion(doc, c, ang, length=24):
    """White arrow for direction of travel (use sparingly: jumps, throws)."""
    art.motion(doc, c, ang, length)


def roller_pad(doc, c, r=9):
    """Machine roller pad seen end-on."""
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="#1C1F24" stroke="#0A0B0D" stroke-width="0.9"/>'
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.3:.1f}" fill="#6D7681"/>')


def grip(j, side="N"):
    """Centre of the closed hand."""
    w, h = j["wrist" + side], j["hand" + side]
    return ((w[0] + h[0]) / 2, (w[1] + h[1]) / 2)


def torso_frame(j):
    """(unit vector hip→shoulder, unit vector towards the chest)."""
    t = art.norm(art.sub(j["shoulder"], j["hip"]))
    return t, (-t[1], t[0])


def on_back(j, back=14, up=3):
    """Barbell position on the upper back (high-bar squat)."""
    t, n = torso_frame(j)
    s = j["shoulder"]
    return (s[0] - n[0] * back + t[0] * up, s[1] - n[1] * back + t[1] * up)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])
