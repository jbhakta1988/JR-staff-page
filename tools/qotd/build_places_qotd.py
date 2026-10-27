"""QOTD batch: local guest-asks (pharmacy, ER, transit, gas, pets, gyms...) built ONLY from data/places.js (verified 2026-10-27).
Run from tools/qotd:  python3 build_places_qotd.py  -> appends rows to data/qotd.json and writes supabase/migrations/20261027_qotd_local_places.sql
Ratings are NOT used. Distances are approximate driving miles (OSRM, no traffic). Restore data/qotd.json before re-running."""
import json, random, re, sys
sys.path.insert(0, '.')
from qa import run
ROOT = '../../'
raw = open(ROOT + 'data/places.js', encoding='utf-8').read()
DATA = json.loads(raw.split('window.PLACES=')[1].split(';\nwindow.PLACES_FAQ=')[0])
BR = {"MSPAM": "Hilton", "MSPMS": "Marriott", "MSPWE": "IHG"}
AREA = {"MSPWE": "gv", "MSPAM": "bl", "MSPMS": "bl"}
def hh(t, es=False):
    h, m = map(int, t.split(":")); h %= 24
    if h == 0 and m == 0: return "medianoche" if es else "midnight"
    return ("%d" % (h % 12 or 12)) + (":%02d" % m if m else "") + (" a.m." if h < 12 else " p.m.")
def htxt(h, es=False):
    if h == "24h": return "24 horas" if es else "24 hours"
    m = re.match(r"^Mo-Su (\d\d:\d\d)-(\d\d:\d\d)$", h)
    if m: return ("todos los días de %s a %s" if es else "daily %s to %s") % (hh(m.group(1), es), hh(m.group(2), es))
    return h
