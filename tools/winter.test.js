const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const wn = require("../winter.js");

const EN = [
  "Train staff on where the water shutoffs are and how to shut them off. Post photos and drawings/maps near the timeclocks, in BOH, and in the emergency manual.",
  "Make sure all stairwell and vestibule heaters are working properly.",
  "Make sure all back-of-house areas have enough heat. Maintenance staff check all BOH areas daily for cold spots (DAILY). All BOH areas must stay above 40°F.",
  "Make sure all buildings are \"weather tight.\" Close all windows, doors, vents, etc. Seal any openings in exterior walls, ceilings/roofs, and floors so they aren't exposed to outside air.",
  "Insulate piping and install heat tracing lines on critical piping, which greatly lowers the risk of a pipe freeze. Facilities personnel should inspect hard-to-heat areas.",
  "Verify that all roof drains, drainpipes, and gutters are free of debris and drain properly. Complete the fall clean-up of all planting beds and planters.",
  "Check any rooms that are out of order for a long time regularly to make sure they stay heated. If the hotel has a dry sprinkler system, drain the water from the low points.",
  "Check the fire pumps and make sure the pump room has enough heat.",
  "Make sure the fire panel is fully working with no troubles.",
  "Hold PIC training with managers, front desk, auditors, and engineering staff. Discuss who is responsible for shoveling and applying ice melt, how often to do it, etc.",
  "Flush and winterize the outdoor lawn sprinkler system.",
  "Bring in outdoor furniture that isn't weather-resistant.",
  "Keep wet floor signs handy, along with a doodlebug/spray to clean up dry salt.",
  "Talk to staff about winter safety and planning for more travel time.",
  "Service and tune up the snow blowers so they work properly. Make sure gasoline/oil is on hand and stored properly.",
  "Inspect the shuttle van tires to make sure they're in good condition and safe for winter.",
  "After the storm passes, inspect, document, and repair any damage to roofs, skylights, or overhangs. Notify emergency response teams of any injuries or deaths. Then restock supplies and maintain the equipment for the next storm. (After each storm.)",
  "Ice melt (at all building entrances)",
  "Shovels",
  "Car scrapers",
  "Flashlights",
  "Extra blankets",
  "Cans of deicer",
  "Dollar-store snug gloves for guests who forget theirs",
  "Portable car battery charger and/or a set of jumper cables",
  "Make sure snow removal agreements are in place and insurance documents are on file.",
  "Mark curbs and obstacles with flags.",
  "Post the snow removal company's number at the front desk, with a log to track when they remove snow and/or salt or sand the lot. (Ongoing log, every visit.)"
];

const gm = { role: "GM", hotel: "MSPAM", name: "GM Example", id: "gm-ex" };
const agm = { role: "AGM", hotel: "MSPAM", name: "AGM Example", id: "agm-ex" };
const mt = { role: "Maintenance", hotel: "MSPAM", name: "Maint Example", id: "mt-ex" };
const fd = { role: "Front Desk", hotel: "MSPAM", name: "Desk Example", id: "fd-ex" };
const other = { role: "GM", hotel: "MSPMS", name: "Other Example", id: "gm-2" };
const corp = { role: "Above Property", hotel: null, name: "Corporate Example", id: "corp-ex" };

function season2026() {
  const state = wn.blankState();
  wn.ensure(state, "2026-10-28");
  return state;
}

