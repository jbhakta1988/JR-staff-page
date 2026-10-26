/* Front desk app-login coverage (GM/AGM dashboard) + app heartbeat. Backend: fd_login_alerts.sql */
(function(){
  const T={en:{h:"Front Desk Coverage — Today",on:"Online",idle:"Logged in, idle",no:"Not logged in",up:"Upcoming",end:"Ended",seen:"Last seen",never:"never",he:"Clocked in (HE)",none:"No front desk shifts scheduled today"},
           es:{h:"Cobertura de Recepción — Hoy",on:"En línea",idle:"Conectado, inactivo",no:"Sin iniciar sesión",up:"Próximo",end:"Terminado",seen:"Última vez",never:"nunca",he:"Marcó entrada (HE)",none:"No hay turnos de recepción hoy"}};
  const L=()=>(typeof LANG!=="undefined"&&LANG==="es")?"es":"en";
  const tm=x=>x?new Date(x).toLocaleTimeString("en-US",{timeZone:"America/Chicago",hour:"numeric",minute:"2-digit"}):"";
  let rows=null,hotel="",at=0;
  function demo(){const n=Date.now(),h=36e5;return[
    {name:"Maria G.",shift_position:"Front Desk Agent",shift_start:new Date(n-3*h),shift_end:new Date(n+5*h),status:"online",last_seen:new Date(n-2e5),clocked_in:true},
    {name:"Jordan P.",shift_position:"Front Desk Agent",shift_start:new Date(n-h),shift_end:new Date(n+7*h),status:"not_logged_in",last_seen:null,clocked_in:true,open_alert:"fd_no_login"},
    {name:"Luis R.",shift_position:"Night Auditor",shift_start:new Date(n+6*h),shift_end:new Date(n+14*h),status:"upcoming",last_seen:null,clocked_in:false}]}
  async function load(h){
    hotel=h;at=Date.now();
    try{ if(typeof useRemote==="function"&&useRemote()){const r=await sb.rpc("fd_coverage_today",{p_hotel:h});rows=r.error?[]:r.data;}else rows=demo(); }catch(e){rows=[]}
    if(typeof render==="function")render();
  }
  window.fdCoverageCard=function(h){
    if(!h)return"";
    if(h!==hotel||Date.now()-at>120000){if(rows===null||h!==hotel)rows=rows||[];load(h)}
    const t=T[L()],cls={online:"good",not_logged_in:"bad",logged_in_idle:"bad"},lab={online:t.on,not_logged_in:t.no,logged_in_idle:t.idle,upcoming:t.up,ended:t.end};
    const body=(rows||[]).length?`<table style="width:100%"><tbody>${rows.map(r=>`<tr><td><b>${(typeof escH==="function"?escH:String)(r.name||"")}</b><br><small>${r.shift_position||""} · ${tm(r.shift_start)}–${tm(r.shift_end)}</small></td><td class="${cls[r.status]||""}">${lab[r.status]||r.status}${r.clocked_in&&r.status==="not_logged_in"?`<br><small>${t.he}</small>`:""}<br><small>${t.seen}: ${r.last_seen?tm(r.last_seen):t.never}</small></td></tr>`).join("")}</tbody></table>`:`<p><small>${t.none}</small></p>`;
    return `<div class="card"><h3>${t.h}</h3>${body}</div>`;
  };
  // heartbeat: on open and every 3 min while visible
  function beat(open){try{if(typeof useRemote==="function"&&useRemote()&&document.visibilityState==="visible")sb.rpc("app_heartbeat",{p_open:!!open})}catch(e){}}
  let first=true;
  setInterval(()=>{beat(first);first=false},180000);
  document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")beat(true)});
  window.fdHeartbeatNow=()=>beat(true);
  setTimeout(()=>beat(true),5000);
})();
