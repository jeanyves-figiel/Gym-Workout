"""App Review submission status / cancel (#1090).

Env: as asc_listing.py, plus REVIEW_ACTION (status | cancel). `cancel` withdraws the open iOS review
submission (Waiting for Review / In Review) when APPLY=true; the version goes back to editable.
"""
import os, sys

sys.path.insert(0, os.path.dirname(__file__))
from asc_listing import APP, APPLY, call, get_all  # noqa: E402

ACTION = os.environ.get("REVIEW_ACTION", "status")
OPEN = {"WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"}

subs, _ = get_all(f"/v1/reviewSubmissions?filter[app]={APP}&filter[platform]=IOS")
for s in subs:
    a = s["attributes"]
    print(f"submission {s['id']}: {a.get('state')} submitted {a.get('submittedDate')}")
vs, _ = get_all(f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS")
for v in vs:
    print(f"version {v['attributes']['versionString']}: {v['attributes'].get('appStoreState')}")
if ACTION == "cancel":
    todo = [s for s in subs if s["attributes"].get("state") in OPEN]
    if not todo:
        sys.exit("No open review submission to cancel")
    for s in todo:
        print(f"{'cancel' if APPLY else 'would cancel'} {s['id']}")
        if APPLY:
            r = call("PATCH", f"/v1/reviewSubmissions/{s['id']}",
                     {"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"canceled": True}}})
            print(f"  now {r['data']['attributes'].get('state')}")
