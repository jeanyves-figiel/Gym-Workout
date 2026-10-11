"""Realistic exercise art (#168): shaded anatomical figure, highlighted muscles, drawn equipment. Own work.

Reuses the pose model of figure.py (absolute segment angles, side view facing right) but draws every
segment as a filled, tapered body shape with soft shading. Muscles are shapes in each segment's local
frame (u along the segment 0..1, v across it: +1 front edge, -1 back edge) so they follow the pose.
Worked muscles use the app's load colours (Theme.heat): primary = heat(1), secondary = heat(0.45).
Equipment is drawn from primitives (steel tubes, upholstered pads, plates, weight stacks, pulleys,
cables) in absolute coordinates, so a machine stays still while the figure moves between frames.
"""
import colorsys
import math

import figure as F

W, H, FLOOR = F.W, F.H, F.FLOOR
GROUND = 266  # floor surface: a standing figure's ankle sits at GROUND - 4


def heat(v, s=0.85, b=1.0):
    r, g, bb = colorsys.hsv_to_rgb(0.22 * (1 - v), s, b)
    return f"#{int(r * 255):02x}{int(g * 255):02x}{int(bb * 255):02x}"


PRIMARY, SECONDARY = 1.0, 0.45

# Body tones: near side lit / mid / shade, far side darker.
SKIN_NEAR = ("#F4F6F9", "#D9DEE5", "#9EA8B5")
SKIN_FAR = ("#C3CAD3", "#A9B1BC", "#7E8895")
OUTLINE = "#3D4552"
LIGHT = (0.28, -0.96)  # light from above, slightly in front


# ---- geometry --------------------------------------------------------------------------------

def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def norm(v):
    n = math.hypot(*v) or 1.0
    return (v[0] / n, v[1] / n)


def ang_pt(p, ang, length):
    a = math.radians(ang)
    return (p[0] + math.cos(a) * length, p[1] + math.sin(a) * length)


class Seg:
    """Centre line a→b (optionally a quadratic curve through control c) with a width profile."""

    def __init__(self, a, b, profile, kind="limb", c=None):
        self.a, self.b, self.c, self.profile, self.kind = a, b, c, profile, kind

    def pos(self, u):
        a, b, c = self.a, self.b, self.c
        if u < 0 or u > 1:
            e = 0 if u < 0 else 1
            return add(self.pos(e), self.tan(e), (u - e) * self.length())
        if c is None:
            return (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u)
        m = 1 - u
        return (m * m * a[0] + 2 * m * u * c[0] + u * u * b[0], m * m * a[1] + 2 * m * u * c[1] + u * u * b[1])

    def tan(self, u):
        u = min(1, max(0, u))
        a, b, c = self.a, self.b, self.c
        if c is None:
            return norm(sub(b, a))
        return norm((2 * (1 - u) * (c[0] - a[0]) + 2 * u * (b[0] - c[0]),
                     2 * (1 - u) * (c[1] - a[1]) + 2 * u * (b[1] - c[1])))

    def length(self):
        return math.hypot(*sub(self.b, self.a))

    def normal(self, u):
        """Unit vector towards the front (anterior) edge."""
        t = self.tan(u)
        return (-t[1], t[0]) if self.kind == "up" else (t[1], -t[0])

    def width(self, u, side):
        p = self.profile
        u = min(p[-1][0], max(p[0][0], u))
        for (u0, f0, b0), (u1, f1, b1) in zip(p, p[1:]):
            if u0 <= u <= u1:
                k = (u - u0) / ((u1 - u0) or 1)
                return (f0 + (f1 - f0) * k) if side > 0 else (b0 + (b1 - b0) * k)
        return p[-1][1] if side > 0 else p[-1][2]

    def at(self, u, v):
        w = self.width(u, 1 if v >= 0 else -1)
        return add(self.pos(u), self.normal(u), v * w)

    def outline(self, n=10):
        front = [self.at(i / n, 1) for i in range(n + 1)]
        back = [self.at(1 - i / n, -1) for i in range(n + 1)]
        return front + self._cap(1) + back + self._cap(0)

    def _cap(self, e):
        c, t, nrm = self.pos(e), self.tan(e), self.normal(e)
        if e == 0:
            t = (-t[0], -t[1])
        f, b = self.width(e, 1), self.width(e, -1)
        r = min(f, b) * 0.95
        pts = []
        for th in (40, 90, 140) if e == 1 else (140, 90, 40):
            ct, st = math.cos(math.radians(th)), math.sin(math.radians(th))
            side = f if ct >= 0 else b
            pts.append(add(add(c, nrm, ct * side), t, st * r))
        return pts


