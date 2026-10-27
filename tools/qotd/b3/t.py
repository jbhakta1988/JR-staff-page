# GM-confirm templates: inactive, needs_confirm=true. The GM fills in the answers in the editor, which turns them on.
H2=["room_attendant","houseman","hk_supervisor"]; MT=["maintenance"]; ALLW=["room_attendant","houseman","hk_supervisor","laundry","maintenance","breakfast"]
COMMON=[
 ("rooms","How many guest rooms does our hotel have?","¿Cuántos cuartos tiene nuestro hotel?",H2,"Rooms table in Supabase is empty, so there's no count in the system yet"),
 ("rooms","How many suites does our hotel have?","¿Cuántas suites tiene nuestro hotel?",H2,"Not in the DB"),
 ("rooms","Which room type do we have the most of?","¿Qué tipo de cuarto tenemos más?",H2,"Room mix not in the DB"),
 ("rooms","How many floors does our hotel have?","¿Cuántos pisos tiene nuestro hotel?",ALLW,"Not on the brand page or in the DB"),
 ("rooms","How many ADA-accessible rooms do we have?","¿Cuántos cuartos accesibles (ADA) tenemos?",H2,"Count not on the brand page"),
 ("history","What year did our hotel open (or last renovate)?","¿En qué año abrió (o se renovó) nuestro hotel?",[],"Not sourced on the brand page"),
 ("location","What are the nearest cross streets / highway exit to our hotel?","¿Cuáles son las calles o la salida de autopista más cercanas al hotel?",["driver"],"Write it the way you give directions"),
 ("building","Where are the ice machines?","¿Dónde están las máquinas de hielo?",ALLW,"Location in the building"),
 ("building","Where are the vending machines?","¿Dónde están las máquinas expendedoras?",ALLW,"Location in the building"),
 ("building","How many guest elevators do we have, and where are they?","¿Cuántos elevadores para huéspedes hay y dónde están?",ALLW,"Location in the building"),
 ("building","Where are the stairwells?","¿Dónde están las escaleras de emergencia?",ALLW,"Location in the building"),
 ("safety","Where is our fire assembly point?","¿Dónde es nuestro punto de reunión en caso de incendio?",ALLW,"Safety — must match the emergency plan"),
 ("safety","Where is the AED kept?","¿Dónde está el desfibrilador (DEA/AED)?",ALLW,"Safety — must match the posted location"),
 ("safety","Where is the first-aid kit?","¿Dónde está el botiquín de primeros auxilios?",ALLW,"Safety"),
 ("policy","How long do we hold lost-and-found items, and where are they logged?","¿Cuánto tiempo guardamos los objetos perdidos y dónde se registran?",H2,"Process"),
 ("policy","After hours, how do you reach the manager on duty?","Fuera de horario, ¿cómo contactas al gerente de turno?",ALLW,"Contact method/number"),
 ("policy","What are our quiet hours?","¿Cuál es nuestro horario de silencio?",H2,"Policy"),
 ("policy","What's the incidental hold/deposit at check-in?","¿Cuál es el depósito o retención para gastos al registrarse?",[],"Amount and method (card/cash)"),
 ("policy","What ID does a guest need to check in?","¿Qué identificación necesita el huésped para registrarse?",[],"Accepted IDs"),
 ("policy","Can guests check in early, and is there a fee?","¿Pueden registrarse temprano y hay cargo?",H2,"Policy"),
 ("policy","Can guests get a late checkout, and is there a fee?","¿Pueden salir tarde y hay cargo?",H2,"Not on the brand page"),
 ("policy","Where do we store guest luggage, and for how long?","¿Dónde guardamos el equipaje de los huéspedes y por cuánto tiempo?",["houseman"],"Process"),
 ("pool","What are the pool hours?","¿Cuál es el horario de la alberca?",["houseman","maintenance"],"Not on the brand page"),
 ("pool","Do we have a hot tub, and what are its hours?","¿Tenemos jacuzzi y cuál es su horario?",["houseman","maintenance"],"Not on the brand page"),
 ("amenities","Is there a guest laundry, where is it, and what does it cost?","¿Hay lavandería para huéspedes, dónde está y cuánto cuesta?",H2+["laundry"],"Location/cost not on the brand page"),
 ("amenities","Where is the pantry / market and how do guests pay?","¿Dónde está la tiendita y cómo pagan los huéspedes?",[],"Location/payment"),
 ("amenities","Where is the business center, and is there a printer?","¿Dónde está el centro de negocios y hay impresora?",[],"Location"),
 ("rooms","Do we have connecting rooms? Which room numbers?","¿Tenemos cuartos conectados? ¿Qué números?",H2,"Room numbers"),
]
EXTRA={
 "MSPAM":[("checkin","What is check-in time at our Hampton?","¿A qué hora es la entrada en nuestro Hampton?",H2,"Not shown on the Hilton page"),
          ("breakfast","What are breakfast hours on weekdays and weekends?","¿Cuál es el horario del desayuno entre semana y en fin de semana?",["breakfast"],"Hours not on the Hilton page"),
          ("fitness","What are the fitness center hours?","¿Cuál es el horario del gimnasio?",["houseman"],"Hours not on the Hilton page")],
 "MSPMS":[("bar","What are the SpringHill Lounge hours?","¿Cuál es el horario del SpringHill Lounge?",["bartender"],"Hours not on the Marriott page"),
          ("shuttle","What are the airport shuttle hours, and how do guests request it?","¿Cuál es el horario del shuttle y cómo lo piden?",["driver"],"Marriott says 'on request', no hours")],
 "MSPWE":[("breakfast","Do weekend breakfast hours differ from 6:00–9:30 a.m.?","¿El horario del desayuno en fin de semana es distinto de 6:00 a 9:30 a. m.?",["breakfast"],"IHG lists one set of hours"),
          ("fitness","What are the fitness center hours?","¿Cuál es el horario del gimnasio?",["houseman"],"Not on the IHG page"),
          ("meetings","Do we have meeting space, and for how many people?","¿Tenemos salas de juntas y para cuántas personas?",[],"Not clear on the IHG page")],
}
NAME={"MSPAM":"Hampton","MSPMS":"SpringHill","MSPWE":"Holiday Inn Express"}
BAN={"MSPWE":{"driver","bartender"},"MSPAM":{"bartender"}}
def templates():
    out=[]
    for hid in ("MSPAM","MSPMS","MSPWE"):
        for t,qe,qs,ex,note in COMMON+EXTRA[hid]:
            if hid!="MSPAM" and qe.startswith("What is check-in"): continue
            qe2=qe.replace("our hotel",f"our {NAME[hid]}"); qs2=qs.replace("nuestro hotel",f"nuestro {NAME[hid]}")
            if NAME[hid] not in qe2: qe2=qe2.rstrip("?")+f" ({NAME[hid]})?"; qs2=qs2.rstrip("?")+f" ({NAME[hid]})?"
            roles=["front_desk","night_audit","gm"]+[r for r in ex if r not in BAN.get(hid,set())]
            out.append(dict(hotel=hid,topic=t,qe=qe2,qs=qs2,roles=roles,note=note))
    return out
