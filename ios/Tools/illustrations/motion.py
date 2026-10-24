"""Movement data for the app's animation overlay (#229): the path of the point that carries the movement
(bar / hand, foot, hips…) across the frames, and what each half of a repetition is called.

For each exercise: `path` = that point per frame, normalised to the picture (0…1, origin top-left), or
empty when nothing travels far enough to draw (holds, stretches); `first` / `second` = phase labels
("UP" / "DOWN", "PUSH" / "PULL", "OUT" / "IN") for start → end and end → start; `effort_first` = True
when start → end is the working (concentric) half, which the app plays at 1 s, the return at 2 s.
"""
import math

import art
import cycles

# Points that can carry the movement, in order of preference when they travel about as far.
CANDIDATES = ("handN", "handF", "toeN", "toeF", "hip", "shoulder", "kneeN", "head")
MIN_TRAVEL = 0.06  # of the picture width; less = no path
HAND_SHARE = 0.5  # hands (they hold the load) win when they travel at least this share of the farthest point

# The load goes up while the point goes down (cable / machine pulled down, lowered stack).
DOWN_IS_EFFORT = ("pulldown", "pull-down", "pushdown", "push-down", "straight-arm", "cable-crunch",
                  "crunch-machine", "rope-crunch", "seated-leg-curl", "leg-curl-seated", "pullover-machine",
                  "kneeling-cable", "woodchop-high", "high-to-low", "slam")
JUMPS = ("jump", "bound", "hop", "skater", "burpee")
# Read as up / down even when the point travels more sideways (curling the trunk up, raising the legs).
VERTICAL = ("sit-up", "crunch", "v-up", "leg-raise", "knee-raise", "toes-to-bar")
# Horizontal: the working half moves towards the body (rows, flys) or away (presses, reverse flys).
OUT_IS_EFFORT_FIRST = ("reverse", "rear", "abduct", "pull-apart", "external")  # checked before IN_IS_EFFORT
IN_IS_EFFORT = ("fly", "pec-deck", "adduct", "squeeze", "row", "face-pull", "pull", "curl", "wheel", "rollout")


def _travel(pts):
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


def analyse(ex_id, joints, view, front):
    x0, y0, w = view
    h = w * art.H / art.W
    def inside(p):
        return -0.05 <= (p[0] - x0) / w <= 1.05 and -0.05 <= (p[1] - y0) / h <= 1.05
    # Only points that stay in the picture (a scene may park a redrawn limb off-screen, a close-up crops it).
    tracks = {k: [j[k] for j in joints] for k in CANDIDATES if all(k in j and inside(j[k]) for j in joints)}
    if not tracks:
        return dict(track="", path=[], first="UP", second="DOWN", effort_first=True)
    travel = {k: _travel(p) for k, p in tracks.items()}
    far = max(travel, key=travel.get)
    # The near hand unless the far one clearly travels further (one-arm work on the far side).
    hands = "handF" if travel.get("handF", 0) > 1.15 * travel.get("handN", 0) else "handN"
    key = hands if travel.get(hands, 0) >= HAND_SHARE * travel[far] else far
    if any(k in ex_id for k in JUMPS):
        key = "hip"  # the body flies, the arms only swing
    pts = tracks[key]
    path = [((x - x0) / w, (y - y0) / h) for x, y in pts]
    if travel[key] / w < MIN_TRAVEL:
        path = []
    dx, dy = pts[-1][0] - pts[0][0], pts[-1][1] - pts[0][1]
    if abs(dy) >= 0.8 * abs(dx) or any(k in ex_id for k in VERTICAL):
        first, second = ("DOWN", "UP") if dy > 0 else ("UP", "DOWN")
        effort_first = first == "UP"
        if any(k in ex_id for k in DOWN_IS_EFFORT):
            effort_first = not effort_first
    else:
        if front:
            centre = sum(j["hip"][0] for j in joints) / len(joints)
            out = abs(pts[-1][0] - centre) > abs(pts[0][0] - centre)
            first, second = ("OUT", "IN") if out else ("IN", "OUT")
        else:
            fwd = dx > 0  # side view: the figure faces right
            first, second = ("PUSH", "PULL") if fwd else ("PULL", "PUSH")
        towards_body = first in ("IN", "PULL")
        if any(k in ex_id for k in OUT_IS_EFFORT_FIRST):
            effort_first = not towards_body
        elif any(k in ex_id for k in IN_IS_EFFORT):
            effort_first = towards_body
        else:
            effort_first = not towards_body  # presses, pushes, throws
    if first in ("PUSH", "PULL", "IN", "OUT") and any(k in ex_id for k in JUMPS):
        first, second, effort_first = "JUMP", "RESET", True  # forward / sideways jumps
    if ex_id in cycles.CYCLIC:
        # One whole stride or turn per play, no working half (#719).
        first, second = cycles.CYCLIC[ex_id]
        return dict(track=key, path=path, first=first, second=second, effort_first=True, cyclic=True)
    return dict(track=key, path=path, first=first, second=second, effort_first=effort_first)