test("catalog is the 28 checklist lines, in section order, in both languages", () => {
  assert.equal(wn.ITEMS.length, 28);
  assert.deepEqual(wn.ITEMS.map((item) => item[2]), EN);
  wn.ITEMS.forEach((item, i) => {
    assert.equal(item[0], i + 1);
    assert.equal(typeof item[3], "string");
    assert.ok(item[3].trim().length > 0);
  });
  assert.deepEqual(wn.ITEMS.filter((item) => item[1] === 1).map((item) => item[0]), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]);
  assert.deepEqual(wn.ITEMS.filter((item) => item[1] === 2).map((item) => item[0]), [15, 16]);
  assert.deepEqual(wn.ITEMS.filter((item) => item[1] === 3).map((item) => item[0]), [17]);
  assert.deepEqual(wn.ITEMS.filter((item) => item[1] === 4).map((item) => item[0]), [18, 19, 20, 21, 22, 23, 24, 25]);
  assert.deepEqual(wn.ITEMS.filter((item) => item[1] === 5).map((item) => item[0]), [26, 27, 28]);
  assert.equal(wn.itemByNo(3)[4], "cold");
  assert.equal(wn.itemByNo(7)[4], "ooo");
  assert.equal(wn.itemByNo(17)[4], "storm");
  assert.equal(wn.itemByNo(28)[4], "snow");
  assert.ok(wn.ITEMS.filter((item) => !item[4]).length === 24);
  assert.ok(wn.CLOSING[0].includes("Emergency access roads"));
  assert.ok(wn.CLOSING[1].length > 20);
});

test("2026 is assigned on Oct 15 with the hotel due dates, and not before", () => {
  const early = wn.blankState();
  wn.ensure(early, "2026-10-14");
  assert.equal(wn.activeYear(early, "2026-10-14"), 0);
  assert.equal(wn.season(early, 2026, "MSPAM"), null);

  const state = season2026();
  assert.equal(state.years["2026"].assignOn, "2026-10-15");
  assert.equal(wn.season(state, 2026, "MSPAM").dueOn, "2026-11-04");
  assert.equal(wn.season(state, 2026, "MSPAM").optional, false);
  assert.equal(wn.season(state, 2026, "MSPMS").dueOn, "2026-11-05");
  assert.equal(wn.season(state, 2026, "MSPWE").dueOn, "2026-11-06");
  assert.equal(wn.season(state, 2026, "MSPWE").optional, true);
  assert.equal(wn.counts(wn.season(state, 2026, "MSPAM")).pct, 0);
});

test("2026 due dates stay put when the yearly default changes", () => {
  const state = wn.blankState();
  assert.equal(wn.setDefaults(state, { assignMonth: 10, assignDay: 1, dueMonth: 11, dueDay: 20 }, corp).ok, true);
  wn.ensure(state, "2026-10-28");
  assert.equal(wn.season(state, 2026, "MSPAM").dueOn, "2026-11-04");
  assert.equal(wn.season(state, 2026, "MSPMS").dueOn, "2026-11-05");
  assert.equal(wn.season(state, 2026, "MSPWE").dueOn, "2026-11-06");
  assert.equal(state.years["2026"].assignOn, "2026-10-01");
});

test("a later year is a fresh copy and the previous year becomes history", () => {
  const state = season2026();
  const now = "2026-10-28T15:00:00.000Z";
  assert.equal(wn.setStatus(state, 2026, "MSPAM", 1, "done", "", gm, now, "2026-10-28").ok, true);
  wn.ensure(state, "2027-10-20");
  assert.equal(wn.isHistory(state, 2026, "2027-10-20"), true);
  assert.equal(wn.season(state, 2027, "MSPAM").items[1].status, "open");
  assert.equal(wn.season(state, 2026, "MSPAM").items[1].status, "done");
  assert.equal(wn.season(state, 2027, "MSPAM").dueOn, "2027-11-05");
  assert.equal(wn.season(state, 2027, "MSPMS").dueOn, "2027-11-05");
  assert.equal(wn.season(state, 2027, "MSPWE").dueOn, "2027-11-05");
  assert.equal(wn.season(state, 2027, "MSPWE").optional, false);
  assert.equal(wn.setStatus(state, 2026, "MSPAM", 2, "done", "", gm, now, "2027-10-20").error, "history");
  assert.equal(wn.setDates(state, 2026, {
    assignOn: "2026-10-15",
    hotels: { MSPAM: { dueOn: "2026-11-04" }, MSPMS: { dueOn: "2026-11-05" }, MSPWE: { dueOn: "2026-11-06", optional: true } }
  }, corp, "2027-10-20").error, "history");
});

