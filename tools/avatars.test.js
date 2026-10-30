const test = require("node:test");
const assert = require("node:assert/strict");
require("../icons.js");
const av = require("../avatars.js");

test("saved cartoon avatars map to a line icon or initials and keep the old record", () => {
  assert.deepEqual(av.mapChoice(null), { icon: "initials", accent: "slate" });
  assert.deepEqual(av.mapChoice({ style: "avataaars", seed: "me", role: "", pin: "" }).icon, "initials");
  assert.equal(av.mapChoice({ style: "lorelei", role: "fd", pin: "" }).icon, "bell");
  assert.equal(av.mapChoice({ style: "micah", role: "mt", pin: "heart" }).icon, "heart");
  assert.equal(av.mapChoice({ style: "bottts", role: "", pin: "" }).icon, "wrench");
  assert.deepEqual(av.mapChoice({ v: 2, icon: "bed", accent: "teal" }), { icon: "bed", accent: "teal" });
  assert.equal(av.mapChoice({ v: 2, icon: "nope", accent: "blue" }).icon, "initials");
  assert.equal(av.OPTIONS.length, 16);
  assert.equal(av.OPTIONS[0].id, "initials");
  assert.equal(av.initialsOf("Rosa Vega"), "RV");
  assert.match(av.badgeHtml({ icon: "key", accent: "amber" }, "Kim", 36), /stroke-width="2"/);
  assert.match(av.badgeHtml({ icon: "initials", accent: "slate" }, "Kim Nguyen", 36), /KN/);
});
