const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const sh = require("../shuttle.js");

const NOW = "2026-10-28T22:40:00.000Z";
const sql = fs.readFileSync(path.join(__dirname, "../supabase/migrations/20261031_shuttle_signup.sql"), "utf8");
const fd = { role: "Front Desk", hotel: "MSPAM", view: "Front Desk" };
const gm = { role: "GM", hotel: "MSPAM", view: "GM" };
const corp = { role: "Above Property", hotel: null, view: "GM" };
const driver = { role: "Shuttle Driver", hotel: "MSPMS", view: "Shuttle Driver" };

function demo() { return sh.buildDemo(NOW); }
function at(hh, mm) { return sh.fromChicagoLocal("2026-10-28T" + String(hh).padStart(2, "0") + ":" + String(mm).padStart(2, "0")); }
function desk(state, actor, hotel, lang) {
  return sh.renderShuttle(state, { actor: actor, now: NOW, hotel: hotel, lang: lang || "en", ui: {} });
}

test("seeded settings, slots, and feature flag", () => {
  assert.equal(sh.chicagoDate(NOW), "2026-10-28");
  assert.equal(sh.defaultSettings("MSPAM").trackingCode, "2860");
  assert.equal(sh.defaultSettings("MSPMS").trackingCode, "2871");
  assert.equal(sh.defaultSettings("MSPAM").seatCapacity, 14);
  assert.equal(sh.defaultSettings("MSPAM").slotMinutes, 30);
  assert.equal(sh.defaultSettings("MSPAM").trackUrl, "https://www.trackmyshuttle.com/");
  const slots = sh.slotsFor(sh.defaultSettings("MSPAM"), "2026-10-28");
  assert.equal(slots.length, 37);
  assert.equal(slots[0].local, "2026-10-28T05:00");
  assert.equal(slots[slots.length - 1].local, "2026-10-28T23:00");
  assert.equal(slots[1].minute - slots[0].minute, 30);
  const state = demo();
  assert.equal(sh.featureOn(state, "MSPWE"), false);
  assert.equal(sh.featureOn(state, "MSPAM"), true);
  assert.equal(sh.featureOn(state, "MSPMS"), true);
  assert.deepEqual(sh.poolHotels(state), ["MSPAM", "MSPMS"]);
});

test("shared seats, full runs, and the 60 minute driver alert", () => {
  const state = demo();
  const soon = at(18, 0);
  const later = at(22, 0);
  assert.equal(sh.seatsLeft(state, soon).used, 5);
  assert.equal(sh.seatsLeft(state, soon).left, 9);
  assert.equal(sh.shouldAlert(soon, NOW), true);
  assert.equal(sh.shouldAlert(later, NOW), false);
  assert.equal(sh.shouldAlert(at(17, 0), NOW), false);
  const tooMany = sh.book(state, {
    hotel: "MSPAM", destination: "t1", departAt: soon, labelKind: "name",
    guestLabel: "Adams", partySize: 10, bags: 0
  }, fd, NOW);
  assert.equal(tooMany.ok, false);
  assert.equal(tooMany.error, "seats");
  const added = sh.book(state, {
    hotel: "MSPAM", destination: "t2", departAt: soon, labelKind: "name",
    guestLabel: "Adams", partySize: 9, bags: 1, flightTime: "20:40"
  }, fd, NOW);
  assert.equal(added.ok, true);
  assert.equal(added.alert, true);
  assert.equal(sh.seatsLeft(added.state, soon).full, true);
  const overflow = sh.book(added.state, {
    hotel: "MSPMS", destination: "moa", departAt: soon, labelKind: "room",
    guestLabel: "214", partySize: 1, bags: 0
  }, { role: "Front Desk", hotel: "MSPMS", view: "Front Desk" }, NOW);
  assert.equal(overflow.error, "full");
  const quiet = sh.book(state, {
    hotel: "MSPAM", destination: "t1", departAt: later, labelKind: "name",
    guestLabel: "Adams", partySize: 1, bags: 0
  }, fd, NOW);
  assert.equal(quiet.ok, true);
  assert.equal(quiet.alert, false);
  const phone = sh.book(state, {
    hotel: "MSPAM", destination: "t1", departAt: later, labelKind: "name",
    guestLabel: "5551234567", partySize: 1, bags: 0
  }, fd, NOW);
  assert.equal(phone.error, "phone");
  assert.equal(sh.book(state, {
    hotel: "MSPWE", destination: "t1", departAt: later, labelKind: "name",
    guestLabel: "Adams", partySize: 1, bags: 0
  }, { role: "Front Desk", hotel: "MSPWE" }, NOW).error, "feature");
  assert.equal(sh.canBook("Shuttle Driver"), false);
  assert.equal(sh.canBook("Housekeeper"), false);
  assert.equal(sh.canConfigure("Front Desk"), false);
  assert.equal(sh.canConfigure("GM"), true);
  assert.equal(sh.canEditUrl("GM"), false);
  assert.equal(sh.canEditUrl("JR Corporate"), true);
});