def smooth(pts, closed=True, k=0.18):
    """Catmull-Rom through the points as cubic Béziers (SVG path data)."""
    n = len(pts)
    if n < 3:
        return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    d = [f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"]
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[0]
        p1, p2 = pts[i], pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else p2
        c1 = (p1[0] + (p2[0] - p0[0]) * k, p1[1] + (p2[1] - p0[1]) * k)
        c2 = (p2[0] - (p3[0] - p1[0]) * k, p2[1] - (p3[1] - p1[1]) * k)
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    return " ".join(d) + (" Z" if closed else "")


# ---- document --------------------------------------------------------------------------------

class Doc:
    def __init__(self, prefix="a"):
        self.defs, self.body, self.n, self.prefix, self.view = [], [], 0, prefix, None

    def uid(self, kind):
        self.n += 1
        return f"{self.prefix}{kind}{self.n}"

    def lin(self, p0, p1, stops):
        i = self.uid("g")
        s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
        self.defs.append(f'<linearGradient id="{i}" gradientUnits="userSpaceOnUse" x1="{p0[0]:.1f}" y1="{p0[1]:.1f}" '
                         f'x2="{p1[0]:.1f}" y2="{p1[1]:.1f}">{s}</linearGradient>')
        return f"url(#{i})"

    def box_grad(self, stops, vertical=True):
        i = self.uid("g")
        s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
        xy = 'x1="0" y1="0" x2="0" y2="1"' if vertical else 'x1="0" y1="0" x2="1" y2="0"'
        self.defs.append(f'<linearGradient id="{i}" {xy}>{s}</linearGradient>')
        return f"url(#{i})"

    def clip(self, d):
        i = self.uid("c")
        self.defs.append(f'<clipPath id="{i}"><path d="{d}"/></clipPath>')
        return f"url(#{i})"

    def add(self, s):
        self.body.append(s)

    def svg(self):
        x, y, w = self.view or (0, 0, W)
        h = w * H / W
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x} {y} {w} {h:g}" width="{W}" height="{H}">'
                f'<defs>{"".join(self.defs)}</defs>' + "".join(self.body) + "</svg>\n")


def lit_axis(seg, u=0.5):
    """Gradient end points across the segment, from shaded edge to lit edge."""
    nrm = seg.normal(u)
    s = 1 if nrm[0] * LIGHT[0] + nrm[1] * LIGHT[1] < 0 else -1  # +1: front edge faces the light
    lit, dark = seg.at(u, s), seg.at(u, -s)
    return dark, lit


# ---- body ------------------------------------------------------------------------------------

# (u, front half-width, back half-width), px in the 400 x 300 view box.
PROFILES = {
    "thigh": [(0, 13.5, 14.5), (0.3, 12.5, 11.5), (0.7, 10, 9), (1, 7.5, 7)],
    "shin": [(0, 7, 7), (0.25, 6, 10), (0.5, 5.5, 8), (0.85, 4, 4), (1, 4, 4.2)],
    "foot": [(0, 5, 4), (0.6, 3.6, 3), (1, 2.6, 2.4)],
    "upper": [(0, 9.5, 9.5), (0.18, 9.5, 9), (0.5, 7.6, 8.2), (0.9, 5.6, 5.6), (1, 5.2, 5.2)],
    "fore": [(0, 5.4, 5.4), (0.25, 6.4, 6), (0.8, 4, 3.8), (1, 3.4, 3.4)],
    "hand": [(0, 3.6, 3.6), (0.5, 4.6, 4.2), (1, 3.8, 3.6)],
    "torso": [(0, 13, 15.5), (0.2, 12.5, 13), (0.45, 11, 11), (0.7, 14.5, 13.5), (0.88, 14, 13.5), (1, 10.5, 11.5)],
    "neck": [(0, 6, 6.5), (1, 5.2, 5.6)],
    "head": [(0, 5.8, 6.4), (0.22, 10.5, 9.5), (0.48, 13.2, 13.4), (0.55, 14.2, 13.6), (0.8, 12, 13), (1, 5, 6.5)],
}

# Athletic build: limbs and trunk a little fuller than the stick-figure capsules.
BULK = {"thigh": 1.2, "shin": 1.18, "upper": 1.22, "fore": 1.16, "torso": 1.12, "neck": 1.15}
PROFILES = {k: [(u, f * BULK.get(k, 1), b * BULK.get(k, 1)) for u, f, b in v] for k, v in PROFILES.items()}

