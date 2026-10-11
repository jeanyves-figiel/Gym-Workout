"""Pose helpers for the exercise scenes (scenes*.py, #170).

Angles: degrees, 0 = right, 90 = down, -90 = up (figure faces right in side view).
  t        torso (hip → shoulder)          h     neck/head
  lN, lF   (thigh, shin[, foot])           aN, aF (upper arm, forearm[, hand])
  curl     bow of the torso (px, + = rounds the back)
  front    frontal view (both sides opaque)
  pin      (joint, (x, y)) instead of floor grounding
  lift     px above the floor (lowest joint otherwise rests on it)
  scale    shrink the whole drawing (tall poses)   top_down  no floor line (seen from above, or hanging)
  front    True = front view, "back" = back view     lit_sides  "N" = only the near limbs light up
  inset    corner of the muscle map ("tl", "tr", "bl", "br") or None
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