def nm(x): return (x["name"], x["name"])
def mi(x, h): return "%.1f miles" % x["d"][h][0]
def build(hid):
    R = [x for x in DATA if x["area"] in (AREA[hid], "all") and x["d"].get(hid)]
    rnd = random.Random(sum(map(ord, hid)) * 11 + 5)
    D = lambda x: x["d"][hid][0]
    FD = ["front_desk", "night_audit"]; DR = FD + ([] if hid == "MSPWE" else ["driver"])
    Q = []
    def pick(pool, n, avoid=()):
        pool = [x for x in pool if x["id"] not in avoid]; rnd.shuffle(pool); return pool[:n]
    def add(roles, diff, qe, qs, g, bs, ee, es, src):
        bs = [b for b in bs if b[0] != g[0]]
        if len(bs) < 3 or len(set(b[0] for b in bs)) < 3: return
        Q.append(dict(roles=roles, diff=diff, qe=qe, qs=qs, oe=[g[0]] + [b[0] for b in bs], os=[g[1]] + [b[1] for b in bs], ee=ee, es=es, src=src))
    cat = lambda c: [x for x in R if x["cat"] == c]
    near = lambda L: sorted(L, key=D)[0] if L else None
    # 1 24-hour pharmacy
    p24 = near([x for x in cat("pharm") if x["hours"] == "24h"])
    if p24:
        g = p24; bs = pick([x for x in cat("pharm") if x["hours"] != "24h"], 3)
        add(FD, "med", "A guest needs a prescription filled at 2 a.m. Which pharmacy does our Local Directory list as open 24 hours?", "Un huésped necesita surtir una receta a las 2 a.m. ¿Qué farmacia aparece en nuestro Directorio local como abierta las 24 horas?",
            nm(g), [nm(b) for b in bs], f"{g['name']} at {g['addr']} is listed as 24 hours, about {mi(g,hid)} by car. Call {g['phone']} first; pharmacy-counter hours can differ from the store.",
            f"{g['name']} en {g['addr']} aparece abierta las 24 horas, a unas {mi(g,hid).replace('miles','millas')} en auto. Llama primero al {g['phone']}; el mostrador de farmacia puede tener otro horario.", g["src"])
    # 2 ER vs urgent care
    er = near([x for x in cat("med") if "er" in x["tags"]]); uc = [x for x in cat("med") if "uc" in x["tags"]]
    if er:
        bs = pick(uc, 3); bs += pick([x for x in cat("pharm")], 3 - len(bs))
        add(FD, "med", "A guest has chest pain late at night and their friend wants to drive them. Which of these is a 24-hour emergency department?", "Un huésped tiene dolor de pecho tarde en la noche y un amigo quiere llevarlo. ¿Cuál de estos es un departamento de emergencias 24 horas?",
            nm(er), [nm(b) for b in bs], f"{er['name']} is a 24-hour ER, about {mi(er,hid)} away. Urgent care clinics close at night. For chest pain, the safest advice is to call 911.",
            f"{er['name']} es una sala de emergencias 24 horas, a unas {mi(er,hid).replace('miles','millas')}. Las clínicas de urgencias cierran de noche. Ante dolor de pecho, lo más seguro es llamar al 911.", er["src"])
    # 3 closest urgent care
    if len(uc) >= 2:
        g = near(uc); bs = sorted([x for x in cat("med") if x["id"] != g["id"]], key=D)[:3]
        if all(D(b) > D(g) for b in bs):
            add(FD, "med", "A guest twisted an ankle and wants the closest walk-in clinic or hospital. Which of these is closest by car?", "Un huésped se torció el tobillo y quiere la clínica sin cita u hospital más cercano. ¿Cuál de estos está más cerca en auto?",
                nm(g), [nm(b) for b in bs], f"{g['name']} is about {mi(g,hid)} away, closer than the others. {('Its posted hours: '+htxt(g['hours'])+'.') if htxt(g['hours'])!=g['hours'] else 'Check its posted hours on the Directory card.'}", f"{g['name']} está a unas {mi(g,hid).replace('miles','millas')}, más cerca que los demás. {('Horario publicado: '+htxt(g['hours'],True)+'.') if htxt(g['hours'])!=g['hours'] else 'Revisa su horario en la tarjeta del Directorio.'}", g["src"])
    # 4 nearest 24h gas
    gs = sorted([x for x in cat("gas") if x["hours"] == "24h" and "ev" not in x["tags"]], key=D)
    if len(gs) >= 2:
        g = gs[0]; bs = gs[1:3] + pick([x for x in R if x["cat"] in ("venue", "attr") and D(x) > D(g)], 1)
        bs = [b for b in bs if D(b) > D(g)]
        add(DR, "easy", "A guest returning a rental car needs gas late at night. Which 24-hour station on our list is closest?", "Un huésped que devuelve un auto rentado necesita gasolina tarde en la noche. ¿Qué gasolinera 24 horas de nuestra lista está más cerca?",
            nm(g), [nm(b) for b in bs], f"{g['name']} is about {mi(g,hid)} away and listed as 24 hours.", f"{g['name']} está a unas {mi(g,hid).replace('miles','millas')} y aparece abierta las 24 horas.", g["src"])
    # 5 rail
    rail = [x for x in cat("transit") if "rail" in x["tags"] and "msp" not in x["tags"]]
    if rail:
        g = near(rail); bs = [x for x in DATA if x["cat"] == "transit" and x["id"] != g["id"] and "msp" not in x["tags"]][:3]
        bs += [x for x in DATA if x["cat"] == "venue"][:3 - len(bs)]
        add(DR, "easy", "A guest wants to ride the light rail. Which station is closest to our hotel?", "Un huésped quiere usar el tren ligero. ¿Qué estación está más cerca de nuestro hotel?",
            nm(g), [nm(b) for b in bs], f"{g['name']} is about {mi(g,hid)} by car. {g['why'][0]}", f"{g['name']} está a unas {mi(g,hid).replace('miles','millas')} en auto. {g['why'][1]}", g["src"])
    # 6 pet ER
    pe = near([x for x in cat("pet") if x["hours"] == "24h"])
    if pe:
        bs = pick([x for x in R if x["cat"] in ("pet", "med", "pharm") and x["id"] != pe["id"] and x["hours"] != "24h"], 3)
        add(FD, "med", "A guest's dog ate something toxic at 11 p.m. Which of these is a 24-hour animal emergency hospital?", "El perro de un huésped comió algo tóxico a las 11 p.m. ¿Cuál de estos es un hospital veterinario de emergencias 24 horas?",
            nm(pe), [nm(b) for b in bs], f"{pe['name']} is listed as 24 hours, about {mi(pe,hid)} away. Phone: {pe['phone']}.", f"{pe['name']} aparece abierto las 24 horas, a unas {mi(pe,hid).replace('miles','millas')}. Teléfono: {pe['phone']}.", pe["src"])
    # 7 24h gym
    gy = near([x for x in cat("gym") if x["hours"] == "24h"])
    if gy:
        bs = pick([x for x in cat("gym") if x["hours"] and x["hours"] != "24h"], 3)
        bs += pick([x for x in R if x["cat"] in ("laundry", "salon") and x["hours"] and x["hours"] != "24h"], 3 - len(bs))
        add(FD, "easy", "A guest on a night shift wants a workout at 3 a.m. Which of these is listed as open 24 hours?", "Un huésped que trabaja de noche quiere hacer ejercicio a las 3 a.m. ¿Cuál de estos aparece abierto las 24 horas?",
            nm(gy), [nm(b) for b in bs], f"{gy['name']} is listed as 24 hours (members; ask about guest passes). The others close overnight.", f"{gy['name']} aparece abierto las 24 horas (socios; pregunta por pases de invitado). Los demás cierran de noche.", gy["src"])
    # 8 late essentials
    sh = [x for x in R if x["cat"] in ("shop", "grocery") and x["hours"]]
    late = sorted(sh, key=lambda x: (x["hours"] != "24h", -int(re.findall(r"-(\d\d):", x["hours"])[0]) if re.findall(r"-(\d\d):", x["hours"]) else 0))
    if late:
        g = late[0]; gl = htxt(g["hours"]); gle = htxt(g["hours"], True)
        bs = [x for x in sh if x["id"] != g["id"] and x["hours"] != "24h" and re.findall(r"-(\d\d):", x["hours"]) and max(map(int, re.findall(r"-(\d\d):", x["hours"]))) < (24 if g["hours"] == "24h" else max(map(int, re.findall(r"-(\d\d):", g["hours"]))))][:3]
        add(DR, "med", "A guest forgot a phone charger and toiletries and it is 10:30 p.m. Which store on our list stays open latest?", "Un huésped olvidó su cargador y artículos de aseo y son las 10:30 p.m. ¿Qué tienda de nuestra lista abre hasta más tarde?",
            nm(g), [nm(b) for b in bs], f"{g['name']} posts: {gl}. The others close earlier. Hours can change, so call ahead.", f"{g['name']} publica: {gle}. Los demás cierran antes. Los horarios pueden cambiar, llama antes.", g["src"])
    # 9 nearest venue
    vs = sorted(cat("venue"), key=D)
    if len(vs) >= 4 and D(vs[0]) < D(vs[1]):
        g = vs[0]; bs = vs[-3:]
        add(DR, "med", "A guest asks which of these event venues is the shortest drive from our hotel.", "Un huésped pregunta cuál de estos recintos de eventos está a menor distancia en auto de nuestro hotel.",
            nm(g), [nm(b) for b in bs], f"{g['name']} is about {mi(g,hid)} away; the others are farther. Allow extra time on event nights.", f"{g['name']} está a unas {mi(g,hid).replace('miles','millas')}; los demás están más lejos. Calcula más tiempo en noches de eventos.", g["src"])
    # 10 nearest attraction / park
    at = sorted(cat("attr"), key=D)
    if len(at) >= 4 and D(at[0]) < D(at[-1]):
        g = at[0]; bs = [x for x in at[-3:] if D(x) > D(g)]
        add(FD, "easy", "A family wants the closest attraction or park from our hotel. Which of these is nearest?", "Una familia quiere la atracción o parque más cercano a nuestro hotel. ¿Cuál de estos está más cerca?",
            nm(g), [nm(b) for b in bs], f"{g['name']} is about {mi(g,hid)} away. {g['why'][0]}", f"{g['name']} está a unas {mi(g,hid).replace('miles','millas')}. {g['why'][1]}", g["src"])
    # 11 24h grocery / earliest coffee
    gr = near([x for x in cat("grocery") if x["hours"] == "24h"])
    if gr:
        bs = pick([x for x in R if x["cat"] in ("grocery", "coffee", "liquor") and x["hours"] and x["hours"] != "24h"], 3)
        add(FD, "easy", "A guest arriving at 1 a.m. wants groceries for their extended stay. Which store on our list is open 24 hours?", "Un huésped que llega a la 1 a.m. quiere comprar víveres para su estancia larga. ¿Qué tienda de nuestra lista abre las 24 horas?",
            nm(gr), [nm(b) for b in bs], f"{gr['name']} is listed as 24 hours, about {mi(gr,hid)} away.", f"{gr['name']} aparece abierta las 24 horas, a unas {mi(gr,hid).replace('miles','millas')}.", gr["src"])
    return Q
