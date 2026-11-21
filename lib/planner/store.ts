import { createHash } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import { archiveBefore, businessDate, DAY_MS } from "./dates";
import {
  applyFields, ARCHIVE_LIMIT_BYTES, invalid, PlannerError, record, requireDate,
  requireId, requireVersion, type Course, type DayPayload,
} from "./domain";

type DayRow = { date: string; archived_at: number | null; payload: string; bytes: number };
type MetaRow = { revision: number; timetable_revision: number; pruned_through: string | null };
type Receipt = { fingerprint: string; result: string };
type MutationResult = { revision: number; itemId: string; dates: string[]; itemVersion: number | null };

const initialized = new WeakSet<DatabaseSync>();
const MAX_DAY_BYTES = 1_000_000;
const MAX_PLAN_ITEMS = 100;
const RETRY_WINDOW = 7 * DAY_MS;

function stableJson(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(stableJson).join(",") + "]";
  const object = value as Record<string, unknown>;
  return "{" + Object.keys(object).sort().map((key) => JSON.stringify(key) + ":" + stableJson(object[key])).join(",") + "}";
}

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function initialize(db: DatabaseSync) {
  if (initialized.has(db)) return;
  db.exec(`
    PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS planner_meta (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      revision INTEGER NOT NULL DEFAULT 0,
      timetable_revision INTEGER NOT NULL DEFAULT 0,
      pruned_through TEXT
    );
    INSERT OR IGNORE INTO planner_meta(id) VALUES (1);
    CREATE TABLE IF NOT EXISTS planner_days (
      date TEXT PRIMARY KEY,
      payload TEXT NOT NULL CHECK (json_valid(payload)),
      bytes INTEGER GENERATED ALWAYS AS (length(CAST(payload AS BLOB))) STORED,
      archived_at INTEGER
    );
    CREATE INDEX IF NOT EXISTS planner_archive_date ON planner_days(date) WHERE archived_at IS NOT NULL;
    CREATE TABLE IF NOT EXISTS planner_courses (
      key TEXT PRIMARY KEY,
      date TEXT NOT NULL,
      payload TEXT NOT NULL CHECK (json_valid(payload))
    );
    CREATE INDEX IF NOT EXISTS planner_courses_date ON planner_courses(date);
    CREATE TABLE IF NOT EXISTS planner_settings (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      revision INTEGER NOT NULL DEFAULT 0,
      reminder_enabled INTEGER NOT NULL DEFAULT 0 CHECK (reminder_enabled IN (0, 1)),
      reminder_time TEXT NOT NULL DEFAULT '21:30'
    );
    INSERT OR IGNORE INTO planner_settings(id) VALUES (1);
    CREATE TABLE IF NOT EXISTS planner_receipts (
      id TEXT PRIMARY KEY,
      fingerprint TEXT NOT NULL,
      result TEXT NOT NULL,
      expires_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS planner_receipts_expires ON planner_receipts(expires_at);
  `);
  initialized.add(db);
}

export class PlannerStore {
  constructor(
    private readonly db: DatabaseSync,
    private readonly now: () => number = Date.now,
    private readonly quota = ARCHIVE_LIMIT_BYTES,
  ) { initialize(db); }

