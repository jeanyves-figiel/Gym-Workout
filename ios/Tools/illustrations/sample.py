#!/usr/bin/env python3
"""Contact sheet of the realistic exercise art (#168) on the category gradients.

    python3 ios/Tools/illustrations/sample.py out.png [-m scenes_module] [exercise-id ...]
"""
import io
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import art  # noqa: E402
from generate import CATALOG, GRADIENT, TRAVEL, VARIATIONS  # noqa: E402
from scenes import SCENES  # noqa: E402


def catalog():
    src = CATALOG.read_text() + TRAVEL.read_text() + VARIATIONS.read_text()
    out = {}
    for m in re.finditer(r'Exercise\(id: "([^"]+)", name: "([^"]+)", category: \.(\w+), pattern: \.[\w`]+, '
                         r'primary: \[([^\]]*)\](?:, secondary: \[([^\]]*)\])?', src):
        mus = lambda s: [p.strip().lstrip(".") for p in (s or "").split(",") if p.strip()]
        out[m.group(1)] = dict(name=m.group(2), category=m.group(3), primary=mus(m.group(4)), secondary=mus(m.group(5)))
    return out


def render(ex_id, cat):
    import generate
    try:
        everything = {**generate.scenes(), **SCENES}
    except ImportError:
        everything = SCENES
    return generate.render(ex_id, cat, everything)


def sheet(ids, out, width=800):
    import cairosvg
    from PIL import Image, ImageDraw, ImageFont

    cat = catalog()
    cw = (width - 16) // 3
    ch = cw * 3 // 4
    rows = len(ids)
    img = Image.new("RGB", (width, rows * (ch + 30) + 8), "#0B0B0F")
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    except OSError:
        font = None
    for r, ex_id in enumerate(ids):
        ex = cat[ex_id]
        c0, c1 = GRADIENT[ex["category"]]
        y = 8 + r * (ch + 30)
        d.text((8, y), ex["name"].upper(), fill="#FFFFFF", font=font)
        for f, svg in enumerate(render(ex_id, cat)):
            x, y0, w, h = re.search(r'viewBox="([^"]+)"', svg).group(1).split()
            head, rest = svg.split(">", 1)
            g = (head + f'><defs><linearGradient id="bg" x2="1" y2="1"><stop offset="0" stop-color="{c0}"/>'
                 f'<stop offset="1" stop-color="{c1}"/></linearGradient></defs>'
                 f'<rect x="{x}" y="{y0}" width="{w}" height="{h}" fill="url(#bg)"/>' + rest)
            png = cairosvg.svg2png(bytestring=g.encode(), output_width=cw, output_height=ch)
            img.paste(Image.open(io.BytesIO(png)).convert("RGB"), (8 + f * (cw + 0), y + 22))
    img.save(out)


if __name__ == "__main__":
    args = sys.argv[2:]
    if args[:1] == ["-m"]:
        import importlib
        mod = importlib.import_module(args[1])
        SCENES.update(mod.SCENES)
        args = args[2:] or list(mod.SCENES)
    ids = args or list(SCENES)
    sheet(ids, sys.argv[1])
