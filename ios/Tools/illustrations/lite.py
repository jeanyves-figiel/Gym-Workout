#!/usr/bin/env python3
"""Light illustrations bundled in the app (#932): 9 of each exercise's HD frames at half size.

The HD frames (ios/HDAnimations/<id>/<frame>.png, written by generate.py) are not in the app: they ship as the HD
pack (pack.py) downloaded after sign-up. This writes ios/MonkeyWorkout/Resources/Illustrations.xcassets with
`illustration-<id>-<k>`, k = 0 … LITE_FRAMES - 1, taken at HD frames `lite_frames(n)` (start, middle and end
included, so the Start / Middle / End strip matches either set).

    python3 ios/Tools/illustrations/lite.py
"""
import json
import shutil
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
IOS = HERE.parent.parent
HD = IOS / "HDAnimations"
ASSETS = IOS / "MonkeyWorkout/Resources/Illustrations.xcassets"
LITE_FRAMES = 9
LITE_SIZE = (360, 270)
COLORS = 128


def lite_frames(n):
    """HD frame of each light frame: evenly spread, first and last included (ExerciseIllustrations.liteFrames)."""
    return [(k * (n - 1) + (LITE_FRAMES - 1) // 2) // (LITE_FRAMES - 1) for k in range(LITE_FRAMES)]


def hd_frame_counts():
    return {d.name: len(list(d.glob("*.png"))) for d in sorted(HD.iterdir()) if d.is_dir()}


def _lite(job):
    src, dst = job
    im = Image.open(src).convert("RGBA").resize(LITE_SIZE, Image.LANCZOS)
    im.quantize(colors=COLORS, method=Image.Quantize.FASTOCTREE).save(dst, optimize=True)


def build():
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir(parents=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    jobs = []
    for ex_id, n in hd_frame_counts().items():
        for k, f in enumerate(lite_frames(n)):
            name = f"illustration-{ex_id}-{k}"
            d = ASSETS / f"{name}.imageset"
            d.mkdir()
            (d / "Contents.json").write_text(json.dumps({
                "images": [{"filename": f"{name}.png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }, indent=2) + "\n")
            jobs.append((HD / ex_id / f"{f}.png", d / f"{name}.png"))
    with ProcessPoolExecutor() as pool:
        list(pool.map(_lite, jobs, chunksize=32))
    return len(jobs)


if __name__ == "__main__":
    n = build()
    size = sum(p.stat().st_size for p in ASSETS.rglob("*.png"))
    print(f"{n} light frames, {size / 1e6:.1f} MB")
