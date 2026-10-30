/* Line-icon avatars. Same stroke as the tiles, centered on a tinted badge.
   Initials are the default. Older cartoon picks map to the nearest icon. */
(function (root) {
  "use strict";

  var ACCENTS = {
    blue: "#1d4ed8",
    teal: "#0f766e",
    amber: "#b45309",
    violet: "#6d28d9",
    green: "#166534",
    slate: "#334155"
  };
  var OPTIONS = [
    { id: "initials", icon: "", accent: "slate", en: "Initials", es: "Iniciales" },
    { id: "key", icon: "key", accent: "amber", en: "Key", es: "Llave" },
    { id: "bell", icon: "bell", accent: "blue", en: "Bell", es: "Campana" },
    { id: "bed", icon: "bed", accent: "teal", en: "Bed", es: "Cama" },
    { id: "coffee", icon: "coffee", accent: "amber", en: "Coffee", es: "Café" },
    { id: "star", icon: "star", accent: "violet", en: "Star", es: "Estrella" },
    { id: "sun", icon: "sun", accent: "amber", en: "Sun", es: "Sol" },
    { id: "leaf", icon: "leaf", accent: "green", en: "Leaf", es: "Hoja" },
    { id: "wrench", icon: "wrench", accent: "slate", en: "Wrench", es: "Llave inglesa" },
    { id: "spark", icon: "spark", accent: "violet", en: "Sparkles", es: "Destellos" },
    { id: "pin", icon: "pin", accent: "blue", en: "Map pin", es: "Pin de mapa" },
    { id: "heart", icon: "heart", accent: "violet", en: "Heart", es: "Corazón" },
    { id: "briefcase", icon: "briefcase", accent: "slate", en: "Briefcase", es: "Maletín" },
    { id: "clock", icon: "clock", accent: "blue", en: "Clock", es: "Reloj" },
    { id: "clipboard", icon: "clipboard", accent: "teal", en: "Clipboard", es: "Portapapeles" },
    { id: "users", icon: "users", accent: "green", en: "Team", es: "Equipo" }
  ];
  var BY_ID = {};
  OPTIONS.forEach(function (opt) { BY_ID[opt.id] = opt; });
  var ROLE_ICON = {
    hk: "bed", hp: "pin", ld: "spark", sup: "briefcase", mt: "wrench", mtt: "wrench",
    fd: "bell", na: "star", bk: "coffee", bar: "coffee", drv: "pin", gm: "briefcase",
    agm: "key", sales: "briefcase"
  };
  var PIN_ICON = {
    star: "star", heart: "heart", sparkle: "spark", wrench: "wrench", trophy: "star",
    flame: "sun", clock: "clock", shine: "spark", crown: "star"
  };
  var STYLE_ICON = { bottts: "wrench", "bottts-neutral": "wrench", shapes: "spark", glass: "spark", "fun-emoji": "star" };

  function choiceOf(id) {
    return BY_ID[id] || BY_ID.initials;
  }
  function mapChoice(saved) {
    if (!saved || typeof saved !== "object") return { icon: "initials", accent: "slate" };
    if (saved.v === 2 && (saved.icon === "initials" || BY_ID[saved.icon])) {
      var keep = choiceOf(saved.icon);
      return { icon: keep.id, accent: ACCENTS[saved.accent] ? saved.accent : keep.accent };
    }
    var icon = PIN_ICON[saved.pin] || ROLE_ICON[saved.role] || STYLE_ICON[saved.style] || "initials";
    return { icon: icon, accent: choiceOf(icon).accent };
  }
  function initialsOf(name) {
    var parts = String(name || "").trim().split(/\s+/).filter(Boolean);
    var a = (parts[0] || "?").charAt(0);
    var b = parts.length > 1 ? parts[parts.length - 1].charAt(0) : "";
    return (a + b).toUpperCase();
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c];
    });
  }
  function iconSvg(name, size) {
    if (!name || !root.HHQIcons || !HHQIcons.svg) return "";
    return HHQIcons.svg(name).replace('width="1em"', 'width="' + size + '"').replace('height="1em"', 'height="' + size + '"');
  }
  function badgeHtml(choice, name, size) {
    choice = choiceOf(choice && choice.icon);
    size = Math.max(24, Math.min(96, Number(size) || 36));
    var color = ACCENTS[choice.accent] || ACCENTS.slate;
    var radius = size >= 48 ? 14 : 10;
    var inner = choice.icon
      ? iconSvg(choice.icon, Math.round(size * 0.52))
      : '<b style="font-size:' + Math.round(size * 0.36) + 'px;letter-spacing:-.03em">' + esc(initialsOf(name)) + "</b>";
    return '<span class="hhq-av" style="width:' + size + "px;height:" + size + "px;border-radius:" + radius + "px;background:color-mix(in srgb," + color + " 14%,#fff);color:" + color + '">' + inner + "</span>";
  }

  var api = {
    ACCENTS: ACCENTS,
    OPTIONS: OPTIONS,
    mapChoice: mapChoice,
    initialsOf: initialsOf,
    badgeHtml: badgeHtml
  };
  root.HHQAv = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof document === "undefined") return;

  function L(en, es) { return (typeof LANG !== "undefined" && LANG === "es") ? es : en; }
  function keyFor(id) { return "jravatar_" + (id || "x"); }
  function readRaw(id) {
    try { return JSON.parse(localStorage.getItem(keyFor(id)) || "null"); } catch (e) { return null; }
  }
  function userByName(name) {
    if (!name || typeof USERS === "undefined") return null;
    var exact = null;
    var loose = null;
    USERS.forEach(function (user) {
      if (!user || !user.name) return;
      if (user.name === name) exact = user;
      else if (!loose && user.name.indexOf(name) === 0) loose = user;
    });
    return exact || loose;
  }
  function storedChoice(id) {
    return mapChoice(readRaw(id));
  }
  function mineChoice() {
    var me = typeof meUser === "function" ? meUser() : null;
    return storedChoice(me && me.id);
  }
  function html(name, size, cfg) {
    var choice;
    var label = name;
    if (cfg) choice = mapChoice(cfg);
    else if (name) {
      var user = userByName(name);
      choice = user ? storedChoice(user.id) : { icon: "initials", accent: "slate" };
      label = user ? user.name : name;
    } else {
      var me = typeof meUser === "function" ? meUser() : null;
      choice = mineChoice();
      label = me && me.name;
    }
    return badgeHtml(choice, label, size);
  }
  api.html = html;
  root.avHTML = html;
  root.initialsHTML = function (name, size) { return badgeHtml({ icon: "initials", accent: "slate" }, name, size); };
  root.avConfig = function (name) {
    if (name) {
      var user = userByName(name);
      return user ? Object.assign({ v: 2 }, storedChoice(user.id)) : { v: 2, icon: "initials", accent: "slate" };
    }
    return Object.assign({ v: 2 }, mineChoice());
  };

  var draft = null;
  function pickerHtml() {
    var me = typeof meUser === "function" ? meUser() : null;
    if (!draft) draft = Object.assign({ v: 2 }, mineChoice());
    var name = me && me.name;
    var buttons = OPTIONS.map(function (opt) {
      var on = draft.icon === opt.id;
      return '<button type="button" class="av-opt' + (on ? " on" : "") + '" onclick="HHQAvPick(\'' + opt.id + '\')" aria-pressed="' + on + '">' +
        badgeHtml(opt, name, 56) + "<small>" + esc(L(opt.en, opt.es)) + "</small></button>";
    }).join("");
    return '<div class="hhq-av-pick" id="hhqAvPick"><h2>' + esc(L("Avatar", "Avatar")) + "</h2>" +
      '<div class="card av-now">' + badgeHtml(draft, name, 72) + "<div><b>" + esc(name || "") + "</b><br><small>" + esc(L("Choose a badge. Initials are the default.", "Elige una insignia. Las iniciales son el predeterminado.")) + "</small></div></div>" +
      '<div class="av-grid">' + buttons + "</div>" +
      '<button type="button" class="btn" style="width:100%;margin-top:12px" onclick="HHQAvSave()">' + esc(L("Save", "Guardar")) + "</button></div>";
  }
  root.HHQAvPick = function (id) {
    if (!BY_ID[id]) return;
    draft = { v: 2, icon: id, accent: BY_ID[id].accent };
    if (typeof render === "function") render();
  };
  root.HHQAvSave = function () {
    var me = typeof meUser === "function" ? meUser() : null;
    if (!me) return;
    var prev = readRaw(me.id);
    var next = { v: 2, icon: draft.icon, accent: draft.accent };
    if (prev && prev.v !== 2) next.legacy = prev;
    else if (prev && prev.legacy) next.legacy = prev.legacy;
    try { localStorage.setItem(keyFor(me.id), JSON.stringify(next)); } catch (e) {}
    if (root.sb && sb.rpc) sb.rpc("set_my_avatar", { p: next }).catch(function () {});
    draft = null;
    if (typeof go === "function") go("home");
  };
  if (typeof V !== "undefined") {
    V.avatar = pickerHtml;
    if (typeof M !== "undefined" && M.avatar) M.avatar[1] = "Avatar";
  }
  if (typeof I18N !== "undefined" && I18N.es) I18N.es.Avatar = "Avatar";

  function pointsTotal() {
    try {
      if (typeof ptsTotal === "function") {
        var n = ptsTotal();
        return n == null || !isFinite(Number(n)) ? null : Number(n);
      }
    } catch (e) {}
    return null;
  }
  function chromeHtml() {
    var me = typeof meUser === "function" ? meUser() : null;
    if (!me) return "";
    var pts = pointsTotal();
    var ptsBtn = pts == null ? "" : '<button type="button" class="hhq-pts-badge" onclick="go(\'pts\')" aria-label="' + esc(L("Points & Rewards", "Puntos y premios")) + '">' +
      iconSvg("star", 16) + "<b>" + esc(String(pts)) + "</b></button>";
    return '<span class="hhq-you">' +
      '<button type="button" class="hhq-av-btn" onclick="go(\'avatar\')" aria-label="' + esc(L("Avatar", "Avatar")) + '">' + html(null, 36) + "</button>" +
      ptsBtn + "</span>";
  }
  function paintChrome() {
    var me = typeof meUser === "function" ? meUser() : null;
    ["hav", "sav"].forEach(function (id) {
      var node = document.getElementById(id);
      if (!me && node) node.remove();
    });
    if (!me) return;
    var htmlYou = chromeHtml();
    var bar = document.getElementById("hbar");
    var hbt = document.getElementById("hbt");
    if (bar && hbt) {
      var slot = document.getElementById("hav");
      if (!slot) {
        slot = document.createElement("span");
        slot.id = "hav";
        bar.insertBefore(slot, hbt);
      }
      slot.innerHTML = htmlYou;
    }
    var side = document.querySelector("#side .sb-top");
    if (side) {
      var sideSlot = document.getElementById("sav");
      if (!sideSlot) {
        sideSlot = document.createElement("div");
        sideSlot.id = "sav";
        var name = document.getElementById("hname2") || side;
        side.insertBefore(sideSlot, name);
      }
      sideSlot.innerHTML = htmlYou;
    }
  }
  if (typeof render === "function") {
    var prev = render;
    root.render = function () {
      var out = prev.apply(this, arguments);
      try { paintChrome(); } catch (e) {}
      return out;
    };
  }

  var css = document.createElement("style");
  css.textContent = [
    ".hhq-av{display:inline-flex;align-items:center;justify-content:center;flex:none;box-sizing:border-box;line-height:0}",
    ".hhq-av svg{width:52%;height:52%;display:block}",
    ".hhq-you{display:inline-flex;align-items:center;gap:6px;flex:none}",
    ".hhq-av-btn{padding:0;border:0;background:transparent;min-height:36px;width:36px}",
    ".hhq-pts-badge{display:inline-flex;align-items:center;gap:4px;min-height:32px;padding:0 10px;border-radius:999px;border:1px solid #e6e8ee;background:#fff;color:#1c1f26;font-weight:750}",
    ".hhq-pts-badge svg{width:16px;height:16px;color:#b45309}",
    "#hbar .hhq-you{margin-right:4px}",
    "#sav{padding:0 12px 8px}",
    "#sav .hhq-you{width:100%}",
    ".av-now{display:flex;align-items:center;gap:12px}",
    ".av-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:12px}",
    ".av-opt{display:flex;flex-direction:column;align-items:center;gap:6px;padding:8px 4px;border:1px solid #e6e8ee;border-radius:14px;background:#fff;min-height:96px}",
    ".av-opt.on{border-color:#1d4ed8;box-shadow:0 0 0 3px rgba(29,78,216,.18)}",
    ".av-opt small{font-size:11px;font-weight:700;line-height:1.2;text-align:center}",
    "#qotd.card{background:#fff;border:1px solid #e6e8ee}",
    "#hhqPts .card{background:#fff}",
    "#hhqPts .card[onclick]{background:#fff!important;border:1px solid #e6e8ee;box-shadow:0 1px 2px rgba(16,24,40,.04)}",
    "#hhqPts table{width:100%}",
    "#hhqPts button{border-radius:10px}",
    "#hhqPts .card>b{display:block;margin-bottom:6px}",
    "@media(max-width:767px){.av-grid{grid-template-columns:repeat(3,minmax(0,1fr))}}",
    "@media(prefers-reduced-motion:reduce){#qotd *,#ptsToast,.hhq-pts-badge{animation:none!important;transition:none!important}}"
  ].join("");
  document.head.appendChild(css);
})(typeof window !== "undefined" ? window : globalThis);