# Muscles: (segment, polygon in (u, v), fibres "u" | "v"). Several entries = several pieces.
MUSCLES = {
    "quads": [("thigh", [(0.16, 0.15), (0.26, 1.02), (0.55, 1.02), (0.8, 0.98), (0.97, 0.5), (0.9, 0.05), (0.55, 0.0), (0.32, 0.02)], "u")],
    "hamstrings": [("thigh", [(0.22, -0.12), (0.34, -1.02), (0.65, -1.02), (0.88, -0.92), (0.98, -0.45), (0.85, -0.08), (0.5, -0.1)], "u")],
    "adductors": [("thigh", [(0.06, -0.06), (0.14, 0.22), (0.42, 0.14), (0.66, -0.02), (0.42, -0.16), (0.18, -0.14)], "u")],
    "hipFlexors": [("thigh", [(-0.04, 0.6), (0.0, 1.02), (0.2, 1.0), (0.3, 0.55), (0.12, 0.3)], "u"),
                   ("torso", [(0.0, 0.55), (0.0, 1.0), (0.12, 1.02), (0.22, 0.75), (0.2, 0.45)], "u")],
    "glutes": [("thigh", [(-0.04, -0.15), (-0.02, -1.02), (0.12, -1.04), (0.3, -0.86), (0.3, -0.3), (0.12, -0.08)], "v"),
               ("torso", [(-0.02, -1.02), (0.08, -1.04), (0.2, -0.9), (0.24, -0.45), (0.1, -0.2), (-0.02, -0.4)], "v")],
    "gluteMed": [("torso", [(0.02, -0.58), (0.16, -0.62), (0.26, -0.18), (0.14, 0.12), (0.02, -0.12)], "u")],
    "calves": [("shin", [(0.04, -0.3), (0.1, -1.02), (0.32, -1.04), (0.52, -0.72), (0.58, -0.2), (0.3, -0.04)], "u")],
    "soleus": [("shin", [(0.34, -0.92), (0.58, -1.02), (0.82, -0.86), (0.8, -0.2), (0.56, -0.12)], "u")],
    "tibialis": [("shin", [(0.08, 0.3), (0.12, 1.02), (0.6, 1.02), (0.86, 0.7), (0.7, 0.28), (0.3, 0.22)], "u")],
    "chest": [("torso", [(0.64, 0.18), (0.62, 0.9), (0.72, 1.03), (0.86, 1.03), (0.98, 0.72), (0.94, 0.25), (0.8, 0.08)], "v")],
    "abs": [("torso", [(0.2, 0.55), (0.2, 1.02), (0.64, 1.02), (0.66, 0.55), (0.42, 0.5)], "u")],
    "lowerAbs": [("torso", [(0.08, 0.5), (0.1, 1.02), (0.34, 1.02), (0.36, 0.5)], "u")],
    "obliques": [("torso", [(0.18, 0.5), (0.26, -0.02), (0.55, -0.12), (0.68, 0.28), (0.62, 0.55), (0.35, 0.6)], "uv")],
    "serratus": [("torso", [(0.55, 0.28), (0.6, -0.02), (0.76, 0.08), (0.82, 0.45), (0.66, 0.62)], "v")],
    "deepCore": [("torso", [(0.12, 0.15), (0.16, 0.65), (0.6, 0.65), (0.62, 0.2), (0.38, 0.02)], "v")],
    "lats": [("torso", [(0.3, -0.5), (0.36, -1.02), (0.62, -1.03), (0.86, -0.98), (0.93, -0.3), (0.84, 0.22), (0.62, 0.12), (0.45, -0.1)], "uv")],
    "upperBack": [("torso", [(0.62, -1.02), (0.96, -1.03), (1.0, -0.5), (0.86, -0.38), (0.68, -0.58)], "v")],
    "traps": [("torso", [(0.8, -0.62), (0.88, -1.03), (1.04, -0.92), (1.13, -0.36), (1.02, -0.02), (0.9, -0.22)], "u")],
    "lowerBack": [("torso", [(0.08, -0.62), (0.1, -1.02), (0.46, -1.02), (0.5, -0.66), (0.3, -0.52)], "u")],
    "rotatorCuff": [("torso", [(0.74, -0.36), (0.78, -0.82), (0.95, -0.76), (0.96, -0.32)], "v")],
    "frontDelts": [("upper", [(-0.14, 0.15), (-0.06, 0.98), (0.14, 1.03), (0.34, 0.62), (0.32, 0.12), (0.1, 0.0)], "u")],
    "sideDelts": [("upper", [(-0.18, -0.3), (-0.16, 0.3), (0.1, 0.38), (0.4, 0.0), (0.1, -0.38)], "u")],
    "rearDelts": [("upper", [(-0.14, -0.15), (-0.06, -0.98), (0.14, -1.03), (0.34, -0.62), (0.32, -0.12), (0.1, 0.0)], "u")],
    "biceps": [("upper", [(0.28, 0.22), (0.34, 1.03), (0.6, 1.03), (0.82, 0.82), (0.9, 0.4), (0.6, 0.18)], "u")],
    "triceps": [("upper", [(0.2, -0.2), (0.28, -1.03), (0.66, -1.03), (0.92, -0.72), (0.96, -0.28), (0.6, -0.18)], "u")],
    "brachialis": [("upper", [(0.55, 0.08), (0.62, 0.34), (0.85, 0.46), (0.96, 0.2), (0.86, -0.12), (0.66, -0.06)], "u")],
    "forearms": [("fore", [(0.04, 0.2), (0.1, 1.03), (0.45, 0.98), (0.76, 0.6), (0.7, 0.1), (0.3, 0.0)], "u")],
    "forearmExtensors": [("fore", [(0.04, -0.2), (0.1, -1.03), (0.45, -0.98), (0.76, -0.6), (0.7, -0.1), (0.3, 0.0)], "u")],
}

def _mirror(poly):
    return [(u, -v) for u, v in poly]


def _both(seg, poly, fib="u"):
    return [(seg, poly, fib), (seg, _mirror(poly), fib)]


