"""QOTD batch: restaurant guest-asks built ONLY from data/restaurants.js (verified fields: hours, distance, address, phone, cuisine, walkable, inside-MOA).
Run from tools/qotd:  python3 build_rest.py   -> appends rows to data/qotd.json and writes supabase/migrations/20261027_qotd_restaurants.sql
Ratings are intentionally NOT used (they change). Distance/walkable are approximate (OSRM, no traffic)."""
import json, random, re, sys
sys.path.insert(0, '.')
from qa import run, norm
ROOT = '/workspace/repo/'
raw = open(ROOT + 'data/restaurants.js', encoding='utf-8').read()
DATA = json.loads(raw.split('window.RESTAURANTS=')[1].rstrip(';\n'))
BR = {"MSPAM": "Hilton", "MSPMS": "Marriott", "MSPWE": "IHG"}
AREA = {"MSPWE": "gv", "MSPAM": "bl", "MSPMS": "bl"}
ES_DAY = {"Mo": 0, "Tu": 1, "We": 2, "Th": 3, "Fr": 4, "Sa": 5, "Su": 6}
DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
def days_of(spec):
    p = spec.split("-"); a = DAYS.index(p[0]); b = DAYS.index(p[-1])
    return list(range(a, b + 1)) if a <= b else list(range(a, 7)) + list(range(0, b + 1))
def day_ranges(h, day):
    """[(open_h, close_h)] for day index (0=Mo); close can exceed 24 (after midnight)."""
    if not h: return None
    if h == "24h": return [(0, 24)]
    out = []
    for seg in h.split(";"):
        m = re.match(r"^\s*([A-Za-z]{2}(?:-[A-Za-z]{2})?)\s+(.+)$", seg)
        if not m or day not in days_of(m.group(1)): continue
        for r in m.group(2).split(","):
            o, c = r.strip().split("-"); oh = int(o[:2]) + int(o[3:]) / 60; ch = int(c[:2]) + int(c[3:]) / 60
            if ch <= oh: ch += 24
            out.append((oh, ch))
    return out
def close_on(x, d):
    r = day_ranges(x["hours"], d); return max(c for o, c in r) if r else None
def open_on(x, d):
    r = day_ranges(x["hours"], d); return min(o for o, c in r) if r else None
