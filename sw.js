/* HotelHQ service worker. Register with scope /JR-staff-page/.
   The ack action opens /JR-staff-page/?ack=<alert_id> and does not call the API. */
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
    tag: raw.tag || nested.tag || "",
    alert_id: alertId == null ? null : alertId,
    lang: raw.lang || nested.lang || ""
  };
}

function absUrl(url) {
  try { return new URL(url, self.registration.scope).href; }
  catch (e) { return self.registration.scope; }
}

function appUrl(alertId) {
  var origin = new URL(self.registration.scope).origin;
  var u = new URL("/JR-staff-page/", origin);
  if (alertId != null && alertId !== "") u.searchParams.set("ack", String(alertId));
  return u.href;
}

async function storedLang(fallback) {
  var lang = await idbGet("lang");
  if (lang === "es" || lang === "en") return lang;
  return fallback === "es" ? "es" : "en";
}

async function showPush(event) {
  var payload = readPayload(event);
  var lang = await storedLang(payload.lang);
  var title = payload.title || "HotelHQ";
  var hasAlert = payload.alert_id != null && payload.alert_id !== "";
  var actions = [];
  if (hasAlert) actions.push({ action: "ack", title: lang === "es" ? "Confirmar" : "Acknowledge" });
  await self.registration.showNotification(title, {
    body: payload.body || "",
    icon: "icon-192.png",
    badge: "icon-192.png",
    tag: payload.tag || (hasAlert ? "alert-" + payload.alert_id : "jr-staff"),
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
    if (typeof c.navigate === "function") {
      try {
        await c.navigate(target);
        if (typeof c.focus === "function") return c.focus();
        return;
      } catch (e) {}
    }
  }
  if (self.clients.openWindow) return self.clients.openWindow(target);
}

self.addEventListener("install", function () { self.skipWaiting(); });
self.addEventListener("activate", function (event) { event.waitUntil(self.clients.claim()); });
self.addEventListener("push", function (event) { event.waitUntil(showPush(event)); });
self.addEventListener("notificationclick", function (event) {
  event.notification.close();
  var data = event.notification.data || {};
  if (event.action === "ack") {
    event.waitUntil(openClient(appUrl(data.alert_id)));
    return;
  }
  event.waitUntil(openClient(data.url || appUrl(null)));
});
