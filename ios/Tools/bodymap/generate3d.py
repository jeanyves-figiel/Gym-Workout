#!/usr/bin/env python3
"""Generate the 3D body figures for the 3D body map (#225): a sculpted body (smooth union of capsules and ellipsoids
fitted to the 2D body map outline in generate.py), polygonised with marching cubes. Our own geometry, no third-party
model. Writes deflate-compressed meshes to ios/Packages/GymCore/Sources/WorkoutEngine/Resources/:

    python3 -m pip install numpy scikit-image
    python3 ios/Tools/bodymap/generate3d.py

Format (little-endian): "BM3D", u32 version (1), u32 vertex count, u32 triangle count, then per vertex
f32 x, y, z (2D design space: x 0-200, y 0-410 down, z toward the front) + i8 nx, ny, nz + 1 pad byte, then
u32 indices (3 per triangle, counter-clockwise seen from outside in design space).
"""
import struct, sys, zlib
from pathlib import Path
import numpy as np
from skimage import measure

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import generate as g

OUT = HERE.parent.parent / "Packages/GymCore/Sources/WorkoutEngine/Resources"
STEP = 1.5

def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)

def ellipsoid(P, c, r):
    q = [(P[i] - c[i]) / r[i] for i in range(3)]
    k0 = np.sqrt(q[0]**2 + q[1]**2 + q[2]**2)
    k1 = np.sqrt((q[0]/r[0])**2 + (q[1]/r[1])**2 + (q[2]/r[2])**2)
    return k0 * (k0 - 1) / np.maximum(k1, 1e-6)

def cone(P, a, b, ra, rb):
    a = np.array(a, float); b = np.array(b, float)
    ba = b - a; L2 = ba @ ba
    pa = [P[i] - a[i] for i in range(3)]
    t = np.clip((pa[0]*ba[0] + pa[1]*ba[1] + pa[2]*ba[2]) / L2, 0, 1)
    d = np.sqrt(sum((pa[i] - ba[i]*t)**2 for i in range(3)))
    return d - (ra + (rb - ra) * t)

def body(P, female):
    x, y, z = P
    # mirror: model one side (design x < 100)
    xm = np.where(x > 100, 200 - x, x)
    if female:  # undo the 2D F warp so the M parts land on the F outline
        k = np.interp(y, [a for a, _ in g.F_WARP], [b for _, b in g.F_WARP])
        xm = 100 + (xm - 100) / k
    Q = (xm, y, z)
    K = 6
    d = ellipsoid(Q, (100, 30, 2), (17.5, 21.5, 19))                       # head
    d = smin(d, cone(Q, (100, 44, -1), (100, 74, 0), 8.5, 10), 4)         # neck
    torso = ellipsoid(Q, (100, 108, 0), (41, 36, 22))                      # chest / ribcage
    torso = smin(torso, ellipsoid(Q, (100, 158, 1), (33, 30, 19)), 12)     # abdomen
    torso = smin(torso, ellipsoid(Q, (100, 202, -1), (37, 26, 21)), 12)    # pelvis
    torso = smin(torso, cone(Q, (64, 82, -2), (100, 74, -3), 10, 12), 8)   # shoulder girdle / traps
    torso = smin(torso, ellipsoid(Q, (82, 100, 10), (17, 13, 11)), 6)      # pec
    torso = smin(torso, ellipsoid(Q, (83, 214, -12), (16, 17, 13)), 7)     # glute
    torso = smin(torso, ellipsoid(Q, (74, 112, -9), (14, 30, 10)), 8)      # lat
    if female:
        torso = smin(torso, ellipsoid(Q, (83, 110, 14), (13, 12, 11)), 6)
    d = smin(d, torso, 8)
    arm = ellipsoid(Q, (50, 90, 0), (13, 15, 13))                          # deltoid
    arm = smin(arm, cone(Q, (44, 104, 0), (37, 150, 0), 9.5, 8), 5)        # upper arm
    arm = smin(arm, cone(Q, (37, 151, 0), (31, 172, 1), 8, 8.6), 3)        # forearm top
    arm = smin(arm, cone(Q, (31, 172, 1), (24, 213, 1), 8.6, 6), 3)        # forearm
    arm = smin(arm, ellipsoid(Q, (20, 232, 2), (6, 13, 5)), 4)             # hand
    d = smin(d, arm, K)
    leg = cone(Q, (79, 222, 0), (80, 300, 0), 20, 13)                      # thigh
    leg = smin(leg, cone(Q, (80, 300, 0), (80, 316, 0), 13, 12), 3)        # knee
    leg = smin(leg, cone(Q, (80, 318, -2), (79, 345, -4), 12, 13.5), 4)    # calf top
    leg = smin(leg, cone(Q, (79, 345, -4), (80, 390, -1), 13.5, 7), 4)     # calf / ankle
    leg = smin(leg, ellipsoid(Q, (80, 400, 6), (8, 6, 15)), 3)             # foot
    d = smin(d, leg, K)
    return d

def build(female, step=1.0):
    xs = np.arange(-4, 204, step); ys = np.arange(-4, 414, step); zs = np.arange(-44, 44, step)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing='ij')
    D = body((X, Y, Z), female)
    v, f, n, _ = measure.marching_cubes(D, 0, spacing=(step, step, step))
    v += np.array([xs[0], ys[0], zs[0]])
    return v, f, -n  # skimage normals point to increasing field (outward = increasing d)


def write(path, v, f, n):
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    blob = bytearray(b"BM3D") + struct.pack("<III", 1, len(v), len(f))
    rec = np.zeros(len(v), dtype=[("p", "<f4", 3), ("n", "i1", 3), ("pad", "u1")])
    rec["p"] = v
    rec["n"] = np.clip(np.round(n * 127), -127, 127)
    blob += rec.tobytes() + f.astype("<u4").tobytes()
    c = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw deflate (NSData .zlib)
    path.write_bytes(c.compress(bytes(blob)) + c.flush())
    print("wrote", path.relative_to(HERE.parent.parent.parent), len(v), "vertices", len(f), "triangles", path.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for female in (False, True):
        v, f, n = build(female, STEP)
        # marching_cubes winds triangles for its (x, y, z) grid; keep them counter-clockwise from outside.
        a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
        if (np.cross(b - a, c - a) * n[f[:, 0]]).sum() < 0:
            f = f[:, [0, 2, 1]]
        write(OUT / f"body-{'female' if female else 'male'}.bm3d", v, f, n)