def phone_ok(x): return bool(x["phone"])
def name(x): return re.sub(r"\s*\((Mall of America.*?|West End|Golden Valley|Nicollet Ave|Lyndale|St\. Louis Park|JW Marriott|Lunds & Byerlys|South)\)", "", x["name"]).strip()
def fmt_mi(v): return ("%.1f" % v) + " miles"
def build(hid):
    rows = [x for x in DATA if x["area"] == AREA[hid] and x["d"].get(hid)]
    rnd = random.Random(sum(map(ord, hid)) * 7 + 3)
    Q = []
    def pick(pool, n, avoid=()):
        pool = [x for x in pool if x["id"] not in avoid]; rnd.shuffle(pool); return pool[:n]
    def add(key, roles, topic, diff, qe, qs, good, bad, ee, es, src, gname=None):
        """good/bad: (en, es) option tuples."""
        Q.append(dict(key=key, roles=roles, topic=topic, diff=diff, qe=qe, qs=qs, oe=[good[0]] + [b[0] for b in bad], os=[good[1]] + [b[1] for b in bad], ee=ee, es=es, src=src))
    FD = ["front_desk", "night_audit"]; DR = FD + ([] if hid == "MSPWE" else ["driver"]); BAR = FD + (["bartender"] if hid == "MSPMS" else [])
    nm = lambda x: (name(x), name(x))
    used = set()
    # A: late Friday sit-down
    for k, (lo, hi, var) in enumerate([(23, 21.6, "10:30 p.m. on a Friday"), (24, 22.1, "11 p.m. on a Saturday")]):
        d = 4 if k == 0 else 5
        good = [x for x in rows if (close_on(x, d) or 0) >= lo and x["id"] not in used and x["cu"] not in ("coffee",)]
        bad = [x for x in rows if close_on(x, d) is not None and close_on(x, d) <= hi]
        if good and len(bad) >= 3:
            g = pick(good, 1)[0]; bs = pick(bad, 3, {g["id"]}); used.add(g["id"])
            c = close_on(g, d) % 24; cs = "midnight" if c == 0 else ("%d a.m." % c if c < 12 and c else "%d p.m." % (c - 12 if c > 12 else c))
            ces = "medianoche" if c == 0 else ("%d a.m." % c if c < 12 and c else "%d p.m." % (c - 12 if c > 12 else c))
            add("late%d" % k, DR if k == 0 else BAR, "restaurants", "med",
                (f"A guest arrives at {var} and wants a sit-down meal. Which of these posts a Friday close of 11 p.m. or later?" if d == 4 else "A theater group gets back on a Saturday night and wants a hot dinner. Which of these stays open until midnight or later that night?"),
                (f"Un huésped llega a las 10:30 p.m. un viernes y quiere comer sentado. ¿Cuál de estos publica un cierre de las 11 p.m. o más tarde el viernes?" if d == 4 else "Un grupo regresa del teatro un sábado por la noche y quiere una cena caliente. ¿Cuál de estos sigue abierto hasta medianoche o más tarde ese día?"),
                nm(g), [nm(b) for b in bs],
                f"{name(g)} posts a {'Friday' if d == 4 else 'Saturday'} close around {cs}; the others close earlier. Hours can change, so call ahead.",
                f"{name(g)} publica un cierre {'el viernes' if d == 4 else 'el sábado'} alrededor de {ces}; los demás cierran antes. Los horarios pueden cambiar, así que llama antes.", g["src"])
    # K: after the bar closes (1 a.m.+ Friday)
    good = [x for x in rows if (close_on(x, 4) or 0) >= 25]; bad = [x for x in rows if close_on(x, 4) is not None and close_on(x, 4) <= 23]
    if good and len(bad) >= 3:
        g = pick(good, 1, used)[0] if [y for y in good if y["id"] not in used] else good[0]; bs = pick(bad, 3, {g["id"]}); used.add(g["id"])
        add("after", BAR, "restaurants", "med", "Bar guests ask where to keep the night going after our lounge closes on a Friday. Which of these posts a Friday close of 1 a.m. or later?",
            "Los huéspedes del bar preguntan a dónde seguir la noche después de que cierra nuestro lounge un viernes. ¿Cuál de estos publica un cierre de la 1 a.m. o más tarde el viernes?",
            nm(g), [nm(b) for b in bs], f"{name(g)} lists a Friday close at {('%d a.m.' % (close_on(g,4)-24))}; confirm by phone before sending anyone.",
            f"{name(g)} indica cierre el viernes a la {('%d a.m.' % (close_on(g,4)-24))}; confirma por teléfono antes de enviar a alguien.", g["src"])
    # B: early breakfast
    good = [x for x in rows if (open_on(x, 0) is not None and open_on(x, 0) <= 6.5)]; bad = [x for x in rows if open_on(x, 0) is not None and open_on(x, 0) >= 10.5]
    if good and len(bad) >= 3:
        g = pick(good, 1)[0]; bs = pick(bad, 3, {g["id"]}); o = open_on(g, 0)
        os_ = "%d:%02d a.m." % (int(o), round((o % 1) * 60)) if o else "12 a.m."
        add("early", DR, "restaurants", "med", "A guest has an early flight and wants breakfast at 7 a.m. on a weekday. Which of these is already open?",
            "Un huésped tiene un vuelo temprano y quiere desayunar a las 7 a.m. entre semana. ¿Cuál de estos ya está abierto?", nm(g), [nm(b) for b in bs],
            (f"{name(g)} posts a weekday opening of {os_}. The others open at 10:30 a.m. or later." if o else f"{name(g)} lists 24-hour service. The others open at 10:30 a.m. or later."), (f"{name(g)} abre entre semana a las {os_}. Los demás abren a las 10:30 a.m. o después." if o else f"{name(g)} indica servicio las 24 horas. Los demás abren a las 10:30 a.m. o después."), g["src"])
    # C: closest / farthest by car
    srt = sorted(rows, key=lambda x: x["d"][hid][0])
    def spread(sel, rev=False):
        for _ in range(200):
            s = rnd.sample(rows, 4); s.sort(key=lambda x: x["d"][hid][0], reverse=rev)
            mi = [x["d"][hid][0] for x in s]
            if abs(mi[0] - mi[1]) >= 0.7 and len({round(v) for v in mi}) == 4: return s
    s = spread(0)
    if s:
        add("near", DR, "restaurants", "easy", "A guest wants the shortest drive to dinner. Which of these restaurants is closest to our hotel by car?", "Un huésped quiere la menor distancia en auto para cenar. ¿Cuál de estos restaurantes está más cerca de nuestro hotel en auto?",
            nm(s[0]), [nm(x) for x in s[1:]], f"{name(s[0])} is about {fmt_mi(s[0]['d'][hid][0])} ({s[0]['d'][hid][1]} min) from the hotel; the others are farther. Distances are approximate, no traffic.",
            f"{name(s[0])} está a unas {fmt_mi(s[0]['d'][hid][0]).replace('miles','millas')} ({s[0]['d'][hid][1]} min) del hotel; los demás están más lejos. Distancias aproximadas, sin tráfico.", s[0]["src"])
    s = spread(1, True)
    if s:
        add("far", DR, "restaurants", "med", "A driver is asked which of these restaurants is the longest drive from our hotel. Which one?", "Preguntan al conductor cuál de estos restaurantes queda más lejos en auto desde nuestro hotel. ¿Cuál?",
            nm(s[0]), [nm(x) for x in s[1:]], f"{name(s[0])} is about {fmt_mi(s[0]['d'][hid][0])} away (about {s[0]['d'][hid][1]} min). Distances are approximate, no traffic.",
            f"{name(s[0])} está a unas {fmt_mi(s[0]['d'][hid][0]).replace('miles','millas')} (unos {s[0]['d'][hid][1]} min). Distancias aproximadas, sin tráfico.", s[0]["src"])
    # D: numeric miles
    cand = [x for x in rows if 1.5 <= x["d"][hid][0] <= 5 and x["id"] not in used]
    for k, g in enumerate(pick(cand, 2)):
        mi = g["d"][hid][0]; opts = [round(mi, 1), round(mi * 0.3 + 0.2, 1), round(mi * 2.2, 1), round(mi * 3.5, 1)]
        if len({round(v) for v in opts}) < 4: continue
        add("dist%d" % k, DR if k == 0 else FD, "restaurants", "med", f"About how far is {name(g)} from our hotel by car?", f"¿Aproximadamente a qué distancia en auto está {name(g)} de nuestro hotel?",
            (fmt_mi(opts[0]), fmt_mi(opts[0]).replace("miles", "millas")), [(fmt_mi(v), fmt_mi(v).replace("miles", "millas")) for v in opts[1:]],
            f"{name(g)} is about {fmt_mi(mi)} (about {g['d'][hid][1]} min) by car, no traffic. Address: {g['addr']}.", f"{name(g)} está a unas {fmt_mi(mi).replace('miles','millas')} (unos {g['d'][hid][1]} min) en auto, sin tráfico. Dirección: {g['addr']}.", g["src"])
        used.add(g["id"])
    # E: cuisine
    CU = [("japanese", "sushi or Japanese food", "sushi o comida japonesa", {"japanese", "asian", "chinese", "noodles", "thai"}),
          ("pizza", "pizza", "pizza", {"pizza", "italian"}), ("mexican", "Mexican food", "comida mexicana", {"mexican"}),
          ("coffee", "a coffee shop", "una cafetería", {"coffee"}), ("steak", "a steakhouse", "un asador", {"steak"}),
          ("thai", "Thai food", "comida tailandesa", {"thai", "asian"}), ("burgers", "a burger", "una hamburguesa", {"burgers", "pub"})]
    order = [c for c in CU if any(x["cu"] == c[0] and (c[0] != "steak" or "steakhouse" in (x["name"] + x["why"][0]).lower()) for x in rows)]; rnd.shuffle(order); n = 0
    for key, en, es, excl in order:
        g = pick([x for x in rows if x["cu"] == key and (key != "steak" or "steakhouse" in (x["name"] + x["why"][0]).lower())], 1)
        bad = [x for x in rows if x["cu"] not in excl and x["cu"] not in ("pub", "american") ]
        if g and len(bad) >= 3 and n < 3:
            bs = pick(bad, 3, {g[0]["id"]}); n += 1
            add("cu" + key, FD if key != "coffee" else DR, "restaurants", "easy", [f"A guest asks for {en} nearby. Which of these fits?", f"Someone at the desk is craving {en}. Which place should you suggest?", f"A family wants {en} tonight. Which of these serves it?"][n-1], [f"Un huésped pide {es} cerca. ¿Cuál de estos encaja?", f"Alguien en recepción se antoja de {es}. ¿Qué lugar sugieres?", f"Una familia quiere {es} esta noche. ¿Cuál de estos lo sirve?"][n-1], nm(g[0]), [nm(b) for b in bs],
                f"{name(g[0])} is listed as {({'japanese':'Japanese/sushi','pizza':'pizza','coffee':'a coffee shop','steak':'a steakhouse','burgers':'burgers','mexican':'Mexican','thai':'Thai'})[key]}; the others serve different food.",
                f"{name(g[0])} aparece como {({'japanese':'japonesa/sushi','pizza':'pizza','coffee':'café','steak':'asador','burgers':'hamburguesas','mexican':'comida mexicana','thai':'tailandesa'}).get(key,key)}; los demás sirven otra comida.", g[0]["src"])
    # F: walkable
    wk = [x for x in rows if x["walk"].get(hid)]; far = [x for x in rows if not x["walk"].get(hid) and x["d"][hid][0] >= 2]
    for k in range(2 if hid == "MSPWE" else 1):
        if wk and len(far) >= 3:
            g = pick(wk, 1, used)[0] if [y for y in wk if y["id"] not in used] else wk[0]; used.add(g["id"]); bs = pick(far, 3, {g["id"]})
            add("walk%d" % k, DR if k == 0 else FD, "restaurants", "med", ["A guest does not have a car and asks what they can walk to. Which of these is within about a 15-minute walk (roughly 0.8 miles or less) of our hotel?", "A guest wants dinner but would rather not call a ride. Which of these is a short walk (about 0.8 miles or less) from the hotel?"][k],
                ["Un huésped sin auto pregunta a dónde puede ir caminando. ¿Cuál de estos está a unos 15 minutos a pie (aprox. 0.8 millas o menos) de nuestro hotel?", "Un huésped quiere cenar pero prefiere no pedir transporte. ¿Cuál de estos queda a una caminata corta (aprox. 0.8 millas o menos) del hotel?"][k], nm(g), [nm(b) for b in bs],
                f"{name(g)} is about {fmt_mi(g['d'][hid][0])} away by road, roughly a 15-minute walk (estimate). The others are 2+ miles away by car.", f"{name(g)} está a unas {fmt_mi(g['d'][hid][0]).replace('miles','millas')} por carretera, más o menos 15 minutos a pie (estimado). Los demás están a más de 2 millas en auto.", g["src"])
    # G: inside MOA
    if AREA[hid] == "bl":
        moa = [x for x in rows if x["moa"]]; out = [x for x in rows if not x["moa"]]
        for k in range(2):
            g = pick([y for y in moa if y["id"] not in used], 1)[0]; used.add(g["id"]); bs = pick(out, 3)
            add("moa%d" % k, DR if k == 0 else FD, "restaurants", "easy", "A family wants to eat without leaving Mall of America. Which of these is inside the mall?" if k == 0 else "A guest is shopping at MOA and asks for lunch inside the mall. Which of these is inside MOA?",
                "Una familia quiere comer sin salir del Mall of America. ¿Cuál de estos está dentro del centro comercial?" if k == 0 else "Un huésped compra en MOA y pide almuerzo dentro del centro. ¿Cuál de estos está dentro de MOA?", nm(g), [nm(b) for b in bs],
                f"{name(g)} is a Mall of America tenant. The others are outside the mall.", f"{name(g)} está dentro del Mall of America. Los demás están fuera del centro comercial.", g["src"])
    # H: closed Sunday
    cl = [x for x in rows if x["hours"] and x["hours"] != "24h" and day_ranges(x["hours"], 6) == [] and re.search(r"closed (sundays|weekends)", x["why"][0].lower())]
    op = [x for x in rows if day_ranges(x["hours"], 6)]
    if cl and len(op) >= 3:
        g = pick(cl, 1)[0]; bs = pick(op, 3)
        add("sun", FD, "restaurants", "med", "A guest wants dinner out on a Sunday. Which of these is closed on Sundays?", "Un huésped quiere cenar fuera un domingo. ¿Cuál de estos cierra los domingos?", nm(g), [nm(b) for b in bs],
            f"{name(g)} is closed on Sundays per its listing. The others post Sunday hours. Always call to confirm.", f"{name(g)} cierra los domingos según su ficha. Los demás publican horario de domingo. Siempre confirma por teléfono.", g["src"])
    # I: phone
    ph = [x for x in rows if x["phone"]]
    if len(ph) >= 4:
        s = rnd.sample(ph, 4)
        add("phone", FD, "restaurants", "med", f"A guest asks you to call {name(s[0])} to check the wait. Which number is theirs?", f"Un huésped te pide llamar a {name(s[0])} para ver la espera. ¿Cuál es su número?",
            (s[0]["phone"], s[0]["phone"]), [(x["phone"], x["phone"]) for x in s[1:]], f"{name(s[0])}: {s[0]['phone']} (from its listing). Re-check if a call does not connect.", f"{name(s[0])}: {s[0]['phone']} (de su ficha). Verifica de nuevo si no contesta.", s[0]["src"])
    # J: call ahead
    g = rows[0]
    add("ahead", FD, "restaurants", "easy", "Before sending a guest to a restaurant late in the evening, what should you do?", "Antes de enviar a un huésped a un restaurante tarde en la noche, ¿qué debes hacer?",
        ("Check its posted hours and suggest calling ahead, because hours can change", "Revisar su horario publicado y sugerir llamar antes, porque los horarios pueden cambiar"),
        [("Promise it is open because our list says so", "Prometer que está abierto porque nuestra lista lo dice"), ("Tell them every restaurant nearby is open until midnight", "Decirle que todos los restaurantes cercanos abren hasta medianoche"), ("Send them without checking so they are not delayed", "Enviarlo sin revisar para no retrasarlo")],
        "Holiday, event and staffing changes can shift hours. Our restaurant list shows the date its hours were last checked, so confirm with a quick call.", "Los días festivos, eventos y el personal pueden cambiar los horarios. Nuestra lista muestra la fecha de la última revisión, así que confirma con una llamada rápida.", g["src"])
    # L: sports bar
    sp = [x for x in rows if x["cu"] == "pub" or "sports" in x["tags"]]; ns = [x for x in rows if x["cu"] in ("coffee", "breakfast", "pizza", "healthy", "deli", "thai", "japanese")]
    if sp and len(ns) >= 3:
        g = pick(sp, 1)[0]; bs = pick(ns, 3)
        add("sports", BAR, "restaurants", "easy", "A guest wants to watch the game with a beer and wings. Which of these is a pub or sports bar?", "Un huésped quiere ver el partido con una cerveza y alitas. ¿Cuál de estos es un pub o bar deportivo?", nm(g), [nm(b) for b in bs],
            f"{name(g)} is listed as a pub / sports bar. The others are not.", f"{name(g)} aparece como pub / bar deportivo. Los demás no.", g["src"])
    # O: 24h / earliest
    h24 = [x for x in rows if x["hours"] == "24h"]
    if h24:
        g = h24[0]; bs = pick([x for x in rows if x["hours"] and x["hours"] != "24h"], 3)
        add("h24", BAR, "restaurants", "easy", "It is 3 a.m. and a guest is hungry for a sit-down breakfast. Which of these posts 24-hour service?", "Son las 3 a.m. y un huésped quiere desayunar sentado. ¿Cuál de estos publica servicio las 24 horas?", nm(g), [nm(b) for b in bs],
            f"{name(g)} lists 24-hour hours. The others close overnight.", f"{name(g)} indica horario de 24 horas. Los demás cierran de noche.", g["src"])
    else:
        er = sorted([x for x in rows if open_on(x, 0) is not None], key=lambda x: open_on(x, 0))
        if er and open_on(er[0], 0) <= 5.5:
            g = er[0]; bs = pick([x for x in rows if (open_on(x, 0) or 0) >= 10.5], 3)
            add("earliest", FD, "restaurants", "med", "A guest asks which of these restaurants opens earliest on weekdays. Which one?", "Un huésped pregunta cuál de estos restaurantes abre más temprano entre semana. ¿Cuál?", nm(g), [nm(b) for b in bs],
                f"{name(g)} posts a weekday opening of 5:30 a.m.", f"{name(g)} abre entre semana a las 5:30 a.m.", g["src"])
    return Q