# Front and back views: v runs across the segment (-1 one edge, +1 the other); shapes are symmetric.
FRONT_MUSCLES = {
    "chest": _both("torso", [(0.64, 0.06), (0.64, 0.9), (0.8, 1.02), (0.95, 0.9), (0.98, 0.4), (0.93, 0.06)], "v"),
    "abs": [("torso", [(0.2, -0.3), (0.2, 0.3), (0.64, 0.34), (0.64, -0.34)], "u")],
    "lowerAbs": [("torso", [(0.04, -0.28), (0.04, 0.28), (0.21, 0.3), (0.21, -0.3)], "u")],
    "obliques": _both("torso", [(0.16, 0.38), (0.2, 1.02), (0.6, 1.02), (0.64, 0.4)], "uv"),
    "serratus": _both("torso", [(0.58, 0.72), (0.6, 1.02), (0.74, 1.02), (0.72, 0.74)], "v"),
    "deepCore": [("torso", [(0.08, -0.62), (0.08, 0.62), (0.45, 0.62), (0.45, -0.62)], "v")],
    "hipFlexors": _both("torso", [(-0.02, 0.32), (-0.02, 0.78), (0.12, 0.72), (0.12, 0.38)], "u")
                  + [("thigh", [(0.0, -0.5), (0.0, 0.5), (0.22, 0.38), (0.22, -0.38)], "u")],
    "traps": _both("torso", [(0.94, 0.28), (1.12, 0.14), (1.12, 0.42), (1.0, 0.78)], "u"),
    "gluteMed": _both("torso", [(0.02, 0.8), (0.04, 1.02), (0.2, 1.02), (0.2, 0.84)], "u"),
    "quads": [("thigh", [(0.14, -0.82), (0.14, 0.82), (0.96, 0.62), (0.96, -0.62)], "u")],
    "adductors": [("thigh", [(0.08, -0.3), (0.08, 0.3), (0.55, 0.28), (0.55, -0.28)], "u")],
    "tibialis": [("shin", [(0.1, -0.15), (0.1, 0.6), (0.72, 0.5), (0.72, -0.15)], "u")],
    "calves": _both("shin", [(0.1, 0.62), (0.1, 1.02), (0.5, 1.02), (0.5, 0.62)], "u"),
    "biceps": [("upper", [(0.3, -0.72), (0.3, 0.72), (0.9, 0.5), (0.9, -0.5)], "u")],
    "brachialis": _both("upper", [(0.6, 0.55), (0.6, 1.02), (0.96, 1.02), (0.96, 0.55)], "u"),
    "frontDelts": [("upper", [(-0.16, -0.92), (-0.16, 0.92), (0.34, 0.72), (0.34, -0.72)], "u")],
    "sideDelts": [("upper", [(-0.18, -1.02), (-0.18, 1.02), (0.4, 0.8), (0.4, -0.8)], "u")],
    "forearms": [("fore", [(0.05, -0.82), (0.05, 0.82), (0.76, 0.42), (0.76, -0.42)], "u")],
}
BACK_MUSCLES = {
    "lats": _both("torso", [(0.34, 0.2), (0.52, 1.02), (0.86, 1.02), (0.93, 0.5), (0.7, 0.14)], "uv"),
    "upperBack": [("torso", [(0.62, -0.48), (0.62, 0.48), (0.96, 0.62), (0.96, -0.62)], "v")],
    "traps": [("torso", [(0.58, 0.0), (0.94, 0.76), (1.12, 0.3), (1.12, -0.3), (0.94, -0.76)], "u")],
    "lowerBack": [("torso", [(0.06, -0.4), (0.06, 0.4), (0.46, 0.3), (0.46, -0.3)], "u")],
    "rotatorCuff": _both("torso", [(0.72, 0.42), (0.75, 0.86), (0.92, 0.86), (0.92, 0.42)], "v"),
    "glutes": [("torso", [(-0.04, -0.96), (-0.04, 0.96), (0.18, 0.9), (0.18, -0.9)], "v"),
               ("thigh", [(-0.06, -1.0), (-0.06, 1.0), (0.26, 0.9), (0.26, -0.9)], "v")],
    "gluteMed": _both("torso", [(0.1, 0.6), (0.1, 1.02), (0.24, 1.02), (0.24, 0.6)], "u"),
    "hamstrings": [("thigh", [(0.24, -0.82), (0.24, 0.82), (0.96, 0.6), (0.96, -0.6)], "u")],
    "adductors": [("thigh", [(0.1, -0.3), (0.1, 0.3), (0.5, 0.26), (0.5, -0.26)], "u")],
    "calves": [("shin", [(0.05, -0.92), (0.05, 0.92), (0.55, 0.72), (0.55, -0.72)], "u")],
    "soleus": [("shin", [(0.46, -0.72), (0.46, 0.72), (0.86, 0.42), (0.86, -0.42)], "u")],
    "triceps": [("upper", [(0.24, -0.76), (0.24, 0.76), (0.92, 0.5), (0.92, -0.5)], "u")],
    "rearDelts": [("upper", [(-0.16, -0.92), (-0.16, 0.92), (0.34, 0.72), (0.34, -0.72)], "u")],
    "sideDelts": [("upper", [(-0.18, -1.02), (-0.18, 1.02), (0.4, 0.8), (0.4, -0.8)], "u")],
    "forearmExtensors": [("fore", [(0.05, -0.82), (0.05, 0.82), (0.76, 0.42), (0.76, -0.42)], "u")],
}
TABLES = {"side": MUSCLES, "front": FRONT_MUSCLES, "back": BACK_MUSCLES}


def view_of(pose):
    f = pose.get("front", False)
    return "back" if f == "back" else ("front" if f else "side")


# Faint anatomical definition on the body (not highlighted).
DEFINITION = ["quads", "hamstrings", "calves", "tibialis", "chest", "abs", "lats", "biceps", "triceps",
              "forearms", "glutes", "sideDelts"]

FRONT_VIEW_SKIP = {"hamstrings", "calves", "soleus", "lats", "upperBack", "traps", "lowerBack", "rotatorCuff",
                   "rearDelts", "triceps", "glutes", "forearmExtensors"}