test("GM, AGM, and maintenance check items; N/A needs a reason; completion is recorded", () => {
  const state = season2026();
  const today = "2026-10-28";
  const now = "2026-10-28T18:04:00.000Z";
  assert.equal(wn.setStatus(state, 2026, "MSPAM", 2, "done", "", fd, now, today).error, "role");
  assert.equal(wn.setStatus(state, 2026, "MSPAM", 2, "done", "", corp, now, today).error, "role");
  assert.equal(wn.setStatus(state, 2026, "MSPAM", 2, "done", "", other, now, today).error, "role");
  assert.equal(wn.setStatus(state, 2026, "MSPAM", 8, "na", "   ", mt, now, today).error, "reason");
  assert.equal(wn.setStatus(state, 2026, "MSPAM", 8, "na", "No fire pump at this hotel", mt, now, today).ok, true);
  const na = wn.season(state, 2026, "MSPAM").items[8];
  assert.equal(na.status, "na");
  assert.equal(na.reason, "No fire pump at this hotel");
  assert.equal(na.by, "Maint Example");
  assert.equal(na.at, now);
  assert.equal(wn.setStatus(state, 2026, "MSPAM", 2, "done", "", agm, now, today).ok, true);
  assert.equal(wn.season(state, 2026, "MSPAM").items[2].byId, "agm-ex");
  for (let n = 1; n <= 28; n++) {
    if (wn.season(state, 2026, "MSPAM").items[n].status === "open") {
      wn.setStatus(state, 2026, "MSPAM", n, "done", "", gm, now, today);
    }
  }
  assert.equal(wn.counts(wn.season(state, 2026, "MSPAM")).pct, 100);
  assert.equal(wn.isOverdue(wn.season(state, 2026, "MSPAM"), "2026-11-10"), false);
});

test("overdue ignores optional Golden Valley and a hotel that is not past its due date", () => {
  const state = season2026();
  const hampton = wn.season(state, 2026, "MSPAM");
  const spring = wn.season(state, 2026, "MSPMS");
  const valley = wn.season(state, 2026, "MSPWE");
  assert.equal(wn.isOverdue(hampton, "2026-11-04"), false);
  assert.equal(wn.isOverdue(hampton, "2026-11-05"), true);
  assert.equal(wn.isOverdue(spring, "2026-11-05"), false);
  assert.equal(wn.isOverdue(spring, "2026-11-06"), true);
  assert.equal(wn.isOverdue(valley, "2026-11-07"), false);
  assert.equal(wn.pastSuggested(valley, "2026-11-07"), true);
});

test("corporate can adjust this year's dates and the yearly defaults", () => {
  const state = season2026();
  const today = "2026-10-28";
  assert.equal(wn.setDates(state, 2026, {
    assignOn: "2026-10-20",
    hotels: {
      MSPAM: { dueOn: "2026-11-04", optional: false },
      MSPMS: { dueOn: "2026-11-08", optional: false },
      MSPWE: { dueOn: "2026-11-06", optional: true }
    }
  }, gm, today).error, "role");
  assert.equal(wn.setDates(state, 2026, {
    assignOn: "2026-11-01",
    hotels: {
      MSPAM: { dueOn: "2026-10-15", optional: false },
      MSPMS: { dueOn: "2026-11-05", optional: false },
      MSPWE: { dueOn: "2026-11-06", optional: true }
    }
  }, corp, today).error, "date");
  assert.equal(wn.setDates(state, 2026, {
    assignOn: "2026-10-20",
    hotels: {
      MSPAM: { dueOn: "2026-11-04", optional: false },
      MSPMS: { dueOn: "2026-11-08", optional: false },
      MSPWE: { dueOn: "2026-11-10", optional: false }
    }
  }, corp, today).ok, true);
  assert.equal(state.years["2026"].assignOn, "2026-10-20");
  assert.equal(wn.season(state, 2026, "MSPMS").dueOn, "2026-11-08");
  assert.equal(wn.season(state, 2026, "MSPWE").optional, false);
  assert.equal(wn.season(state, 2026, "MSPAM").items[1].status, "open");
});

