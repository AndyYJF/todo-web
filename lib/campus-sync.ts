// 校园事务监控系统对接：
// - 增量拉取（updated_since）+ status=all 感知完成/取消
// - 本地勾选完成 → 回写上游（带 revision 版本校验，412 自动重试一次）
import { getDb, nowLocal } from "./db";
import { httpGetJson, httpRequest } from "./httpget";

const PROJECT = "校园事务";
const SYNC_INTERVAL_MS = 10 * 60 * 1000;

interface UpstreamFeed {
  generated_at?: string;
  tasks: UpstreamTask[];
}

interface UpstreamTask {
  task_id: string;
  revision: number;
  title: string;
  description: string;
  action_text?: string;
  category?: string;
  status: string; // open | completed | cancelled
  due_at: string | null;
  due_date: string | null;
  time_text?: string;
  updated_at: string;
  sources?: {
    group_alias: string;
    text?: string;
    media?: string[];
  }[];
}

function errMsg(e: unknown): string {
  if (!(e instanceof Error)) return `非Error异常: ${String(e)}`;
  const c = e.cause as Record<string, unknown> | undefined;
  const detail = c
    ? Object.entries(c)
        .filter(([, v]) => typeof v === "string" || typeof v === "number")
        .map(([k, v]) => `${k}=${v}`)
        .join(" ")
    : "";
  return `[sync-v4] ${e.name}: ${e.message}${detail ? ` [${detail}]` : ""}`;
}

/** 从 CAMPUS_API_URL 解析 base 与 token */
function conf(): { base: string; token: string } | null {
  const raw = process.env.CAMPUS_API_URL;
  if (!raw) return null;
  try {
    const u = new URL(raw);
    return {
      base: u.origin,
      token: u.searchParams.get("token") ?? "",
    };
  } catch {
    return null;
  }
}

