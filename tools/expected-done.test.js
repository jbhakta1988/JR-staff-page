const test = require("node:test");
const assert = require("node:assert/strict");
const done = require("../expected-done.js");

const standards = { checkout: 30, stayover: 20, other: 25, breakMin: 30 };

test("a housekeeper finishes at start plus remaining rooms and the break", () => {
  const result = done.project({
    role: "Housekeeper",
    startMin: 8 * 60,
    endMin: 16 * 60,
    standards: standards,
    rooms: [{ kind: "checkout" }, { kind: "checkout" }, { kind: "stayover" }]
  });
  assert.equal(result.ok, true);
  assert.equal(result.finish, 8 * 60 + 60 + 20 + 30);
  assert.equal(done.formatClock(result.finish), "9:50 AM");
  assert.equal(done.phrase(result.finish, "en"), "Expected done by 9:50 AM");
  assert.equal(done.phrase(result.finish, "es"), "Termina a las 9:50 AM");
  assert.equal(result.flag, "ok");
});

test("cleaned and refused rooms drop out and the finish moves earlier", () => {
  const rooms = [
    { hk: "Rosa", flow: "dirty", s: "VD" },
    { hk: "Rosa", flow: "cleaned", s: "RFI", t1: "10:00 AM" },
    { hk: "Rosa", flow: "dirty", s: "OD", occ: true, x: "DND" },
    { hk: "Ana", flow: "dirty", s: "VD" }
  ];
  assert.deepEqual(done.remainingRooms(rooms, "Rosa"), [{ kind: "checkout" }]);
  const open = done.project({ role: "Housekeeper", startMin: 8 * 60, endMin: 16 * 60, standards: standards, rooms: done.remainingRooms(rooms, "Rosa") });
  const after = done.project({ role: "Housekeeper", startMin: 8 * 60, endMin: 16 * 60, standards: standards, rooms: [] });
  assert.equal(open.finish, 9 * 60);
  assert.equal(after.finish, 8 * 60 + 30);
  assert.ok(after.finish < open.finish);
});

test("missing room or break standards stay blank", () => {
  const noCheckout = done.project({
    role: "Housekeeper",
    startMin: 8 * 60,
    endMin: 16 * 60,
    standards: { checkout: null, stayover: 20, breakMin: 30 },
    rooms: [{ kind: "checkout" }]
  });
  assert.equal(noCheckout.ok, false);
  assert.equal(done.hint("en"), "Set labor standards");
  assert.match(done.hint("es"), /estándares/);
  const noBreak = done.project({
    role: "Housekeeper",
    startMin: 8 * 60,
    standards: { checkout: 30, stayover: 20, breakMin: null },
    rooms: []
  });
  assert.equal(noBreak.ok, false);
});

test("laundry uses planned hours and does not add a break", () => {
  const result = done.project({
    role: "Laundry Attendant",
    startMin: 7 * 60,
    endMin: 15 * 60,
    plannedHours: 8,
    standards: standards
  });
  assert.equal(result.finish, 15 * 60);
  assert.equal(done.formatClock(result.finish), "3:00 PM");
  assert.equal(result.flag, "ok");
  const missing = done.project({ role: "Laundry Attendant", startMin: 7 * 60, endMin: 15 * 60, plannedHours: null });
  assert.equal(missing.ok, false);
});

test("running behind is amber past the scheduled end and red after 30 minutes", () => {
  const amber = done.project({ role: "Laundry Attendant", startMin: 7 * 60, endMin: 15 * 60, plannedHours: 8.5 });
  const red = done.project({ role: "Laundry Attendant", startMin: 7 * 60, endMin: 15 * 60, plannedHours: 9 });
  const edge = done.project({ role: "Laundry Attendant", startMin: 7 * 60, endMin: 15 * 60, plannedHours: 8 });
  assert.equal(amber.flag, "amber");
  assert.equal(red.flag, "red");
  assert.equal(edge.flag, "ok");
  assert.equal(done.flagLabel("amber", "en"), "Running behind");
  assert.equal(done.flagLabel("red", "es"), "Atrasado");
  assert.equal(done.flagLabel("ok", "en"), "");
});

test("start comes from the schedule, then from the first activity", () => {
  const scheduled = done.pickShift([{ start: 8 * 60, end: 16 * 60 }], 10 * 60);
  assert.equal(scheduled.start, 8 * 60);
  assert.equal(done.parseClock("7:05 AM"), 7 * 60 + 5);
  assert.equal(done.parseClock("15:00"), 15 * 60);
  const none = done.project({ role: "Housekeeper", startMin: null, standards: standards, rooms: [] });
  assert.equal(none.reason, "start");
});

test("houseperson is not part of expected done", () => {
  assert.equal(done.project({ role: "House Person", startMin: 8 * 60, plannedHours: 8, standards: standards }), null);
  assert.equal(done.ROLES["House Person"], undefined);
  assert.equal(done.TEAM.Housekeeping, 1);
  assert.equal(done.TEAM["House Person"], undefined);
});
