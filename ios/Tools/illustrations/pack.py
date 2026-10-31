#!/usr/bin/env python3
"""HD animation pack (#932): the full-frame illustrations downloaded by the app after sign-up.

Reads ios/HDAnimations/<id>/<frame>.png and writes to OUT (default ios/build/hd-pack):
- `<id>-<sha256[:12]>.mwf` per exercise: b"MWF1", frame count (UInt16 LE), each frame's byte length (UInt32 LE), then
  the PNGs; then (#944) b"MCLP", the movement clip's byte length (UInt32 LE) and the HD clip (ios/HDMotion/<id>.mp4,
  video.py). Apps from before the clips read the frames and ignore the rest. Named by content, so a file never changes once published (cached for good) and a new manifest never
  points at a file an older one used.
- `manifest.json`: {"format": 1, "version", "published", "exercises": {id: {"file", "frames", "bytes", "sha256"}}, "bytes": total}.
  `version` (#995): first 8 hex of the sha256 over every exercise's sha256, so it changes only when art changes;
  `published`: when this pack was built (UTC, ISO 8601). Settings → HD animations shows both.
The app keeps a file only when its frame count matches its build's catalog and its sha256 matches the manifest.
Published as assets of the `hd-animations` release by the "HD animations pack" workflow.

    python3 ios/Tools/illustrations/pack.py [OUT]
"""
import hashlib
import json
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
IOS = HERE.parent.parent
HD = IOS / "HDAnimations"
CLIPS = IOS / "HDMotion"


def pack(ex_dir):
    frames = [(ex_dir / f"{i}.png").read_bytes() for i in range(len(list(ex_dir.glob("*.png"))))]
    head = b"MWF1" + struct.pack("<H", len(frames)) + b"".join(struct.pack("<I", len(f)) for f in frames)
    clip = CLIPS / f"{ex_dir.name}.mp4"
    tail = b"MCLP" + struct.pack("<I", clip.stat().st_size) + clip.read_bytes() if clip.exists() else b""
    return len(frames), head + b"".join(frames) + tail


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    exercises, total = {}, 0
    for d in sorted(p for p in HD.iterdir() if p.is_dir()):
        n, data = pack(d)
        sha = hashlib.sha256(data).hexdigest()
        name = f"{d.name}-{sha[:12]}.mwf"
        (out / name).write_bytes(data)
        exercises[d.name] = {"file": name, "frames": n, "bytes": len(data), "sha256": sha}
        total += len(data)
    version = hashlib.sha256("".join(e["sha256"] for _, e in sorted(exercises.items())).encode()).hexdigest()[:8]
    published = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    (out / "manifest.json").write_text(json.dumps({"format": 1, "version": version, "published": published,
                                                   "exercises": exercises, "bytes": total},
                                                  indent=1, sort_keys=True) + "\n")
    print(f"{len(exercises)} exercises, {total / 1e6:.1f} MB → {out}")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else IOS / "build/hd-pack")
