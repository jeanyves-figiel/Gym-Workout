"""Cyclic movements (#719): gaits, carries and machines drawn as one whole cycle that ends where it starts, so the
app plays them forward and wraps (`ExerciseMotion.cyclic`) instead of playing half a stride and then backwards.

A gait's key poses are a step (start), the passing pose (middle) and the other step (end, the start with the near
and far limbs swapped). The cycle runs start → middle → end → middle with the limbs swapped → start, at an even
pace. Machines that turn (bikes, cross-trainer) are posed at every frame from the crank's phase.
"""
import art
import scenes_power as PW

GAIT = ("STEP", "STRIDE")
PEDAL = ("PEDAL", "TURN")
# Labels of half a cycle and of the whole cycle (the app's chip shows the whole one): a step of a stride for gaits
# and carries, a pedal stroke of a turn for the machines and the bicycle crunch.
CYCLIC = {
    "treadmill-run": GAIT,
    "incline-walk": GAIT,
    "sled-sprint": GAIT,
    "sled-drag": GAIT,
    "farmer-carry": GAIT,
    "front-rack-carry": GAIT,
    "trap-bar-carry": GAIT,
    "stair-climber": GAIT,
    "mountain-climber": GAIT,
    "bicycle-crunch": PEDAL,
    "bike": PEDAL,
    "air-bike": PEDAL,
    "elliptical": PEDAL,
}

# Machines posed from the crank's phase: (phase of the first frame, pose at a phase).
PHASED = {
    "bike": (-30, lambda ph: PW.bike_pose((176, 154), -64, PW.BK_CRANK, 20, ph, (264, 128), (260, 129), h=-70,
                                          handle=10, moving=PW.bike_moving)),
    "air-bike": (-30, lambda ph: PW.bike_pose(PW.AB_HIP, -76, PW.AB_CRANK, 21, ph, PW.ab_lever(ph), PW.ab_lever(ph + 180),
                                              h=-80, moving=PW.air_bike_moving)),
    "elliptical": (0, PW.el_pose),
}


def swapped(pose):
    """The pose with the near and far limbs exchanged (keys ending in N / F)."""
    out = dict(pose)
    for k in pose:
        if k.endswith("N") and k[:-1] + "F" in pose:
            out[k], out[k[:-1] + "F"] = pose[k[:-1] + "F"], pose[k]
    return out


def poses(ex_id, keys):
    """art.FRAMES poses of one whole cycle; the last is the first again, so playback wraps without a jump."""
    n = art.FRAMES
    if ex_id in PHASED:
        start, at = PHASED[ex_id]
        return [at(start + 360 * i / (n - 1)) for i in range(n)]
    a, m, b = art.keyframes(keys)
    knots = [a, m, b, swapped(m), a]
    out = []
    for i in range(n):
        s = i / (n - 1) * (len(knots) - 1)
        k = min(int(s), len(knots) - 2)
        f = s - k
        if f == 0 or i == n - 1:
            out.append(knots[round(s)])
            continue
        out.append(art.floor_guard(art.lerp_pose(knots[k], knots[k + 1], f), knots))
    return out
