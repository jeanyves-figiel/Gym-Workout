"""Start/end poses for every catalog exercise without a free-exercise-db photo.

Angles: degrees, 0 = right, 90 = down, -90 = up (figure faces right in side view).
  t        torso (hip → shoulder)          h     neck/head
  lN, lF   (thigh, shin[, foot])           aN, aF (upper arm, forearm[, hand])
  curl     bow of the torso (px, + = rounds the back)
  front    frontal view (both sides opaque)
  pin      (joint, (x, y)) instead of floor grounding
  lift     px above the floor (lowest joint otherwise rests on it)
  scale    shrink the whole drawing (tall poses)   top_down  no floor line (seen from above, or hanging)
  props    list of (kind, *args) from figure.PROP_DRAW
"""

STAND = dict(t=-90, lN=(90, 90), lF=(90, 90), aN=(90, 90), aF=(90, 90))


def P(**kw):
    p = dict(STAND)
    p.update(kw)
    return p


def plank(**kw):
    """High plank, head to the right."""
    base = dict(t=-4, lN=(176, 176), lF=(176, 176), aN=(90, 90, 0), aF=(90, 90, 0))
    base.update(kw)
    return P(**base)


def quadruped(**kw):
    base = dict(t=0, lN=(90, 180, 180), lF=(90, 180, 180), aN=(90, 90, 0), aF=(90, 90, 0))
    base.update(kw)
    return P(**base)


