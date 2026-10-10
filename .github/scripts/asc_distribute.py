"""Add the newest App Store Connect build to a TestFlight beta group.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8), APP_ID, GROUP (group name), WAIT_MIN (default 30).
Waits for the build to finish Apple processing, then assigns it. Idempotent.
"""
import json, os, sys, time, urllib.error, urllib.request

import jwt  # PyJWT[crypto]

API = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def call(method: str, path: str, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: HTTP {e.code} {e.read().decode()[:500]}")


app, group_name = os.environ["APP_ID"], os.environ.get("GROUP", "Workout")
deadline = time.time() + 60 * int(os.environ.get("WAIT_MIN", "30"))
while True:
    builds = call("GET", f"/builds?filter[app]={app}&sort=-uploadedDate&limit=1")["data"]
    if not builds:
        sys.exit("No builds found")
    build = builds[0]
    state = build["attributes"]["processingState"]
    print(f"Build {build['attributes']['version']}: {state}")
    if state == "VALID":
        break
    if state in ("FAILED", "INVALID") or time.time() > deadline:
        sys.exit(f"Build not usable: {state}")
    time.sleep(30)

groups = [g for g in call("GET", f"/betaGroups?filter[app]={app}&limit=50")["data"] if g["attributes"]["name"] == group_name]
if not groups:
    sys.exit(f"Beta group {group_name!r} not found")
call("POST", f"/betaGroups/{groups[0]['id']}/relationships/builds", {"data": [{"type": "builds", "id": build["id"]}]})
print(f"Build {build['attributes']['version']} added to {group_name!r}")
