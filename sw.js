/* JR Staff Portal service worker. Register with scope /JR-staff-page/. */
var SB_PUSH_URL = "https://clxvmtbmveusrbxacnxe.supabase.co/rest/v1/rpc/acknowledge_alert";
var SB_PUSH_KEY = "sb_publishable_ehDhAPcG-9jVDXx1FU_5PQ_QYb9YP77";

function idbGet(key) {
  return new Promise(function (resolve) {
    var req = indexedDB.open("jr-staff-push", 1);
    req.onupgradeneeded = function () {
      var db = req.result;
      if (!db.objectStoreNames.contains("kv")) db.createObjectStore("kv");
    };
    req.onerror = function () { resolve(null); };
    req.onsuccess = function () {
      var db = req.result;
      try {
        var tx = db.transaction("kv", "readonly");
        var get = tx.objectStore("kv").get(key);
        get.onsuccess = function () { resolve(get.result == null ? null : get.result); };
        get.onerror = function () { resolve(null); };
      } catch (e) { resolve(null); }
    };
  });
}

function rpcAlertId(id) {
  if (typeof id === "number") return id;
  if (typeof id === "string" && /^-?\d+$/.test(id)) return Number(id);
  return id;
}

function readPayload(event) {
  var raw = {};
  if (event.data) {
    try { raw = event.data.json() || {}; }
    catch (e) { raw = { body: event.data.text ? event.data.text() : "" }; }
  }
  var nested = raw.data && typeof raw.data === "object" ? raw.data : {};
  var note = raw.notification && typeof raw.notification === "object" ? raw.notification : {};
  var alertId = raw.alert_id != null ? raw.alert_id : nested.alert_id;
  return {
    title: raw.title || note.title || "",
    body: raw.body || note.body || nested.body || "",
    url: raw.url || nested.url || note.url || "",
    alert_id: alertId == null ? null : alertId,
    lang: raw.lang || nested.lang || ""
  };
}

function absUrl(url) {
  try { return new URL(url, self.registration.scope).href; }
  catch (e) { return self.registration.scope; }
}

function appAlertUrl(data) {
  var u = new URL("./", self.registration.scope);
  if (data && data.alert_id != null && data.alert_id !== "") u.searchParams.set("alert", String(data.alert_id));
  return u.href;
}

async function storedLang(fallback) {
  var lang = await idbGet("lang");
  if (lang === "es" || lang === "en") return lang;
  var session = await idbGet("session");
  if (session && (session.lang === "es" || session.lang === "en")) return session.lang;
  return fallback === "es" ? "es" : "en";
}

async function showPush(event) {
  var payload = readPayload(event);
  var lang = await storedLang(payload.lang);
  var title = payload.title || "JR Staff Portal";
  var actions = [];
  if (payload.alert_id != null && payload.alert_id !== "") {
    actions.push({ action: "ack", title: lang === "es" ? "Confirmar" : "Acknowledge" });
  }
  await self.registration.showNotification(title, {
    body: payload.body || "",
    icon: "icon-192.png",
    badge: "icon-192.png",
    tag: payload.alert_id != null && payload.alert_id !== "" ? "alert-" + payload.alert_id : "jr-staff",
    data: { url: payload.url || "", alert_id: payload.alert_id, lang: lang },
    actions: actions
  });
}

async function openClient(url) {
  var target = absUrl(url);
  var all = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
  var origin = new URL(target).origin;
  for (var i = 0; i < all.length; i++) {
    var c = all[i];
    if (!c.url || new URL(c.url).origin !== origin) continue;
    if (typeof c.navigate === "function") { try { await c.navigate(target); } catch (e) {} }
    if (typeof c.focus === "function") return c.focus();
  }
  if (self.clients.openWindow) return self.clients.openWindow(target);
}

async function acknowledge(data) {
  data = data || {};
  var session = await idbGet("session");
  var token = session && session.access_token;
  var dest = data.url || appAlertUrl(data);
  if (!token || data.alert_id == null || data.alert_id === "") {
    await openClient(dest);
    return;
  }
  try {
    var res = await fetch(SB_PUSH_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": SB_PUSH_KEY,
        "Authorization": "Bearer " + token
      },
      body: JSON.stringify({ alert_id: rpcAlertId(data.alert_id) })
    });
    if (!res.ok) await openClient(dest);
  } catch (e) {
    await openClient(dest);
  }
}

self.addEventListener("install", function () { self.skipWaiting(); });
self.addEventListener("activate", function (event) { event.waitUntil(self.clients.claim()); });
self.addEventListener("push", function (event) { event.waitUntil(showPush(event)); });
self.addEventListener("notificationclick", function (event) {
  event.notification.close();
  var data = event.notification.data || {};
  if (event.action === "ack") {
    event.waitUntil(acknowledge(data));
    return;
  }
  event.waitUntil(openClient(data.url || appAlertUrl(data)));
});
