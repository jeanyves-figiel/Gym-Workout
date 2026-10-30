"""Push the App Store listing in ios/AppStore/listing.json to App Store Connect (#882).

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8), APP_ID,
     APPLY ("true" to write; anything else = dry run, GET requests only),
     REVIEW_DEMO_EMAIL, REVIEW_DEMO_PASSWORD, REVIEW_CONTACT_PHONE (optional secrets for App Review Information).

Sets, for the editable iOS version (state PREPARE_FOR_SUBMISSION and the like):
  - App info (en-US): name, subtitle, privacy policy URL; primary + secondary category.
  - Age rating declaration.
  - Version (en-US): description, keywords, promotional text, support + marketing URLs.
  - App Review Information: contact, demo account, notes.
Not in Apple's API, so done by hand in App Store Connect: App Privacy labels (answers in
docs/app-store-review.md) and screenshots (app-store-screenshots branch).
"""
import json, os, sys, time, urllib.error, urllib.request

import jwt  # PyJWT[crypto]

API = "https://api.appstoreconnect.apple.com"
APP = os.environ["APP_ID"]
APPLY = os.environ.get("APPLY", "false").lower() == "true"
# Same client as asc_subscriptions.py (that script runs on import).
_tok = {"exp": 0, "jwt": ""}


def token() -> str:
    now = int(time.time())
    if now > _tok["exp"] - 60:
        key = open(os.environ["ASC_KEY_PATH"]).read()
        _tok.update(exp=now + 900, jwt=jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
            key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]}))
    return _tok["jwt"]


def call(method: str, path: str, body=None, allow404=False):
    url = path if path.startswith("http") else API + path
    for attempt in range(8):
        req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors="replace")
            if e.code == 429 or e.code >= 500:
                wait = min(60, 2 ** attempt * 2)
                print(f"  {method} {path}: HTTP {e.code}, retrying in {wait}s")
                time.sleep(wait)
                continue
            if e.code == 404 and allow404:
                return None
            print(f"{method} {path}: HTTP {e.code} {text[:1500]}")
            sys.exit(1)
    sys.exit(f"{method} {path}: giving up after repeated 429/5xx")


def get_all(path: str):
    """GET every page of a collection. Returns (data, included)."""
    data, included, url = [], [], path + ("&" if "?" in path else "?") + "limit=200"
    while url:
        r = call("GET", url)
        data += r.get("data") or []
        included += r.get("included") or []
        url = (r.get("links") or {}).get("next")
    return data, included


L = json.load(open(os.path.join(os.path.dirname(__file__), "../../ios/AppStore/listing.json")))
LOC = L["locale"]
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
            "WAITING_FOR_REVIEW", "INVALID_BINARY"}
summary = []


def patch(kind: str, id_: str, attributes: dict, label: str, relationships=None):
    """PATCH only the attributes that differ from `current` (caller passes the diff). Dry run prints."""
    if not attributes and not relationships:
        summary.append(f"= {label}")
        return
    summary.append(f"{'~' if APPLY else '?'} {label}: {', '.join(list(attributes) + list(relationships or {}))}")
    if APPLY:
        body = {"data": {"type": kind, "id": id_, "attributes": attributes}}
        if relationships:
            body["data"]["relationships"] = relationships
        call("PATCH", f"/v1/{kind}/{id_}", body)


def create(kind: str, attributes: dict, relationships: dict, label: str):
    summary.append(f"{'+' if APPLY else '?'} {label}")
    if APPLY:
        return call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": attributes,
                                                     "relationships": relationships}})["data"]["id"]


def diff(current: dict, wanted: dict) -> dict:
    return {k: v for k, v in wanted.items() if v is not None and current.get(k) != v}


