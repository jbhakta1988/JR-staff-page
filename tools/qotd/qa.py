"""QOTD QA pipeline: format checks, exact + near-duplicate detection (EN and ES), answer sanity.
Usage: from qa import run; ok, rejects = run(candidates, existing_texts)"""
import re, difflib
STOP=set("a an the is are to of and or for in on at do you your what which how should guest asks a guest who when where".split())
def norm(s): return re.sub(r"\s+"," ",re.sub(r"[^a-z0-9áéíóúñü ]"," ",s.lower())).strip()
def toks(s): return {w for w in norm(s).split() if w not in STOP}
def jacc(a,b): return len(a&b)/max(1,len(a|b))
def near(a,b): return difflib.SequenceMatcher(None,norm(a),norm(b)).ratio()
def check(x):
    e=[]
    for k in ("qe","qs","ee","es","src"):
        if not str(x.get(k,"")).strip(): e.append("missing "+k)
    oe,os_=x["oe"],x["os"]
    if not 3<=len(oe)<=4: e.append("needs 3-4 options")
    if len(oe)!=len(os_): e.append("EN/ES option count mismatch")
    if len({norm(o) for o in oe})!=len(oe): e.append("duplicate EN options")
    if len({norm(o) for o in os_})!=len(os_): e.append("duplicate ES options")
    if not 0<=x["c"]<len(oe): e.append("bad correct index")
    if not str(x["src"]).startswith("http") and x["src"]!="general hospitality best practice": e.append("bad source")
    if "{" in x["qe"]+x["qs"]+"".join(oe+os_)+x["ee"]+x["es"]: e.append("unfilled placeholder")
    # one clearly correct answer: correct option must not be a substring of / near-identical to a distractor
    c=norm(oe[x["c"]])
    for i,o in enumerate(oe):
        if i!=x["c"] and (near(c,norm(o))>0.9): e.append("distractor too close to answer")
    if re.search(r"\ball of the above\b|\bnone of the above\b",norm(" ".join(oe))): e.append("all/none of the above")
    if norm(x["qe"])==norm(x["qs"]): e.append("ES not translated")
    if x.get("difficulty") not in ("easy","med","hard"): e.append("missing difficulty")
    return e
def run(cands, existing, scope=lambda x:None):
    ok,rej=[],[]
    seen=[(scope(None),t) for t in existing]  # global existing
    for x in cands:
        e=check(x)
        sc=scope(x)
        if not e:
            for s,t in seen+[(scope(y),y["qe"]) for y in ok]:
                if s not in (None,sc): continue
                if norm(t)==norm(x["qe"]): e.append("exact duplicate"); break
                if near(t,x["qe"])>0.88 or jacc(toks(t),toks(x["qe"]))>0.8: e.append("near-duplicate of: "+t[:60]); break
        (rej if e else ok).append((x,e) if e else x)
    return ok,rej
