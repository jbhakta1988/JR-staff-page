/* Per-hotel module switches.
   parking, sales_leads, greetings, and guest_scores share one list.
   A missing row stays on. Parking at MSPWE starts off.
   JR Corporate changes the switches. Other modules call HotelFeatures.on(hotel, id). */
(function (root) {
  "use strict";

  var HOTELS = ["MSPWE", "MSPAM", "MSPMS"];
  var FEATURES = [
    { id: "parking", en: "Parking", es: "Estacionamiento" },
    { id: "sales_leads", en: "Sales leads", es: "Prospectos de ventas" },
    { id: "greetings", en: "Greetings", es: "Saludos" },
    { id: "guest_scores", en: "Guest scores", es: "Calificaciones de huéspedes" }
  ];
  var FEATURE_OK = {};
  FEATURES.forEach(function (f) { FEATURE_OK[f.id] = 1; });

  function defaultOn(hotel, feature) {
    if (!FEATURE_OK[feature] || HOTELS.indexOf(hotel) < 0) return false;
    if (feature === "parking" && hotel === "MSPWE") return false;
    return true;
  }
  function key(hotel, feature) { return hotel + "|" + feature; }

  var api = {
    HOTELS: HOTELS,
    FEATURES: FEATURES,
    defaultOn: defaultOn,
    on: defaultOn
  };
  root.HotelFeatures = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof document === "undefined") return;

  var KEY = "jrportal_hotel_features_v1";
  var remote = null;
  var remoteState = "";

  function esc(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[c];
    });
  }
  function L(en, es) { return (typeof LANG !== "undefined" && LANG === "es") ? es : en; }
  function corporate() {
    var role = "";
    try { role = authRole(); } catch (e) { role = ""; }
    return role === "Above Property" || role === "JR Corporate";
  }
  function remoteOn() {
    return typeof useRemote === "function" && !!useRemote() && typeof sb !== "undefined" && sb;
  }
  function readBag() {
    try {
      var data = JSON.parse(localStorage.getItem(KEY) || "null");
      if (!data || data.v !== 1 || !data.rows) return {};
      return data.rows;
    } catch (e) { return {}; }
  }
  function writeBag(rows) {
    try { localStorage.setItem(KEY, JSON.stringify({ v: 1, rows: rows })); } catch (e) {}
  }
  function ensureRemote() {
    if (!remoteOn() || remoteState === "loading" || remoteState === "ready") return;
    remoteState = "loading";
    sb.from("hotel_features").select("hotel,feature,enabled").then(function (res) {
      remote = {};
      if (!res.error) (res.data || []).forEach(function (row) { remote[key(row.hotel, row.feature)] = !!row.enabled; });
      remoteState = "ready";
      if (typeof render === "function") render();
    }, function () { remoteState = "ready"; remote = {}; });
  }
  function on(hotel, feature) {
    if (remoteOn()) ensureRemote();
    var id = key(hotel, feature);
    if (remoteOn() && remote && Object.prototype.hasOwnProperty.call(remote, id)) return !!remote[id];
    if (!remoteOn()) {
      var bag = readBag();
      if (Object.prototype.hasOwnProperty.call(bag, id)) return !!bag[id];
    }
    return defaultOn(hotel, feature);
  }
  api.on = on;
  function setOn(hotel, feature, enabled) {
    if (!corporate() || !FEATURE_OK[feature] || HOTELS.indexOf(hotel) < 0) return;
    enabled = !!enabled;
    if (remoteOn()) {
      sb.rpc("set_hotel_feature", { p_hotel: hotel, p_feature: feature, p_enabled: enabled }).then(function () {
        remote = remote || {};
        remote[key(hotel, feature)] = enabled;
        if (feature === "parking" && root.Parking && root.Parking.noteModule) root.Parking.noteModule(hotel, enabled);
        if (typeof render === "function") render();
      });
      return;
    }
    var bag = readBag();
    bag[key(hotel, feature)] = enabled;
    writeBag(bag);
    if (feature === "parking" && root.Parking && root.Parking.noteModule) root.Parking.noteModule(hotel, enabled);
    if (typeof render === "function") render();
  }
  root.hfSet = function (hotel, feature, enabled) { setOn(hotel, feature, enabled); };

  function cardHtml() {
    if (!corporate()) return "";
    var blocks = HOTELS.map(function (hotel) {
      var rows = FEATURES.map(function (feature) {
        var checked = on(hotel, feature.id) ? " checked" : "";
        return "<label class=\"hf-row\"><input type=\"checkbox\"" + checked + " onchange=\"hfSet('" + hotel + "','" + feature.id + "',this.checked)\"> " +
          esc(L(feature.en, feature.es)) + "</label>";
      }).join("");
      return "<section class=\"hf-hotel\"><h3>" + esc(hotel) + "</h3>" + rows + "</section>";
    }).join("");
    return "<div class=\"card raw hf\" id=\"hfCard\"><h3>" + esc(L("Hotel features", "Módulos del hotel")) + "</h3><p class=\"hf-note\">" +
      esc(L("JR Corporate can turn a whole module off for one hotel.", "JR Corporate puede apagar un módulo entero en un hotel.")) + "</p>" + blocks + "</div>";
  }

  if (typeof V !== "undefined" && V.home) {
    var prevHome = V.home;
    V.home = function () {
      var card = "";
      try { card = cardHtml(); } catch (e) { card = ""; }
      return card + prevHome.apply(this, arguments);
    };
  }
  var style = document.createElement("style");
  style.textContent = ".hf-note{font-size:13px;color:#3c4658}.hf-hotel{margin-top:8px}.hf-row{display:flex;align-items:center;gap:8px;min-height:44px;font-weight:700}.hf-row input{width:22px;height:22px;min-height:0}";
  document.head.appendChild(style);
  if (typeof render === "function") {
    var prevRender = render;
    root.render = function () {
      var result = prevRender.apply(this, arguments);
      try {
        var card = document.getElementById("hfCard");
        var app = document.getElementById("app");
        if (card && app && typeof S !== "undefined" && S.tab === "home" && app.firstChild !== card) app.insertAdjacentElement("afterbegin", card);
      } catch (e) {}
      return result;
    };
  }
  try { if (typeof meUser === "function" && meUser() && typeof render === "function") render(); } catch (e) {}
})(typeof window !== "undefined" ? window : globalThis);
