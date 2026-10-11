"""Create the MonkeyWorkout Pro auto-renewable subscriptions in App Store Connect.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8), APP_ID,
     APPLY ("true" to write; anything else = dry run, GET requests only),
     NOTIFICATION_URLS ("true" to set the App Store Server Notifications V2 URLs).

Idempotent: every object is looked up first and only created when missing; nothing is deleted
and nothing existing is modified, except the app's subscription status URLs.
  - Subscription group "MonkeyWorkout Pro" + en-US group localization.
  - Subscriptions yearly / monthly / weekly (CHF 60 / 6 / 2) + en-US localizations.
  - Prices: CHE base price point with the exact CHF amount, plus Apple's equalized price
    in every other territory.
  - Availability in all priced territories (and new territories).
  - Introductory offer: 1-week free trial in every priced territory.
Requires the Paid Apps agreement (App Store Connect > Business) to be active.
"""
import base64, json, os, sys, time, urllib.error, urllib.request

import jwt  # PyJWT[crypto]

API = "https://api.appstoreconnect.apple.com"
APP = os.environ["APP_ID"]
APPLY = os.environ.get("APPLY", "false").lower() == "true"
NOTIFY = os.environ.get("NOTIFICATION_URLS", "true").lower() == "true"
BASE = "CHE"
GROUP = "MonkeyWorkout Pro"
AGREEMENT = "Sign the Paid Apps agreement and add banking/tax in App Store Connect → Business first."
PRODUCTS = [  # productId, name, period, groupLevel, CHF price, en-US description (<= 55 chars)
    ("monkeyworkout.pro.yearly", "Pro Yearly", "ONE_YEAR", 1, "60.00", "All MonkeyWorkout Pro features, billed yearly."),
    ("monkeyworkout.pro.monthly", "Pro Monthly", "ONE_MONTH", 2, "6.00", "All MonkeyWorkout Pro features, billed monthly."),
    ("monkeyworkout.pro.weekly", "Pro Weekly", "ONE_WEEK", 3, "2.00", "All MonkeyWorkout Pro features, billed weekly."),
]
NOTIFY_URLS = {
    "subscriptionStatusUrl": "https://workout.monkeygrade.cloud/v1/app-store/notifications",
    "subscriptionStatusUrlVersion": "V2",
    "subscriptionStatusUrlForSandbox": "https://workout-staging.monkeygrade.cloud/v1/app-store/notifications",
    "subscriptionStatusUrlVersionForSandbox": "V2",
}
_tok = {"exp": 0, "jwt": ""}
summary = []


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
            if e.code == 403 and ("agreement" in text.lower() or "subscriptionGroups" in path):
                sys.exit(AGREEMENT)
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


def create(kind: str, attributes: dict, relationships: dict, label: str):
    """POST /v1/{kind} when APPLY, else just report it. Returns the new resource (or None in dry run)."""
    summary.append(("create" if APPLY else "would create") + f": {label}")
    print(f"  {'CREATE' if APPLY else 'WOULD CREATE'} {label}")
    if not APPLY:
        return None
    rels = {k: {"data": v} for k, v in relationships.items()}
    return call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": attributes, "relationships": rels}})["data"]


def ref(kind: str, id_: str) -> dict:
    return {"type": kind, "id": id_}


def territory_of(obj: dict) -> str:
    """Territory id from relationships (requires include=territory), else from the encoded price point id."""
    rel = ((obj.get("relationships") or {}).get("territory") or {}).get("data")
    if rel:
        return rel["id"]
    raw = obj["id"] + "=" * (-len(obj["id"]) % 4)
    return json.loads(base64.urlsafe_b64decode(raw))["t"]


def base_price_point(sub_id: str, price: str) -> str:
    points, _ = get_all(f"/v1/subscriptions/{sub_id}/pricePoints?filter[territory]={BASE}")
    for p in points:
        if p["attributes"]["customerPrice"] == price:
            return p["id"]
    want = float(price)
    near = sorted({p["attributes"]["customerPrice"] for p in points}, key=lambda v: abs(float(v) - want))[:6]
    sys.exit(f"No {BASE} price point at exactly CHF {price}. Nearest: {', '.join(sorted(near, key=float))}")