POSES = {
    "hip-thrust-machine": [
        P(t=205, lN=(-5, 95, 0), lF=(-5, 95, 0), aN=(120, 30), aF=(120, 30),
          props=[("bench", "shoulder", 70, -20), ("pad", "hip", "kneeN", -14, 14)]),
        P(t=180, lN=(-30, 90, 0), lF=(-30, 90, 0), aN=(120, 30), aF=(120, 30),
          props=[("bench", "shoulder", 70, -20), ("pad", "hip", "kneeN", -14, 14)]),
    ],
    "cossack-squat": [
        P(front=True, lN=(68, 90, 0), lF=(112, 90, 180), aN=(72, -168), aF=(108, -12),
          props=[("kettlebell", "wristN")]),
        P(front=True, t=-80, lN=(15, 105, 0), lF=(165, 165, -100), aN=(72, -168), aF=(108, -12),
          props=[("kettlebell", ("handN", 0, -8), True)]),
    ],
    "ring-push-up": [
        plank(aN=(90, 90), aF=(90, 90), props=[("ring", "wristN")]),
        P(t=-2, lN=(178, 178), lF=(178, 178), aN=(145, 45), aF=(145, 45), props=[("ring", "wristN")]),
    ],
    "landmine-press": [
        P(lN=(0, 90, 0), lF=(90, 180, 180), aN=(110, -100), aF=(100, 40),
          props=[("landmine", "wristN", 200)]),
        P(t=-84, lN=(0, 90, 0), lF=(90, 180, 180), aN=(-45, -40), aF=(100, 40),
          props=[("landmine", "wristN", 200)]),
    ],
    "trx-body-saw": [
        P(t=-4, lN=(178, 178), lF=(178, 178), aN=(95, -5), aF=(95, -5),
          props=[("strap", "ankleN", -40)]),
        P(t=-4, lN=(178, 178), lF=(178, 178), aN=(55, 0), aF=(55, 0),
          props=[("strap", "ankleN", -60)]),
    ],
    "hanging-knee-raise": [
        P(scale=0.84, top_down=True, aN=(-88, -90), aF=(-92, -90), pin=("wristN", (200, 30)), props=[("bar", "wristN")]),
        P(scale=0.84, top_down=True, t=-96, lN=(-15, 95), lF=(-10, 100), aN=(-84, -88), aF=(-88, -88), pin=("wristN", (200, 30)),
          props=[("bar", "wristN")]),
    ],
    "hollow-hold": [
        P(t=185, h=190, lN=(-5, -5, -90), lF=(-5, -5, -90), aN=(190, 190), aF=(188, 188),
          props=[("mat", -150, 150)]),
        P(t=195, h=200, curl=-6, lN=(-14, -14, -100), lF=(-14, -14, -100), aN=(198, 198), aF=(196, 196),
          props=[("mat", -150, 150)]),
    ],
    "suitcase-carry": [
        P(lN=(70, 105), lF=(110, 90, 0), aN=(95, 90), aF=(80, 95), props=[("kettlebell", "wristN")]),
        P(lN=(110, 90, 0), lF=(70, 105), aN=(85, 90), aF=(100, 85), props=[("kettlebell", "wristN")]),
    ],
    "overhead-carry": [
        P(scale=0.74, lN=(70, 105), lF=(110, 90, 0), aN=(-90, -90), aF=(80, 95), props=[("kettlebell", ("handN", 0, -8), True)]),
        P(scale=0.74, lN=(110, 90, 0), lF=(70, 105), aN=(-90, -90), aF=(100, 85), props=[("kettlebell", ("handN", 0, -8), True)]),
    ],
    "prone-ytw": [
        P(t=-30, lN=(110, 90, 0), lF=(110, 90, 0), aN=(90, 90), aF=(85, 90),
          props=[("pad", "hip", "shoulder", 14, 14), ("post", ("hip", 30, 8)), ("dumbbell", "wristN")]),
        P(t=-30, lN=(110, 90, 0), lF=(110, 90, 0), aN=(-30, -30), aF=(-34, -34),
          props=[("pad", "hip", "shoulder", 14, 14), ("post", ("hip", 30, 8)), ("dumbbell", "wristN")]),
    ],
    "push-up-plus": [
        P(t=-2, lN=(178, 178), lF=(178, 178), aN=(145, 45, 0), aF=(145, 45, 0)),
        P(t=-7, curl=7, lN=(174, 174), lF=(174, 174), aN=(90, 90, 0), aF=(90, 90, 0)),
    ],
    "pronation-supination": [
        P(lN=(0, 90, 0), lF=(0, 90, 0), aN=(70, -5), aF=(80, 10),
          props=[("seat", "hip"), ("dumbbell", "handN", -90)]),
        P(lN=(0, 90, 0), lF=(0, 90, 0), aN=(70, -5), aF=(80, 10),
          props=[("seat", "hip"), ("dumbbell", "handN", -10)]),
    ],
    "trap-bar-jump": [
        P(t=-62, lN=(30, 120), lF=(30, 120), aN=(95, 95), aF=(92, 92),
          props=[("plate", "wristN", 22, 0, 4)]),
        P(t=-88, lN=(95, 92, 40), lF=(95, 92, 40), aN=(95, 92), aF=(92, 92), lift=34,
          props=[("plate", "wristN", 22, 0, 4), ("motion", "head", -90, 22, 22, -10)]),
    ],
    "rotational-throw": [
        P(front=True, t=-96, lN=(75, 95, 0), lF=(118, 92, 180), aN=(140, 180), aF=(120, 170),
          props=[("ball", "wristF", 13, -6, 0)]),
        P(front=True, t=-82, lN=(62, 90, 0), lF=(105, 85, 180), aN=(-10, -5), aF=(10, -10),
          props=[("ball", "wristN", 13, 34, -6), ("motion", "wristN", -5, 24, 52, -8)]),
    ],
    "explosive-pull-up": [
        P(scale=0.84, top_down=True, aN=(-88, -90), aF=(-92, -90), lN=(95, 100), lF=(85, 95), pin=("wristN", (200, 30)),
          props=[("bar", "wristN")]),
        P(scale=0.84, top_down=True, aN=(62, -100), aF=(58, -100), lN=(95, 100), lF=(85, 95), pin=("wristN", (200, 30)),
          props=[("bar", ("wristN", 0, 0)), ("motion", "hip", -90, 24, 30, -20)]),
    ],
    "ski-erg": [
        P(scale=0.84, t=-88, lN=(88, 92), lF=(88, 92), aN=(-75, -80), aF=(-80, -85),
          props=[("skierg", 70), ("cords", 70, "wristN", "wristF")]),
        P(scale=0.84, t=-45, lN=(60, 120), lF=(60, 120), aN=(100, 110), aF=(95, 105),
          props=[("skierg", 70), ("cords", 70, "wristN", "wristF")]),
    ],
    "air-bike": [
        P(t=-82, lN=(20, 70), lF=(45, 125), aN=(-5, 5), aF=(30, -20),
          props=[("airbike", "hip", 110), ("handles", ("hip", 105, 30), "wristN", "wristF")]),
        P(t=-82, lN=(45, 125), lF=(20, 70), aN=(30, -20), aF=(-5, 5),
          props=[("airbike", "hip", 110), ("handles", ("hip", 105, 30), "wristN", "wristF")]),
    ],
    "hip-90-90": [
        P(front=True, lN=(-20, 125), lF=(15, 140), aN=(120, 100), aF=(60, 80),
          props=[("mat", -130, 130)]),
        P(front=True, lN=(165, 40), lF=(200, 55), aN=(120, 100), aF=(60, 80),
          props=[("mat", -130, 130)]),
    ],
    "band-dislocates": [
        P(scale=0.84, front=True, lN=(80, 90, 0), lF=(100, 90, 180), aN=(60, 70), aF=(120, 110),
          props=[("band", "wristN", "wristF")]),
        P(scale=0.84, front=True, lN=(80, 90, 0), lF=(100, 90, 180), aN=(-40, -55), aF=(-140, -125),
          props=[("band", "wristN", "wristF")]),
    ],
    "scap-push-up": [
        plank(t=-2, curl=-5),
        plank(t=-6, curl=8),
    ],
    "squat-to-stand": [
        P(t=70, h=80, curl=8, lN=(100, 92), lF=(100, 92), aN=(85, 105), aF=(85, 102)),
        P(t=-65, lN=(-12, 112), lF=(-12, 112), aN=(-60, -70), aF=(-65, -72)),
    ],
    "lunge-twist": [
        P(lN=(90, 90), lF=(90, 90), aN=(10, 0), aF=(5, 0)),
        P(lN=(15, 95), lF=(135, 165, 180), aN=(30, -20), aF=(-30, -10)),
    ],
    "wrist-prep": [
        quadruped(aN=(90, 90, 180), aF=(90, 90, 180)),
        quadruped(t=-12, aN=(70, 70, 180), aF=(70, 70, 180)),
    ],
    "frog-rockback": [
        quadruped(lN=(80, 180, 180), lF=(100, 180, 180), props=[("mat", -110, 140)]),
        quadruped(t=-10, lN=(135, 180, 180), lF=(140, 180, 180), aN=(10, 90, 0), aF=(10, 90, 0),
                  props=[("mat", -110, 140)]),
    ],
    "deep-squat-pry": [
        P(t=-72, lN=(-12, 110), lF=(-8, 112), aN=(70, -80), aF=(65, -80)),
        P(t=-58, lN=(-12, 110), lF=(-8, 112), aN=(80, -40), aF=(60, -70)),
    ],
    "bw-cossack": [
        P(front=True, lN=(66, 90, 0), lF=(114, 90, 180), aN=(10, 0), aF=(170, 180)),
        P(front=True, t=-80, lN=(12, 108, 0), lF=(165, 165, -100), aN=(-10, -5), aF=(20, 10)),
    ],
    "pancake-gm": [
        P(t=-90, lN=(0, 0, -90), lF=(0, 0, -90), aN=(90, 0), aF=(90, 0), props=[("mat", -60, 160)]),
        P(t=-14, h=-5, lN=(0, 0, -90), lF=(0, 0, -90), aN=(0, 0), aF=(5, 5), props=[("mat", -60, 160)]),
    ],
    "hip-flexor-lift": [
        P(t=-88, lN=(0, 0, -90), lF=(0, 0, -90), aN=(75, 75, 0), aF=(78, 78, 0), props=[("mat", -60, 160)]),
        P(t=-88, lN=(-14, -14, -100), lF=(0, 0, -90), aN=(75, 75, 0), aF=(78, 78, 0),
         props=[("mat", -60, 160)]),
    ],
    "wall-slide": [
        P(scale=0.84, front=True, lN=(85, 90, 0), lF=(95, 90, 180), aN=(10, -80), aF=(170, -100),
          props=[("panel", -95, 28, 190, 240)]),
        P(scale=0.84, front=True, lN=(85, 90, 0), lF=(95, 90, 180), aN=(-50, -65), aF=(-130, -115),
          props=[("panel", -95, 28, 190, 240)]),
    ],
    "shoulder-car": [
        P(scale=0.84, aN=(0, 0), props=[("arc", "shoulder", 78, -160, 70)]),
        P(scale=0.84, aN=(-110, -120), props=[("arc", "shoulder", 78, -160, 70)]),
    ],
    "open-book": [
        P(top_down=True, t=0, lN=(70, 160), lF=(66, 156), aN=(80, 80), aF=(78, 78), pin=("hip", (170, 200)),
          props=[]),
        P(top_down=True, t=0, lN=(70, 160), lF=(66, 156), aN=(-95, -100), aF=(78, 78), pin=("hip", (170, 200)),
          props=[("arc", "shoulder", 70, -80, 70)]),
    ],
    "thread-needle": [
        quadruped(aN=(-90, -90), aF=(90, 90, 0)),
        quadruped(t=15, aN=(170, 180), aF=(110, 80, 0)),
    ],
    "t-spine-roller": [
        P(t=200, h=230, lN=(-40, 75, 0), lF=(-40, 75, 0), aN=(-100, 40), aF=(-100, 40),
         props=[("roller", "shoulder", 6)]),
        P(t=172, h=150, lN=(-30, 82, 0), lF=(-30, 82, 0), aN=(-150, 40), aF=(-150, 40),
         props=[("roller", "shoulder", 6)]),
    ],
    "knee-to-wall": [
        P(lN=(5, 90, 0), lF=(90, 180, 180), aN=(5, 0), aF=(0, 0), props=[("wall", 118)]),
        P(t=-80, lN=(-5, 62, 0), lF=(100, 180, 180), aN=(5, 0), aF=(0, 0), props=[("wall", 118)]),
    ],
    "jefferson-curl": [
        P(scale=0.84, aN=(90, 90), aF=(88, 88), props=[("box", -40, 80, 60), ("dumbbell", "wristN")]),
        P(scale=0.84, t=85, h=95, curl=18, aN=(95, 95), aF=(92, 92), props=[("box", -40, 80, 60), ("dumbbell", "wristN")],
         lift=60),
    ],
    "pec-stretch": [
        P(aN=(180, -90), aF=(90, 90), props=[("post", ("wristN", 0, -10)), ("wall", -60)]),
        P(t=-80, lN=(70, 110), lF=(105, 85, 0), aN=(190, -95), aF=(90, 90),
          props=[("post", ("wristN", 0, -10)), ("wall", -64)]),
    ],
    "lat-stretch": [
        P(t=-10, lN=(90, 180, 180), lF=(90, 180, 180), aN=(-15, -80), aF=(-12, -80),
          props=[("bench", "elbowN", 90, 40)]),
        P(t=15, h=25, lN=(125, 180, 180), lF=(125, 180, 180), aN=(-5, -80), aF=(-2, -80),
          props=[("bench", "elbowN", 90, 40)]),
    ],
    "sleeper-stretch": [
        P(top_down=True, t=0, lN=(160, 120), lF=(156, 116), aN=(-90, -90), aF=(60, -40), pin=("hip", (190, 180)),
          props=[]),
        P(top_down=True, t=0, lN=(160, 120), lF=(156, 116), aN=(-90, -10), aF=(55, -60), pin=("hip", (190, 180)),
          props=[]),
    ],
    "biceps-wall": [
        P(aN=(175, 180, 180), aF=(90, 90), props=[("wall", -88)]),
        P(t=-84, aN=(170, 175, 180), aF=(90, 90), lN=(75, 100), lF=(100, 85, 0), props=[("wall", -88)]),
    ],
    "forearm-extensor": [
        P(aN=(0, 0, 0), aF=(70, 0)),
        P(aN=(0, 0, 100), aF=(30, -15)),
    ],
    "couch-stretch": [
        P(t=-62, lN=(-2, 92, 0), lF=(110, -110, -110), aN=(75, 0), aF=(80, 10),
         props=[("box", -95, 70, 52)]),
        P(t=-90, lN=(-2, 92, 0), lF=(110, -110, -110), aN=(90, 90), aF=(90, 90),
         props=[("box", -95, 70, 52)]),
    ],
    "pigeon": [
        P(t=-82, lN=(25, 175, 180), lF=(175, 178, 180), aN=(80, 85, 0), aF=(78, 85, 0)),
        P(t=-8, h=0, lN=(25, 175, 180), lF=(175, 178, 180), aN=(10, 5), aF=(8, 5)),
    ],
    "frog-stretch": [
        P(t=-2, lN=(85, 180, 180), lF=(95, 180, 180), aN=(90, 0), aF=(90, 0), props=[("mat", -110, 140)]),
        P(t=-14, lN=(115, 180, 180), lF=(120, 180, 180), aN=(70, 0), aF=(70, 0), props=[("mat", -110, 140)]),
    ],
    "sphinx": [
        P(t=-2, h=0, lN=(180, 180, 90), lF=(180, 180, 90), aN=(120, 0), aF=(120, 0),
          props=[("mat", -170, 110)]),
        P(t=-22, h=-50, lN=(180, 180, 90), lF=(180, 180, 90), aN=(90, 0), aF=(90, 0),
          props=[("mat", -170, 110)]),
    ],
    "side-delt-stretch": [
        P(front=True, lN=(84, 90, 0), lF=(96, 90, 180), aN=(110, 175), aF=(70, 175)),
        P(front=True, h=-60, lN=(84, 90, 0), lF=(96, 90, 180), aN=(120, 185), aF=(60, 168)),
    ],
    "breathing": [
        P(t=180, h=180, lN=(-90, 0, -90), lF=(-90, 0, -90), aN=(30, -20), aF=(30, -20),
          props=[("box", 30, 70, 44), ("breath", ("hip", -30, -16))]),
        P(t=180, h=180, lN=(-90, 0, -90), lF=(-90, 0, -90), aN=(30, -20), aF=(30, -20),
          props=[("box", 30, 70, 44)]),
    ],
    "barbell-split-squat": [
        P(lN=(70, 100), lF=(115, 115, 180), aN=(130, -40), aF=(125, -40),
          props=[("plate", ("shoulder", -4, 0), 26)]),
        P(lN=(5, 95), lF=(110, 170, 180), aN=(130, -40), aF=(125, -40),
          props=[("plate", ("shoulder", -4, 0), 26)]),
    ],
    "reverse-nordic": [
        P(lN=(90, 180, 180), lF=(90, 180, 180), aN=(70, -110), aF=(70, -110), props=[("mat", -90, 110)]),
        P(t=-122, h=-110, lN=(58, 180, 180), lF=(58, 180, 180), aN=(30, -150), aF=(30, -150), props=[("mat", -90, 110)]),
    ],
    "trx-hamstring-curl": [
        P(t=168, h=180, lN=(-10, -10, -95), lF=(-10, -10, -95), aN=(8, 0), aF=(8, 0),
          props=[("strap", "ankleN", 330), ("mat", -110, 60)]),
        P(t=152, h=172, lN=(-58, 42, -60), lF=(-58, 42, -60), aN=(20, 0), aF=(20, 0),
          props=[("strap", "ankleN", 330), ("mat", -110, 60)]),
    ],
    "copenhagen-plank": [
        P(front=True, t=0, h=0, lN=(180, 180, 180), lF=(158, 158, 158), aN=(90, 0), aF=(-40, 140),
          pin=("elbowN", (300, 262)), props=[("bench", "ankleN", 80, -20, 9)]),
        P(front=True, t=0, h=0, lN=(180, 180, 180), lF=(178, 178, 178), aN=(90, 0), aF=(-90, -90),
          pin=("elbowN", (300, 262)), props=[("bench", "ankleN", 80, -20, 9)]),
    ],
    "torso-rotation": [
        P(front=True, lN=(-10, 90, 0), lF=(190, 90, 180), aN=(40, 170), aF=(140, 10),
          props=[("machine", -70, 40, 140, 70), ("seat", "hip", 70)]),
        P(front=True, lN=(-30, 70, -20), lF=(150, 110, 200), aN=(40, 170), aF=(140, 10),
          props=[("machine", -70, 40, 140, 70), ("seat", "hip", 70), ("motion", "kneeN", -30, 24, 10, -10)]),
    ],
    # Travel kit (#68).
    "bw-reverse-lunge": [
        P(aN=(80, 95), aF=(80, 95)),
        P(lN=(5, 95), lF=(110, 170, 180), aN=(80, 95), aF=(80, 95)),
    ],
    "sl-hip-thrust": [
        P(t=205, lN=(-5, 95, 0), lF=(-20, -20), aN=(120, 30), aF=(120, 30),
          props=[("bench", "shoulder", 70, -20)]),
        P(t=180, lN=(-30, 90, 0), lF=(-25, -25), aN=(120, 30), aF=(120, 30),
          props=[("bench", "shoulder", 70, -20)]),
    ],
    "bw-sl-rdl": [
        P(lF=(100, 120), aN=(90, 90), aF=(90, 90)),
        P(t=-8, lN=(85, 95, 0), lF=(185, 185, 95), aN=(90, 90), aF=(90, 90)),
    ],
    "prone-pulldown": [
        P(t=-4, h=-6, lN=(180, 180, 90), lF=(180, 180, 90), aN=(-6, -6), aF=(-4, -4), props=[("mat", -170, 150)]),
        P(t=-8, h=-10, lN=(180, 180, 90), lF=(180, 180, 90), aN=(170, 10), aF=(168, 8), props=[("mat", -170, 150)]),
    ],
    "pike-push-up": [
        P(t=48, h=60, lN=(128, 128, 0), lF=(128, 128, 0), aN=(92, 92, 0), aF=(92, 92, 0)),
        P(t=62, h=75, lN=(122, 122, 0), lF=(122, 122, 0), aN=(150, 40, 0), aF=(150, 40, 0)),
    ],
    "bw-calf-raise": [
        P(lN=(90, 90, 15), lF=(100, 160), aN=(15, 5), aF=(20, 10), props=[("box", -10, 40, 26), ("wall", 80)]),
        P(lN=(90, 90, 75), lF=(100, 160), aN=(15, 5), aF=(20, 10), props=[("box", -10, 40, 26), ("wall", 80)], lift=10),
    ],
    "db-floor-pullover": [
        P(t=180, h=180, lN=(-50, 60, 0), lF=(-50, 60, 0), aN=(-88, -88), aF=(-92, -92),
          props=[("mat", -150, 120), ("dumbbell", "wristN")]),
        P(t=180, h=180, lN=(-50, 60, 0), lF=(-50, 60, 0), aN=(178, 178), aF=(176, 176),
          props=[("mat", -150, 120), ("dumbbell", "wristN")]),
    ],
    "band-row": [
        P(lN=(70, 100), lF=(110, 90, 0), aN=(2, 2), aF=(4, 4),
          props=[("band", "wristN", ("hip", 165, -58)), ("post", ("hip", 165, -58))]),
        P(lN=(70, 100), lF=(110, 90, 0), aN=(150, -5), aF=(152, -3),
          props=[("band", "wristN", ("hip", 165, -58)), ("post", ("hip", 165, -58))]),
    ],
    "band-pulldown": [
        P(lN=(90, 180, 180), lF=(90, 180, 180), aN=(-62, -62), aF=(-64, -64),
          props=[("band", "wristN", ("hip", 120, -200)), ("wall", 126)]),
        P(lN=(90, 180, 180), lF=(90, 180, 180), aN=(115, -75), aF=(112, -78),
          props=[("band", "wristN", ("hip", 120, -200)), ("wall", 126)]),
    ],
    "band-chest-press": [
        P(lN=(70, 100), lF=(110, 90, 0), aN=(150, -10), aF=(152, -8),
          props=[("band", "wristN", ("hip", -110, -58)), ("post", ("hip", -110, -58))]),
        P(lN=(70, 100), lF=(110, 90, 0), aN=(0, 0), aF=(2, 2),
          props=[("band", "wristN", ("hip", -110, -58)), ("post", ("hip", -110, -58))]),
    ],
}
