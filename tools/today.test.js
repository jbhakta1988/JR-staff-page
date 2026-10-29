const test = require("node:test");
const assert = require("node:assert/strict");
const today = require("../today.js");

test("today sorts by urgency and keeps the top 5", () => {
  const items = today.buildItems({
    role: "Front Desk",
    me: "Kim",
    punches: [{ name: "Kim", issue: "in" }],
    rush: [{ room: 214, late: false }, { room: 101, late: true }],
    issues: [{ room: "305", days: 0 }],
    deep: 2,
    lost: 1,
    alerts: [{ en: "PTAC", es: "PTAC" }],
    cleans: { date: "2026-10-28" },
    events: ["Fundraiser"],
    sla: 1
  });
  assert.equal(items[0].en.indexOf("Clock in") === 0, true);
  assert.ok(items[1].en.indexOf("101") >= 0);
  assert.equal(today.take(items, false).length, 5);
  assert.equal(today.take(items, true).length, items.length);
  assert.ok(items.every(function (it, i) { return i === 0 || items[i - 1].rank <= it.rank; }));
});

test("a housekeeper does not see the front-desk lost-and-found pile", () => {
  const items = today.buildItems({
    role: "Housekeeper",
    me: "Maria",
    lost: 4,
    rush: [{ room: 118, hk: "Maria", late: true }, { room: 220, hk: "Rosa", late: true }],
    events: ["Ballroom"]
  });
  assert.equal(items.some(function (it) { return it.go === "lf"; }), false);
  assert.equal(items.some(function (it) { return it.go === "brief"; }), false);
  assert.equal(items.filter(function (it) { return it.go === "rushq"; }).length, 1);
});
