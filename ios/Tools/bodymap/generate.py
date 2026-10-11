#!/usr/bin/env python3
"""Generate the body map figures (#110): front + back, two body figures (M, F), drawn as our own vector art.

Source of truth for the outline and muscle shapes. Writes
ios/Packages/GymCore/Sources/WorkoutEngine/BodyMapGeometry.swift; the app smooths each polygon
(Catmull-Rom) when drawing and hit-tests the raw polygon.

    python3 ios/Tools/bodymap/generate.py                   # write Swift
    python3 ios/Tools/bodymap/generate.py --preview out.html  # + SVG preview page with sample heat

Design space 200 x 410, body centred on x = 100. Shapes are given for the figure's right side
(viewer's left, x < 100) and mirrored; `mid` shapes straddle the centre line. The F figure is the M
geometry warped (narrower shoulders and waist, wider hips) plus its own chest shape.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
IOS = HERE.parent.parent
SWIFT_OUT = IOS / "Packages/GymCore/Sources/WorkoutEngine/BodyMapGeometry.swift"

W, H, CX = 200, 410, 100

# Silhouette, right half: neck top centre, down the outside of the arm, round the hand, up the inner arm,
# down the torso and the outside of the leg, round the foot, up the inner leg to the crotch.
OUTLINE = [
    (91, 50), (90, 62), (76, 68), (60, 71), (48, 75), (40, 83), (36, 95), (34, 110), (31, 128), (28, 146),
    (24, 162), (20, 182), (18, 200), (17, 216), (14, 226), (13, 238), (16, 248), (22, 250), (26, 240),
    (27, 228), (31, 210), (36, 188), (40, 168), (44, 152), (47, 134), (50, 120), (56, 112), (59, 128),
    (62, 148), (66, 166), (65, 182), (62, 198), (60, 214), (59, 236), (61, 260), (65, 284), (68, 304),
    (68, 318), (65, 336), (66, 356), (70, 376), (72, 390), (69, 398), (71, 405), (88, 405), (90, 397),
    (88, 388), (89, 370), (91, 350), (92, 330), (93, 314), (95, 290), (97, 264), (98, 242),
]
HEAD = (100, 30, 18, 22)  # cx, cy, rx, ry

FRONT = [
    # (muscle, points, mirrored)
    ("sideDelts", [(49, 76), (41, 83), (36, 95), (35, 108), (40, 110), (44, 98), (46, 86)], True),
    ("frontDelts", [(62, 74), (52, 77), (46, 84), (45, 96), (48, 106), (56, 99), (63, 87)], True),
    ("chest", [(98, 78), (80, 75), (66, 79), (61, 87), (60, 99), (65, 110), (78, 116), (92, 116), (98, 112)], True),
    ("biceps", [(46, 110), (40, 116), (37, 128), (37, 141), (41, 149), (46, 142), (49, 128), (51, 117)], True),
    ("forearms", [(38, 156), (30, 166), (24, 184), (21, 202), (22, 214), (27, 212), (32, 194), (38, 177), (42, 162)], True),
    ("obliques", [(86, 122), (66, 118), (63, 136), (66, 158), (70, 177), (78, 190), (87, 192), (88, 160)], True),
    ("abs", [(90, 120), (110, 120), (112, 150), (111, 180), (106, 200), (100, 206), (94, 200), (89, 180), (88, 150)], False),
    ("hipFlexors", [(68, 192), (75, 204), (84, 216), (92, 226), (95, 218), (89, 204), (80, 195)], True),
    ("quads", [(64, 214), (61, 236), (62, 262), (66, 286), (72, 302), (82, 304), (89, 296), (91, 272), (89, 248), (84, 228), (74, 214)], True),
    ("adductors", [(90, 230), (97, 240), (97, 262), (94, 276), (91, 262), (89, 246)], True),
    ("calves", [(68, 322), (66, 340), (68, 360), (73, 376), (78, 370), (80, 350), (78, 330)], True),
    ("calves", [(88, 320), (91, 338), (89, 360), (85, 370), (83, 352), (84, 332)], True),
]

BACK = [
    ("upperBack", [(100, 54), (92, 58), (76, 67), (63, 73), (70, 82), (84, 96), (92, 118), (100, 128), (108, 118),
                   (116, 96), (130, 82), (137, 73), (124, 67), (108, 58)], False),
    ("sideDelts", [(49, 76), (41, 83), (36, 95), (35, 108), (40, 110), (44, 98), (46, 86)], True),
    ("rearDelts", [(61, 75), (52, 78), (46, 86), (46, 100), (53, 100), (60, 90)], True),
    ("rotatorCuff", [(67, 84), (61, 91), (62, 102), (71, 106), (80, 101), (77, 92)], True),
    ("lats", [(62, 106), (60, 122), (64, 144), (70, 163), (80, 178), (89, 170), (91, 150), (86, 128), (74, 110)], True),
    ("triceps", [(46, 108), (39, 113), (35, 126), (36, 142), (42, 149), (48, 139), (50, 121)], True),
    ("forearms", [(38, 156), (30, 166), (24, 184), (21, 202), (22, 214), (27, 212), (32, 194), (38, 177), (42, 162)], True),
    ("lowerBack", [(92, 152), (108, 152), (113, 178), (110, 194), (100, 198), (90, 194), (87, 178)], False),
    ("glutes", [(98, 198), (84, 194), (70, 198), (62, 211), (62, 227), (72, 240), (88, 242), (98, 236)], True),
    ("hamstrings", [(63, 244), (61, 264), (65, 286), (72, 304), (82, 306), (89, 300), (91, 276), (89, 256), (82, 246)], True),
    ("adductors", [(91, 246), (97, 250), (97, 270), (94, 282), (91, 266)], True),
    ("calves", [(68, 318), (64, 336), (66, 356), (72, 372), (79, 368), (81, 346), (79, 326)], True),
    ("calves", [(83, 320), (90, 330), (91, 350), (87, 370), (82, 358), (82, 336)], True),
]

# Female chest replaces the M one: rounder, lower contour.
F_CHEST = [(98, 84), (82, 81), (69, 85), (63, 95), (64, 108), (74, 120), (88, 123), (98, 118)]

# Decorative detail lines (open polylines, drawn faintly over muscles): ab segments, linea alba, pec split.
FRONT_DETAILS = [
    ([(100, 122), (100, 202)], False),
    ([(90, 140), (110, 140)], False),
    ([(89, 160), (111, 160)], False),
    ([(89, 180), (111, 180)], False),
    ([(98, 80), (98, 112)], True),
    ([(66, 302), (82, 312), (89, 302)], True),  # kneecap
    ([(76, 226), (78, 296)], True),  # rectus femoris / vastus split
]
BACK_DETAILS = [
    ([(100, 60), (100, 196)], False),
    ([(100, 236), (97, 218)], True),  # glute cleft
    ([(77, 252), (77, 300)], True),   # hamstring split
]

# F warp: horizontal scale around the centre line by height (knots y -> k), linear between knots.
F_WARP = [(0, 0.94), (55, 0.94), (75, 0.88), (110, 0.88), (165, 0.85), (185, 0.95), (215, 1.06), (245, 1.04),
          (300, 0.97), (410, 0.93)]


def warp_k(y):
    for (y0, k0), (y1, k1) in zip(F_WARP, F_WARP[1:]):
        if y0 <= y <= y1:
            return k0 + (k1 - k0) * (y - y0) / (y1 - y0)
    return F_WARP[-1][1]


def warp(pts, female):
    if not female:
        return pts
    return [(round(CX + (x - CX) * warp_k(y), 1), y) for x, y in pts]


def mirror(pts):
    return [(W - x, y) for x, y in pts]


def head_polygon(female, n=20):
    import math
    cx, cy, rx, ry = HEAD
    if female:
        rx, ry = rx * 0.94, ry * 0.95
    return [(round(cx + rx * math.cos(2 * math.pi * i / n), 1), round(cy + ry * math.sin(2 * math.pi * i / n), 1)) for i in range(n)]


def sheet(side, female):
    shapes = []
    for muscle, pts, mirrored in (FRONT if side == "front" else BACK):
        if female and muscle == "chest":
            pts = F_CHEST
        shapes.append((muscle, warp(pts, female)))
        if mirrored:
            shapes.append((muscle, warp(mirror(pts), female)))
    body = warp(OUTLINE + list(reversed(mirror(OUTLINE))), female)
    details = []
    for pts, mirrored in (FRONT_DETAILS if side == "front" else BACK_DETAILS):
        if female and side == "front" and pts[0] == (98, 80):
            continue  # no pec split line on F
        details.append(warp(pts, female))
        if mirrored:
            details.append(warp(mirror(pts), female))
    return {"outline": [head_polygon(female), body], "muscles": shapes, "details": details}


def fmt(pts):
    return "[" + ", ".join(f"{x:g}, {y:g}" for x, y in pts) + "]"


def swift():
    out = [
        "// Generated by ios/Tools/bodymap/generate.py — do not edit by hand.",
        "// Our own vector art (#110): outline + muscle polygons per figure and side, flat x, y pairs in the",
        "// 200 × 410 design space.",
        "",
        "extension BodyMapLayout {",
        "    static func sheet(_ figure: Figure, _ side: Side) -> Sheet {",
        "        switch (figure, side) {",
    ]
    for fig in ("male", "female"):
        for side in ("front", "back"):
            s = sheet(side, fig == "female")
            out.append(f"        case (.{fig}, .{side}): {fig}{side.capitalize()}")
    out += ["        }", "    }", ""]
    for fig in ("male", "female"):
        for side in ("front", "back"):
            s = sheet(side, fig == "female")
            out.append(f"    private static let {fig}{side.capitalize()} = Sheet(")
            out.append("        outline: [")
            out += [f"            {fmt(p)}," for p in s["outline"]]
            out.append("        ],")
            out.append("        muscles: [")
            out += [f"            (.{m}, {fmt(p)})," for m, p in s["muscles"]]
            out.append("        ],")
            out.append("        details: [")
            out += [f"            {fmt(p)}," for p in s["details"]]
            out.append("        ]")
            out.append("    )")
            out.append("")
    out[-1] = "}"
    return "\n".join(out) + "\n"


# --- preview ---------------------------------------------------------------------------------

def smooth_path(pts, closed=True):
    """Catmull-Rom → cubic Bézier, same as the app."""
    n = len(pts)
    if not closed:
        return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    d = f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"
    for i in range(n):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f" C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}"
    return d + "Z"


def heat_color(v):
    import colorsys
    r, g, b = colorsys.hsv_to_rgb(0.22 * (1 - v), 0.85, 1)
    return f"#{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"


SAMPLE_HEAT = {"glutes": 1, "quads": 0.75, "hamstrings": 0.7, "upperBack": 0.4, "lats": 0.45, "chest": 0.35,
               "frontDelts": 0.4, "triceps": 0.3, "biceps": 0.2, "calves": 0.3, "abs": 0.15, "forearms": 0.25,
               "sideDelts": 0.1, "rearDelts": 0.3}


def svg(side, female, heat, selected=None):
    s = sheet(side, female)
    parts = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg">',
             '<defs><linearGradient id="skin" x1="0" y1="0" x2="0" y2="1">'
             '<stop offset="0" stop-color="#fff" stop-opacity="0.10"/><stop offset="1" stop-color="#fff" stop-opacity="0.04"/>'
             '</linearGradient><filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter></defs>']
    for p in s["outline"]:
        parts.append(f'<path d="{smooth_path(p)}" fill="url(#skin)" stroke="#fff" stroke-opacity="0.14" stroke-width="0.8"/>')
    for m, p in s["muscles"]:
        h = heat.get(m, 0)
        if h > 0.5:
            parts.append(f'<path d="{smooth_path(p)}" fill="{heat_color(h)}" opacity="0.55" filter="url(#glow)"/>')
    for m, p in s["muscles"]:
        h = heat.get(m, 0)
        fill = heat_color(h) if h > 0 else "#ffffff"
        op = 0.6 + 0.4 * h if h > 0 else 0.07
        sel = m == selected
        stroke = 'stroke="#fff" stroke-width="1.6"' if sel else 'stroke="#000" stroke-opacity="0.35" stroke-width="0.7"'
        parts.append(f'<path d="{smooth_path(p)}" fill="{fill}" fill-opacity="{op:.2f}" {stroke}/>')
    for p in s["details"]:
        parts.append(f'<path d="{smooth_path(p, False)}" fill="none" stroke="#000" stroke-opacity="0.3" stroke-width="0.8" stroke-linecap="round"/>')
    parts.append("</svg>")
    return "".join(parts)


def preview(path):
    rows = []
    for female in (False, True):
        cells = "".join(
            f'<div class="cell">{svg(side, female, SAMPLE_HEAT, "glutes" if side == "back" else None)}<p>{side.upper()}</p></div>'
            for side in ("front", "back"))
        rows.append(f'<div class="row"><h3>{"F" if female else "M"}</h3>{cells}</div>')
    Path(path).write_text(
        "<html><body style='background:#0b0b0f;color:#9a9aa5;font:700 12px -apple-system,sans-serif;letter-spacing:3px;margin:0'>"
        "<style>.row{display:flex;gap:10px;align-items:center;padding:8px}.cell{width:170px;text-align:center}"
        "svg{width:170px;height:349px}h3{width:20px}</style>" + "".join(rows) + "</body></html>")


if __name__ == "__main__":
    SWIFT_OUT.write_text(swift())
    print("wrote", SWIFT_OUT.relative_to(IOS.parent))
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
