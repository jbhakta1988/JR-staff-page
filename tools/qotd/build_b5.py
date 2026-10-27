import json,random,sys
sys.path.insert(0,'.')
from qa import run, norm
for f in 'aklm': exec(open(f'b5/{f}.py').read())
BAN={}
def templates(): return []
HP=MP=IP=''
BR={"MSPAM":"Hilton","MSPMS":"Marriott","MSPWE":"IHG"}; SRC={"MSPAM":HP,"MSPMS":MP,"MSPWE":IP}
cands=[]
for r,kind,t,d,qe,qs,oe,os_,ee,es,src,*s in Q:
    cands.append(dict(hotel=None,brand="all",roles=sorted(r),kind=kind,topic=t,topics=[t]+sorted({"housekeeping" if x in("room_attendant","hk_supervisor") else x for x in r}),difficulty=d,
      qe=qe,qs=qs,oe=oe,os=os_,c=0,ee=ee,es=es,src=src,season=(s[0] if s else None),review_by=None))
for hid,extra,t,d,qe,qs,oe,os_,ee,es,src in HQ:
    ban=BAN.get(hid,set())
    roles=sorted(set(["front_desk","night_audit"]+[x for x in extra if x not in ban]))
    cands.append(dict(hotel=hid,brand=BR[hid],roles=roles,kind="role",topic=t,topics=["hotel",t,hid.lower()],difficulty=d,qe=qe,qs=qs,oe=oe,os=os_,c=0,ee=ee,es=es,src=src,season=None,review_by="2027-04-26"))
bank=json.load(open('/workspace/repo/data/qotd.json'))
ok,rej=run(cands,[x[4] for x in bank],scope=lambda x: x and x["hotel"])
random.seed(265)
for x in ok:
    p=list(range(len(x["oe"])));random.shuffle(p)
    x["oe"]=[x["oe"][i] for i in p];x["os"]=[x["os"][i] for i in p];x["c"]=p.index(0)
print("candidates",len(cands),"accepted",len(ok),"rejected",len(rej))
for x,e in rej: print(" REJECT",x["hotel"],x["qe"][:70],"->",e)
# templates (no answer yet) — dedupe on exact text only
have={norm(x[4]) for x in bank}
tm=[t for t in templates() if norm(t["qe"]) not in have]
q=lambda s:"null" if s is None else "'"+str(s).replace("'","''")+"'"
arr=lambda a:"array["+",".join(q(v) for v in a)+"]::text[]"
js=lambda a:q(json.dumps(a,ensure_ascii=False))+"::jsonb"
COLS="brand,role_group,topic,question_en,question_es,options_en,options_es,correct_idx,explain_en,explain_es,source_url,roles,kind,difficulty,topics,hotel_id,season_start,season_end,review_by"
L=["-- QOTD batch 5: front desk + night audit daily, bartender, brand standards, local guest-asks"]
for x in ok:
    ss,se=(x["season"] or (None,None))
    L.append(f"insert into public.qotd_questions({COLS}) values ("+",".join([q(x["brand"]),"'all'",q(x["topic"]),q(x["qe"]),q(x["qs"]),js(x["oe"]),js(x["os"]),str(x["c"]),q(x["ee"]),q(x["es"]),q(x["src"]),arr(x["roles"]),q(x["kind"]),q(x["difficulty"]),arr(x["topics"]),q(x["hotel"]),q(ss),q(se),(q(x["review_by"])+"::date") if x["review_by"] else "null"])+") on conflict (brand,role_group,question_en) do nothing;")
PE=["[GM: correct answer]","[GM: wrong answer]","[GM: wrong answer]"]; PS=["[GM: respuesta correcta]","[GM: respuesta incorrecta]","[GM: respuesta incorrecta]"]
for t in tm:
    t["oe"]=PE;t["os"]=PS
    L.append(f"insert into public.qotd_questions({COLS},active,needs_confirm,confirm_note) values ("+",".join([q(BR[t['hotel']]),"'all'",q(t["topic"]),q(t["qe"]),q(t["qs"]),js(PE),js(PS),"0",q("Confirmed by the hotel GM."),q("Confirmado por el gerente del hotel."),q(SRC[t["hotel"]]),arr(sorted(set(t["roles"]))),"'role'","'easy'",arr(["hotel",t["topic"],t["hotel"].lower(),"gm_confirm"]),q(t["hotel"]),"null","null","'2027-04-26'::date","false","true",q(t["note"])])+") on conflict (brand,role_group,question_en) do nothing;")
open('b5.sql','w').write("\n".join(L)+"\n")
nj=max(x[0] for x in bank if x[0]<2000)+1; nl=max(x[0] for x in bank)+1
for x in ok:
    if x["hotel"]: i=nl;nl+=1
    else: i=nj;nj+=1
    ss,se=(x["season"] or (None,None))
    bank.append([i,x["brand"],"all",x["topic"],x["qe"],x["qs"],x["oe"],x["os"],x["c"],x["ee"],x["es"],x["src"],True,x["roles"],x["kind"],x["hotel"],[ss,se] if ss else None,x["review_by"],x["difficulty"],x["topics"]])
for t in tm:
    bank.append([nl,BR[t["hotel"]],"all",t["topic"],t["qe"],t["qs"],PE,PS,0,"Confirmed by the hotel GM.","Confirmado por el gerente del hotel.",SRC[t["hotel"]],True,sorted(set(t["roles"])),"role",t["hotel"],None,"2027-04-26","easy",["hotel",t["topic"],"gm_confirm"],{"pending":True,"note":t["note"]}]); nl+=1
json.dump(bank,open('/tmp/qotd_new.json','w'),ensure_ascii=False)
print("templates",len(tm),"bank",len(bank))
