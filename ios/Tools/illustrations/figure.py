"""Pose-figure renderer for MonkeyWorkout exercise illustrations (own work, no third-party art).

A pose is a stick-and-capsule mannequin described by absolute segment angles
(degrees, 0 = +x/right, 90 = +y/down, SVG coordinates). Side view by default:
the figure faces right, "N" limbs are near the viewer (opaque), "F" limbs far
(translucent). `front=True` draws a frontal view where both sides are opaque.
"""
import math

W, H = 400, 300
FLOOR = 268

# Segment lengths (px in the 400x300 viewBox).
TORSO, NECK, HEAD_R = 72, 10, 15
UPPER_ARM, FOREARM, HAND = 42, 38, 10
THIGH, SHIN, FOOT = 56, 54, 14

LIMB_W, TORSO_W = 14, 26

WHITE = "#FFFFFF"


def _pt(p, ang, length):
    a = math.radians(ang)
    return (p[0] + math.cos(a) * length, p[1] + math.sin(a) * length)


def joints(pose):
    """Absolute joint positions relative to hip=(0,0)."""
    j = {"hip": (0.0, 0.0)}
    t = pose.get("t", -90)
    curl = pose.get("curl", 0)
    j["shoulder"] = _pt(j["hip"], t, TORSO)
    j["neck"] = _pt(j["shoulder"], pose.get("h", t), NECK)
    j["head"] = _pt(j["neck"], pose.get("h", t), HEAD_R)
    for side in "NF":
        thigh, shin, *foot = pose.get("l" + side, (90, 90))
        j["knee" + side] = _pt(j["hip"], thigh, THIGH)
        j["ankle" + side] = _pt(j["knee" + side], shin, SHIN)
        j["toe" + side] = _pt(j["ankle" + side], foot[0] if foot else shin - 90, FOOT)
        upper, fore, *hand = pose.get("a" + side, (90, 90))
        j["elbow" + side] = _pt(j["shoulder"], upper, UPPER_ARM)
        j["wrist" + side] = _pt(j["elbow" + side], fore, FOREARM)
        j["hand" + side] = _pt(j["wrist" + side], hand[0] if hand else fore, HAND)
    j["_curl"] = curl
    j["_t"] = t
    return j


# Which drawn segment lights up for each primary muscle.
MUSCLE_SEGMENTS = {
    "quads": ["thigh"], "hamstrings": ["thigh"], "adductors": ["thigh"], "hipFlexors": ["thigh"],
    "glutes": ["hipblob"], "calves": ["shin"],
    "chest": ["torso"], "abs": ["torso"], "obliques": ["torso"], "lowerBack": ["torso"],
    "upperBack": ["torso"], "lats": ["torso"],
    "frontDelts": ["shoulderblob"], "sideDelts": ["shoulderblob"], "rearDelts": ["shoulderblob"],
    "rotatorCuff": ["shoulderblob"],
    "biceps": ["upper"], "triceps": ["upper"], "forearms": ["fore"],
}


def _line(a, b, w, color, opacity=1.0, cap="round"):
    return (f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" '
            f'stroke="{color}" stroke-width="{w}" stroke-linecap="{cap}" stroke-opacity="{opacity}"/>')


def _poly(points, w, color, opacity=1.0):
    d = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
    return (f'<polyline points="{d}" fill="none" stroke="{color}" stroke-width="{w}" '
            f'stroke-linecap="round" stroke-linejoin="round" stroke-opacity="{opacity}"/>')


def _circle(c, r, fill, opacity=1.0):
    return f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="{fill}" fill-opacity="{opacity}"/>'


def _torso(j, w, color, opacity=1.0):
    a, b, curl = j["hip"], j["shoulder"], j["_curl"]
    if not curl:
        return _line(a, b, w, color, opacity)
    # Quadratic curve bowed perpendicular to the torso (positive = towards the back).
    mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    nx, ny = math.cos(math.radians(j["_t"] + 90)), math.sin(math.radians(j["_t"] + 90))
    c = (mx - nx * curl, my - ny * curl)
    return (f'<path d="M{a[0]:.1f},{a[1]:.1f} Q{c[0]:.1f},{c[1]:.1f} {b[0]:.1f},{b[1]:.1f}" fill="none" '
            f'stroke="{color}" stroke-width="{w}" stroke-linecap="round" stroke-opacity="{opacity}"/>')


