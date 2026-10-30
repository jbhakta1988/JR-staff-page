/* More is a grid of icon tiles grouped by area.
   The caller passes the screens this person can already open. This file does not
   add screens, change roles, or read another hotel's data. A tile is hidden when
   its id is not in that list. The home grid stays collapsed unless this person
   turned on "Show More expanded on home screen". */
(function (root) {
  "use strict";

  var GROUPS = [
    { id: "front_desk", en: "Front Desk", es: "Recepción", ids: ["greq", "gi", "notes", "comp", "lf", "recs", "notice", "parking", "shut", "brief", "find"] },
    { id: "housekeeping", en: "Housekeeping", es: "Ama de llaves", ids: ["rooms", "myrooms", "insp", "esc", "rushq", "check", "ckhub", "lreq", "dc", "floors"] },
    { id: "maintenance", en: "Maintenance", es: "Mantenimiento", ids: ["wo", "pm", "equip", "pmsch", "walk", "inv", "order", "logs", "qimp", "winter"] },
    { id: "sales", en: "Sales & Events", es: "Ventas y eventos", ids: ["slead", "sleads", "meetings"] },
    { id: "team", en: "Team", es: "Equipo", ids: ["team", "my", "sched", "line", "onb", "pts", "goals", "qotd", "fun", "celebr", "about", "avatar", "avcredits", "photos"] },
    { id: "admin", en: "Admin & Reports", es: "Administración y reportes", ids: ["labor", "lplan", "lcmd", "onclock", "trreq", "fc", "health", "score", "gscores", "gmc", "rules", "crep", "audit", "alog", "settings"] }
  ];

  var ICONS = {
    home: "home", team: "users", rooms: "bed", insp: "search", wo: "wrench", pm: "calendar",
    equip: "wrench", pmsch: "calendar", notes: "file", check: "check", walk: "walk", inv: "package",
    order: "cart", labor: "clock", fc: "trendUp", gmc: "clipboard", my: "user", myrooms: "bed",
    lf: "bag", esc: "flag", rules: "gear", line: "clipboard", lreq: "inbox", shut: "bus",
    sched: "calendar", health: "trendDown", score: "broom", pts: "star", photos: "camera",
    qotd: "bulb", goals: "target", about: "user", fun: "spark", celebr: "spark", avatar: "user",
    avcredits: "file", comp: "mail", gi: "bell", recs: "pin", rushq: "zap", brief: "sun",
    lplan: "calendar", trreq: "grad", lcmd: "bars", onclock: "clock", onb: "grad", winter: "snow",
    meetings: "calendar", alog: "list", parking: "pin", slead: "handshake", sleads: "list",
    floors: "map", gscores: "trendUp", settings: "gear", ckhub: "clipboard", greq: "bell",
    find: "search", logs: "clipboard", notice: "file", dc: "broom", crep: "bars", audit: "eye",
    qimp: "inbox", help: "help"
  };

  var EXTRA = {
    snow: '<path d="M12 2v20M4.9 4.9l14.2 14.2M19.1 4.9 4.9 19.1M2 12h20"/><path d="m8 4 4 3 4-3M8 20l4-3 4 3M4 8l3 4-3 4M20 8l-3 4 3 4"/>',
    handshake: '<path d="m11 17 2 2a2 2 0 0 0 3 0l3.5-3.5a2 2 0 0 0 0-3L16 9"/><path d="m8 14-3.5 3.5a2 2 0 0 0 0 3L8 21"/><path d="M7 14.5 3.5 11a2 2 0 0 1 0-3L7 4.5"/><path d="m14 8 3.5-3.5a2 2 0 0 1 3 0L22 6"/><path d="M8 13l3-3 5 5"/>'
  };

  function ensureIcons() {
    if (!root.HHQIcons && typeof require === "function") {
      try { require("./icons.js"); } catch (e) {}
    }
    if (root.HHQIcons && root.HHQIcons.PATHS) {
      Object.keys(EXTRA).forEach(function (name) {
        if (!root.HHQIcons.PATHS[name]) root.HHQIcons.PATHS[name] = EXTRA[name];
      });
    }
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c];
    });
  }
  function langNow(lang) {
    if (lang === "es" || lang === "en") return lang;
    return (typeof LANG !== "undefined" && LANG === "es") ? "es" : "en";
  }
  function safeId(id) {
    return /^[a-z][a-z0-9_]{0,40}$/.test(String(id || "")) ? String(id) : "";
  }
  function enName(id) {
    if (typeof M !== "undefined" && M[id] && M[id][1]) return String(M[id][1]);
    return String(id || "");
  }
  function label(id, lang) {
    var en = enName(id);
    if (langNow(lang) === "es" && typeof I18N !== "undefined" && I18N.es && I18N.es[en] != null) return I18N.es[en];
    if (lang == null && typeof t === "function") return t(en);
    return en;
  }
  function iconSvg(id) {
    ensureIcons();
    var name = ICONS[id] || "list";
    if (root.HHQIcons && typeof root.HHQIcons.svg === "function") {
      return root.HHQIcons.svg(name) || root.HHQIcons.svg("list") || "";
    }
    return "";
  }
  function groupsFor(ids) {
    var allow = {};
    (ids || []).forEach(function (id) {
      if (safeId(id) && id !== "home") allow[id] = true;
    });
    var used = {};
    var out = GROUPS.map(function (group) {
      var items = group.ids.filter(function (id) {
        if (!allow[id] || used[id]) return false;
        used[id] = true;
        return true;
      });
      return { id: group.id, en: group.en, es: group.es, items: items };
    }).filter(function (group) { return group.items.length; });
    var rest = Object.keys(allow).filter(function (id) { return !used[id]; });
    if (rest.length) out.push({ id: "more", en: "More", es: "Más", items: rest });
    return out;
  }
  function bothKeys(id) {
    var en = enName(id);
    var es = (typeof I18N !== "undefined" && I18N.es && I18N.es[en]) || en;
    return (en + " " + es + " " + label(id, "en") + " " + label(id, "es")).toLowerCase();
  }
  function tileHtml(id, lang) {
    id = safeId(id);
    if (!id) return "";
    var text = label(id, lang);
    return '<button type="button" class="more-tile" data-id="' + id + '" data-k="' + esc(bothKeys(id)) + '" onclick="if(window.uxClose)uxClose();go(\'' + id + '\')"><span class="more-ic" aria-hidden="true">' + iconSvg(id) + '</span><span class="more-lb">' + esc(text) + "</span></button>";
  }
  function helpTile(lang) {
    var es = langNow(lang) === "es";
    var text = es ? "Ayuda y recorrido" : "Help & tour";
    return '<button type="button" class="more-tile" data-id="help" data-k="help tour ayuda recorrido" onclick="if(window.uxClose)uxClose();if(window.uxTour)uxTour(1)"><span class="more-ic" aria-hidden="true">' + iconSvg("help") + '</span><span class="more-lb">' + esc(text) + "</span></button>";
  }
  function gridHtml(ids, lang, opts) {
    opts = opts || {};
    var es = langNow(lang) === "es";
    var groups = groupsFor(ids);
    var admin = false;
    var html = groups.map(function (group) {
      var help = opts.help && group.id === "admin";
      if (group.id === "admin") admin = true;
      return '<section class="more-group" data-group="' + group.id + '"><h3 class="more-sec">' + esc(es ? group.es : group.en) + '</h3><div class="more-tiles">' +
        group.items.map(function (id) { return tileHtml(id, lang); }).join("") +
        (help ? helpTile(lang) : "") +
        "</div></section>";
    }).join("");
    if (opts.help && !admin) {
      html += '<section class="more-group" data-group="admin"><h3 class="more-sec">' + esc(es ? "Administración y reportes" : "Admin & Reports") + '</h3><div class="more-tiles">' + helpTile(lang) + "</div></section>";
    }
    return html;
  }
  function visibleIds() {
    var ids = [];
    try {
      if (typeof root.uxAllowed === "function") ids = root.uxAllowed();
      else if (typeof rIds === "function") ids = rIds();
    } catch (e) { ids = []; }
    var seen = {};
    return (ids || []).filter(function (id) {
      if (!safeId(id) || id === "home" || seen[id]) return false;
      seen[id] = true;
      return true;
    });
  }
  function expanded() {
    try {
      if (typeof moreExpandedOf === "function") return !!moreExpandedOf(typeof meUser === "function" ? meUser() : null);
    } catch (e) {}
    return false;
  }
  function setExpanded(on) {
    if (typeof setMoreExpanded === "function") setMoreExpanded(!!on);
  }
  function settingText(lang) {
    return langNow(lang) === "es"
      ? "Mostrar Más expandido en la pantalla de inicio"
      : "Show More expanded on home screen";
  }
  function settingHtml(lang) {
    return '<label class="more-pref"><input type="checkbox" class="more-pref-input"' + (expanded() ? " checked" : "") + ' onchange="HHQMore.setExpanded(this.checked)"><span>' + esc(settingText(lang)) + "</span></label>";
  }
  function homeHtml() {
    return '<div id="moreTiles" class="more-home">' + settingHtml() + gridHtml(visibleIds(), null, { help: true }) + "</div>";
  }
  function sheetHtml() {
    var es = langNow() === "es";
    return "<h3>" + esc(es ? "Más" : "More") + "</h3>" +
      '<input id="uxMq" placeholder="' + esc(es ? "Filtrar…" : "Filter…") + '" oninput="uxFilt(this.value)">' +
      settingHtml() +
      '<div class="more-sheet-grid">' + gridHtml(visibleIds(), null, { help: true }) + "</div>";
  }
  function filter(q) {
    if (typeof document === "undefined") return;
    q = String(q || "").toLowerCase();
    var host = document.querySelector(".ux-more") || document;
    host.querySelectorAll(".more-group").forEach(function (group) {
      var shown = 0;
      group.querySelectorAll(".more-tile").forEach(function (btn) {
        var hit = !q || String(btn.getAttribute("data-k") || "").indexOf(q) >= 0;
        btn.hidden = !hit;
        if (hit) shown += 1;
      });
      group.hidden = shown === 0;
    });
  }

  var api = {
    GROUPS: GROUPS,
    groupsFor: groupsFor,
    label: label,
    iconSvg: iconSvg,
    tileHtml: tileHtml,
    htmlFor: gridHtml,
    settingText: settingText,
    settingHtml: settingHtml,
    homeHtml: homeHtml,
    sheetHtml: sheetHtml,
    expanded: expanded,
    setExpanded: setExpanded,
    filter: filter,
    visibleIds: visibleIds
  };
  root.HHQMore = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof document === "undefined") return;

  if (typeof I18N !== "undefined" && I18N.es) {
    if (!I18N.es["Sales & Events"]) I18N.es["Sales & Events"] = "Ventas y eventos";
    if (!I18N.es["Admin & Reports"]) I18N.es["Admin & Reports"] = "Administración y reportes";
    if (!I18N.es["Show More expanded on home screen"]) I18N.es["Show More expanded on home screen"] = "Mostrar Más expandido en la pantalla de inicio";
    if (!I18N.es["Help & tour"]) I18N.es["Help & tour"] = "Ayuda y recorrido";
  }

  function mountDesk() {
    var foot = document.getElementById("sbFoot");
    if (!foot) return;
    var btn = document.getElementById("uxDeskMore");
    if (!btn) {
      btn = document.createElement("button");
      btn.id = "uxDeskMore";
      btn.type = "button";
      btn.className = "btn2";
      btn.onclick = function () { if (root.uxSheet) root.uxSheet("more"); };
      foot.insertBefore(btn, foot.firstChild);
    }
    var es = langNow() === "es";
    btn.hidden = !(typeof rMode === "function" && rMode() === "desk");
    btn.innerHTML = iconSvg("menu") + "<span></span>";
    btn.querySelector("span").textContent = es ? "Más" : "More";
    btn.setAttribute("aria-label", es ? "Más" : "More");
  }

  var css = document.createElement("style");
  css.textContent = [
    ".more-pref{display:flex;align-items:flex-start;gap:10px;min-height:48px;margin:4px 0 12px;font-weight:700;line-height:1.35}",
    ".more-pref input{width:22px;height:22px;min-height:22px;margin-top:2px;flex:none}",
    ".more-sec{margin:14px 0 8px;font-size:12px;font-weight:800;letter-spacing:.04em;text-transform:uppercase;color:var(--muted,#5c6570)}",
    ".more-tiles{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}",
    ".more-tile{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;width:100%;min-height:92px;padding:8px 6px;border:1px solid var(--line,#e6e8ee);background:var(--surface,#fff);color:var(--ink,#1c1f26);border-radius:12px;box-shadow:var(--shadow,0 1px 2px rgba(16,24,40,.04));font-size:12px;font-weight:750;line-height:1.25;text-align:center}",
    ".more-tile[hidden]{display:none}",
    ".more-ic{display:flex;align-items:center;justify-content:center;color:var(--accent,#3b5bdb)}",
    ".more-ic svg,.more-ic .i{width:26px;height:26px}",
    ".more-lb{display:block;max-width:100%;overflow-wrap:anywhere}",
    "#uxDeskMore{width:100%;margin:0 0 8px;display:flex;align-items:center;justify-content:center;gap:8px}",
    "#uxDeskMore[hidden]{display:none}",
    "@media(min-width:1024px){",
    ".more-tiles{grid-template-columns:repeat(5,minmax(0,1fr))}",
    ".ux-more .ux-sheet{width:min(980px,100%)}",
    "}",
    "@media(min-width:1400px){.more-tiles{grid-template-columns:repeat(6,minmax(0,1fr))}}"
  ].join("");
  document.head.appendChild(css);

  if (typeof render === "function") {
    var prev = render;
    root.render = function () {
      var result = prev.apply(this, arguments);
      try { mountDesk(); } catch (e) {}
      return result;
    };
  }
  try { mountDesk(); } catch (e2) {}
})(typeof window !== "undefined" ? window : globalThis);
