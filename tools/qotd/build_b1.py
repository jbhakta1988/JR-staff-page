import json,random,sys
sys.path.insert(0,'.')
from qa import run,norm
exec(open('local/b1.py').read())
HOT={"MSPAM":dict(brand="Hilton",H="Hampton Inn & Suites MSP Airport/Mall of America",P="952-854-7600",A="2860 Metro Drive",HS=HAMP),
     "MSPMS":dict(brand="Marriott",H="SpringHill Suites MSP Airport/Mall of America",P="952-854-0300",A="2870 Metro Drive",HS=SHS),
     "MSPWE":dict(brand="IHG")}
ROLES={"FD":["front_desk","night_audit","gm"],"DR":["front_desk","night_audit","gm","driver"],"BAR":["bartender","front_desk","night_audit","gm"]}
BAR_TOPICS={"food","transit","liquor","local","health"}
def sub(s,h): 
    for k in ("H","P","A","HS"):
        if k in h: s=s.replace("{"+k+"}",h[k])
    return s
cands=[]
for hid,rows in (("MSPAM",BLOOM),("MSPMS",BLOOM),("MSPWE",GV)):
    h=HOT[hid]
    for r in rows:
        rk,topic,diff,qe,qs,oe,os_,ee,es,src=r[:10]; season=r[10] if len(r)>10 else None
        if rk=="BAR" and hid!="MSPMS": continue
        roles=list(ROLES[rk])
        if hid=="MSPMS" and rk!="BAR" and topic in BAR_TOPICS: roles.append("bartender")
        if hid=="MSPWE": roles=[x for x in roles if x!="driver"]
        cands.append(dict(hotel=hid,brand=h["brand"],roles=sorted(set(roles)),topic=topic,topics=["local",topic,hid.lower()],difficulty=diff,
          qe=sub(qe,h),qs=sub(qs,h),oe=[sub(o,h) for o in oe],os=[sub(o,h) for o in os_],c=0,ee=sub(ee,h),es=sub(es,h),src=sub(src,h),
          season=season,review_by="2027-04-26"))
existing=[x[4] for x in json.load(open('/workspace/repo/data/qotd.json'))]
ok,rej=run(cands,existing,scope=lambda x: x and x["hotel"])
random.seed(172)
for x in ok:
    p=list(range(len(x["oe"])));random.shuffle(p)
    x["oe"]=[x["oe"][i] for i in p];x["os"]=[x["os"][i] for i in p];x["c"]=p.index(0)
json.dump(ok,open('local/b1_ok.json','w'),ensure_ascii=False,indent=0)
print("candidates",len(cands),"accepted",len(ok),"rejected",len(rej))
for x,e in rej: print(" REJECT",x["hotel"],x["qe"][:70],"->",e)
from collections import Counter
c=Counter((x["hotel"],r) for x in ok for r in x["roles"]); print(sorted(c.items()))