def fixp(t): return re.sub(r'\.\.(?!\.)', '.', t)
cands = []
for hid in ("MSPWE", "MSPAM", "MSPMS"):
    for q in build(hid):
        Q = q; roles = sorted(set(q["roles"]))
        cands.append(dict(hotel=hid, brand=BR[hid], roles=roles, kind="role", topic="local", topics=["hotel", "local", hid.lower()] + [r for r in roles if r == "driver"], difficulty=q["diff"],
                          qe=q["qe"], qs=q["qs"], oe=q["oe"], os=q["os"], c=0, ee=fixp(q["ee"]), es=fixp(q["es"]), src=q.get("src") or "", season=None, review_by="2027-04-26"))

bank = json.load(open(ROOT + 'data/qotd.json'))
ok, rej = run(cands, [x[4] for x in bank], scope=lambda x: x and x["hotel"])
random.seed(2711)
for x in ok:
    p = list(range(len(x["oe"]))); random.shuffle(p)
    x["oe"] = [x["oe"][i] for i in p]; x["os"] = [x["os"][i] for i in p]; x["c"] = p.index(0)
from collections import Counter
print("candidates", len(cands), "accepted", len(ok), "rejected", len(rej), Counter(x["hotel"] for x in ok))
for x, e in rej: print(" REJECT", x["hotel"], x["qe"][:70], "->", e)
q = lambda s: "null" if s is None else "'" + str(s).replace("'", "''") + "'"
arr = lambda a: "array[" + ",".join(q(v) for v in a) + "]::text[]"
js = lambda a: q(json.dumps(a, ensure_ascii=False)) + "::jsonb"
COLS = "brand,role_group,topic,question_en,question_es,options_en,options_es,correct_idx,explain_en,explain_es,source_url,roles,kind,difficulty,topics,hotel_id,season_start,season_end,review_by"
L = ["-- QOTD: local guest-asks built from data/places.js (verified 2026-10-27); review_by 2027-04-26"]
nl = max(x[0] for x in bank) + 1
for x in ok:
    L.append(f"insert into public.qotd_questions({COLS}) values (" + ",".join([q(x["brand"]), "'all'", q(x["topic"]), q(x["qe"]), q(x["qs"]), js(x["oe"]), js(x["os"]), str(x["c"]), q(x["ee"]), q(x["es"]), q(x["src"]), arr(x["roles"]), q(x["kind"]), q(x["difficulty"]), arr(x["topics"]), q(x["hotel"]), "null", "null", "'2027-04-26'::date"]) + ") on conflict (brand,role_group,question_en) do nothing;")
    bank.append([nl, x["brand"], "all", x["topic"], x["qe"], x["qs"], x["oe"], x["os"], x["c"], x["ee"], x["es"], x["src"], True, x["roles"], x["kind"], x["hotel"], None, "2027-04-26", x["difficulty"], x["topics"], None, 0]); nl += 1
open(ROOT + 'supabase/migrations/20261027_qotd_local_places.sql', 'w').write("\n".join(L) + "\n")
json.dump(bank, open(ROOT + 'data/qotd.json', 'w'), ensure_ascii=False, separators=(",", ":"))
print("bank", len(bank))