  private transaction<T>(work: (now: number, today: string) => T): T {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const now = this.now();
      const result = work(now, businessDate(now));
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  private row(date: string): DayRow | undefined {
    return this.db.prepare("SELECT * FROM planner_days WHERE date = ?").get(date) as DayRow | undefined;
  }

  private meta(): MetaRow {
    return this.db.prepare("SELECT revision, timetable_revision, pruned_through FROM planner_meta WHERE id=1").get() as MetaRow;
  }

  private bump(timetable = false): number {
    return (this.db.prepare(`UPDATE planner_meta SET revision = revision + 1,
      timetable_revision = timetable_revision + ? WHERE id=1 RETURNING revision`)
      .get(timetable ? 1 : 0) as { revision: number }).revision;
  }

  private archiveBytes(): number {
    return (this.db.prepare(`SELECT coalesce(sum(bytes), 0) AS bytes
      FROM planner_days WHERE archived_at IS NOT NULL`).get() as { bytes: number }).bytes;
  }

  private prune() {
    let bytes = this.archiveBytes();
    if (bytes <= this.quota) return;
    let through: string | undefined;
    const oldest = this.db.prepare("SELECT date, bytes FROM planner_days WHERE archived_at IS NOT NULL ORDER BY date LIMIT 128");
    const remove = this.db.prepare("DELETE FROM planner_days WHERE date = ? AND archived_at IS NOT NULL");
    while (bytes > this.quota) {
      const batch = oldest.all() as Array<{ date: string; bytes: number }>;
      if (!batch.length) throw new Error("Planner archive accounting mismatch");
      for (const entry of batch) {
        remove.run(entry.date);
        through = entry.date;
        bytes -= entry.bytes;
        if (bytes <= this.quota) break;
      }
    }
    this.db.prepare("UPDATE planner_meta SET pruned_through = max(coalesce(pruned_through, ''), ?) WHERE id=1").run(through!);
  }

  private maintain(now: number) {
    const archived = this.db.prepare("UPDATE planner_days SET archived_at = ? WHERE date < ? AND archived_at IS NULL")
      .run(now, archiveBefore(now)).changes;
    if (archived) {
      this.prune();
      this.bump();
    }
    this.db.prepare("DELETE FROM planner_receipts WHERE expires_at <= ?").run(now);
  }

  sweep() {
    this.transaction((now) => this.maintain(now));
  }

  private courses(date: string): Course[] {
    const rows = this.db.prepare("SELECT payload FROM planner_courses WHERE date = ?").all(date) as Array<{ payload: string }>;
    return rows.map((row) => JSON.parse(row.payload) as Course)
      .sort((a, b) => a.startsAt.localeCompare(b.startsAt) || a.key.localeCompare(b.key));
  }

  private payload(row: DayRow | undefined, date: string): DayPayload {
    return row ? JSON.parse(row.payload) as DayPayload : { items: [], courses: this.courses(date) };
  }

  private save(date: string, payload: DayPayload) {
    if (payload.items.length > MAX_PLAN_ITEMS) invalid("每天最多保存 100 项工作");
    const json = JSON.stringify(payload);
    if (Buffer.byteLength(json) > MAX_DAY_BYTES) invalid("当天计划内容超过大小限制");
    this.db.prepare(`INSERT INTO planner_days(date, payload) VALUES (?, ?)
      ON CONFLICT(date) DO UPDATE SET payload = excluded.payload`).run(date, json);
  }

  day(date: string) {
    const result = this.transaction((now, today) => {
      this.maintain(now);
      const row = this.row(date);
      const meta = this.meta();
      if (!row && meta.pruned_through && date <= meta.pruned_through) {
        return new PlannerError(410, "history_pruned", "该日期已超出保留的历史范围");
      }
      const openFrom = archiveBefore(now);
      const day = !row && date < openFrom ? { items: [], courses: [] } : this.payload(row, date);
      return { date, today, openFrom, serverTime: now, archived: row?.archived_at != null, revision: meta.revision,
        timetableRevision: meta.timetable_revision, ...day };
    });
    if (result instanceof PlannerError) throw result;
    return result;
  }

  history(before: string | null, limit: number) {
    return this.transaction((now, today) => {
      this.maintain(now);
      const rows = this.db.prepare(`SELECT date, archived_at AS archivedAt,
          json_array_length(payload, '$.items') AS itemCount,
          (SELECT count(*) FROM json_each(payload, '$.items') WHERE json_extract(value, '$.status') = 'done') AS doneCount
        FROM planner_days WHERE archived_at IS NOT NULL AND date < ? ORDER BY date DESC LIMIT ?`)
        .all(before ?? today, limit + 1) as Array<{ date: string }>;
      const items = rows.slice(0, limit);
      return { items, nextBefore: rows.length > limit ? items.at(-1)?.date : null,
        bytes: this.archiveBytes(), limitBytes: this.quota, revision: this.meta().revision,
        earliestDate: (this.db.prepare("SELECT min(date) AS date FROM planner_days WHERE archived_at IS NOT NULL")
          .get() as { date: string | null }).date };
    });
  }

  private idempotent<T>(id: string, input: unknown, now: number, issuedAt: number, work: () => T): T {
    if (issuedAt > now + 5 * 60_000 || issuedAt <= now - RETRY_WINDOW) {
      throw new PlannerError(409, "operation_expired", "此操作已超出重试期限，请刷新后重新提交");
    }
    const fingerprint = sha256(stableJson(input));
    const receipt = this.db.prepare("SELECT fingerprint, result FROM planner_receipts WHERE id=?").get(id) as Receipt | undefined;
    if (receipt) {
      if (receipt.fingerprint !== fingerprint) throw new PlannerError(409, "operation_conflict", "此操作 ID 已用于其他内容");
      return JSON.parse(receipt.result) as T;
    }
    const result = work();
    this.db.prepare("INSERT INTO planner_receipts VALUES (?, ?, ?, ?)").run(id, fingerprint, JSON.stringify(result), issuedAt + RETRY_WINDOW);
    return result;
  }

  mutate(input: unknown): MutationResult {
    const body = record(input);
    const operationId = requireId(body.operationId);
    const issuedAt = requireVersion(body.issuedAt);
    for (const [key, value] of Object.entries(body)) {
      const values = key === "fields" ? Object.values(record(value)) : [value];
      if (values.some((field) => field !== null && typeof field === "object")) invalid("规划字段必须是简单值");
    }
    const date = requireDate(body.date);
    const action = body.action;
    if (action !== "create" && action !== "edit" && action !== "delete" && action !== "move") invalid("未知规划操作");
    return this.transaction((now) => {
      this.maintain(now);
      const openFrom = archiveBefore(now);
      return this.idempotent(operationId, { endpoint: "item", body }, now, issuedAt, () => {
        const row = this.row(date);
        if ((date < openFrom || row?.archived_at != null) && (!row || action !== "edit" || body.correctHistory !== true)) {
          throw new PlannerError(row ? 409 : 410, "history_read_only", "旧日期只允许主动补记仍保留的档案");
        }
        const day = this.payload(row, date);
        if (action === "create") {
          if (day.items.some((item) => item.id === operationId)) {
            throw new PlannerError(409, "operation_conflict", "此条目已存在");
          }
          const item = applyFields({ id: operationId, version: 1, title: "", startTime: null,
            endTime: null, status: "pending", note: "", todoId: null }, body.fields);
          if (!item.title) invalid("标题必填");
          if (item.todoId && !this.db.prepare("SELECT 1 FROM tasks WHERE id = ?").get(item.todoId)) invalid("关联的待办不存在");
          day.items.push(item);
          this.save(date, day);
          return { revision: this.bump(), itemId: item.id, dates: [date], itemVersion: item.version };
        }
        const id = requireId(body.itemId);
        const baseVersion = requireVersion(body.baseVersion);
        const item = day.items.find((entry) => entry.id === id);
        if (!item) throw new PlannerError(409, "item_missing", "条目已移动或删除");
        if (item.version !== baseVersion) throw new PlannerError(409, "item_conflict", "条目已在另一端修改", item);
        let itemVersion: number | null = null;
        const dates = [date];
        if (action === "edit") {
          const updated = applyFields(item, body.fields);
          if (updated.todoId !== item.todoId && updated.todoId &&
              !this.db.prepare("SELECT 1 FROM tasks WHERE id=?").get(updated.todoId)) invalid("关联的待办不存在");
          itemVersion = ++updated.version;
          day.items = day.items.map((entry) => entry.id === id ? updated : entry);
        } else {
          day.items = day.items.filter((entry) => entry.id !== id);
          if (action === "move") {
            const target = requireDate(body.targetDate);
            if (target === date || target < openFrom) invalid("只能移动到另一未归档日期");
            const targetRow = this.row(target);
            if (targetRow?.archived_at != null) invalid("不能移动到已归档日期");
            const destination = this.payload(targetRow, target);
            if (destination.items.some((entry) => entry.id === id)) throw new PlannerError(409, "item_conflict", "目标日期已存在条目");
            itemVersion = item.version + 1;
            const moved = body.fields === undefined ? item : applyFields(item, body.fields);
            if (moved.todoId !== item.todoId) invalid("移动时请保留关联待办");
            destination.items.push({ ...moved, version: itemVersion });
            this.save(target, destination);
            dates.push(target);
          }
        }
        this.save(date, day);
        if (row?.archived_at != null) this.prune();
        return { revision: this.bump(), itemId: id, dates, itemVersion };
      });
    });
  }

  settings() {
    const row = this.db.prepare("SELECT revision, reminder_enabled, reminder_time FROM planner_settings WHERE id=1")
      .get() as { revision: number; reminder_enabled: number; reminder_time: string };
    return { revision: row.revision, enabled: row.reminder_enabled === 1,
      time: row.reminder_time, timeZone: "Asia/Shanghai", serverTime: this.now() };
  }

  saveSettings(input: unknown) {
    const body = record(input);
    const operationId = requireId(body.operationId);
    const issuedAt = requireVersion(body.issuedAt);
    const baseVersion = requireVersion(body.baseVersion, 0);
    const { enabled, time } = body;
    if (typeof enabled !== "boolean" || typeof time !== "string" || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(time)) {
      invalid("提醒开关或提醒时间无效");
    }
    return this.transaction((now) => {
      this.maintain(now);
      return this.idempotent(operationId, { endpoint: "settings", issuedAt, baseVersion, enabled, time }, now, issuedAt, () => {
        const current = this.settings();
        if (baseVersion !== current.revision) {
          throw new PlannerError(409, "settings_conflict", "提醒设置已在另一端更新", current);
        }
        this.db.prepare("UPDATE planner_settings SET reminder_enabled=?, reminder_time=?, revision=revision+1 WHERE id=1")
          .run(enabled ? 1 : 0, time);
        return this.settings();
      });
    });
  }

  private importDiff(courses: Course[], effectiveFrom: string) {
    const from = courses[0].date;
    const through = courses.at(-1)!.date;
    const rows = this.db.prepare("SELECT key, payload FROM planner_courses WHERE date BETWEEN ? AND ?")
      .all(from < effectiveFrom ? effectiveFrom : from, through) as Array<{ key: string; payload: string }>;
    const previous = new Map(rows.map((entry) => [entry.key, entry.payload]));
    let added = 0, updated = 0;
    for (const course of courses) {
      if (course.date < effectiveFrom) continue;
      if (!previous.has(course.key)) added++;
      else if (previous.get(course.key) !== JSON.stringify(course)) updated++;
      previous.delete(course.key);
    }
    return { from, through, effectiveFrom, added, updated, removed: previous.size };
  }

  previewImport(courses: Course[], checksum: string) {
    return this.transaction((now, today) => {
      this.maintain(now);
      return { checksum, serverTime: now, baseVersion: this.meta().timetable_revision,
        ...this.importDiff(courses, today), count: courses.length,
        sample: courses.filter((course) => course.date >= today).slice(0, 12) };
    });
  }

  commitImport(courses: Course[], checksum: string, previewDay: string, baseVersion: number, operationId: string, issuedAt: number) {
    return this.transaction((now, today) => {
      this.maintain(now);
      return this.idempotent(operationId, { endpoint: "import", checksum, previewDay, baseVersion, issuedAt }, now, issuedAt, () => {
        if (baseVersion !== this.meta().timetable_revision || previewDay !== today) {
          throw new PlannerError(409, "timetable_conflict", "课表版本或业务日期已变化，请重新预览");
        }
        const diff = this.importDiff(courses, today);
        if (diff.through < today) invalid("课表不包含今天或将来的课程");
        if (!diff.added && !diff.updated && !diff.removed) {
          const meta = this.meta();
          return { revision: meta.revision, timetableRevision: meta.timetable_revision, ...diff };
        }
        this.db.prepare("DELETE FROM planner_courses WHERE date BETWEEN ? AND ?")
          .run(diff.from < today ? today : diff.from, diff.through);
        const insert = this.db.prepare("INSERT INTO planner_courses VALUES (?, ?, ?)");
        for (const course of courses) if (course.date >= today) insert.run(course.key, course.date, JSON.stringify(course));
        // Updating the timetable and the stored course snapshots is one operation.
        const affected = this.db.prepare("SELECT * FROM planner_days WHERE date >= ? AND date BETWEEN ? AND ? AND archived_at IS NULL")
          .all(today, diff.from, diff.through) as DayRow[];
        for (const row of affected) this.save(row.date, { ...this.payload(row, row.date), courses: this.courses(row.date) });
        return { revision: this.bump(true), timetableRevision: baseVersion + 1, ...diff };
      });
    });
  }
}