def frontal(j):
    """Front/back view: arms hang from either shoulder, legs from either hip (joints shifted sideways)."""
    t = norm(sub(j["shoulder"], j["hip"]))
    n = (-t[1], t[0])
    sw, hw = PROFILES["torso"][-1][1] * 1.45 * 0.9, 9.0
    for side, s in (("N", 1), ("F", -1)):
        for k in ("elbow", "wrist", "hand"):
            j[k + side] = add(j[k + side], n, s * sw)
        for k in ("knee", "ankle", "toe"):
            j[k + side] = add(j[k + side], n, s * hw)
        j["shoulder" + side] = add(j["shoulder"], n, s * sw)
        j["hip" + side] = add(j["hip"], n, s * hw)
    return j


def body_segments(j, front=False):
    """Segments per layer: far limbs, trunk (torso, neck, head), near limbs."""
    hip, sh = j["hip"], j["shoulder"]
    t = j["_t"]
    c = None
    if j["_curl"]:
        mx, my = (hip[0] + sh[0]) / 2, (hip[1] + sh[1]) / 2
        nx, ny = math.cos(math.radians(t + 90)), math.sin(math.radians(t + 90))
        c = (mx - nx * j["_curl"] * 1.6, my - ny * j["_curl"] * 1.6)
    torso_prof = PROFILES["torso"]
    if front:  # wider, symmetric trunk seen from the front
        torso_prof = [(u, max(f, b) * (1.2 + 0.35 * u), max(f, b) * (1.2 + 0.35 * u)) for u, f, b in torso_prof]
    torso = Seg(hip, sh, torso_prof, "up", c)
    hd = norm(sub(j["head"], j["neck"]))
    head = Seg(add(j["neck"], hd, -3), add(j["neck"], hd, 2 * F.HEAD_R + 3), PROFILES["head"], "up")
    neck = Seg(add(sh, hd, -6), j["neck"], PROFILES["neck"], "up")

    def sym(p):
        return [(u, max(f, b) * 0.92, max(f, b) * 0.92) for u, f, b in p] if front else p

    def limbs(side):
        k = side
        return {
            "thigh": Seg(j.get("hip" + k, hip), j["knee" + k], sym(PROFILES["thigh"])),
            "shin": Seg(j["knee" + k], j["ankle" + k], sym(PROFILES["shin"])),
            "foot": Seg(add(j["ankle" + k], norm(sub(j["toe" + k], j["ankle" + k])), -5), j["toe" + k], PROFILES["foot"]),
            "upper": Seg(j.get("shoulder" + k, sh), j["elbow" + k], sym(PROFILES["upper"])),
            "fore": Seg(j["elbow" + k], j["wrist" + k], sym(PROFILES["fore"])),
            "hand": Seg(j["wrist" + k], j["hand" + k], PROFILES["hand"]),
        }
    return limbs("F"), {"torso": torso, "neck": neck, "head": head}, limbs("N")


def muscle_levels(ex):
    lv = {m: SECONDARY for m in ex.get("secondary", [])}
    lv.update({m: PRIMARY for m in ex["primary"]})
    return lv


def draw_segment(doc, seg, tones, outline_op=0.75):
    d = smooth(seg.outline())
    dark, lit = lit_axis(seg)
    fill = doc.lin(dark, lit, [(0, tones[2]), (0.55, tones[1]), (1, tones[0])])
    doc.add(f'<path d="{d}" fill="{fill}" stroke="{OUTLINE}" stroke-opacity="{outline_op}" stroke-width="1.1" '
            f'stroke-linejoin="round"/>')
    return d


def draw_muscles(doc, seg, name, levels, clip_d, far, view):
    clip = None
    for m, pieces in TABLES[view].items():
        for seg_name, poly, fib in pieces:
            if seg_name != name:
                continue
            if m not in levels and m not in DEFINITION:
                continue
            pts = [seg.at(u, v) for u, v in poly]
            d = smooth(pts, k=0.16)
            clip = clip or doc.clip(clip_d)
            if m not in levels:
                doc.add(f'<path d="{d}" fill="none" stroke="#000" stroke-opacity="{0.07 if far else 0.11}" '
                        f'stroke-width="0.9" clip-path="{clip}"/>')
                continue
            lv = levels[m]
            v = 0.82 if far else 1.0
            dark, lit = lit_axis(seg)
            fill = doc.lin(dark, lit, [(0, heat(lv, 0.95, 0.62 * v)), (0.6, heat(lv, 0.88, 0.88 * v)),
                                       (1, heat(lv, 0.55, 1.0 * v))])
            mc = doc.clip(d)
            doc.add(f'<g clip-path="{clip}"><path d="{d}" fill="{fill}" stroke="{heat(lv, 1, 0.45)}" '
                    f'stroke-opacity="0.8" stroke-width="0.9"/>')
            us = [u for u, _ in poly]
            vs = [vv for _, vv in poly]
            lines = []
            if "u" in fib:
                for i in range(1, 12):
                    vv = min(vs) + (max(vs) - min(vs)) * i / 12
                    lines.append([seg.at(min(us) + (max(us) - min(us)) * s / 8, vv) for s in range(9)])
            if "v" in fib:
                for i in range(1, 10):
                    uu = min(us) + (max(us) - min(us)) * i / 10
                    lines.append([seg.at(uu, min(vs) + (max(vs) - min(vs)) * s / 6) for s in range(7)])
            for ln in lines:
                doc.add(f'<path d="{smooth(ln, closed=False)}" fill="none" stroke="{heat(lv, 1, 0.4)}" '
                        f'stroke-opacity="0.28" stroke-width="0.6" clip-path="{mc}"/>')
            if m == "abs":
                for uu in (0.33, 0.45, 0.56):
                    doc.add(f'<path d="{smooth([seg.at(uu, 0.55), seg.at(uu + 0.01, 0.8), seg.at(uu, 1.02)], closed=False)}" '
                            f'fill="none" stroke="{heat(lv, 1, 0.4)}" stroke-opacity="0.6" stroke-width="1" clip-path="{mc}"/>')
            doc.add("</g>")


