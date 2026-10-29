const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const sl = require("../sales-leads.js");

const TODAY = "2026-10-29T16:00:00.000Z";
const sql = fs.readFileSync(path.join(__dirname, "../supabase/migrations/20261031_sales_leads.sql"), "utf8");
const fn = fs.readFileSync(path.join(__dirname, "../supabase/functions/sales-lead-email/index.ts"), "utf8");

test("front desk, AGM, GM, and corporate can file; managers can update", () => {
  ["Front Desk", "front_desk", "AGM", "agm", "GM", "gm", "Above Property", "JR Corporate", "above_property"].forEach((role) => {
    assert.equal(sl.canCapture(role), true, role);
  });
  ["Sales Manager", "sales_manager", "Housekeeping", "Housekeeper", "Maintenance", ""].forEach((role) => {
    assert.equal(sl.canCapture(role), false, role);
  });
  ["GM", "AGM", "JR Corporate", "Sales Manager", "sales_manager"].forEach((role) => {
    assert.equal(sl.canManage(role), true, role);
  });
  assert.equal(sl.canManage("Front Desk"), false);
  assert.equal(sl.canConfigure("GM"), true);
  assert.equal(sl.canConfigure("JR Corporate"), true);
  assert.equal(sl.canConfigure("AGM"), false);
  assert.equal(sl.canConfigure("Sales Manager"), false);
  assert.equal(sl.canConfigure("Front Desk"), false);
});

test("a lead needs a real name plus a phone or a valid email", () => {
  const base = { hotel: "MSPWE", first: "Alex", last: "Example", phone: "", email: "", needs: ["Local Negotiated Rate"], other: "", start: "", end: "", notes: "" };
  assert.equal(sl.validateLead(base).error, "contact");
  assert.equal(sl.validateLead(Object.assign({}, base, { last: "" })).error, "name");
  assert.equal(sl.validateLead(Object.assign({}, base, { phone: "555-12" })).error, "phone");
  assert.equal(sl.validateLead(Object.assign({}, base, { email: "alex@" })).error, "email");
  assert.equal(sl.validateLead(Object.assign({}, base, { phone: "(555) 010-0142", needs: [] })).error, "needs");
  assert.equal(sl.validateLead(Object.assign({}, base, { phone: "(555) 010-0142", needs: ["Other"], other: "" })).error, "other");
  assert.equal(sl.validateLead(Object.assign({}, base, { phone: "(555) 010-0142", start: "2026-11-10", end: "2026-11-01" })).error, "dates");
  const ok = sl.validateLead(Object.assign({}, base, { email: "Alex.Example@Example.Test", needs: ["Other", "Group Block"], other: "FAKE dinner" }));
  assert.equal(ok.ok, true);
  assert.equal(ok.value.contactEmail, "alex.example@example.test");
  assert.deepEqual(ok.value.needs, ["Other", "Group Block"]);
  assert.equal(sl.cleanEmails([" Sales.Demo@Example.Test ", "", "sales.demo@example.test"]).emails.length, 1);
  assert.equal(sl.cleanEmails(["not-an-email"]).ok, false);
});

test("the subject names the hotel and the contact", () => {
  assert.equal(sl.subjectLine("MSPWE", "Alex\n", " Example "), "New sales lead - MSPWE - Alex Example");
  assert.match(fn, /New sales lead - \$\{hotel\} - \$\{contact\}/);
  assert.match(fn, /Deno\.env\.get\("RESEND_API_KEY"\)/);
  assert.match(fn, /Deno\.env\.get\("SALES_LEAD_FROM"\)/);
  assert.match(fn, /&lt;/);
  assert.doesNotMatch(fn, /re_[A-Za-z0-9]{8,}/);
});

