import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PlannerError, ARCHIVE_LIMIT_BYTES } from "../lib/planner/domain";
import { PlannerStore } from "../lib/planner/store";
import { DAY_MS } from "../lib/planner/dates";
import { parseCommunitySemesters, parseOfficialNotices, teachingWeek } from "../lib/planner/academic-calendar";

function errorCode(code: string) {
  return (error: unknown) => error instanceof PlannerError && error.code === code;
}

test("archive uses UTF-8 bytes, rotates whole days and rejects revival after restart", () => {
  const db = new DatabaseSync(":memory:");
  let clock = Date.parse("2026-11-21T15:59:59Z"); // UTC+8: 23:59:59
  const quota = 480;
  let store = new PlannerStore(db, () => clock, quota);
  const make = (date: string, note: string) => store.mutate({
    action: "create", date, operationId: randomUUID(), issuedAt: clock, fields: { title: "复盘", note },
  });
  const oldest = make("2026-11-21", "测".repeat(60));
  const recent = make("2026-11-22", "试".repeat(60));
  const future = make("2026-11-23", "新".repeat(60));

  assert.equal(store.history(null, 20).bytes, 0);
  clock += 1000;
  store.sweep();
  assert.equal(store.day("2026-11-21").archived, false, "midnight leaves yesterday open");
  clock += 4 * 60 * 60 * 1000 - 1;
  assert.equal(store.day("2026-11-21").archived, false, "03:59:59.999 is still editable");
  store.mutate({ action: "edit", date: "2026-11-21", operationId: randomUUID(), issuedAt: clock,
    itemId: oldest.itemId, baseVersion: 1, fields: { status: "done" } });
  clock += 1;
  store.sweep();
  assert.equal(store.day("2026-11-21").archived, true);
  assert.equal(store.day("2026-11-22").archived, false);
  const oldBytes = store.history(null, 20).bytes;
  assert.ok(oldBytes > 180);
  assert.ok(oldBytes < quota);
  const saved = db.prepare("SELECT payload FROM planner_days WHERE date=?").get("2026-11-21") as { payload: string };
  assert.equal(oldBytes, Buffer.byteLength(saved.payload));

  // A new store instance catches up at the following 04:00.
  clock += DAY_MS;
  store = new PlannerStore(db, () => clock, quota);
  assert.throws(() => store.day("2026-11-21"), errorCode("history_pruned"));
  assert.deepEqual(store.history(null, 20).items.map((item) => item.date), ["2026-11-22"]);
  assert.ok(store.history(null, 20).bytes <= quota);
  assert.equal(store.day("2026-11-23").items[0].id, future.itemId);
  assert.throws(() => store.mutate({ action: "edit", date: "2026-11-21", correctHistory: true,
    operationId: randomUUID(), issuedAt: clock, itemId: oldest.itemId, baseVersion: 1, fields: { status: "done" },
  }), errorCode("history_read_only"));

  store.mutate({ action: "edit", date: "2026-11-22", correctHistory: true, operationId: randomUUID(),
    issuedAt: clock, itemId: recent.itemId, baseVersion: 1, fields: { status: "done", note: "已补记" } });
  assert.equal(store.day("2026-11-22").items[0].note, "已补记");
  assert.equal(store.day("2026-11-22").items[0].status, "done");
  assert.throws(() => store.mutate({ action: "edit", date: "2026-11-22", correctHistory: true,
    operationId: randomUUID(), issuedAt: clock, itemId: recent.itemId, baseVersion: 1,
    fields: { note: "并发旧版本" },
  }), errorCode("item_conflict"));
  store.mutate({ action: "edit", date: "2026-11-22", correctHistory: true, operationId: randomUUID(),
    issuedAt: clock, itemId: recent.itemId, baseVersion: 2, fields: { note: "超".repeat(150) } });
  assert.equal(store.history(null, 20).bytes, 0, "growing an archived note applies the same quota");
  assert.equal(store.day("2026-11-23").archived, false);
  assert.equal(ARCHIVE_LIMIT_BYTES, 500_000_000);
  db.close();
});

test("cross-midnight import confirmation preserves the saved day's courses", () => {
  const db = new DatabaseSync(":memory:");
  let clock = Date.parse("2026-11-21T15:59:59Z");
  const store = new PlannerStore(db, () => clock);
  const original = { key: "course", date: "2026-11-21", title: "原课表", location: "",
    startsAt: "2026-11-21T08:00:00", endsAt: "2026-11-21T09:00:00", allDay: false };
  const operation = randomUUID();
  store.commitImport([original], "original", original.date, 0, operation, clock);
  store.mutate({ action: "create", date: original.date, operationId: randomUUID(), issuedAt: clock, fields: { title: "作业" } });
  const replacement = { ...original, title: "替换课表" };
  const preview = store.previewImport([replacement], "modified");

  clock += 1000;
  assert.throws(() => store.commitImport([replacement], "modified", preview.effectiveFrom,
    preview.baseVersion, randomUUID(), clock), errorCode("timetable_conflict"));
  assert.equal(store.day(original.date).archived, false);
  clock += 4 * 60 * 60 * 1000;
  const historical = store.day(original.date);
  assert.equal(historical.archived, true);
  assert.equal(historical.courses[0].title, "原课表");
  assert.equal(historical.items[0].title, "作业");

  // Retry of the previously acknowledged import is independent of the new business date.
  assert.equal(store.commitImport([original], "original", original.date, 0, operation, clock - 4 * 60 * 60 * 1000 - 1000).timetableRevision, 1);
  clock += 8 * DAY_MS;
  assert.throws(() => store.commitImport([original], "original", original.date, 0, operation,
    clock - 8 * DAY_MS - 4 * 60 * 60 * 1000 - 1000), errorCode("operation_expired"));
  db.close();
});

test("future calendar discovery accepts official articles and community week ranges", () => {
  const notices = parseOfficialNotices(`
    <a href="https://unrelated.example/info/1101/4.htm">2027-2028学年四川大学校历</a>
    <a href="info/1101/12345.htm" target="_blank">2027—2028学年四川大学校历</a>`);
  assert.deepEqual(notices, [{ year: "2027-2028", url: "https://jwc.scu.edu.cn/info/1101/12345.htm" }]);
  const semesters = parseCommunitySemesters({ semesters: [{ n: "2027-2028学年秋季学期", s: "2027-08-30", w: 20 }] });
  assert.equal(teachingWeek("2027-08-29", semesters)?.week, 1);
  assert.equal(teachingWeek("2027-09-05", semesters)?.week, 2);
  assert.equal(teachingWeek("2027-08-28", semesters), null);
  assert.throws(() => parseCommunitySemesters({ semesters: [] }));
});
