"""Hand-made in-between poses (#229) for movements a straight interpolation of the key poses cannot show:
`EXTRA[exercise id](key poses) -> {frame: pose}`, frames between 1 and art.FRAMES - 2 (not the middle key)."""
import art

EXTRA = {}


def _high_pull(keys):
    """Clean, second pull: bar rising close to the body to the chest, elbows high, before the catch."""
    p = art.lerp_pose(keys[1], keys[2], 0.35)
    p["aN"] = (-155, 35, 35)
    p["aF"] = (-153, 37, 37)
    return {art.at(0.75): p}


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
    return {art.at(0.75): p}


def _get_up(keys):
    """Turkish get-up: from the tall sit, sweep the back leg under into a half-kneel (bell still overhead),
    then stand up (end key)."""
    from poses import P
    import scenes_var_core as V
    up = (-90, -90, -90)
    p = P(t=-90, h=-90, lN=(2, 90, 0), lF=(92, 178, 178), aN=up, aF=(88, 90),
          pin=("ankleN", (V.TGU_HIP[0] + 44, V.FOOT_Y)))
    return {art.at(0.75): p}


EXTRA["man-maker"] = _man_maker
EXTRA["turkish-get-up"] = _get_up


def _burpee(keys):
    import scenes_var_core as V
    return V.burpee_tweens(keys)


EXTRA["burpee"] = _burpee


def _lunge_step(keys):
    """Walking lunge with twist: the stepping foot swings forward off the floor instead of the in-between legs
    dipping into it (the floor guard then snapped the knee); mid-twist the far arm passes close behind the
    torso (elbow bent, hand at the chest) instead of hanging down below the hip."""
    import scenes_power as SP
    twist = art.lerp_pose(keys[1], keys[2], 0.5)
    twist["aF"] = (95, -60, -60)
    return {art.at(0.25): SP.lunge_step(), art.at(0.75): twist}


EXTRA["lunge-twist"] = _lunge_step


def _calis_path(name):
    """scenes_gym_calis: in-betweens solved on the movement's path (hands stay on the bar)."""
    def extra(keys):
        import scenes_gym_calis as C
        return C.path_tweens(getattr(C, name))(keys)
    return extra


EXTRA["archer-pull-up"] = _calis_path("archer_at")
EXTRA["muscle-up"] = _calis_path("mu_at")
EXTRA["weighted-muscle-up"] = _calis_path("mu_at")
EXTRA["hanging-shoulder-circles"] = _calis_path("circles_at")


def _shoulder_car(keys):
    """Shoulder CAR: from overhead the arm keeps circling back and down behind the body; a straight
    interpolation of the overhead and end keys swung it back down the front instead (and hid it)."""
    p = dict(keys[2])
    p["aN"] = (-155, -155, -155)
    return {art.at(0.75): p}


EXTRA["shoulder-car"] = _shoulder_car


def _spider(keys):
    import scenes_gym_calis as C
    return C.spider_tweens(keys)


EXTRA["spiderman-push-up"] = _spider


def _halo(keys):
    import scenes_gym_calis as C
    import scenes_gym_free as G
    return C.path_tweens(G.halo_at)(keys)


EXTRA["kb-halo"] = _halo


def _tgu_path(keys):
    """Turkish get-up, second half solved along a path with the near foot planted (replaces _get_up's single
    in-between, whose far-leg sweep jumped between frames)."""
    import scenes_var_core as V
    return V.tgu_tweens(keys)


EXTRA["turkish-get-up"] = _tgu_path
