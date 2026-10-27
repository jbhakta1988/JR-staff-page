#!/usr/bin/env python3
"""Build data/restaurants.js from tools/restaurants_data.py.
Geocodes with OpenStreetMap Nominatim and measures driving distance/time with the public OSRM demo router
(approximate, no live traffic). Results are cached in tools/restaurants-geocache.json so rebuilds are offline.
Walkable = straight-line * 1.25 <= 0.8 mile (about a 15-minute walk); it is an estimate, not a verified route."""
import json, math, os, sys, time, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from restaurants_data import ROWS, HOTELS
CACHE = os.path.join(HERE, "restaurants-geocache.json")
cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {"geo": {}, "route": {}}
UA = "HotelHQ-staff-portal/1.0 (jbhakta1988@users.noreply.github.com)"
MOA_ADDR = "Mall of America, 60 E Broadway, Bloomington, MN 55425"
def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return json.load(urllib.request.urlopen(req, timeout=30))
def geocode(q):
    if q in cache["geo"]: return cache["geo"][q]
    qs = [q, q.split(",", 1)[0] + "," + ",".join(q.split(",")[1:]).replace(" Blvd", " Boulevard")]
    for cand in qs + [", ".join(q.split(",")[1:])]:
        time.sleep(1.1)
        j = get("https://nominatim.openstreetmap.org/search?format=json&limit=1&q=" + urllib.parse.quote(cand))
        if j:
            cache["geo"][q] = [float(j[0]["lat"]), float(j[0]["lon"]), cand]; break
    else: cache["geo"][q] = None
    json.dump(cache, open(CACHE, "w"), indent=1); return cache["geo"][q]
def hav(a, b):
    R = 3958.8; p1, p2 = math.radians(a[0]), math.radians(b[0]); dl = math.radians(b[1]-a[1]); dp = p2-p1
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*R*math.asin(math.sqrt(h))
def route(a, b):
    k = "%.5f,%.5f>%.5f,%.5f" % (a[0], a[1], b[0], b[1])
    if k in cache["route"]: return cache["route"][k]
    time.sleep(0.3)
    j = get("https://router.project-osrm.org/route/v1/driving/%f,%f;%f,%f?overview=false" % (a[1], a[0], b[1], b[0]))
    r = j["routes"][0]; cache["route"][k] = [r["distance"], r["duration"]]
    json.dump(cache, open(CACHE, "w"), indent=1); return cache["route"][k]
hot = {}
for k, h in HOTELS.items():
    g = geocode(h["addr"]); hot[k] = g; print(k, g)
# Dropped from the guide: too far from the hotels to be useful for walk-up/driver recs (6+ miles).
DROP = {"bl-5120", "bl-perkup"}
ROWS = [r for r in ROWS if r["id"] not in DROP]
out = []
def late(h):
    if h == "24h": return True
    for seg in h.split(";"):
        for rng in seg.strip().split(" ", 1)[-1].split(","):
            try: o, c = rng.strip().split("-")
            except ValueError: continue
            oh = int(o.split(":")[0]); ch = int(c.split(":")[0]) + int(c.split(":")[1])/60
            if ch <= oh or ch > 22.0: return True
    return False
for r in ROWS:
    g = geocode(MOA_ADDR if r["moa"] else r["addr"]) 
    if not g: print("NO GEO", r["name"]); continue
    d = {}
    for k, hg in hot.items():
        if (k == "MSPWE") != (r["area"] == "gv"): continue
        m, s = route(hg[:2], g[:2]); line = hav(hg[:2], g[:2])
        d[k] = [round(m/1609.344, 1), max(1, int(round(s/60.0))), 1 if line*1.25 <= 0.8 else 0]
    t = list(r["tags"])
    if r["hours"] and late(r["hours"]) and "late" not in t: t.append("late")
    if r["hours"] and "late" in t and not late(r["hours"]) and r["id"] != "gv-papacorazon" and r["id"] != "gv-chipotle": t.remove("late")
    if r["hours"] and "Su" in r["hours"] or r["hours"] == "24h":
        if "sun" not in t: t.append("sun")
    if r["moa"] and "moa" not in t: t.append("moa")
    q = urllib.parse.quote_plus(r["name"] + " " + r["addr"])
    rec = dict(id=r["id"], area=r["area"], name=r["name"], cu=r["cu"], price=r["price"], addr=r["addr"], phone=r["phone"], web=r["web"],
        hours=r["hours"], takeout=bool(r["take"]), deliv=r["deliv"], kid=r["kid"], veg=r["veg"], gf=r["gf"], tags=t, moa=r["moa"], walk=None,
        d=d, why=r["why"], src=r["src"], verified="2026-10-27",
        google_rating=r["gr"], google_review_count=r["gn"], google_src=r["gsrc"], google_asof=(r["gasof"] or ("2026-10-27" if r["gr"] != "" else "")),
        yelp_rating=r["yr"], yelp_review_count=r["yn"], yelp_src=r["ysrc"], yelp_url=r["yurl"],
        google_maps_url="https://www.google.com/maps/search/?api=1&query=" + q, ratings_as_of="2026-10-27", note=r["note"],
        lat=round(g[0], 5), lon=round(g[1], 5))
    rec["walk"] = {k: v[2] for k, v in d.items()}
    for k in d: d[k] = d[k][:2]
    out.append(rec)
hdr = ("/* HotelHQ restaurant guide. Built by tools/build-restaurants.py from tools/restaurants_data.py.\n"
 " * Values were read from fetched pages/search results on 2026-10-27; blank = not verified. Hours can change: call ahead.\n"
 " * Ratings change: Yelp/Google values are as seen on that date (google_asof/yelp_src show the source). Distances are approximate\n"
 " * driving miles/minutes without traffic (OSRM) from each hotel: d.MSPWE / d.MSPAM / d.MSPMS = [miles, minutes].\n"
 " * kid/veg/gf/price/phone/hours are only filled where a page showed them. tags[] are editorial good-for suggestions (venue type + listings);\n * takeout=true only where a listing showed takeout. Dropped as too far (6+ mi): 5120 Restaurant, Perk Up Kitchen. D'Amico & Sons dropped: permanently closed. */\n")
js = hdr + "window.RESTAURANT_HOTELS=" + json.dumps({k: {"name": v["name"], "addr": v["addr"], "src": v["src"]} for k, v in HOTELS.items()}, ensure_ascii=False) + ";\n"
js += "window.RESTAURANTS=" + json.dumps(out, ensure_ascii=False, separators=(",", ":")).replace("},{", "},\n{") + ";\n"
open(os.path.join(HERE, "..", "data", "restaurants.js"), "w").write(js)
print(len(out), "records")