def draw_head_details(doc, head, view="side"):
    clip = doc.clip(smooth(head.outline()))
    if view != "side":
        cap = [(0.66, -1.04), (1.06, -1.04), (1.06, 1.04), (0.66, 1.04)] if view == "front" else \
              [(0.38, -1.04), (1.06, -1.04), (1.06, 1.04), (0.38, 1.04)]
        doc.add(f'<path d="{smooth([head.at(u, v) for u, v in cap])}" fill="#2B2F36" fill-opacity="0.9" clip-path="{clip}"/>')
        for s in (-1, 1):
            ear = head.at(0.5, s * 1.02)
            doc.add(f'<circle cx="{ear[0]:.1f}" cy="{ear[1]:.1f}" r="2.8" fill="#B9C1CC" stroke="{OUTLINE}" stroke-opacity="0.5" stroke-width="0.8"/>')
        return
    hair = [head.at(u, v) for u, v in [(0.62, -0.2), (0.62, -1.03), (0.9, -1.04), (1.06, -0.2), (1.02, 0.6), (0.9, 0.86), (0.78, 0.4)]]
    doc.add(f'<path d="{smooth(hair)}" fill="#2B2F36" fill-opacity="0.9" clip-path="{clip}"/>')
    ear = head.at(0.5, -0.12)
    doc.add(f'<ellipse cx="{ear[0]:.1f}" cy="{ear[1]:.1f}" rx="2.6" ry="3.6" fill="#B9C1CC" stroke="{OUTLINE}" '
            f'stroke-opacity="0.5" stroke-width="0.8" transform="rotate({math.degrees(math.atan2(*reversed(head.tan(0.5)))) + 90:.0f} {ear[0]:.1f} {ear[1]:.1f})"/>')


def draw_figure(doc, j, ex, pose):
    view = view_of(pose)
    front = view != "side"
    far_l, trunk, near_l = body_segments(j, front)
    levels = muscle_levels(ex)
    sides = pose.get("lit_sides", "NF")

    def seg(limbs, name, side, tones, far):
        sg = limbs[name]
        d = draw_segment(doc, sg, tones, 0.55 if far else 0.75)
        draw_muscles(doc, sg, name, levels if side in sides else {}, d, far, view)

    if front:
        # Legs, trunk, then both arms in front of it.
        for limbs, side in ((far_l, "F"), (near_l, "N")):
            for name in ("foot", "shin", "thigh"):
                seg(limbs, name, side, SKIN_NEAR, False)
    else:
        # Far arm, far leg, trunk, near leg, near arm.
        for name in ("upper", "fore", "hand", "foot", "shin", "thigh"):
            seg(far_l, name, "F", SKIN_FAR, True)
    for name in ("neck", "torso"):
        sg = trunk[name]
        d = draw_segment(doc, sg, SKIN_NEAR)
        draw_muscles(doc, sg, name, levels, d, False, view)
    head = trunk["head"]
    draw_segment(doc, head, SKIN_NEAR)
    draw_head_details(doc, head, view)
    if front:
        for limbs, side in ((far_l, "F"), (near_l, "N")):
            for name in ("upper", "fore", "hand"):
                seg(limbs, name, side, SKIN_NEAR, False)
    else:
        for name in ("foot", "shin", "thigh", "upper", "fore", "hand"):
            seg(near_l, name, "N", SKIN_NEAR, False)


# ---- equipment ---------------------------------------------------------------------------------

STEEL = ("#5F6873", "#3A414A", "#1F242A")
PAD = ("#3A4048", "#1E2227", "#121417")
CHROME = "#D5DCE4"


def at(j, ref):
    if isinstance(ref, str):
        return j[ref]
    if isinstance(ref, tuple) and len(ref) == 3 and isinstance(ref[0], str):
        p = j[ref[0]]
        return (p[0] + ref[1], p[1] + ref[2])
    return ref


def tube(doc, a, b, w=7, cap="round"):
    nrm = norm((-(b[1] - a[1]), b[0] - a[0]))
    if nrm[0] * LIGHT[0] + nrm[1] * LIGHT[1] > 0:
        nrm = (-nrm[0], -nrm[1])
    m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    g = doc.lin(add(m, nrm, w / 2), add(m, nrm, -w / 2), [(0, STEEL[2]), (0.45, STEEL[1]), (0.8, STEEL[0]), (1, STEEL[1])])
    doc.add(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="{g}" stroke-width="{w}" '
            f'stroke-linecap="{cap}"/>')


def pad(doc, a, b, t=11, stitch=True):
    """Upholstered pad along a→b (its top face is on the left of a→b)."""
    L = math.hypot(*sub(b, a))
    ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
    g = doc.box_grad([(0, PAD[0]), (0.25, PAD[1]), (1, PAD[2])])
    tr = f'translate({a[0]:.1f} {a[1]:.1f}) rotate({ang:.1f})'
    doc.add(f'<g transform="{tr}"><rect x="0" y="{-t:.1f}" width="{L:.1f}" height="{t:.1f}" rx="{t * 0.42:.1f}" fill="{g}" '
            f'stroke="#0A0B0D" stroke-width="0.8"/>'
            + (f'<line x1="{t * 0.5:.1f}" y1="{-t + 2.6:.1f}" x2="{L - t * 0.5:.1f}" y2="{-t + 2.6:.1f}" stroke="#6B737D" '
               f'stroke-opacity="0.55" stroke-width="0.6" stroke-dasharray="2 1.6"/>' if stitch else "") + "</g>")