def fixp(t): return re.sub(r'\.\.(?!\.)', '.', t)
cands = []
for hid in ("MSPWE", "MSPAM", "MSPMS"):
    for q in build(hid)[:16]:
        roles = sorted(set(q["roles"]))
        cands.append(dict(hotel=hid, brand=BR[hid], roles=roles, kind="role", topic="restaurants", topics=["hotel", "restaurants", hid.lower()] + [r for r in roles if r in ("driver", "bartender")], difficulty=q["diff"],
                          qe=q["qe"], qs=q["qs"], oe=q["oe"], os=q["os"], c=0, ee=fixp(q["ee"]), es=fixp(q["es"]), src=q["src"], season=None, review_by="2027-04-26"))
bank = json.load(open(ROOT + 'data/qotd.json'))
ok, rej = run(cands, [x[4] for x in bank], scope=lambda x: x and x["hotel"])
random.seed(2710)
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
L = ["-- QOTD: restaurant guest-asks built from data/restaurants.js (verified 2026-10-27); review_by 2027-04-26"]
nl = max(x[0] for x in bank) + 1
for x in ok:
    L.append(f"insert into public.qotd_questions({COLS}) values (" + ",".join([q(x["brand"]), "'all'", q(x["topic"]), q(x["qe"]), q(x["qs"]), js(x["oe"]), js(x["os"]), str(x["c"]), q(x["ee"]), q(x["es"]), q(x["src"]), arr(x["roles"]), q(x["kind"]), q(x["difficulty"]), arr(x["topics"]), q(x["hotel"]), "null", "null", "'2027-04-26'::date"]) + ") on conflict (brand,role_group,question_en) do nothing;")
    bank.append([nl, x["brand"], "all", x["topic"], x["qe"], x["qs"], x["oe"], x["os"], x["c"], x["ee"], x["es"], x["src"], True, x["roles"], x["kind"], x["hotel"], None, "2027-04-26", x["difficulty"], x["topics"], None, 0]); nl += 1
open(ROOT + 'supabase/migrations/20261027_qotd_restaurants.sql', 'w').write("\n".join(L) + "\n")
json.dump(bank, open(ROOT + 'data/qotd.json', 'w'), ensure_ascii=False, separators=(",", ":"))
print("bank", len(bank))
