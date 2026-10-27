#!/usr/bin/env python3
"""Build data/places.js (Local Tips directory) from tools/places_data.py plus the coffee rows in data/restaurants.js.
Geocodes with OpenStreetMap Nominatim; driving miles/minutes from the public OSRM demo router (approximate, no traffic).
Cache: tools/places-geocache.json. Walkable = straight-line * 1.25 <= 0.8 mile (estimate). Run from the repo root."""
import json, math, os, sys, time, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from places_data import P, FAQ, C
from restaurants_data import HOTELS
CACHE = os.path.join(HERE, "places-geocache.json")
cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {"geo": {}, "route": {}}
old = json.load(open(os.path.join(HERE, "restaurants-geocache.json")))
UA = "HotelHQ-staff-portal/1.0 (local directory build)"
def get(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=30))
# Nominatim-friendly fallbacks for addresses it cannot resolve (approximate pin = the named landmark).
GEO_FIX = {
 "3601 Highway 100 S, St. Louis Park, MN 55416": "3601 Highway 100 South, St. Louis Park",
 "330 E Broadway, Ste E330, Bloomington, MN 55425": "Mall of America, Bloomington",
 "1000 NW Court, Bloomington, MN 55425": "Mall of America, Bloomington",

 "2555 W 79th St, Bloomington, MN 55431": "Southtown Center, Bloomington",
 "5525 Cedar Lake Rd S, St. Louis Park, MN 55416": "Life Time St. Louis Park",
 "Minneapolis-Saint Paul International Airport Terminal 1": "Minneapolis–Saint Paul International Airport",
 "Minneapolis-Saint Paul International Airport Terminal 2": "Terminal 2 Humphrey",
 "Mall of America Transit Station, Bloomington": "Mall of America, Bloomington",
 "1650 Park Place Blvd, Ste 103, St. Louis Park, MN 55416": "Park Place Boulevard, St. Louis Park",
 "7817 Southtown Center, Ste 208, Bloomington, MN 55431": "Southtown Center, Bloomington",
 "5100 Center Ct, Bloomington, MN 55425": "Mall of America, Bloomington",
 "5120 Center Ct, Bloomington, MN 55425": "Mall of America, Bloomington",
 "101 Snelling Lake Rd, St. Paul, MN 55111": "Historic Fort Snelling",
 "The Armory, Minneapolis": "Minneapolis Armory",
 "4000 SW Court, Bloomington, MN 55425": "Mall of America, Bloomington"
}
def geocode(q):
    if q in cache["geo"]: return cache["geo"][q]
    if q in old["geo"]: cache["geo"][q] = old["geo"][q]; return old["geo"][q]
    FIX = GEO_FIX
    cands = ([FIX[q]] if q in FIX else []) + [q, q.replace(" Blvd", " Boulevard").replace(" Ave ", " Avenue ").replace(" St,", " Street,"), q.split(",", 1)[0].split(" Ste")[0] + "," + q.split(",", 1)[-1]]
    res = None
    for c in cands:
        time.sleep(1.1)
        j = get("https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us&q=" + urllib.parse.quote(c))
        if j: res = [float(j[0]["lat"]), float(j[0]["lon"]), c]; break
    cache["geo"][q] = res; json.dump(cache, open(CACHE, "w"), indent=1); return res
def hav(a, b):
    R = 3958.8; p1, p2 = math.radians(a[0]), math.radians(b[0]); dl = math.radians(b[1]-a[1]); dp = p2-p1
    return 2*R*math.asin(math.sqrt(math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2))
def route(a, b):
    k = "%.5f,%.5f>%.5f,%.5f" % (a[0], a[1], b[0], b[1])
    if k in cache["route"]: return cache["route"][k]
    if k in old["route"]: return old["route"][k]
    time.sleep(0.3)
    r = get("https://router.project-osrm.org/route/v1/driving/%f,%f;%f,%f?overview=false" % (a[1], a[0], b[1], b[0]))["routes"][0]
    cache["route"][k] = [r["distance"], r["duration"]]; json.dump(cache, open(CACHE, "w"), indent=1); return cache["route"][k]