def app_info():
    infos, _ = get_all(f"/v1/apps/{APP}/appInfos")
    info = next((i for i in infos if i["attributes"].get("appStoreState") in EDITABLE
                 or i["attributes"].get("state") in {"PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW"}), infos[0])
    iid = info["id"]
    cats = {k: {"data": {"type": "appCategories", "id": L[f"{k}"]}} for k in ("primaryCategory", "secondaryCategory")}
    current = {}
    for k in cats:
        r = call("GET", f"/v1/appInfos/{iid}/relationships/{k}", allow404=True) or {}
        current[k] = ((r.get("data") or {}).get("id"))
    patch("appInfos", iid, {}, "App info categories",
          {k: v for k, v in cats.items() if current[k] != L[k]} or None)

    locs, _ = get_all(f"/v1/appInfos/{iid}/appInfoLocalizations")
    wanted = {"name": L["name"], "subtitle": L["subtitle"], "privacyPolicyUrl": L["privacyPolicyUrl"]}
    loc = next((x for x in locs if x["attributes"]["locale"] == LOC), None)
    if loc:
        patch("appInfoLocalizations", loc["id"], diff(loc["attributes"], wanted), f"App info {LOC}")
    else:
        create("appInfoLocalizations", {"locale": LOC, **wanted},
               {"appInfo": {"data": {"type": "appInfos", "id": iid}}}, f"App info {LOC}")

    age = call("GET", f"/v1/appInfos/{iid}/ageRatingDeclaration")["data"]
    # Only questions Apple's API has for this app (the questionnaire grows over time).
    known = {k: v for k, v in L["ageRating"].items() if k in age["attributes"]}
    for k in sorted(set(L["ageRating"]) - set(known)):
        summary.append(f"! Age rating question {k} not in the API: answer it in App Store Connect.")
    patch("ageRatingDeclarations", age["id"], diff(age["attributes"], known), "Age rating")


def version():
    vs, _ = get_all(f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS")
    v = next((x for x in vs if x["attributes"].get("appStoreState") in EDITABLE
              or x["attributes"].get("appVersionState") in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                                             "REJECTED", "METADATA_REJECTED"}), None)
    if not v:
        summary.append("! No editable iOS version: App Store Connect → + Version first; version text skipped.")
        return
    vid, vname = v["id"], v["attributes"]["versionString"]
    wanted = {"description": "\n".join(L["description"]), "keywords": L["keywords"],
              "promotionalText": L["promotionalText"], "supportUrl": L["supportUrl"], "marketingUrl": L["marketingUrl"]}
    locs, _ = get_all(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    loc = next((x for x in locs if x["attributes"]["locale"] == LOC), None)
    if loc:
        patch("appStoreVersionLocalizations", loc["id"], diff(loc["attributes"], wanted), f"Version {vname} {LOC}")
    else:
        create("appStoreVersionLocalizations", {"locale": LOC, **wanted},
               {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}, f"Version {vname} {LOC}")

    r = L["review"]
    wanted = {"contactFirstName": r["contactFirstName"], "contactLastName": r["contactLastName"],
              "contactEmail": r["contactEmail"], "contactPhone": os.environ.get("REVIEW_CONTACT_PHONE") or None,
              "demoAccountRequired": r["demoAccountRequired"],
              "demoAccountName": os.environ.get("REVIEW_DEMO_EMAIL") or None,
              "demoAccountPassword": os.environ.get("REVIEW_DEMO_PASSWORD") or None,
              "notes": "\n".join(r["notes"])}
    for k in ("contactPhone", "demoAccountName", "demoAccountPassword"):
        if not wanted[k]:
            summary.append(f"! Secret for {k} not set: fill it in App Store Connect or add the secret.")
    detail = (call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail", allow404=True) or {}).get("data")
    if detail:
        cur = dict(detail["attributes"], demoAccountPassword=None)  # never read back; always resend when set
        patch("appStoreReviewDetails", detail["id"], diff(cur, wanted), "App Review information")
    else:
        create("appStoreReviewDetails", {k: v for k, v in wanted.items() if v is not None},
               {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}, "App Review information")


if __name__ == "__main__":
    print(f"{'APPLY' if APPLY else 'DRY RUN'}: listing for app {APP}")
    app_info()
    version()
    print("\n".join(summary))
    print("By hand: App Privacy labels (docs/app-store-review.md), screenshots.")