test("shared queue for both airport desks, status stamps, and ridership", () => {
  const state = demo();
  const groups = sh.pickupGroups(state.signups.filter(function (s) { return s.departAt === at(18, 0); }), sh.defaultSettings("MSPAM"));
  assert.deepEqual(groups.map(function (g) { return g.hotel; }), ["MSPAM", "MSPMS"]);
  assert.equal(groups[0].rows[0].guestLabel, "Keller (EX)");
  assert.equal(groups[1].rows[0].guestLabel, "Walsh (EX)");
  const fdHtml = desk(state, fd, "MSPAM", "en");
  assert.match(fdHtml, /id="shCode">2860</);
  assert.match(fdHtml, /Pickups: TrackMyShuttle/);
  assert.match(fdHtml, /Keller \(EX\)/);
  assert.match(fdHtml, /Walsh \(EX\)/);
  assert.match(fdHtml, /Garcia \(EX\)/);
  assert.match(fdHtml, /id="shCode-MSPMS">2871</);
  assert.doesNotMatch(fdHtml, /type="tel"|phone/i);
  assert.match(fdHtml, /9 seats left/);
  const es = desk(state, fd, "MSPAM", "es");
  assert.match(es, /Recogidas: TrackMyShuttle/);
  assert.match(es, /Copiar código/);
  assert.match(es, /id="shCode">2860</);
  const changed = sh.saveSettings(state, {
    hotel: "MSPAM", trackingCode: "9999", slotMinutes: 30, seatCapacity: 14,
    openMinute: 300, closeMinute: 1380, trackUrl: "https://example.com/shuttle",
    pickupOrder: ["MSPMS", "MSPAM"]
  }, gm);
  assert.equal(changed.ok, true);
  assert.equal(changed.state.settings.MSPAM.trackingCode, "9999");
  assert.equal(changed.state.settings.MSPMS.trackingCode, "2871");
  assert.equal(changed.state.settings.MSPAM.trackUrl, "https://www.trackmyshuttle.com/");
  assert.equal(changed.state.settings.MSPAM.pickupOrder[0], "MSPMS");
  const corpSave = sh.saveSettings(changed.state, {
    hotel: "MSPMS", trackingCode: "2871", slotMinutes: 30, seatCapacity: 16,
    openMinute: 300, closeMinute: 1380, trackUrl: "https://www.trackmyshuttle.com/guest",
    pickupOrder: ["MSPAM", "MSPMS"]
  }, corp);
  assert.equal(corpSave.ok, true);
  assert.equal(corpSave.state.settings.MSPAM.trackUrl, "https://www.trackmyshuttle.com/guest");
  assert.equal(corpSave.state.settings.MSPAM.seatCapacity, 16);
  assert.match(desk(changed.state, fd, "MSPAM"), /id="shCode">9999</);
  assert.doesNotMatch(desk(changed.state, fd, "MSPAM"), /id="shCode">2860</);
  const drv = desk(state, driver, "MSPMS");
  assert.match(drv, /2860/);
  assert.match(drv, /2871/);
  assert.match(drv, /Keller \(EX\)/);
  assert.match(drv, /Walsh \(EX\)/);
  assert.match(drv, /Pickup at/);
  const stamped = sh.setStatus(state, "ex5", "boarded", driver, NOW);
  assert.equal(stamped.ok, true);
  assert.equal(stamped.signup.status, "boarded");
  assert.equal(stamped.signup.boardedAt, NOW);
  assert.equal(sh.setStatus(state, "ex6", "no_show", fd, NOW).ok, true);
  assert.equal(sh.setStatus(state, "ex6", "done", { role: "Front Desk", hotel: "MSPWE" }, NOW).ok, false);
  assert.equal(sh.setStatus(state, "ex5", "done", { role: "Housekeeper", hotel: "MSPAM" }, NOW).ok, false);
  const counts = sh.ridership(state, "2026-10-28");
  const am = counts.filter(function (r) { return r.hotel === "MSPAM"; }).reduce(function (s, r) { return s + r.rode; }, 0);
  const ms = counts.filter(function (r) { return r.hotel === "MSPMS"; }).reduce(function (s, r) { return s + r.rode; }, 0);
  assert.equal(am, 3);
  assert.equal(ms, 1);
  assert.match(desk(state, gm, "MSPAM"), /Ridership today/);
  const gv = desk(state, { role: "GM", hotel: "MSPWE", view: "GM" }, "MSPWE");
  assert.match(gv, /No shuttle at this property/);
  assert.doesNotMatch(gv, /2860|2871|Keller/);
  const hk = desk(state, { role: "Housekeeper", hotel: "MSPAM", view: "Housekeeper" }, "MSPAM");
  assert.match(hk, /No shuttle at this property/);
  assert.doesNotMatch(hk, /Keller \(EX\)/);
  const note = sh.buildAlert(stamped.signup, "en");
  assert.deepEqual(note.hotels, ["MSPAM", "MSPMS"]);
  assert.deepEqual(note.roles, ["Shuttle Driver"]);
  assert.equal(note.kind, "shuttle_signup");
  assert.doesNotMatch(note.body, /Keller|214|555/);
});