hot = {k: geocode(h["addr"]) for k, h in HOTELS.items()}
HOT_OF = {"gv": ["MSPWE"], "bl": ["MSPAM", "MSPMS"], "all": ["MSPWE", "MSPAM", "MSPMS"]}
rows = [dict(id=r[0], area=r[1], cat=r[2], name=r[3], addr=r[4], phone=r[5], web=r[6], hours=r[7], why=[r[8], r[9]], src=r[10], tags=r[11], note=r[12], geo=r[13]) for r in P]
# Coffee: reuse the verified coffee rows from the restaurant guide (same sources/date).
s = open(os.path.join(HERE, "..", "data", "restaurants.js"), encoding="utf-8").read()
R = json.loads(s.split("window.RESTAURANTS=")[1].strip().rstrip(";"))
for x in R:
    if x["cu"] == "coffee":
        rows.append(dict(id="c-" + x["id"], area=x["area"], cat="coffee", name=x["name"], addr=x["addr"], phone=x["phone"], web=x["web"], hours=x["hours"], why=x["why"], src=x["src"], tags=(["moa"] if x.get("moa") else []), note=x.get("note", ""), geo="",
                         _r=x))
out = []
for r in rows:
    g = geocode(r["geo"] or r["addr"]) if not r.get("_r") else [r["_r"]["lat"], r["_r"]["lon"]]
    d, w = {}, {}
    if not g: print("NO GEO (distance left blank)", r["id"], r["geo"] or r["addr"])
    for k in (HOT_OF[r["area"]] if g else []):
        if r.get("_r") and k in r["_r"]["d"]:
            d[k] = r["_r"]["d"][k]; w[k] = r["_r"]["walk"].get(k, 0); continue
        m, sec = route(hot[k][:2], g[:2]); d[k] = [round(m/1609.344, 1), max(1, int(round(sec/60.0)))]
        w[k] = 1 if hav(hot[k][:2], g[:2])*1.25 <= 0.8 else 0
    x = r.get("_r") or {}
    q = urllib.parse.quote_plus((r["name"] + " " + (r["addr"] or r["geo"])).strip())
    out.append(dict(id=r["id"], area=r["area"], cat=r["cat"], name=r["name"], addr=r["addr"], phone=r["phone"], web=r["web"], hours=r["hours"],
        tags=r["tags"], why=r["why"], src=r["src"], note=r["note"], verified=C, d=d, walk=w,
        google_rating=x.get("google_rating", ""), google_review_count=x.get("google_review_count", ""),
        yelp_rating=x.get("yelp_rating", ""), yelp_review_count=x.get("yelp_review_count", ""), yelp_url=x.get("yelp_url", ""),
        ratings_as_of=C, google_maps_url="https://www.google.com/maps/search/?api=1&query=" + q))
hdr = ("/* HotelHQ Local Tips directory. Built by tools/build-places.py from tools/places_data.py (+ coffee rows of data/restaurants.js).\n"
 " * Read from the page in `src` on 2026-10-27; blank = not verified (never guessed). Hours change: call ahead.\n"
 " * d.<HOTEL> = [driving miles, minutes] without traffic (OSRM); walk.<HOTEL> = 1 if about a 15-minute walk (estimate).\n"
 " * Ratings: only values seen on a page/search result (as of ratings_as_of); blank otherwise. */\n")
js = hdr + "window.PLACES=" + json.dumps(out, ensure_ascii=False, separators=(",", ":")).replace("},{", "},\n{") + ";\n"
js += "window.PLACES_FAQ=" + json.dumps({k: [list(f) for f in v] for k, v in FAQ.items()}, ensure_ascii=False) + ";\n"
open(os.path.join(HERE, "..", "data", "places.js"), "w", encoding="utf-8").write(js)
print(len(out), "places")
