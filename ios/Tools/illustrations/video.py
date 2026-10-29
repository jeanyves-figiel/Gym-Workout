#!/usr/bin/env python3
"""Exercise movement clips (#944): each movement drawn with 61 eased in-betweens and played at 60 fps.

Each catalog exercise is rendered start → end at FRAMES frames (the same scenes and poses as generate.py) and encoded
as one HEVC clip that plays start → end → start (2 × FRAMES - 1 frames at FPS). Video has no alpha here, so each
picture is stacked: colour on top, its alpha as grey below (the app masks one with the other, MotionClip.swift).

Writes the light clips bundled in the app, ios/MonkeyWorkout/Resources/Motion/motion-<id>.mp4 (360 × 270), and the HD
clips of the HD pack, ios/HDMotion/<id>.mp4 (720 × 540, packed by pack.py). Needs cairosvg, Pillow, numpy, ffmpeg
(libx265). generate.py runs it after the frames; on its own:

    python3 ios/Tools/illustrations/video.py [ids…]
"""
import io
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import cairosvg
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import generate  # noqa: E402

IOS = HERE.parent.parent
LIGHT = IOS / "MonkeyWorkout/Resources/Motion"
HD = IOS / "HDMotion"
FRAMES = 61  # start → end; MotionClip.frames in the app
FPS = 60
SIZES = {"hd": (720, 540), "light": (360, 270)}
CRF = {"hd": 28, "light": 30}
# Short keyframe interval: the app plays pieces of the clip (tempo, holds, the way back) and each jump decodes from the
# keyframe before it.
GOP = 30


def stacked(im):
    """RGBA picture as one RGB picture twice as tall: colour on top, alpha as grey below."""
    rgba = np.asarray(im)
    alpha = np.repeat(rgba[..., 3:], 3, -1)
    return Image.fromarray(np.concatenate([rgba[..., :3], alpha], 0), "RGB")


def encode(frames_dir, out, kind):
    w, h = SIZES[kind]
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", str(frames_dir / "%03d.png"),
        "-vf", f"scale={w}:{2 * h}:flags=lanczos,format=yuv420p", "-c:v", "libx265", "-preset", "slow",
        "-crf", str(CRF[kind]), "-x265-params", f"log-level=error:keyint={GOP}:min-keyint={GOP}:scenecut=0",
        "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
        "-tag:v", "hvc1", "-an", "-movflags", "+faststart", str(out)], check=True)


def clip(ex_id):
    cat, all_scenes = clip.cat, clip.scenes
    svgs = generate._render(ex_id, cat, all_scenes, None, FRAMES)
    if len(svgs) != FRAMES:
        raise SystemExit(f"{ex_id}: {len(svgs)} frames, want {FRAMES}")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        hd = SIZES["hd"]
        pics = []
        for svg in svgs:
            png = cairosvg.svg2png(bytestring=svg.encode(), output_width=hd[0], output_height=hd[1])
            pics.append(stacked(Image.open(io.BytesIO(png)).convert("RGBA")))
        # Start → end → start: the way back plays forward in the file.
        for i, pic in enumerate(pics + pics[-2::-1]):
            pic.save(tmp / f"{i:03d}.png", compress_level=1)
        encode(tmp, HD / f"{ex_id}.mp4", "hd")
        encode(tmp, LIGHT / f"motion-{ex_id}.mp4", "light")
    return ex_id


def _init():
    clip.cat = generate.catalog()
    clip.scenes = generate.scenes()


def build(ids=None):
    cat = generate.catalog()
    everything = ids is None
    ids = sorted(cat) if everything else ids
    if everything:
        for d in (LIGHT, HD):
            if d.exists():
                shutil.rmtree(d)
    for d in (LIGHT, HD):
        d.mkdir(parents=True, exist_ok=True)
    with ProcessPoolExecutor(initializer=_init) as pool:
        for n, ex_id in enumerate(pool.map(clip, ids), 1):
            if n % 25 == 0 or n == len(ids):
                print(f"{n}/{len(ids)} clips", flush=True)
    light = sum(p.stat().st_size for p in LIGHT.glob("*.mp4"))
    hd = sum(p.stat().st_size for p in HD.glob("*.mp4"))
    print(f"light {light / 1e6:.1f} MB, HD {hd / 1e6:.1f} MB")


if __name__ == "__main__":
    build(sys.argv[1:] or None)