test("guest code rides in the link, the share text, and the QR", () => {
  const link = sh.trackLink("https://www.trackmyshuttle.com/", "2860");
  assert.equal(link, "https://www.trackmyshuttle.com/?code=2860");
  const text = sh.shareText("en", "2860", "https://www.trackmyshuttle.com/");
  assert.match(text, /2860/);
  assert.match(text, /https:\/\/www\.trackmyshuttle\.com\/\?code=2860/);
  const es = sh.shareText("es", "2871", "https://www.trackmyshuttle.com/");
  assert.match(es, /2871/);
  assert.notEqual(es, text);
  const payload = sh.qrPayload("https://www.trackmyshuttle.com/", "2860");
  assert.match(payload, /2860/);
  assert.match(payload, /trackmyshuttle\.com\/\?code=2860/);
  assert.equal(sh.formatBits(0), 0x5412);
  const matrix = sh.qrMatrix(payload);
  assert.equal(matrix.length, 21 + 4 * (5 - 1));
  assert.equal(matrix[0].length, matrix.length);
  assert.equal(matrix[0][0], true);
  const park = sh.draftFromParking({ id: "am-v3", hotel: "MSPAM", room: "", pfConfirm: "SAMPLE1", plate: "EXA2103", vehicleType: "park_fly" });
  assert.equal(park.hotel, "MSPAM");
  assert.equal(park.guestLabel, "");
  assert.equal(park.notes, "Park & Fly SAMPLE1");
  assert.equal(park.parkingVisitId, "am-v3");
  assert.equal(JSON.stringify(park).includes("EXA2103"), false);
});

test("migration is additive and keeps the shared driver queue narrow", () => {
  assert.match(sql, /hotel = any \(\(select private\.my_hotels\(\)\)::text\[\]\)/);
  assert.equal(/hotel = any \(select private\.my_hotels\(\)\)/.test(sql), false);
  assert.match(sql, /shuttle_staff_in_pool/);
  assert.match(sql, /front_desk', 'gm', 'agm', 'shuttle_driver'/);
  assert.match(sql, /hotel = any \(private\.shuttle_pool\(\)\)/);
  assert.match(sql, /No phone, billing, rate, or plate/);
  assert.match(sql, /'MSPWE', 'shuttle', false/);
  assert.match(sql, /'MSPAM', 'shuttle', true/);
  assert.match(sql, /'MSPMS', 'shuttle', true/);
  assert.match(sql, /\('MSPAM', '2860'\)/);
  assert.match(sql, /\('MSPMS', '2871'\)/);
  assert.match(sql, /https:\/\/www\.trackmyshuttle\.com\//);
  assert.match(sql, /security invoker/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /enable row level security/);
  assert.match(sql, /No phone number/);
  assert.doesNotMatch(sql, /drop table/i);
  assert.doesNotMatch(sql, /delete from/i);
  assert.equal(/anon execute/i.test(sql), false);
  assert.match(fs.readFileSync(path.join(__dirname, "../index.html"), "utf8"), /shuttle\.js/);
  const js = fs.readFileSync(path.join(__dirname, "../shuttle.js"), "utf8");
  assert.match(js, /careAlert/);
  assert.match(js, /notifications/);
  assert.doesNotMatch(js, /if \(hotel === "MSPAM"\) return "2860"/);
  assert.equal(sh.SEED_CODE.MSPAM, "2860");
  assert.equal(sh.SEED_CODE.MSPMS, "2871");
});

test("spanish phrases exist for the shuttle screen", () => {
  const same = {
    "Shuttle": 1, "Hotel": 1, "Hampton (MSPAM)": 1, "SpringHill (MSPMS)": 1, "Mall of America": 1
  };
  Object.keys(sh.PHRASES).forEach(function (en) {
    const es = sh.PHRASES[en];
    assert.equal(typeof es, "string");
    assert.ok(es.length > 0, en);
    if (!same[en]) assert.notEqual(es, en, en);
  });
  assert.notEqual(sh.PHRASES["Pickups: TrackMyShuttle"], "Pickups: TrackMyShuttle");
});
