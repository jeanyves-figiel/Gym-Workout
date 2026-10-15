"""Print recent TestFlight crash reports (crashes testers chose to share) for the app.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8), APP_ID, LIMIT (default 5), OUT_DIR (full logs, uploaded as artifact).
Prints build, device, OS and the exception + crashed-thread frames only (no tester email or comment).
"""
import json, os, re, sys, time, urllib.error, urllib.request

import jwt  # PyJWT[crypto]

API = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def get(path: str):
    req = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {token()}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"GET {path}: HTTP {e.code} {e.read().decode()[:400]}")
        return None


def excerpt(log: str) -> str:
    keep, lines, crashed = [], log.splitlines(), False
    for i, line in enumerate(lines):
        if re.match(r"(Exception Type|Exception Codes|Exception Reason|Termination Reason|Triggered by Thread|Crashed Thread|Application Specific Information|Hardware Model|OS Version|Version):", line):
            keep.append(line)
            if line.startswith("Application Specific Information"):
                keep += lines[i + 1:i + 4]
        if re.match(r"Thread \d+ (name: .*)?Crashed:", line) or re.match(r"Thread \d+ Crashed:", line):
            crashed = True
            keep.append(line)
            continue
        if crashed:
            if not line.strip():
                crashed = False
                keep.append("")
            else:
                keep.append(line)
    return "\n".join(keep)


app = os.environ["APP_ID"]
limit = int(os.environ.get("LIMIT", "5"))
out = os.environ.get("OUT_DIR", "crashes")
os.makedirs(out, exist_ok=True)
subs = get(f"/apps/{app}/betaFeedbackCrashSubmissions?sort=-createdDate&limit={limit}&include=build")
if not subs:
    sys.exit("No crash submissions endpoint result")
builds = {b["id"]: b["attributes"].get("version") for b in subs.get("included", []) if b["type"] == "builds"}
print(f"{len(subs['data'])} crash submission(s)")
for s in subs["data"]:
    a = s["attributes"]
    bid = (s.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
    print("=" * 80)
    print(f"{a.get('createdDate')} build {builds.get(bid, '?')} {a.get('deviceModel')} iOS {a.get('osVersion')} "
          f"battery {a.get('batteryPercentage')} conn {a.get('connectionType')}")
    log = get(f"/betaFeedbackCrashSubmissions/{s['id']}/crashLog")
    text = ((log or {}).get("data") or {}).get("attributes", {}).get("logText") or ""
    if not text:
        print("(no crash log text)")
        continue
    open(os.path.join(out, f"{a.get('createdDate', s['id']).replace(':', '-')}.crash"), "w").write(text)
    print(excerpt(text)[:12000])