def figure_svg(j, lit, accent, front=False):
    """SVG elements for the figure. `lit` = set of segment kinds to highlight."""
    out = []
    far = 1.0 if front else 0.42

    def limb(side, op):
        leg = [j["hip"], j["knee" + side], j["ankle" + side], j["toe" + side]]
        arm = [j["shoulder"], j["elbow" + side], j["wrist" + side], j["hand" + side]]
        return leg, arm, op

    layers = [limb("F", far)]
    # Far limbs first, then torso/head, then near limbs.
    for leg, arm, op in layers:
        out += _limb_parts(leg, arm, op, lit, accent)
    out.append(_torso(j, TORSO_W, WHITE))
    if "torso" in lit:
        out.append(_torso(j, TORSO_W - 8, accent))
    if "hipblob" in lit:
        out.append(_circle(j["hip"], 10, accent))
    out.append(_line(j["shoulder"], j["neck"], 10, WHITE))
    out.append(_circle(j["head"], HEAD_R, WHITE))
    leg, arm, op = limb("N", 1.0)
    out += _limb_parts(leg, arm, op, lit, accent)
    if "shoulderblob" in lit:
        out.append(_circle(j["shoulder"], 9, accent))
    return out


def _limb_parts(leg, arm, op, lit, accent):
    out = [_poly(leg, LIMB_W, WHITE, op), _poly(arm, LIMB_W - 2, WHITE, op)]
    hl = 1.0 if op == 1.0 else 0.6
    if "thigh" in lit:
        out.append(_line(leg[0], leg[1], LIMB_W - 6, accent, hl))
    if "shin" in lit:
        out.append(_line(leg[1], leg[2], LIMB_W - 6, accent, hl))
    if "upper" in lit:
        out.append(_line(arm[0], arm[1], LIMB_W - 7, accent, hl))
    if "fore" in lit:
        out.append(_line(arm[1], arm[2], LIMB_W - 7, accent, hl))
    return out


# ---- props -------------------------------------------------------------------------------

PROP = "#FFFFFF"
PROP_OP = 0.55


def _at(j, ref):
    if isinstance(ref, str):
        return j[ref]
    if isinstance(ref, tuple) and len(ref) == 3:  # (joint, dx, dy)
        p = j[ref[0]]
        return (p[0] + ref[1], p[1] + ref[2])
    return ref


def props_svg(j, props):
    out = []
    for p in props:
        kind, args = p[0], p[1:]
        out += PROP_DRAW[kind](j, *args)
    return out


def _rect(x, y, w, h, op=PROP_OP, r=4):
    return (f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r}" '
            f'fill="{PROP}" fill-opacity="{op}"/>')


def p_floor(j):
    return [_line((14, FLOOR + 8), (W - 14, FLOOR + 8), 3, PROP, 0.35)]


def p_mat(j, x0, x1):
    h = j["hip"][0]
    x0, x1 = h + x0, h + x1
    return [_rect(x0, FLOOR + 5, x1 - x0, 6, 0.4, 3)]


def p_bench(j, ref, w=110, dx=0, top_off=9):
    """Flat bench whose pad sits just under `ref` (a joint)."""
    c = _at(j, ref)
    top = c[1] + top_off
    x = c[0] - w / 2 + dx
    return [_rect(x, top, w, 10, 0.6),
            _rect(x + 10, top + 10, 8, FLOOR + 8 - top - 10, 0.45, 2),
            _rect(x + w - 18, top + 10, 8, FLOOR + 8 - top - 10, 0.45, 2)]


def p_box(j, x, w, h):
    x = j["hip"][0] + x
    return [_rect(x, FLOOR + 8 - h, w, h, 0.5)]


def p_pad(j, a, b, off=10, w=12):
    """Pad parallel to segment a→b, offset `off` px along the segment normal (below for left→right)."""
    pa, pb = _at(j, a), _at(j, b)
    dx, dy = pb[0] - pa[0], pb[1] - pa[1]
    n = math.hypot(dx, dy) or 1
    nx, ny = -dy / n, dx / n
    if ny < 0:
        nx, ny = -nx, -ny
    s = lambda p: (p[0] + nx * off, p[1] + ny * off)
    return [_line(s(pa), s(pb), w, PROP, 0.6)]


def p_post(j, ref):
    """Vertical support from a point down to the floor."""
    c = _at(j, ref)
    return [_line(c, (c[0], FLOOR + 8), 8, PROP, 0.45, "butt")]


