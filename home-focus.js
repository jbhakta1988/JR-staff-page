/* Home shows at most four compact pieces: a Today summary, urgent alerts,
   the role's main actions, and a collapsed More section. Cards with nothing
   to show are omitted. Sales Leads by Hotel (#slRollup) and the sales-lead
   home card stay in More. Nothing is removed from its own screen. */
(function (root) {
  "use strict";

  function L(en, es) {
    return (typeof LANG !== "undefined" && LANG === "es") ? es : en;
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c];
    });
  }

  function todayModel(role, snap) {
    snap = snap || {};
    function row(n, en, es) { return { n: String(n), en: en, es: es }; }
    var items;
    if (role === "Shuttle Driver" && snap.shuttle === false) {
      return { noteEn: "No shuttle at this property.", noteEs: "No hay shuttle en esta propiedad.", items: [] };
    }
    if (role === "Front Desk") items = [row(snap.arr == null ? "—" : snap.arr, "Arrivals", "Llegadas"), row(num(snap.dirty), "Dirty", "Sucios"), row(num(snap.openWo), "Open WOs", "Órdenes")];
    else if (role === "Housekeeping") items = [row(num(snap.dirty), "Dirty", "Sucios"), row(num(snap.rfi), "To inspect", "Por inspeccionar"), row(num(snap.esc), "Escalations", "Escalaciones")];
    else if (role === "Housekeeper") items = [row(snap.done == null ? "0/0" : snap.done, "Done", "Listos"), row(num(snap.progress), "In progress", "En proceso"), row(num(snap.dnd), "DND / refused", "No molestar")];
    else if (role === "Maintenance") items = [row(num(snap.openWo), "Open WOs", "Órdenes"), row(num(snap.overduePm), "Overdue PMs", "PM atrasados"), row(num(snap.check) + "%", "Checklist", "Lista")];
    else if (role === "Shuttle Driver") items = [row(num(snap.runs), "Runs left", "Viajes"), row(num(snap.check) + "%", "Checklist", "Lista")];
    else if (role === "House Person" || role === "Laundry Attendant" || role === "Breakfast Attendant") items = [row(num(snap.openReq), "Open requests", "Solicitudes"), row(num(snap.check) + "%", "Checklist", "Lista")];
    else items = [row(snap.occ == null ? "—" : snap.occ + "%", "Occupancy", "Ocupación"), row(num(snap.dirty), "Dirty", "Sucios"), row(snap.issues != null ? snap.issues : num(snap.openWo), "Open issues", "Asuntos")];
    return { noteEn: "", noteEs: "", items: items.slice(0, 4) };
  }
  function num(v) { return v == null || v === "" ? 0 : v; }

  function portfolioRow(code, name, snap) {
    if (!snap) return { hotel: code, name: name || code, metric: "—", metricEn: "Occ", metricEs: "Ocup.", issues: "—" };
    var occ = snap.occ != null && snap.occ !== "";
    return {
      hotel: code,
      name: name || code,
      metric: occ ? String(snap.occ) + "%" : (snap.ready != null ? String(snap.ready) : "—"),
      metricEn: occ ? "Occ" : "Rooms ready",
      metricEs: occ ? "Ocup." : "Cuartos listos",
      issues: snap.issues != null ? snap.issues : 0
    };
  }
  function hotelsFor(role, own, all, sees) {
    return (all || []).filter(function (hotel) { return sees(role, own, hotel); });
  }
  function slotFor(id) {
    if (id === "hhqToday" || id === "uxHero") return "today";
    if (id === "hhqUrgent") return "urgent";
    if (id === "hhqActions") return "actions";
    if (id === "hhqMore" || id === "hhqFocus") return "shell";
    return "more";
  }
  function cardIsEmpty(card) {
    card = card || {};
    if (card.keep) return false;
    var rows = Number(card.rows) || 0;
    if (rows > 0) return false;
    if (card.badge === 0 && (card.id === "opsList" || card.id === "alerts" || card.id === "reminders")) return true;
    if (card.id === "mtMgrHome" && card.count === 0) return true;
    if ((card.id === "mtDayBanner" || card.id === "todayCard" || card.id === "alerts") && rows === 0) return true;
    var text = String(card.text || "").replace(/\s+/g, " ").trim();
    if (!text && !card.controls) return true;
    var low = text.toLowerCase();
    var empty = [
      "no alerts.", "no alerts", "sin alertas.", "no hay alertas.",
      "nothing urgent right now.", "nada urgente por ahora.",
      "nothing here yet.", "nada aquí todavía.",
      "no requests yet.", "aún no hay solicitudes.",
      "no open punch issues.",
      "no meetings today.", "no hay reuniones hoy.",
      "none right now.", "nada por ahora."
    ];
    if (empty.indexOf(low) >= 0) return true;
    if (!card.controls && text.length < 180 && /nothing here yet|nada aquí todavía|no alerts|nothing urgent|nada urgente|no requests yet|aún no hay solicitudes|no meetings today|no hay reuniones|no open punch/i.test(text)) return true;
    return false;
  }
  function urgentItems(input) {
    input = input || {};
    var items = [];
    if (input.featureMeet !== false && input.canMeet !== false && input.meetings > 0) items.push({ kind: "meeting", n: input.meetings });
    if (input.overdueWo > 0) items.push({ kind: "wo", n: input.overdueWo });
    if (input.overduePm > 0 && input.seesPm) items.push({ kind: "pm", n: input.overduePm });
    if (input.overdueTasks > 0) items.push({ kind: "task", n: input.overdueTasks });
    if (input.lateRush > 0) items.push({ kind: "rush", n: input.lateRush });
    return items;
  }

  var api = {
    todayModel: todayModel,
    portfolioRow: portfolioRow,
    hotelsFor: hotelsFor,
    slotFor: slotFor,
    cardIsEmpty: cardIsEmpty,
    urgentItems: urgentItems
  };
  root.HHQHome = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof document === "undefined" || typeof V === "undefined") return;

  var folding = false;
  var PLACE = /no requests yet|aún no hay solicitudes|nothing here yet|nada aquí todavía|no alerts|nothing urgent|nada urgente|none yet|none right now|nada por ahora|no meetings today|no hay reuniones|no open punch/i;

  function roleNow() {
    try { return authRole() || S.role || ""; } catch (e) { return (typeof S !== "undefined" && S.role) || ""; }
  }
  function can(cap) {
    try { if (root.HHQ && HHQ.can) return !!HHQ.can(roleNow(), cap); } catch (e) {}
    return false;
  }
  function featureOn(hotel, feature) {
    try { if (root.HotelFeatures && HotelFeatures.on) return HotelFeatures.on(hotel, feature) !== false; } catch (e) {}
    return true;
  }
  function corporatePortfolio() {
    if (!can("see.allHotels")) return false;
    if (typeof S !== "undefined" && S.role && S.role !== "GM") return false;
    return !S.hhqDrill;
  }
  function seenHotels() {
    var own = "";
    try { var u = meUser(); own = (u && u.hotel) || ""; } catch (e) {}
    var all = Object.keys(typeof HOTELS !== "undefined" ? HOTELS : {});
    return hotelsFor(roleNow(), own, all, function (role, hotelOwn, hotel) {
      try { if (root.HHQ && HHQ.seesHotel) return HHQ.seesHotel(role, hotelOwn, hotel); } catch (e) {}
      return can("see.allHotels") || !hotelOwn || hotelOwn === hotel;
    });
  }
  function snapOf(hotel) {
    var bag = (typeof S !== "undefined" && S.h) ? S.h[hotel] : null;
    if (!bag) return null;
    var rooms = bag.rooms || [];
    var openWo = (bag.wo || []).filter(function (w) { return w.s !== "Done"; }).length;
    var esc = (bag.esc || []).filter(function (x) { return x.st !== "Resolved" && x.st !== "Acknowledged"; }).length;
    return {
      openWo: openWo,
      dirty: rooms.filter(function (x) { return /D$/.test(x.s || ""); }).length,
      ready: rooms.filter(function (x) { return x.s === "VC" || x.s === "OC"; }).length,
      rfi: rooms.filter(function (x) { return x.s === "RFI"; }).length,
      esc: esc,
      occ: bag.fc && bag.fc[0] ? bag.fc[0].occ : null,
      arr: bag.fc && bag.fc[0] ? bag.fc[0].arr : null,
      issues: openWo + esc
    };
  }
  function liveSnap() {
    var hotel = S.hotel;
    var base = snapOf(hotel) || {};
    var role = S.role;
    base.shuttle = featureOn(hotel, "shuttle") && (hotel === "MSPAM" || hotel === "MSPMS");
    if (role === "Maintenance" || role === "Shuttle Driver" || role === "House Person" || role === "Laundry Attendant" || role === "Breakfast Attendant") {
      try { base.check = typeof lpct === "function" ? lpct(role) : 0; } catch (e) { base.check = 0; }
    }
    if (role === "Shuttle Driver") {
      try { base.runs = typeof SH === "function" ? SH().runs.filter(function (x) { return x.st !== "Complete"; }).length : 0; } catch (e2) { base.runs = 0; }
    }
    if (role === "House Person" || role === "Laundry Attendant" || role === "Breakfast Attendant") {
      try { base.openReq = typeof myReqs === "function" ? myReqs().filter(function (x) { return x.st !== "Done"; }).length : 0; } catch (e3) { base.openReq = 0; }
    }
    if (role === "Housekeeper") {
      var me = "";
      try { me = cw(); } catch (e5) { me = ""; }
      var rooms = ((S.h || {})[hotel] || {}).rooms || [];
      var mine = rooms.filter(function (x) { return x.hk === me && ((/VD|OD|RFI/).test(x.s || "") || x.x || x.t1); });
      base.done = mine.filter(function (x) { return x.t1 || x.s === "RFI"; }).length + "/" + mine.length;
      base.progress = mine.filter(function (x) { return x.t0 && !x.t1; }).length;
      base.dnd = mine.filter(function (x) { return x.x; }).length;
    }
    return base;
  }
  function overduePm() {
    var n = 0;
    if (typeof eqList === "function") n += eqList().filter(function (e) { return e.od; }).length;
    if (typeof pmToday === "function") n += pmToday().filter(function (x) { return x.od && !x.done; }).length;
    return n;
  }
  function overdueWo() {
    var bag = (S.h || {})[S.hotel] || {};
    var today = typeof ld === "function" ? ld() : "";
    return (bag.wo || []).filter(function (w) {
      if (!w || w.s === "Done") return false;
      if (w.od || w.overdue) return true;
      return !!(w.due && today && String(w.due) < today);
    }).length;
  }
  function overdueTasks(role) {
    if (typeof ITEMS !== "function" || typeof od !== "function") return 0;
    return ITEMS().filter(function (it) {
      if (!od(it)) return false;
      var grp = String(it.grp || "");
      if (role === "GM" || role === "AGM") return grp.indexOf("GM") === 0;
      if (role === "Front Desk") return it.def === "Front Desk" || grp.indexOf("Front Desk") === 0;
      if (role === "Housekeeping") return it.def === "Housekeeping" || grp.indexOf("Housekeeping") === 0;
      if (role === "Maintenance") return it.def === "Maintenance" || grp.indexOf("Maintenance") === 0;
      return it.def === role || grp.indexOf(role) === 0;
    }).length;
  }
  function lateRush(role) {
    var allowed = role === "Housekeeper" || can("rush.see");
    if (!allowed || typeof rushList !== "function" || typeof rushLate !== "function") return 0;
    var rows = rushList().filter(rushLate);
    if (role === "Housekeeper") {
      var me = "";
      try { me = cw(); } catch (e) { me = ""; }
      rows = rows.filter(function (r) { return !r.hk || r.hk === me; });
    }
    return rows.length;
  }
  function seesPm() {
    try {
      if (typeof tilesFor === "function" && (tilesFor(S.role) || []).indexOf("pm") >= 0) return true;
    } catch (e) {}
    return S.role === "GM" || S.role === "Maintenance" || can("pm.manage");
  }
  function realRows(el) {
    var n = 0;
    el.querySelectorAll(".li, .td-row, .mt-line, .miss-row, .rhline, .gs-jump, .tile, tbody tr").forEach(function (row) {
      var text = (row.textContent || "").replace(/\s+/g, " ").trim();
      if (!text || PLACE.test(text)) return;
      n++;
    });
    return n;
  }
  function isQuiet(el) {
    if (!el || el.nodeType !== 1) return true;
    if (el.id === "hhqFocus" || el.id === "uxHero" || el.id === "hhqToday") return false;
    if (el.classList && el.classList.contains("ux-sec")) return true;
    var badge = el.querySelector(".badge");
    var badgeN = badge ? parseInt(badge.textContent, 10) : null;
    var countEl = el.id === "mtMgrHome" ? el.querySelector("b") : null;
    return cardIsEmpty({
      id: el.id,
      rows: realRows(el),
      badge: badge && (badge.classList.contains("zero") || badgeN === 0) ? 0 : (badge ? badgeN : null),
      count: countEl ? parseInt(countEl.textContent, 10) || 0 : null,
      text: (el.textContent || "").replace(/\s+/g, " ").trim(),
      controls: !!el.querySelector("input, textarea, select, img, canvas, table")
    });
  }
  function titleOf(el) {
    if (el.id === "slRollup" || el.id === "slHome") {
      var heading = el.querySelector("h3, h2");
      if (heading && heading.textContent.trim()) return heading.textContent.replace(/\s+/g, " ").trim().slice(0, 72);
      return L("Sales leads", "Prospectos");
    }
    if (el.classList.contains("grid")) return L("Screens", "Pantallas");
    if (el.classList.contains("onc-home") || el.id === "oncMe") return L("On the clock", "En el reloj");
    if (el.id === "deviceNote") return L("Saved on this device", "Guardado en este aparato");
    if (el.id === "pwaInstall") return L("Install HotelHQ", "Instalar HotelHQ");
    if (el.classList.contains("fm-home")) return L("Floor map", "Mapa del piso");
    var head = el.querySelector("h2, h3");
    var text = (head ? head.textContent : el.textContent) || "";
    text = text.replace(/\s+/g, " ").trim();
    return text.slice(0, 72) || L("Details", "Detalle");
  }
  function wrap(el) {
    if (!el || el.tagName === "DETAILS") return el;
    var box = document.createElement("details");
    box.className = "hhq-fold";
    var sum = document.createElement("summary");
    sum.textContent = titleOf(el);
    box.appendChild(sum);
    box.appendChild(el);
    return box;
  }
  function meetingUrgent() {
    var feature = featureOn(S.hotel, "meetings");
    var allowed = can("meetings");
    if (!feature || !allowed) return [];
    var items = [];
    var day = document.getElementById("mtDayBanner");
    if (day) {
      [].forEach.call(day.querySelectorAll(".mt-line"), function (line, i) {
        if (i > 2) return;
        var name = ((line.querySelector("b") || {}).textContent || "").trim() || L("Meeting", "Reunión");
        var spans = [].map.call(line.querySelectorAll("span"), function (s) { return (s.textContent || "").trim(); });
        var label = L("Meeting today", "Reunión hoy") + " · " + name;
        if (spans[0]) label += " · " + spans[0];
        if (spans[1]) label += " · " + spans[1];
        items.push({ label: label, onclick: line.getAttribute("onclick") || "go('meetings')" });
      });
    }
    if (!items.length) {
      var mgr = document.getElementById("mtMgrHome");
      var n = mgr ? parseInt(((mgr.querySelector("b") || {}).textContent || "0"), 10) || 0 : 0;
      if (urgentItems({ featureMeet: true, canMeet: true, meetings: n }).some(function (it) { return it.kind === "meeting"; })) {
        items.push({ label: n + " " + L("meetings today", "reuniones hoy"), onclick: "go('meetings')" });
      }
    }
    return items;
  }
  function urgentButtons() {
    var role = S.role;
    var items = meetingUrgent();
    var where = corporatePortfolio() ? S.hotel + " · " : "";
    var pmOk = seesPm();
    urgentItems({
      overdueWo: overdueWo(),
      overduePm: pmOk ? overduePm() : 0,
      seesPm: pmOk,
      overdueTasks: overdueTasks(role),
      lateRush: lateRush(role),
      meetings: 0
    }).forEach(function (it) {
      if (it.kind === "wo") items.push({ label: it.n + " " + L("overdue work orders", "órdenes atrasadas"), onclick: "go('wo')" });
      if (it.kind === "pm") items.push({ label: it.n + " " + L("overdue work", "trabajo atrasado"), onclick: "go('pm')" });
      if (it.kind === "task") items.push({ label: it.n + " " + L("overdue tasks", "tareas atrasadas"), onclick: "go('" + (role === "GM" || role === "AGM" ? "gmc" : "check") + "')" });
      if (it.kind === "rush") items.push({ label: it.n + " " + L("overdue rush rooms", "cuartos urgentes atrasados"), onclick: "go('rushq')" });
    });
    if (where) items.forEach(function (item) { item.label = where + item.label; });
    return items;
  }
  function hotelButtons() {
    return seenHotels().map(function (code) {
      var full = (typeof HOTELS !== "undefined" && HOTELS[code]) || code;
      var parts = String(full).split(" · ");
      var row = portfolioRow(code, parts[1] || "", snapOf(code));
      return "<button type=\"button\" class=\"hhq-hotel\" onclick=\"hhqOpenHotel('" + esc(code) + "')\">" +
        "<span><b>" + esc(parts[0] || code) + "</b><small>" + esc(row.name) + "</small></span>" +
        "<span><b>" + esc(row.metric) + "</b><small>" + esc(L(row.metricEn, row.metricEs)) + "</small></span>" +
        "<span><b>" + esc(row.issues) + "</b><small>" + esc(L("Open issues", "Asuntos")) + "</small></span>" +
        "<span class=\"hhq-go\" aria-hidden=\"true\">›</span></button>";
    }).join("");
  }
  function kpiHtml(model) {
    if (model.noteEn) return "<p class=\"hhq-note\">" + esc(L(model.noteEn, model.noteEs)) + "</p>";
    if (!model.items.length) return "";
    return "<div class=\"hhq-kpis\">" + model.items.map(function (item) {
      return "<div><b>" + esc(item.n) + "</b><span>" + esc(L(item.en, item.es)) + "</span></div>";
    }).join("") + "</div>";
  }
  function buildTop(hi, search) {
    var section = document.createElement("section");
    section.id = "uxHero";
    section.className = "hhq-home";
    var today = document.createElement("div");
    today.className = "hhq-today";
    today.id = "hhqToday";
    if (hi) today.appendChild(hi);
    if (corporatePortfolio()) {
      today.insertAdjacentHTML("beforeend", "<div class=\"hhq-hotels\" id=\"hhqHotels\">" + hotelButtons() + "</div>");
    } else {
      if (can("see.allHotels") && S.hhqDrill) {
        today.insertAdjacentHTML("beforeend", "<button type=\"button\" class=\"hhq-back\" onclick=\"hhqPortfolio()\">‹ " + esc(L("All hotels", "Todos los hoteles")) + "</button>");
      }
      var model = todayModel(S.role, liveSnap());
      today.insertAdjacentHTML("beforeend", "<p class=\"hhq-day\">" + esc(L("Today", "Hoy")) + "</p>" + kpiHtml(model));
    }
    if (search) today.appendChild(search);
    section.appendChild(today);
    var urgent = urgentButtons();
    if (urgent.length) {
      var box = document.createElement("div");
      box.className = "hhq-urgent";
      box.id = "hhqUrgent";
      urgent.forEach(function (item) {
        var btn = document.createElement("button");
        btn.type = "button";
        btn.textContent = item.label;
        btn.setAttribute("onclick", item.onclick);
        box.appendChild(btn);
      });
      section.appendChild(box);
    }
    return section;
  }
  function placeActions(section, actions) {
    if (!actions.length) return;
    var grid = document.createElement("div");
    grid.className = "hhq-actions";
    grid.id = "hhqActions";
    actions.forEach(function (btn) { grid.appendChild(btn); });
    section.appendChild(grid);
  }
  function fold() {
    if (folding || typeof S === "undefined" || S.tab !== "home") return;
    var app = document.getElementById("app");
    if (!app || app.querySelector("#hhqFocus")) return;
    folding = true;
    try {
      var kids = [].slice.call(app.children);
      var hero = document.getElementById("uxHero");
      var hi = hero ? hero.querySelector(".ux-hi") : null;
      var search = hero ? hero.querySelector(".ux-search") : null;
      var actions = hero ? [].slice.call(hero.querySelectorAll(".ux-act")) : [];
      if (hero) hero.removeAttribute("id");
      var shell = document.createElement("div");
      shell.id = "hhqFocus";
      var top = buildTop(hi, search);
      placeActions(top, actions);
      shell.appendChild(top);
      var more = document.createElement("details");
      more.id = "hhqMore";
      var sum = document.createElement("summary");
      sum.textContent = L("More", "Más");
      var body = document.createElement("div");
      body.id = "hhqMoreBody";
      more.appendChild(sum);
      more.appendChild(body);
      shell.appendChild(more);
      app.insertBefore(shell, app.firstChild);
      kids.forEach(function (el) {
        if (!el.parentNode || el === shell || el.id === "hhqFocus") return;
        if (el === hero) {
          [].slice.call(hero.querySelectorAll(".ux-sec")).forEach(function (node) { node.remove(); });
          if (!(hero.textContent || "").replace(/\s+/g, "").length) { hero.remove(); return; }
        }
        if (el.classList && el.classList.contains("warn")) {
          var today = document.getElementById("hhqToday");
          if (today) today.insertBefore(el, today.children[1] || null);
          return;
        }
        if (isQuiet(el)) { el.remove(); return; }
        body.appendChild(wrap(el));
      });
    } finally { folding = false; }
  }
  function tidy() {
    if (folding || typeof S === "undefined" || S.tab !== "home") return;
    var app = document.getElementById("app");
    var body = document.getElementById("hhqMoreBody");
    if (!app || !body || !document.getElementById("hhqFocus")) return;
    var stray = [].filter.call(app.children, function (el) { return el.id !== "hhqFocus"; });
    if (!stray.length) return;
    folding = true;
    try {
      stray.forEach(function (el) {
        if (isQuiet(el)) el.remove();
        else body.appendChild(wrap(el));
      });
    } finally { folding = false; }
  }

  root.hhqOpenHotel = function (code) {
    if (!/^[A-Z0-9]+$/.test(String(code || ""))) return;
    if (!can("see.allHotels")) return;
    if (typeof HOTELS !== "undefined" && !HOTELS[code]) return;
    S.hhqDrill = 1;
    if (S.hotel !== code && typeof setHotel === "function") setHotel(code);
    else {
      if (typeof save === "function") save();
      if (typeof render === "function") render();
    }
  };
  root.hhqPortfolio = function () {
    if (!can("see.allHotels")) return;
    S.hhqDrill = 0;
    if (typeof save === "function") save();
    if (typeof render === "function") render();
  };

  var css = document.createElement("style");
  css.textContent = [
    "#hhqFocus{display:block}",
    "#uxHero.hhq-home{background:transparent;color:inherit;padding:0;margin:0}",
    ".hhq-today{background:#fff;border-radius:12px;padding:12px;margin:0 0 8px;box-shadow:0 1px 3px #0001}",
    ".hhq-day{margin:0 0 8px;font-size:13px;font-weight:800;letter-spacing:.04em;text-transform:uppercase;color:#55606f}",
    ".hhq-note{margin:0;font-weight:700}",
    ".hhq-kpis{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}",
    ".hhq-kpis div{background:#eef3fa;border-radius:10px;text-align:center;padding:8px 4px;min-width:0}",
    ".hhq-kpis b{display:block;font-size:22px;line-height:1.15}",
    ".hhq-kpis span{display:block;font-size:12px;color:#55606f;font-weight:700}",
    ".hhq-hotels{display:flex;flex-direction:column}",
    ".hhq-hotel{display:grid;grid-template-columns:minmax(0,1.5fr) .7fr .9fr auto;gap:6px;align-items:center;width:100%;text-align:left;background:#fff;border:0;border-bottom:1px solid #e6ebf2;min-height:64px;padding:8px 2px;border-radius:0}",
    ".hhq-hotel b{display:block;font-size:16px}",
    ".hhq-hotel small{display:block;color:#55606f;font-weight:650;font-size:12px;line-height:1.2}",
    ".hhq-go{font-size:22px;color:#14365d}",
    ".hhq-back{display:inline-flex;align-items:center;background:#eef3fa;border:0;border-radius:10px;min-height:44px;font-weight:800;margin:0 0 8px;padding:0 12px}",
    ".hhq-urgent{background:#fff7f2;border-radius:12px;padding:2px 8px;margin:0 0 8px}",
    ".hhq-urgent button{display:block;width:100%;text-align:left;background:transparent;border:0;border-bottom:1px solid #f0e2d6;border-radius:0;min-height:48px;font-weight:750;color:#7a2e0e;padding:8px 2px}",
    ".hhq-urgent button:last-child{border-bottom:0}",
    ".hhq-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:0 0 8px}",
    "#hhqFocus .ux-act{display:flex;flex-direction:column;align-items:flex-start;justify-content:center;gap:2px;width:100%;background:#fff;color:#14365d;border:0;border-radius:12px;min-height:76px;padding:10px;box-shadow:0 1px 3px #0001;text-align:left}",
    "#hhqFocus .ux-act .chev{display:none}",
    "#hhqFocus .ux-act .ic{font-size:22px}",
    "#hhqFocus .ux-act small{display:block;color:#55606f;font-weight:600}",
    "#hhqFocus .ux-act.pri{background:#14365d;color:#fff}",
    "#hhqFocus .ux-act.pri small{color:#e7eef8}",
    "#hhqFocus .ux-hi{color:#14365d;font-size:20px;font-weight:800;margin:0 0 6px}",
    "#hhqFocus .ux-search{width:100%;text-align:left;background:#eef3fa;color:#243044;border:0;border-radius:12px;min-height:48px;margin:8px 0 0}",
    "#hhqMore{background:#fff;border-radius:12px;padding:0 12px;margin:0 0 12px;box-shadow:0 1px 3px #0001}",
    "#hhqMore > summary{min-height:48px;display:flex;align-items:center;font-weight:800;cursor:pointer}",
    ".hhq-fold{border-top:1px solid #e6ebf2}",
    ".hhq-fold > summary{min-height:48px;display:flex;align-items:center;font-weight:700;cursor:pointer}",
    ".hhq-today .warn{margin:0 0 8px}"
  ].join("");
  document.head.appendChild(css);

  var obs = new MutationObserver(function () { tidy(); });
  var watched = document.getElementById("app");
  if (watched) obs.observe(watched, { childList: true });

  setTimeout(function () {
    if (typeof render !== "function") return;
    var prev = render;
    root.render = function () {
      var result = prev.apply(this, arguments);
      try { fold(); } catch (e) {}
      return result;
    };
    try { if (typeof meUser === "function" && meUser() && S.tab === "home") fold(); } catch (e2) {}
  }, 0);
})(typeof window !== "undefined" ? window : globalThis);
