import json,random,sys
sys.path.insert(0,'.')
from qa import run
for f in 'abcdefg': exec(open(f'b2{f}.py').read())
BR={"MSPAM":"Hilton","MSPMS":"Marriott","MSPWE":"IHG"}
BAR_TOPICS={"food","transit","liquor","local","health"}
cands=[]
for r,t,d,qe,qs,oe,os_,ee,es,src,season in Q:
    cands.append(dict(hotel=None,brand="all",roles=sorted(r),topic=t,topics=[t]+sorted({"housekeeping" if x in("room_attendant","hk_supervisor") else x for x in r}),difficulty=d,
      qe=qe,qs=qs,oe=oe,os=os_,c=0,ee=ee,es=es,src=src,season=season,review_by=None))
def loc(hid,row):
    t,d,qe,qs,oe,os_,ee,es,src=row
    roles=["front_desk","gm","night_audit"]+(["bartender"] if hid=="MSPMS" and t in BAR_TOPICS else [])
    return dict(hotel=hid,brand=BR[hid],roles=sorted(roles),topic=t,topics=["local",t,hid.lower()],difficulty=d,qe=qe,qs=qs,oe=oe,os=os_,c=0,ee=ee,es=es,src=src,season=None,review_by="2027-04-26")
for row in GV2: cands.append(loc("MSPWE",row))
for hs,row in RW.values():
    for h in hs: cands.append(loc(h,row))
bank=json.load(open('/workspace/repo/data/qotd.json'))
ok,rej=run(cands,[x[4] for x in bank],scope=lambda x: x and x["hotel"])
random.seed(262)
for x in ok:
    p=list(range(len(x["oe"])));random.shuffle(p)
    x["oe"]=[x["oe"][i] for i in p];x["os"]=[x["os"][i] for i in p];x["c"]=p.index(0)
print("candidates",len(cands),"accepted",len(ok),"rejected",len(rej))
for x,e in rej: print(" REJECT",x["hotel"],x["qe"][:70],"->",e)
q=lambda s:"null" if s is None else "'"+str(s).replace("'","''")+"'"
arr=lambda a:"array["+",".join(q(v) for v in a)+"]::text[]"
js=lambda a:q(json.dumps(a,ensure_ascii=False))+"::jsonb"
L=["-- QOTD batch 2: job-scenario questions (RA/supervisor/laundry/houseman/maintenance/breakfast) + Golden Valley local + batch-1 rewords"]
for x in ok:
    ss,se=(x["season"] or (None,None))
    L.append("insert into public.qotd_questions(brand,role_group,topic,question_en,question_es,options_en,options_es,correct_idx,explain_en,explain_es,source_url,roles,kind,difficulty,topics,hotel_id,season_start,season_end,review_by) values ("
      +",".join([q(x["brand"]),"'all'",q(x["topic"]),q(x["qe"]),q(x["qs"]),js(x["oe"]),js(x["os"]),str(x["c"]),q(x["ee"]),q(x["es"]),q(x["src"]),arr(x["roles"]),"'role'",q(x["difficulty"]),arr(x["topics"]),q(x["hotel"]),q(ss),q(se),(q(x["review_by"])+"::date") if x["review_by"] else "null"])
      +") on conflict (brand,role_group,question_en) do nothing;")
open('b2.sql','w').write("\n".join(L)+"\n")
nj=max(x[0] for x in bank if x[0]<2000)+1; nl=max(x[0] for x in bank)+1
for x in ok:
    if x["hotel"]: i=nl;nl+=1
    else: i=nj;nj+=1
    ss,se=(x["season"] or (None,None))
    bank.append([i,x["brand"],"all",x["topic"],x["qe"],x["qs"],x["oe"],x["os"],x["c"],x["ee"],x["es"],x["src"],True,x["roles"],"role",x["hotel"],[ss,se] if ss else None,x["review_by"],x["difficulty"],x["topics"]])
json.dump(bank,open('/tmp/qotd_new.json','w'),ensure_ascii=False)
from collections import Counter
print(sorted(Counter(r for x in ok for r in x["roles"]).items()))