def p_dumbbell(j, ref, ang=None):
    c = _at(j, ref)
    if ang is None:
        return [_rect(c[0] - 13, c[1] - 7, 26, 14, 0.85, 4), _line((c[0] - 9, c[1]), (c[0] + 9, c[1]), 4, "#000", 0.25)]
    a = math.radians(ang)
    e1 = (c[0] + math.cos(a) * 14, c[1] + math.sin(a) * 14)
    e2 = (c[0] - math.cos(a) * 14, c[1] - math.sin(a) * 14)
    return [_line(e1, e2, 4, PROP, 0.85), _circle(e1, 7, PROP, 0.85), _circle(e2, 7, PROP, 0.85)]


def p_kettlebell(j, ref, up=False):
    c = _at(j, ref)
    if up:
        return [_circle((c[0], c[1] - 14), 11, PROP, 0.85),
                f'<path d="M{c[0]-6:.1f},{c[1]-4:.1f} Q{c[0]:.1f},{c[1]+6:.1f} {c[0]+6:.1f},{c[1]-4:.1f}" fill="none" stroke="{PROP}" stroke-opacity="0.85" stroke-width="4"/>']
    return [_circle((c[0], c[1] + 15), 11, PROP, 0.85),
            f'<path d="M{c[0]-6:.1f},{c[1]+5:.1f} Q{c[0]:.1f},{c[1]-6:.1f} {c[0]+6:.1f},{c[1]+5:.1f}" fill="none" stroke="{PROP}" stroke-opacity="0.85" stroke-width="4"/>']


def p_plate(j, ref, r=24, dx=0, dy=0):
    c = _at(j, ref)
    c = (c[0] + dx, c[1] + dy)
    return [_circle(c, r, PROP, 0.5), _circle(c, 5, PROP, 0.9)]


def p_ball(j, ref, r=13, dx=0, dy=0):
    c = _at(j, ref)
    return [_circle((c[0] + dx, c[1] + dy), r, PROP, 0.85)]


def p_bar(j, ref, half=30):
    """Horizontal bar (pull-up bar) through `ref`, with uprights to the top edge."""
    c = _at(j, ref)
    return [_line((c[0] - half, c[1]), (c[0] + half, c[1]), 6, PROP, 0.8),
            _line((c[0] - half, c[1]), (c[0] - half, 0), 5, PROP, 0.4, "butt"),
            _line((c[0] + half, c[1]), (c[0] + half, 0), 5, PROP, 0.4, "butt")]


def p_strap(j, ref, top_x):
    c = _at(j, ref)
    return [_line(c, (top_x, 0), 3, PROP, 0.6), _circle(c, 6, PROP, 0.8)]


