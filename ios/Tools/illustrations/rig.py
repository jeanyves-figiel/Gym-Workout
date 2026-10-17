#!/usr/bin/env python3
"""Pose the athletic body (body.py --build -> body_rig.npz) on positions.py joints with the full MakeHuman rig:
forward kinematics down the skeleton, the spine and neck share the trunk's bend, the shoulder girdle follows the arm
part way, arms and legs reach the 2D figure's wrists and ankles by two-bone IK (elbow / knee toward the figure's),
linear-blend skinning with the rig's own weights.

    python3 rig.py EXERCISE KEY OUT.json [grip]
"""
import json, sys, zlib
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
DATA = HERE.parent.parent / "Packages/GymCore/Sources/WorkoutEngine/Resources/ExercisePositions.json.z"
MUSH = 24          # delta-mush smoothing passes
LIMB = {"arm": (42.0, 38.0), "leg": (56.0, 54.0)}    # figure.py lengths


def nrm(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def perp(v, ax):
    return v - (v @ ax) * ax


def basis(u, a):
    u = nrm(u); a = nrm(perp(a, u))
    if np.linalg.norm(a) < 1e-6:
        a = nrm(perp(np.array([1.0, 0, 0]) if abs(u[0]) < 0.9 else np.array([0, 1.0, 0]), u))
    return np.stack([u, a, np.cross(u, a)], 1)


def rot(B0, B1):
    return B1 @ B0.T


def slerp_m(R0, R1, t):
    """Rotation part way from R0 to R1."""
    D = R1 @ R0.T
    ang = np.arccos(np.clip((np.trace(D) - 1) / 2, -1, 1))
    if ang < 1e-6:
        return R0
    ax = np.array([D[2, 1] - D[1, 2], D[0, 2] - D[2, 0], D[1, 0] - D[0, 1]])
    if np.linalg.norm(ax) < 1e-6:          # 180 degrees: take the axis from the symmetric part
        w, v = np.linalg.eigh((D + D.T) / 2)
        ax = v[:, -1]
    ax = nrm(ax)
    K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
    a = ang * t
    return (np.eye(3) + np.sin(a) * K + (1 - np.cos(a)) * K @ K) @ R0


def between(a, b):
    """Shortest rotation taking direction a to direction b."""
    a, b = nrm(a), nrm(b)
    v = np.cross(a, b); c = a @ b
    if c < -0.9999:
        ax = nrm(perp(np.array([1.0, 0, 0]) if abs(a[0]) < 0.9 else np.array([0, 1.0, 0]), a))
        K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
        return np.eye(3) + 2 * K @ K
    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def two_bone(S, T, a, b, pole):
    """Elbow/knee position for a chain S->E->T with lengths a, b, bending toward pole."""
    d = T - S
    L = np.linalg.norm(d)
    L = min(L, (a + b) * 0.999)
    u = nrm(d)
    x = (a * a - b * b + L * L) / (2 * L)
    h = np.sqrt(max(a * a - x * x, 0))
    p = nrm(perp(pole - S, u))
    if np.linalg.norm(p) < 1e-6:
        p = nrm(perp(np.array([1.0, 0, 0]), u))
    return S + u * x + p * h, S + u * L


def held_object(J, d, props):
    """What the figure's hand on side d holds: ("rod", axis, (a, b)) for a bar/handle/cable through the hand,
    ("db", None, centre) for a dumbbell/kettlebell/ball at the hand, else None."""
    h, w = J["hand" + d], J["wrist" + d]
    best = None
    for p in props:
        k = p["k"]
        if k == "rod":
            a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
            ab = b - a; L2 = ab @ ab
            if L2 < 1e-6:
                continue
            for pt in (h, (h + w) / 2):
                t = np.clip(((pt - a) @ ab) / L2, 0, 1)
                dist = np.linalg.norm(pt - (a + t * ab))
                lim = 9.0 if p.get("s") == "cable" else 7.5
                if dist < lim and (best is None or dist < best[0]):
                    best = (dist, ("rod", nrm(ab), (a, b)))
        elif k in ("db", "kb", "ball"):
            if k == "ball" and p.get("r", 8) > 12:     # a stability ball is sat or lain on, not held
                continue
            # the weight may already sit in the body's (wider) hand, outside the figure's: measure across the
            # shoulder line and allow the sideways offset
            c = np.asarray(p["c"], float)
            lat = nrm(J["shoulder" + d] - J["shoulder"])
            l = (c - h) @ lat
            dist = np.linalg.norm((c - h) - l * lat)
            if dist < p.get("r", 8) + 6 and -16 < l < 30 and (best is None or dist < best[0]):
                best = (dist, (k, None, c))
    return None if best is None else best[1]


def db_axis(J, d):
    """Dumbbell handle axis for the hand on side d: front-back when the arm hangs at the side or reaches out
    sideways (neutral grip), across the body otherwise (curls, presses, rows)."""
    h, sh = J["hand" + d], J["shoulder" + d]
    hanging = h[1] < J["hip"][1] + 20 and abs(h[0] - sh[0]) < 15
    lateral = abs(h[2] - J["shoulder"][2]) > abs(sh[2] - J["shoulder"][2]) + 12
    return np.array([1.0, 0, 0]) if hanging or lateral else np.array([0, 0, 1.0])


def palm_dir(J, d, hd, fa, held, a_fa):
    """Palm normal for the hand on figure side d: fingers wrap around the held object's axis; the palm continues
    the forearm when the load is along it (presses, pulls, hangs), else faces the body. Free hands relax."""
    u = nrm(hd)
    mid = (J["hip"] + J["shoulder"]) / 2
    to_body = mid - J["hand" + d]
    sh = J["shoulder" + d]
    if held is None:
        if J["hand" + d][1] < 8:                       # hand on the floor: palm down, flat
            p = perp(np.array([0, -1.0, 0]), u)
        else:                                          # relaxed: palm toward the body
            p = perp(to_body, u)
        return nrm(p) if np.linalg.norm(p) > 1e-3 else a_fa
    if held[0] == "rod":
        axis = held[1]
    else:
        axis = db_axis(J, d)
    axis = perp(axis, u)
    if np.linalg.norm(axis) < 0.2:
        axis = perp(np.array([0, 0, 1.0]), u)
    p = nrm(np.cross(axis, u))
    along = p @ nrm(fa)
    if abs(along) > 0.45:
        return p if along > 0 else -p
    return p if p @ to_body >= 0 else -p


class Rig:
    def __init__(self):
        r = np.load(HERE / "body_rig.npz")
        self.V = r["v"].astype(float); self.Vf = r["vf"].astype(float)
        self.bi = r["bi"].astype(int); self.bw = r["bw"].astype(float)
        self.H = r["heads"].astype(float); self.T = r["tails"].astype(float)
        self.P = r["parents"].astype(int); self.names = json.loads(str(r["names"]))
        self.palm = {"L": r["palm"][0].astype(float), "R": r["palm"][1].astype(float)}
        self.ix = {n: i for i, n in enumerate(self.names)}
        order, seen = [], set()

        def visit(i):
            if i in seen:
                return
            if self.P[i] >= 0:
                visit(self.P[i])
            seen.add(i); order.append(i)
        for i in range(len(self.names)):
            visit(i)
        self.order = order
        b = np.load(HERE / "body_rest.npz")
        self.F, self.m, self.mu, self.cav, self.band = b["f"], b["m"], b["mu"], b["cav"], b["band"]
        self.legs = None
        self.mush = None; self.adj = None

    def h(self, n):
        return self.H[self.ix[n]]

    def rest_joints(self):
        h = self.h
        J = {"hip": (h("upperleg01.L") + h("upperleg01.R")) / 2, "shoulder": (h("upperarm01.L") + h("upperarm01.R")) / 2,
             "neck": h("neck01"), "head": h("head") + (self.T[self.ix["head"]] - h("head")) * 0.35}
        for s in "LR":
            J["shoulder" + s] = h(f"upperarm01.{s}"); J["elbow" + s] = h(f"lowerarm01.{s}")
            J["wrist" + s] = h(f"wrist.{s}"); J["hand" + s] = h(f"finger3-1.{s}")
            J["hip" + s] = h(f"upperleg01.{s}"); J["knee" + s] = h(f"lowerleg01.{s}")
            J["ankle" + s] = h(f"foot.{s}"); J["toe" + s] = h(f"toe3-1.{s}")
        return J

    def pose(self, J, props=None, grip=None):
        """props: the key's prop list (positions.py JSON). A hand closes into a fist only around something it holds,
        and the palm turns to the grip; `grip` forces fists on the given figure sides ("N"/"F")."""
        J = {k: np.asarray(v, float) for k, v in J.items() if not k.startswith("_")}
        self.held = {d: held_object(J, d, props or []) for d in ("N", "F")}
        self.grip = {}          # where each gripping hand's fist closes (world), filled by _arm
        if grip is None:
            grip = tuple(d for d in ("N", "F") if self.held[d] is not None)
        R0 = self.rest_joints()
        up = J["shoulder"] - J["hip"]
        toe = (J["toeN"] + J["toeF"]) / 2 - (J["ankleN"] + J["ankleF"]) / 2
        chir = np.linalg.det(np.stack([perp(toe, nrm(up)), up, J["shoulderF"] - J["shoulderN"]]))
        # rest: x forward, y up, MakeHuman .L at -z, so (fwd, up, R-L) is right-handed
        S = {"L": "N", "R": "F"} if chir > 0 else {"L": "F", "R": "N"}

        def trunk(Jx, side_l, side_r):
            u = nrm(Jx["shoulder"] - Jx["hip"])
            fw_t = (Jx["toe" + side_l] + Jx["toe" + side_r]) / 2 - (Jx["ankle" + side_l] + Jx["ankle" + side_r]) / 2
            out = []
            for lat in (Jx["hip" + side_r] - Jx["hip" + side_l], Jx["shoulder" + side_r] - Jx["shoulder" + side_l]):
                f = np.cross(u, nrm(lat))
                if f @ fw_t < 0:
                    f = -f
                out.append(basis(u, f))
            hu = nrm(Jx["head"] - Jx["neck"])
            out.append(basis(hu, out[1][:, 1]))
            return out
        Bp0, Bc0, Bh0 = trunk(R0, "L", "R")
        Bp1, Bc1, Bh1 = trunk(J, S["L"], S["R"])
        Rp, Rc, Rh = rot(Bp0, Bp1), rot(Bc0, Bc1), rot(Bh0, Bh1)
        n = len(self.names)
        Rw = [None] * n; Sc = [None] * n; Ph = np.zeros((n, 3))
        M = [None] * n          # skin: x -> A @ x + t

        def setb(i, R, k=1.0):
            Rw[i] = R
            d = nrm(self.T[i] - self.H[i])
            Sc[i] = np.eye(3) + (k - 1) * np.outer(d, d) + (np.sqrt(k) - 1) * (np.eye(3) - np.outer(d, d))
        fixed = {"root": Rp, "spine05": Rp, "spine04": slerp_m(Rp, Rc, 0.25), "spine03": slerp_m(Rp, Rc, 0.5),
                 "spine02": slerp_m(Rp, Rc, 0.8), "spine01": Rc, "neck01": slerp_m(Rc, Rh, 0.35),
                 "neck02": slerp_m(Rc, Rh, 0.7), "neck03": Rh, "head": Rh}
        hip_c_rest = (self.h("upperleg01.L") + self.h("upperleg01.R")) / 2
        limb = {}
        for i in self.order:
            name = self.names[i]
            p = self.P[i]
            A_par = M[p][0] if p >= 0 else None
            # posed head: through the parent's skin transform (root: pelvis placed at the figure's hip)
            if p < 0:
                Ph[i] = J["hip"] + Rp @ (self.H[i] - hip_c_rest)
            else:
                Ph[i] = M[p][0] @ self.H[i] + M[p][1]
            side = name[-1] if name[-2:] in (".L", ".R") else ""
            base = name[:-2] if side else name
            if name in fixed:
                setb(i, fixed[name])
            elif base in ("clavicle", "shoulder01", "upperarm01", "upperarm02", "lowerarm01", "lowerarm02", "wrist"):
                if side not in limb:
                    limb[side] = self._arm(side, S[side], J, R0, Rc, Ph, i)
                setb(i, *limb[side][base]) if base in limb[side] else setb(i, Rw[p])
            elif base in ("upperleg01", "upperleg02", "lowerleg01", "lowerleg02", "foot"):
                if "leg" + side not in limb:
                    limb["leg" + side] = self._leg(side, S[side], J, R0, Rp, Ph[i])
                setb(i, *limb["leg" + side][base])
            elif base.startswith("toe") and "toe" in limb.get("leg" + side, {}):
                setb(i, limb["leg" + side]["toe"])
            else:
                setb(i, Rw[p] if p >= 0 else Rp)
            A = Rw[i] @ Sc[i]
            M[i] = (A, Ph[i] - A @ self.H[i])
        Vin = self.V.copy()
        for s in "LR":
            if S[s] in grip:
                hand = np.isin(self.bi[:, 0], [self.ix[nm] for nm in self.names if nm.endswith("." + s) and
                                               (nm.startswith(("finger", "metacarpal", "wrist")))])
                Vin[hand] = self.Vf[hand]
        out = np.zeros_like(Vin)
        Rv = np.zeros((len(Vin), 3, 3))
        As = np.stack([M[b][0] for b in range(n)]); ts = np.stack([M[b][1] for b in range(n)])
        for k in range(4):
            A = As[self.bi[:, k]]
            out += self.bw[:, k, None] * (np.einsum("vij,vj->vi", A, Vin) + ts[self.bi[:, k]])
            Rv += self.bw[:, k, None, None] * A
        # delta mush: smooth away skinning creases (armpits, shoulders, hips), then put the rest-pose detail back
        if MUSH:
            if self.mush is None:
                self.mush = Vin - self._smooth(Vin, MUSH)
            d = self.mush if not grip else Vin - self._smooth(Vin, MUSH)
            out = self._smooth(out, MUSH) + np.einsum("vij,vj->vi", Rv, d)
        return out

    def _smooth(self, X, n):
        if self.adj is None:
            import scipy.sparse as sp
            F = self.F
            E = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
            E = np.concatenate([E, E[:, ::-1]])
            A = sp.csr_matrix((np.ones(len(E)), (E[:, 0], E[:, 1])), shape=(len(self.V),) * 2)
            A.data[:] = 1
            deg = np.asarray(A.sum(1)).ravel()
            self.adj = sp.diags(1 / np.maximum(deg, 1)) @ A
        for _ in range(n):
            X = 0.5 * X + 0.5 * (self.adj @ X)
        return X

    def _arm(self, s, d, J, R0, Rc, Ph, i_clav):
        """Rotations (and stretch) for clavicle .. wrist on side s (rest) / d (figure)."""
        h = self.h
        sh0, el0, wr0, hd0 = h(f"upperarm01.{s}"), h(f"lowerarm01.{s}"), h(f"wrist.{s}"), h(f"finger3-1.{s}")
        a0, b0 = np.linalg.norm(el0 - sh0), np.linalg.norm(wr0 - el0)
        # figure's arm direction relative to the chest decides how far the girdle follows (elevation part)
        dir_t = nrm(J["elbow" + d] - J["shoulder" + d])
        dir_r = nrm(Rc @ (el0 - sh0))
        G = between(dir_r, dir_t)
        out = {"clavicle": (slerp_m(Rc, G @ Rc, 0.18),), "shoulder01": (slerp_m(Rc, G @ Rc, 0.35),)}
        # shoulder position after the girdle: clavicle head (posed) + girdle rotations of the rest offsets
        clav_h = Ph[i_clav]
        Rcl, Rsh = out["clavicle"][0], out["shoulder01"][0]
        S_ = clav_h + Rcl @ (h(f"shoulder01.{s}") - h(f"clavicle.{s}"))
        S_ = S_ + Rsh @ (sh0 - h(f"shoulder01.{s}"))
        # the figure is narrower than the body: carry the shoulder's sideways offset to the elbow and to hands that
        # hang outside the shoulder line (hands that grip or meet in front stay put)
        lat = nrm(J["shoulder" + d] - J["shoulder"])
        off = ((S_ - J["shoulder" + d]) @ lat) * lat
        wl = np.linalg.norm(J["shoulder" + d] - J["shoulder"])
        kk = float(np.clip(((J["hand" + d] - J["shoulder"]) @ lat) / max(wl, 1e-6), 0, 1))
        Wt = J["wrist" + d] + off * kk + lat * 8.0 * kk       # clear the lats
        Jel = J["elbow" + d] + off * (0.5 + 0.5 * kk) + lat * 6.0 * kk
        # grip: the hollow of the fist (past the knuckles, on the palm side) is what sits on the object. Bars and
        # handles stay where the scene put them and the hand goes to them; a dumbbell follows the hand (contact.py)
        held = self.held.get(d)
        hd = J["hand" + d] - J["wrist" + d]
        pd = palm_dir(J, d, hd, J["wrist" + d] - J["elbow" + d], held, nrm(np.cross(hd, np.array([0, 1.0, 0]))))
        goff = 0.62 * np.linalg.norm(hd0 - wr0) * nrm(hd) + 3.0 * pd
        if held is not None and held[0] == "rod":
            a, b = held[2]
            ab = b - a
            t = np.clip(((Wt + goff - a) @ ab) / (ab @ ab), 0, 1)
            Wt = a + t * ab - goff
        elif held is None and J["hand" + d][1] < 8:
            Wt[1] = max(Wt[1], 4.0)                          # a flat hand on the floor: wrist a palm's thickness up
        self.grip[d] = Wt + goff
        reach = np.linalg.norm(J["wrist" + d] - J["shoulder" + d])
        k = np.clip((LIMB["arm"][0] + LIMB["arm"][1]) * np.linalg.norm(Wt - S_) / max(reach, 1e-6) / (a0 + b0), 0.95, 1.4)
        E, Wp = two_bone(S_, Wt, a0 * k, b0 * k, Jel + (Jel - (S_ + Wt) / 2) * 2)
        ua, fa = E - S_, Wp - E
        bend = np.linalg.norm(perp(nrm(fa), nrm(ua)))
        fw_c = Rc @ np.array([1.0, 0, 0])
        a_ua = perp(nrm(fa), nrm(ua)) if bend > 0.2 else perp(fw_c, nrm(ua))
        ua0, fa0 = el0 - sh0, wr0 - el0
        a_ua0 = perp(nrm(fa0), nrm(ua0))
        Rua = rot(basis(ua0, a_ua0), basis(ua, a_ua))
        a_fa0 = -perp(nrm(ua0), nrm(fa0))
        a_fa = -perp(nrm(ua), nrm(fa)) if bend > 0.2 else Rua @ a_fa0
        Rfa = rot(basis(fa0, a_fa0), basis(fa, a_fa))
        hd = J["hand" + d] - J["wrist" + d]
        Rhd = rot(basis(hd0 - wr0, self.palm[s]), basis(hd, palm_dir(J, d, hd, fa, self.held.get(d), a_fa)))
        return {**out, "upperarm01": (Rua, k), "upperarm02": (Rua, k), "lowerarm01": (Rfa, k), "lowerarm02": (Rfa, k),
                "wrist": (Rhd,)}

    def _leg(self, s, d, J, R0, Rp, Hp):
        h = self.h
        hp0, kn0, an0, to0 = h(f"upperleg01.{s}"), h(f"lowerleg01.{s}"), h(f"foot.{s}"), h(f"toe3-1.{s}")
        a0, b0 = np.linalg.norm(kn0 - hp0), np.linalg.norm(an0 - kn0)
        off = Hp - J["hip" + d]
        off = off - (off @ nrm(J["shoulder"] - J["hip"])) * nrm(J["shoulder"] - J["hip"])
        At = J["ankle" + d] + off
        Toe = J["toe" + d] + off
        on_toes = At[1] >= 8 and Toe[1] < 4 and At[1] > Toe[1] + 6   # push-ups, planks: up on the ball of the foot
        if At[1] < 8:     # the 2D figure's ankle sits on the floor; the body's ankle is above its sole
            At = At + np.array([0, an0[1] - 0.5, 0])
            Toe[1] = max(Toe[1], to0[1])
        elif on_toes:
            Toe[1] = to0[1]
        Jkn = J["knee" + d] + off
        reach = np.linalg.norm(J["ankle" + d] - J["hip" + d])
        k = np.clip((LIMB["leg"][0] + LIMB["leg"][1]) * np.linalg.norm(At - Hp) / max(reach, 1e-6) / (a0 + b0), 0.9, 1.15)
        K, Ap = two_bone(Hp, At, a0 * k, b0 * k, Jkn + (Jkn - (Hp + At) / 2) * 2)
        th, sn = K - Hp, Ap - K
        ft = Toe - Ap
        th0, sn0, ft0 = kn0 - hp0, an0 - kn0, to0 - an0
        a_sn0, a_sn = perp(nrm(ft0), nrm(sn0)), perp(nrm(ft), nrm(sn))
        kb = np.linalg.norm(perp(nrm(sn), nrm(th)))
        a_th = -perp(nrm(sn), nrm(th)) if kb > 0.15 else a_sn
        a_th0 = perp(nrm(ft0), nrm(th0))
        Rth = rot(basis(th0, a_th0), basis(th, a_th))
        Rsn = rot(basis(sn0, a_sn0), basis(sn, a_sn))
        up = np.array([0, 1.0, 0])
        Rft = rot(basis(ft0, up), basis(ft, up))
        out = {"upperleg01": (Rth, k), "upperleg02": (Rth, k), "lowerleg01": (Rsn, k), "lowerleg02": (Rsn, k), "foot": (Rft,)}
        if on_toes:       # toes bend back to lie flat on the floor
            fl = perp(ft, up)
            if np.linalg.norm(fl) < 1e-3:
                fl = perp(th, up)
            out["toe"] = rot(basis(ft0, up), basis(nrm(fl), up))
        return out


if __name__ == "__main__":
    sys.path.insert(0, str(HERE))
    import body
    d = json.loads(zlib.decompress(DATA.read_bytes(), -15))
    rig = Rig()
    key = d[sys.argv[1]]["k"][int(sys.argv[2])]
    V = rig.pose(key["j"], key["p"])
    legs = np.ones(len(V), bool)
    ry = np.load(HERE / "body_rest.npz")["v"][:, 1]
    hipsy = np.isin(rig.bi[:, 0], [rig.ix[nm] for nm in rig.names if nm.startswith(("upperleg", "pelvis", "root", "spine05", "spine04"))])
    ph = body.fibre_phase(rig.V, rig.mu, rig.rest_joints())
    body.export_json(V, rig.F, rig.m, rig.mu, rig.cav, np.where(hipsy, rig.V[:, 1], 999), rig.band, sys.argv[3], ph)
