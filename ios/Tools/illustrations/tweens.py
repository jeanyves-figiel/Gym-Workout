"""Hand-made in-between poses (#229) for movements a straight interpolation of the key poses cannot show:
`EXTRA[exercise id](key poses) -> {frame: pose}`, frames between 1 and art.FRAMES - 2 (not the middle key)."""
import art

EXTRA = {}


def _high_pull(keys):
    """Clean, second pull: bar rising close to the body to the chest, elbows high, before the catch."""
    p = art.lerp_pose(keys[1], keys[2], 0.35)
    p["aN"] = (-155, 35, 35)
    p["aF"] = (-153, 37, 37)
    return {6: p}


EXTRA["power-clean"] = _high_pull
EXTRA["hang-power-clean"] = _high_pull


def _man_maker(keys):
    """Man maker: after the row the feet jump in and the dumbbells are cleaned to the shoulders in a squat,
    then the stand-and-press (end key)."""
    import scenes_gym_free as G
    from scenes_lower import ANK, body, shoulder
    hip, t = (G.MM_HIP[0] - 8, art.GROUND - 66), -58
    s = shoulder(hip, t)
    g = (s[0] + 12, s[1] + 6)
    p = body(hip, t, h=-80, ankN=(G.MM_HIP[0] + 14, ANK), ankF=(G.MM_HIP[0] + 10, ANK), gN=g, gF=(g[0] - 3, g[1] - 1),
             eN=-1, eF=-1)
    return {6: p}


def _get_up(keys):
    """Turkish get-up: from the tall sit, sweep the back leg under into a half-kneel (bell still overhead),
    then stand up (end key)."""
    from poses import P
    import scenes_var_core as V
    up = (-90, -90, -90)
    p = P(t=-90, h=-90, lN=(2, 90, 0), lF=(92, 178, 178), aN=up, aF=(88, 90),
          pin=("ankleN", (V.TGU_HIP[0] + 44, V.FOOT_Y)))
    return {6: p}


EXTRA["man-maker"] = _man_maker
EXTRA["turkish-get-up"] = _get_up