def p_ring(j, ref):
    c = _at(j, ref)
    return [_line((c[0], c[1] - 9), (c[0], 0), 3, PROP, 0.6),
            f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="8" fill="none" stroke="{PROP}" stroke-opacity="0.85" stroke-width="4"/>']


def p_band(j, a, b):
    return [_line(_at(j, a), _at(j, b), 4, PROP, 0.85)]


def p_wall(j, x):
    x = j["hip"][0] + x
    return [_rect(x, 20, 12, FLOOR + 8 - 20, 0.4, 2)]


def p_panel(j, x, y, w, h):
    x = j["hip"][0] + x
    return [_rect(x, y, w, h, 0.16, 10)]


def p_roller(j, ref, dx=0):
    c = _at(j, ref)
    return [_circle((c[0] + dx, FLOOR + 8 - 13), 13, PROP, 0.6)]


def p_landmine(j, ref, anchor_x):
    c = _at(j, ref)
    a = (j["hip"][0] + anchor_x, FLOOR + 6)
    dx, dy = c[0] - a[0], c[1] - a[1]
    n = math.hypot(dx, dy)
    end = (c[0] + dx / n * 16, c[1] + dy / n * 16)
    return [_line(a, end, 6, PROP, 0.8), _circle(end, 9, PROP, 0.6), _rect(a[0] - 8, a[1] - 4, 16, 8, 0.6, 2)]


def p_arc(j, ref, r, a0, a1):
    c = _at(j, ref)
    s = (c[0] + r * math.cos(math.radians(a0)), c[1] + r * math.sin(math.radians(a0)))
    e = (c[0] + r * math.cos(math.radians(a1)), c[1] + r * math.sin(math.radians(a1)))
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return [f'<path d="M{s[0]:.1f},{s[1]:.1f} A{r},{r} 0 {large} 1 {e[0]:.1f},{e[1]:.1f}" fill="none" '
            f'stroke="{PROP}" stroke-opacity="0.6" stroke-width="3" stroke-dasharray="2 7" stroke-linecap="round"/>']


def p_motion(j, ref, ang, length=26, dx=0, dy=0):
    """Small arrow showing direction of travel."""
    c = _at(j, ref)
    c = (c[0] + dx, c[1] + dy)
    a = math.radians(ang)
    e = (c[0] + math.cos(a) * length, c[1] + math.sin(a) * length)
    l = (e[0] - math.cos(a - 0.6) * 9, e[1] - math.sin(a - 0.6) * 9)
    r = (e[0] - math.cos(a + 0.6) * 9, e[1] - math.sin(a + 0.6) * 9)
    return [_poly([c, e], 3, PROP, 0.7), _poly([l, e, r], 3, PROP, 0.7)]


def p_skierg(j, x):
    x = j["hip"][0] + x
    top = 40
    return [_rect(x, top, 18, FLOOR + 8 - top, 0.45, 6), _rect(x - 14, FLOOR - 2, 46, 10, 0.45, 3)]


def p_cords(j, x, a, b):
    x = j["hip"][0] + x
    top = (x + 9, 48)
    return [_line(top, _at(j, a), 2.5, PROP, 0.7), _line(top, _at(j, b), 2.5, PROP, 0.5)]


def p_airbike(j, seat_ref, wheel_x):
    s = _at(j, seat_ref)
    wc = (j["hip"][0] + wheel_x, FLOOR + 8 - 40)
    crank = (s[0] + 34, FLOOR - 26)
    return [
        f'<circle cx="{wc[0]:.1f}" cy="{wc[1]:.1f}" r="40" fill="none" stroke="{PROP}" stroke-opacity="0.5" stroke-width="7"/>',
        _line((s[0], s[1] + 10), crank, 7, PROP, 0.5),
        _line(crank, wc, 7, PROP, 0.5),
        _line((s[0] - 14, s[1] + 9), (s[0] + 12, s[1] + 9), 8, PROP, 0.7),
        _line((s[0] - 20, FLOOR + 6), (wc[0] + 30, FLOOR + 6), 6, PROP, 0.45),
        _circle(crank, 8, PROP, 0.6),
    ]


def p_handles(j, pivot, a, b):
    pv = _at(j, pivot)
    return [_line(pv, _at(j, a), 5, PROP, 0.7), _line(pv, _at(j, b), 5, PROP, 0.4)]


def p_breath(j, ref, n=3):
    c = _at(j, ref)
    out = []
    for i in range(n):
        r = 12 + i * 9
        out.append(f'<path d="M{c[0]-r:.1f},{c[1]-6-i*4:.1f} Q{c[0]:.1f},{c[1]-r-14:.1f} {c[0]+r:.1f},{c[1]-6-i*4:.1f}" '
                   f'fill="none" stroke="{PROP}" stroke-opacity="{0.7 - i*0.18:.2f}" stroke-width="3" stroke-linecap="round"/>')
    return out


def p_machine(j, x, y, w, h):
    x = j["hip"][0] + x
    return [_rect(x, y, w, h, 0.4, 8)]


def p_seat(j, ref, w=46, h=None):
    c = _at(j, ref)
    top = c[1] + 9
    return [_rect(c[0] - w / 2, top, w, 10, 0.65), _rect(c[0] - 5, top + 10, 10, FLOOR + 8 - top - 10, 0.45, 2)]


PROP_DRAW = {k[2:]: v for k, v in globals().items() if k.startswith("p_")}


# ---- placement ---------------------------------------------------------------------------

def place(pose):
    """Joints in viewBox coordinates: grounded on the floor and centred, unless pinned."""
    j = joints(pose)
    pts = {k: v for k, v in j.items() if not k.startswith("_")}
    if "pin" in pose:
        name, (px, py) = pose["pin"]
        dx, dy = px - pts[name][0], py - pts[name][1]
    else:
        # Lowest joint touches the floor (stroke radius accounted for).
        def bottom(k):
            r = HEAD_R if k == "head" else (TORSO_W / 2 if k in ("hip", "shoulder") else LIMB_W / 2)
            return pts[k][1] + r
        lowest = max(bottom(k) for k in pts)
        dy = FLOOR + 1 - lowest - pose.get("lift", 0)
        xs = [p[0] for p in pts.values()]
        dx = W / 2 - (min(xs) + max(xs)) / 2 + pose.get("dx", 0)
    out = {k: ((v[0] + dx, v[1] + dy) if not k.startswith("_") else v) for k, v in j.items()}
    return out
