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
