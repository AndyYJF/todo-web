// 校园事务监控系统对接：
// - 增量拉取（updated_since）+ status=all 感知完成/取消
// - 本地勾选完成 → 回写上游（带 revision 版本校验，412 自动重试一次）
import { getDb, nowLocal } from "./db";
import { httpGetJson, httpRequest } from "./httpget";

const PROJECT = "校园事务";
const SYNC_INTERVAL_MS = 10 * 60 * 1000;

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
}

const globalForSync = globalThis as unknown as { __campusSyncState?: CampusSyncState };
const syncState = (globalForSync.__campusSyncState ??= {
  lastResult: null,
  lastUpstreamAt: null,
  started: false,
});

export function lastSyncResult() {
  return syncState.lastResult;
}

export async function syncCampusTasks(): Promise<SyncResult> {
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
  let data: { generated_at?: string; tasks?: UpstreamTask[] } | null = null;
  let lastErr: unknown = null;
  for (let attempt = 0; attempt < 3 && !data; attempt++) {
    try {
      const params = new URLSearchParams({ token: c.token, status: "all" });
      if (syncState.lastUpstreamAt) params.set("updated_since", syncState.lastUpstreamAt);
      data = await httpGetJson(`${c.base}/api/todo/v1/tasks?${params}`, 20000);
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
    const upstream = data.tasks ?? [];
    result.total = upstream.length;
    if (data.generated_at) syncState.lastUpstreamAt = data.generated_at;

    if (!upstream.length) {
      syncState.lastResult = { ...result, at: nowLocal() };
      return result;
    }

    const db = getDb();
    const findByExt = db.prepare(
      "SELECT id, external_rev, done FROM tasks WHERE external_id = ?"
    );
    const insert = db.prepare(
      `INSERT INTO tasks (title, note, start_at, due_at, priority, project, external_id, external_rev, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    const update = db.prepare(
      `UPDATE tasks SET title = ?, note = ?, start_at = ?, due_at = ?, priority = ?, external_rev = ?,
        done = ?, done_at = CASE WHEN ? = 1 AND done = 0 THEN ? ELSE done_at END,
        updated_at = ?
       WHERE external_id = ?`
    );

    for (const t of upstream) {
      if (!t.task_id || !t.title) continue;
      const m = mapTask(t, c.token);
      const existing = findByExt.get(t.task_id) as
        | { id: number; external_rev: number | null; done: number }
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
          m.done, m.done, nowLocal(), nowLocal(), t.task_id
        );
        if (m.done && !existing.done) result.completed++;
        else result.updated++;
      }
    }
  } catch (e) {
    result.error = errMsg(e);
  }

  syncState.lastResult = { ...result, at: nowLocal() };
  return result;
}

/**
 * 回写上游状态（本地勾选完成/取消完成时调用）。
 * 带 revision 版本校验；412（版本过旧）→ 用 current_revision 重试一次。
 * 失败不抛异常（本地状态已生效，下次全量同步会校准）。
 */
export async function writebackStatus(
  taskId: string,
  revision: number | null,
  done: boolean
): Promise<{ ok: boolean; newRev?: number }> {
  const c = conf();
  if (!c) return { ok: false };
  const status = done ? "completed" : "open";

  async function attempt(version: number | null): Promise<{ status: number; json: () => unknown }> {
    // 上游网络不稳定：每次调用最多重试 3 次
    for (let i = 0; i < 3; i++) {
      try {
        const r = await httpRequest(
          `${c!.base}/api/todo/v1/tasks/${taskId}/status?token=${c!.token}`,
          {
            method: "POST",
            body: JSON.stringify(
              version !== null ? { status, version } : { status }
            ),
            timeoutMs: 20000,
          }
        );
        return {
          status: r.status,
          json: () => JSON.parse(r.body.toString("utf8")),
        };
      } catch (e) {
        if (i === 2) throw e;
        await new Promise((r) => setTimeout(r, 1500));
      }
    }
    throw new Error("unreachable");
  }

  function parseJson(fn: () => unknown): Record<string, unknown> | null {
    try {
      return fn() as Record<string, unknown>;
    } catch {
      return null;
    }
  }

  try {
    let res = await attempt(revision);
    if (res.status === 412) {
      const d = parseJson(res.json) as { current_revision?: number } | null;
      if (d?.current_revision !== undefined) {
        res = await attempt(d.current_revision);
      }
    }
    if (res.status < 200 || res.status >= 300) return { ok: false };
    const d = parseJson(res.json) as { version?: number } | null;
    // 更新本地 revision，避免下次同步误判
    if (d?.version !== undefined) {
      getDb()
        .prepare("UPDATE tasks SET external_rev = ? WHERE external_id = ?")
        .run(d.version, taskId);
    }
    return { ok: true, newRev: d?.version };
  } catch (e) {
    console.error(`[campus] 回写失败 ${taskId} -> ${status}:`, e);
    return { ok: false };
  }
}

/** 服务启动时调用：立即同步一次，之后每 10 分钟同步 */
export function startCampusSyncLoop() {
  if (!process.env.CAMPUS_API_URL) return;
  if (syncState.started) return;
  syncState.started = true;
  syncCampusTasks().catch(() => {});
  setInterval(() => syncCampusTasks().catch(() => {}), SYNC_INTERVAL_MS).unref();
}
