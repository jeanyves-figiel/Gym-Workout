"""List / revoke the Apple Development certificates CI creates when it signs an archive.

Every TestFlight run signs on a fresh macOS runner, so Xcode creates a new development certificate
via the App Store Connect API key ("Created via API"); its private key dies with the runner. Apple caps
development certificates per account, so these pile up until archiving fails with
"Your account has reached the maximum number of certificates".

Usage: asc_ci_certs.py list | prune | revoke-serials SERIAL...
  list            print every development certificate (read-only)
  prune           revoke development certificates named "Created via API" (never the ones made on a Mac)
  revoke-serials  revoke the "Created via API" certificates with these serial numbers (this run's own)
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8).
"""
import json, os, sys, time, urllib.error, urllib.request

import jwt  # PyJWT[crypto]

API = "https://api.appstoreconnect.apple.com/v1"
DEV_TYPES = "DEVELOPMENT,IOS_DEVELOPMENT,MAC_APP_DEVELOPMENT"
CI_MARK = "Created via API"


def token() -> str:
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]},
    )


def call(method: str, path: str):
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": f"Bearer {token()}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: HTTP {e.code} {e.read().decode()[:500]}")


def dev_certs():
    certs = call("GET", f"/certificates?filter[certificateType]={DEV_TYPES}&limit=200")["data"]
    for c in certs:
        a = c["attributes"]
        print(f"- {a.get('name')} | {a.get('displayName')} | {a.get('certificateType')} | "
              f"serial {a.get('serialNumber')} | expires {a.get('expirationDate')}")
    return certs


def is_ci(c) -> bool:
    a = c["attributes"]
    return CI_MARK in (a.get("name") or "") or CI_MARK in (a.get("displayName") or "")


def revoke(certs):
    for c in certs:
        call("DELETE", f"/certificates/{c['id']}")
        print(f"Revoked {c['attributes'].get('name')} (serial {c['attributes'].get('serialNumber')})")
    print(f"{len(certs)} certificate(s) revoked")


mode = sys.argv[1] if len(sys.argv) > 1 else "list"
certs = dev_certs()
print(f"{len(certs)} development certificate(s), {sum(map(is_ci, certs))} created by CI")
if mode == "prune":
    revoke([c for c in certs if is_ci(c)])
elif mode == "revoke-serials":
    serials = {s.upper().lstrip("0") for s in sys.argv[2:]}
    revoke([c for c in certs if is_ci(c) and (c["attributes"].get("serialNumber") or "").upper().lstrip("0") in serials])
elif mode != "list":
    sys.exit(__doc__)