test("demo contacts are fake and this week's new count is one per hotel", () => {
  const demo = sl.buildDemo(TODAY);
  assert.equal(sl.weekStart("2026-10-29"), "2026-10-26");
  assert.equal(sl.chicagoDate("2026-10-29T03:30:00.000Z"), "2026-10-28");
  assert.equal(sl.countNewThisWeek(demo.leads, "MSPWE", TODAY), 1);
  assert.equal(sl.countNewThisWeek(demo.leads, "MSPAM", TODAY), 1);
  assert.equal(sl.countNewThisWeek(demo.leads, "MSPMS", TODAY), 1);
  assert.deepEqual(demo.routes, { MSPWE: [], MSPAM: [], MSPMS: [] });
  demo.leads.forEach((row) => {
    assert.equal(row.example, true);
    assert.match(row.notes, /FAKE/);
    if (row.contactEmail) assert.match(row.contactEmail, /@example\.test$/);
    if (row.contactPhone) assert.match(row.contactPhone, /555/);
    assert.equal(sl.telHref("(555) 010-0142"), "tel:+15550100142");
  });
  const lost = demo.leads.filter((row) => row.status === "Lost");
  assert.equal(sl.inThisWeek(lost[0].createdAt, TODAY), false);
});

test("the form is bilingual and asks to read the email back", () => {
  ["Sales Lead", "Read it back to the guest.", "Enter a phone number or an email.", "Email not sent", "New leads this week", "Local Negotiated Rate", "Group Block", "Meeting Space", "Other"].forEach((en) => {
    assert.notEqual(sl.label(en, "es"), en);
  });
  const html = sl.formHtml(
    { first: "", last: "", phone: "", email: "", needs: ["Other"], other: "", start: "", end: "", notes: "" },
    { lang: "es", hotelLabel: "MSPWE · HIE&S Golden Valley", staffName: "Jordan Lee", error: "contact", emailWarn: true, saving: false, corporate: false }
  );
  assert.match(html, /Léelo de nuevo al huésped/);
  assert.match(html, /Escribe un teléfono o un correo/);
  assert.match(html, /id="slProperty"/);
  assert.match(html, /Jordan Lee/);
  assert.match(html, /¿Qué más necesita/);
});

test("the migration is additive, private, and has no real addresses", () => {
  assert.match(sql, /hotel = any \(\(select private\.my_hotels\(\)\)::text\[\]\)/);
  assert.match(sql, /set search_path = ''/);
  assert.match(sql, /revoke all on function private\.sales_lead_can_capture\(\) from public, anon/);
  assert.match(sql, /revoke all on function public\.save_sales_lead\(text, text, text, text, text, text, text\[\], text, date, date, text\) from public, anon/);
  assert.match(sql, /grant execute on function public\.save_sales_lead\(text, text, text, text, text, text, text\[\], text, date, date, text\) to authenticated/);
  assert.match(sql, /status in \('New', 'Contacted', 'Won', 'Lost'\)/);
  assert.doesNotMatch(sql, /grant execute[\s\S]*to anon/);
  assert.doesNotMatch(sql, /drop table/i);
  assert.doesNotMatch(sql, /delete from/i);
  assert.doesNotMatch(sql, /truncate/i);
  assert.doesNotMatch(sql, /[a-z0-9._%+-]+@[a-z0-9.-]+\.(com|net|org|test|edu)/i);
  assert.doesNotMatch(sql, /gmail|yahoo|jrhospitality/i);
  const bodies = sql.split(/create or replace function/i).slice(1);
  assert.ok(bodies.length >= 8);
  bodies.forEach((body) => assert.match(body, /set search_path = ''/));
});

test("GM home count only includes New leads from this week", () => {
  const demo = sl.buildDemo(TODAY);
  const html = sl.homeCardHtml(demo, {
    hotel: "MSPWE",
    lang: "en",
    canCapture: true,
    canManage: true,
    viewRole: "GM",
    now: TODAY
  });
  assert.match(html, /id="slCapture"/);
  assert.match(html, /id="slWeek"/);
  assert.match(html, /<b>1<\/b>/);
  assert.match(html, /Fake contacts only/);
  const fd = sl.homeCardHtml(demo, { hotel: "MSPWE", lang: "en", canCapture: true, canManage: false, viewRole: "Front Desk", now: TODAY });
  assert.match(fd, /id="slCapture"/);
  assert.doesNotMatch(fd, /id="slWeek"/);
  const hk = sl.homeCardHtml(demo, { hotel: "MSPWE", lang: "en", canCapture: false, canManage: false, viewRole: "Housekeeping", now: TODAY });
  assert.equal(hk, "");
});