def ensure_subscription(group_id, product_id, name, period, level, price, description, existing):
    print(f"\n{product_id} ({name}, {period}, CHF {price})")
    sub = existing.get(product_id)
    if not sub:
        sub = create("subscriptions", {"name": name, "productId": product_id, "subscriptionPeriod": period,
                                       "groupLevel": level, "familySharable": False},
                     {"group": ref("subscriptionGroups", group_id)} if group_id else {}, f"subscription {product_id}")
        if not sub:
            print(f"  (dry run: localization, CHF {price} prices, availability and free trial would follow)")
            return
    else:
        print(f"  exists ({sub['id']}, state {sub['attributes'].get('state')})")
    sid = sub["id"]

    locs, _ = get_all(f"/v1/subscriptions/{sid}/subscriptionLocalizations")
    if not any(l["attributes"]["locale"] == "en-US" for l in locs):
        create("subscriptionLocalizations", {"locale": "en-US", "name": GROUP, "description": description},
               {"subscription": ref("subscriptions", sid)}, f"{product_id} en-US localization")

    # Price points: exact CHF base price + Apple's equalized price for each other territory.
    pp = base_price_point(sid, price)
    eq, _ = get_all(f"/v1/subscriptionPricePoints/{pp}/equalizations?include=territory")
    points = {BASE: pp, **{territory_of(p): p["id"] for p in eq}}
    print(f"  price point {BASE} {price} + {len(points) - 1} equalized territories")

    # Availability before prices/offers, so territories are open for sale.
    avail = call("GET", f"/v1/subscriptions/{sid}/subscriptionAvailability", allow404=True)
    if avail and avail.get("data"):
        print("  availability exists")
    else:
        create("subscriptionAvailabilities", {"availableInNewTerritories": True},
               {"subscription": ref("subscriptions", sid),
                "availableTerritories": [ref("territories", t) for t in sorted(points)]},
               f"{product_id} availability in {len(points)} territories")

    prices, _ = get_all(f"/v1/subscriptions/{sid}/prices?include=territory")
    priced = {territory_of(p) for p in prices}
    missing = [t for t in sorted(points, key=lambda t: t != BASE) if t not in priced]  # base territory first
    print(f"  prices: {len(priced)} existing, {len(missing)} missing")
    for t in missing:
        create("subscriptionPrices", {"preserveCurrentPrice": False},
               {"subscription": ref("subscriptions", sid), "subscriptionPricePoint": ref("subscriptionPricePoints", points[t]),
                "territory": ref("territories", t)}, f"{product_id} price {t}")

    offers, _ = get_all(f"/v1/subscriptions/{sid}/introductoryOffers?include=territory")
    offered = {territory_of(o) for o in offers if (o.get("relationships") or {}).get("territory", {}).get("data")}
    todo = [t for t in sorted(points) if t not in offered]
    print(f"  intro offers: {len(offered)} existing, {len(todo)} missing")
    for t in todo:
        create("subscriptionIntroductoryOffers", {"duration": "ONE_WEEK", "offerMode": "FREE_TRIAL", "numberOfPeriods": 1},
               {"subscription": ref("subscriptions", sid), "territory": ref("territories", t)},
               f"{product_id} 1-week free trial {t}")


print(f"App {APP} — {'APPLY' if APPLY else 'DRY RUN (read-only)'}")

groups, _ = get_all(f"/v1/apps/{APP}/subscriptionGroups")
group = next((g for g in groups if g["attributes"]["referenceName"] == GROUP), None)
print(f"\nSubscription group {GROUP!r}: " + (f"exists ({group['id']})" if group else "missing"))
if not group:
    group = create("subscriptionGroups", {"referenceName": GROUP}, {"app": ref("apps", APP)}, f"subscription group {GROUP!r}")
gid = group["id"] if group else None

existing = {}
if gid:
    glocs, _ = get_all(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations")
    if not any(l["attributes"]["locale"] == "en-US" for l in glocs):
        create("subscriptionGroupLocalizations", {"locale": "en-US", "name": GROUP},
               {"subscriptionGroup": ref("subscriptionGroups", gid)}, "group en-US localization")
    subs, _ = get_all(f"/v1/subscriptionGroups/{gid}/subscriptions")
    existing = {s["attributes"]["productId"]: s for s in subs}
elif not APPLY:
    print("  (dry run: group localization would follow)")

for product in PRODUCTS:
    ensure_subscription(gid, *product, existing)

if NOTIFY:
    attrs = call("GET", f"/v1/apps/{APP}?fields[apps]=" + ",".join(NOTIFY_URLS))["data"]["attributes"]
    print("\nServer notification URLs:")
    for k, v in NOTIFY_URLS.items():
        print(f"  {k}: {attrs.get(k)!r}" + ("" if attrs.get(k) == v else f" -> {v!r}"))
    diff = {k: v for k, v in NOTIFY_URLS.items() if attrs.get(k) != v}
    if diff:
        summary.append(("update" if APPLY else "would update") + f": app notification URLs ({', '.join(diff)})")
        if APPLY:
            call("PATCH", f"/v1/apps/{APP}", {"data": {"type": "apps", "id": APP, "attributes": diff}})

print(f"\nSummary ({'applied' if APPLY else 'dry run'}): " + ("nothing to do" if not summary else f"{len(summary)} change(s)"))
counts = {}
for line in summary:
    key = line.rsplit(" ", 1)[0] if (" price " in line or "free trial" in line) else line
    counts[key] = counts.get(key, 0) + 1
for key, n in counts.items():
    print(f"  {key}" + (f" × {n} territories" if n > 1 else ""))
