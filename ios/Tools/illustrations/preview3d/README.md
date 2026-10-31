# 3D position guide preview (#959)

Renders the position guide's skinned body + equipment headless, the way `PositionGuideView` draws it, to check
contact (feet on plates, hands on handles, body on pads) without a Mac.

    cd ios/Tools/illustrations/preview3d
    npm i three@0.169.0 && cp node_modules/three/build/three.module.js .
    mkdir -p out
    python3 export.py out ../../../Packages/GymCore/Sources/WorkoutEngine/Resources/ExercisePositions.json.z leg-press
    node shot.js lp.png 300 300 leg-press_0:0 leg-press_0:-0.785 leg-press_0:0:3:ankleN   # name:yaw[:zoom[:joint]]
    python3 audit.py ../../../Packages/GymCore/Sources/WorkoutEngine/Resources/ExercisePositions.json.z > audit.txt

`audit.py` lists per key: body vertices inside pads / blocks / rods, feet 2.5–22 off a pad or block, fists off the
rod they hold, free hands next to a handle. Playwright's Chromium renders with SwiftShader; `P=prefix` on export.py
keeps two data versions side by side. Handles render steel; `export.py` writes posed vertices (MUSH 0).

## Realism check (#1020)

    python3 realism.py                      # every exercise: grip, through, limb, stretch, floor findings
    python3 realism.py barbell-shrug dips   # some exercises
    python3 realism.py --ratchet            # CI (Position realism workflow): fails on a finding not in realism-baseline.json
    python3 realism.py --write-baseline     # after fixing poses: lock in the smaller baseline

Needs numpy + scipy; JOBS=n workers (default CPU count, ~2.5 min on 4 cores). Findings: **grip** fist > 6 off the bar
it holds (weights > r + 7), free hand on a handle; **through** a bar, plate or weight inside the skin; **limb** forearm
in the trunk / legs, shin in the other leg; **stretch** limb scaled > 1.06; **floor** body or kit below the floor.

Body vs figure: the body's arms (67.7) are shorter than the 2D figure's (80) and the rig no longer stretches them
(`ARM_STRETCH` 1.03, Swift `armStretch`). `contact.py` moves held bars / handles into reach, bodies on bars to the bar
(`reach`), dip bars under the shoulders (`parallel_bars_width`), free forearms out of the hips (`arms_clear`), kit onto the
floor (`on_floor`), widens frames (`widen_frames`), moves machine parts and bars out of the skin (`clear_kit`, `bar_out`) and rebuilds shrugs (`shrugs`: `_elev` joint = shoulder girdle raised, rig `elev`).