/** ISO 时间 → Asia/Shanghai 本地 "YYYY-MM-DD HH:mm"（与库内格式一致） */
function toLocal(s: string): string | null {
  const d = new Date(s);
  if (isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")} ${get("hour")}:${get("minute")}`;
}

/** 今天 00:00（Asia/Shanghai），用于同步任务的起始时间 */
function todayStart(): string {
  const d = toLocal(new Date().toISOString());
  return d ? `${d.slice(0, 10)} 00:00` : nowLocal().slice(0, 10) + " 00:00";
}

/** 上游任务 → 本地 note / dueAt / startAt */
function mapTask(t: UpstreamTask, token: string) {
  // 截止时间：精确时间优先；只有日期 → 当天 23:59
  let dueAt: string | null = null;
  if (t.due_at) dueAt = toLocal(t.due_at);
  else if (t.due_date) dueAt = `${t.due_date} 23:59`;
  // 有截止日期的同步任务：开始时间按今天算
  const startAt = dueAt ? todayStart() : null;

  const parts: string[] = [];
  if (t.description?.trim()) parts.push(t.description.trim());
  if (t.action_text?.trim()) parts.push(`行动：${t.action_text.trim()}`);
  if (t.time_text?.trim()) parts.push(`原文时间：${t.time_text.trim()}`);
  const src = t.sources?.[0];
  if (src?.group_alias) parts.push(`来源：${src.group_alias}`);
  // 群消息原文（多来源去重，完整保留）
  const texts = [...new Set(
    (t.sources ?? []).map((s) => s.text?.trim()).filter((x): x is string => !!x)
  )];
  for (const text of texts) {
    parts.push(`—— 群消息原文 ——\n${text}`);
  }
  // 图片：/media 开头拼 base + token；http 直链直接用
  for (const s of t.sources ?? []) {
    for (const m of s.media ?? []) {
      const url = m.startsWith("http")
        ? m
        : `${conf()?.base ?? ""}${m}?token=${token}`;
      parts.push(`图片：${url}`);
    }
  }

  // 类别 → 优先级：考试/作业/报名默认高优先
  const highPri = ["exam", "assignment", "registration"].includes(
    t.category ?? ""
  );

  return {
    dueAt,
    startAt,
    note: parts.join("\n"),
    done: t.status === "open" ? 0 : 1,
    priority: highPri ? "high" : "normal",
  };
}

export interface SyncResult {
  added: number;
  updated: number;
  completed: number;
  total: number;
  incremental: boolean;
  error?: string;
}

interface CampusSyncState {
  lastResult: (SyncResult & { at: string }) | null;
  lastUpstreamAt: string | null;
  started: boolean;
  pull?: Promise<SyncResult>;
  retries?: Promise<void>;
  writes: Map<number, Promise<void>>;
}

const globalForSync = globalThis as unknown as { __campusSyncState?: CampusSyncState };
const syncState: CampusSyncState = (globalForSync.__campusSyncState ??= {
  lastResult: null,
  lastUpstreamAt: null,
  started: false,
  writes: new Map(),
});

export function lastSyncResult() {
  return syncState.lastResult;
}

export function syncCampusTasks(): Promise<SyncResult> {
  if (conf()) void retryCampusWritebacks();
  return (syncState.pull ??= pullCampusTasks().finally(() => {
    syncState.pull = undefined;
  }));
}

async function pullCampusTasks(): Promise<SyncResult> {
  const c = conf();
  const result: SyncResult = {
    added: 0,
    updated: 0,
    completed: 0,
    total: 0,
    incremental: !!syncState.lastUpstreamAt,
  };
  if (!c) {
    result.error = "未配置 CAMPUS_API_URL";
    syncState.lastResult = { ...result, at: nowLocal() };
    return result;
  }

  // 上游网络不稳定：拉取重试最多 3 次
  let data: UpstreamFeed | null = null;
  let lastErr: unknown = null;
  for (let attempt = 0; attempt < 3 && !data; attempt++) {
    try {
      const params = new URLSearchParams({ token: c.token, status: "all" });
      if (syncState.lastUpstreamAt) params.set("updated_since", syncState.lastUpstreamAt);
      const response = await httpGetJson<UpstreamFeed>(
        `${c.base}/api/todo/v1/tasks?${params}`, 20000
      );
      if (!Array.isArray(response.tasks)) throw new Error("Campus 返回的任务列表无效");
      data = response;
    } catch (e) {
      lastErr = e;
      console.error(`[campus] 拉取失败(第${attempt + 1}次):`, errMsg(e));
      await new Promise((r) => setTimeout(r, 1500));
    }
  }
  if (!data) {
    result.error = errMsg(lastErr);
    syncState.lastResult = { ...result, at: nowLocal() };
    return result;
  }

  try {
    const upstream = data.tasks;
    result.total = upstream.length;

    if (!upstream.length) {
      if (data.generated_at) syncState.lastUpstreamAt = data.generated_at;
      syncState.lastResult = { ...result, at: nowLocal() };
      return result;
    }

    const db = getDb();
    const findByExt = db.prepare(
      "SELECT external_rev, done, campus_pending FROM tasks WHERE external_id = ?"
    );
    const insert = db.prepare(
      `INSERT INTO tasks (title, note, start_at, due_at, priority, project, external_id, external_rev, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    const update = db.prepare(
      `UPDATE tasks SET title = ?, note = ?, start_at = ?, due_at = ?, priority = ?, external_rev = ?,
        campus_remote_done = ?,
        done = CASE WHEN campus_pending IS NULL THEN ? ELSE done END,
        done_at = CASE
          WHEN campus_pending IS NOT NULL THEN done_at
          WHEN ? = 0 THEN NULL
          WHEN done = 0 THEN ?
          ELSE done_at END,
        updated_at = ?
       WHERE external_id = ?`
    );

    db.exec("BEGIN IMMEDIATE");
    try {
      for (const t of upstream) {
        if (!t.task_id || !t.title) continue;
        const m = mapTask(t, c.token);
        const existing = findByExt.get(t.task_id) as
          | { external_rev: number | null; done: number; campus_pending: string | null }
          | undefined;

        if (!existing) {
          if (m.done) continue; // 已完成/已取消的历史任务不导入
          insert.run(
            t.title, m.note, m.startAt, m.dueAt, m.priority, PROJECT,
            t.task_id, t.revision, nowLocal(), nowLocal()
          );
          result.added++;
        } else if ((existing.external_rev ?? -1) < t.revision) {
          update.run(
            t.title, m.note, m.startAt, m.dueAt, m.priority, t.revision,
            m.done, m.done, m.done, nowLocal(), nowLocal(), t.task_id
          );
          if (m.done && !existing.done && !existing.campus_pending) result.completed++;
          else result.updated++;
        }
      }
      db.exec("COMMIT");
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
    if (data.generated_at) syncState.lastUpstreamAt = data.generated_at;
  } catch (e) {
    result.error = errMsg(e);
  }

  syncState.lastResult = { ...result, at: nowLocal() };
  return result;
}

type PendingStatus = {
  externalId: string;
  revision: number | null;
  done: number;
  operationId: string;
};

type WritebackResult =
  | { revision: number }
  | { error: string; terminal?: boolean; withdrawn?: boolean }
  | { superseded: true };

function pendingStatus(id: number): PendingStatus | undefined {
  return getDb().prepare(
    `SELECT external_id AS externalId, external_rev AS revision, done,
            campus_pending AS operationId
     FROM tasks WHERE id = ? AND campus_pending IS NOT NULL`
  ).get(id) as PendingStatus | undefined;
}

async function sendCampusStatus(
  pending: PendingStatus,
  isCurrent: () => boolean,
): Promise<WritebackResult> {
  const campus = conf();
  if (!campus) return { error: "未配置校园同步" };
  const status = pending.done ? "completed" : "open";
  const url = `${campus.base}/api/todo/v1/tasks/${encodeURIComponent(pending.externalId)}/status`;
  const target = new URL(url);
  target.searchParams.set("token", campus.token);
  const send = (version: number) => httpRequest(target.toString(), {
    method: "POST",
    body: JSON.stringify({ status, version, operationId: pending.operationId }),
  });

  try {
    let response = await send(pending.revision ?? 0);
    if (response.status === 412) {
      const conflict = JSON.parse(response.body.toString("utf8"));
      if (!isCurrent()) return { superseded: true };
      if (Number.isInteger(conflict.current_revision)) {
        response = await send(conflict.current_revision);
      }
    }
    if (response.status === 404) return { error: "Campus 事项已不存在", terminal: true };
    if (response.status === 409) {
      return { error: "Campus 事项已撤回", terminal: true, withdrawn: true };
    }
    if (response.status < 200 || response.status >= 300) {
      return { error: `Campus 回写 HTTP ${response.status}` };
    }
    const { version } = JSON.parse(response.body.toString("utf8"));
    if (!Number.isInteger(version)) return { error: "Campus 回写响应缺少版本" };
    return { revision: version };
  } catch {
    return { error: "Campus 暂时无法确认状态回写" };
  }
}

async function writeLatestStatus(id: number): Promise<void> {
  const db = getDb();
  let pending = pendingStatus(id);
  while (pending) {
    const attempt = pending;
    const isCurrent = () => pendingStatus(id)?.operationId === attempt.operationId;
    const result = await sendCampusStatus(attempt, isCurrent);
    if ("revision" in result) {
      // A newer upstream revision may have arrived while the reply was in flight.
      db.prepare(
        `UPDATE tasks SET
           done = CASE WHEN external_rev > ? THEN COALESCE(campus_remote_done, done) ELSE done END,
           done_at = CASE WHEN external_rev > ? AND campus_remote_done = 0 THEN NULL
                          WHEN external_rev > ? AND campus_remote_done = 1 THEN COALESCE(done_at, ?)
                          ELSE done_at END,
           campus_remote_done = CASE WHEN external_rev > ? THEN campus_remote_done ELSE ? END,
           external_rev = MAX(COALESCE(external_rev, 0), ?),
           campus_pending = NULL, campus_writeback_error = NULL
         WHERE id = ? AND campus_pending = ?`
      ).run(
        result.revision, result.revision, result.revision, nowLocal(),
        result.revision, attempt.done, result.revision, id, attempt.operationId,
      );
    } else if ("error" in result && isCurrent()) {
      db.prepare(
        `UPDATE tasks SET campus_writeback_error = ?,
          campus_pending = CASE WHEN ? THEN NULL ELSE campus_pending END,
          done = CASE WHEN ? THEN 1 ELSE done END,
          done_at = CASE WHEN ? THEN COALESCE(done_at, ?) ELSE done_at END
         WHERE id = ? AND campus_pending = ?`
      ).run(
        result.error, Number(!!result.terminal), Number(!!result.withdrawn),
        Number(!!result.withdrawn), nowLocal(), id, attempt.operationId,
      );
      return;
    }
    pending = pendingStatus(id);
  }
}

export function flushCampusWriteback(id: number): Promise<void> {
  const active = syncState.writes.get(id);
  if (active) return active;
  const write = writeLatestStatus(id).finally(() => syncState.writes.delete(id));
  syncState.writes.set(id, write);
  return write;
}

function retryCampusWritebacks(): Promise<void> {
  return (syncState.retries ??= (async () => {
    const pending = getDb().prepare("SELECT id FROM tasks WHERE campus_pending IS NOT NULL")
      .all() as { id: number }[];
    for (const { id } of pending) await flushCampusWriteback(id);
  })().catch((error) => console.error("[campus] 处理待回写状态失败:", error)).finally(() => {
    syncState.retries = undefined;
  }));
}

export function campusWritebackStatus() {
  return getDb().prepare(
    `SELECT COUNT(CASE WHEN campus_pending IS NOT NULL THEN 1 END) AS pending,
            COUNT(campus_writeback_error) AS failed
     FROM tasks`
  ).get();
}

/** 服务启动时调用：立即同步一次，之后每 10 分钟同步 */
export function startCampusSyncLoop() {
  if (!process.env.CAMPUS_API_URL) return;
  if (syncState.started) return;
  syncState.started = true;
  syncCampusTasks().catch(() => {});
  setInterval(() => syncCampusTasks().catch(() => {}), SYNC_INTERVAL_MS).unref();
}