def plate(doc, c, r=30, hub=True):
    g = doc.lin((c[0] - r, c[1] - r), (c[0] + r, c[1] + r), [(0, "#3A3F46"), (0.5, "#1B1E22"), (1, "#0E1012")])
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="{g}" stroke="#08090A" stroke-width="1"/>')
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.82:.1f}" fill="none" stroke="#4A5058" stroke-opacity="0.7" stroke-width="1.2"/>')
    if hub:
        doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.3:.1f}" fill="#2C3137" stroke="#5A616A" stroke-width="1"/>')
        doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{max(2.5, r * 0.13):.1f}" fill="{CHROME}"/>')


def db_end(doc, c, r=10):
    """Dumbbell seen end-on (handle points at the viewer): hex head with chrome handle end."""
    pts = [(c[0] + r * math.cos(math.radians(30 + 60 * i)), c[1] + r * math.sin(math.radians(30 + 60 * i))) for i in range(6)]
    g = doc.lin((c[0] - r, c[1] - r), (c[0] + r, c[1] + r), [(0, "#4A5058"), (0.5, "#24282D"), (1, "#121417")])
    doc.add(f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in pts)}" fill="{g}" stroke="#08090A" stroke-width="0.9" stroke-linejoin="round"/>')
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.36:.1f}" fill="{CHROME}" stroke="#7D8794" stroke-width="0.8"/>')


def db_side(doc, c, ang, r=9, half=17):
    """Dumbbell seen from the side, handle at angle `ang` through c."""
    a = math.radians(ang)
    e = (math.cos(a), math.sin(a))
    tube(doc, add(c, e, -half), add(c, e, half), 3.6)
    for s in (-1, 1):
        h = add(c, e, s * (half - 2))
        p0, p1 = add(h, e, -4), add(h, e, 5)
        nrm = (-e[1], e[0])
        quad = [add(p0, nrm, r), add(p1, nrm, r), add(p1, nrm, -r), add(p0, nrm, -r)] if s > 0 else \
               [add(add(h, e, -5), nrm, r), add(add(h, e, 4), nrm, r), add(add(h, e, 4), nrm, -r), add(add(h, e, -5), nrm, -r)]
        doc.add(f'<polygon points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in quad)}" fill="#1D2125" stroke="#08090A" stroke-width="0.8"/>')


