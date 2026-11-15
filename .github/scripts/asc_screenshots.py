"""Upload App Store screenshots to the editable iOS version (#1090).

Env: as asc_listing.py, plus SHOTS_DIR (the `full/` folder of the app-store-screenshots branch).
Each device folder (iPhone 6.9", 6.3", iPad 13", Watch) replaces that display type's screenshots in every listing locale (APPLY=true),
in file-name order. Blank captures (player all white, #1078: under 150 KB) are skipped.
Dry run lists what would be uploaded.
"""
import hashlib, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from asc_listing import APP, APPLY, LOCS, call, get_all  # noqa: E402

DIR = os.environ["SHOTS_DIR"]
# watch: Apple Watch Series 10/11 46 mm captures (416 x 496), required because the app ships a Watch app.
TYPES = {"iphone-6.9": "APP_IPHONE_67", "iphone-6.3": "APP_IPHONE_61", "ipad-13": "APP_IPAD_PRO_3GEN_129",
         "watch": "APP_WATCH_SERIES_10"}
MIN_BYTES = 150_000


def files(folder):
    out = []
    min_bytes = 0 if folder.endswith("watch") else MIN_BYTES  # Watch captures are small by nature
    for f in sorted(os.listdir(folder)):
        p = os.path.join(folder, f)
        if f.endswith(".jpg") and os.path.getsize(p) >= min_bytes:
            out.append(p)
        elif f.endswith(".jpg"):
            print(f"  skip {f} (blank capture, {os.path.getsize(p)} B)")
    return out[:10]


def upload(set_id, path):
    data = open(path, "rb").read()
    shot = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
            "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in shot["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"],
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders") or []})
        urllib.request.urlopen(req, timeout=120).read()
    call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
         "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


def main():
    print(f"{'APPLY' if APPLY else 'DRY RUN'}: screenshots for app {APP} from {DIR}")
    vs, _ = get_all(f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=PREPARE_FOR_SUBMISSION")
    if not vs:
        sys.exit("No version in Prepare for Submission")
    locs, _ = get_all(f"/v1/appStoreVersions/{vs[0]['id']}/appStoreVersionLocalizations")
    for loc in (x for x in locs if x["attributes"]["locale"] in LOCS):
        lid, lname = loc["id"], loc["attributes"]["locale"]
        sets, _ = get_all(f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets")
        for folder, dtype in TYPES.items():
            src = os.path.join(DIR, folder)
            if folder == "watch" and not os.path.isdir(src):
                src = os.environ.get("WATCH_SHOTS_DIR", "ios/AppStore/screenshots/watch")  # kept in the repo
            if not os.path.isdir(src):
                print(f"{lname} {dtype}: no folder {folder}")
                continue
            shots = files(src)
            print(f"{lname} {dtype}: {len(shots)} screenshots ({', '.join(os.path.basename(s) for s in shots)})")
            if not APPLY:
                continue
            s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == dtype), None)
            if s:
                old, _ = get_all(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")
                for o in old:
                    call("DELETE", f"/v1/appScreenshots/{o['id']}")
                sid = s["id"]
            else:
                sid = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                           "attributes": {"screenshotDisplayType": dtype},
                           "relationships": {"appStoreVersionLocalization": {"data": {
                               "type": "appStoreVersionLocalizations", "id": lid}}}}})["data"]["id"]
            for p in shots:
                upload(sid, p)
            print("  uploaded")


if __name__ == "__main__":
    main()
