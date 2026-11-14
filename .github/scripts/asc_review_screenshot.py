"""App Review screenshot (the paywall) for every subscription and the Lifetime purchase (#1090).

Env: as asc_listing.py, plus SHOT (PNG path). Products that already have one are left alone unless REPLACE=true.
"""
import hashlib, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from asc_listing import APP, APPLY, call, get_all  # noqa: E402

SHOT = os.environ["SHOT"]
REPLACE = os.environ.get("REPLACE", "false").lower() == "true"
data = open(SHOT, "rb").read()


def upload(kind, rel_name, rel_type, owner_id):
    shot = call("POST", f"/v1/{kind}", {"data": {"type": kind,
            "attributes": {"fileName": "paywall.png", "fileSize": len(data)},
            "relationships": {rel_name: {"data": {"type": rel_type, "id": owner_id}}}}})["data"]
    for op in shot["attributes"]["uploadOperations"]:
        req = urllib.request.Request(op["url"], data=data[op["offset"]:op["offset"] + op["length"]], method=op["method"],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders") or []})
        urllib.request.urlopen(req, timeout=120).read()
    call("PATCH", f"/v1/{kind}/{shot['id']}", {"data": {"type": kind, "id": shot["id"],
         "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


def handle(label, current_path, kind, rel_name, rel_type, owner_id):
    cur = (call("GET", current_path, allow404=True) or {}).get("data")
    if cur and not REPLACE:
        print(f"= {label}: has a review screenshot")
        return
    print(f"{'+' if APPLY else '?'} {label}: review screenshot{' (replace)' if cur else ''}")
    if APPLY:
        if cur:
            call("DELETE", f"/v1/{kind}/{cur['id']}")
        upload(kind, rel_name, rel_type, owner_id)


print(f"{'APPLY' if APPLY else 'DRY RUN'}: review screenshots for app {APP} ({len(data)} B)")
groups, _ = get_all(f"/v1/apps/{APP}/subscriptionGroups")
for g in groups:
    subs, _ = get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptions")
    for s in subs:
        handle(s["attributes"]["productId"], f"/v1/subscriptions/{s['id']}/appStoreReviewScreenshot",
               "subscriptionAppStoreReviewScreenshots", "subscription", "subscriptions", s["id"])
iaps, _ = get_all(f"/v1/apps/{APP}/inAppPurchasesV2")
for i in iaps:
    handle(i["attributes"]["productId"], f"/v2/inAppPurchases/{i['id']}/appStoreReviewScreenshot",
           "inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseV2", "inAppPurchases", i["id"])