def pulley(doc, c, r=6.5):
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r}" fill="#262A30" stroke="#0A0B0D" stroke-width="0.9"/>')
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="{r * 0.62:.1f}" fill="none" stroke="#6D7681" stroke-width="1"/>')
    doc.add(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="1.8" fill="{CHROME}"/>')


def cable(doc, pts):
    doc.add(f'<polyline points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in pts)}" fill="none" stroke="#0B0C0E" '
            f'stroke-width="1.7" stroke-linejoin="round"/>')


def stack(doc, x, top, bottom, w=34, plates=12, lifted=0):
    """Selectorized weight stack between two guide rods; `lifted` plates ride up with the cable."""
    tube(doc, (x + 4, top), (x + 4, bottom), 3, "butt")
    tube(doc, (x + w - 4, top), (x + w - 4, bottom), 3, "butt")
    ph = 6.4
    y = bottom - 2
    for i in range(plates):
        yy = y - (i + 1) * ph - (lifted if i >= plates - 4 else 0)
        g = doc.box_grad([(0, "#4B525B"), (0.3, "#2A2F35"), (1, "#16191C")])
        doc.add(f'<rect x="{x:.1f}" y="{yy:.1f}" width="{w}" height="{ph - 0.8:.1f}" rx="1.2" fill="{g}" stroke="#0A0B0D" stroke-width="0.6"/>')
    top_plate = y - plates * ph - lifted
    doc.add(f'<rect x="{x + w / 2 - 2:.1f}" y="{top_plate - 10:.1f}" width="4" height="10" fill="{CHROME}"/>')
    pin_y = y - (plates - 3.5) * ph - lifted
    doc.add(f'<rect x="{x + w - 2:.1f}" y="{pin_y - 1.6:.1f}" width="9" height="3.2" rx="1.6" fill="#E23B3B"/>')
    return (x + w / 2, top_plate - 10)


def shroud(doc, x, top, bottom, w):
    g = doc.box_grad([(0, "#2E343B"), (0.5, "#3C434C"), (1, "#252A30")], vertical=False)
    doc.add(f'<rect x="{x:.1f}" y="{top:.1f}" width="{w:.1f}" height="{bottom - top:.1f}" rx="3" fill="{g}" stroke="#0A0B0D" stroke-width="0.8"/>')


def floor(doc, x0=-200, x1=W + 200):
    doc.add(f'<rect x="{x0}" y="{GROUND}" width="{x1 - x0}" height="3" rx="1.5" fill="#000" fill-opacity="0.28"/>')


def shadow(doc, cx, rx, cy=GROUND + 1, ry=4.5):
    doc.add(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry}" fill="#000" fill-opacity="0.22"/>')


def motion(doc, c, ang, length=24):
    a = math.radians(ang)
    e = (c[0] + math.cos(a) * length, c[1] + math.sin(a) * length)
    l = (e[0] - math.cos(a - 0.55) * 8, e[1] - math.sin(a - 0.55) * 8)
    r = (e[0] - math.cos(a + 0.55) * 8, e[1] - math.sin(a + 0.55) * 8)
    doc.add(f'<polyline points="{c[0]:.1f},{c[1]:.1f} {e[0]:.1f},{e[1]:.1f}" stroke="#fff" stroke-opacity="0.85" stroke-width="3" '
            f'stroke-linecap="round" fill="none"/>'
            f'<polyline points="{l[0]:.1f},{l[1]:.1f} {e[0]:.1f},{e[1]:.1f} {r[0]:.1f},{r[1]:.1f}" stroke="#fff" stroke-opacity="0.85" '
            f'stroke-width="3" stroke-linecap="round" stroke-linejoin="round" fill="none"/>')


PRIMS = {"tube": tube, "pad": pad, "plate": plate, "db_end": db_end, "db_side": db_side, "pulley": pulley,
         "cable": cable, "stack": stack, "shroud": shroud, "floor": floor, "shadow": shadow, "motion": motion}


def resolve(j, v):
    if isinstance(v, list):
        return [resolve(j, x) for x in v]
    if isinstance(v, (str, tuple)):
        try:
            return at(j, v)
        except (KeyError, TypeError):
            return v
    return v


def draw_props(doc, j, props):
    for p in props:
        if callable(p):
            p(doc, j)
            continue
        kind, *args = p
        PRIMS[kind](doc, *[resolve(j, a) for a in args])


# ---- muscle map inset ---------------------------------------------------------------------------

def _bodymap():
    import importlib.util
    from pathlib import Path
    p = Path(__file__).resolve().parent.parent / "bodymap" / "generate.py"
    spec = importlib.util.spec_from_file_location("bodymap_generate", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


BODYMAP = _bodymap()


def inset(doc, levels, view, corner="tl"):
    """Small front + back body map in a corner: exactly which muscles work, whatever the pose hides."""
    x, y, w = view
    h = w * H / W
    ph = h * 0.36
    s = ph / 430
    pw = (2 * 200 + 10) * s + 8
    px = x + 6 if corner[1] == "l" else x + w - pw - 6
    py = y + 6 if corner[0] == "t" else y + h - ph - 6
    doc.add(f'<rect x="{px:.1f}" y="{py:.1f}" width="{pw:.1f}" height="{ph:.1f}" rx="{ph * 0.08:.1f}" fill="#0B0B0F" fill-opacity="0.32"/>')
    for i, side in enumerate(("front", "back")):
        sh = BODYMAP.sheet(side, False)
        ox, oy = px + 4 + i * (200 + 10) * s, py + 10 * s
        tr = f'translate({ox:.2f} {oy:.2f}) scale({s:.4f})'
        g = [f'<g transform="{tr}">']
        for p in sh["outline"]:
            g.append(f'<path d="{smooth(p, k=1 / 6)}" fill="#FFFFFF" fill-opacity="0.22"/>')
        for m, p in sh["muscles"]:
            if m in levels:
                g.append(f'<path d="{smooth(p, k=1 / 6)}" fill="{heat(levels[m])}" stroke="#000" stroke-opacity="0.3" stroke-width="1.5"/>')
            else:
                g.append(f'<path d="{smooth(p, k=1 / 6)}" fill="#FFFFFF" fill-opacity="0.16" stroke="#000" stroke-opacity="0.12" stroke-width="1.2"/>')
        g.append("</g>")
        doc.add("".join(g))


# ---- frames ----------------------------------------------------------------------------------

def lerp_pose(a, b, k):
    out = dict(a)
    for key, va in a.items():
        vb = b.get(key)
        if isinstance(va, (int, float)) and isinstance(vb, (int, float)) and not isinstance(va, bool):
            out[key] = va + (vb - va) * k
        elif isinstance(va, tuple) and isinstance(vb, tuple) and len(va) == len(vb) and all(isinstance(x, (int, float)) for x in va):
            out[key] = tuple(x + (y - x) * k for x, y in zip(va, vb))
        elif key == "pin" and vb:
            (n, pa), (_, pb) = va, vb
            out[key] = (n, (pa[0] + (pb[0] - pa[0]) * k, pa[1] + (pb[1] - pa[1]) * k))
    for key in ("props", "front_props"):
        if key in b and key not in a:
            out[key] = b[key]
    return out


def frames(poses):
    """Three frames: start, middle, end. A pose list of 2 gets its middle interpolated."""
    if len(poses) == 3:
        return poses
    return [poses[0], lerp_pose(poses[0], poses[1], 0.5), poses[1]]


def render(pose, ex, scene=None, prefix="a", view=None):
    doc = Doc(prefix)
    doc.view = view
    j = F.place(pose)
    if view_of(pose) != "side":
        frontal(j)
    if scene:
        scene(doc, j, "back")
    draw_props(doc, j, pose.get("props", []))
    draw_figure(doc, j, ex, pose)
    if scene:
        scene(doc, j, "front")
    draw_props(doc, j, pose.get("front_props", []))
    if view and pose.get("inset", "tl"):
        inset(doc, muscle_levels(ex), view, pose.get("inset", "tl"))
    return doc.svg()