test("recurring logs: daily cold spots, out-of-order rooms, storms, and the front-desk snow log", () => {
  const state = season2026();
  const today = "2026-10-28";
  const at = "2026-10-28T20:00:00.000Z";
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "cold", day: today, at, tempF: 40, area: "Laundry" }, mt, today).log.below, true);
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "cold", day: today, at, tempF: 41, area: "Stairwell" }, mt, today).log.below, false);
  assert.equal(wn.loggedOn(wn.season(state, 2026, "MSPAM"), "cold", today), true);
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "cold", day: today, at, tempF: "", area: "Kitchen" }, mt, today).error, "temp");
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "ooo", day: today, at, room: "214", heated: true }, gm, today).ok, true);
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "ooo", day: today, at, room: "" }, gm, today).error, "room");
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "storm", day: today, at, note: "" }, gm, today).error, "note");
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "storm", day: today, at, note: "Roof clear", notified: false }, gm, today).ok, true);
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "snow", day: today, at, snow: false, salt: false }, fd, today).error, "action");
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "snow", day: today, at, snow: true, salt: true, note: "Lot and walk" }, fd, today).ok, true);
  assert.equal(wn.addLog(state, 2026, "MSPAM", { kind: "cold", day: today, at, tempF: 50, area: "BOH" }, fd, today).error, "role");
  assert.equal(wn.addLog(state, 2026, "MSPMS", { kind: "snow", day: today, at, snow: true }, fd, today).error, "role");
  const snow = wn.logsOf(wn.season(state, 2026, "MSPAM"), "snow");
  assert.equal(snow.length, 1);
  assert.equal(snow[0].by, "Desk Example");
  assert.equal(snow[0].salt, true);
});

test("notes and photos stay on the item without marking it done", () => {
  const state = season2026();
  const today = "2026-10-28";
  const photo = "data:image/jpeg;base64,aaaa";
  assert.equal(wn.setMeta(state, 2026, "MSPAM", 19, { note: "By the side door", photo }, mt, today).ok, true);
  const item = wn.season(state, 2026, "MSPAM").items[19];
  assert.equal(item.status, "open");
  assert.equal(item.note, "By the side door");
  assert.equal(item.photo, photo);
  assert.equal(wn.setMeta(state, 2026, "MSPAM", 19, { photo: "javascript:alert(1)" }, mt, today).ok, true);
  assert.equal(wn.season(state, 2026, "MSPAM").items[19].photo, "");
  assert.equal(wn.setPhone(state, 2026, "MSPAM", "555-0100", gm, today).ok, true);
  assert.equal(wn.season(state, 2026, "MSPAM").snowPhone, "555-0100");
  assert.equal(wn.setPhone(state, 2026, "MSPAM", "555-0101", fd, today).error, "role");
});

test("migration is additive, locks search_path, and does not publish secrets", () => {
  const sql = fs.readFileSync(path.join(__dirname, "../supabase/migrations/20261028_winter_preparedness.sql"), "utf8");
  const js = fs.readFileSync(path.join(__dirname, "../winter.js"), "utf8");
  assert.match(sql, /enable row level security/i);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /revoke all on function public\.winter_ensure_year\(integer\) from public, anon/);
  assert.match(sql, /hq_can_see/);
  assert.match(sql, /hq_is_gm_agm/);
  assert.match(sql, /hq_is_corporate/);
  assert.doesNotMatch(sql, /drop table/i);
  assert.match(sql, /2026-11-04/);
  assert.match(sql, /2026-11-05/);
  assert.match(sql, /2026-11-06/);
  for (const file of [sql, js]) {
    assert.doesNotMatch(file, /Uselman|Bhakta|Relikor|5820|5,820|gm\.hampton|rbhakta|10dKtXnn/i);
  }
  assert.match(fs.readFileSync(path.join(__dirname, "../index.html"), "utf8"), /winter\.js/);
});
